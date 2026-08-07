# Delivery roadmap

Status values describe current evidence, not intent. A phase completes only when its exit gate is proven.

## Phase 0 — Foundation and tooling (completed)

- Godot project and explicit composition root.
- DOX hierarchy, architecture docs, ADRs, provenance lock, test runner, CI, MCP integration.
- Clean pinned Castle and Remake reference worktrees.

Exit evidence: the application launched through MCP Pro 1.16.0 on Godot 4.7.1; runtime UI discovery and simulated input changed observed state; a 960×600 smoke screenshot was captured; the final editor error list was empty; headless verification passed; pinned clean reference worktrees were created; and the DOX hierarchy was re-read and reconciled.

## Phase 1 — Package contract and deterministic kernel (completed)

- Implemented: additive Providence `.realmz2` exporter, deterministic ZIP/JSON/hashes, desktop target/report, authoritative schema, byte-identical runtime mirror, and a 3×3 synthetic package generator.
- Implemented: independent ZIP/hash/capability/reference/topology validation into typed Realmz content; direct map/AP/Classic-action models; deterministic session, party/state, clock, QuickDraw-compatible RNG and traces; detached save envelope and transactional save repository.
- Implemented evidence: repeated Providence exports compare byte-for-byte; runtime accepts the generated package and rejects a valid-ZIP stale-hash mutation; deterministic search/save/reload resumes the same RNG branch and state revision.
Exit evidence: repeated Providence exports are byte-identical; the runtime independently accepts the generated package and rejects a valid-ZIP stale-hash mutation; seed 1 produces the verified QuickDraw/Castle search roll 52; save/reload preserves the session revision, one-minute clock advance, RNG state, and draw count; and failed restore leaves the active session untouched. Through MCP Pro, the composition root loaded the package, committed the search through simulated input, observed the expected runtime state, saved `mcp-phase1`, and captured the 960×600 loaded-session screenshot. The final editor error list was empty and the full 43-assertion verification suite passed.

## Phase 2 — Authoritative world and exploration (completed)

- Implemented: Providence normalization of land and packed dungeon representations into explicit cells, directional edges/features, random regions, and Layout transitions; strict independent runtime construction and validation.
- Implemented: typed world overlays, movement, deterministic pathfinding, LOS/visibility, search, secrets, doors, transitions, random rectangles, clock advancement, trigger execution, and terrain replacement through one topology.
- Implemented: a `GameView`-only Classic 2D presenter with topology-derived minimap and movement/LOS/trigger debug facts.

Exit evidence: the synthetic three-map fixture exercises message AP execution, terrain replacement, random-region gating, hidden-secret blocking/discovery, directional dungeon secrets, door opening, land transition, pathfinding, visibility, and save/reload through one topology. The 93-assertion suite passes across six suites. MCP Pro keyboard/mouse input traversed the message AP, search roll 52, secret, and transition; restart/restore retained map, coordinate, clock, RNG state/draw count, and overlays; the 960×600 topology/minimap screenshot was inspected; and a fresh editor inspection reported zero errors.

## Phase 3 — Scenario VM and Actions (completed)

- Implemented: a serializable, session-owned VM with preserved Classic instructions, signed GOSUB, CODE 111/112 stack behavior, XAP replacement, Simple Encounter yields, one runtime API, and explicit unsupported behavior.
- Implemented: compiled Safe Scenario Actions with typed calls, persistent state, private helpers, bounded flow/arrays/steps, separate Classic/Safe frame limits, and save/resume at interaction boundaries.
- Implemented: Providence ordinary Action calls and generated call editors, project-wide Scenario Action library, Safe bytecode compilation, derived export readiness, and removal of visible scripting tiers, gameplay profiles, behavior anchors, and sandbox creation from the normal 2.0 path.

Exit evidence: the synthetic route executes AP opcode -4 to a serializable Simple Encounter request, selected result message, `CallScenarioAction`, Classic opcode 39 to an XAP, and CODE 111 return as one ordered trace. Save/reload reproduces the pending request and exact continuation. The 132-assertion runtime suite passes across seven suites; Providence passes 905 frontend tests plus its Rust exporter, typecheck, lint, architecture, module-size, production-build, and cargo-check gates. Repeated Phase 3 exports are byte-identical. MCP Pro exercised the pending-save, response, restore, repeated response, and final route state with a clean editor error inspection. Castle source/control-flow evidence and the precise proof boundary are recorded in `docs/scenario-vm-evidence.md`.

