# Development automation contract

## Purpose

Own reproducible local verification, contract checks, fixture tooling, and release automation.

## Ownership

- Headless Godot verification and architecture boundary guards.
- `verify_architecture.ps1` enforces the dependency matrix, including the session layer, rejects live protocol dictionary rematerialization outside strict request/continuation/execution-context serializers and explicitly detached event serialization sites, rejects the retired dictionary interaction/targeting command bus, keeps restore validation out of `GameSession`, prevents session coordinators from regaining an owner/private-result backchannel, requires composed party-setup responsibilities, prevents infrastructure media catalogs from crossing the app-view boundary, and keeps route-domain rendering/controllers out of `ClassicScreenRouter` behind explicit scene-owned hosts.
- Package determinism/schema mirror checks and oracle harness launchers as introduced.
- `package_probe.gd` exercises the public package repository and session boundary for an arbitrary local `.realmz2` package without installing or committing it; its output separates public package load, session start, view construction, and representative movement timings.
- `movement_performance_probe.gd` prepares six synthetic public-session characters inside a caller-supplied package, locates a trigger-free corridor, and reports warm transaction/projection p95 latency without embedding campaign data or machine-local paths. Its 60-step alternating run must keep every ordinary and source-owned hourly-fatigue step on the incremental projection path and fail above the 50 ms combined p95 contract; it does not claim Godot frame/draw latency, which remains MCP evidence.
- `combat_performance_probe.gd` constructs a deterministic six-character battle from a caller-supplied package and reports synchronous battle setup, detached combat-view construction, staged memorized-spell option/reason construction, full-state checkpoint, Auto-command timing, scheduled playback duration, and bounded package-media read timing. It accepts an optional Classic battle ID, embeds no campaign path or payload, and separates simulation/projection work from the presentation timeline rather than claiming Godot draw latency.
- `verify_hotspot_test_budget.ps1` and `hotspot-test-budget.json` measure substantive GDScript deterministically. Hash-bound grandfather entries may not grow and are removed after responsibility-based extraction; final caps are 1,000 production lines per file, 150 per function, 1,200 per test suite, 7,900 total test lines, and 20 percent of production. Tier 2 and Tier 3 both enforce the ratchet.
- `package_discovery_probe.gd` measures manifest-only campaign discovery through the public repository without loading package graphs.
- `route_acceptance.gd` loads an external package and route, creates a deterministic six-member application-valid party when the package opens at fresh-party setup, drives trigger programs through the normal session/VM boundary, answers typed interactions, and emits a deterministic local report. It must not embed campaign route records or bypass rules except for its explicit deterministic party and battle-victory setup.
- `corpus_acceptance.ps1` runs package probes and optional external routes from caller-supplied campaign descriptors; it never discovers or embeds commercial paths.
- Synthetic package provenance and fixture-byte checks used by the aggregate gate.
- `ui-assets/verify-classic-application-media.ps1` validates the complete committed integrated-sound manifest, exact resource keys, provenance/license metadata, byte counts, and hashes plus every generated-chrome manifest path, dimension, and hash; Tier 2 and Tier 3 run it without requiring a Castle checkout.
- `ui-assets/sync-classic-application-text.ps1` extracts stock player-spell descriptions from the pinned Family Jewels negative `STR#` resources into Rebuilt's deterministic application-text catalog. It verifies the clean Castle commit and exact source hash; it never writes scenario package content.
- `verify_differential_evidence.ps1` validates the rolling functional-differential ledger locally and, when clean reference roots are supplied, checks the pinned external commits, paths, and symbols. Intentional corrections require a stable decision ID plus an existing hash-matched source-observation fixture.
- Source-intelligence resolution treats duplicated qualified symbols as ambiguous/external instead of emitting a resolved edge with no target; aggregate regeneration must never crash on such ambiguity.
- `verify_application_workflow_inventory.ps1` validates the fixed Classic/host workflow denominator, every public-boundary and differential link, the parity-convergence policy/current batch, optional historical maintenance-pause records, optional clean reference roots, and deterministic regeneration of `docs/classic-application-workflow-status.md`. It enforces 3–5 targets, one certification target, owned gaps, baseline totals, and approved archaeology triggers without pretending to measure effort percentages. UI route coverage is derived from the authoritative `UiRouteCatalog`, not incidental router match branches. Use `-Write` only to regenerate the report from the inventory and `-Check` in aggregate gates.
- `verify_gameplay_parity_inventory.ps1` deterministically regenerates or checks the complete Classic opcode denominator and the pinned application spell/effect denominator. Its committed JSON and Markdown artifacts include application-owned mechanical families and per-casting-context executable/pending counts while keeping discovery, compiler preservation, semantic runtime testing, route proof, and ordinary-play certification separate; commercial scenario additions remain local untracked sidecars.
- `analyze_gameplay_feature_reports.ps1` validates local Providence feature-report sidecars against the mirrored schemas, rejects scenario payload and machine-local paths, and ranks candidate campaigns by deterministic coverage gain against supplied certified baselines. When given the committed gameplay-parity inventory, it also requires exact normalized agreement with every application spell signature and an executable disposition for every reported opcode identity. Optional local hash-keyed metadata supplies the player-priority and reliable-completion-route tie-breakers after feature gain, high-risk boundaries, and compiler-loss diagnostics. It emits only hashes, counts, scores, normalized feature gains, capability counts, and tie-break values; it never discovers or commits commercial reports.
- `run_tests.ps1` is the Tier 1 focused runner. It streams Godot output with heartbeats, accepts suite and named-case filter arrays, reports timing, defaults to a 120-second process budget, and verifies launched process-tree termination on timeout. `stream_process.ps1` supplies the same live-output behavior to Tier 3 without imposing the focused timeout. The Tier 2 helper, `verify_workflow.ps1`, uses the focused runner before adding the architecture guard, differential and workflow-inventory validators, scope/local-path checks, and `git diff --check`. Neither focused helper invokes the aggregate gate or MCP by default; an unchanged timed-out command must be narrowed or investigated rather than repeated.

