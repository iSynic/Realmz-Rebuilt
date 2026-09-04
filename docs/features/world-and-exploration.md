# World and exploration

`MapTopology` is the sole map truth. `WorldState` stores save-owned changes such as visited and seen cells, secrets, doors, terrain replacements, random-region bounds, notes, and player maps. `ExplorationTimeWorkflow` performs movement, search, time, fatigue, camp, rest, and field healing through the session transaction.

Input begins with `ExplorationIntents`, whose factories distinguish ordinary movement, overhead dungeon movement, turns, Search, camp/rest/heal, contextual encounters, Torch, and location notes. `ExplorationIntentPayloads` carries only the direction, heading-alignment, turn, or note value; legality remains in the workflow and rules.

When exploration yields for clock processing, an AP, a random region, or a boat choice, resume state is created by `ExplorationContinuations` and carried by `ExplorationContinuationBody` or `BoatContinuationBody`. The strict central codec preserves those exact save fields without making exploration coordination depend on a generic protocol catalog.

Both 2D and 3D presentation consume the same detached `MapView`; neither owns collision, LOS, heading, or discovery rules. Start rule changes in `test_map_topology.gd` and public journeys in `test_exploration_session.gd`. Use the movement and dungeon-transition probes whenever projection or spatial presentation changes.
