# Realmz Rebuilt

Realmz Rebuilt is a greenfield Godot 4.7.1 runtime for Providence-authored Realmz campaigns. It models Realmz directly, uses Castle Realmz as the behavioral oracle, and keeps gameplay in a deterministic simulation that is independent of Godot scenes and presentation timing.

This repository intentionally does not load saves or campaign projects from the earlier Realmz Remake. Providence compiles canonical projects into immutable `.realmz2` packages; this runtime validates and executes those packages.

## Current status

The greenfield kernel, package loader, topology, Scenario VM/Actions, responsive Classic-wide shell, source-backed AOGM/War route lanes, and optional topology-derived dungeon 3D are implemented. Native three-platform release jobs are configured but remain certification evidence only after they run. The current roadmap and exit gates are in [docs/roadmap.md](docs/roadmap.md). Architectural contracts are in [docs/architecture.md](docs/architecture.md), the [UI strategy](docs/ui-strategy.md), and the ADRs under `docs/adr`.

## Development

Use Godot 4.7.1 stable. Run the local verification lane from PowerShell:

```powershell
./tools/verify.ps1
```

Godot MCP Pro 1.16.0 is vendored under `addons/godot_mcp`; its Node server remains an external local tool. See [docs/development.md](docs/development.md).

The 13 scenarios distributed with Castle Realmz are bundled under CC BY-NC-SA 4.0 with pinned source/compiler provenance. City of Bywater uses the project-owner-designated production snapshot pending its adoption by Castle; the other twelve use the pinned Castle source. No other commercial or user-owned scenario payloads, extracted assets, user saves, or generated oracle installations belong in this repository. The synthetic package remains test-only and is excluded from release exports.

Realmz Rebuilt includes provenance-checked integrated Classic media and Castle-distributed scenarios under the terms recorded in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt). Scenario-owned media remains in immutable `.realmz2` packages and may override the matching exact Classic resource key.
