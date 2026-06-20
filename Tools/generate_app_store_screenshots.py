#!/usr/bin/env python3
"""Generate App Store screenshots from real Grimora UI test captures."""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT_ROOT = ROOT / "AppStoreScreenshots"
INTERMEDIATE_ROOT = Path("/private/tmp/grimora-app-store-screenshots")
RESULT_ROOT = Path("/private/tmp/grimora-app-store-screenshot-results")


@dataclass(frozen=True)
class CaptureRun:
    key: str
    scheme: str
    destination: str
    test_identifier: str
    source_subdir: str
    filenames: tuple[str, ...]


@dataclass(frozen=True)
class OutputImage:
    path: str
    source_run: str
    source_name: str
    size: tuple[int, int]


CAPTURE_RUNS: dict[str, CaptureRun] = {
    "iphone": CaptureRun(
        key="iphone",
        scheme="GrimoraiOS",
        destination=os.environ.get(
            "GRIMORA_SCREENSHOT_IPHONE_DESTINATION",
            "platform=iOS Simulator,name=iPhone 17 Pro Max",
        ),
        test_identifier="GrimoraiOSUITests/AppStoreScreenshotUITests/testGenerateAppStoreScreenshots",
        source_subdir="iPhone-6.9-portrait",
        filenames=(
            "01-card-actions.png",
            "02-card-value-details.png",
            "03-card-detail.png",
            "04-list-stats.png",
            "05-search-menu.png",
            "06-search-filtered.png",
            "07-search-home.png",
            "08-setup-library.png",
        ),
    ),
    "ipad": CaptureRun(
        key="ipad",
        scheme="GrimoraiOS",
        destination=os.environ.get(
            "GRIMORA_SCREENSHOT_IPAD_DESTINATION",
            "platform=iOS Simulator,name=iPad Pro 13-inch (M5)",
        ),
        test_identifier="GrimoraiOSUITests/AppStoreScreenshotUITests/testGenerateAppStoreScreenshots",
        source_subdir="iPad-13-landscape",
        filenames=(
            "01-lists.png",
            "02-setup-library.png",
            "03-new-list.png",
            "04-list-detail-printings.png",
            "05-card-detail-expanded.png",
            "06-search-grid.png",
            "07-list-grid.png",
            "08-search-filtered.png",
        ),
    ),
    "vision": CaptureRun(
        key="vision",
        scheme="GrimoraVisionOS",
        destination=os.environ.get(
            "GRIMORA_SCREENSHOT_VISION_DESTINATION",
            "platform=visionOS Simulator,name=Apple Vision Pro",
        ),
        test_identifier="GrimoraVisionOSUITests/AppStoreScreenshotUITests/testGenerateAppStoreScreenshots",
        source_subdir="VisionOS-3840x2160",
        filenames=(
            "01-setup-library.png",
            "02-list-detail-grid.png",
            "03-lists-overview.png",
            "04-lists-overview-alt.png",
            "05-search-results.png",
        ),
    ),
    "mac": CaptureRun(
        key="mac",
        scheme="GrimoraMac",
        destination=os.environ.get("GRIMORA_SCREENSHOT_MAC_DESTINATION", "platform=macOS"),
        test_identifier="GrimoraMacUITests/AppStoreScreenshotUITests/testGenerateAppStoreScreenshots",
        source_subdir="Mac-2880x1800/from-desktop",
        filenames=(
            "01-search-library.png",
            "02-filtered-search.png",
            "03-create-list.png",
            "04-lists-overview.png",
            "05-list-detail.png",
        ),
    ),
}


