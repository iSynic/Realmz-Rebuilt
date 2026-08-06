# Package and save contracts

## `.realmz2`

A deterministic ZIP contains canonical minified JSON and content-addressed media:

- `manifest.json`: format/version, campaign/content IDs, compiler provenance, engine requirements, start location, capability inventory, file hashes, package hash.
- `content.json`: Realmz definitions and text.
- `world.json`: maps, authoritative topology, APs/XAPs, transitions, random rectangles, timed encounters, and immutable metadata.
- `scenario.json`: Classic instructions, Scenario Action programs, state definitions, and migrations.
- `assets/index.json` plus hashed media payloads.

Providence owns the schema. The runtime mirror under `contracts` is byte-identical and independently enforced. The package excludes editor layout, absolute paths, native raw bytes, compatibility annexes, and archaeology artifacts.

Schema v1 is pinned by SHA-256 `2798e65c8f5d6e6ebd99222c18859cbd7b8874c8b170de44245f2fa85df39739` from Providence commit `364755324fae1685b82bbf0c751572045ee6888d`. Its world contract uses normalized directional edges and explicit features; Castle's packed dungeon fields and Providence's Layout record remain compiler inputs, not runtime map models. Its content contract carries direct Simple/Complex/Thief/Timed Encounter records and direct race, caste, item, spell, monster, battle, treasure, and shop definitions. Standard Data S records compile to their packed class/level/slot identities; custom Data Spell slot 0 is packed ID 5101 and slot 104 is 5521. Its scenario contract contains trigger/program references, preserved `ClassicAction` instructions, typed `CallScenarioAction` instructions, compiled Safe bytecode, versioned action-state definitions, and migrations. It does not contain Safe visual/source AST, behavior anchors, authoring modes, or sandbox source.

`PackageRepository` rejects unsafe/extra entries, noncanonical entry order, schema or capability drift, per-file size/hash mismatches, package-hash mismatches, malformed topology, duplicate identities, unresolved map/trigger/program/action references, unsupported Classic opcodes, invalid Scenario Action namespaces or callers, argument/type mismatches, oversized Safe programs/arrays, and unknown capabilities before constructing `RealmzContent`.

## `.r2save`

A versioned envelope under `user://saves/<campaign-id>/` records the campaign and package hash, rules/deviation IDs, complete game state, overlays, clock, economy, equipment escrow, allies, encounter attempts/type flags, mutable shop stock, combat, scenario-program replacements, VM frames, pending interaction, Scenario Action state, RNG state/draw count, and metadata.

Saves occur only at committed boundaries. Infrastructure writes a temporary file, reads and validates it, rotates one backup, and atomically replaces the slot. Restore validates an entire replacement before changing the active session. Schema migrations are ordered pure transforms with fixtures.

There is no Classic or prior-Remake save importer.

`SaveRepository` implements the v1 write sequence now: write a temporary envelope, parse it back into typed state, rotate one backup, and rename the verified temporary file into the slot. `GameSession.snapshot()` returns a detached aggregate, including all gameplay-domain state, VM frames, pending request/continuation, Scenario Action state, and post-move continuation. Restore constructs and validates replacement state, RNG, VM, action-state, and interaction objects before replacing the active session.
