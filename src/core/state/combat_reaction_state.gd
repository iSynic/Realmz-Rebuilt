class_name CombatReactionState
extends RefCounted

const CHARACTER_MOVE: StringName = &"character-move"
const MONSTER_MOVE: StringName = &"monster-move"
const MONSTER_RETREAT: StringName = &"monster-retreat"
const MONSTER_CONTACT: StringName = &"monster-contact"
const GUARD_BEFORE: StringName = &"guard-before"
const WITHDRAWAL: StringName = &"withdrawal"
const GUARD_AFTER: StringName = &"guard-after"

var kind: StringName
var mover_id: String
var origin: Vector2i
var destination: Vector2i
var movement_cost: int
var phase: StringName = GUARD_BEFORE
var next_attacker_index: int = 0
var mover_killed: bool = false
var auto_switch_to_melee: bool = false
var friendly_collision_action: StringName = &""
var friendly_collision_target_id: String = ""
var _attacker_ids: Array[String] = []
var _origin_hostile_ids: Array[String] = []


func _init(reaction_kind: StringName, source_mover_id: String, source_origin: Vector2i, source_destination: Vector2i, source_movement_cost: int) -> void:
	kind = reaction_kind
	mover_id = source_mover_id
	origin = source_origin
	destination = source_destination
	movement_cost = source_movement_cost


func attackers() -> Array[String]:
	return _attacker_ids.duplicate()


func origin_hostiles() -> Array[String]:
	return _origin_hostile_ids.duplicate()


func set_origin_hostiles(actor_ids: Array[String]) -> void:
	_origin_hostile_ids = actor_ids.duplicate()


func set_phase(next_phase: StringName, attacker_ids: Array[String]) -> void:
	phase = next_phase
	_attacker_ids = attacker_ids.duplicate()
	next_attacker_index = 0


func has_next_attacker() -> bool:
	return next_attacker_index < _attacker_ids.size()


func take_next_attacker() -> String:
	if not has_next_attacker():
		return ""
	var result := _attacker_ids[next_attacker_index]
	next_attacker_index += 1
	return result


func to_data() -> Dictionary:
	return {
		"kind": String(kind),
		"moverId": mover_id,
		"origin": [origin.x, origin.y],
		"destination": [destination.x, destination.y],
		"movementCost": movement_cost,
		"phase": String(phase),
		"attackerIds": _attacker_ids.duplicate(),
		"originHostileIds": _origin_hostile_ids.duplicate(),
		"nextAttackerIndex": next_attacker_index,
		"moverKilled": mover_killed,
		"autoSwitchToMelee": auto_switch_to_melee,
		"friendlyCollisionAction": String(friendly_collision_action),
		"friendlyCollisionTargetId": friendly_collision_target_id,
	}


static func from_data(data: Variant) -> CombatReactionState:
	if not data is Dictionary or data.size() not in [10, 11, 13]:
		return null
	if (data.size() == 11 and not data.has("autoSwitchToMelee")) or (data.size() == 13 and (not data.has("autoSwitchToMelee") or not data.has("friendlyCollisionAction") or not data.has("friendlyCollisionTargetId"))):
		return null
	for field: String in ["kind", "moverId", "origin", "destination", "movementCost", "phase", "attackerIds", "originHostileIds", "nextAttackerIndex", "moverKilled"]:
		if not data.has(field):
			return null
	if not data["kind"] is String or data["kind"] not in [String(CHARACTER_MOVE), String(MONSTER_MOVE), String(MONSTER_RETREAT), String(MONSTER_CONTACT)] or not data["moverId"] is String or data["moverId"].is_empty() or not data["phase"] is String or data["phase"] not in [String(GUARD_BEFORE), String(WITHDRAWAL), String(GUARD_AFTER)] or not data["attackerIds"] is Array or not data["originHostileIds"] is Array or not data["moverKilled"] is bool:
		return null
	if data.has("autoSwitchToMelee") and not data["autoSwitchToMelee"] is bool:
		return null
	if data.has("friendlyCollisionAction") and (not data["friendlyCollisionAction"] is String or data["friendlyCollisionAction"] not in ["", "swap", "attack"] or not data.get("friendlyCollisionTargetId") is String):
		return null
	var auto_switch: bool = bool(data.get("autoSwitchToMelee", false))
	var collision_action := StringName(data.get("friendlyCollisionAction", ""))
	var collision_target_id: String = data.get("friendlyCollisionTargetId", "")
	if auto_switch and (data["kind"] != String(CHARACTER_MOVE) or data["phase"] != String(GUARD_BEFORE)):
		return null
	if collision_action.is_empty() != collision_target_id.is_empty() or (not collision_action.is_empty() and data["kind"] != String(CHARACTER_MOVE)):
		return null
	var source_origin := _coordinate(data["origin"])
	var source_destination := _coordinate(data["destination"])
	var cost := _integer(data["movementCost"])
	var attacker_index := _integer(data["nextAttackerIndex"])
	var stationary_contact: bool = data["kind"] == String(MONSTER_CONTACT) and source_destination == source_origin
	if source_origin.x < 0 or source_destination.x < 0 or absi(source_destination.x - source_origin.x) > 1 or absi(source_destination.y - source_origin.y) > 1 or (source_destination == source_origin and not stationary_contact) or (stationary_contact and cost != 0) or cost < 0 or attacker_index < 0 or attacker_index > data["attackerIds"].size():
		return null
	if data["kind"] == String(MONSTER_CONTACT) and data["phase"] != String(GUARD_AFTER):
		return null
	if data["kind"] in [String(MONSTER_MOVE), String(MONSTER_RETREAT)] and data["phase"] not in [String(WITHDRAWAL), String(GUARD_AFTER)]:
		return null
	if data["kind"] not in [String(CHARACTER_MOVE), String(MONSTER_RETREAT)] and not data["originHostileIds"].is_empty():
		return null
	var attacker_ids: Array[String] = []
	var seen: Dictionary = {}
	for entry: Variant in data["attackerIds"]:
		if not entry is String or entry.is_empty() or entry == data["moverId"] or seen.has(entry):
			return null
		seen[entry] = true
		attacker_ids.append(entry)
	var origin_hostile_ids: Array[String] = []
	var hostile_seen: Dictionary = {}
	for entry: Variant in data["originHostileIds"]:
		if not entry is String or entry.is_empty() or entry == data["moverId"] or hostile_seen.has(entry):
			return null
		hostile_seen[entry] = true
		origin_hostile_ids.append(entry)
	var result := CombatReactionState.new(StringName(data["kind"]), data["moverId"], source_origin, source_destination, cost)
	result.phase = StringName(data["phase"])
	result._attacker_ids = attacker_ids
	result._origin_hostile_ids = origin_hostile_ids
	result.next_attacker_index = attacker_index
	result.mover_killed = data["moverKilled"]
	result.auto_switch_to_melee = auto_switch
	result.friendly_collision_action = collision_action
	result.friendly_collision_target_id = collision_target_id
	return result


static func _coordinate(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2:
		return Vector2i(-1, -1)
	var x := _integer(value[0])
	var y := _integer(value[1])
	if x < 0 or x >= BattlefieldState.SIZE or y < 0 or y >= BattlefieldState.SIZE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