OUTPUT_IMAGES: tuple[OutputImage, ...] = (
    OutputImage("iPhone-6.9-portrait/01-card-actions.png", "iphone", "01-card-actions.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/02-card-value-details.png", "iphone", "02-card-value-details.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/03-card-detail.png", "iphone", "03-card-detail.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/04-list-stats.png", "iphone", "04-list-stats.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/05-search-menu.png", "iphone", "05-search-menu.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/06-search-filtered.png", "iphone", "06-search-filtered.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/07-search-home.png", "iphone", "07-search-home.png", (1320, 2868)),
    OutputImage("iPhone-6.9-portrait/08-setup-library.png", "iphone", "08-setup-library.png", (1320, 2868)),
    OutputImage("iPhone-6.5-portrait/01-card-actions.png", "iphone", "01-card-actions.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/02-card-value-details.png", "iphone", "02-card-value-details.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/03-card-detail.png", "iphone", "03-card-detail.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/04-list-stats.png", "iphone", "04-list-stats.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/05-search-menu.png", "iphone", "05-search-menu.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/06-search-filtered.png", "iphone", "06-search-filtered.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/07-search-home.png", "iphone", "07-search-home.png", (1242, 2688)),
    OutputImage("iPhone-6.5-portrait/08-setup-library.png", "iphone", "08-setup-library.png", (1242, 2688)),
    OutputImage("iPad-13-landscape/01-lists.png", "ipad", "01-lists.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/02-setup-library.png", "ipad", "02-setup-library.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/03-new-list.png", "ipad", "03-new-list.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/04-list-detail-printings.png", "ipad", "04-list-detail-printings.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/05-card-detail-expanded.png", "ipad", "05-card-detail-expanded.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/06-search-grid.png", "ipad", "06-search-grid.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/07-list-grid.png", "ipad", "07-list-grid.png", (2732, 2048)),
    OutputImage("iPad-13-landscape/08-search-filtered.png", "ipad", "08-search-filtered.png", (2732, 2048)),
    OutputImage("VisionOS-3840x2160/01-setup-library.png", "vision", "01-setup-library.png", (3840, 2160)),
    OutputImage("VisionOS-3840x2160/02-list-detail-grid.png", "vision", "02-list-detail-grid.png", (3840, 2160)),
    OutputImage("VisionOS-3840x2160/03-lists-overview.png", "vision", "03-lists-overview.png", (3840, 2160)),
    OutputImage("VisionOS-3840x2160/04-lists-overview-alt.png", "vision", "04-lists-overview-alt.png", (3840, 2160)),
    OutputImage("VisionOS-3840x2160/05-search-results.png", "vision", "05-search-results.png", (3840, 2160)),
    OutputImage("Mac-2880x1800/from-desktop/01-search-library.png", "mac", "01-search-library.png", (2880, 1800)),
    OutputImage("Mac-2880x1800/from-desktop/02-filtered-search.png", "mac", "02-filtered-search.png", (2880, 1800)),
    OutputImage("Mac-2880x1800/from-desktop/03-create-list.png", "mac", "03-create-list.png", (2880, 1800)),
    OutputImage("Mac-2880x1800/from-desktop/04-lists-overview.png", "mac", "04-lists-overview.png", (2880, 1800)),
    OutputImage("Mac-2880x1800/from-desktop/05-list-detail.png", "mac", "05-list-detail.png", (2880, 1800)),
    OutputImage("Mac-2880x1800/raw/01-search.png", "mac", "01-search-library.png", (3680, 2392)),
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run Grimora UI tests with fictional fixture cards and write App Store screenshot PNGs."
    )
    parser.add_argument(
        "--platform",
        choices=("iphone", "ipad", "vision", "mac", "all"),
        action="append",
        default=None,
        help="Capture only selected platform(s). Defaults to all.",
    )
    parser.add_argument(
        "--skip-xcodebuild",
        action="store_true",
        help="Reuse existing intermediate captures instead of running UI tests.",
    )
    parser.add_argument(
        "--keep-intermediates",
        action="store_true",
        help="Keep /private/tmp intermediate screenshots and result bundles.",
    )
    args = parser.parse_args()

    selected_runs = selected_platforms(args.platform)
    INTERMEDIATE_ROOT.mkdir(parents=True, exist_ok=True)
    RESULT_ROOT.mkdir(parents=True, exist_ok=True)

    if not args.skip_xcodebuild:
        for run_key in selected_runs:
            run_capture(CAPTURE_RUNS[run_key])

    sources = collect_source_images(selected_runs)
    write_outputs(sources, selected_runs)
    validate_outputs(selected_runs)

    if not args.keep_intermediates and not args.skip_xcodebuild:
        shutil.rmtree(INTERMEDIATE_ROOT, ignore_errors=True)
        shutil.rmtree(RESULT_ROOT, ignore_errors=True)


def selected_platforms(values: list[str] | None) -> tuple[str, ...]:
    if not values or "all" in values:
        return ("iphone", "ipad", "vision", "mac")
    ordered = []
    for key in ("iphone", "ipad", "vision", "mac"):
        if key in values:
            ordered.append(key)
    return tuple(ordered)


