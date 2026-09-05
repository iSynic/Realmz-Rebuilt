## Binds one authored six-choice row in the character appearance catalog.

class_name AppearanceThumbnailRow
extends VBoxContainer

signal option_selected(option_id: String)

func bind(kind_prefix: String, label_text: String, row_index: int, options: Array, textures: Dictionary, selected_id: String, group: ButtonGroup) -> void:
	name = "%sRaceRow%d" % [kind_prefix, row_index]
	var race_label := get_node("%RaceLabel") as Label
	var choices: Array[Button] = [
		get_node("%Choice1") as Button,
		get_node("%Choice2") as Button,
		get_node("%Choice3") as Button,
		get_node("%Choice4") as Button,
		get_node("%Choice5") as Button,
		get_node("%Choice6") as Button,
	]
	race_label.name = "%sRaceLabel%d" % [kind_prefix, row_index]
	race_label.text = label_text
	for index: int in choices.size():
		var choice := choices[index]
		choice.button_group = group
		choice.icon = null
		choice.text = ""
		choice.tooltip_text = ""
		choice.button_pressed = false
		if index >= options.size():
			choice.disabled = true
			choice.mouse_filter = Control.MOUSE_FILTER_IGNORE
			choice.modulate = Color(1.0, 1.0, 1.0, 0.0)
			continue
		var option: CharacterAppearanceOptionView = options[index] as CharacterAppearanceOptionView
		choice.name = "%sChoice_%d" % [kind_prefix, option.classic_resource_id]
		choice.disabled = false
		choice.mouse_filter = Control.MOUSE_FILTER_STOP
		choice.modulate = Color.WHITE
		choice.button_pressed = option.id == selected_id
		choice.tooltip_text = option.label
		var texture := textures.get(option.id) as Texture2D
		if texture != null:
			choice.icon = texture
		else:
			choice.text = "Unavailable"
		var option_id := option.id
		choice.pressed.connect(func() -> void: option_selected.emit(option_id))
