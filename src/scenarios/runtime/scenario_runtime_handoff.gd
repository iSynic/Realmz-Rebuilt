## Defines the typed scenario runtime handoff boundary used by the scenario VM.

class_name ScenarioRuntimeHandoff
extends RefCounted

const VERSION: int = 1
const PARTY_DEFEAT: StringName = &"party-defeat"
const CLASSIC_COMBAT: StringName = &"classic-combat"
const SAFE_COMBAT: StringName = &"safe-combat"
const CLASSIC_HEALTH: StringName = &"classic-health"
const CLASSIC_SPELL: StringName = &"classic-spell"
const CLASSIC_CLOCK: StringName = &"classic-clock"

var kind: StringName
var battle_id: String
var source_kind: StringName
var caller: ScenarioBattleCaller
var effect_opcode: int
var effect_extra_code: Array[int] = []
var effect_target_ids: Array[String] = []
var effect_next_index: int
var clock_continuation: ScenarioRuntimeContinuation
var nested_handoff: ScenarioVmHandoff


func _init(handoff_kind: StringName = &"") -> void:
	kind = handoff_kind


static func clock_timer(continuation: ScenarioRuntimeContinuation, nested: ScenarioVmHandoff) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.source_kind = CLASSIC_CLOCK
	result.clock_continuation = continuation
	result.nested_handoff = nested
	return result


static func party_defeat(battle: String, source: StringName, battle_caller: ScenarioBattleCaller) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.battle_id = battle
	result.source_kind = source
	result.caller = battle_caller.copy() if battle_caller != null else null
	return result


static func character_defeat(opcode: int, extra_code: Array[int], target_ids: Array[String], next_index: int) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.source_kind = CLASSIC_HEALTH if opcode in [15, 16] else CLASSIC_SPELL
	result.effect_opcode = opcode
	result.effect_extra_code.assign(extra_code)
	result.effect_target_ids.assign(target_ids)
	result.effect_next_index = next_index
	return result


func copy() -> ScenarioRuntimeHandoff:
	var duplicate := from_data(to_data())
	if duplicate == null:
		push_error("A live typed runtime handoff must round-trip through its wire codec.")
	return duplicate


func to_data() -> Dictionary:
	if kind == PARTY_DEFEAT and source_kind == CLASSIC_CLOCK:
		return {"kind": String(kind), "version": VERSION, "data": {"sourceKind": String(source_kind), "clockContinuation": clock_continuation.to_data(), "nestedHandoff": nested_handoff.to_data()}}
	if kind == PARTY_DEFEAT and source_kind in [CLASSIC_HEALTH, CLASSIC_SPELL]:
		if not effect_fields_are_valid():
			return {}
		return {"kind": String(kind), "version": VERSION, "data": {"sourceKind": String(source_kind), "opcode": effect_opcode, "extraCode": effect_extra_code.duplicate(), "targetIds": effect_target_ids.duplicate(), "nextIndex": effect_next_index}}
	if kind != PARTY_DEFEAT or battle_id.is_empty() or source_kind not in [CLASSIC_COMBAT, SAFE_COMBAT] or caller == null or not caller_matches_source():
		return {}
	var caller_data := caller.to_data()
	if caller_data.is_empty():
		return {}
	return {
		"kind": String(kind),
		"version": VERSION,
		"data": {
			"battleId": battle_id,
			"sourceKind": String(source_kind),
			"caller": caller_data,
		},
	}


static func from_data(value: Variant, depth: int = 0) -> ScenarioRuntimeHandoff:
	if depth > 32 or not value is Dictionary:
		return null
	var envelope: Dictionary = value
	if envelope.size() != 3 or not envelope.get("kind") is String or _integer(envelope.get("version")) != VERSION or not envelope.get("data") is Dictionary or envelope["kind"] != String(PARTY_DEFEAT):
		return null
	var data: Dictionary = envelope["data"]
	if data.get("sourceKind") == String(CLASSIC_CLOCK):
		if data.size() != 3 or not _bounded_clock_handoffs(data): return null
		var continuation := ScenarioRuntimeContinuation.from_data(data.get("clockContinuation"), depth)
		var nested := ScenarioVmHandoff.from_data(data.get("nestedHandoff"), depth + 1)
		return clock_timer(continuation, nested) if continuation != null and continuation.body is ScenarioClockContinuationBody and nested != null else null
	if data.get("sourceKind") in [String(CLASSIC_HEALTH), String(CLASSIC_SPELL)]:
		if data.size() != 5 or _integer(data.get("opcode")) == null or not data.get("extraCode") is Array or not data.get("targetIds") is Array or _integer(data.get("nextIndex")) == null:
			return null
		var extra: Array[int] = []
		for entry: Variant in data["extraCode"]:
			if _integer(entry) == null:
				return null
			var extra_value: int = entry
			extra.append(extra_value)
		var ids: Array[String] = []
		for entry: Variant in data["targetIds"]:
			if not entry is String:
				return null
			ids.append(entry)
		var opcode: int = data["opcode"]
		var next_index: int = data["nextIndex"]
		var effect_source_kind: String = data["sourceKind"]
		var health := character_defeat(opcode, extra, ids, next_index)
		return health if health.source_kind == StringName(effect_source_kind) and health.effect_fields_are_valid() else null
	if data.size() != 3 or not data.get("battleId") is String:
		return null
	var battle_id: String = data["battleId"]
	if battle_id.is_empty() or not data.get("sourceKind") is String or data["sourceKind"] not in [String(CLASSIC_COMBAT), String(SAFE_COMBAT)]:
		return null
	var source_kind_text: String = data["sourceKind"]
	var parsed_caller := ScenarioBattleCaller.from_data(data.get("caller"))
	if parsed_caller == null:
		return null
	var result := party_defeat(battle_id, StringName(source_kind_text), parsed_caller)
	return result if result.caller_matches_source() else null


static func _bounded_clock_handoffs(data: Dictionary) -> bool:
	for depth: int in 32:
		var nested: Variant = data.get("nestedHandoff")
		if not nested is Dictionary: return false
		var nested_handoff: Dictionary = nested
		if not nested_handoff.get("data") is Dictionary: return false
		var nested_data: Dictionary = nested_handoff["data"]
		var runtime: Variant = nested_data.get("runtime")
		if not runtime is Dictionary: return false
		var runtime_continuation: Dictionary = runtime
		if not runtime_continuation.get("data") is Dictionary: return false
		data = runtime_continuation["data"]
		if data.get("sourceKind") != String(CLASSIC_CLOCK): return true
	return false


func caller_matches_source() -> bool:
	if caller == null:
		return false
	return source_kind == SAFE_COMBAT and caller.kind == ScenarioBattleCaller.SAFE or source_kind == CLASSIC_COMBAT and caller.kind == ScenarioBattleCaller.CLASSIC


func effect_fields_are_valid() -> bool:
	if not battle_id.is_empty() or caller != null or effect_opcode not in ([15, 16] if source_kind == CLASSIC_HEALTH else [17, 18]) or effect_extra_code.size() < (5 if source_kind == CLASSIC_HEALTH else 4) or effect_extra_code.size() > 5 or effect_target_ids.is_empty() or effect_next_index <= 0 or effect_next_index > effect_target_ids.size():
		return false
	var unique_ids := {}
	for id: String in effect_target_ids:
		if id.is_empty() or unique_ids.has(id):
			return false
		unique_ids[id] = true
	return true


static func _integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)):
			return int(number)
	return null