def run_capture(run: CaptureRun) -> None:
    source_dir = INTERMEDIATE_ROOT / run.source_subdir
    result_bundle = RESULT_ROOT / f"{run.key}.xcresult"
    attachments_dir = RESULT_ROOT / f"{run.key}-attachments"
    shutil.rmtree(source_dir, ignore_errors=True)
    shutil.rmtree(result_bundle, ignore_errors=True)
    shutil.rmtree(attachments_dir, ignore_errors=True)
    source_dir.mkdir(parents=True, exist_ok=True)

    print(f"Running {run.key} UI screenshot test on {run.destination}")
    command = [
        "xcodebuild",
        "test",
        "-project",
        "Grimora.xcodeproj",
        "-scheme",
        run.scheme,
        "-configuration",
        "Debug",
        "-destination",
        run.destination,
        "-parallel-testing-enabled",
        "NO",
        f"-only-testing:{run.test_identifier}",
        "-resultBundlePath",
        str(result_bundle),
    ]
    environment = os.environ.copy()
    environment["GRIMORA_APP_STORE_SCREENSHOT_OUTPUT_DIR"] = str(source_dir)
    if run.key == "vision":
        environment["GRIMORA_APP_STORE_SCREENSHOT_HOST_CAPTURE"] = "1"
        run_capture_with_host_screenshots(command, environment, source_dir, run.destination)
    else:
        subprocess.run(command, cwd=ROOT, env=environment, check=True)

    if result_bundle.exists():
        attachments_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                str(result_bundle),
                "--output-path",
                str(attachments_dir),
            ],
            cwd=ROOT,
            check=True,
        )


def run_capture_with_host_screenshots(
    command: list[str],
    environment: dict[str, str],
    source_dir: Path,
    destination: str,
) -> None:
    simulator_udid = simulator_udid_for_destination(destination)
    process = subprocess.Popen(command, cwd=ROOT, env=environment)
    handled: set[Path] = set()
    try:
        while process.poll() is None:
            handle_host_capture_requests(source_dir, simulator_udid, handled)
            time.sleep(0.2)
        handle_host_capture_requests(source_dir, simulator_udid, handled)
        if process.returncode:
            raise subprocess.CalledProcessError(process.returncode, command)
    finally:
        if process.poll() is None:
            process.terminate()


def handle_host_capture_requests(source_dir: Path, simulator_udid: str, handled: set[Path]) -> None:
    for request_path in sorted(source_dir.glob("*.png.request")):
        if request_path in handled:
            continue
        filename = request_path.name[: -len(".request")]
        screenshot_path = source_dir / filename
        capture_simulator_screenshot(simulator_udid, screenshot_path)
        (source_dir / f"{filename}.captured").write_text("ok", encoding="utf-8")
        handled.add(request_path)


def capture_simulator_screenshot(simulator_udid: str, output_path: Path) -> None:
    last_error: subprocess.CalledProcessError | None = None
    for _ in range(8):
        try:
            subprocess.run(
                ["xcrun", "simctl", "io", simulator_udid, "screenshot", str(output_path)],
                cwd=ROOT,
                check=True,
            )
            return
        except subprocess.CalledProcessError as error:
            last_error = error
            time.sleep(0.5)
    assert last_error is not None
    raise last_error


def simulator_udid_for_destination(destination: str) -> str:
    name = destination_value(destination, "name")
    if not name:
        raise RuntimeError(f"Unable to resolve simulator name from destination: {destination}")

    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(result.stdout)
    matches = [
        device
        for devices in data.get("devices", {}).values()
        for device in devices
        if device.get("name") == name and device.get("isAvailable", True)
    ]
    booted = next((device for device in matches if device.get("state") == "Booted"), None)
    selected = booted or (matches[0] if matches else None)
    if not selected:
        raise RuntimeError(f"No available simulator named {name!r} was found.")
    return str(selected["udid"])


def destination_value(destination: str, key: str) -> str | None:
    prefix = f"{key}="
    for component in destination.split(","):
        trimmed = component.strip()
        if trimmed.startswith(prefix):
            return trimmed[len(prefix) :]
    return None


def collect_source_images(selected_runs: tuple[str, ...]) -> dict[tuple[str, str], Path]:
    sources: dict[tuple[str, str], Path] = {}
    for run_key in selected_runs:
        run = CAPTURE_RUNS[run_key]
        source_dir = INTERMEDIATE_ROOT / run.source_subdir
        attachments_dir = RESULT_ROOT / f"{run.key}-attachments"
        expected = set(run.filenames)

        for filename in expected:
            direct_path = source_dir / filename
            if direct_path.exists():
                sources[(run_key, filename)] = direct_path

        for key, path in attachment_sources(run_key, expected, attachments_dir).items():
            sources.setdefault(key, path)

        missing = sorted(filename for filename in expected if (run_key, filename) not in sources)
        if missing:
            formatted = ", ".join(missing)
            raise RuntimeError(f"Missing {run.key} screenshot capture(s): {formatted}")
    return sources


