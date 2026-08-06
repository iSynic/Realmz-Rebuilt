# Package and save contracts

## `.realmz2`

A deterministic ZIP contains canonical minified JSON and content-addressed media:

- `manifest.json`: format/version, campaign/content IDs, compiler provenance, engine requirements, start location, capability inventory, file hashes, package hash.
- `content.json`: Realmz definitions and text.
- `world.json`: maps, authoritative topology, APs/XAPs, transitions, random rectangles, timed encounters, and immutable metadata.
- `scenario.json`: Classic instructions, Scenario Action programs, state definitions, and migrations.
- `assets/index.json` plus hashed media payloads.

Providence owns the schema. The runtime mirror under `contracts` is byte-identical and independently enforced. The package excludes editor layout, absolute paths, native raw bytes, compatibility annexes, and archaeology artifacts.

Schema v1 is pinned by SHA-256 `816caa25632b89b2e342ff1dc814189d05c2d12899844ac0f4eb688f370448e3` from Providence commit `e38b3f7584dbe87e8a59c54c372b5626d0aafb07`. Its world contract uses normalized directional edges and explicit features; Castle's packed dungeon fields and Providence's Layout record remain compiler inputs, not runtime map models. `PackageRepository` rejects unsafe/extra entries, noncanonical entry order, schema or capability drift, per-file size/hash mismatches, package-hash mismatches, malformed topology, duplicate identities, unresolved map/trigger/program references, invalid Classic instruction shapes, and out-of-contract Scenario Actions before constructing `RealmzContent`.

## `.r2save`

A versioned envelope under `user://saves/<campaign-id>/` records the campaign and package hash, rules/deviation IDs, complete game state, overlays, clock, economy, combat, VM frames, pending interaction, Scenario Action state, RNG state/draw count, and metadata.

Saves occur only at committed boundaries. Infrastructure writes a temporary file, reads and validates it, rotates one backup, and atomically replaces the slot. Restore validates an entire replacement before changing the active session. Schema migrations are ordered pure transforms with fixtures.

There is no Classic or prior-Remake save importer.

`SaveRepository` implements the v1 write sequence now: write a temporary envelope, parse it back into typed state, rotate one backup, and rename the verified temporary file into the slot. `GameSession.snapshot()` returns a detached aggregate, and restore constructs and validates replacement state/RNG/interaction objects before replacing the active session.
