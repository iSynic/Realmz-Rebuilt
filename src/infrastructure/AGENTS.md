# Infrastructure adapters contract

## Purpose

Own package loading, schema/hash validation, save persistence, migrations, and external host adapters.

## Ownership

- `.realmz2` ZIP verification and typed domain construction.
- `.r2save` repositories, validation, backup rotation, and pure migrations.
- Installed package discovery, current-revision selection, and capability/readiness reporting.

## Local Contracts

- Treat package and save data as untrusted until all structural, hash, reference, limit, topology, and capability checks pass.
- Discovery verifies manifest/schema/capability and complete archive size/hash integrity without parsing and constructing every campaign. Starting a package performs the complete typed validation; unchanged immutable packages may reuse an in-memory result keyed by canonical path, modification time, and byte count.
- Generic package discovery retains every immutable revision for diagnostics. Installed-campaign discovery exposes only the most recently installed valid revision for each campaign and leaves older content-hash files untouched.
- Validate Classic opcode support, Scenario Action namespaces, caller contexts, typed arguments, Safe bytecode limits, and every program/action reference before constructing content.
- Verify deterministic ZIP inventory/order, canonical manifest package hash, schema hash, and every file hash before parsing runtime documents.
- Runtime JSON dictionaries do not cross into the core; validating factories construct typed immutable content, including explicit topology edges/features, random regions, cross-map transitions, direct Simple/Complex/Thief/Timed Encounters, and rule definitions for races, castes, items, spells, monsters, battles, treasures, and shops.
- Packages with reachable battles require complete typed battle-terrain sets. Land sets contain exactly active-landlook tiles 0 through 200 plus global combat tiles 201 through 400; dungeon sets contain exactly global tiles 200 through 400. Every tile has an exact 3×3 build, and every map reference must match its level type and effective landlook.
- Every race definition must carry exactly five signed `ageChanges` rows of fifteen integers plus five age ranges. The loader rejects missing or malformed aging rows before constructing immutable `RaceDefinition` content.
- Placed triggers must carry a valid `postActionLocation`; the loader rejects missing destination maps and coordinates outside the authoritative topology. Unplaced XAP programs carry no destination.
- Standard and scenario spells use Castle's packed spell identity at the package boundary. The loader rejects duplicate packed IDs and unresolved cross-domain references before constructing content.
- A monster using a Classic random-weapon table requires every item that table can produce. Package readiness queries the same rules-owned table used by monster construction and rejects missing generated weapon identities before play.
- Imported Providence resource-catalog pictures, icons, sounds, Classic special-land `cicn` overlays, every map-referenced tileset, and source-backed shared Classic sounds referenced by reachable instructions are compiled as content-addressed package media. A runtime-ready managed or scenario asset with the same Classic resource identity replaces the shared-resource fallback.
- Presentation media lookup matches the exact four-character resource type plus signed numeric ID. It preserves case and trailing spaces and never falls back to another type merely because the number matches. Package construction rejects duplicate exact keys before presentation receives a catalog.
- Reject a package when a topology cell references a missing tileset or image overlay, when atlas dimensions disagree with its declared tile grid, or when tileset metadata is incomplete. JSON asset records stop at this boundary; presentation receives typed `PackageMediaAsset` values.
- Save only at committed session boundaries. Save the whole aggregate, including VM and session interactions, post-move/random-region continuation, clock, overlays, action state, and RNG.
- Saves may also contain a pending direct-session monster death macro; its battle, combatant, program, VM request, and RNG position validate as one continuation.
- Write a temporary save, read and validate it, rotate one backup, then atomically replace the slot.
- Restore failure leaves the current session untouched.
- Save installation is temporary-write, typed readback, one-backup rotation, then same-volume rename; never expose a partially parsed envelope.
- Infrastructure may use Godot filesystem APIs; core and scenario code may not.
- Presentation settings schema 3 persists window mode and interface density independently from text scale, volume, reduced motion, topology diagnostics, and dungeon-view preference. Schemas 1 and 2 migrate without loss.
- Packages requiring `realmz.scenario.gdscript-actions-v1` fail readiness until an OS-confined external host exists. No in-process or token-scanned GDScript fallback is permitted.
- Release exports contain runtime resources plus Godot-generated export metadata only; local MCP configuration, addon code, tests, tools, docs, contract mirrors, and references are excluded.

## Work Guidance

- Keep installed immutable content separate from mutable session state.
- `CharacterVaultRepository` owns immutable `.r2char` revisions under `user://characters/<character-id>/`. Reads are untrusted and typed; publishing uses temporary write/readback, one-backup rotation, and atomic replacement. Archive is the only removal operation.
- Character-vault records reject battle-scoped character allegiance. A charmed character may exist only inside an active central combat save and must be restored to its base side before publication.
- Vault eligibility is calculated against the target package's stable race, caste, level, item, and spell identities. Missing definitions and authored restrictions produce explicit reasons; import never strips or substitutes content.
- Return typed validation errors suitable for readiness/error screens.

## Verification

- Contract tests cover hash/schema/reference rejection, package mismatch, corrupt saves, backup recovery, and migrations.

## Child DOX Index

- No child AGENTS.md files are currently required.
