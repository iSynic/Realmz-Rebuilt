# Playthrough world

This folder contains the operations a party performs while exploring. Start with `exploration_movement_workflow.gd` for travel, heading, boats, and fatigue; `exploration_search_workflow.gd` for Search and secrets; `exploration_time_workflow.gd` for Camp, Rest, and Heal; or `location_note_workflow.gd` for player notes.

When an operation yields for time, an Action Point, a random rectangle, a timed record, or a player choice, `exploration_continuation_workflow.gd` and `session_exploration_coordinator.gd` resume it from typed payloads. `session_map_view_builder.gd` joins immutable `MapTopology` with save-owned world changes to produce the detached map read by both 2D and 3D presentation.

Player commands enter through `intents/exploration_intents.gd`; `ExplorationIntentPayloads` carries explicit directions, coordinates, note text, and other world-command values without embedding session state.

The important invariants are one topology, deterministic RNG and event order, no projection mutation, and all-or-nothing session commit. Begin verification with `tests/core/test_map_topology.gd`, `tests/integration/test_exploration_session.gd`, and `tests/integration/test_session_persistence.gd`; use the movement and dungeon-transition probes for projection-sensitive work.
