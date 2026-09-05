## Binds detached party setup inspection data to scene-owned controls.

class_name PartySetupInspectionController
extends RefCounted

const INSPECTION_OVERLAY_SCENE_PATH := "res://src/ui/setup/party_setup_inspection_overlay.tscn"

var _state: RefCounted


func _init(state: RefCounted) -> void:
	_state = state

func build_setup_character_inspection() -> void:
	var overlay_scene := load(INSPECTION_OVERLAY_SCENE_PATH) as PackedScene
	_state.setup_inspection_overlay = overlay_scene.instantiate() as PanelContainer
	_state.setup_inspection_overlay.visible = false
	_state.setup_overlay.add_child(_state.setup_inspection_overlay)
	_state.setup_inspection_body = _state.setup_inspection_overlay.get_node("%CharacterInspectionSheetHost") as VBoxContainer
	(_state.setup_inspection_overlay.get_node("%BackToPartySetup") as Button).pressed.connect(close_setup_character_inspection)

func inspect_setup_character(character_id: String) -> void:
	_state.setup_inspection_character_id = character_id
	render_setup_character_inspection()

func render_setup_character_inspection() -> void:
	if _state.setup_inspection_overlay == null or _state.setup_inspection_body == null or _state.view == null:
		return
	var inspected: CharacterView = null
	for character: CharacterView in _state.view.party_members:
		if character.id == _state.setup_inspection_character_id:
			inspected = character
			break
	if inspected == null:
		close_setup_character_inspection()
		return
	_state.clear_children(_state.setup_inspection_body)
	(_state.setup_inspection_overlay.get_node("%InspectionHeading") as Label).text = "Inspect %s" % inspected.name
	_state.ensure_appearance_textures()
	var sheet := _state.character_sheet_scene.instantiate() as ClassicCharacterSheet
	sheet.name = "PartySetupCharacterSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.present(_state.view.party_members, _state.setup_inspection_character_id, _state.appearance_textures, _state.settings.text_scale, &"overview", _state.view.portrait_options, _state.view.combat_icon_options, ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are available after beginning the adventure."), _state.media, _state.layout_profile)
	sheet.character_selected.connect(func(character_id: String) -> void: _state.setup_inspection_character_id = character_id)
	_state.setup_inspection_body.add_child(sheet)
	_state.setup_inspection_overlay.visible = true
	_state.focus_first(_state.setup_inspection_overlay)

func close_setup_character_inspection() -> void:
	_state.setup_inspection_character_id = ""
	if _state.setup_inspection_overlay != null:
		_state.setup_inspection_overlay.visible = false
	_state.focus_first(_state.setup_overlay)
