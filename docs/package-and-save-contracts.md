# Package and save contracts

## `.realmz2`

A deterministic ZIP contains canonical minified JSON and content-addressed media:

- `manifest.json`: format/version, campaign/content IDs, compiler provenance, engine requirements, start location, capability inventory, file hashes, package hash.
- `content.json`: Realmz definitions and text.
- `world.json`: maps, authoritative topology, APs/XAPs, transitions, random rectangles, timed encounters, and immutable metadata.
- `scenario.json`: Classic instructions, Scenario Action programs, state definitions, and migrations.
- `assets/index.json` plus hashed media payloads.

Providence owns the schema. The runtime mirror under `contracts` is byte-identical and independently enforced. The package excludes editor layout, absolute paths, native raw bytes, compatibility annexes, and archaeology artifacts.

Schema v1 is pinned by SHA-256 `4ecdc3866ada29a0d311e87700870d2e63732d97bf04d4898a3bc68331d073fd` from the Providence exporter lineage through commit `a525e9df0d0619847a5928463eed881ace79152a`. Its world contract uses normalized directional edges and explicit features; Castle's packed dungeon fields and Providence's Layout record remain compiler inputs, not runtime map models. Placed AP headers compile to a typed `postActionLocation`; XAPs use `null`, and tile mutation remains an explicit scenario instruction. Random rectangles retain signed 1-in-10,000 chances, battle ranges, three random-door slots, only/option behavior, and media IDs. Its content contract carries direct Simple/Complex/Thief/Timed Encounter records and direct race, caste, item, spell, monster, battle, treasure, and shop definitions. Providence merges 799 nonzero bundled Classic item identities with scenario supplies/overrides and compiles standard Data S records to packed class/level/slot identities; custom Data Spell slot 0 is packed ID 5101 and slot 104 is 5715. Battle records retain explicit monster slots, coordinates, and traitor inversion. Its scenario contract contains trigger/program references, preserved `ClassicAction` instructions, typed `CallScenarioAction` instructions, compiled Safe bytecode, versioned action-state definitions, and migrations. It does not contain Safe visual/source AST, behavior anchors, authoring modes, or sandbox source.

Managed Providence media and decoded imported resource-catalog pictures/icons/sounds become content-addressed payloads. Every referenced map tileset is also a required content-addressed PNG with explicit grid metadata; Providence normalizes Classic PICT 302's fixed dungeon-composition region to a 4×4 runtime atlas. Managed media wins when it claims the same Classic resource identity. Absolute paths and resource-fork bytes never enter the package.

`PackageRepository` rejects unsafe/extra entries, noncanonical entry order, schema or capability drift, per-file size/hash mismatches, package-hash mismatches, malformed topology, duplicate identities, unresolved map/trigger/program/action references, unsupported Classic opcodes, invalid Scenario Action namespaces or callers, argument/type mismatches, oversized Safe programs/arrays, and unknown capabilities before constructing `RealmzContent`. `realmz.scenario.gdscript-actions-v1` is a recognized but unavailable capability and fails readiness until an OS-confined external host exists.

Installed-package discovery is deliberately staged. It verifies the manifest, schema/capabilities, deterministic archive inventory, and every declared file size/hash so corrupt or stale packages do not appear playable, but it does not parse the 65 MB AOGM world document or construct 72,900 cells merely to draw the campaign list. Selecting Play runs the full document/reference/topology validation and typed construction above. An unchanged immutable package load is cached in memory by canonical path, modification time, and byte count; installation of the file already at its content-hash destination does not validate it a second time.

## `.r2save`

A versioned envelope under `user://saves/<campaign-id>/` records the campaign and package hash, rules/deviation IDs, complete game state, overlays, clock, economy, equipment escrow, allies, encounter attempts/type flags, mutable shop stock, combat, scenario-program replacements, VM frames, VM or session-owned pending interaction, post-move/random-region/AP-destination, direct combat-death-macro, or post-battle ally-selection continuation, Scenario Action state, RNG state/draw count, and metadata.

Saves occur only at committed boundaries. Infrastructure writes a temporary file, reads and validates it, rotates one backup, and atomically replaces the slot. Restore validates an entire replacement before changing the active session. Schema migrations are ordered pure transforms with fixtures.

There is no Classic or prior-Remake save importer.

`SaveRepository` writes envelope v3 by creating a temporary file, parsing it back into typed state, rotating one backup, and renaming the verified temporary file into the slot. Ordered pure migrations take v1 through v2's session-interaction/random-region fields and then add v3's `actionPointDestinationDepth` to nonempty post-move continuations. V3 also validates the alternate direct combat-death-macro and post-battle ally-selection continuation shapes against their matching combat and pending request. `GameSession.snapshot()` returns a detached aggregate, including all gameplay-domain state, VM frames, pending request/continuation, Scenario Action state, and host continuation. Restore constructs and validates replacement state, RNG, VM, action-state, session-interaction, and continuation objects before replacing the active session.
