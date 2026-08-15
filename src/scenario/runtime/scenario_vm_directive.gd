class_name ScenarioVmDirective
extends RefCounted

const FINISH: StringName = &"finish"
const BRANCH_XAP: StringName = &"branch-xap"
const BRANCH_PROGRAM: StringName = &"branch-program"

var kind: StringName
var target_id: int = -1
var gosub: bool
var program_id: String
var context: ScenarioExecutionContext = ScenarioExecutionContext.empty()


func _init(directive_kind: StringName) -> void:
	kind = directive_kind


static func finish() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(FINISH)


static func branch_xap(target: int, use_gosub: bool) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(BRANCH_XAP)
	directive.target_id = target
	directive.gosub = use_gosub
	return directive


static func branch_program(program: String, use_gosub: bool, frame_context: ScenarioExecutionContext) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(BRANCH_PROGRAM)
	directive.program_id = program
	directive.gosub = use_gosub
	directive.context = ScenarioExecutionContext.empty() if frame_context == null else frame_context.copy()
	return directive


func copy() -> ScenarioVmDirective:
	return from_data(to_data())


func to_data() -> Dictionary:
	match kind:
		FINISH:
			return {"kind": String(kind)}
		BRANCH_XAP:
			return {"kind": String(kind), "targetId": target_id, "gosub": gosub}
		BRANCH_PROGRAM:
			return {"kind": String(kind), "programId": program_id, "gosub": gosub, "context": context.to_data()}
	return {}


static func from_data(value: Variant) -> ScenarioVmDirective:
	if not value is Dictionary or not value.get("kind") is String:
		return null
	match StringName(value["kind"]):
		FINISH:
			return finish() if value.size() == 1 else null
		BRANCH_XAP:
			if value.size() != 3 or not value.get("targetId") is int or not value.get("gosub") is bool:
				return null
			return branch_xap(value["targetId"], value["gosub"])
		BRANCH_PROGRAM:
			if value.size() != 4 or not value.get("programId") is String or value["programId"].is_empty() or not value.get("gosub") is bool or not value.get("context") is Dictionary:
				return null
			var restored_context := ScenarioExecutionContext.from_data(value["context"])
			return null if restored_context == null else branch_program(value["programId"], value["gosub"], restored_context)
	return null
