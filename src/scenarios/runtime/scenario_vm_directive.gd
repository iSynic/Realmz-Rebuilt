## Defines the typed scenario VM directive boundary used by the scenario VM.

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
const DROPOUT: StringName = &"dropout"
const CLOCK_TIMER_RETURN: StringName = &"clock-timer-return"
const RECHECK_PROGRAM: StringName = &"recheck-program"
const PUSH_CLASSIC_RETURN: StringName = &"push-classic-return"

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


static func push_classic_return() -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(PUSH_CLASSIC_RETURN)
	directive.gosub = true
	return directive


static func dropout() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(DROPOUT)


static func clock_timer_return(program: String, cursor: int, frame_context: ScenarioExecutionContext = null) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(CLOCK_TIMER_RETURN)
	directive.program_id = program
	directive.entry_cursor = cursor
	directive.context = ScenarioExecutionContext.empty() if frame_context == null else frame_context.copy()
	return directive


func copy() -> ScenarioVmDirective:
	return from_data(to_data())


func to_data() -> Dictionary:
	match kind:
		FINISH, FINISH_TIMELINE, RESUME_AFTER_ENCOUNTER, RESTART_CURRENT_PROGRAM, DROPOUT, PUSH_CLASSIC_RETURN:
			return {"kind": String(kind)}
		BRANCH_XAP:
			return {"kind": String(kind), "targetId": target_id, "gosub": gosub}
		CLOCK_TIMER_RETURN, RECHECK_PROGRAM:
			return {"kind": String(kind), "programId": program_id, "entryCursor": entry_cursor, "context": ScenarioExecutionContextCodec.encode(context)}
		BRANCH_PROGRAM:
			var data := {"kind": String(kind), "programId": program_id, "gosub": gosub, "context": ScenarioExecutionContextCodec.encode(context)}
			if entry_cursor != 0:
				data["entryCursor"] = entry_cursor
			return data
		ENTER_ENCOUNTER:
			return {"kind": String(kind), "encounterKind": String(encounter_kind), "encounterId": target_id, "gosub": gosub}
		BRANCH_ENCOUNTER_RESULT:
			return {"kind": String(kind), "programId": program_id, "gosub": gosub, "context": ScenarioExecutionContextCodec.encode(context), "repeatEncounter": repeat_encounter}
	return {}


static func from_data(value: Variant) -> ScenarioVmDirective:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if not data.get("kind") is String:
		return null
	var kind_text: String = data["kind"]
	if StringName(kind_text) in [FINISH, FINISH_TIMELINE, RESUME_AFTER_ENCOUNTER, RESTART_CURRENT_PROGRAM, DROPOUT, PUSH_CLASSIC_RETURN]:
		return _empty_directive(StringName(kind_text)) if data.size() == 1 else null
	match StringName(kind_text):
		BRANCH_XAP:
			if data.size() != 3 or not data.get("targetId") is int or not data.get("gosub") is bool:
				return null
			var target: int = data["targetId"]
			var use_gosub: bool = data["gosub"]
			return branch_xap(target, use_gosub)
		BRANCH_PROGRAM:
			var cursor_value: Variant = data.get("entryCursor", 0)
			if data.size() not in [4, 5] or (data.size() == 5 and not data.has("entryCursor")) or _nonempty_string(data.get("programId")).is_empty() or not data.get("gosub") is bool or not data.get("context") is Dictionary or not _whole_number(cursor_value) or cursor_value < 0 or cursor_value > 4096:
				return null
			var restored_context := ScenarioExecutionContextCodec.decode(data["context"])
			var program: String = data["programId"]
			var use_gosub: bool = data["gosub"]
			var cursor: int = cursor_value
			return null if restored_context == null else branch_program_at(program, use_gosub, restored_context, cursor)
		CLOCK_TIMER_RETURN, RECHECK_PROGRAM:
			var cursor_value: Variant = data.get("entryCursor")
			var restored_context := ScenarioExecutionContextCodec.decode(data.get("context"))
			if data.size() != 4 or restored_context == null or _nonempty_string(data.get("programId")).is_empty() or not _whole_number(cursor_value) or cursor_value < 0 or cursor_value > 4096: return null
			var program: String = data["programId"]
			var cursor: int = cursor_value
			var directive := clock_timer_return(program, cursor, restored_context)
			directive.kind = StringName(kind_text)
			return directive
		ENTER_ENCOUNTER:
			var encounter_kind_value: Variant = data.get("encounterKind")
			var encounter_id_value: Variant = data.get("encounterId")
			if data.size() != 4 or not encounter_kind_value is String or encounter_kind_value not in ["simple", "complex"] or not _whole_number(encounter_id_value) or encounter_id_value < 0 or not data.get("gosub") is bool:
				return null
			var encounter_kind_text: String = encounter_kind_value
			var encounter_id: int = encounter_id_value
			var use_gosub: bool = data["gosub"]
			return enter_encounter(StringName(encounter_kind_text), encounter_id, use_gosub)
		BRANCH_ENCOUNTER_RESULT:
			if data.size() != 5 or _nonempty_string(data.get("programId")).is_empty() or not data.get("gosub") is bool or not data.get("context") is Dictionary or not data.get("repeatEncounter") is bool:
				return null
			var restored_context := ScenarioExecutionContextCodec.decode(data["context"])
			var program: String = data["programId"]
			var use_gosub: bool = data["gosub"]
			var repeat: bool = data["repeatEncounter"]
			return null if restored_context == null else branch_encounter_result(program, use_gosub, restored_context, repeat)
	return null


static func _empty_directive(kind_value: StringName) -> ScenarioVmDirective:
	match kind_value:
		FINISH: return finish()
		FINISH_TIMELINE: return finish_timeline()
		RESUME_AFTER_ENCOUNTER: return resume_after_encounter()
		RESTART_CURRENT_PROGRAM: return restart_current_program()
		DROPOUT: return dropout()
		PUSH_CLASSIC_RETURN: return push_classic_return()
	return null


static func _whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	var number: float = value
	return not is_nan(number) and not is_inf(number) and number == floorf(number)


static func _nonempty_string(value: Variant) -> String:
	if not value is String:
		return ""
	var text: String = value
	return text
