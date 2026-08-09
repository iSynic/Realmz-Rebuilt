class_name CombatState
extends RefCounted

const MAX_FUMBLED_ITEMS: int = 20

var battle_id: String
var macro_id: int = 0
var round_number: int = 1
var turn_index: int = 0
var completed: bool = false
var outcome: StringName = &"active"
var battlefield: BattlefieldState
var pending_monster_attack: PendingMonsterAttack
var pending_reaction: CombatReactionState
var active_turn: CombatTurnState
var _turn_order: Array[String] = []
var _monsters: Array[MonsterState] = []
var _fumbled_items: Array[ItemInstance] = []
var _character_weapon_modes: Dictionary = {}
var _guarding_actor_ids: Dictionary = {}
var _retreated_character_ids: Dictionary = {}


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


func advance_turn() -> void:
	if _turn_order.is_empty():
		return
	active_turn = null
	turn_index += 1
	if turn_index >= _turn_order.size():
		turn_index = 0
		round_number += 1


func begin_active_turn() -> CombatTurnState:
	var actor_id := active_actor_id()
	if actor_id.is_empty():
		return null
	if active_turn == null:
		active_turn = CombatTurnState.new(actor_id)
	return active_turn


func clear_active_turn() -> void:
	active_turn = null


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
	return {"battleId": battle_id, "macroId": macro_id, "round": round_number, "turnIndex": turn_index, "completed": completed, "outcome": String(outcome), "turnOrder": _turn_order.duplicate(), "monsters": monster_data, "pendingMonsterAttack": pending_data, "pendingReaction": reaction_data, "activeTurn": active_turn_data, "fumbledItems": fumbled_data, "characterWeaponModes": weapon_modes, "guardingActorIds": guarding_actor_ids(), "retreatedCharacterIds": retreated_character_ids(), "battlefield": null if battlefield == null else battlefield.to_data()}


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
	result._turn_order = order
	var guarding_data: Variant = data.get("guardingActorIds", [])
	if not guarding_data is Array or guarding_data.size() > order.size():
		return null
	for actor_id: Variant in guarding_data:
		if not actor_id is String or actor_id.is_empty() or not order.has(actor_id) or result._guarding_actor_ids.has(actor_id):
			return null
		result._guarding_actor_ids[actor_id] = true
	var retreated_data: Variant = data.get("retreatedCharacterIds", [])
	if not retreated_data is Array or retreated_data.size() > 6:
		return null
	for actor_id: Variant in retreated_data:
		if not actor_id is String or actor_id.is_empty() or not order.has(actor_id) or result.monster_by_id(actor_id) != null or result._retreated_character_ids.has(actor_id):
			return null
		result._retreated_character_ids[actor_id] = true
	var weapon_modes: Variant = data.get("characterWeaponModes", {})
	if not weapon_modes is Dictionary or weapon_modes.size() > 6:
		return null
	for actor_id: Variant in weapon_modes:
		var mode: Variant = weapon_modes[actor_id]
		if not actor_id is String or actor_id.is_empty() or not mode is String or mode not in ["melee", "missile"] or not order.has(actor_id) or result.monster_by_id(actor_id) != null:
			return null
		result._character_weapon_modes[actor_id] = mode
	var loaded_fumbled_items: Array[ItemInstance] = []
	var fumbled_ids: Dictionary = {}
	var fumbled_data: Variant = data.get("fumbledItems", [])
	if not fumbled_data is Array or fumbled_data.size() > MAX_FUMBLED_ITEMS:
		return null
	for entry: Variant in fumbled_data:
		var item := ItemInstance.from_data(entry)
		if item == null or item.equipped or fumbled_ids.has(item.id):
			return null
		fumbled_ids[item.id] = true
		loaded_fumbled_items.append(item)
	result._fumbled_items = loaded_fumbled_items
	var active_turn_data: Variant = data.get("activeTurn")
	if active_turn_data != null:
		result.active_turn = CombatTurnState.from_data(active_turn_data)
		if result.active_turn == null:
			return null
	var pending_data: Variant = data.get("pendingMonsterAttack")
	if pending_data != null:
		result.pending_monster_attack = PendingMonsterAttack.from_data(pending_data)
		if result.pending_monster_attack == null:
			return null
	var reaction_data: Variant = data.get("pendingReaction")
	if reaction_data != null:
		result.pending_reaction = CombatReactionState.from_data(reaction_data)
		if result.pending_reaction == null:
			return null
	if (result._turn_order.is_empty() and result.turn_index != 0) or (not result._turn_order.is_empty() and result.turn_index >= result._turn_order.size()):
		return null
	if result.active_turn != null and (result.completed or result.active_turn.actor_id != result.active_actor_id()):
		return null
	if result.pending_reaction != null and (result.completed or result.active_turn == null or result.active_actor_id() != result.pending_reaction.mover_id or result.active_turn.actor_id != result.pending_reaction.mover_id):
		return null
	if result.pending_monster_attack != null and result.monster_by_id(result.pending_monster_attack.actor_id) == null:
		return null
	if result.pending_monster_attack != null and result.pending_reaction == null and result.active_actor_id() != result.pending_monster_attack.actor_id:
		return null
	if result.pending_monster_attack != null and result.pending_reaction == null and result.active_turn == null:
		result.active_turn = CombatTurnState.new(result.pending_monster_attack.actor_id)
		result.active_turn.action = result.pending_monster_attack.action
		result.active_turn.attack_index = 1
		result.active_turn.target_id = result.pending_monster_attack.target_id
	if result.pending_monster_attack != null and result.pending_reaction == null:
		result.active_turn.physical_action_committed = true
	if result.pending_monster_attack != null and result.pending_reaction == null and (result.active_turn.actor_id != result.pending_monster_attack.actor_id or result.active_turn.target_id != result.pending_monster_attack.target_id or result.active_turn.action != result.pending_monster_attack.action or result.active_turn.attack_index < 1):
		return null
	if result.pending_monster_attack != null and result.pending_reaction != null:
		var expected_action := &"withdrawal" if result.pending_reaction.phase == CombatReactionState.WITHDRAWAL else &"guard"
		var completed_attackers := result.pending_reaction.attackers().slice(0, result.pending_reaction.next_attacker_index)
		if result.pending_monster_attack.target_id != result.pending_reaction.mover_id or result.pending_monster_attack.action != expected_action or not completed_attackers.has(result.pending_monster_attack.actor_id):
			return null
	return result


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
