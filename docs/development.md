# Development and verification

## Required tools

- Godot 4.7.1 stable, typed GDScript runtime.
- PowerShell for local automation.
- Godot MCP Pro addon 1.16.0 from the vendored `addons/godot_mcp` directory.
- The Godot MCP Pro Node server kept externally; configure its machine-specific absolute path through the untracked MCP configuration.

The project-local `.mcp.json` contains machine-specific absolute paths and stays untracked. Do not set a fixed WebSocket port; use automatic discovery.

The project uses `application/config/use_custom_user_dir` with the stable name `RealmzRemake2`. This keeps Godot 4.7.1 and MCP Pro 1.16.0 on the same file-IPC `user://` path and gives save repositories a predictable root.

## Source intelligence

The repository also maintains an offline source-intelligence snapshot under docs/codemap/. It embeds exact local source and documentation text, source spans, DOX ownership, tests, flows, retrieval chunks, and conservative resolved/unknown relationships. Open docs/codemap/codemap.html directly for the browser encyclopedia, or consume intelligence.json and chunks.jsonl from an agent. Use ./tools/source-intelligence/validate.ps1 for the read-only artifact check. The aggregate gate regenerates it automatically; local verification leaves regenerated files for review and CI fails if the committed snapshot is stale.

## Local gate

```powershell
./tools/verify.ps1
```

The aggregate gate imports the project headlessly, validates all scripts, runs typed GDScript tests, checks forbidden core dependencies, verifies the mirrored schema and synthetic package hashes/provenance, and runs `git diff --check`.

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

Do not run the headless verification lane while a live MCP editor session is open. MCP Pro injects editor-only autoloads and removes them when an editor process exits; serializing these lanes prevents a headless process from removing the live editor's runtime inspector settings. The MCP scene-save command can also emit Godot progress-dialog errors while handling its deferred request; restart the editor before the final clean error inspection after MCP-authored scene changes.

Release presets exclude `addons/godot_mcp`, `.mcp.json`, tests, tools, docs, contract mirrors, local artifacts, and ignored reference worktrees. `tools/verify_export_contract.ps1` enforces those exclusions and the ETC2/ASTC import required by the universal macOS preset; Godot's generated export metadata remains part of a valid pack.

The repository defines `Windows Desktop`, `Linux`, and `macOS` release presets. CI runs the same import, typed test, architecture, contract, and export gates on native runners; a configured matrix is not cross-platform evidence until those jobs pass.

`tools/corpus_acceptance.ps1` accepts caller-supplied package/route/report descriptors so commercial campaign locations remain external. `tools/route_acceptance.gd` may execute a named compiled macro directly for an unplaced ED3/XAP checkpoint; that proves the macro path and never upgrades it to placed-map reachability.

## Reference repositories

Reference repositories are read-only inputs unless work is explicitly assigned there. Never copy a dirty worktree. The pinned identities are recorded in `docs/references.lock.json`; create clean isolated worktrees before porting source or fixtures.

## Evidence and copyright

Each Classic fidelity test identifies whether its evidence is source/control-flow, Castle runtime, runtime unit/integration, or a live certified route. Synthetic fixtures are preferred. Commercial scenario data, extracted assets, user saves, and generated oracle installations remain local and untracked.

Packages declaring `realmz.scenario.gdscript-actions-v1` are rejected until a platform has an independently confined process host with passing abuse, timeout, memory, filesystem, network, process, reflection, and state-size tests. Safe Scenario Actions require no such host.
