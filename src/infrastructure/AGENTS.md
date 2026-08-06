# Infrastructure adapters contract

## Purpose

Own package loading, schema/hash validation, save persistence, migrations, and external host adapters.

## Ownership

- `.realmz2` ZIP verification and typed domain construction.
- `.r2save` repositories, validation, backup rotation, and pure migrations.
- Installed package discovery and capability/readiness reporting.

## Local Contracts

- Treat package and save data as untrusted until all structural, hash, reference, limit, topology, and capability checks pass.
- Validate Classic opcode support, Scenario Action namespaces, caller contexts, typed arguments, Safe bytecode limits, and every program/action reference before constructing content.
- Verify deterministic ZIP inventory/order, canonical manifest package hash, schema hash, and every file hash before parsing runtime documents.
- Runtime JSON dictionaries do not cross into the core; validating factories construct typed immutable content, including explicit topology edges/features, random regions, cross-map transitions, direct Simple/Complex/Thief/Timed Encounters, and rule definitions for races, castes, items, spells, monsters, battles, treasures, and shops.
- Placed triggers must carry a valid `postActionLocation`; the loader rejects missing destination maps and coordinates outside the authoritative topology. Unplaced XAP programs carry no destination.
- Standard and scenario spells use Castle's packed spell identity at the package boundary. The loader rejects duplicate packed IDs and unresolved cross-domain references before constructing content.
- Imported Providence resource-catalog pictures, icons, sounds, and every map-referenced tileset are compiled as content-addressed package media. A runtime-ready managed asset with the same Classic resource identity replaces the imported preview.
- Reject a package when a topology cell references a missing tileset, when atlas dimensions disagree with its declared tile grid, or when tileset metadata is incomplete. JSON asset records stop at this boundary; presentation receives typed `PackageMediaAsset` values.
- Save only at committed session boundaries. Save the whole aggregate, including VM and session interactions, post-move/random-region continuation, clock, overlays, action state, and RNG.
- Saves may also contain a pending direct-session monster death macro; its battle, combatant, program, VM request, and RNG position validate as one continuation.
- Write a temporary save, read and validate it, rotate one backup, then atomically replace the slot.
- Restore failure leaves the current session untouched.
- Save installation is temporary-write, typed readback, one-backup rotation, then same-volume rename; never expose a partially parsed envelope.
- Infrastructure may use Godot filesystem APIs; core and scenario code may not.
- Packages requiring `realmz.scenario.gdscript-actions-v1` fail readiness until an OS-confined external host exists. No in-process or token-scanned GDScript fallback is permitted.
- Release exports contain runtime resources plus Godot-generated export metadata only; local MCP configuration, addon code, tests, tools, docs, contract mirrors, and references are excluded.

## Work Guidance

- Keep installed immutable content separate from mutable session state.
- Return typed validation errors suitable for readiness/error screens.

## Verification

- Contract tests cover hash/schema/reference rejection, package mismatch, corrupt saves, backup recovery, and migrations.

## Child DOX Index

- No child AGENTS.md files are currently required.
