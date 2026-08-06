# Development automation contract

## Purpose

Own reproducible local verification, contract checks, fixture tooling, and release automation.

## Ownership

- Headless Godot verification and architecture boundary guards.
- Package determinism/schema mirror checks and oracle harness launchers as introduced.
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