## Phase 4 — Realmz gameplay domains (completed)

- Implemented: direct race, caste, item, spell, monster, battle, treasure, shop, and Complex/Thief/Timed Encounter models with independently validated package construction.
- Implemented: fixed character, condition/time, inventory/economy, combat, magic, monster, and combat-flow rules; save-owned domain state; packed standard/scenario spell identities; opcode 7/8 program mutation; opcode 36 equipment escrow; and stateful opcode 122 fumble behavior.
- Implemented evidence: the 452-assertion suite covers rules, package construction, domain mutation, RNG ordering, save/restore, VM routing, and explicit error paths. A bounded hash-labelled Assault on Giant Mountain inventory declares 58 active normalized opcodes; every one has one owner, passes package readiness, and dispatches without top-level fallback. This is content-inventory evidence, not live-route proof.

Exit: every active capability needed by the synthetic fixture and Assault on Giant Mountain has executable source-backed behavior with no fallback or silent no-op.

Exit evidence: Providence commit `364755324fae1685b82bbf0c751572045ee6888d` passes its Rust library/exporter/example checks, 321 library tests, frontend typecheck, and production build. The runtime's full gate passes 452 assertions across eight suites plus schema, fixture-provenance, architecture, export-exclusion, and whitespace checks. A fresh MCP Pro editor session reported zero errors; the main scene played, exposed the expected runtime tree, accepted simulated mouse input, changed the observed status, captured a 960×600 frame, and stopped cleanly. Phase 4 domain behavior is proven by deterministic headless tests; the current minimal host does not yet expose those domain screens, which is Phase 5 work.

## Phase 5 — Classic shell and first campaign (route-certified; presentation fidelity ongoing)

- Implemented: Classic-first 2D shell with campaign discovery/install, party creation, exploration HUD, character/inventory/spell views, typed encounter/combat/shop/temple/bank presenters, package pictures/audio, settings, and save/load surfaces.
- Scope note: those are functional routes and surfaces, not a claim that the current shell reproduces the density, composition, interaction affordances, or finish of the Classic Realmz UI. Presentation fidelity remains active work even though the bounded AOGM route gate passed.
- Implemented: source-backed random-rectangle continuation, active-combat intent lockout, save v3 migration, Castle-correct AP post-action destinations, and deterministic synthetic interaction/save routes. The runtime gate passes 531 assertions across eight suites.
- Package/route evidence: a fresh local Providence export of Assault on Giant Mountain independently validates and starts with 21 decoded media assets. Package hash `7561aa2d2f1c2acf4dc57bc12cef1d79049473a2e9bd19fe8c6e377acf087e84` and route hash `b84ff7d68d2d203cb03aca65f94600d4f7c87e01054d8b9a97aba6d68ef19a95` remain local-only evidence; no campaign payload is committed. The route passes opening presentation, Battle 60, Baron briefing/macro, Battle 274, four fortress tile mutations, quest 17, rewards 68/467/625, final report, and final position land 0 (84,8).
- Compiler evidence: Providence commit `a06f2ef152139dfd3fccfc5e563ba9ee58b62d3a` passes 323 Rust library tests with one audit test ignored, frontend typecheck, production build, and `cargo check`.
- MCP evidence: Godot MCP Pro discovered the unfixed port automatically, opened and inspected the main scene, started the synthetic campaign, created the party, entered the typed random-surprise request, saved it as `quick`, declined it, loaded the save, observed the identical prompt and options again, and accepted the restored decline response. A 960×600 frame was captured. A fresh post-fix editor session repeated project/scene inspection, play, runtime text inspection, screenshot capture, and stop with zero editor errors.

Exit: a fresh export completes the certified route with no unsupported active mechanic or save/reload divergence.

