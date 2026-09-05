# Scenario game model

Start with `ScenarioProgressState` when you need to understand mutable scenario truth. It owns searched cells, quests, journal discovery, and the current source-ordered character selection. Encounter-specific bookkeeping lives one step deeper in `ScenarioEncounterState`: timed records, choice/result elimination, attempt counts, thief flags, and scenario-program redirects.

Compiled authored content remains beside this state under `content`, `instructions`, and `safe`. `content` holds the immutable campaign aggregate, restrictions, messages, labels, triggers, direct encounters, and program/action definitions. `ScenarioContentCatalog` is the direct lookup for those scenario records after package construction; the compiled program graph remains `RealmzContent.scenario`, while the same aggregate exposes the neighboring character, item, magic, combat, economy, and world catalogs directly. The executing VM and Classic instruction adapters live in `src/scenarios`; `GameSession` and its workflows decide when those operations run.

`CampaignSummaryView` is the small detached selection record derived after package preparation. It carries visible title, author, version, restrictions, guidance, and splash identity without exposing the compiled content aggregate to the UI.

`requests/` contains the detached Complex Encounter, Thief Encounter, and Pick Lock bodies carried through the shared interaction envelope. They expose only the choice and timing facts required by presentation and resumption; they do not contain live VM frames.

`classic_pick_lock_rules.gd` contains the deterministic Castle tumbler timing and chance calculations. Scenario execution owns the attempt and RNG transaction; presentation only animates the detached preview described by the request body.

```text
compiled package definitions
          |
          v
ScenarioVm / RealmzRuntimeApi
          |
          v
ScenarioProgressState -> ScenarioEncounterState
          |
          v
GameState flat save fields
```

The state split is intentionally in-memory only. `ScenarioProgressState.write_to` writes the long-established top-level save keys, and restore validates those same keys before accepting them. Do not nest or rename those fields without an explicit save-version migration. The state classes are pure `RefCounted` objects: no Nodes, files, wall-clock time, or untracked randomness.

Use `tests/scenario/test_scenario_vm.gd` for instruction and encounter behavior, `tests/integration/test_session_persistence.gd` for complete save restoration, and `tests/integration/test_exploration_session.gd` for searched cells and world triggers. Scenario progress is small dictionary-backed state and is not on the rendering hot path.
