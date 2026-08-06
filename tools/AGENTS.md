# Development automation contract

## Purpose

Own reproducible local verification, contract checks, fixture tooling, and release automation.

## Ownership

- Headless Godot verification and architecture boundary guards.
- Package determinism/schema mirror checks and oracle harness launchers as introduced.
- `package_probe.gd` independently validates and starts an arbitrary local `.realmz2` package without installing or committing it.
- `route_acceptance.gd` loads an external package and route, drives trigger programs through the normal session/VM boundary, answers typed interactions, and emits a deterministic local report. It must not embed campaign route records or bypass rules except for its explicit deterministic battle-victory setup.
- Synthetic package provenance and fixture-byte checks used by the aggregate gate.

## Local Contracts

- Tools must resolve the repository root from their own path and avoid machine-specific committed paths.
- Do not modify source-reference worktrees or commercial campaign installations.
- Keep local absolute MCP/server configuration untracked.
- Serialize headless verification and live MCP editor sessions because MCP Pro temporarily owns editor-only autoload settings.

## Work Guidance

- PowerShell is the primary Windows automation surface. Fail immediately on command errors.

## Verification

- `tools/verify.ps1` is the aggregate local gate.

## Child DOX Index

- No child AGENTS.md files are currently required.
