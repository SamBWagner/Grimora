# Grimora CloudKit Schema

`Grimora.ckdb` is the canonical schema exported from the development
environment after a development-signed Grimora build has bootstrapped every
record type and field in the checked-in schema contract.

Use `Tools/manage_cloudkit_schema.sh` for exports, validation, development
imports, and the guarded production promotion. The production command always
exports a backup first and refuses to run without an explicit confirmation
environment variable.

The application may create missing schema only in debug builds. Release builds
fail closed when the production schema is incomplete.
