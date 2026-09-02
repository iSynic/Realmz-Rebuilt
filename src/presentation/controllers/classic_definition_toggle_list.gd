class_name ClassicDefinitionToggleList
extends ScrollContainer

signal option_selected(option_id: String)

const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")

var _buttons: Dictionary = {}
var _order: Array[String] = []
var _button_group := ButtonGroup.new()
var _content := VBoxContainer.new()

var item_count: int:
	get: return _order.size()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 3)
	add_child(_content)


func add_option(option_id: String, display_name: String, tooltip: String, enabled: bool, selected: bool) -> void:
	var button := SpellSelectionChrome.definition_button(
		"Definition_%s" % option_id,
		display_name,
		selected,
		enabled,
		tooltip,
		_option_pressed.bind(option_id)
	)
	button.button_group = _button_group
	button.set_meta(&"definition_id", option_id)
	_buttons[option_id] = button
	_order.append(option_id)
	_content.add_child(button)


func clear_options() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.free()
	_buttons.clear()
	_order.clear()
	_button_group = ButtonGroup.new()


func select_id(option_id: String) -> void:
	for candidate_id: String in _order:
		var button := _buttons.get(candidate_id) as Button
		if button != null:
			button.button_pressed = candidate_id == option_id


func is_enabled(option_id: String) -> bool:
	var button := _buttons.get(option_id) as Button
	return button != null and not button.disabled


func first_enabled_id() -> String:
	for option_id: String in _order:
		if is_enabled(option_id):
			return option_id
	return ""


func option_button(option_id: String) -> Button:
	return _buttons.get(option_id) as Button


func _option_pressed(option_id: String) -> void:
	if is_enabled(option_id):
		option_selected.emit(option_id)
