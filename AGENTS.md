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
- Use the pinned current Remake as a functional-difference and test donor, then use Castle source or a controlled Castle runtime fixture to adjudicate every Classic-visible difference before implementation.
- Providence is the canonical authoring/compiler system. Runtime packages are immutable compiled inputs.
- Keep simulation deterministic and presentation-independent. Gameplay code must not use Nodes, autoloads, wall-clock time, filesystem APIs, or Godot randomness.
- Keep one authoritative map topology and derive every renderer or navigation cache from it.
- Use Scenario Actions as reusable callable definitions from normal AP and Encounter action timelines; never author executable behavior in a call-site gap.
- Use Godot MCP Pro for editor/runtime inspection and playable-slice verification. Runtime MCP operations must follow `play_scene`.
- Use one Classic-wide UI language: preserve the map/picture stage, right six-character roster, bottom narrative/status well, contextual original bitmap commands, and compact menu hierarchy inside responsive Realmz 2 slate frames. Keep imported pixels intact at 1x/2x, interface density independent from text scale, hidden item facts private, and unimplemented actions disabled with explicit reasons.
- Never use `codex` or `Codex` in branch names.
- Group normal player-visible work into coherent batches of 3–5 related workflows, with one focused-verified commit per workflow. Use the risk-tiered delivery and delegation policy in `docs/development.md`; CI remains comprehensive.
- Sol retains the critical path, architecture and fidelity adjudication, high-risk boundaries, cross-cutting integration, final review/tests/commit, and user conclusions. When a concrete suitable sidecar exists, delegate it under the bounded Luna rules in `docs/development.md`; Luna agents do not commit or push.

## Child DOX Index

- `contracts/AGENTS.md` owns mirrored Providence schemas and contract-drift rules.
- `docs/AGENTS.md` owns architecture, ADRs, fidelity decisions, provenance, and roadmap documentation.
- `src/app/AGENTS.md` owns the composition root and host orchestration.
- `src/core/AGENTS.md` owns the pure Realmz model, rules, topology, clock, RNG, and session state.
- `src/infrastructure/AGENTS.md` owns package, save, validation, and external adapters.
- `src/presentation/AGENTS.md` owns Godot scenes, controls, rendering, animation, and audio.
- `src/scenario/AGENTS.md` owns the scenario VM, Classic instructions, Scenario Actions, capabilities, and runtime API contract.
- `tests/AGENTS.md` owns test categories, fixture provenance, oracle evidence, and copyright boundaries.
- `tools/AGENTS.md` owns local verification and development automation.
- Root-owned files include `project.godot`, `README.md`, `.gitignore`, and repository-level configuration.
