# DOX framework

- DOX is highly performant AGENTS.md hierarchy installed here
- Agent must follow DOX instructions across any edits

## Core Contract

- AGENTS.md files are binding work contracts for their subtrees
- Work products, source materials, instructions, records, assets, and durable docs must stay understandable from the nearest applicable AGENTS.md plus every parent AGENTS.md above it

## Read Before Editing

1. Read the root AGENTS.md
2. Identify every file or folder you expect to touch
3. Walk from the repository root to each target path
4. Read every AGENTS.md found along each route
5. If a parent AGENTS.md lists a child AGENTS.md whose scope contains the path, read that child and continue from there
6. Use the nearest AGENTS.md as the local contract and parent docs for repo-wide rules
7. If docs conflict, the closer doc controls local work details, but no child doc may weaken DOX

Do not rely on memory. Re-read the applicable DOX chain in the current session before editing.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done.

Update the closest owning AGENTS.md when a change affects:

- purpose, scope, ownership, or responsibilities
- durable structure, contracts, workflows, or operating rules
- required inputs, outputs, permissions, constraints, side effects, or artifacts
- user preferences about behavior, communication, process, organization, or quality
- AGENTS.md creation, deletion, move, rename, or index contents

Update parent docs when parent-level structure, ownership, workflow, or child index changes. Update child docs when parent changes alter local rules. Remove stale or contradictory text immediately. Small edits that do not change behavior or contracts may leave docs unchanged, but the DOX pass still must happen.

## Hierarchy

- Root AGENTS.md is the DOX rail: project-wide instructions, global preferences, durable workflow rules, and the top-level Child DOX Index
- Child AGENTS.md files own domain-specific instructions and their own Child DOX Index
- Each parent explains what its direct children cover and what stays owned by the parent
- The closer a doc is to the work, the more specific and practical it must be

## Child Doc Shape

- Create a child AGENTS.md when a folder becomes a durable boundary with its own purpose, rules, responsibilities, workflow, materials, or quality standards
- Work Guidance must reflect the current standards of the project or user instructions; if there are no specific standards or instructions yet, leave it empty
- Verification must reflect an existing check; if no verification framework exists yet, leave it empty and update it when one exists

Default section order:
- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

## Style

- Keep docs concise, current, and operational
- Document stable contracts, not diary entries
- Put broad rules in parent docs and concrete details in child docs
- Prefer direct bullets with explicit names
- Do not duplicate rules across many files unless each scope needs a local version
- Delete stale notes instead of explaining history
- Trim obvious statements, repeated rules, misplaced detail, and warnings for risks that no longer exist

## Closeout

1. Re-check changed paths against the DOX chain
2. Update nearest owning docs and any affected parents or children
3. Refresh every affected Child DOX Index
4. Remove stale or contradictory text
5. Run existing verification when relevant
6. Report any docs intentionally left unchanged and why

## User Preferences

When the user requests a durable behavior change, record it here or in the relevant child AGENTS.md.

