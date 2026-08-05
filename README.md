# Realmz Remake 2.0

Realmz Remake 2.0 is a greenfield Godot 4.7.1 runtime for Providence-authored Realmz campaigns. It models Realmz directly, uses Castle Realmz as the behavioral oracle, and keeps gameplay in a deterministic simulation that is independent of Godot scenes and presentation timing.

This repository intentionally does not load saves or campaign projects from the earlier Realmz Remake. Providence compiles canonical projects into immutable `.realmz2` packages; this runtime validates and executes those packages.

## Current status

The repository is under active construction. The current roadmap and exit gates are in [docs/roadmap.md](docs/roadmap.md). Architectural contracts are in [docs/architecture.md](docs/architecture.md) and the ADRs under `docs/adr`.

## Development

Use Godot 4.7.1 stable. Run the local verification lane from PowerShell:

```powershell
./tools/verify.ps1
```

Godot MCP Pro 1.16.0 is vendored under `addons/godot_mcp`; its Node server remains an external local tool. See [docs/development.md](docs/development.md).

No commercial scenario payloads, extracted assets, user saves, or generated oracle installations belong in this repository.
