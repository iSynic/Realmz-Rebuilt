class_name CombatState
extends RefCounted

const CombatUndoStateType := preload("res://src/core/state/combat_undo_state.gd")
const PersistentCombatFieldType := preload("res://src/core/state/persistent_combat_field.gd")
const MAX_SPELL_DEATH_MACROS := 100
const MAX_PERSISTENT_FIELDS := 60

const MAX_FUMBLED_ITEMS: int = 20

var battle_id: String
var macro_id: int = 0
var round_number: int = 1
var turn_index: int = 0
var completed: bool = false
var outcome: StringName = &"active"
var rewards_started: bool = false
var rewards_completed: bool = false
var classic_post_battle_sentinel: int = 0
var battlefield: BattlefieldState
var pending_monster_attack: PendingMonsterAttack
var pending_reaction: CombatReactionState
var active_turn: CombatTurnState
var undo_state: CombatUndoStateType
var _turn_order: Array[String] = []
var _monsters: Array[MonsterState] = []
var _fumbled_items: Array[ItemInstance] = []
var _character_weapon_modes: Dictionary = {}
var _guarding_actor_ids: Dictionary = {}
var _retreated_character_ids: Dictionary = {}
var _attacked_actor_ids: Dictionary = {}
var _bleeding_character_ids: Dictionary = {}
var _turned_undead_actor_ids: Dictionary = {}
var _spell_death_macro_queue: Array[String] = []
var _spell_macro_actor_id: String = ""
var _spell_macro_advances_turn: bool = false
var _persistent_fields: Array[PersistentCombatFieldType] = []
var _persistent_field_collision_slots: Dictionary = {}


func _init(source_battle_id: String, initial_monsters: Array[MonsterState] = [], battle_macro_id: int = 0, initial_battlefield: BattlefieldState = null) -> void:
	battle_id = source_battle_id
	_monsters = initial_monsters.duplicate()
	macro_id = battle_macro_id
	battlefield = initial_battlefield


func monsters() -> Array[MonsterState]:
	return _monsters.duplicate()


func turn_order() -> Array[String]:
	return _turn_order.duplicate()


func set_turn_order(order: Array[String]) -> void:
	_turn_order = order.duplicate()
	turn_index = 0
	active_turn = null
	undo_state = null
	_persistent_field_collision_slots.clear()


func active_actor_id() -> String:
	return "" if _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size() else _turn_order[turn_index]


func monster_by_id(monster_id: String) -> MonsterState:
	for monster: MonsterState in _monsters:
		if monster.id == monster_id:
			return monster
	return null


func add_monster(monster: MonsterState) -> bool:
	if monster == null or monster_by_id(monster.id) != null:
		return false
	_monsters.append(monster)
	return true


func fumbled_items() -> Array[ItemInstance]:
	return _fumbled_items.duplicate()


func can_queue_fumbled_item() -> bool:
	return _fumbled_items.size() < MAX_FUMBLED_ITEMS


func queue_fumbled_item(item: ItemInstance) -> bool:
	if item == null or not can_queue_fumbled_item():
		return false
	for queued: ItemInstance in _fumbled_items:
		if queued.id == item.id:
			return false
	item.equipped = false
	_fumbled_items.append(item)
	return true


func requeue_fumbled_item_first(item: ItemInstance) -> bool:
	if item == null or not can_queue_fumbled_item():
		return false
	for queued: ItemInstance in _fumbled_items:
		if queued.id == item.id:
			return false
	item.equipped = false
	_fumbled_items.push_front(item)
	return true


func remove_fumbled_item(instance_id: String) -> ItemInstance:
	for index: int in _fumbled_items.size():
		if _fumbled_items[index].id == instance_id:
			return _fumbled_items.pop_at(index)
	return null


func clear_fumbled_items() -> void:
	_fumbled_items.clear()


func advance_turn() -> bool:
	if _turn_order.is_empty():
		return false
	active_turn = null
	undo_state = null
	_persistent_field_collision_slots.clear()
	turn_index += 1
	if turn_index >= _turn_order.size():
		turn_index = 0
		round_number += 1
		_attacked_actor_ids.clear()
		return true
	return false


func delay_active_actor() -> bool:
	if _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size():
		return false
	active_turn = null
	undo_state = null
	_persistent_field_collision_slots.clear()
	if turn_index >= _turn_order.size() - 1:
		turn_index = 0
		round_number += 1
		_attacked_actor_ids.clear()
		return true
	var actor_id: String = _turn_order.pop_at(turn_index)
	_turn_order.append(actor_id)
	return false


