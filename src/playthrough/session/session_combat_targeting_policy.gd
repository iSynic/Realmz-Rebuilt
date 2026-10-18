## Admits only operations that can complete an existing combat commitment.

class_name SessionCombatTargetingPolicy
extends RefCounted


static func pending_cast_allows_intent(state: GameState, intent: PlayerIntent) -> bool:
	var pending := CombatCastResources.pending(state)
	if pending == null:
		return true
	if intent == null or pending.selection == null:
		return false
	if intent.kind == PlayerIntent.Kind.SET_COMBAT_AUTO:
		var auto_payload := intent.payload as CombatIntentPayloads.Auto
		return auto_payload != null and not auto_payload.enabled
	if intent.kind == PlayerIntent.Kind.COMBAT_TARGETING:
		var targeting := intent.payload as CombatIntentPayloads.Targeting
		if targeting == null or targeting.selection == null:
			return false
		if targeting.operation == &"abort_cast":
			return targeting.selection.actor_id == pending.selection.actor_id
		if targeting.operation == &"adjust_cast":
			return pending.selection.action == &"cast_spell" and targeting.selection.same_source(pending.selection)
		return false
	match intent.kind:
		PlayerIntent.Kind.CAST_SPELL:
			var spell := intent.payload as SpellIntentPayload
			if spell == null:
				return false
			if spell.operation == &"cast":
				return pending.selection.action == &"cast_spell" and pending.selection.actor_id == spell.caster_id and pending.selection.spell_id == spell.spell_id and pending.selection.power == spell.power
			if spell.operation == &"use-scroll":
				return pending.selection.action == &"use_scroll" and pending.selection.actor_id == spell.caster_id and pending.selection.scroll_slot == spell.scroll_slot
			return false
		PlayerIntent.Kind.USE_ITEM, PlayerIntent.Kind.USE_ITEM_ON_TARGET:
			var actor_id := ""
			var item_id := ""
			if intent.payload is InventoryIntentPayloads.Use:
				var use := intent.payload as InventoryIntentPayloads.Use
				actor_id = use.actor_id
				item_id = use.item_id
			elif intent.payload is InventoryIntentPayloads.Target:
				var target := intent.payload as InventoryIntentPayloads.Target
				actor_id = target.actor_id
				item_id = target.item_id
			return pending.selection.action == &"use_item" and pending.selection.actor_id == actor_id and pending.selection.item_instance_id == item_id
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			var action := intent.payload as CombatIntentPayloads.Action
			return action != null and pending.selection.action == &"attack" and pending.selection.actor_id == action.actor_id and action.action == &"attack"
	return false
