# Scenario runtime

`RealmzRuntimeApi` is the one session-owned gateway used by `ScenarioVm`. It routes preserved Classic instructions to `../classic`, Safe Scenario Action operations to their declared capabilities, and every player decision through a typed, saveable runtime continuation.

Execution provenance lives in `ScenarioExecutionContext`; only its codec handles the sparse save dictionary. Operation results, directives, callers, and handoffs are small typed records that keep the VM independent from presentation and storage. Start in `realmz_runtime_api.gd`, then follow the named collaborator rather than adding another facade method.

The `continuations/` folder owns the closed suspended-operation payload families. VM scheduling, frames, snapshots, and trace limits remain in `../vm`.
