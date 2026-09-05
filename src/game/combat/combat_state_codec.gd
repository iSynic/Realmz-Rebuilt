## Encodes and validates the stable CombatState save representation.

class_name CombatStateCodec
extends RefCounted


static func encode(combat: CombatState) -> Dictionary:
	return {
		"battleId": combat.battle_id,
		"macroId": combat.macro_id,
		"round": combat.turns.round_number,
		"turnIndex": combat.turns.turn_index,
		"completed": combat.completed,
		"outcome": String(combat.outcome),
		"rewardsStarted": combat.rewards_started,
		"rewardsCompleted": combat.rewards_completed,
		"classicPostBattleSentinel": combat.classic_post_battle_sentinel,
		"turnOrder": combat.turns.turn_order(),
		"monsters": combat.roster.to_data(),
		"pendingMonsterAttack": null if combat.pending_monster_attack == null else combat.pending_monster_attack.to_data(),
		"pendingReaction": null if combat.pending_reaction == null else combat.pending_reaction.to_data(),
		"activeTurn": null if combat.turns.active_turn == null else combat.turns.active_turn.to_data(),
		"undoState": null if combat.turns.undo_state == null else combat.turns.undo_state.to_data(),
		"fumbledItems": combat.dropped_items.to_data(),
		"characterWeaponModes": combat.actor_statuses.weapon_modes_data(),
		"guardingActorIds": combat.actor_statuses.guarding_actor_ids(),
		"retreatedCharacterIds": combat.actor_statuses.retreated_character_ids(),
		"attackedActorIds": combat.actor_statuses.attacked_actor_ids(),
		"bleedingCharacterIds": combat.actor_statuses.bleeding_character_ids(),
		"turnUndeadActorIds": combat.actor_statuses.turn_undead_actor_ids(),
		"spellDeathMacroQueue": combat.spell_runtime.death_macro_queue(),
		"spellMacroActorId": combat.spell_runtime.macro_actor_id(),
		"spellMacroAdvancesTurn": combat.spell_runtime.macro_advances_turn(),
		"persistentFields": combat.spell_runtime.persistent_fields().map(func(field: PersistentCombatField) -> Dictionary: return field.to_data()),
		"persistentFieldCollisionSlots": combat.spell_runtime.field_collision_slots(),
		"battlefield": null if combat.battlefield == null else BattlefieldStateCodec.to_data(combat.battlefield),
	}


static func decode(data: Variant) -> CombatState:
	if not _has_required_header(data):
		return null
	var loaded_round := _integer(data["round"])
	var loaded_turn := _integer(data["turnIndex"])
	var loaded_macro := _signed_integer(data.get("macroId", 0))
	if not _valid_header(data, loaded_round, loaded_turn, loaded_macro):
		return null
	var decoded_monsters: Variant = _decode_monsters(data["monsters"])
	if decoded_monsters == null:
		return null
	var monsters: Array[MonsterState] = decoded_monsters
	var battlefield := _decode_battlefield(data.get("battlefield"))
	if data.get("battlefield") != null and battlefield == null:
		return null
	var decoded_order: Variant = _decode_turn_order(data["turnOrder"])
	if decoded_order == null:
		return null
	var order: Array[String] = decoded_order
	var result := CombatState.new(data["battleId"], monsters, loaded_macro, battlefield)
	if not _restore_header(result, data, order, loaded_round, loaded_turn):
		return null
	if not _restore_actor_statuses(result, data, order) or not _restore_spell_runtime(result, data, order):
		return null
	if not _restore_inventory_and_modes(result, data, order) or not _restore_pending_state(result, data):
		return null
	return result if _loaded_state_is_consistent(result) else null


