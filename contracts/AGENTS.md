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
- Schema v2 currently mirrors Providence commit `2b5eadff` at SHA-256 `c9c713b99ec58c366f6eeaf96ed371c94e491e8ab8351ba791a848d5f2f878ac`. The v2 campaign contract adds typed display metadata, restrictions, contact fields, splash identity, and race/caste eligibility relationships.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
