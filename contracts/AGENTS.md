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
- Schema v2 currently mirrors Providence commit `899a191272643295d0c7d0c00d23a073407870fa` at SHA-256 `8167835e4db54d97eb90a263967d472f8108dbf63c3bc0ebd5d723441bdadbaf`. The v2 contract includes typed display metadata, Data SC aggregate recommended/maximum party-level guidance with source-authorship evidence, typed Data MD-1/Data MD1 Monster Sets, restrictions, exactly thirty one-based Classic race and caste profiles with aligned eligibility and aging tables, fourteen authored race/caste trained-ability values, thirty caste victory thresholds, eight-direction land Layout transitions, bounded monster `requiredWeapon`/`magicToHit` fields separate from battle placement `distance`, exactly forty signed monster starting conditions, signed Classic spell-record fields, complete source-backed battle-terrain sets for each effective landlook plus the shared dungeon combat table, exactly six position-preserving monster item slots, at most twenty typed `Data MD2` player-map records with separate menu names, exact display-mode/resource identities, crop geometry, ordered CICN markers, and notes, and exact nullable Start Game, Party Death, End Adventure, Shop, and Temple application-hook program references. Its canonical JSON bytes use LF line endings on every platform.

## Verification

- CI compares the mirrored schema hash to the Providence-authoritative expected hash when that checkout/artifact is available.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
