# Development automation contract

## Purpose

Own reproducible local verification, contract checks, fixture tooling, and release automation.

## Ownership

- Headless Godot verification and architecture boundary guards.
- Package determinism/schema mirror checks and oracle harness launchers as introduced.
- `package_probe.gd` independently validates and starts an arbitrary local `.realmz2` package without installing or committing it; its output separates manifest, document parse, typed construction, session start, view construction, and representative movement timings.
- `route_acceptance.gd` loads an external package and route, drives trigger programs through the normal session/VM boundary, answers typed interactions, and emits a deterministic local report. It must not embed campaign route records or bypass rules except for its explicit deterministic battle-victory setup.
- `corpus_acceptance.ps1` runs package probes and optional external routes from caller-supplied campaign descriptors; it never discovers or embeds commercial paths.
- Synthetic package provenance and fixture-byte checks used by the aggregate gate.
- `ui-assets/verify-classic-application-media.ps1` validates the complete committed integrated-sound manifest, exact resource keys, provenance/license metadata, byte counts, and hashes; Tier 2 and Tier 3 run it without requiring a Castle checkout.
- `verify_differential_evidence.ps1` validates the rolling functional-differential ledger locally and, when clean reference roots are supplied, checks the pinned external commits, paths, and symbols. Intentional corrections require a stable decision ID plus an existing hash-matched source-observation fixture.
- `verify_application_workflow_inventory.ps1` validates the fixed Classic/host workflow denominator, every public-boundary and differential link, the parity-convergence policy/current batch, optional clean reference roots, and deterministic regeneration of `docs/classic-application-workflow-status.md`. It enforces 3–5 targets, one certification target, owned gaps, baseline totals, and approved archaeology triggers without pretending to measure effort percentages. UI route coverage is derived from the authoritative `UiRouteCatalog`, not incidental router match branches. Use `-Write` only to regenerate the report from the inventory and `-Check` in aggregate gates.
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
- Tier 3 runs `verify.ps1` once per workflow batch, plus source-intelligence validation/regeneration, clean-reference evidence validation, relevant Providence full checks, and one coherent MCP walkthrough.

## Work Guidance

- PowerShell is the primary Windows automation surface. Fail immediately on command errors.
- Every meaningful tool change receives the applicable DOX pass: re-read the nearest `AGENTS.md`, check the allowed scope, preserve repository-relative paths, and report the exact focused or batch-level evidence used.

## Verification

- `tools/verify.ps1` is the aggregate local gate.

## Child DOX Index

- `source-intelligence/AGENTS.md` owns deterministic source indexing, artifact generation, validation, catalog, schema, and HTML template contracts.
- `ui-assets/AGENTS.md` owns exact-commit Classic control import, pinned font acquisition, deterministic slate derivation, and asset manifests.
