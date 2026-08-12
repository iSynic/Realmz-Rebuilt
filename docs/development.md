# Development and verification

## Required tools

- Godot 4.7.1 stable, typed GDScript runtime.
- PowerShell for local automation.
- Godot MCP Pro addon 1.16.0 from the vendored `addons/godot_mcp` directory.
- The Godot MCP Pro Node server kept externally; configure its machine-specific absolute path through the untracked MCP configuration.

The project-local `.mcp.json` contains machine-specific absolute paths and stays untracked. Do not set a fixed WebSocket port; use automatic discovery.

The project uses `application/config/use_custom_user_dir` with the stable name `RealmzRemake2`. This keeps Godot 4.7.1 and MCP Pro 1.16.0 on the same file-IPC `user://` path and gives save repositories a predictable root.

## Risk-tiered delivery and delegation

Normal player-visible work is planned as a coherent batch of 3–5 related workflows. Each workflow has one focused-verified commit. In the roadmap, a rolling pass means this workflow batch; the roadmap does not create a new rolling pass for a tiny edit, and a tiny edit does not pay the batch closeout gate by itself.

Use the lowest tier that covers the changed boundary:

- **Tier 1 — focused behavior:** run only the affected test suite or suites. Do not run the aggregate gate, source intelligence/codemap, MCP, or unrelated routes. Every meaningful change still receives a DOX review; update a contract only when its durable behavior or ownership changed.
- **Tier 2 — focused workflow:** run the affected suites, the architecture check when product source changed, the differential and application-workflow inventory validators, scope/local-path checks, `git diff --check`, and the applicable DOX review. Regenerate `docs/classic-application-workflow-status.md` only when its authoritative inventory changed. Do not run the aggregate gate or MCP by default.
- **Tier 3 — batch closeout:** once per batch, run the full `tools/verify.ps1` gate, source-intelligence validation/regeneration, clean-reference evidence validation, relevant Providence full checks, and one coherent MCP walkthrough.

Move directly to Tier 3 for package or schema changes; save, migration, or continuation changes; RNG or VM changes; topology changes; terminal combat or reward sequencing; and composition-root ownership changes. CI remains comprehensive regardless of the local tier.

At batch start, Sol identifies the critical path and any suitable sidecars. If suitable sidecars exist, use no more than two `gpt-5.6-luna` agents at `xhigh`, each with a detailed self-contained prompt and a disjoint write scope. Luna may perform bounded archaeology, settled regression tests, isolated UI or fixture implementation, mechanical evidence/DOX work, review, and parallel verification. Sol retains architecture, ambiguous Castle/fidelity adjudication, high-risk boundaries, the critical path, cross-cutting integration, final review/tests/commit, and final conclusions.

Every Luna prompt states the objective; repository and base; DOX requirements; read and write scope; settled interfaces and evidence; non-goals; tests; ambiguity handling; and final-report format. Luna must not commit or push, modify references, broaden scope, or make fidelity decisions unless explicitly authorized. Sol reviews every result, and Luna evidence never upgrades audit status without Sol validation.

### Parity convergence

The workflow inventory schedules parity work; the differential ledger adjudicates only the behavior a scheduled workflow needs. Each batch records 3–5 workflow targets, its baseline commit and delivery-state counts, the gaps it owns, and at least one ordinary-play certification target. Batch closeout reports changes in missing, partial, functional, and certified counts. Assertion totals and differential-case totals are supporting evidence, not delivery progress by themselves.

Use this priority order:

1. AOGM blocker or ordinary-play certification gap.
2. Missing Classic workflow.
3. Major partial workflow reachable in AOGM.
4. War prerequisite.
5. Broader Classic parity gap.
6. Rare or unreachable Castle edge case.

Plan effort at approximately 60 percent ordinary-play acceptance and presentation, 25 percent missing or partial workflow implementation, and 15 percent targeted archaeology. This is a planning allocation, not a machine-derived time or commit metric. Prefer closing a missing or partial workflow over adding another edge case to one already functional.

Archaeology begins or continues only when at least one trigger applies:

- Ordinary play reproduces a discrepancy.
- A reachable campaign or release blocker depends on the answer.
- Save, RNG, VM, authoritative topology, terminal combat, or another named high-risk boundary is involved.
- Providence may be dropping or changing authored data.
- Source ambiguity affects a target certification campaign.

Stop once complete source flow establishes the ordinary behavior and focused tests pass. Use a controlled Castle runtime fixture only when source remains ambiguous at one of those triggers. Record rare, unreachable, malformed-data, and non-blocking quirks as deferred parity gaps; do not investigate them merely because they exist. A functional workflow may receive further archaeology only when certification or a target campaign depends on it.

At batch start, update `currentBatch` in the authoritative workflow inventory and regenerate its status report. At batch closeout, update workflow evidence and gaps, regenerate the report, and state both the functional and certified count deltas. If a prerequisite changes the selected batch, record the new rationale and baseline rather than silently drifting into another domain.

## Source intelligence

The repository also maintains an offline source-intelligence snapshot under docs/codemap/. It embeds exact local source and documentation text, source spans, DOX ownership, tests, flows, retrieval chunks, and conservative resolved/unknown relationships. Open docs/codemap/codemap.html directly for the browser encyclopedia, or consume intelligence.json and chunks.jsonl from an agent. Use ./tools/source-intelligence/validate.ps1 for the read-only artifact check. The aggregate gate regenerates it automatically; local verification leaves regenerated files for review and CI fails if the committed snapshot is stale.

## Local gate

```powershell
./tools/verify.ps1
```