def attachment_sources(run_key: str, expected: set[str], attachments_dir: Path) -> dict[tuple[str, str], Path]:
    if not attachments_dir.exists():
        return {}

    found: dict[tuple[str, str], Path] = {}
    for path in attachments_dir.rglob("*.png"):
        for filename in expected:
            if attachment_name_matches(filename, path.name):
                found[(run_key, filename)] = path

    manifest = attachments_dir / "manifest.json"
    if manifest.exists():
        with manifest.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
        for name, path_value in walk_manifest(data):
            filename = next((expected_name for expected_name in expected if attachment_name_matches(expected_name, name)), None)
            if filename is None:
                continue
            path = Path(path_value)
            if not path.is_absolute():
                path = attachments_dir / path
            if path.exists() and path.suffix.lower() == ".png":
                found[(run_key, filename)] = path
    return found


def walk_manifest(value: object) -> Iterable[tuple[str, str]]:
    if isinstance(value, dict):
        name = string_value(
            value,
            ("suggestedHumanReadableName", "name", "displayName", "attachmentName", "title"),
        )
        path = string_value(
            value,
            ("exportedFileName", "path", "filename", "fileName", "payloadPath", "outputPath"),
        )
        if name and path:
            yield name, path
        for child in value.values():
            yield from walk_manifest(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_manifest(child)


def string_value(value: dict[str, object], keys: tuple[str, ...]) -> str | None:
    for key in keys:
        child = value.get(key)
        if isinstance(child, str) and child:
            return child
    return None


def attachment_name_matches(expected: str, candidate: str) -> bool:
    if candidate == expected:
        return True
    expected_stem = Path(expected).stem
    candidate_name = Path(candidate).name
    return candidate_name.startswith(f"{expected_stem}_") or candidate_name.startswith(f"{expected_stem}-")


def write_outputs(sources: dict[tuple[str, str], Path], selected_runs: tuple[str, ...]) -> None:
    selected = set(selected_runs)
    for output in OUTPUT_IMAGES:
        if output.source_run not in selected:
            continue
        source_path = sources[(output.source_run, output.source_name)]
        destination = SCREENSHOT_ROOT / output.path
        destination.parent.mkdir(parents=True, exist_ok=True)
        normalize_image(source_path, destination, output.size)
        print(f"Wrote {destination.relative_to(ROOT)}")


def normalize_image(source_path: Path, destination: Path, size: tuple[int, int]) -> None:
    with Image.open(source_path) as image:
        transposed = ImageOps.exif_transpose(image)
        if transposed.mode in ("RGBA", "LA") or "transparency" in transposed.info:
            rgba = transposed.convert("RGBA")
            background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            background.alpha_composite(rgba)
            source = background.convert("RGB")
        else:
            source = transposed.convert("RGB")
        source = trim_dark_matte(source)
        if source.size == size:
            source.save(destination)
            return

        source_ratio = source.width / source.height
        target_ratio = size[0] / size[1]
        if abs(math.log(source_ratio / target_ratio)) < 0.06:
            output = ImageOps.fit(source, size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
        else:
            output = Image.new("RGB", size, (255, 255, 255))
            contained = ImageOps.contain(source, size, method=Image.Resampling.LANCZOS)
            origin = ((size[0] - contained.width) // 2, (size[1] - contained.height) // 2)
            output.paste(contained, origin)
        output.save(destination)


def trim_dark_matte(source: Image.Image) -> Image.Image:
    mask = source.convert("L").point(lambda value: 255 if value > 24 else 0)
    bounds = mask.getbbox()
    if bounds is None:
        return source

    left, top, right, bottom = bounds
    horizontal_trim = left + (source.width - right)
    vertical_trim = top + (source.height - bottom)
    if horizontal_trim == 0 and vertical_trim == 0:
        return source

    if right - left < source.width * 0.55 or bottom - top < source.height * 0.55:
        return source

    return source.crop(bounds)


def validate_outputs(selected_runs: tuple[str, ...]) -> None:
    selected = set(selected_runs)
    failures = []
    for output in OUTPUT_IMAGES:
        if output.source_run not in selected:
            continue
        path = SCREENSHOT_ROOT / output.path
        if not path.exists():
            failures.append(f"{output.path} was not written")
            continue
        with Image.open(path) as image:
            if image.size != output.size:
                failures.append(f"{output.path} is {image.size[0]}x{image.size[1]}, expected {output.size[0]}x{output.size[1]}")
    if failures:
        raise RuntimeError("\n".join(failures))


if __name__ == "__main__":
    main()
