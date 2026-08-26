class_name ScenarioVmDirective
extends RefCounted

const FINISH: StringName = &"finish"
const FINISH_TIMELINE: StringName = &"finish-timeline"
const RESUME_AFTER_ENCOUNTER: StringName = &"resume-after-encounter"
const BRANCH_XAP: StringName = &"branch-xap"
const BRANCH_PROGRAM: StringName = &"branch-program"
const ENTER_ENCOUNTER: StringName = &"enter-encounter"
const BRANCH_ENCOUNTER_RESULT: StringName = &"branch-encounter-result"
const RESTART_CURRENT_PROGRAM: StringName = &"restart-current-program"

var kind: StringName
var target_id: int = -1
var gosub: bool
var program_id: String
var entry_cursor: int = 0
var context: ScenarioExecutionContext = ScenarioExecutionContext.empty()
var repeat_encounter: bool
var encounter_kind: StringName


func _init(directive_kind: StringName) -> void:
	kind = directive_kind


static func finish() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(FINISH)


static func finish_timeline() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(FINISH_TIMELINE)


static func resume_after_encounter() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(RESUME_AFTER_ENCOUNTER)


static func branch_xap(target: int, use_gosub: bool) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(BRANCH_XAP)
	directive.target_id = target
	directive.gosub = use_gosub
	return directive


static func branch_program(program: String, use_gosub: bool, frame_context: ScenarioExecutionContext) -> ScenarioVmDirective:
	return branch_program_at(program, use_gosub, frame_context, 0)


static func branch_program_at(program: String, use_gosub: bool, frame_context: ScenarioExecutionContext, cursor: int) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(BRANCH_PROGRAM)
	directive.program_id = program
	directive.gosub = use_gosub
	directive.entry_cursor = cursor
	directive.context = ScenarioExecutionContext.empty() if frame_context == null else frame_context.copy()
	return directive


static func enter_encounter(kind_value: StringName, encounter_id: int, use_gosub: bool) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(ENTER_ENCOUNTER)
	directive.encounter_kind = kind_value
	directive.target_id = encounter_id
	directive.gosub = use_gosub
	return directive


static func branch_encounter_result(program: String, use_gosub: bool, frame_context: ScenarioExecutionContext, repeat: bool) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(BRANCH_ENCOUNTER_RESULT)
	directive.program_id = program
	directive.gosub = use_gosub
	directive.context = ScenarioExecutionContext.empty() if frame_context == null else frame_context.copy()
	directive.repeat_encounter = repeat
	return directive


static func restart_current_program() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(RESTART_CURRENT_PROGRAM)


func copy() -> ScenarioVmDirective:
	return from_data(to_data())


func to_data() -> Dictionary:
	match kind:
		FINISH, FINISH_TIMELINE, RESUME_AFTER_ENCOUNTER, RESTART_CURRENT_PROGRAM:
			return {"kind": String(kind)}
		BRANCH_XAP:
			return {"kind": String(kind), "targetId": target_id, "gosub": gosub}
		BRANCH_PROGRAM:
			var data := {"kind": String(kind), "programId": program_id, "gosub": gosub, "context": context.to_data()}
			if entry_cursor != 0:
				data["entryCursor"] = entry_cursor
			return data
		ENTER_ENCOUNTER:
			return {"kind": String(kind), "encounterKind": String(encounter_kind), "encounterId": target_id, "gosub": gosub}
		BRANCH_ENCOUNTER_RESULT:
			return {"kind": String(kind), "programId": program_id, "gosub": gosub, "context": context.to_data(), "repeatEncounter": repeat_encounter}
	return {}


static func from_data(value: Variant) -> ScenarioVmDirective:
	if not value is Dictionary or not value.get("kind") is String:
		return null
	match StringName(value["kind"]):
		FINISH:
			return finish() if value.size() == 1 else null
		FINISH_TIMELINE:
			return finish_timeline() if value.size() == 1 else null
		RESUME_AFTER_ENCOUNTER:
			return resume_after_encounter() if value.size() == 1 else null
		RESTART_CURRENT_PROGRAM:
			return restart_current_program() if value.size() == 1 else null
		BRANCH_XAP:
			if value.size() != 3 or not value.get("targetId") is int or not value.get("gosub") is bool:
				return null
			return branch_xap(value["targetId"], value["gosub"])
		BRANCH_PROGRAM:
			var cursor_value: Variant = value.get("entryCursor", 0)
			if value.size() not in [4, 5] or (value.size() == 5 and not value.has("entryCursor")) or not value.get("programId") is String or value["programId"].is_empty() or not value.get("gosub") is bool or not value.get("context") is Dictionary or not _whole_number(cursor_value) or cursor_value < 0 or cursor_value > 4096:
				return null
			var restored_context := ScenarioExecutionContext.from_data(value["context"])
			return null if restored_context == null else branch_program_at(value["programId"], value["gosub"], restored_context, int(cursor_value))
		ENTER_ENCOUNTER:
			var encounter_kind_value: Variant = value.get("encounterKind")
			var encounter_id_value: Variant = value.get("encounterId")
			if value.size() != 4 or not encounter_kind_value is String or encounter_kind_value not in ["simple", "complex"] or not _whole_number(encounter_id_value) or encounter_id_value < 0 or not value.get("gosub") is bool:
				return null
			return enter_encounter(StringName(encounter_kind_value), int(encounter_id_value), value["gosub"])
		BRANCH_ENCOUNTER_RESULT:
			if value.size() != 5 or not value.get("programId") is String or value["programId"].is_empty() or not value.get("gosub") is bool or not value.get("context") is Dictionary or not value.get("repeatEncounter") is bool:
				return null
			var restored_context := ScenarioExecutionContext.from_data(value["context"])
			return null if restored_context == null else branch_encounter_result(value["programId"], value["gosub"], restored_context, value["repeatEncounter"])
	return null


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and not is_nan(value) and not is_inf(value) and value == floorf(value)
