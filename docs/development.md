# Development and verification

Realmz Rebuilt targets Godot 4.7.1. Install Git LFS before cloning so bundled `.realmz2` packages materialize as real ZIP archives rather than pointer files.

```powershell
git lfs install
git clone https://github.com/iSynic/Realmz-Rebuilt.git
cd Realmz-Rebuilt
git lfs pull
```

Open `project.godot` in Godot 4.7.1 and run the main scene. Mobile is the default renderer. Use `--rendering-method gl_compatibility` to exercise the supported OpenGL fallback.

## Find the owner first

Read [the Builder's Manual](builders-manual.md), the nearest feature `README.md`, and the system's entry in [the machine-checked manifest](system-manifest.json).

- `src/game`: definitions, mutable state, pure rules, topology, RNG, detached views
- `src/playthrough`: `GameSession`, typed commands, workflows, continuations, projection
- `src/scenarios`: Classic instructions, Safe Scenario Actions, runtime operations, VM frames
- `src/storage`: package, save, Character Files, and settings repositories
- `src/ui`: scenes, controllers, renderers, audio, animation, editor previews
- `src/app`: startup, navigation, session hosting, platform lifecycle, composition

Change a fact in the lowest boundary that owns its meaning. Do not add a forwarding facade, cross-object private call, dictionary command bus, generic source bucket, or second copy of saved truth to avoid following the existing interface.

## Stable contracts

- Preserve package, save, Character Files, opcode, resource, and user-directory identities unless an explicit migration is designed.
- Keep simulation deterministic and independent of Nodes, wall-clock time, filesystem APIs, and Godot randomness.
- Keep Providence as the scenario authoring/compiler boundary. Runtime packages are immutable compiled inputs.
- Resolve application and scenario content by exact resource type and ID, with a scenario-owned exact-key overlay before application fallback.
- Keep gameplay state out of scenes and presentation state out of saves.
- Move paired `.uid` files and rewrite resource paths atomically when renaming Godot files.

## UI changes

Stable panels, splits, headings, buttons, details, alternate states, and command regions belong in `.tscn` scenes. Controllers bind detached values, connect signals, toggle modes, and populate exported row or card scenes for variable collections. They do not reconstruct the screen hierarchy.

Map, battlefield, dungeon, animation, and effect geometry may remain algorithmic when a node tree would obscure the calculation. Their viewport, camera, layers, materials, masks, and surrounding controls remain scene-authored.

Use Realmz Builder to inspect registered scenes with Wide, Compact, Empty, Long Content, Unavailable, and Error data. Verify the canonical 1280x720 composition and optional 800x600 Compact composition. Editor readability complements runtime play; it does not replace it.

## Classic fidelity

Castle source and controlled Castle runtime fixtures adjudicate Classic-visible differences. Keep source control flow, fixture observation, runtime tests, and ordinary-play evidence distinct. Record a deliberate correction in the fidelity ledger rather than silently changing behavior.

Use targeted archaeology only when a reproduced discrepancy, release blocker, high-risk save/RNG/VM/topology boundary, suspected compiler loss, or certification-campaign ambiguity depends on the answer. Stop when the ordinary behavior is established and the owning public workflow is covered.

The generated [Classic workflow status](classic-application-workflow-status.md) and [gameplay parity status](classic-gameplay-parity-status.md) own their denominators. Edit their source inventories and regenerate them; do not hand-edit generated status.

## Risk-tiered verification

Group normal work into three to five related workflows. Give each workflow a focused, verified commit, then run Tier 2 and the aggregate gate once at batch closeout.

### Tier 1: focused behavior

Run the affected suite or named cases while iterating:

```powershell
./tools/run_tests.ps1 -Suite @("tests/integration/test_inventory_session.gd")
./tools/run_tests.ps1 -Suite @("tests/integration/test_exploration_session.gd") -Case @("fatigue")
```

Every filter must match. Named cases require an owning suite. A timeout is a diagnostic: narrow or investigate the slow case rather than immediately repeating the same command.

Low-risk path and ownership moves additionally require a stale-path scan, `git diff --check`, the architecture ratchet, a complete Godot editor import, and directly affected suites. They do not require a performance run when no hot loop or runtime construction changes.

### Tier 2: workflow boundary

Run the affected suites plus architecture, evidence, inventory, scope, and whitespace checks:

```powershell
./tools/verify_workflow.ps1 -Suite @("tests/presentation/test_classic_ui_system.gd")
```

Regenerate a status report only when its authoritative inventory changed.

### Tier 3: batch closeout

Run the aggregate gate once after the complete batch is assembled:

```powershell
./tools/verify.ps1
```

The aggregate gate imports the project, launches the main scene, runs every typed suite, checks teardown, validates architecture and test budgets, verifies packages, media, exports, schemas, fixtures, bundled scenarios, differential evidence, workflow inventories, gameplay parity, local-path hygiene, and `git diff --check`.

Move directly to Tier 3 for package/schema changes; semantic save, migration, or continuation changes; RNG or VM changes; topology changes; terminal combat/reward sequencing; and application composition-root changes.

## Test admission

A durable automated check should protect one of these responsibilities:

- architecture or wire-contract invariant;
- non-obvious source-backed rule;
- complete public session workflow;
- general presentation lifecycle/layout invariant;
- ordinary campaign certification route.

Map a defect to an existing invariant first. Add a regression test when it protects a distinct durable boundary, not merely because a defect was reported. Do not test private helpers or repeat the same fact at every layer. The enforced test-source ceiling is 20 percent of production source, with at most 1,200 substantive lines per suite.

## Performance

Measure the boundary that changed with the existing startup, package, movement, rendered-runtime, dungeon-transition, combat, or navigation probe. Use three warmed before-and-after samples on the same machine and compare medians.

Reject a core transaction/projection regression exceeding both 5 percent and 0.20 ms, a rendered-frame regression exceeding both 5 percent and 0.50 ms, or a startup/package regression exceeding both 5 percent and 100 ms. Existing absolute budgets also remain binding. Explain or remove export-size or peak-memory growth above 5 percent.

Core timing does not prove draw latency, a two-cell loop does not prove traversal, and automated input does not prove perceived responsiveness. Match the evidence to the user-visible claim.

## Providence preview requests

Providence may compile an unsaved revision to a temporary `.realmz2` and ask a source checkout of Rebuilt to validate and enter one target without installing the package. The version-one request is strict JSON:

```json
{
  "kind": "realmz2.preview-request",
  "formatVersion": 1,
  "packagePath": "C:\\absolute\\temporary\\scenario.realmz2",
  "packageSha256": "64 lowercase hexadecimal characters",
  "target": {"kind": "action-point", "id": "stable trigger id", "mapId": "land:0", "x": 1, "y": 2},
  "partyFixture": "classic-six",
  "rngSeed": 17,
  "isolatedSession": true,
  "resultPath": "C:\\absolute\\temporary\\preview-result.json"
}
```

For a Simple Encounter, `target` is `{"kind":"simple-encounter","id":0}`. A map preview uses `{"kind":"map-location","id":"land:0","mapId":"land:0","x":1,"y":2}`; `id` and `mapId` must be the same canonical map identity, and coordinates are zero-based and map-local. A scrolling preview uses `{"kind":"scrolling-text","id":-200}`, where `id` is the signed identity of an exact scenario-owned `TEXT` resource. A Battle preview uses `{"kind":"battle","id":2}`, where `id` is the nonnegative Classic `Data BD` native identity; it is ready only after the ordinary battle command produces an active combat surface and typed combat request. Unknown kinds, extra fields, stale coordinates, application-fallback text, unsupported fixtures, package hash mismatches, and unavailable targets fail explicitly. Run the contract probe with:

```powershell
godot --headless --path . --script res://tools/development_preview_probe.gd -- C:\absolute\temporary\preview-request.json
```

The probe writes `realmz2.preview-result` format version 1 to `resultPath`. It loads the ordinary application-plus-scenario package boundary, creates a fresh deterministic in-memory party, and enters the requested target through `GameSession`. It never installs the temporary package or opens saves, settings, recent campaigns, or Character Files. The separate interactive host is responsible only for presenting that already-isolated session.

To open the same isolated target in the production Realmz shell, run the export-excluded developer scene:

```powershell
godot --path . --scene res://tools/development_preview_host.tscn -- C:\absolute\temporary\preview-request.json
```

The interactive host uses the same package validator, party fixture, target registry, and result envelope as the headless probe. It starts with default presentation settings and redirects any preview-time save or settings action to scratch paths beside `resultPath`; it does not discover or install campaigns, read Character Files, seed the vault, or change recent-campaign state. The tool scene and its host script are excluded from native exports.

## Before requesting review

- Re-read the nearest feature guidance and update it when ownership or contracts changed.
- Ensure scenes, controllers, model types, tests, and `system-manifest.json` agree.
- Keep the worktree free of `.godot`, `dist`, logs, captures, saves, local paths, personal configuration, and unlicensed content.
- Report the exact checks run and distinguish automated, visual, ordinary-play, and native-platform evidence.
- Note every required platform or campaign check that remains outstanding.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the short public contribution checklist and [the Beta 1 plan](beta-1.md) for release acceptance.