func begin_active_turn() -> CombatTurnState:
	var actor_id := active_actor_id()
	if actor_id.is_empty():
		return null
	if active_turn == null:
		active_turn = CombatTurnState.new(actor_id)
	return active_turn


func stage_random_item_power(actor_id: String, instance_id: String, power: int) -> bool:
	if active_turn == null or active_turn.actor_id != actor_id or actor_id != active_actor_id() or monster_by_id(actor_id) != null or instance_id.is_empty() or power < 1 or power > 7 or not active_turn.staged_item_instance_id.is_empty():
		return false
	active_turn.staged_item_instance_id = instance_id
	active_turn.staged_item_power = power
	return true


func staged_random_item_power(actor_id: String, instance_id: String) -> int:
	if active_turn == null or active_turn.actor_id != actor_id or actor_id != active_actor_id() or active_turn.staged_item_instance_id != instance_id:
		return 0
	return active_turn.staged_item_power


func staged_random_item_instance_id() -> String:
	return "" if active_turn == null else active_turn.staged_item_instance_id


func clear_staged_random_item_power() -> void:
	if active_turn == null:
		return
	active_turn.staged_item_instance_id = ""
	active_turn.staged_item_power = 0


func begin_character_undo(actor_id: String) -> bool:
	if active_turn == null or active_turn.actor_id != actor_id or active_actor_id() != actor_id or battlefield == null or not battlefield.has_actor(actor_id) or monster_by_id(actor_id) != null:
		return false
	undo_state = CombatUndoStateType.new(actor_id, battlefield.actor_position(actor_id), round_number, turn_index)
	return true


func clear_active_turn() -> void:
	active_turn = null
	undo_state = null


func invalidate_undo() -> void:
	if undo_state != null:
		undo_state.available = false


func restart_active_turn_after_undo() -> void:
	active_turn = null
	undo_state = null


func append_turn_actor(actor_id: String) -> void:
	if not actor_id.is_empty() and not _turn_order.has(actor_id):
		_turn_order.append(actor_id)


func set_character_weapon_mode(actor_id: String, mode: StringName) -> bool:
	if actor_id.is_empty() or mode not in [&"melee", &"missile"] or not _turn_order.has(actor_id) or monster_by_id(actor_id) != null:
		return false
	_character_weapon_modes[actor_id] = String(mode)
	return true


func character_weapon_mode(actor_id: String) -> StringName:
	return StringName(_character_weapon_modes.get(actor_id, "melee"))


func set_guarding(actor_id: String, guarding: bool) -> bool:
	if actor_id.is_empty() or not _turn_order.has(actor_id):
		return false
	if guarding:
		_guarding_actor_ids[actor_id] = true
	else:
		_guarding_actor_ids.erase(actor_id)
	return true


func is_guarding(actor_id: String) -> bool:
	return bool(_guarding_actor_ids.get(actor_id, false))


func guarding_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _guarding_actor_ids:
		result.append(String(actor_id))
	result.sort()
	return result


func mark_attacked(actor_id: String) -> bool:
	if actor_id.is_empty() or not _turn_order.has(actor_id):
		return false
	_attacked_actor_ids[actor_id] = true
	return true


func was_attacked(actor_id: String) -> bool:
	return bool(_attacked_actor_ids.get(actor_id, false))


func attacked_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _attacked_actor_ids:
		result.append(String(actor_id))
	result.sort()
	return result


func set_character_bleeding(actor_id: String, bleeding: bool) -> bool:
	if actor_id.is_empty() or not _turn_order.has(actor_id) or monster_by_id(actor_id) != null:
		return false
	if bleeding:
		_bleeding_character_ids[actor_id] = true
	else:
		_bleeding_character_ids.erase(actor_id)
	return true


func is_character_bleeding(actor_id: String) -> bool:
	return bool(_bleeding_character_ids.get(actor_id, false))


func bleeding_character_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _bleeding_character_ids:
		result.append(String(actor_id))
	result.sort()
	return result


func mark_turn_undead_used(actor_id: String) -> bool:
	if actor_id.is_empty() or not _turn_order.has(actor_id) or monster_by_id(actor_id) != null:
		return false
	_turned_undead_actor_ids[actor_id] = true
	return true


