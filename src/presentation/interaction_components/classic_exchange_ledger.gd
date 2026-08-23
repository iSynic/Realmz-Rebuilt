class_name ClassicExchangeLedger
extends PanelContainer

signal item_dropped(payload: Dictionary, target_id: String)

var target_id: String = ""
var accepted_kind: StringName = &""


func configure_drop(kind: StringName, destination_id: String) -> void:
	accepted_kind = kind
	target_id = destination_id


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and StringName(data.get("kind", &"")) == accepted_kind and not target_id.is_empty() and String(data.get("sourceId", "")) != target_id


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		item_dropped.emit((data as Dictionary).duplicate(true), target_id)
