## Defines the typed scenario battle caller boundary used by the scenario VM.

class_name ScenarioBattleCaller
extends RefCounted

const VERSION: int = 1
const SAFE: StringName = &"safe"
const CLASSIC: StringName = &"classic"
const SAFE_POLICY: StringName = &"continue"

var kind: StringName
var policy: StringName
var opcode: int
var gosub: bool
var mode: int
var branch_target: int


func _init(caller_kind: StringName = &"") -> void:
	kind = caller_kind


static func safe_continue() -> ScenarioBattleCaller:
	var result := ScenarioBattleCaller.new(SAFE)
	result.policy = SAFE_POLICY
	return result


static func classic(opcode_value: int, use_gosub: bool, battle_mode: int, target: int) -> ScenarioBattleCaller:
	var result := ScenarioBattleCaller.new(CLASSIC)
	result.opcode = opcode_value
	result.gosub = use_gosub
	result.mode = battle_mode
	result.branch_target = target
	return result


func copy() -> ScenarioBattleCaller:
	var duplicate := from_data(to_data())
	if duplicate == null:
		push_error("A live typed battle caller must round-trip through its wire codec.")
	return duplicate


func to_data() -> Dictionary:
	match kind:
		SAFE:
			if policy != SAFE_POLICY:
				return {}
			return {"kind": String(kind), "version": VERSION, "data": {"policy": String(policy)}}
		CLASSIC:
			if opcode not in [2, 48, 56, 107]:
				return {}
			return {
				"kind": String(kind),
				"version": VERSION,
				"data": {
					"opcode": opcode,
					"gosub": gosub,
					"mode": mode,
					"branchTarget": branch_target,
				},
			}
	return {}


static func from_data(value: Variant) -> ScenarioBattleCaller:
	if not value is Dictionary:
		return null
	var envelope: Dictionary = value
	if envelope.size() != 3 or not envelope.get("kind") is String or _integer(envelope.get("version")) != VERSION or not envelope.get("data") is Dictionary:
		return null
	var data: Dictionary = envelope["data"]
	var kind_text: String = envelope["kind"]
	match StringName(kind_text):
		SAFE:
			if data.size() != 1 or not data.get("policy") is String or data["policy"] != String(SAFE_POLICY):
				return null
			return safe_continue()
		CLASSIC:
			if data.size() != 4 or not data.get("gosub") is bool:
				return null
			var parsed_opcode: Variant = _integer(data.get("opcode"))
			var parsed_mode: Variant = _integer(data.get("mode"))
			var parsed_branch_target: Variant = _integer(data.get("branchTarget"))
			if parsed_opcode == null or parsed_mode == null or parsed_branch_target == null:
				return null
			var opcode: int = parsed_opcode
			if opcode not in [2, 48, 56, 107]:
				return null
			var use_gosub: bool = data["gosub"]
			var mode: int = parsed_mode
			var branch_target: int = parsed_branch_target
			return classic(opcode, use_gosub, mode, branch_target)
	return null


static func _integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)):
			return int(number)
	return null
