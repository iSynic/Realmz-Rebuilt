# Infrastructure adapters contract

## Purpose

Own package loading, schema/hash validation, strict save persistence, and external host adapters.

## Ownership

- `.realmz2` ZIP verification and typed domain construction.
- Strict `.r2save` v4 encoding/decoding, validation, backup rotation, and explicit rejection of older envelopes.
- Installed package discovery, current-revision selection, and capability/readiness reporting.

## Local Contracts

- Treat package and save data as untrusted until all structural, hash, reference, limit, topology, and capability checks pass.
- `.r2save` v4 encodes the typed `SessionSnapshot` and every closed protocol variant as `{kind, version, data}`. Unknown kinds, fields, or versions fail before constructing a session; v1 through v3 are incompatible and have no migration path.
- Character vault revisions preserve all ten Fast Spell bindings as character-owned state. Eligibility rejects bindings whose spell identity is absent from the target package, no longer known by the character, or paired with an invalid power; it never silently clears or substitutes a shortcut.
- Discovery reads the ZIP inventory and verifies manifest/schema/capability metadata without hashing payload bytes or constructing every campaign. Importing an external package performs complete file-integrity and typed-content validation once, installs the exact bytes under the package identity, and atomically writes an app-owned receipt containing the schema, campaign/package identities, compressed archive SHA-256, byte count, and modification identity. Selecting an installed package validates the receipt's cheap file identity and exact manifest identity; a matching disposable runtime-image sidecar may restore the already-verified primitive documents without rehashing the archive. Missing or corrupt sidecars force the complete archive SHA-256 before reparsing and rebuilding them. It does not repeat compiler-level per-document, media, topology, or cross-reference validation on every Play. Any receipt identity mismatch invalidates the installation and requires reinstalling the package.
- Long package validation and installation run in a host-owned worker with detached, mutex-protected progress and cooperative cancellation between integrity items. The worker may use infrastructure adapters only; it never accesses Nodes, presenters, or the active session, and shutdown joins it before process exit.
- A package-install worker retains one repository instance across sequential operations so an unchanged immutable package can reuse its typed in-memory result. A fresh process uses the durable install receipt for app-owned immutable packages; absent receipts are upgraded only after one complete validation, and malformed or mismatched receipts fail explicitly.
- Generic package discovery retains every immutable revision for diagnostics. Installed-campaign discovery exposes only the most recently installed valid revision for each campaign, preserves the Providence-authored manifest name for presentation, collapses equivalent rejected revisions, and leaves older content-hash files untouched.
- Validate Classic opcode support, Scenario Action namespaces, caller contexts, typed arguments, Safe bytecode limits, every program/action reference, and the exact nullable Start Game, Party Death, End Adventure, Shop, and Temple application-hook program references before constructing content.
- Providence verifies deterministic ZIP inventory/order, canonical manifest package hash, schema hash, references, topology, and every file hash while compiling. Runtime import independently repeats those checks for an external package once; ordinary installed startup verifies the app-owned receipt's cheap file identity and manifest identity, restoring an exact versioned runtime image when present and repeating the compressed archive SHA-256 only when that image must be rebuilt.
- The committed Classic character library is a Providence-built application package with a pinned campaign/package identity and adjacent provenance record. It contains stock Race, Caste, spell, appearance, standard item, and only stock-caste-referenced New Scenario supply defaults; it contains no commercial scenario payload. Release exports include it explicitly. Runtime startup trusts its shipped immutable bytes after matching the pinned manifest identity, while external campaign packages retain the ordinary untrusted import/install path.
- Stock Realmz definitions and text are application content. Campaign package decoding resolves stock identities through Rebuilt's pinned application library and accepts package-owned data only for scenario-authored definitions or proven exact-key overrides. Standard spell descriptions are decoded from Rebuilt's bundled Family Jewels catalog by Classic spell ID; blank campaign fields cannot erase them and campaign packages must not become carriers for the stock description table.
- Runtime JSON dictionaries do not cross into the core; validating factories construct typed immutable content, including explicit topology edges/features, random regions, cross-map transitions, direct Simple/Complex/Thief/Timed Encounters, and rule definitions for races, castes, items, spells, monsters, battles, treasures, and shops.
- Player-map construction validates source order, unique Classic IDs zero through nineteen, positive icon sizes, source-map references, exact signed PICT/TEXT identities, exact CICN 138 party media, ordered marker type-plus-ID pairs, and every opcode 29 reference before content becomes playable. Player maps never become alternate playable topology.
- Packages with reachable battles require complete typed battle-terrain sets. Land sets contain exactly active-landlook tiles 0 through 200 plus global combat tiles 201 through 400; dungeon sets contain exactly global tiles 200 through 400. Every tile has an exact 3×3 build, and every map reference must match its level type and effective landlook.
- Every race definition must carry exactly five signed `ageChanges` rows of fifteen integers plus five age ranges. The loader rejects missing or malformed aging rows before constructing immutable `RaceDefinition` content.
- Placed triggers must carry a valid `postActionLocation`; the loader rejects missing destination maps and coordinates outside the authoritative topology. Unplaced XAP programs carry no destination.
- Standard and scenario spells use Castle's packed spell identity at the package boundary. The loader rejects duplicate packed IDs and unresolved cross-domain references before constructing content.
- A monster using a Classic random-weapon table requires every item that table can produce. Package readiness queries the same rules-owned table used by monster construction and rejects missing generated weapon identities before play.
- Every monster definition carries exactly six native item slots. Empty slots remain empty strings; validation must never compact them because slot zero is the physical fallback and slot one is the projectile weapon.
- Every monster definition carries exactly forty signed-byte starting conditions. The loader rejects missing, packed, or out-of-range arrays before immutable content construction.
- Every monster definition also carries its independent Classic name ID, authored bestiary description, and `notOnMenu` flag. These are immutable package facts rather than identities inferred from display names or encounter reachability.
- Imported Providence resource-catalog pictures, icons, sounds, Classic special-land `cicn` overlays, every map-referenced tileset, source-backed shared Classic sounds referenced by reachable instructions, and both native facing variants of every reachable monster `cicn` are compiled as content-addressed package media. A runtime-ready managed or scenario asset with the same Classic resource identity replaces the shared-resource fallback.
- Packages with reachable battles require capability `realmz.presentation.battle-atlas-v1` and exactly one valid `classic-battle-tiles-302` 20×20 atlas. Capability and asset presence must agree; presentation combines that shared lower half with the active landlook rather than accepting an ambiguous resource-ID fallback.
- Realmz 2 packages contain one decoded, role-labelled asset for every selectable Classic portrait 257–376 and tactical icon 9000–9119. Missing or wrong-role appearance data fails readiness before typed content construction.
- Presentation media lookup matches the exact four-character resource type plus signed numeric ID. It preserves case and trailing spaces and never falls back to another type merely because the number matches. Package construction rejects duplicate exact keys before presentation receives a catalog.
- Reject a package when a topology cell references a missing tileset or image overlay, when atlas dimensions disagree with its declared tile grid, or when tileset metadata is incomplete. JSON asset records stop at this boundary; the package adapter constructs core `MediaAsset` values and implements the core `MediaSource` port without exposing archive ownership to presentation.
- Save only at committed session boundaries. Save the whole typed aggregate, including VM and session interactions, post-move/random-region continuation, clock, overlays, action state, and RNG state/draw count; debug RNG traces are not persisted.
- Saves may also contain a pending direct-session monster death macro; its battle, combatant, program, VM request, and RNG position validate as one continuation.
- Write a temporary save, read and validate it, rotate one backup, then atomically replace the slot.
- Save browsing enumerates primary and backup records as detached previews. It classifies structural corruption and campaign/package identity mismatches without exposing paths or mutable envelopes; an enabled preview is still fully validated through replacement-session restore before becoming active.
- Restore failure leaves the current session untouched.
- Save installation is temporary-write, typed readback, one-backup rotation, then same-volume rename; never expose a partially parsed envelope.
- Infrastructure may use Godot filesystem APIs; core and scenario code may not.
- The settings repository encodes and decodes the pure core `PresentationSettings` value. Schema 10 persists Castle's default-on Auto Switch to Melee, default-off Auto Note, Reduced Sound, traveled-area preview, exploration cadence, window mode, interface density, typography, independent effects/music controls, playlist modes, and Classic exploration visibility. Schemas 1 through 9 migrate with source-backed safe defaults and without gameplay-save ownership.
- Packages requiring `realmz.scenario.gdscript-actions-v1` fail readiness until an OS-confined external host exists. No in-process or token-scanned GDScript fallback is permitted.
- Release exports contain runtime resources plus Godot-generated export metadata only; local MCP configuration, addon code, tests, tools, docs, contract mirrors, and references are excluded.

