# Playthrough scenario

Use `session_scenario_coordinator.gd` for transitions between the public `GameSession` transaction and the scenario VM: application hooks, suspended scenario handoffs, party-defeat revival, and exact return to the owning world or combat workflow.

`scenario_application_hook_workflow.gd` resolves the authored hook program and execution context. `scenario_continuations.gd` creates its stable saved continuation, while `scenario_application_continuation_body.gd` carries only the hook, service, revival, and optional suspended-VM facts.

The bodies under `src/game/scenario/requests` describe Complex Encounter, Thief Encounter, and Pick Lock decisions. This layer resumes those decisions through the session transaction; the bodies carry only detached choices and timing facts, while VM frames remain under `src/scenarios`.

Opcode execution, Scenario Actions, VM frames, and runtime continuations remain under `src/scenarios`. Begin verification with the scenario-VM and session-persistence suites, then use the combat, reward, exploration, or application suite matching the return path being changed.
