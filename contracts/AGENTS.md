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
- Schema v2 currently mirrors Providence commit `202c87f1b4d856ec968760ed982f6ea6eeae3204` at SHA-256 `56b70255779a8a7dfadcda80ec16c86fba15ce269c31f974db840f74dff49861`. The v2 contract includes typed display metadata, restrictions, exactly thirty one-based Classic race and caste profiles with aligned eligibility and aging tables, fourteen authored race/caste trained-ability values, thirty caste victory thresholds, eight-direction land Layout transitions, bounded monster `requiredWeapon`/`magicToHit` fields separate from battle placement `distance`, exactly forty signed monster starting conditions, signed Classic spell-record fields, complete source-backed battle-terrain sets for each effective landlook plus the shared dungeon combat table, and exactly six position-preserving monster item slots. Its canonical JSON bytes use LF line endings on every platform.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