Exit evidence: the source-backed route completes through the ordinary 2.0 session/VM API with no fallback, the synthetic suite covers save/reload at its typed interaction boundaries, and the compiler/runtime gates above pass. This certifies the bounded completion spine; it does not claim exhaustive Castle parity for every optional branch.

## Phase 6 — Corpus, releases, and extensions (implemented; cross-platform certification pending)

- Implemented: Windows, Linux, and macOS export presets plus three-runner verify/export CI matrices. Release exports exclude MCP, tests, references, and local evidence.
- Implemented: optional Classic dungeon 3D whose floor, edges, doors, secrets, stairs, and columns are projected from the same `MapView` facts as the 2D map. No second collision or discovery model exists.
- Implemented: explicit rejection of packages requiring `realmz.scenario.gdscript-actions-v1`. Safe packages remain portable; an in-process or token-scanned GDScript fallback was not introduced.
- Implemented: generic external corpus probing/routing, expanded source-backed opcode ownership, held-over ally combat with serializable Castle body-count selection, serializable battle-round/death macros, and Providence reachability retention for direct opcode 88/89 monster references.
- Local campaign evidence: a fresh War in the Sword Lands package at hash `4509fcda9f3684292b5406c151b7108979f4f6211eb1ee198b808ce798e464dd` passes all eight external route stages and observes Battles 377, 473, 474, and 212 before ending at land 16 (78,36) with quest flags 1, 42, and 75. Route hash `fa08b47bd53e0f506333c3c488ccb609b7387fc324b7784586b88d9899e5b1d3`; package, route, and report remain local-only.
- Compiler evidence: Providence commit `d8a958c1bfa7f2e3ee344c7f33f5db95be05024c` retains direct ally monster definitions, preserves Classic column-major land storage, separates negative-land `cicn` overlays from base terrain, and packages every referenced map atlas, including a normalized Classic dungeon composition atlas. Its focused ten-test Realmz 2.0 exporter gate passes. Runtime unit/integration coverage currently passes 774 assertions across nine suites.
- Current AOGM visual/performance evidence: local package hash `ae346e44c4983277725139270653a389be7bb995a3c69b2525f1f6f2450de8fb` independently validates with 80 media assets. Its land 0 base layer matches all 8,100 established reference cells, start (48,15) resolves to tile 155, and 59 special cells use separate overlays. A 960×600 MCP capture shows coherent paths, shore/earth, walls, forest, rocks, and buildings at native 32×32 size with normal-play diagnostics disabled in the clipped 530×452 map viewport. The view exposes gold passable and muted blocked cardinal cues plus click/hold and arrow/WASD movement. AOGM view construction measured 12–17 ms, and cold full package validation/construction measured about 7.0 seconds. The runtime suite passes 774 assertions across nine suites. This does not replace the earlier route package's `live-route` evidence until that route is rerun against the new hash.
- Local release-pack evidence: Windows, Linux, and macOS presets each produce a 497,592-byte Safe runtime PCK with SHA-256 `530c3d07f020fa90ee0cb9da5223086d8d1d745b052795665643f65b33494b5a`; inspection of Godot's export inventory found no MCP configuration/addon, tests, tools, docs, contract mirrors, references, or GitHub workflow entries.
- MCP evidence: the 1.16.0 doctor check passed; automatic port discovery inspected the Godot 4.7.1 project and scene tree; a fresh editor reported zero errors; the main scene played; runtime inspection observed `Pure session boundary online`; simulated mouse input loaded the synthetic package and changed that status to `Loaded realmz2-synthetic-fixture • land:0 1,1 • seed 1`; a 960×600 frame was captured; the post-input editor error list remained empty; and the scene stopped cleanly.

Exit: Safe packages are cross-platform deterministic, certified routes pass, 2D/3D agree, and unsupported sandbox requirements reject cleanly.

Remaining exit evidence: execute the configured native-binary verify/export matrices on actual Windows, macOS, and Linux runners. The byte-identical cross-preset PCK is local packaging evidence, not proof that each native executable launches. The implementation does not claim Phase 6 certification until those jobs pass; additional campaign routes expand corpus confidence without weakening the completed AOGM and War route boundaries.
