## Defines the typed scenario VM directive boundary used by the scenario VM.

class_name ScenarioVmDirective
extends RefCounted

const NATIVE_RETURN: StringName = &"native-return"
const END_RECORD: StringName = &"end-record"
const BLOWOUT: StringName = &"blowout"
const FINISH: StringName = &"finish"
const FINISH_TIMELINE: StringName = &"finish-timeline"
const KEEP_CODES: StringName = &"keep-codes"
const COPY_RECORD: StringName = &"copy-record"
const RESUME_AFTER_ENCOUNTER: StringName = &"resume-after-encounter"
const BRANCH_XAP: StringName = &"branch-xap"
const BRANCH_PROGRAM: StringName = &"branch-program"
const ENTER_ENCOUNTER: StringName = &"enter-encounter"
const BRANCH_ENCOUNTER_RESULT: StringName = &"branch-encounter-result"
const RESTART_CURRENT_PROGRAM: StringName = &"restart-current-program"
const DROPOUT: StringName = &"dropout"
const CLOCK_TIMER_RETURN: StringName = &"clock-timer-return"
const RESET_CODE: StringName = &"reset-code"
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
var copied_code: ScenarioClassicProgramState
var native_slot: int = 0
var return_value: int = 0
var clear_encounter: bool = false
var backout: ScenarioNativeCompletion.Backout = ScenarioNativeCompletion.Backout.NONE
var admitted: bool = true


func _init(directive_kind: StringName) -> void:
	kind = directive_kind


static func native_return(value: int, reason: ScenarioNativeCompletion.Backout = ScenarioNativeCompletion.Backout.NONE) -> ScenarioVmDirective:
	var result := ScenarioVmDirective.new(NATIVE_RETURN)
	result.return_value = value
	result.backout = reason
	return result


static func end_record(clear_flag: bool = false) -> ScenarioVmDirective:
	var result := ScenarioVmDirective.new(END_RECORD)
	result.clear_encounter = clear_flag
	return result


static func blowout() -> ScenarioVmDirective:
	return ScenarioVmDirective.new(BLOWOUT)


static func keep_codes(clear_flag: bool = false) -> ScenarioVmDirective:
	var result := ScenarioVmDirective.new(KEEP_CODES)
	result.clear_encounter = clear_flag
	return result


static func copy_record(code: ScenarioClassicProgramState, slot: int = 0, use_gosub: bool = false) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(COPY_RECORD)
	directive.copied_code = code.copy()
	directive.native_slot = slot
	directive.gosub = use_gosub
	return directive


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


static func reset_code(program: String, cursor: int, source_context: ScenarioExecutionContext) -> ScenarioVmDirective:
	var result := ScenarioVmDirective.new(RESET_CODE)
	result.program_id = program
	result.entry_cursor = cursor
	result.context = source_context.copy()
	return result


static func recheck_program(program: String, accepted: bool, frame_context: ScenarioExecutionContext = null) -> ScenarioVmDirective:
	var directive := ScenarioVmDirective.new(RECHECK_PROGRAM)
	directive.program_id = program
	directive.admitted = accepted
	directive.context = ScenarioExecutionContext.empty() if frame_context == null else frame_context.copy()
	return directive


func copy() -> ScenarioVmDirective:
	return from_data(to_data())


