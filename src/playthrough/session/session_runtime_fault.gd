## Carries one nonserialized terminal legacy-content fault for the active session.

class_name SessionRuntimeFault
extends RefCounted

var campaign_id: String
var program_id: String
var slot: int
var opcode: int
var operands: Array[int] = []
var target_kind: StringName
var target_id: String
var error_code: StringName
var error_message: String


func _init(
		fault_campaign_id: String,
		fault_program_id: String,
		fault_slot: int,
		fault_opcode: int,
		fault_operands: Array[int],
		fault_target_kind: StringName,
		fault_target_id: String,
		fault_error_code: StringName,
		fault_error_message: String
) -> void:
	campaign_id = fault_campaign_id
	program_id = fault_program_id
	slot = fault_slot
	opcode = fault_opcode
	operands.assign(fault_operands)
	target_kind = fault_target_kind
	target_id = fault_target_id
	error_code = fault_error_code
	error_message = fault_error_message


func copy() -> SessionRuntimeFault:
	return SessionRuntimeFault.new(campaign_id, program_id, slot, opcode, operands, target_kind, target_id, error_code, error_message)


func to_data() -> Dictionary:
	return {
		"campaignId": campaign_id,
		"programId": program_id,
		"slot": slot,
		"opcode": opcode,
		"operands": operands.duplicate(),
		"targetKind": String(target_kind),
		"targetId": target_id,
		"errorCode": String(error_code),
		"errorMessage": error_message,
	}


func display_message() -> String:
	return "Scenario content fault in %s slot %d (opcode %d): unavailable %s '%s'. Load a saved adventure or return to the main menu." % [program_id, slot, opcode, String(target_kind).replace("-", " "), target_id]
