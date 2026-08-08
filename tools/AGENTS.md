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
- `verify_differential_evidence.ps1` validates the rolling functional-differential ledger locally and, when clean reference roots are supplied, checks the pinned external commits, paths, and symbols.

## Local Contracts

- Tools must resolve the repository root from their own path and avoid machine-specific committed paths.
- Do not modify source-reference worktrees or commercial campaign installations.
- Keep local absolute MCP/server configuration untracked.
- Serialize headless verification and live MCP editor sessions because MCP Pro temporarily owns editor-only autoload settings.
- Keep the universal macOS export preset on ETC2/ASTC texture import; `verify_export_contract.ps1` enforces the exporter requirement.
- An action-list route step may execute its named compiled XAP/ED3 program directly when the record has no map topology. Reports must keep that distinction from placed AP reachability.

## Work Guidance

- PowerShell is the primary Windows automation surface. Fail immediately on command errors.

## Verification

- `tools/verify.ps1` is the aggregate local gate.

## Child DOX Index

- `source-intelligence/AGENTS.md` owns deterministic source indexing, artifact generation, validation, catalog, schema, and HTML template contracts.
- `ui-assets/AGENTS.md` owns exact-commit Classic control import, pinned font acquisition, deterministic slate derivation, and asset manifests.
