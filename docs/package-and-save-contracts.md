# Package and save contracts

## `.realmz2`

A deterministic ZIP contains canonical minified JSON and content-addressed media:

- `manifest.json`: format/version, campaign/content IDs, compiler provenance, engine requirements, start location, capability inventory, file hashes, package hash.
- `content.json`: Realmz definitions and text.
- `world.json`: maps, authoritative topology, APs/XAPs, transitions, random rectangles, timed encounters, and immutable metadata.
- `scenario.json`: Classic instructions, Scenario Action programs, state definitions, and migrations.
- `assets/index.json` plus hashed media payloads.

Providence owns the schema. The runtime mirror under `contracts` is byte-identical and independently enforced. The package excludes editor layout, absolute paths, native raw bytes, compatibility annexes, and archaeology artifacts.

Schema v1 is pinned by SHA-256 `dd3c467b9dc3fe61574a2809c43e9c28f38c7e5d4fee98a547dfcd9da95dfe2b` from Providence commit `bb300fe8795604e5b288eee41b82f819a13eb951`. Its world contract uses normalized directional edges and explicit features; Castle's packed dungeon fields and Providence's Layout record remain compiler inputs, not runtime map models. Random rectangles retain signed 1-in-10,000 chances, battle ranges, three random-door slots, only/option behavior, and media IDs. Its content contract carries direct Simple/Complex/Thief/Timed Encounter records and direct race, caste, item, spell, monster, battle, treasure, and shop definitions. Providence merges 799 nonzero bundled Classic item identities with scenario supplies/overrides and compiles standard Data S records to packed class/level/slot identities; custom Data Spell slot 0 is packed ID 5101 and slot 104 is 5715. Battle records retain explicit monster slots, coordinates, and traitor inversion. Its scenario contract contains trigger/program references, preserved `ClassicAction` instructions, typed `CallScenarioAction` instructions, compiled Safe bytecode, versioned action-state definitions, and migrations. It does not contain Safe visual/source AST, behavior anchors, authoring modes, or sandbox source.

Managed Providence media and decoded imported resource-catalog pictures/icons/sounds become content-addressed payloads. Managed media wins when it claims the same Classic resource identity. Absolute paths and resource-fork bytes never enter the package.

`PackageRepository` rejects unsafe/extra entries, noncanonical entry order, schema or capability drift, per-file size/hash mismatches, package-hash mismatches, malformed topology, duplicate identities, unresolved map/trigger/program/action references, unsupported Classic opcodes, invalid Scenario Action namespaces or callers, argument/type mismatches, oversized Safe programs/arrays, and unknown capabilities before constructing `RealmzContent`.

## `.r2save`

A versioned envelope under `user://saves/<campaign-id>/` records the campaign and package hash, rules/deviation IDs, complete game state, overlays, clock, economy, equipment escrow, allies, encounter attempts/type flags, mutable shop stock, combat, scenario-program replacements, VM frames, VM or session-owned pending interaction, post-move/random-region continuation, Scenario Action state, RNG state/draw count, and metadata.

Saves occur only at committed boundaries. Infrastructure writes a temporary file, reads and validates it, rotates one backup, and atomically replaces the slot. Restore validates an entire replacement before changing the active session. Schema migrations are ordered pure transforms with fixtures.

There is no Classic or prior-Remake save importer.

`SaveRepository` writes envelope v2 by creating a temporary file, parsing it back into typed state, rotating one backup, and renaming the verified temporary file into the slot. The ordered pure v1-to-v2 migration adds session-interaction and random-region continuation fields without changing gameplay state. `GameSession.snapshot()` returns a detached aggregate, including all gameplay-domain state, VM frames, pending request/continuation, Scenario Action state, and post-move continuation. Restore constructs and validates replacement state, RNG, VM, action-state, session-interaction, and continuation objects before replacing the active session.
