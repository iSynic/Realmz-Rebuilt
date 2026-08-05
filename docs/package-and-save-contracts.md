# Package and save contracts

## `.realmz2`

A deterministic ZIP contains canonical minified JSON and content-addressed media:

- `manifest.json`: format/version, campaign/content IDs, compiler provenance, engine requirements, start location, capability inventory, file hashes, package hash.
- `content.json`: Realmz definitions and text.
- `world.json`: maps, authoritative topology, APs/XAPs, transitions, random rectangles, timed encounters, and immutable metadata.
- `scenario.json`: Classic instructions, Scenario Action programs, state definitions, and migrations.
- `assets/index.json` plus hashed media payloads.

Providence owns the schema. The runtime mirror under `contracts` is byte-identical and independently enforced. The package excludes editor layout, absolute paths, native raw bytes, compatibility annexes, and archaeology artifacts.

## `.r2save`

A versioned envelope under `user://saves/<campaign-id>/` records the campaign and package hash, rules/deviation IDs, complete game state, overlays, clock, economy, combat, VM frames, pending interaction, Scenario Action state, RNG state/draw count, and metadata.

Saves occur only at committed boundaries. Infrastructure writes a temporary file, reads and validates it, rotates one backup, and atomically replaces the slot. Restore validates an entire replacement before changing the active session. Schema migrations are ordered pure transforms with fixtures.

There is no Classic or prior-Remake save importer.