func to_data() -> Dictionary:
	match kind:
		NATIVE_RETURN:
			return {"kind": String(kind), "returnValue": return_value,"backout":backout}
		END_RECORD, KEEP_CODES:
			return {"kind": String(kind), "clearEncounter": clear_encounter}
		COPY_RECORD:
			return {"kind": String(kind), "code": copied_code.to_data(), "nativeSlot": native_slot, "gosub": gosub}
		FINISH, FINISH_TIMELINE, BLOWOUT, RESUME_AFTER_ENCOUNTER, RESTART_CURRENT_PROGRAM, DROPOUT, PUSH_CLASSIC_RETURN:
			return {"kind": String(kind)}
		BRANCH_XAP:
			return {"kind": String(kind), "targetId": target_id, "gosub": gosub}
		CLOCK_TIMER_RETURN, RESET_CODE:
			return {"kind": String(kind), "programId": program_id, "entryCursor": entry_cursor, "context": ScenarioExecutionContextCodec.encode(context)}
		RECHECK_PROGRAM:
			return {"kind":String(kind),"programId":program_id,"admitted":admitted,"context":ScenarioExecutionContextCodec.encode(context)}
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
	if StringName(kind_text) in [FINISH, FINISH_TIMELINE, BLOWOUT, RESUME_AFTER_ENCOUNTER, RESTART_CURRENT_PROGRAM, DROPOUT, PUSH_CLASSIC_RETURN]:
		return _empty_directive(StringName(kind_text)) if data.size() == 1 else null
	match StringName(kind_text):
		END_RECORD, KEEP_CODES, NATIVE_RETURN:
			return _exit_directive(data, StringName(kind_text))
		COPY_RECORD:
			return _copied_record(data)
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
		CLOCK_TIMER_RETURN, RESET_CODE, RECHECK_PROGRAM:
			return _record_transfer(data,StringName(kind_text))
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


static func _exit_directive(data: Dictionary, kind_value: StringName) -> ScenarioVmDirective:
	if kind_value == NATIVE_RETURN:
		if not ScenarioExecutionWire.fields(data, ["kind", "returnValue","backout"]): return null
		var value := ScenarioExecutionWire.integer(data["returnValue"], -1, 1)
		var reason := ScenarioExecutionWire.integer(data["backout"],ScenarioNativeCompletion.Backout.NONE,ScenarioNativeCompletion.Backout.BACKED_UP)
		return null if value < -1 or reason < 0 or reason != ScenarioNativeCompletion.Backout.NONE and value != 1 else native_return(value,reason as ScenarioNativeCompletion.Backout)
	if not ScenarioExecutionWire.fields(data, ["kind", "clearEncounter"]) or not data["clearEncounter"] is bool: return null
	var clear_flag: bool = data["clearEncounter"]
	return end_record(clear_flag) if kind_value == END_RECORD else keep_codes(clear_flag)


static func _record_transfer(data: Dictionary, kind_value: StringName) -> ScenarioVmDirective:
	var context_value := ScenarioExecutionContextCodec.decode(data.get("context"))
	if context_value == null or _nonempty_string(data.get("programId")).is_empty(): return null
	var program: String = data["programId"]
	if kind_value == RECHECK_PROGRAM:
		if not ScenarioExecutionWire.fields(data,["kind","programId","admitted","context"]) or not data["admitted"] is bool: return null
		var accepted: bool = data["admitted"]
		return recheck_program(program,accepted,context_value)
	if not ScenarioExecutionWire.fields(data,["kind","programId","entryCursor","context"]): return null
	var cursor := ScenarioExecutionWire.integer(data["entryCursor"],0,4096)
	if cursor < 0: return null
	if kind_value == RESET_CODE: return reset_code(program, cursor, context_value)
	var legacy := ScenarioVmDirective.new(CLOCK_TIMER_RETURN)
	legacy.program_id = program
	legacy.entry_cursor = cursor
	legacy.context = context_value
	return legacy


static func _copied_record(data: Dictionary) -> ScenarioVmDirective:
	if not ScenarioExecutionWire.fields(data, ["kind", "code", "nativeSlot", "gosub"]) or not data["gosub"] is bool: return null
	var code := ScenarioClassicProgramState.from_data(data["code"])
	var slot := ScenarioExecutionWire.integer(data["nativeSlot"], 0, 8)
	var use_gosub: bool = data["gosub"]
	return copy_record(code, slot, use_gosub) if code != null and code.kind != ScenarioClassicProgramState.Kind.UNAVAILABLE and slot >= 0 else null


static func _empty_directive(kind_value: StringName) -> ScenarioVmDirective:
	match kind_value:
		FINISH, FINISH_TIMELINE: return ScenarioVmDirective.new(kind_value)
		BLOWOUT: return blowout()
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
