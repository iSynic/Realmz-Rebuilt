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

- Write public player-facing project copy in the owner's direct, approachable voice, leading with what players can do. In that copy, refer to Castle as "the Realmz Castle codebase."
- Build a greenfield Realmz runtime. Do not reproduce Samuel's host architecture or add compatibility paths for its saves and campaigns.
- Model Castle Realmz concepts and behavior directly. Keep Classic behavior as the fixed ruleset and document deliberate fidelity corrections.
- Player Auto and NPC combat decision-making may deliberately improve on Castle, including movement routing, action and weapon selection, spell choice, and ally-safe targeting. Keep every improvement deterministic from the serialized session RNG, rules-legal, presentation-independent, and explicitly documented rather than treating Castle's weak AI as a fixed fidelity requirement. Treat positive tactical scores as relative likelihood weights between viable action categories rather than always selecting the maximum; keep the exact legal target, spell/power/placement, and route deterministic inside the selected category. Forced and single-option actions consume no choice draw. Persistent Auto must yield after each character activation so the player can return any roster member to manual control during an ongoing battle; Escape is the host safety hatch that disables every party Auto toggle and resumes manual control at the next activation boundary.
- Use the pinned current Remake as a functional-difference and test donor, then use Castle source or a controlled Castle runtime fixture to adjudicate every Classic-visible difference before implementation.
- Providence is the canonical authoring/compiler system. Runtime packages are immutable compiled inputs.
- The accepted Providence conversion toolchain is one hash-locked immutable build whose executables report their embedded source identity. Imported Classic projects may be `ready-with-warnings` when optional legacy references are unavailable or unsafe optional records are quarantined, but package integrity, type/schema safety, unique identities, required application composition, essential startup data, and any valid native content omitted by the compiler remain hard failures. Deferred data is checked only if execution selects it; failure halts gameplay and saving with exact source context and never infers replacement content.
- Presentation settings remember only the stable identity of the last successfully started campaign. After the front-door video and application shell are stable, resolve that identity through ordinary discovery and prepare it on the existing cancellable package worker. Retain at most one prepared candidate; matching selection claims it, different selection supersedes it with foreground priority, and all package trust checks remain unchanged.
- Preserve Castle's resource-chain model directly in Providence and Rebuilt: exact `(resource type, ID)` lookup with scenario ownership before application fallback. Semantic roles may annotate and validate a resource but must never decide whether its authored bytes are preserved or create duplicate role-specific payloads; content-address identical bytes once.
- Rebuilt owns the complete stock Realmz application library. Every rule record, display string, font, control image, sound, PICT/CICN, and other resource shipped by Realmz belongs in Rebuilt once, not in each scenario package. A scenario package contains only content the original scenario owned plus normalized references to stock identities. It may replace a stock exact resource key only where Castle's scenario-before-application resource chain proves that override. Providence validates scenario references against the pinned application library and never copies application-owned content into campaign output.
- Use Castle's source-authentic RLMZ APPL icon family for the Godot project and native exports. Preserve the native 16-by-16 and 32-by-32 pixels, derive 48-by-48 and larger members from the detailed 32-by-32 icon with nearest-neighbor scaling, and retain the reviewed multi-size Windows and macOS containers.
- Ship the 13 scenarios distributed with Castle Realmz as provenance-pinned CC BY-NC-SA 4.0 packages, except that City of Bywater uses the project-owner-designated source snapshot until Castle adopts it byte-for-byte. Keep the synthetic package test-only, and never bundle other commercial, user-owned, tutorial, test, template, or duplicate scenario payloads.
- Public releases use a sanitized one-root-commit `main` with `.realmz2` files in Git LFS. Original Rebuilt code is GPL-3.0-or-later; Realmz-derived scenarios, assets, and the exact six Realmz 7.1.2 starter characters remain CC BY-NC-SA 4.0 with pinned provenance. Public source excludes every DOX/`AGENTS.md` file, graph/codemap state, local tool configuration and editor-automation addon, internal process records, editor state, logs, captures, and private history. Realmz Builder and the reproducible verification/conversion tools remain public project tooling. Tags rebuild and launch Windows, Linux, and macOS artifacts. A new tag creates a draft prerelease for owner review; refreshing an existing release preserves its draft, prerelease, and Latest state.
- Treat source-proven stock application sound cues as Classic-visible behavior. Request the exact application-owned sound ID from the action or transition owner; keep explicit workspace-entry cues presentation-only, and never infer a cue merely because a matching sound exists in the bank.
- Keep simulation deterministic and presentation-independent. Gameplay code must not use Nodes, autoloads, wall-clock time, filesystem APIs, or Godot randomness.
- Keep one authoritative map topology and derive every renderer or navigation cache from it.
- Ordinary adjacent movement may attach one nonserialized presentation delta to its detached map view. Simulation, saves, replay traces, and package data never retain that hint; unknown events, restores, map or LOS changes, transitions, and interactions rebuild from authoritative state. Presentation retains decoded map art and visibility state, projects one nonserialized guard cell beyond every visible edge, updates only the entering strip and changed overlays, and never queues missed held steps. Every projected map cell withheld by exploration visibility uses the default-on byte-exact project-owner fog tile, with a host preference that replaces it with Castle's opaque black: never-seen cells on authored LOS maps and non-LOS cells outside both the current Classic window and remembered discovery. Current LOS may keep changing for gameplay, but leaving it never re-conceals revealed terrain; decorative surround art remains only outside projected map cells. Copy-on-write map patches must allocate typed chunks before crossing an 8x8 chunk boundary so camera movement can never outrun a failed entering strip.
- Use Scenario Actions as reusable callable definitions from normal AP and Encounter action timelines; never author executable behavior in a call-site gap.
- Use Godot MCP Pro for editor/general runtime inspection; its runtime operations must follow `play_scene`. The owned Realmz Runtime Testing Bridge is the game-aware fixture and journey route. Live adventures permit observation and validated checkpoint export only; automated input and direct invocation require visibly identified isolated fixtures. Keep ordinary gameplay, actual UI-control execution, and direct invocation as distinct proof modes. Castle mirrors use a separate pinned instrumentation worktree, native loaders, and a preparation-time shared RNG checkpoint; unsupported capabilities and unexplained differences never establish parity.
- Use one Classic-wide UI language: preserve the map/picture stage, right six-character roster, bottom narrative/status well, contextual original bitmap commands, and compact menu hierarchy inside responsive Realmz 2 slate frames. The exploration footer spans the application width as World commands, the fixed-width narrative/status well, and Party commands; do not stretch narrative merely because the command surface grows. Footer commands use one Rebuilt slate compositor with a centered icon stage and a separate live Black Chancery caption band; never display a donor hotkey or embedded caption as part of that recomposed control. Design and accept the canonical application at 1280x720. The only secondary composition is an optional 800x600 Classic 4:3 mode with a square gameplay viewport; intermediate or larger resolutions may scale/reflow but are not separate design targets. Keep imported pixels intact at 1x/2x, interface density independent from text scale, hidden item facts private, and unimplemented actions disabled with explicit reasons. Source-backed Classic typography is the default; Preferences must retain a readable modern-font alternative without changing simulation.
- Display scaling defaults to the existing responsive composition. Optional whole-window integer scaling retains a 1280x720 logical application with centered black margins; optional world-canvas integer zoom keeps the responsive UI and offers 1x–4x 32-pixel map and battle tiles; optional Fill uniformly scales the whole application and explicitly expands its logical stage beyond the ordinary 16:9 ultrawide limit while preserving roster and narrative measure. Below 1280x720, whole-window modes use the compact composition. Pixel-art smoothing is independently default-off and applies one retained xBRZ pass only to enlarged composed surfaces; presentation settings never enter saves or campaign packages.
- CRT filtering is independently default-off. Preferences retain CRT-Pi or CRT-Lottes and World canvas or Whole window choices while off. The same curated Godot shader ports serve Mobile/Vulkan and OpenGL Compatibility, disable curvature, omit the phosphor mask below 2x, and run after xBRZ through a retained GPU intermediate only when both effects apply.
- Support controller-only access across the player experience through one active-pad owner, focus navigation, tap-and-confirm action/workspace radials, combat previews, explicit transfer destinations, an embedded scenario file browser, and a built-in modal QWERTY editor. Default bindings follow physical button positions with automatic Xbox, PlayStation, and Switch-style prompts plus an override; retain simultaneous mouse/keyboard use, configurable primitive bindings, 25-percent stick dead zones with release hysteresis, 350/100-millisecond UI repeat, and neutral acknowledgement after disconnect or focus loss. Do not add a virtual mouse, vibration, platform-keyboard dependency, or a second gameplay-command path.
- Party roster typography must be legible at native application size. Give complete names and race/caste dedicated room, use one consistent size for numeric stats including armor, and accommodate long HP/SP values without clipping or shrinking individual fields. Use a more legible face where ornamental lettering cannot remain readable. Display complete source portraits at native 1x size (44-by-44 for the stock portrait family), without cropping, shrinking, or stretching them to fit the row. Keep effects in a hover/focus helper when inline text competes with core facts. Review distinct Classic and revised-layout mockups before implementation; visual acceptance must inspect representative full identities and large numeric values at 1x, independently of test results or reviewer scores.
- Use Godot's Mobile rendering method as the default native renderer so supported Windows, Linux, and macOS systems use the RenderingDevice path. Keep the same project runnable through the explicit `gl_compatibility`/OpenGL command-line override for older or problematic hardware. Renderer changes may not alter nearest-filtered Classic pixels, simulation, projection, or save/package contracts, and any default change requires equal-workload canonical and native performance evidence plus visual verification.
- Keep Godot engine boot plain black without engine branding. The first runtime frame contains only the project-owner-supplied Rebuilt card over opaque black plus its source-backed entry cue. After that frame draws, load the menu dependencies, prepare and start the retained silent intro-video decoder behind the opaque card, and request the complete gameplay scene through Godot's threaded resource loader. Hold the card for three seconds, play the full exit cue while it remains visible, then remove the card and black field, reveal the already-playing application front door, and start its music in the same callback. Temporary menu coverage suspends but does not reload the OGV; final front-door teardown releases it, and the independent MP3 remains demand-loaded. Keep scenario, saved-adventure, and Character Files actions gated until background construction finishes, keep Quit available, and expose Retry only for an actual load failure. Do not add routine loading captions or custom worker-thread parsing before handing off through public shell routes.
- Populate the Character Files browser from one validated revision cache keyed by stable character identity and revision hash. Add and drag/drop import detached clones from that cache, invalidate it after vault mutation or refresh, retain the six party-slot controls across setup edits, and prepare each revision/portrait drag cursor before a physical drag begins.
- Persist ordered equipped-instance identity in `.r2save` v5 and Character Files v2. Runtime loading rejects older save and character revisions without silent migration, inference, overwrite, or deletion. The pinned Realmz 7.1.2 starter converter emits v2 directly; an explicit offline maintainer conversion may preserve selected testing Character Files as new v2 revisions from retained inventory order only after a complete vault backup and readback validation.
- For the pinned Half Truth media-only revision change, offer an explicit Update Save action that verifies both archives and unchanged gameplay documents, restores against the current package, and writes a separately named copy while preserving the original and backup. Never generalize package-hash rebinding or silently update a save.
- Keep ordinary scenario narration text-only and ordinarily visible without scrolling. Do not spend its fixed measure on generic continuation, Auto Note, or journal helper copy; put authored Yes/No and indexed responses in a compact floating pane immediately above it. Use transient application-owned indicators for committed save and journal activity without inventing an autosave policy.
- Every spell-selection surface uses the source-backed gradient `Spell Level` identity and level-colored `Level #` parent filters before its level-filtered list; hidden-level selections persist. Level-up spell learning uses the available application height rather than inheriting roster height. Leaving Treasure with unclaimed wealth retains the exact Treasure workspace beneath a locked confirmation modal so Return restores the same task state.
- Every reversible application workspace must expose a persistent visible Back, Done, or Cancel action appropriate to its route or local task. Escape remains an equivalent shortcut, never the only discoverable exit.
- Retail builds retain physical F12 from the front door through active play as a presentation-only Diagnostics menu for the default-off AP and random-rectangle map overlay. The shared host admits both raw key events and an edge-latched physical-key fallback so an exported input-map miss cannot suppress it or double-toggle it. Warp, no-clip, party restoration, encounter or battle injection, forced victory, event logging, and the console remain debug-build-only; every optional diagnostic toggle defaults off and changes only by explicit user choice.
- Organize the runtime around the human-facing `app`, `game`, `playthrough`, `scenarios`, `storage`, and `ui` boundaries. Reserve `Classic` for source-backed Castle behavior, data, media, or evidence; use ordinary product names for shells, screens, navigation, and components. Stable editable layout belongs in `.tscn` scenes, while scripts bind data, coordinate behavior, and create genuinely dynamic collections. Rename internal code decisively without aliases while preserving serialized IDs, packages, saves, Character Files, and the stable user-data directory.
- Never use `codex` or `Codex` in branch names.
- Push approved public changes directly after required verification; do not create pull requests unless the user requests one. Run the same six Verify/Export checks on a `release/**` preparation branch before fast-forwarding protected `main`; preserve branch protections and required checks.
- Group normal player-visible work into coherent batches of 3–5 related workflows, with one focused-verified commit per workflow and one full aggregate gate at batch closeout. Low-risk path or ownership moves use stale-reference, architecture-ratchet, Godot-import, and directly affected existing-suite checks per commit; do not repeatedly pay Tier 2 or Tier 3 inside the same batch unless a high-risk boundary changes. Use the public risk-tiered delivery policy in `docs/development.md`; this root contract owns internal delegation rules. CI remains comprehensive.
- Freeze architecture, maintainability, and exact test-source ceilings for the duration of a feature or compatibility batch and its release preparation. Incidental reductions create headroom but do not lower a ceiling mid-batch; ratchet ceilings downward only in an explicitly scoped architecture/refactor closeout so dependent work rebases once.
- Choose regression tests by risk and durable contract value. A defect fix does not require a new regression test when existing focused coverage and direct verification adequately prove the repair; preserve the enforced overall test-source budget.
- Use the failure-first AP policy in `docs/development.md`: prioritize reported misfires and shared defects, then untested high-risk behavior, then meaningful variants across caller contexts and outcomes. Broaden representatives across all 13 pinned bundled scenarios. Existing workflow and gameplay inventories remain authoritative denominators; static opcode presence is not runtime coverage. Full campaign certification remains a separate track and does not gate cross-scenario AP testing.
- Use the [upstream TypeSafe skill](https://raw.githubusercontent.com/typesafe-ai/skills/main/skills/typesafe-ai/SKILL.md) and its current documentation when evaluating or implementing TypeSafe/Jev assistance for this project. Consulting the skill does not itself authorize a hosted-service integration or change the Castle evidence requirements.
- Keep only one automated Realmz fixture open by default. Close superseded fixtures gracefully before launching a replacement; retain their checkpoints and failure evidence. A bounded comparison may temporarily use a second engine, which must close when its capture finishes. Never close the player's unowned adventure or editor.
- Execute full scenario and gameplay certification in this order: certify AOGM, certify War in the Sword Lands, then select each legally available scenario by recomputed unique-feature coverage gain. After corpus certification, close unused stock opcodes, spell signatures, and gameplay workflows with synthetic fixtures until every denominator entry has a final disposition. Use tooling or MCP only for an immediate blocker or credible cumulative savings across identified upcoming cases; record expected implementation and verification effort and savings, prefer existing CLI recipes and checkpoints, and never make capability-matrix completion a bug-closure gate.
- Sol retains the critical path, architecture and fidelity adjudication, high-risk boundaries, cross-cutting integration, final review/tests/commit, and user conclusions. When a concrete suitable sidecar exists, use a bounded self-contained Luna task with explicit read/write scope, non-goals, verification, and ambiguity escalation; Luna agents do not commit or push. Never fork a long-lived task's accumulated context into a child agent, and suspend delegation when task initialization or duplicated context creates material storage pressure.

## Child DOX Index

- `addons/realmz_builder/AGENTS.md` owns the public editor-only scene preview and maintainer-navigation plugin.
- `contracts/AGENTS.md` owns mirrored Providence schemas and contract-drift rules.
- `docs/AGENTS.md` owns architecture, ADRs, fidelity decisions, provenance, and roadmap documentation.
- `src/app/AGENTS.md` owns the composition root and host orchestration.
- `src/game/AGENTS.md` owns the pure Realmz model, rules, topology, clock, RNG, and session state.
- `src/storage/AGENTS.md` owns package, save, validation, and external adapters.
- `src/ui/AGENTS.md` owns Godot scenes, controls, rendering, animation, and audio.
- `src/scenarios/AGENTS.md` owns the scenario VM, Classic instructions, Scenario Actions, capabilities, and runtime API contract.
- `src/playthrough/AGENTS.md` owns the pure transaction coordinator joining core state/rules to scenario execution.
- `tests/AGENTS.md` owns test categories, fixture provenance, oracle evidence, and copyright boundaries.
- `tools/AGENTS.md` owns local verification and development automation.
- Root-owned files include `project.godot`, `README.md`, `.gitignore`, and repository-level configuration.
