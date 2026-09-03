# Combat

`CombatState` owns the active battle. `CombatFlow` is the stable command surface over round, action, reaction, magic, field, navigation, and automation collaborators. They share one explicit combat context and return typed results; callers must not reach into collaborator-private methods.

The battlefield is authoritative state, while `CombatView` is detached presentation data. The UI submits typed commands and targets and plays already-committed events. Begin rules work in `test_combat_flow.gd`, navigation work in `test_battlefield_navigation.gd`, and measure sensitive changes with both combat performance probes.
