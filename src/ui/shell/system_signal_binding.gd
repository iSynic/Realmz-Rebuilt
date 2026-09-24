## Disconnects prior System workspace bindings before a retained control is rebound.
class_name SystemSignalBinding
extends RefCounted


static func clear_pressed(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


static func clear_toggled(button: BaseButton) -> void:
	for connection: Dictionary in button.toggled.get_connections():
		button.toggled.disconnect(connection["callable"] as Callable)


static func clear_item_selected(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection["callable"] as Callable)


static func clear_value_changed(control: Range) -> void:
	for connection: Dictionary in control.value_changed.get_connections():
		control.value_changed.disconnect(connection["callable"] as Callable)


static func clear_text_changed(control: LineEdit) -> void:
	for connection: Dictionary in control.text_changed.get_connections():
		control.text_changed.disconnect(connection["callable"] as Callable)
