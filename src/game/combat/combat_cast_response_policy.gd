## Admits only responses that can complete a pending combat cast commitment.

class_name CombatCastResponsePolicy
extends RefCounted


static func allows(state: GameState, body: InteractionResponse.CombatBody) -> bool:
	var pending := CombatCastResources.pending(state)
	if pending == null:
		return true
	if body == null or pending.selection == null:
		return false
	if body.action == &"set_auto":
		return not body.enabled
	if body.action == &"abort_cast":
		return pending.selection.actor_id == body.actor_id
	if body.action == &"adjust_cast":
		var adjusted := CombatCastSelection.from_body(body)
		return adjusted != null and pending.selection.action == &"cast_spell" and pending.selection.same_source(adjusted)
	if body.action == &"attack":
		return pending.selection.action == &"attack" and pending.selection.actor_id == body.actor_id
	if body.action == &"use_item":
		return pending.selection.action == &"use_item" and pending.selection.actor_id == body.actor_id and pending.selection.item_instance_id == body.item_instance_id
	if body.action not in [&"cast_spell", &"use_scroll", &"use_item"]:
		return false
	var confirmation := CombatCastSelection.from_body(body)
	return confirmation != null and pending.selection.same_source(confirmation) and pending.selection.power == confirmation.power
