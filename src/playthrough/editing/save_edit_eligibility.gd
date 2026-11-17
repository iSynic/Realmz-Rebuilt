## Decides whether a saved adventure is at rest: no battle, prompt, interrupted action or
## running scenario script that an edited party, ally list or setting could invalidate.

class_name SaveEditEligibility
extends RefCounted


## Why `snapshot` can't be edited, or "" when it is at rest.
static func reason(snapshot: SessionSnapshot) -> String:
	if snapshot == null or snapshot.game_state == null:
		return "This save can't be read."
	var state := snapshot.game_state
	if not state.party_setup_completed or state.character_draft != null:
		return "This save was made during party setup. Begin the adventure and save again to edit it."
	if state.combat != null:
		return "This save was made during a battle. Finish the battle and save again to edit it."
	if snapshot.pending_interaction() != null:
		return "This save is waiting for a choice or message. Answer it and save again to edit it."
	if _pending(snapshot.continuation) or _pending(snapshot.battle_return_continuation):
		return "This save was made partway through an action. Finish it and save again to edit it."
	var vm := snapshot.scenario_vm
	if vm != null and (vm.has_execution_records() or vm.pending_continuation != null):
		return "This save was made while a scenario event was running. Let it finish and save again to edit it."
	return ""


static func _pending(continuation: SessionContinuation) -> bool:
	return continuation != null and not continuation.is_empty()
