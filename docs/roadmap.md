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

## Phase 3 — Scenario VM and Actions (in progress)

- Serializable Classic VM, AP/XAP/GOSUB/encounters/yields and one session runtime API.
- Safe Scenario Actions and ordinary Providence timeline calls; no visible scripting modes or behavior anchors.

Exit: AP to encounter to result to XAP/Scenario Action to return survives every save boundary and matches Castle fixtures.

## Phase 4 — Realmz gameplay domains (pending)

- Character, inventory/economy, combat, magic, monster/AI, lifecycle, and active opcode ownership.

Exit: every active capability needed by the synthetic fixture and Assault on Giant Mountain has executable source-backed behavior with no fallback or silent no-op.

## Phase 5 — Classic shell and first campaign (pending)

- Complete Classic-first 2D shell and local Providence export of Assault on Giant Mountain.
- Deterministic completion-critical route checkpoints.

Exit: a fresh export completes the certified route with no unsupported active mechanic or save/reload divergence.

## Phase 6 — Corpus, releases, and extensions (pending)

- Expanded Castle/campaign corpus, Windows/macOS/Linux gates, optional OS-confined GDScript Action host, optional topology-derived 3D.

Exit: Safe packages are cross-platform deterministic, certified routes pass, 2D/3D agree, and unsupported sandbox requirements reject cleanly.
