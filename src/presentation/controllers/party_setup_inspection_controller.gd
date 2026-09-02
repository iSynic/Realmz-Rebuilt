class_name PartySetupInspectionController
extends RefCounted

const CLASSIC_UI_THEME_PATH := "res://src/presentation/classic_ui_theme.tres"

var _state: RefCounted


func _init(state: RefCounted) -> void:
	_state = state

func _build_setup_character_inspection() -> void:
	_state.setup_inspection_overlay = PanelContainer.new()
	_state.setup_inspection_overlay.name = "PartySetupCharacterInspection"
	var classic_ui_theme := load(CLASSIC_UI_THEME_PATH) as Theme
	var inspection_surface := classic_ui_theme.get_stylebox("panel", "ClassicInset").duplicate() as StyleBoxTexture
	_state.setup_inspection_overlay.add_theme_stylebox_override("panel", inspection_surface)
	_state.setup_inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_state.setup_inspection_overlay.clip_contents = true
	_state.setup_inspection_overlay.z_index = 1
	_state.setup_inspection_overlay.visible = false
	_state.setup_overlay.add_child(_state.setup_inspection_overlay)
	_state.setup_inspection_overlay.position = Vector2.ZERO
	_state.setup_inspection_overlay.size = _state.setup_overlay.size
	_state.setup_inspection_body = VBoxContainer.new()
	_state.setup_inspection_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state.setup_inspection_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_state.setup_inspection_body.add_theme_constant_override("separation", 8)
	_state.setup_inspection_overlay.add_child(_state.setup_inspection_body)

func _inspect_setup_character(character_id: String) -> void:
	_state.setup_inspection_character_id = character_id
	_render_setup_character_inspection()

func _render_setup_character_inspection() -> void:
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
	_state._clear(_state.setup_inspection_body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.name = "BackToPartySetup"
	back.text = "Back to party setup"
	back.pressed.connect(close_setup_character_inspection)
	header.add_child(back)
	var heading: Label = _state._label("Inspect %s" % inspected.name, _state.GOLD, 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_state.setup_inspection_body.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.name = "CharacterInspectionScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_state.setup_inspection_body.add_child(scroll)
	_state._ensure_appearance_textures()
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "PartySetupCharacterSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.present(_state.view.party_members, _state.setup_inspection_character_id, _state._appearance_textures, _state.settings.text_scale, &"overview", _state.view.portrait_options, _state.view.combat_icon_options, ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are available after beginning the adventure."), _state.media, _state.layout_profile)
	sheet.character_selected.connect(func(character_id: String) -> void: _state.setup_inspection_character_id = character_id)
	scroll.add_child(sheet)
	_state.setup_inspection_overlay.visible = true
	_state._focus_first(_state.setup_inspection_overlay)

func close_setup_character_inspection() -> void:
	_state.setup_inspection_character_id = ""
	if _state.setup_inspection_overlay != null:
		_state.setup_inspection_overlay.visible = false
	_state._focus_first(_state.setup_overlay)
