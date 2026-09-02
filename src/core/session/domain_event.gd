class_name DomainEvent
extends RefCounted

var kind: StringName
var payload: Dictionary


func _init(event_kind: StringName, event_payload: Dictionary = {}) -> void:
	kind = event_kind
	payload = event_payload.duplicate(true)


func to_data() -> Dictionary:
	return {"kind": String(kind), "payload": payload.duplicate(true)}
