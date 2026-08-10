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
- Schema v2 currently mirrors Providence commit `1d660bb6dbab175e641f33d07e8755e8ee3be24e` at SHA-256 `e0ebe02f52c1fb52e83ce6e91074d82f4adf5c39db7af8e7a7512dd83e5c3f62`. The v2 contract includes typed display metadata, restrictions, exactly thirty one-based Classic race and caste profiles with aligned eligibility and aging tables, eight-direction land Layout transitions, bounded monster `requiredWeapon`/`magicToHit` fields separate from battle placement `distance`, exactly forty signed monster starting conditions, complete source-backed battle-terrain sets for each effective landlook plus the shared dungeon combat table, and exactly six position-preserving monster item slots.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