static func _has_required_header(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for field: String in ["battleId", "round", "turnIndex", "completed", "outcome", "turnOrder", "monsters"]:
		if not data.has(field):
			return false
	return true


static func _valid_header(data: Dictionary, loaded_round: int, loaded_turn: int, loaded_macro: int) -> bool:
	return data["battleId"] is String and not data["battleId"].is_empty() and loaded_macro != -100_000 and loaded_round >= 1 and loaded_turn >= 0 and data["completed"] is bool and data["outcome"] is String and data["turnOrder"] is Array and data["monsters"] is Array


static func _decode_monsters(data: Array) -> Variant:
	var result: Array[MonsterState] = []
	for entry: Variant in data:
		var monster := MonsterState.from_data(entry)
		if monster == null:
			return null
		result.append(monster)
	return result


static func _decode_battlefield(data: Variant) -> BattlefieldState:
	return null if data == null else BattlefieldStateCodec.from_data(data)


static func _decode_turn_order(data: Array) -> Variant:
	var result: Array[String] = []
	for entry: Variant in data:
		if not entry is String or entry.is_empty():
			return null
		result.append(entry)
	return result


static func _restore_header(result: CombatState, data: Dictionary, order: Array[String], loaded_round: int, loaded_turn: int) -> bool:
	if not data.get("rewardsStarted", false) is bool or not data.get("rewardsCompleted", false) is bool:
		return false
	result.set_turn_order(order)
	result.turns.round_number = loaded_round
	result.turns.turn_index = loaded_turn
	result.completed = data["completed"]
	result.outcome = StringName(data["outcome"])
	result.rewards_started = data.get("rewardsStarted", false)
	result.rewards_completed = data.get("rewardsCompleted", false)
	result.classic_post_battle_sentinel = _integer(data.get("classicPostBattleSentinel", 0))
	return result.classic_post_battle_sentinel in [0, 8] and not (result.rewards_completed and not result.rewards_started)


static func _restore_actor_statuses(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var descriptors: Array = [
		[data.get("guardingActorIds", []), order.size(), false, &"guarding"],
		[data.get("attackedActorIds", []), order.size(), false, &"attacked"],
		[data.get("bleedingCharacterIds", []), 6, true, &"bleeding"],
		[data.get("turnUndeadActorIds", []), 6, true, &"turn-undead"],
		[data.get("retreatedCharacterIds", []), 6, true, &"retreated"],
	]
	for descriptor: Array in descriptors:
		if not _restore_actor_set(result, order, descriptor[0], descriptor[1], descriptor[2], descriptor[3]):
			return false
	return true


static func _restore_actor_set(result: CombatState, order: Array[String], values: Variant, maximum: int, characters_only: bool, kind: StringName) -> bool:
	if not values is Array or values.size() > maximum:
		return false
	var seen: Dictionary = {}
	for actor_id: Variant in values:
		if not actor_id is String or actor_id.is_empty() or not order.has(actor_id) or seen.has(actor_id) or characters_only and result.roster.monster_by_id(actor_id) != null:
			return false
		seen[actor_id] = true
		if not _apply_actor_marker(result.actor_statuses, actor_id, kind):
			return false
	return true


static func _apply_actor_marker(statuses: CombatActorStatusState, actor_id: String, kind: StringName) -> bool:
	match kind:
		&"guarding": return statuses.set_guarding(actor_id, true)
		&"attacked": return statuses.mark_attacked(actor_id)
		&"bleeding": return statuses.set_character_bleeding(actor_id, true)
		&"turn-undead": return statuses.mark_turn_undead_used(actor_id)
		&"retreated": return statuses.mark_character_retreated(actor_id)
	return false


static func _restore_spell_runtime(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var queue: Variant = data.get("spellDeathMacroQueue", [])
	var actor: Variant = data.get("spellMacroActorId", "")
	var advances: Variant = data.get("spellMacroAdvancesTurn", false)
	if not queue is Array or queue.size() > CombatSpellRuntimeState.MAX_DEATH_MACROS or not actor is String or not advances is bool:
		return false
	var loaded_queue: Array[String] = []
	for combatant_id: Variant in queue:
		if not combatant_id is String or combatant_id.is_empty() or result.roster.monster_by_id(combatant_id) == null:
			return false
		loaded_queue.append(combatant_id)
	result.spell_runtime.restore_death_macro_sequence(loaded_queue, actor, advances)
	return _restore_persistent_fields(result, data, order)


static func _restore_persistent_fields(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var field_data: Variant = data.get("persistentFields", [])
	var collision_data: Variant = data.get("persistentFieldCollisionSlots", [])
	if not field_data is Array or field_data.size() > CombatSpellRuntimeState.MAX_PERSISTENT_FIELDS or not collision_data is Array or collision_data.size() > CombatSpellRuntimeState.MAX_PERSISTENT_FIELDS:
		return false
	var fields: Array[PersistentCombatField] = []
	var slots: Dictionary = {}
	for entry: Variant in field_data:
		var field := PersistentCombatField.from_data(entry) as PersistentCombatField
		if field == null or slots.has(field.slot) or field.phase_turn_index >= order.size() or not order.has(field.caster_id):
			return false
		slots[field.slot] = true
		fields.append(field)
	var decoded_collisions: Variant = _decode_collision_slots(collision_data, slots)
	if decoded_collisions == null:
		return false
	var collisions: Array[int] = decoded_collisions
	result.spell_runtime.restore_persistent_fields(fields, collisions)
	return true


static func _decode_collision_slots(data: Array, field_slots: Dictionary) -> Variant:
	var result: Array[int] = []
	var seen: Dictionary = {}
	for value: Variant in data:
		var slot := _integer(value)
		if slot < 0 or slot >= CombatSpellRuntimeState.MAX_PERSISTENT_FIELDS or not field_slots.has(slot) or seen.has(slot):
			return null
		seen[slot] = true
		result.append(slot)
	return result


static func _restore_inventory_and_modes(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var modes: Variant = data.get("characterWeaponModes", {})
	if not modes is Dictionary or modes.size() > 6:
		return false
	for actor_id: Variant in modes:
		var mode: Variant = modes[actor_id]
		if not actor_id is String or actor_id.is_empty() or not mode is String or mode not in ["melee", "missile"] or not order.has(actor_id) or result.roster.monster_by_id(actor_id) != null or not result.actor_statuses.set_character_weapon_mode(actor_id, StringName(mode)):
			return false
	var item_data: Variant = data.get("fumbledItems", [])
	if not item_data is Array or item_data.size() > CombatDroppedItemState.MAX_ITEMS:
		return false
	for entry: Variant in item_data:
		var item := ItemInstance.from_data(entry)
		if item == null or item.equipped or not result.dropped_items.queue(item):
			return false
	return true


static func _restore_pending_state(result: CombatState, data: Dictionary) -> bool:
	var active_data: Variant = data.get("activeTurn")
	if active_data != null:
		result.turns.active_turn = CombatTurnState.from_data(active_data)
		if result.turns.active_turn == null: return false
	var undo_data: Variant = data.get("undoState")
	if undo_data != null:
		result.turns.undo_state = _undo_from_data(undo_data)
		if result.turns.undo_state == null: return false
	var pending_data: Variant = data.get("pendingMonsterAttack")
	if pending_data != null:
		result.pending_monster_attack = PendingMonsterAttack.from_data(pending_data)
		if result.pending_monster_attack == null: return false
	var reaction_data: Variant = data.get("pendingReaction")
	if reaction_data != null:
		result.pending_reaction = CombatReactionState.from_data(reaction_data)
		if result.pending_reaction == null: return false
	return true


static func _loaded_state_is_consistent(result: CombatState) -> bool:
	var order := result.turns.turn_order()
	if order.is_empty() and result.turns.turn_index != 0 or not order.is_empty() and result.turns.turn_index >= order.size(): return false
	if result.turns.active_turn != null and (result.completed or result.turns.active_turn.actor_id != result.turns.active_actor_id()): return false
	if result.turns.active_turn != null and not result.turns.active_turn.staged_item_instance_id.is_empty() and result.roster.monster_by_id(result.turns.active_turn.actor_id) != null: return false
	if not _undo_is_consistent(result) or not _spell_sequence_is_consistent(result) or not _reaction_is_consistent(result): return false
	return _pending_attack_is_consistent(result)


static func _undo_is_consistent(result: CombatState) -> bool:
	var undo := result.turns.undo_state
	if undo == null: return true
	return not result.completed and result.turns.active_turn != null and result.battlefield != null and undo.actor_id == result.turns.active_actor_id() and undo.actor_id == result.turns.active_turn.actor_id and undo.round_number == result.turns.round_number and undo.turn_index == result.turns.turn_index and result.battlefield.actors.has_actor(undo.actor_id)


static func _spell_sequence_is_consistent(result: CombatState) -> bool:
	var queue := result.spell_runtime.death_macro_queue()
	var actor_id := result.spell_runtime.macro_actor_id()
	if queue.is_empty() != actor_id.is_empty() or not actor_id.is_empty() and (result.completed or result.turns.active_actor_id() != actor_id): return false
	return not queue.is_empty() or not result.spell_runtime.macro_advances_turn()


static func _reaction_is_consistent(result: CombatState) -> bool:
	if result.pending_reaction == null: return true
	return not result.completed and result.turns.active_turn != null and result.turns.active_actor_id() == result.pending_reaction.mover_id and result.turns.active_turn.actor_id == result.pending_reaction.mover_id


static func _pending_attack_is_consistent(result: CombatState) -> bool:
	var pending := result.pending_monster_attack
	if pending == null: return true
	if result.roster.monster_by_id(pending.actor_id) == null: return false
	if result.pending_reaction == null and result.turns.active_actor_id() != pending.actor_id: return false
	if result.pending_reaction == null and result.turns.active_turn == null:
		result.turns.active_turn = CombatTurnState.new(pending.actor_id)
		result.turns.active_turn.action = pending.action
		result.turns.active_turn.attack_index = 1
		result.turns.active_turn.target_id = pending.target_id
	if result.pending_reaction == null:
		result.turns.active_turn.physical_action_committed = true
		return result.turns.active_turn.actor_id == pending.actor_id and result.turns.active_turn.target_id == pending.target_id and result.turns.active_turn.action == pending.action and result.turns.active_turn.attack_index >= 1
	var expected_action := &"withdrawal" if result.pending_reaction.phase == CombatReactionState.WITHDRAWAL else &"guard"
	var completed_attackers := result.pending_reaction.attackers().slice(0, result.pending_reaction.next_attacker_index)
	return pending.target_id == result.pending_reaction.mover_id and pending.action == expected_action and completed_attackers.has(pending.actor_id)


static func _undo_from_data(data: Variant) -> CombatUndoState:
	if not data is Dictionary or data.size() != 5:
		return null
	for field: String in ["actorId", "startPosition", "round", "turnIndex", "available"]:
		if not data.has(field): return null
	if not data["actorId"] is String or data["actorId"].is_empty() or not data["available"] is bool: return null
	var start_data: Variant = data["startPosition"]
	if not start_data is Array or start_data.size() != 2: return null
	var position := Vector2i(_signed_integer(start_data[0]), _signed_integer(start_data[1]))
	var loaded_round := _integer(data["round"])
	var loaded_turn := _integer(data["turnIndex"])
	if position.x == -100_000 or position.y == -100_000 or not BattlefieldGrid.contains(position) or loaded_round < 1 or loaded_turn < 0: return null
	var undo := CombatUndoState.new(data["actorId"], position, loaded_round, loaded_turn)
	undo.available = data["available"]
	return undo


static func _integer(value: Variant) -> int:
	if value is int: return value
	if value is float and is_equal_approx(value, round(value)): return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int: return value
	if value is float and is_equal_approx(value, round(value)): return int(value)
	return -100_000
