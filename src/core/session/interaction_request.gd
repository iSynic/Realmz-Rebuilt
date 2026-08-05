class_name InteractionRequest
extends RefCounted

var request_id: String
var kind: StringName
var payload: Dictionary


func _init(id: String, request_kind: StringName, request_payload: Dictionary = {}) -> void:
	request_id = id
	kind = request_kind
	payload = request_payload.duplicate(true)


func to_data() -> Dictionary:
	return {"request_id": request_id, "kind": String(kind), "payload": payload.duplicate(true)}
