## Exposes the authored starting-spell workspace and its variable record scenes.

class_name CharacterCreationSpellsStep
extends VBoxContainer

@export var spell_button_scene: PackedScene
@export var effect_preview_scene: PackedScene


func _ready() -> void:
	(%StartingSpellLevelHeading as TextureRect).texture = ClassicUiAssetCatalog.texture(&"spells.label.level")


func show_unavailable(message: String) -> Label:
	return _show_alternate(%StartingSpellUnavailable as Control, %StartingSpellUnavailableText as Label, message)


func show_not_applicable(message: String) -> Label:
	return _show_alternate(%StartingSpellNotApplicable as Control, %StartingSpellNotApplicableText as Label, message)


func show_missing(message: String) -> Label:
	return _show_alternate(%StartingSpellMissing as Control, %StartingSpellMissingText as Label, message)


func show_workspace() -> void:
	_set_alternate_visibility(null)
	(%StartingSpellWorkspace as Control).visible = true
	(%StartingSpellAllowance as Control).visible = true


func level_button(level: int) -> Button:
	return get_node("%%StartingSpellLevel%d" % level) as Button


func spell_rows() -> VBoxContainer:
	return %StartingSpellList as VBoxContainer


func effect_host() -> VBoxContainer:
	return %StartingSpellEffectHost as VBoxContainer


func _show_alternate(panel: Control, label: Label, message: String) -> Label:
	_set_alternate_visibility(panel)
	label.text = message
	return label


func _set_alternate_visibility(visible_panel: Control) -> void:
	for panel: Control in [%StartingSpellUnavailable, %StartingSpellNotApplicable, %StartingSpellMissing]:
		panel.visible = panel == visible_panel
	(%StartingSpellWorkspace as Control).visible = false
	(%StartingSpellAllowance as Control).visible = false
