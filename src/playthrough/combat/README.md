# Playthrough combat

Use `combat_command_workflow.gd` for session-level battle commands: ordinary actions, movement, retreat, and persistent party Auto. It delegates legality, mutation, routing, automation, and completion to the rules-owned `CombatFlow` surface rather than implementing combat again.

`combat_continuations.gd` fixes the stable continuation kinds for retreat, friendly collision, death macros, ally selection, fumble recovery, and rewards. `combat_continuation_body.gd` carries command or macro facts; `combat_reward_continuation_body.gd` retains the exact battle and scenario return point for reward resumption.

Begin verification with `tests/core/test_combat_flow.gd`. Use the reward, persistence, and scenario-VM suites for terminal battles and interrupted continuation paths; tactical presentation remains under `src/ui/combat`.
