# Classic scenario execution

Start with `classic_opcode_catalog.gd` to identify an opcode and `classic_opcode_handler_registry.gd` to find its handler. The three files under `handlers/` divide encounter, presentation, and world/time dispatch; the typed implementations under `operations/` perform the source-backed work through game rules and state.

`scenario_classic_control_flow.gd` owns VM frame changes such as XAP transfer, GOSUB, Encounter entry and repetition, and timeline completion. It returns a typed transition to `ScenarioVm`; it does not run a second VM. `RealmzRuntimeApi` remains the session-owned entry point under the neighboring `runtime/` feature.

`operations/classic_reward_state.gd` is the saveable progress record for a Classic reward sequence. It sits beside `ClassicRewardWorkflow`, which advances its Treasure, level, and spell-selection phases.

When changing one opcode, follow this order: catalog identity, registered handler, named operation, game rule/state collaborator, scenario-VM test, then the matching differential evidence. Preserve stable opcode numbers, RNG order, event order, continuation shape, and save representation.
