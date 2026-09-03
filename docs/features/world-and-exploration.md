# World and exploration

`MapTopology` is the sole map truth. `WorldState` stores save-owned changes such as visited and seen cells, secrets, doors, terrain replacements, random-region bounds, notes, and player maps. `ExplorationTimeWorkflow` performs movement, search, time, fatigue, camp, rest, and field healing through the session transaction.

Both 2D and 3D presentation consume the same detached `MapView`; neither owns collision, LOS, heading, or discovery rules. Start rule changes in `test_map_topology.gd` and public journeys in `test_exploration_session.gd`. Use the movement and dungeon-transition probes whenever projection or spatial presentation changes.
