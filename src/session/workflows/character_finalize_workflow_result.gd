class_name CharacterFinalizeWorkflowResult
extends RefCounted

var ok: bool
var events: Array[DomainEvent]
var error_code: StringName
var error_message: String
var character_id: String
var character_name: String
var remaining_spell_points: int


func _init(
	succeeded: bool,
	committed_events: Array[DomainEvent] = [],
	code: StringName = &"",
	message: String = "",
	subject_id: String = "",
	subject_name: String = "",
	remaining: int = 0,
) -> void:
	ok = succeeded
	events = committed_events
	error_code = code
	error_message = message
	character_id = subject_id
	character_name = subject_name
	remaining_spell_points = remaining


static func ready(subject_id: String, subject_name: String, remaining: int) -> CharacterFinalizeWorkflowResult:
	return CharacterFinalizeWorkflowResult.new(true, [], &"", "", subject_id, subject_name, remaining)


static func committed(subject_id: String, subject_name: String, committed_events: Array[DomainEvent]) -> CharacterFinalizeWorkflowResult:
	return CharacterFinalizeWorkflowResult.new(true, committed_events, &"", "", subject_id, subject_name)


static func failed(code: StringName, message: String) -> CharacterFinalizeWorkflowResult:
	return CharacterFinalizeWorkflowResult.new(false, [], code, message)
