## Owns the ordered captured death queue and its actor-action continuation.
class_name CombatDeathMacroState
extends RefCounted

const MAX_DEATH_MACROS := 100
var _roster: CombatRosterState
var _turns: CombatTurnSequenceState
var _death_macro_queue: Array[CombatDeathMacroRequest] = []
var _macro_actor_id: String = ""
var _macro_advances_turn: bool = false


func bind(roster: CombatRosterState, turns: CombatTurnSequenceState) -> void:
	_roster = roster
	_turns = turns


func queue(request: CombatDeathMacroRequest) -> bool:
	if request == null or _roster == null or _roster.monster_by_id(request.combatant_id) == null or _death_macro_queue.size() >= MAX_DEATH_MACROS:
		return false
	_death_macro_queue.append(request.copy())
	return true


func begin_sequence(actor_id: String, advances_turn: bool) -> bool:
	if _turns == null or _death_macro_queue.is_empty() or actor_id.is_empty() or actor_id != _turns.active_actor_id() or not _macro_actor_id.is_empty():
		return false
	_macro_actor_id = actor_id
	_macro_advances_turn = advances_turn
	return true


func pending_id() -> String:
	return "" if _death_macro_queue.is_empty() else _death_macro_queue[0].combatant_id


func pending_request() -> CombatDeathMacroRequest:
	return null if _death_macro_queue.is_empty() else _death_macro_queue[0].copy()


func complete(combatant_id: String) -> bool:
	if combatant_id.is_empty() or pending_id() != combatant_id:
		return false
	_death_macro_queue.pop_front()
	return true


func ids() -> Array[String]:
	var result: Array[String] = []
	for request: CombatDeathMacroRequest in _death_macro_queue: result.append(request.combatant_id)
	return result


func facts() -> Array[CombatDeathMacroRequest]:
	var result: Array[CombatDeathMacroRequest] = []
	for request: CombatDeathMacroRequest in _death_macro_queue: result.append(request.copy())
	return result


func actor_id() -> String:
	return _macro_actor_id


func advances_turn() -> bool:
	return _macro_advances_turn


func clear() -> void:
	_death_macro_queue.clear()
	_macro_actor_id = ""
	_macro_advances_turn = false


func restore(facts: Array[CombatDeathMacroRequest], actor_id: String, advances_turn: bool) -> void:
	_death_macro_queue.clear()
	for request: CombatDeathMacroRequest in facts: _death_macro_queue.append(request.copy())
	_macro_actor_id = actor_id
	_macro_advances_turn = advances_turn
