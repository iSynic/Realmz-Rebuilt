# Runtime contract mirror

## Purpose

Mirror the authoritative Providence `.realmz2` schemas byte-for-byte and expose drift verification to the runtime repository.

## Ownership

- JSON Schemas and explicit format/version identifiers consumed by the runtime.
- Mirror hashes and schema-drift checks.

## Local Contracts

- Providence is authoritative. Changes originate there, are reviewed with its exporter, then are mirrored without hand edits.
- Schema files use canonical UTF-8 bytes and deterministic ordering.
- Runtime package fixtures are synthetic and contain no commercial payloads.

## Work Guidance

- Record the matching Providence commit and schema SHA-256 when updating the mirror.
- Schema v3 is a clean cut mirroring Providence commit `90d3e80af6f01250ca298687699c6a3fe8c81653` at SHA-256 `8911a4de6f6182e7d18a5c1ee2c8ccf2989a5bb22cfcb24c6f9fc4ab19a23602`. Manifests use format version 2 and all five canonical documents use schema version 3; v1/v2 packages are rejected and must be re-exported. Land topology uses the fixed row-major `realmz2.compact-cell-rows.v2` ABI: every cell retains exact Classic `needboad`, movement sound, ordinary cost, and blocked-attempt timeclicks, while each land map carries the active landlook's exact tile-60 and tile-147 replacement profiles for moved boats. Dungeon maps carry no boat profiles. The complete normalized display, rules, encounter, topology, media, and application-hook data established by schema v2 remains mandatory runtime input. Canonical schema bytes use LF line endings on every platform.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
