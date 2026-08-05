# Delivery roadmap

Status values describe current evidence, not intent. A phase completes only when its exit gate is proven.

## Phase 0 — Foundation and tooling (completed)

- Godot project and explicit composition root.
- DOX hierarchy, architecture docs, ADRs, provenance lock, test runner, CI, MCP integration.
- Clean pinned Castle and Remake reference worktrees.

Exit evidence: the application launched through MCP Pro 1.16.0 on Godot 4.7.1; runtime UI discovery and simulated input changed observed state; a 960×600 smoke screenshot was captured; the final editor error list was empty; headless verification passed; pinned clean reference worktrees were created; and the DOX hierarchy was re-read and reconciled.

## Phase 1 — Package contract and deterministic kernel (in progress)

- Providence-authoritative `.realmz2` schema/exporter and byte-identical runtime mirror.
- Validating loader, immutable models, `GameSession`, state, clock, RNG, typed boundaries, and save v1.
- Tiny synthetic Providence fixture with one party/map/message/AP/saveable mutation.

Exit: repeated exports are byte-identical; load, deterministic transitions, save/reload, and RNG replay match.

## Phase 2 — Authoritative world and exploration (pending)

- Land/dungeon topology, overlays, movement, LOS, searches, secrets, doors, transitions, random rectangles, time, triggers.
- Topology-derived 2D presenter, minimap, and debug overlays.

Exit: the fixture exercises exploration and mutations through one topology with MCP visual/input verification.

## Phase 3 — Scenario VM and Actions (pending)

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
