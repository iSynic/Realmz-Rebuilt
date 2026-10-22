## Owns initiative order, activation progress, and the character undo checkpoint.

class_name CombatTurnSequenceState
extends RefCounted

var round_number: int = 1
var turn_index: int = 0
var active_turn: CombatTurnState
var undo_state: CombatUndoState
var retained_item_powers: Array[CombatItemPowerRoll] = []

var _roster: CombatRosterState
var _turn_order: Array[String] = []
var _actor_ids: Dictionary = {}


func _init(roster: CombatRosterState) -> void:
	_roster = roster


func turn_order() -> Array[String]:
	return _turn_order.duplicate()


func set_turn_order(order: Array[String]) -> void:
	_turn_order = order.duplicate()
	_actor_ids.clear()
	for actor_id: String in _turn_order:
		_actor_ids[actor_id] = true
	turn_index = 0
	_reset_activation()


func active_actor_id() -> String:
	return "" if _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size() else _turn_order[turn_index]


func has_actor(actor_id: String) -> bool:
	return _actor_ids.has(actor_id)


func advance_turn() -> bool:
	if _turn_order.is_empty():
		return false
	_reset_activation()
	turn_index += 1
	if turn_index < _turn_order.size():
		return false
	turn_index = 0
	round_number += 1
	return true


func delay_active_actor() -> bool:
	if _turn_order.is_empty() or turn_index < 0 or turn_index >= _turn_order.size():
		return false
	_reset_activation()
	if turn_index >= _turn_order.size() - 1:
		turn_index = 0
		round_number += 1
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


func stage_random_item_power(actor_id: String, instance_id: String, power: int, retained_definition_id: String = "") -> bool:
	if active_turn == null or active_turn.actor_id != actor_id or actor_id != active_actor_id() or _roster.monster_by_id(actor_id) != null or instance_id.is_empty() or power < 1 or power > 7 or not active_turn.staged_item_instance_id.is_empty() and retained_definition_id.is_empty():
		return false
	if not retained_definition_id.is_empty() and not _retain_item_power(instance_id, retained_definition_id, power):
		return false
	active_turn.staged_item_instance_id = instance_id
	active_turn.staged_item_power = power
	return true


func staged_random_item_power(actor_id: String, instance_id: String) -> int:
	if actor_id != active_actor_id():
		return 0
	if active_turn != null and active_turn.actor_id == actor_id and active_turn.staged_item_instance_id == instance_id:
		return active_turn.staged_item_power
	for roll: CombatItemPowerRoll in retained_item_powers:
		if roll.instance_id == instance_id:
			return roll.power
	return 0


func staged_random_item_instance_id() -> String:
	return "" if active_turn == null else active_turn.staged_item_instance_id


func clear_staged_random_item_power() -> void:
	if active_turn == null:
		return
	active_turn.staged_item_instance_id = ""
	active_turn.staged_item_power = 0


func begin_character_undo(actor_id: String, battlefield: BattlefieldState) -> bool:
	if active_turn == null or active_turn.actor_id != actor_id or active_actor_id() != actor_id or battlefield == null or not battlefield.actors.has_actor(actor_id) or _roster.monster_by_id(actor_id) != null:
		return false
	undo_state = CombatUndoState.new(actor_id, battlefield.actors.actor_position(actor_id), round_number, turn_index)
	return true


func clear_active_turn() -> void:
	_reset_activation()


func invalidate_undo() -> void:
	if undo_state != null:
		undo_state.available = false


func restart_active_turn_after_undo() -> void:
	active_turn = null
	undo_state = null


func append_turn_actor(actor_id: String) -> void:
	if not actor_id.is_empty() and not _actor_ids.has(actor_id):
		_turn_order.append(actor_id)
		_actor_ids[actor_id] = true


func _retain_item_power(instance_id: String, definition_id: String, power: int) -> bool:
	# FD-COMBAT-022: free cancellation never buys another draw for this instance.
	for roll: CombatItemPowerRoll in retained_item_powers:
		if roll.instance_id == instance_id:
			return roll.definition_id == definition_id and roll.power == power
	retained_item_powers.append(CombatItemPowerRoll.new(instance_id, definition_id, power))
	return true


func consume_random_item_power(instance_id: String) -> void:
	retained_item_powers = retained_item_powers.filter(func(roll: CombatItemPowerRoll) -> bool: return roll.instance_id != instance_id)
	if staged_random_item_instance_id() == instance_id:
		clear_staged_random_item_power()


func _reset_activation() -> void:
	active_turn = null
	undo_state = null
	retained_item_powers.clear()