## Work Guidance

- Keep installed immutable content separate from mutable session state.
- `CharacterVaultRepository` owns immutable `.r2char` revisions under `user://characters/<character-id>/`. Reads are untrusted and typed; publishing uses temporary write/readback, one-backup rotation, and atomic replacement. Archive is the only removal operation. Stable IDs may contain interior dots but every path component rejects traversal names, separators, rooted paths, and nonportable characters.
- Vault enumeration validates each record against both its character directory and revision filename. Current-index changes, archive moves, and exact revision recovery remain host-owned transactional operations; presenters receive detached revision and eligibility views only.
- Character-vault records reject battle-scoped character allegiance. A charmed character may exist only inside an active central combat save and must be restored to its base side before publication.
- Vault records retain the complete detached character, including separate racial combat modifiers, trained abilities, two-hand, inventory, and known spells. Older records missing additive nested fields use the same typed character defaults as save restoration.
- Vault eligibility is calculated against the target campaign's stable race, caste, level, item, spell, portrait, and combat-icon identities. Stock portrait and combat-icon IDs resolve through the pinned application character library after an exact scenario role lookup; missing definitions, wrong roles, and authored restrictions still produce explicit reasons, and import never strips or substitutes content.
- Return typed validation errors suitable for readiness/error screens.
- Schema-v3 land maps use `realmz2.compact-cell-rows.v2`. Decode exact Classic boat requirements, blocked-attempt timeclicks, forest semantic, map base scale, and the active landlook's tile-60/tile-147 replacement profiles once at package construction; reject contradictory flags, land-only facts on dungeon maps, or missing land profiles rather than inventing runtime defaults. Scenario-owned Custom 1–3 audio is selected only by its validated `scenarioMusicSlot`, never by resource-key inference.

## Verification

- Contract tests cover hash/schema/reference rejection, package mismatch, explicit legacy-save rejection, corrupt saves, and backup recovery.

## Child DOX Index

- `packages/AGENTS.md` owns package-v3 installation, discovery, decoding, validation, receipts, and bounded cache responsibilities.