- Build a greenfield Realmz runtime. Do not reproduce Samuel's host architecture or add compatibility paths for its saves and campaigns.
- Model Castle Realmz concepts and behavior directly. Keep Classic behavior as the fixed ruleset and document deliberate fidelity corrections.
- Player Auto and NPC combat decision-making may deliberately improve on Castle, including movement routing, action and weapon selection, spell choice, and ally-safe targeting. Keep every improvement deterministic from the serialized session RNG, rules-legal, presentation-independent, and explicitly documented rather than treating Castle's weak AI as a fixed fidelity requirement. Treat positive tactical scores as relative likelihood weights between viable action categories rather than always selecting the maximum; keep the exact legal target, spell/power/placement, and route deterministic inside the selected category. Forced and single-option actions consume no choice draw. Persistent Auto must yield after each character activation so the player can return any roster member to manual control during an ongoing battle; Escape is the host safety hatch that disables every party Auto toggle and resumes manual control at the next activation boundary.
- Use the pinned current Remake as a functional-difference and test donor, then use Castle source or a controlled Castle runtime fixture to adjudicate every Classic-visible difference before implementation.
- Providence is the canonical authoring/compiler system. Runtime packages are immutable compiled inputs.
- Presentation settings remember only the stable identity of the last successfully started campaign. After the front-door video and application shell are stable, resolve that identity through ordinary discovery and prepare it on the existing cancellable package worker. Retain at most one prepared candidate; matching selection claims it, different selection supersedes it with foreground priority, and all package trust checks remain unchanged.
- Preserve Castle's resource-chain model directly in Providence and Rebuilt: exact `(resource type, ID)` lookup with scenario ownership before application fallback. Semantic roles may annotate and validate a resource but must never decide whether its authored bytes are preserved or create duplicate role-specific payloads; content-address identical bytes once.
- Rebuilt owns the complete stock Realmz application library. Every rule record, display string, font, control image, sound, PICT/CICN, and other resource shipped by Realmz belongs in Rebuilt once, not in each scenario package. A scenario package contains only content the original scenario owned plus normalized references to stock identities. It may replace a stock exact resource key only where Castle's scenario-before-application resource chain proves that override. Providence validates scenario references against the pinned application library and never copies application-owned content into campaign output.
- Ship the 13 scenarios distributed with Castle Realmz as provenance-pinned CC BY-NC-SA 4.0 packages, except that City of Bywater uses the project-owner-designated source snapshot until Castle adopts it byte-for-byte. Keep the synthetic package test-only, and never bundle other commercial, user-owned, tutorial, test, template, or duplicate scenario payloads.
- Public releases use a sanitized one-root-commit `main` with `.realmz2` files in Git LFS. Original Rebuilt code is GPL-3.0-or-later; Realmz-derived scenarios, assets, and the exact six Realmz 7.1.2 starter characters remain CC BY-NC-SA 4.0 with pinned provenance. Public source excludes every DOX/`AGENTS.md` file, graph/codemap state, local tool configuration, internal process records, editor state, logs, captures, and private history. Tags rebuild and launch Windows, Linux, and macOS artifacts and create only a draft prerelease; the project owner manually publishes after review.
- Treat source-proven stock application sound cues as Classic-visible behavior. Request the exact application-owned sound ID from the action or transition owner; keep explicit workspace-entry cues presentation-only, and never infer a cue merely because a matching sound exists in the bank.
- Keep simulation deterministic and presentation-independent. Gameplay code must not use Nodes, autoloads, wall-clock time, filesystem APIs, or Godot randomness.
- Keep one authoritative map topology and derive every renderer or navigation cache from it.
- Ordinary adjacent movement may attach one nonserialized presentation delta to its detached map view. Simulation, saves, replay traces, and package data never retain that hint; unknown events, restores, map or LOS changes, transitions, and interactions rebuild from authoritative state. Presentation retains decoded map art and visible-cell state, projects one nonserialized guard cell beyond every visible edge, updates only the entering strip and changed overlays, and never queues missed held steps. Copy-on-write map patches must allocate typed chunks before crossing an 8x8 chunk boundary so camera movement can never outrun a failed entering strip.
- Use Scenario Actions as reusable callable definitions from normal AP and Encounter action timelines; never author executable behavior in a call-site gap.
- Use Godot MCP Pro for editor/runtime inspection and playable-slice verification. Runtime MCP operations must follow `play_scene`.
- Use one Classic-wide UI language: preserve the map/picture stage, right six-character roster, bottom narrative/status well, contextual original bitmap commands, and compact menu hierarchy inside responsive Realmz 2 slate frames. The exploration footer spans the application width as World commands, the fixed-width narrative/status well, and Party commands; do not stretch narrative merely because the command surface grows. Footer commands use one Rebuilt slate compositor with a centered icon stage and a separate live Black Chancery caption band; never display a donor hotkey or embedded caption as part of that recomposed control. Design and accept the canonical application at 1280x720. The only secondary composition is an optional 800x600 Classic 4:3 mode with a square gameplay viewport; intermediate or larger resolutions may scale/reflow but are not separate design targets. Keep imported pixels intact at 1x/2x, interface density independent from text scale, hidden item facts private, and unimplemented actions disabled with explicit reasons. Source-backed Classic typography is the default; Preferences must retain a readable modern-font alternative without changing simulation.
- Use Godot's Mobile rendering method as the default native renderer so supported Windows, Linux, and macOS systems use the RenderingDevice path. Keep the same project runnable through the explicit `gl_compatibility`/OpenGL command-line override for older or problematic hardware. Renderer changes may not alter nearest-filtered Classic pixels, simulation, projection, or save/package contracts, and any default change requires equal-workload canonical and native performance evidence plus visual verification.
- Keep Godot engine boot plain black without engine branding. The first runtime frame contains only the project-owner-supplied Rebuilt card over opaque black plus its source-backed entry cue. After that frame draws, load the menu dependencies, prepare and start the retained silent intro-video decoder behind the opaque card, and request the complete gameplay scene through Godot's threaded resource loader. Hold the card for three seconds, play the full exit cue while it remains visible, then remove the card and black field, reveal the already-playing application front door, and start its music in the same callback. Temporary menu coverage suspends but does not reload the OGV; final front-door teardown releases it, and the independent MP3 remains demand-loaded. Keep scenario, saved-adventure, and Character Files actions gated until background construction finishes, keep Quit available, and expose Retry only for an actual load failure. Do not add routine loading captions or custom worker-thread parsing before handing off through public shell routes.
- Populate the Character Files browser from one validated revision cache keyed by stable character identity and revision hash. Add and drag/drop import detached clones from that cache, invalidate it after vault mutation or refresh, retain the six party-slot controls across setup edits, and prepare each revision/portrait drag cursor before a physical drag begins.
- Keep ordinary scenario narration text-only and ordinarily visible without scrolling. Do not spend its fixed measure on generic continuation, Auto Note, or journal helper copy; put authored Yes/No and indexed responses in a compact floating pane immediately above it. Use transient application-owned indicators for committed save and journal activity without inventing an autosave policy.
- Every spell-selection surface uses the source-backed gradient `Spell Level` identity and level-colored `Level #` parent filters before its level-filtered list; hidden-level selections persist. Level-up spell learning uses the available application height rather than inheriting roster height. Leaving Treasure with unclaimed wealth retains the exact Treasure workspace beneath a locked confirmation modal so Return restores the same task state.
- Every reversible application workspace must expose a persistent visible Back, Done, or Cancel action appropriate to its route or local task. Escape remains an equivalent shortcut, never the only discoverable exit.
- Never use `codex` or `Codex` in branch names.
- Group normal player-visible work into coherent batches of 3–5 related workflows, with one focused-verified commit per workflow. Use the risk-tiered delivery and delegation policy in `docs/development.md`; CI remains comprehensive.
- Use the parity-convergence amendment in `docs/development.md`: every batch declares an ordinary-play certification target, prioritizes missing/partial and target-campaign gaps over deeper functional edge cases, and limits archaeology to approved discrepancy, blocker, high-risk, compiler-loss, or target-campaign ambiguity triggers.
- Execute scenario and gameplay parity in this order: certify AOGM, certify War in the Sword Lands, then select each legally available scenario by recomputed unique-feature coverage gain. After corpus certification, close unused stock opcodes, spell signatures, and gameplay workflows with synthetic fixtures until every denominator entry has a final disposition.
- Sol retains the critical path, architecture and fidelity adjudication, high-risk boundaries, cross-cutting integration, final review/tests/commit, and user conclusions. When a concrete suitable sidecar exists, delegate it under the bounded Luna rules in `docs/development.md`; Luna agents do not commit or push. Never fork a long-lived task's accumulated context into a child agent. Use a self-contained non-forked prompt, and suspend delegation entirely when the parent task or child initialization exceeds the storage limits in `docs/development.md`.

## Child DOX Index

- `contracts/AGENTS.md` owns mirrored Providence schemas and contract-drift rules.
- `docs/AGENTS.md` owns architecture, ADRs, fidelity decisions, provenance, and roadmap documentation.
- `src/app/AGENTS.md` owns the composition root and host orchestration.
- `src/core/AGENTS.md` owns the pure Realmz model, rules, topology, clock, RNG, and session state.
- `src/infrastructure/AGENTS.md` owns package, save, validation, and external adapters.
- `src/presentation/AGENTS.md` owns Godot scenes, controls, rendering, animation, and audio.
- `src/scenario/AGENTS.md` owns the scenario VM, Classic instructions, Scenario Actions, capabilities, and runtime API contract.
- `src/session/AGENTS.md` owns the pure transaction coordinator joining core state/rules to scenario execution.
- `tests/AGENTS.md` owns test categories, fixture provenance, oracle evidence, and copyright boundaries.
- `tools/AGENTS.md` owns local verification and development automation.
- Root-owned files include `project.godot`, `README.md`, `.gitignore`, and repository-level configuration.