## Local Contracts

- Tools must resolve the repository root from their own path and avoid machine-specific committed paths.
- Do not modify source-reference worktrees or commercial campaign installations.
- Keep local absolute MCP/server configuration untracked.
- The vendored MCP plugin must skip initialization in headless editor processes so verification cannot claim or remove a live interactive editor's temporary runtime-service autoloads.
- The aggregate headless test gate captures process output and fails on ObjectDB leak or retained-resource teardown diagnostics, even when Godot exits zero.
- Keep the universal macOS export preset on ETC2/ASTC texture import; `verify_export_contract.ps1` enforces the exporter requirement.
- An action-list route step may execute its named compiled XAP/ED3 program directly when the record has no map topology. Reports must keep that distinction from placed AP reachability.
- Tier 2 report regeneration is allowed only when the authoritative workflow inventory changed; never use `-Write` for an unrelated workflow edit and never hand-edit the generated status report.
- Tier 2 scope checks permit only synthetic test packages and the exact committed application Character Files catalog. Every other `.realmz2` remains a local/install artifact and fails the workflow gate.
- Tier 3 runs `verify.ps1` once per workflow batch, plus source-intelligence validation/regeneration, clean-reference evidence validation, relevant Providence full checks, and one coherent MCP walkthrough.

## Work Guidance

- PowerShell is the primary Windows automation surface. Fail immediately on command errors.
- PowerShell scripts must parse under Windows PowerShell 5.1 from UTF-8-without-BOM checkouts; keep generated Markdown literals ASCII-safe unless the script explicitly reads or writes UTF-8 with a declared encoding.
- Every meaningful tool change receives the applicable DOX pass: re-read the nearest `AGENTS.md`, check the allowed scope, preserve repository-relative paths, and report the exact focused or batch-level evidence used.

## Verification

- `tools/verify.ps1` is the aggregate local gate.

## Child DOX Index

- `source-intelligence/AGENTS.md` owns deterministic source indexing, artifact generation, validation, catalog, schema, and HTML template contracts.
- `ui-assets/AGENTS.md` owns exact-commit Classic control import, pinned font acquisition, deterministic slate derivation, and asset manifests.