func has_used_turn_undead(actor_id: String) -> bool:
	return bool(_turned_undead_actor_ids.get(actor_id, false))


func turn_undead_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _turned_undead_actor_ids:
		result.append(String(actor_id))
	result.sort()
	return result


func queue_spell_death_macro(combatant_id: String) -> bool:
	if combatant_id.is_empty() or monster_by_id(combatant_id) == null or _spell_death_macro_queue.size() >= MAX_SPELL_DEATH_MACROS:
		return false
	_spell_death_macro_queue.append(combatant_id)
	return true


func begin_spell_death_macro_sequence(actor_id: String, advances_turn: bool) -> bool:
	if _spell_death_macro_queue.is_empty() or actor_id.is_empty() or actor_id != active_actor_id() or not _spell_macro_actor_id.is_empty():
		return false
	_spell_macro_actor_id = actor_id
	_spell_macro_advances_turn = advances_turn
	return true


func pending_spell_death_macro_id() -> String:
	return "" if _spell_death_macro_queue.is_empty() else _spell_death_macro_queue[0]


func complete_spell_death_macro(combatant_id: String) -> bool:
	if combatant_id.is_empty() or pending_spell_death_macro_id() != combatant_id:
		return false
	_spell_death_macro_queue.pop_front()
	return true


func spell_death_macro_queue() -> Array[String]:
	return _spell_death_macro_queue.duplicate()


func spell_macro_actor_id() -> String:
	return _spell_macro_actor_id


func spell_macro_advances_turn() -> bool:
	return _spell_macro_advances_turn


func clear_spell_death_macro_sequence() -> void:
	_spell_death_macro_queue.clear()
	_spell_macro_actor_id = ""
	_spell_macro_advances_turn = false


func persistent_fields() -> Array[PersistentCombatFieldType]:
	var result := _persistent_fields.duplicate()
	result.sort_custom(func(left: PersistentCombatFieldType, right: PersistentCombatFieldType) -> bool: return left.slot < right.slot)
	return result


func can_queue_persistent_field() -> bool:
	return _persistent_fields.size() < MAX_PERSISTENT_FIELDS


func queue_persistent_field(spell_id: String, caster_id: String, center: Vector2i, rotation: int, shape: int, queue_icon: int, power_level: int, cast_level: int, duration: int) -> PersistentCombatFieldType:
	if not can_queue_persistent_field() or spell_id.is_empty() or caster_id.is_empty() or not BattlefieldState.contains(center) or rotation < 0 or rotation > 3 or shape < 1 or shape > 127 or queue_icon == 0 or queue_icon < -128 or queue_icon > 127 or power_level < 1 or power_level > 7 or cast_level < 0 or cast_level > 7 or duration < 1 or duration > 32_767 or _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size():
		return null
	var used_slots: Dictionary = {}
	for field: PersistentCombatFieldType in _persistent_fields:
		used_slots[field.slot] = true
	var slot := 0
	while used_slots.has(slot):
		slot += 1
	var result := PersistentCombatFieldType.new(slot, spell_id, caster_id, center, rotation, shape, queue_icon, power_level, cast_level, duration, turn_index)
	_persistent_fields.append(result)
	return result


func decay_persistent_fields_for_phase(phase_turn_index: int) -> Array[PersistentCombatFieldType]:
	var expired: Array[PersistentCombatFieldType] = []
	for index: int in range(_persistent_fields.size() - 1, -1, -1):
		var field: PersistentCombatFieldType = _persistent_fields[index]
		if field.phase_turn_index != phase_turn_index:
			continue
		field.remaining_duration -= 1
		if field.remaining_duration <= 0:
			expired.push_front(_persistent_fields.pop_at(index))
	return expired


func has_persistent_field_collision(slot: int) -> bool:
	return bool(_persistent_field_collision_slots.get(slot, false))


func mark_persistent_field_collision(slot: int) -> bool:
	if slot < 0 or slot >= MAX_PERSISTENT_FIELDS or has_persistent_field_collision(slot) or not persistent_fields().any(func(field: PersistentCombatFieldType) -> bool: return field.slot == slot):
		return false
	_persistent_field_collision_slots[slot] = true
	return true


func persistent_field_collision_slots() -> Array[int]:
	var result: Array[int] = []
	for slot: Variant in _persistent_field_collision_slots:
		result.append(int(slot))
	result.sort()
	return result


