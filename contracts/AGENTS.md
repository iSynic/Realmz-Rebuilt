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
- Schema v3 is a clean cut mirroring Providence commit `0a3aab2e8c1951c48d2d626ee24e96fb9c7aab04` at SHA-256 `a696ccf50fe1f03475205caa5351729427494a1ad4a35bed25069f05d1220e2c`. Manifests use format version 2 and all five canonical documents use schema version 3; v1/v2 packages are rejected and must be re-exported. The topology remains the fixed row-major `realmz2.compact-cell-rows.v1` ABI, and the complete normalized display, rules, encounter, topology, media, and application-hook data established by schema v2 remains mandatory runtime input. Canonical schema bytes use LF line endings on every platform.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
