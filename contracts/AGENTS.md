# Runtime and diagnostic contract mirror

## Purpose

Mirror the authoritative Providence `.realmz2` package and feature-report schemas byte-for-byte and expose drift verification to the runtime repository.

## Ownership

- JSON Schemas and explicit format/version identifiers consumed by the runtime or parity tooling.
- Mirror hashes and schema-drift checks.

## Local Contracts

- Providence is authoritative. Changes originate there, are reviewed with its exporter, then are mirrored without hand edits.
- Schema files use canonical UTF-8 bytes and deterministic ordering.
- Runtime package fixtures are synthetic and contain no commercial payloads.

## Work Guidance

- Record the matching Providence commit and schema SHA-256 when updating the mirror.
- Schema v3 is a clean cut mirroring Providence commit `efee09f5ce05de7000dacf20efb0ebbc72bcd047` at SHA-256 `12376856235a11f507b993835acad87b546f87b9ad519533967ed2701ddb89cd`. Manifests use format version 2 and all five canonical documents use schema version 3; v1/v2 packages are rejected and must be re-exported. Land topology uses the fixed row-major `realmz2.compact-cell-rows.v2` ABI: every cell retains exact Classic `needboad`, movement sound, ordinary cost, blocked-attempt timeclicks, and forest semantic. Action-point marker bands remain enterable independently of underlying landlook solidity. Negative special-land overlays derive traversal from the base tile plus independent `Data Solids` and retain Castle's fixed sound/time behavior. Each map preserves its exact base scale and each land map carries the active landlook's exact tile-60 and tile-147 replacement profiles for moved boats. Dungeon maps carry no boat profiles or base scale. Monster records preserve independent Classic name identity plus bestiary description/menu visibility. Occupied shop stock preserves its unique native 0–999 slot. Scenario-owned Custom 1–3 audio carries an explicit music slot. Opcode 92 preserves its second consecutive Extra Code row as operands 5–9; ordinary actions retain five operands. Timed records identify the exact Data ED3 macro and `xap:<id>` program. Playable-level names remain canonical `Land level N` and `Dungeon level N`; STR# player-map titles belong only to player-map records. The complete normalized display, rules, encounter, topology, media, and application-hook data established by schema v2 remains mandatory runtime input. Canonical schema bytes use LF line endings on every platform.
- Feature-report format v2 uses Providence generator baseline `8ae731e851544575d6687059b9c84a2535f89d5f` at schema SHA-256 `be4fa175ebfc8ed756a0db2b0c6073108bd9f635e8c23321d1258cfcf4e73ee4`. Spell signatures include `queueIcon` so persistent battlefield fields cannot collapse into otherwise similar one-shot areas. It is a diagnostic sidecar, not a runtime package document. Informational preservation diagnostics do not count as unresolved compiler loss. Commercial reports remain local and untracked; only their normalized hashes, counts, and coverage results may enter committed parity artifacts when they reveal no scenario payload.

## Verification

- CI verifies both mirrored schema hashes against the committed Providence-authoritative expected hashes.
- Package validation tests exercise every schema revision in use.

## Child DOX Index

- No child AGENTS.md files are currently required.
