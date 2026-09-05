# Human-centered architecture

Realmz Rebuilt is organized so a contributor can begin with a visible feature, locate its scene and controller, follow its typed command into the playthrough, find the owning rules and state, and reach the relevant tests without private project history. Structural implementation and local performance certification are complete. The published Beta 1 predates this overhaul; the architecture update remains blocked until unfamiliar-maintainer, ordinary-play, native-platform, and hosted-update acceptance also pass.

Use [the Builder's Manual](builders-manual.md) for the newcomer tour, [the system manifest](system-manifest.json) for machine-checked ownership, [the architecture record](architecture-migration.md) for current boundaries, and [the roadmap](roadmap.md) for remaining release work.

## Design principles

- Organize code by the game concept a maintainer recognizes, not by framework-shaped buckets or the order in which the prototype was built.
- Use `app`, `game`, `playthrough`, `scenarios`, `storage`, and `ui` as the stable top-level boundaries.
- Keep immutable definitions, mutable state, pure rules, detached views, workflows, scene controllers, renderers, repositories, codecs, and catalogs distinguishable by name and responsibility.
- Keep deterministic simulation in pure objects. Use Godot Nodes for scenes, lifecycle, signals, timers, input, audio, and rendering.
- Author stable UI hierarchy in `.tscn` scenes. Instantiate exported row or card scenes for variable collections. Keep genuinely algorithmic map, battlefield, dungeon, and effect geometry in named presenters.
- Preserve public package, save, Character Files, opcode, resource, RNG, and user-directory contracts during internal reorganization.
- Prefer direct public collaborators over facade chains and cross-object private calls.
- Make the repository explain itself through local READMEs, feature guides, scene previews, the system manifest, and owning tests.

## Structural acceptance

The architecture-overhaul verifier currently reports zero for every final target:

- production files over 600 substantive lines;
- functions over 60 substantive lines;
- top-level classes over 40 total methods or 20 public methods;
- cross-object private calls;
- generic preload aliases;
- major UI surfaces without editable scenes or production-bound previews;
- placeholder shell-mode scenes;
- missing or undeclared feature directories;
- production files loose at a source-boundary root.

Every declared feature directory contains a public `README.md`. The system manifest names each system's guide, entry points, public interfaces, tests, and performance probes. The maintainability gate separately rejects compressed statements, missing purpose headers, stale or unclassified runtime control construction, class/file naming mismatches, and obsolete route scenes.

## Scene acceptance

The application shell, Character, Character Files, Allies, Bestiary, Inventory, Spells, Maps and Journal, System, party setup, character creation, Shop, Temple, Bank, Treasure, Encounter, Level Up, Pick Lock, lifecycle prompts, scrolling text, combat deck, and roster spellbook expose their stable composition through scenes.

Realmz Builder binds those production scenes and controllers to Wide, Compact, Empty, Long Content, Unavailable, and Error profiles without saving preview children. The current preview suite passes 313 assertions, and the latest 148-frame Wide/Compact gallery has passed manual layout review. Exploration and Combat remain modes of the persistent shell; their topology-derived surfaces are not duplicated as fake workspace scenes.

## Runtime acceptance

The latest local aggregate gate passes:

- Godot 4.7.1 import and main-scene smoke;
- 4,030 assertions across 28 suites;
- package, save, media, music, export, schema, provenance, bundled-scenario, differential, workflow-inventory, and gameplay-parity checks;
- all thirteen bundled scenarios and six generated Classic starter characters;
- the fixed 20-percent test-source limit, currently 14.06 percent.

A tracked-files-only clean checkout has completed first import, startup, the complete test suite, architecture verification, scenario validation, and every Builder preview. A local sanitized single-root Git/LFS rehearsal and a separate no-local clone have also passed. These prove the local construction and acquisition paths, not the actual GitHub archive behavior.

## Performance certification

The completed tree has passed the local core-performance gate against the archived pre-migration production tree using three warmed samples on the same Windows host. Application readiness improved from 9,847.479 to 9,203.296 ms; movement transaction-plus-projection p95 from 2.094 to 1.811 ms; 3D dungeon unique-step p95 from 8.365 to 5.602 ms; battle setup from 112.968 to 84.114 ms; native 3440x1440 frame p95 from 6.198 to 5.852 ms; and native transaction-plus-projection p95 from 2.457 to 2.345 ms. The canonical 1280x720 completed tree measured 5.319 ms frame p95 and 1.936 ms transaction-plus-projection p95. No rendered sample skipped or queued a movement interval.

[Runtime performance evidence](runtime-performance.md) records the complete medians, probe boundaries, absolute limits, and exact Windows candidate footprint. The final PCK grew 0.31 percent, the combined export grew 0.18 percent, and median peak working set fell 1.94 percent against the same-workspace pre-migration export.

## Remaining certification

| Gate | Status | Required evidence |
|---|---|---|
| Structural architecture | Complete | All final architecture and maintainability targets green |
| Automated behavior | Complete locally | Full suite and deterministic validators green |
| Editor readability | Complete locally | Production-bound previews and visual gallery accepted |
| Clean local onboarding | Complete locally | Tracked-files-only checkout imports, runs, and verifies |
| Independent maintainer trial | Open | Six hint-free journeys completed without folklore |
| Ordinary-play candidate | Open | AOGM, War, and City of Bywater walkthroughs accepted |
| Final performance | Complete locally | Core probes, exact Windows export size, and peak memory pass the relative and absolute limits |
| Native platforms | Partial | Windows pre-certified; exact Windows/Linux/macOS candidate still required |
| Hosted update | Open | Manifest-synchronized review branch and all protected GitHub checks green |
| Next publication | Open | Owner-selected prerelease version, green exact tag, reviewed draft assets, and manual publication |

No open acceptance gate permits weakening the completed architecture. A failure is repaired in its owning feature, scene, guide, workflow, or release boundary and then reverified at the appropriate risk tier.