func mark_character_retreated(actor_id: String) -> bool:
	if actor_id.is_empty() or not _turn_order.has(actor_id) or monster_by_id(actor_id) != null:
		return false
	_retreated_character_ids[actor_id] = true
	return true


func has_character_retreated(actor_id: String) -> bool:
	return bool(_retreated_character_ids.get(actor_id, false))


func retreated_character_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id: Variant in _retreated_character_ids:
		result.append(String(actor_id))
	result.sort()
	return result


func to_data() -> Dictionary:
	var monster_data: Array[Dictionary] = []
	for monster: MonsterState in _monsters:
		monster_data.append(monster.to_data())
	var pending_data: Variant = null
	if pending_monster_attack != null:
		pending_data = pending_monster_attack.to_data()
	var active_turn_data: Variant = null
	if active_turn != null:
		active_turn_data = active_turn.to_data()
	var undo_data: Variant = null
	if undo_state != null:
		undo_data = undo_state.to_data()
	var reaction_data: Variant = null
	if pending_reaction != null:
		reaction_data = pending_reaction.to_data()
	var fumbled_data: Array[Dictionary] = []
	for item: ItemInstance in _fumbled_items:
		fumbled_data.append(item.to_data())
	var weapon_modes: Dictionary = {}
	var weapon_mode_ids: Array = _character_weapon_modes.keys()
	weapon_mode_ids.sort()
	for actor_id: Variant in weapon_mode_ids:
		weapon_modes[String(actor_id)] = _character_weapon_modes[actor_id]
	return {"battleId": battle_id, "macroId": macro_id, "round": round_number, "turnIndex": turn_index, "completed": completed, "outcome": String(outcome), "rewardsStarted": rewards_started, "rewardsCompleted": rewards_completed, "classicPostBattleSentinel": classic_post_battle_sentinel, "turnOrder": _turn_order.duplicate(), "monsters": monster_data, "pendingMonsterAttack": pending_data, "pendingReaction": reaction_data, "activeTurn": active_turn_data, "undoState": undo_data, "fumbledItems": fumbled_data, "characterWeaponModes": weapon_modes, "guardingActorIds": guarding_actor_ids(), "retreatedCharacterIds": retreated_character_ids(), "attackedActorIds": attacked_actor_ids(), "bleedingCharacterIds": bleeding_character_ids(), "turnUndeadActorIds": turn_undead_actor_ids(), "spellDeathMacroQueue": _spell_death_macro_queue.duplicate(), "spellMacroActorId": _spell_macro_actor_id, "spellMacroAdvancesTurn": _spell_macro_advances_turn, "persistentFields": _persistent_fields.map(func(field: PersistentCombatFieldType) -> Dictionary: return field.to_data()), "persistentFieldCollisionSlots": persistent_field_collision_slots(), "battlefield": null if battlefield == null else battlefield.to_data()}


static func from_data(data: Variant) -> CombatState:
	if not data is Dictionary:
		return null
	for field: String in ["battleId", "round", "turnIndex", "completed", "outcome", "turnOrder", "monsters"]:
		if not data.has(field):
			return null
	var loaded_round := _integer(data["round"])
	var loaded_turn := _integer(data["turnIndex"])
	var loaded_macro := _signed_integer(data.get("macroId", 0))
	if not data["battleId"] is String or data["battleId"].is_empty() or loaded_macro == -100_000 or loaded_round < 1 or loaded_turn < 0 or not data["completed"] is bool or not data["outcome"] is String or not data["turnOrder"] is Array or not data["monsters"] is Array:
		return null
	var loaded_monsters: Array[MonsterState] = []
	for entry: Variant in data["monsters"]:
		var monster := MonsterState.from_data(entry)
		if monster == null:
			return null
		loaded_monsters.append(monster)
	var loaded_battlefield: BattlefieldState = null
	if data.get("battlefield") != null:
		loaded_battlefield = BattlefieldState.from_data(data["battlefield"])
		if loaded_battlefield == null:
			return null
	var result := CombatState.new(data["battleId"], loaded_monsters, loaded_macro, loaded_battlefield)
	var order: Array[String] = []
	for entry: Variant in data["turnOrder"]:
		if not entry is String or entry.is_empty():
			return null
		order.append(entry)
	result.round_number = loaded_round
	result.turn_index = loaded_turn
	result.completed = data["completed"]
	result.outcome = StringName(data["outcome"])
	if not data.get("rewardsStarted", false) is bool or not data.get("rewardsCompleted", false) is bool:
		return null
	result.rewards_started = data.get("rewardsStarted", false)
	result.rewards_completed = data.get("rewardsCompleted", false)
	result.classic_post_battle_sentinel = _integer(data.get("classicPostBattleSentinel", 0))
	if result.classic_post_battle_sentinel not in [0, 8]:
		return null
	if result.rewards_completed and not result.rewards_started:
		return null
	result._turn_order = order
	if not _restore_actor_sets(result, data, order) or not _restore_spell_macro_state(result, data) or not _restore_persistent_fields(result, data, order) or not _restore_inventory_and_modes(result, data, order) or not _restore_pending_state(result, data) or not _loaded_state_is_consistent(result):
		return null
	return result


