#!/usr/bin/env python3

import argparse
import copy
import json
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class RelayState:
    def __init__(self):
        self.lock = threading.Lock()
        self.generation = 0
        self.identity = None
        self.records = {}
        self.recoveries = {}

    @staticmethod
    def key(entity_type, record_id):
        return f"{entity_type}:{record_id}"

    @staticmethod
    def newer(candidate, current):
        if candidate["updatedAt"] != current["updatedAt"]:
            return candidate["updatedAt"] > current["updatedAt"]
        if bool(candidate.get("deletedAt")) != bool(current.get("deletedAt")):
            return bool(candidate.get("deletedAt"))
        return True

    def insert(self, record):
        key = self.key(record["entityType"], record["recordID"])
        current = self.records.get(key)
        if current is None or self.newer(record, current):
            self.records[key] = record

    def merge_snapshot(self, snapshot, identity):
        with self.lock:
            self.identity = identity
            source = snapshot["id"]
            captured_at = snapshot["capturedAt"]
            self.insert(
                {
                    "entityType": "library",
                    "recordID": "sync-metadata",
                    "payload": identity,
                    "updatedAt": captured_at,
                    "sourceDeviceID": source,
                }
            )
            settings = snapshot["searchSettings"]
            self.insert(
                {
                    "entityType": "searchSettings",
                    "recordID": "user-preferences",
                    "payload": settings,
                    "updatedAt": settings["updatedAt"],
                    "sourceDeviceID": source,
                }
            )
            library = snapshot["listSnapshot"]
            for entity_type, values in (
                ("cardList", library["lists"]),
                ("cardListCategory", library["categories"]),
                ("cardListEntry", library["entries"]),
            ):
                for value in values:
                    updated_at = value.get("updatedAt", value["createdAt"])
                    self.insert(
                        {
                            "entityType": entity_type,
                            "recordID": value["id"],
                            "payload": value,
                            "updatedAt": updated_at,
                            "sourceDeviceID": source,
                        }
                    )
            tombstones = list(snapshot.get("deletedEntities", []))
            tombstones.extend(
                {
                    "entityType": "cardList",
                    "recordID": deletion["id"],
                    "deletedAt": deletion["deletedAt"],
                }
                for deletion in snapshot.get("deletedLists", [])
            )
            for tombstone in tombstones:
                self.insert(
                    {
                        "entityType": tombstone["entityType"],
                        "recordID": tombstone["recordID"],
                        "payload": None,
                        "updatedAt": tombstone["deletedAt"],
                        "deletedAt": tombstone["deletedAt"],
                        "sourceDeviceID": source,
                    }
                )
            self.generation += 1
            return self.envelope_locked()

    def merge_recoveries(self, recoveries):
        with self.lock:
            for recovery in recoveries:
                current = self.recoveries.get(recovery["id"])
                if current is None or recovery["createdAt"] > current["createdAt"]:
                    self.recoveries[recovery["id"]] = recovery
            self.recoveries = {
                item["id"]: item for item in self.retained_recoveries()
            }
            self.generation += 1
            return self.envelope_locked()

    def retained_recoveries(self):
        values = sorted(
            self.recoveries.values(),
            key=lambda item: (item["createdAt"], item["id"]),
            reverse=True,
        )
        cutoff = datetime.now(timezone.utc) - timedelta(days=30)
        retained = []
        for index, value in enumerate(values):
            created_at = datetime.fromisoformat(value["createdAt"].replace("Z", "+00:00"))
            if index < 20 or created_at >= cutoff:
                retained.append(value)
        return retained

    def snapshot_locked(self):
        if not self.records:
            return None

        active = [
            record
            for record in self.records.values()
            if not record.get("deletedAt")
        ]
        lists = [
            copy.deepcopy(record["payload"])
            for record in active
            if record["entityType"] == "cardList"
        ]
        list_ids = {value["id"] for value in lists}
        categories = [
            copy.deepcopy(record["payload"])
            for record in active
            if record["entityType"] == "cardListCategory"
            and record["payload"]["listID"] in list_ids
        ]
        category_ids = {value["id"] for value in categories}
        entries = [
            copy.deepcopy(record["payload"])
            for record in active
            if record["entityType"] == "cardListEntry"
            and record["payload"]["listID"] in list_ids
            and (
                record["payload"].get("categoryID") is None
                or record["payload"]["categoryID"] in category_ids
            )
        ]
        settings_record = self.records.get("searchSettings:user-preferences")
        settings = (
            copy.deepcopy(settings_record["payload"])
            if settings_record and not settings_record.get("deletedAt")
            else {
                "defaultSearchText": "",
                "alwaysIncludedSearchText": "",
                "defaultSortModeRawValue": "releaseDate",
                "defaultSortDirectionRawValue": "ascending",
                "searchInputModeRawValue": "scryfall",
                "displayCurrencyRawValue": "USD",
                "searchHistory": [],
                "plainTextSearchHistory": [],
                "updatedAt": "0001-01-01T00:00:00Z",
            }
        )
        identity_record = self.records.get("library:sync-metadata")
        identity = (
            copy.deepcopy(identity_record["payload"])
            if identity_record and not identity_record.get("deletedAt")
            else self.identity
        )
        tombstones = [
            {
                "id": f"relay-{record['entityType']}-{record['recordID']}",
                "entityType": record["entityType"],
                "recordID": record["recordID"],
                "deletedAt": record["deletedAt"],
            }
            for record in self.records.values()
            if record.get("deletedAt")
            and record["entityType"]
            in ("cardList", "cardListCategory", "cardListEntry")
        ]
        timestamps = [record["updatedAt"] for record in self.records.values()]
        lists.sort(key=lambda value: value["id"])
        categories.sort(key=lambda value: value["id"])
        entries.sort(key=lambda value: value["id"])
        return {
            "id": "icloud-v4-entities",
            "deviceName": "Simulator Relay",
            "capturedAt": max(timestamps),
            "libraryIdentity": identity,
            "searchSettings": settings,
            "listSnapshot": {
                "lists": lists,
                "categories": categories,
                "entries": entries,
            },
            "deletedLists": [
                {
                    "id": value["recordID"],
                    "deletedAt": value["deletedAt"],
                }
                for value in tombstones
                if value["entityType"] == "cardList"
            ],
            "deletedEntities": tombstones,
        }

    def envelope_locked(self):
        snapshot = self.snapshot_locked()
        return {
            "generation": self.generation,
            "state": {
                "requiredLibraryIdentity": self.identity,
                "snapshots": [snapshot] if snapshot else [],
                "recoverySnapshots": self.retained_recoveries(),
            },
        }

    def envelope(self):
        with self.lock:
            return self.envelope_locked()

    def reset(self):
        with self.lock:
            self.generation += 1
            self.identity = None
            self.records = {}
            self.recoveries = {}
            return self.envelope_locked()


def handler_type(state):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/state":
                self.send_error(404)
                return
            self.write_json(state.envelope())

        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/snapshot":
                envelope = state.merge_snapshot(
                    payload["snapshot"],
                    payload["requiredLibraryIdentity"],
                )
            elif self.path == "/recovery":
                envelope = state.merge_recoveries(payload["recoverySnapshots"])
            elif self.path == "/reset":
                envelope = state.reset()
            else:
                self.send_error(404)
                return
            self.write_json(envelope)

        def write_json(self, payload):
            data = json.dumps(
                payload,
                separators=(",", ":"),
                sort_keys=True,
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, fmt, *args):
            return

    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    state = RelayState()
    server = ThreadingHTTPServer((args.host, args.port), handler_type(state))
    print(f"grimora-sync-relay http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
