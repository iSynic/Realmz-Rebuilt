## Presents the dynamic Classic exchange ledger interaction without owning gameplay state.

class_name ClassicExchangeLedger
extends PanelContainer

signal item_dropped(payload: Dictionary, target_id: String)

var target_id: String = ""
var accepted_kind: StringName = &""


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_forward_drop_surface(self)


func _forward_drop_surface(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			var drag := (control as ClassicExchangeItemButton).create_drag_data if control is ClassicExchangeItemButton else Callable()
			control.set_drag_forwarding(drag, _can_drop_data, _drop_data)
		_forward_drop_surface(child)


func configure_drop(kind: StringName, destination_id: String) -> void:
	accepted_kind = kind
	target_id = destination_id


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and StringName(data.get("kind", &"")) == accepted_kind and not target_id.is_empty() and String(data.get("sourceId", "")) != target_id


func _drop_data(_position: Vector2, data: Variant) -> void:
	if _can_drop_data(_position, data):
		item_dropped.emit((data as Dictionary).duplicate(true), target_id)
