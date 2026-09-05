# Playthrough combat

Use `combat_command_workflow.gd` for session-level battle commands: ordinary actions, movement, retreat, and persistent party Auto. It delegates legality, mutation, routing, automation, and completion to the rules-owned `CombatFlow` surface rather than implementing combat again.

`combat_continuations.gd` fixes the stable continuation kinds for retreat, friendly collision, death macros, ally selection, fumble recovery, and rewards. `combat_continuation_body.gd` carries command or macro facts; `combat_reward_continuation_body.gd` retains the exact battle and scenario return point for reward resumption.

Player commands enter through `intents/combat_intents.gd`; `CombatIntentPayloads` names the action, target, destination, item, spell, and Auto values admitted by the command workflow.

`src/game/combat/requests/combat_request_body.gd` is the detached command deck handed to presentation. It reports calculated actions and targets; this workflow submits the selected command but does not reimplement its legality.

Begin verification with `tests/core/test_combat_flow.gd`. Use the reward, persistence, and scenario-VM suites for terminal battles and interrupted continuation paths; tactical presentation remains under `src/ui/combat`.
