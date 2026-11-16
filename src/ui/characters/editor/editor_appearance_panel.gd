## Appearance tab: stock and imported portraits and combat icons at their native size.
## Textures load on demand when the tab is shown.

class_name EditorAppearancePanel
extends ScrollContainer

signal command(operation: Dictionary)

@export var choice_scene: PackedScene

var _portrait_group := ButtonGroup.new()
var _icon_group := ButtonGroup.new()

@onready var _portraits: HFlowContainer = %PortraitGrid
@onready var _icons: HFlowContainer = %IconGrid


func bind(session: CharacterEditorSession, texture_for: Callable, imported_art: Array[CharacterAppearanceOptionView]) -> void:
	var identity := session.queries.identity()
	for portrait: bool in [true, false]:
		var options := session.queries.appearance_options(portrait)
		var kind := CharacterAppearanceDefinition.PORTRAIT if portrait else CharacterAppearanceDefinition.COMBAT_ICON
		for option: CharacterAppearanceOptionView in imported_art:
			if option.kind == kind:
				options.append(option)
		if portrait:
			_bind_grid(_portraits, options, texture_for, String(identity.portraitId), &"portrait", _portrait_group)
		else:
			_bind_grid(_icons, options, texture_for, String(identity.iconId), &"icon", _icon_group)


func _bind_grid(grid: HFlowContainer, options: Array[CharacterAppearanceOptionView], texture_for: Callable, selected_id: String, kind: StringName, group: ButtonGroup) -> void:
	while grid.get_child_count() < options.size():
		var choice := choice_scene.instantiate() as Button
		choice.button_group = group
		choice.pressed.connect(_choose.bind(choice, kind))
		grid.add_child(choice)
	for index: int in grid.get_child_count():
		var choice := grid.get_child(index) as Button
		choice.visible = index < options.size()
		if not choice.visible:
			continue
		var option := options[index]
		choice.set_meta(&"option_id", option.id)
		choice.icon = texture_for.call(option.id) as Texture2D
		choice.text = "" if choice.icon != null else option.label
		choice.tooltip_text = option.label
		choice.set_pressed_no_signal(option.id == selected_id)


func _choose(choice: Button, kind: StringName) -> void:
	command.emit({"kind": kind, "value": String(choice.get_meta(&"option_id"))})
