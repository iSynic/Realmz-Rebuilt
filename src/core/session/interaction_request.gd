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


static func from_data(data: Variant) -> InteractionRequest:
	if not data is Dictionary:
		return null
	for field: String in ["request_id", "kind", "payload"]:
		if not data.has(field):
			return null
	if not data["request_id"] is String or data["request_id"].is_empty() or not data["kind"] is String or data["kind"].is_empty() or not data["payload"] is Dictionary:
		return null
	return InteractionRequest.new(data["request_id"], StringName(data["kind"]), data["payload"])
