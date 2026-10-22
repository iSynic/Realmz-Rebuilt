## Owns resources paid while a manual combat cast awaits its targets.
class_name CombatCastResources
extends RefCounted


static func pending(state: GameState) -> CombatCastCommitment:
	if state == null or state.combat == null or state.combat.turns.active_turn == null:
		return null
	return state.combat.turns.active_turn.cast_commitment


static func reserve(state: GameState, content: RealmzContent, selection: CombatCastSelection) -> bool:
	var caster := state.party.character_by_id(selection.actor_id)
	var turn := state.combat.turns.active_turn
	if caster == null or turn == null or turn.cast_commitment != null:
		return false
	var commitment := CombatCastCommitment.new()
	commitment.selection = CombatCastSelection.from_data(selection.to_data())
	match selection.action:
		&"cast_spell":
			var spell := content.magic.spell_by_id(selection.spell_id)
			if spell == null: return false
			commitment.spell_points_paid = absi(spell.cost * selection.power)
			if caster.spell_points < commitment.spell_points_paid: return false
			caster.spell_points -= commitment.spell_points_paid
			turn.spell_cast_count += 1
			caster.lifetime_record.record_spell_cast()
			commitment.reserved_spell_count = true
		&"use_scroll":
			var scroll := caster.scroll_at(selection.scroll_slot)
			if scroll == null or scroll.is_empty(): return false
			commitment.scroll = SpellScrollState.from_data(scroll.to_data())
			if not caster.clear_scroll(selection.scroll_slot): return false
		&"use_item", &"attack":
			if not _reserve_item(caster, content, selection, commitment): return false
		_: return false
	turn.cast_commitment = commitment
	turn.classic_spell_active = true
	return true


static func _reserve_item(caster: CharacterState, content: RealmzContent, selection: CombatCastSelection, commitment: CombatCastCommitment) -> bool:
	var items := caster.inventory()
	for index: int in range(items.size()):
		var item := items[index]
		if item.id != selection.item_instance_id: continue
		var definition := content.items.item_by_id(item.definition_id)
		if definition == null or item.charges == 0: return false
		commitment.item = ItemInstance.from_data(item.to_data())
		commitment.item_index = index
		commitment.carried_load_before = caster.carried_load
		commitment.equipment_order_before = caster.equipment_order.ids()
		return InventoryRules.new().use_charge(caster, item.id, definition)
	return false


## Used by detached previews and transactional confirmation or optional free cancellation.
static func release(state: GameState) -> bool:
	var commitment := pending(state)
	if commitment == null: return false
	var caster := state.party.character_by_id(commitment.selection.actor_id)
	if caster == null: return false
	if commitment.reserved_spell_count:
		caster.spell_points += commitment.spell_points_paid
		state.combat.turns.active_turn.spell_cast_count -= 1
		caster.lifetime_record.spells_cast = RealmzArithmetic.new().signed_32(caster.lifetime_record.spells_cast - 1)
	elif commitment.scroll != null:
		if not caster.write_scroll(commitment.selection.scroll_slot, commitment.scroll.spell_id, commitment.scroll.power): return false
	elif commitment.item != null:
		if not _release_item(caster, commitment): return false
	state.combat.turns.active_turn.cast_commitment = null
	state.combat.turns.active_turn.classic_spell_active = false
	return true


static func _release_item(caster: CharacterState, commitment: CombatCastCommitment) -> bool:
	var items := caster.inventory()
	var existing_index := -1
	for index: int in range(items.size()):
		if items[index].id == commitment.item.id: existing_index = index
	var restored := ItemInstance.from_data(commitment.item.to_data())
	if existing_index >= 0:
		if existing_index != commitment.item_index: return false
		items[existing_index] = restored
	else:
		if commitment.item_index > items.size(): return false
		items.insert(commitment.item_index, restored)
	caster.set_inventory(items)
	caster.carried_load = commitment.carried_load_before
	return caster.equipment_order.set_exact(commitment.equipment_order_before, items)


static func preview(state: GameState) -> GameState:
	var result := GameState.from_data(state.to_data())
	if result == null or not release(result): return null
	return result


static func abort(state: GameState) -> void:
	var commitment := pending(state)
	var caster := state.party.character_by_id(commitment.selection.actor_id)
	# Castle combatinfo-combatchoice.c:1122-1146: spent sources stay spent.
	if commitment.reserved_spell_count:
		caster.spell_points += int(0.66 * commitment.spell_points_paid)
		state.combat.turns.active_turn.spell_cast_count -= 1
	caster.movement = maxi(0, caster.movement - 3)
	state.combat.turns.active_turn.cast_commitment = null
	state.combat.turns.active_turn.classic_spell_active = false
	if not commitment.selection.item_instance_id.is_empty() and state.combat.turns.staged_random_item_instance_id() == commitment.selection.item_instance_id:
		state.combat.turns.clear_staged_random_item_power()