The aggregate gate imports the project headlessly, validates all scripts, runs typed GDScript tests, checks forbidden core dependencies, verifies the mirrored schema and synthetic package hashes/provenance, checks the differential ledger and application workflow inventory, and runs `git diff --check`.

Regenerate the deterministic application-completeness report with `./tools/verify_application_workflow_inventory.ps1 -Write`; normal verification uses `-Check` and fails if the report is stale. Clean Castle, Remake, and Providence roots may be supplied to validate every external path and symbol against the pinned commits.

For Tier 1 focused characterization, run `godot --headless --path . --script res://tests/test_runner.gd -- --suite <path-fragment>`; repeat `--suite <path-fragment>` to select several suites in one process. Every supplied filter must match, and a suite runs only once when filters overlap. For Tier 2, use `./tools/verify_workflow.ps1 -Suite @("<fragment-a>", "<fragment-b>")`; it performs the focused suites, conditional architecture check, differential/inventory checks, scope checks, and whitespace check. Clean-reference roots are a Tier 3 input. Release and Tier 3 closeout evidence uses the complete suite.

The Tier 2 helper is not a substitute for the batch closeout gate. Do not add unrelated suites, invoke MCP, or regenerate source-intelligence artifacts merely to make a focused workflow appear comprehensive.

## UI verification

The canonical UI contract is `docs/ui-strategy.md`. `tests/presentation/classic_ui_fixture_gallery.gd` supplies nominal, empty, loading, error, unavailable, and oversized cases for all routes and interaction kinds. Verify 800x600, 960x600, 1280x720, 1600x900, and 1920x1080, then repeat dense screens with 150 percent text and each explicit interface density. Check map dominance, roster visibility, textbox/action reachability, menu overflow, wrapping, scroll reachability, focus order/restoration, Back order, exact 1x/2x control art, and that a pending interaction blocks both map and route input.

Content images must be inspected with nearest-neighbor filtering. Missing media must show its neutral diagnostic fallback rather than a guessed file. Item checks must include unidentified content to prove that identified names, descriptions, values, and curse relationships remain hidden.

The committed Classic control corpus is reproducible from tracked source commits with `./tools/ui-assets/sync-classic-ui-assets.ps1 -SourceRepository <clean-remake-checkout> -CastleRepository <clean-castle-checkout>`. The importer reads Git object data, not donor working files; Remake controls copy exact PNG bytes, while built-in map CICNs are decoded from their pinned Castle resource fork and validated by source/output hashes. `./tools/ui-assets/sync-fonts.ps1` downloads the pinned OFL font bytes. `build-classic-surfaces.ps1` imports a selected SpriteCook source image; `./tools/ui-assets/build-classic-surfaces.ps1 -RebuildFromCommittedSurface` deterministically rebuilds its seamless runtime tile and tiled frame kit offline while preserving source provenance. Normal verification is offline and validates committed hashes; it does not rerun network or donor imports.

## Godot MCP Pro workflow

After the initial bootstrap, change project settings through MCP/editor project-setting operations rather than editing `project.godot` directly. For each playable slice:

1. Open or build the scene using editor tools.
2. Inspect editor errors.
3. Call `play_scene`.
4. Simulate input or run a test scenario.
5. Inspect runtime state and screen text.
6. Capture screenshots.
7. Call `stop_scene`.

For interaction slices, inspect the pending request ID before responding, save while the request is pending, resume it once, restore that save, and resume it again. This proves that presentation is returning typed responses and that the issuing VM frame—not a UI callback—is the continuation authority.

Runtime operations before `play_scene` are invalid. Use CLI discovery with `node <server>/build/cli.js --help` when MCP tools are not exposed in the current client.

The vendored MCP plugin does not initialize in a headless editor process. This keeps headless verification from claiming and removing the live editor's temporary runtime-service autoloads, so focused and aggregate checks may run while the MCP editor remains open. The MCP scene-save command can still emit Godot progress-dialog errors while handling its deferred request; restart the editor before the final clean error inspection after MCP-authored scene changes.

Release presets exclude `addons/godot_mcp`, `.mcp.json`, tests, tools, docs, contract mirrors, local artifacts, and ignored reference worktrees. `tools/verify_export_contract.ps1` enforces those exclusions and the ETC2/ASTC import required by the universal macOS preset; Godot's generated export metadata remains part of a valid pack.

The repository defines `Windows Desktop`, `Linux`, and `macOS` release presets. CI runs the same import, typed test, architecture, contract, and export gates on native runners; a configured matrix is not cross-platform evidence until those jobs pass.

`tools/corpus_acceptance.ps1` accepts caller-supplied package/route/report descriptors so commercial campaign locations remain external. `tools/route_acceptance.gd` may execute a named compiled macro directly for an unplaced ED3/XAP checkpoint; that proves the macro path and never upgrades it to placed-map reachability.

## Reference repositories

Reference repositories are read-only inputs unless work is explicitly assigned there. Never copy a dirty worktree. The pinned identities are recorded in `docs/references.lock.json`; create clean isolated worktrees before porting source or fixtures.

## Evidence and copyright

Each Classic fidelity test identifies whether its evidence is source/control-flow, Castle runtime, runtime unit/integration, or a live certified route. Synthetic fixtures are preferred. Commercial scenario data, extracted assets, user saves, and generated oracle installations remain local and untracked.

Packages declaring `realmz.scenario.gdscript-actions-v1` are rejected until a platform has an independently confined process host with passing abuse, timeout, memory, filesystem, network, process, reflection, and state-size tests. Safe Scenario Actions require no such host.
