## Binds one authored pause action and its complete availability explanation.
class_name PauseMenuAction
extends VBoxContainer

signal activated(action_id: StringName)
signal selected(action_id: StringName)
@export var action_id: StringName
@export var caption: String
@onready var button: Button = %ActionButton
@onready var reason_label: Label = %Reason


func _ready() -> void:
	button.text = caption
	button.set_meta("focus_key", "pause:%s" % action_id)
	button.pressed.connect(func() -> void: activated.emit(action_id))
	button.focus_entered.connect(func() -> void: selected.emit(action_id))
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and not event.relative.is_zero_approx(): selected.emit(action_id))


func set_availability(reason: String) -> void:
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	reason_label.text = reason
	reason_label.visible = not reason.is_empty()


func set_selected(value: bool) -> void:
	%FocusOutline.visible = value
	%FocusMarker.color = Color("101a24") if value else Color("7c969e")
	button.add_theme_color_override("font_color", Color("101a24") if value else Color("ecebe3"))
	button.add_theme_color_override("font_focus_color", Color("101a24") if value else Color("ecebe3"))
	button.add_theme_color_override("font_hover_color", Color("101a24") if value else Color("ecebe3"))
	button.add_theme_color_override("font_disabled_color", Color("33434c") if value else Color("879ba6"))
	if not value and button.has_focus(): button.release_focus()
	if value and not button.disabled:
		button.grab_focus()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	$ActionRow.custom_minimum_size.y = maxf(50.0 * profile.ui_scale, button.get_combined_minimum_size().y)
