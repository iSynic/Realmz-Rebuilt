# Human-centered architecture overhaul

Realmz Rebuilt is behaviorally mature, but its source still exposes too much of its construction history to a new maintainer. Beta 1 is blocked while the repository is reorganized into an editor-readable, feature-oriented form. The working game remains the behavioral reference during this migration.

## Starting point

The migration branch begins at commit `55292533` with Godot 4.7.1. The complete local verification gate passed at that commit with 3,532 assertions across 27 suites, 101 differential cases, all 13 bundled scenarios, and every package, schema, export, media, and workflow check.

The initial structural audit found:

- 64,250 substantive production lines and 8,596 substantive test lines.
- 664 `Control.new()` calls, all admitted by the former reviewed-classification budget.
- 28 production files above the new 600-line limit and 103 functions above the new 60-line limit.
- 38 top-level scripts above the new method-count limits.
- 203 production calls into another object's underscore-prefixed method.
- 133 generic `Type` or `Script` preload aliases.
- Two one-node shell-mode marker scenes and no registered editor-preview profiles.

These numbers are migration debt, not the desired architecture. The overhaul gate prevents any category from growing and requires each ceiling to move downward as its owning workflow is converted. The final ceilings are zero except for the ordinary numeric size limits and explicitly named algorithmic renderers.

## Performance baseline

Three warmed samples were taken on the same Windows machine before structural work. Medians are used for comparison.

| Probe | Baseline median |
|---|---:|
| Application ready | 6,734.890 ms |
| First frame | 153.658 ms |
| Movement transaction plus projection p95 | 1.781 ms |
| Movement transaction p95 | 0.787 ms |
| Movement projection p95 | 1.034 ms |
| 3D dungeon unique-step p95 | 4.573 ms |
| 3D dungeon turn p95 | 0.023 ms |
| 3D dungeon backtrack p95 | 0.035 ms |
| Battle setup | 93.719 ms |
| Combat view | 1.532 ms |
| Auto activation | 30.311 ms |
| Warm monster phase | 9.798 ms |

The performance probes now load scenario packages through the pinned application catalog before measuring them. This is required by the separated application-catalog and scenario-overlay contract.

## Working rules

- Unrelated feature work remains paused. Defects, fidelity blockers, and migration-required polish may proceed.
- Each batch starts with characterization evidence and ends with focused tests, the architecture gates, and three comparable performance samples when it touches a sensitive path.
- Stable layout moves into scenes. Scripts bind data, coordinate behavior, and instantiate exported scenes for genuinely variable records.
- Simulation remains pure and deterministic. The migration does not move rules or saved truth into Nodes.
- Renames are decisive. Serialized identifiers, packages, saves, Character Files, and the existing user-data directory do not change.
- A system is finished only when its source, scene, guide, tests, and manifest entry agree.

Current ownership and navigation are recorded in `system-manifest.json`. That manifest changes atomically with every move, rename, new public interface, scene conversion, or test transfer.

## Current certification status

The structural migration is complete: every architecture-overhaul ceiling is zero, the complete 4,030-assertion suite is green, and the 148-frame graphical Mobile/Vulkan gallery runs through every registered route and interaction family without a script error. The gallery waits for the public application library and follows the live scene-owned Encounter dock, so it exercises the retained production composition rather than an obsolete test hierarchy.

Visual acceptance remains open. The current evidence shows that the wide field-Spells workspace collapses its records into unreadable narrow columns, while compact Inventory and Party Wealth place their persistent exit below the initial viewport. The compact combat capture also needs diagnosis because its retained tactical surface is absent while the lower command deck is clipped. These are Beta-blocking scene-composition defects, not exceptions to the editor-readable target. Clean-clone onboarding, the independent maintainer exercise, ordinary-play campaign walkthroughs, and native macOS certification also remain open.