static func _restore_actor_sets(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var sets: Array = [
		[data.get("guardingActorIds", []), result._guarding_actor_ids, order.size(), false],
		[data.get("attackedActorIds", []), result._attacked_actor_ids, order.size(), false],
		[data.get("bleedingCharacterIds", []), result._bleeding_character_ids, 6, true],
		[data.get("turnUndeadActorIds", []), result._turned_undead_actor_ids, 6, true],
		[data.get("retreatedCharacterIds", []), result._retreated_character_ids, 6, true],
	]
	for descriptor: Array in sets:
		var values: Variant = descriptor[0]
		var target: Dictionary = descriptor[1]
		var maximum: int = descriptor[2]
		var characters_only: bool = descriptor[3]
		if not values is Array or values.size() > maximum: return false
		for actor_id: Variant in values:
			if not actor_id is String or actor_id.is_empty() or not order.has(actor_id) or target.has(actor_id): return false
			if characters_only and result.monster_by_id(actor_id) != null: return false
			target[actor_id] = true
	return true


static func _restore_spell_macro_state(result: CombatState, data: Dictionary) -> bool:
	var queue: Variant = data.get("spellDeathMacroQueue", [])
	var actor: Variant = data.get("spellMacroActorId", "")
	var advances: Variant = data.get("spellMacroAdvancesTurn", false)
	if not queue is Array or queue.size() > MAX_SPELL_DEATH_MACROS or not actor is String or not advances is bool: return false
	for combatant_id: Variant in queue:
		if not combatant_id is String or combatant_id.is_empty() or result.monster_by_id(combatant_id) == null: return false
		result._spell_death_macro_queue.append(combatant_id)
	result._spell_macro_actor_id = actor
	result._spell_macro_advances_turn = advances
	return true


static func _restore_persistent_fields(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var field_data: Variant = data.get("persistentFields", [])
	var collision_data: Variant = data.get("persistentFieldCollisionSlots", [])
	if not field_data is Array or field_data.size() > MAX_PERSISTENT_FIELDS or not collision_data is Array or collision_data.size() > MAX_PERSISTENT_FIELDS:
		return false
	var slots: Dictionary = {}
	for entry: Variant in field_data:
		var field := PersistentCombatFieldType.from_data(entry)
		if field == null or slots.has(field.slot) or field.phase_turn_index >= order.size() or not order.has(field.caster_id):
			return false
		slots[field.slot] = true
		result._persistent_fields.append(field)
	for value: Variant in collision_data:
		var slot := _integer(value)
		if slot < 0 or slot >= MAX_PERSISTENT_FIELDS or not slots.has(slot) or result._persistent_field_collision_slots.has(slot):
			return false
		result._persistent_field_collision_slots[slot] = true
	return true


static func _restore_inventory_and_modes(result: CombatState, data: Dictionary, order: Array[String]) -> bool:
	var modes: Variant = data.get("characterWeaponModes", {})
	if not modes is Dictionary or modes.size() > 6: return false
	for actor_id: Variant in modes:
		var mode: Variant = modes[actor_id]
		if not actor_id is String or actor_id.is_empty() or not mode is String or mode not in ["melee", "missile"] or not order.has(actor_id) or result.monster_by_id(actor_id) != null: return false
		result._character_weapon_modes[actor_id] = mode
	var items: Array[ItemInstance] = []
	var item_ids: Dictionary = {}
	var item_data: Variant = data.get("fumbledItems", [])
	if not item_data is Array or item_data.size() > MAX_FUMBLED_ITEMS: return false
	for entry: Variant in item_data:
		var item := ItemInstance.from_data(entry)
		if item == null or item.equipped or item_ids.has(item.id): return false
		item_ids[item.id] = true
		items.append(item)
	result._fumbled_items = items
	return true


static func _restore_pending_state(result: CombatState, data: Dictionary) -> bool:
	var active_data: Variant = data.get("activeTurn")
	if active_data != null:
		result.active_turn = CombatTurnState.from_data(active_data)
		if result.active_turn == null: return false
	var undo_data: Variant = data.get("undoState")
	if undo_data != null:
		result.undo_state = _undo_from_data(undo_data)
		if result.undo_state == null: return false
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
	if (result._turn_order.is_empty() and result.turn_index != 0) or (not result._turn_order.is_empty() and result.turn_index >= result._turn_order.size()): return false
	if result.active_turn != null and (result.completed or result.active_turn.actor_id != result.active_actor_id()): return false
	if result.active_turn != null and not result.active_turn.staged_item_instance_id.is_empty() and result.monster_by_id(result.active_turn.actor_id) != null: return false
	if result.undo_state != null and (result.completed or result.active_turn == null or result.battlefield == null or result.undo_state.actor_id != result.active_actor_id() or result.undo_state.actor_id != result.active_turn.actor_id or result.undo_state.round_number != result.round_number or result.undo_state.turn_index != result.turn_index or not result.battlefield.has_actor(result.undo_state.actor_id)): return false
	if result._spell_death_macro_queue.is_empty() != result._spell_macro_actor_id.is_empty() or (not result._spell_macro_actor_id.is_empty() and (result.completed or result.active_actor_id() != result._spell_macro_actor_id)): return false
	if result._spell_death_macro_queue.is_empty() and result._spell_macro_advances_turn: return false
	if result.pending_reaction != null and (result.completed or result.active_turn == null or result.active_actor_id() != result.pending_reaction.mover_id or result.active_turn.actor_id != result.pending_reaction.mover_id): return false
	if result.pending_monster_attack == null: return true
	if result.monster_by_id(result.pending_monster_attack.actor_id) == null: return false
	if result.pending_reaction == null and result.active_actor_id() != result.pending_monster_attack.actor_id: return false
	if result.pending_reaction == null and result.active_turn == null:
		result.active_turn = CombatTurnState.new(result.pending_monster_attack.actor_id)
		result.active_turn.action = result.pending_monster_attack.action
		result.active_turn.attack_index = 1
		result.active_turn.target_id = result.pending_monster_attack.target_id
	if result.pending_reaction == null:
		result.active_turn.physical_action_committed = true
		return result.active_turn.actor_id == result.pending_monster_attack.actor_id and result.active_turn.target_id == result.pending_monster_attack.target_id and result.active_turn.action == result.pending_monster_attack.action and result.active_turn.attack_index >= 1
	var expected_action := &"withdrawal" if result.pending_reaction.phase == CombatReactionState.WITHDRAWAL else &"guard"
	var completed_attackers := result.pending_reaction.attackers().slice(0, result.pending_reaction.next_attacker_index)
	return result.pending_monster_attack.target_id == result.pending_reaction.mover_id and result.pending_monster_attack.action == expected_action and completed_attackers.has(result.pending_monster_attack.actor_id)


static func _undo_from_data(data: Variant) -> RefCounted:
	if not data is Dictionary or data.size() != 5:
		return null
	for field: String in ["actorId", "startPosition", "round", "turnIndex", "available"]:
		if not data.has(field):
			return null
	if not data["actorId"] is String or data["actorId"].is_empty() or not data["available"] is bool:
		return null
	var start_data: Variant = data["startPosition"]
	if not start_data is Array or start_data.size() != 2:
		return null
	var x := _signed_integer(start_data[0])
	var y := _signed_integer(start_data[1])
	var loaded_round := _integer(data["round"])
	var loaded_turn := _integer(data["turnIndex"])
	var position := Vector2i(x, y)
	if x == -100_000 or y == -100_000 or not BattlefieldState.contains(position) or loaded_round < 1 or loaded_turn < 0:
		return null
	var undo := CombatUndoStateType.new(data["actorId"], position, loaded_round, loaded_turn)
	undo.available = data["available"]
	return undo


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
