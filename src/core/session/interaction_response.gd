class_name InteractionResponse
extends RefCounted

var request_id: String
var kind: StringName
var payload: Dictionary


func _init(id: String, response_kind: StringName, response_payload: Dictionary = {}) -> void:
	request_id = id
	kind = response_kind
	payload = response_payload.duplicate(true)
