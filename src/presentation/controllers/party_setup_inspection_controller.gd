extends "res://src/presentation/controllers/campaign_party_setup_state.gd"

func _build_setup_character_inspection() -> void:
	setup_inspection_overlay = PanelContainer.new()
	setup_inspection_overlay.name = "PartySetupCharacterInspection"
	var inspection_surface := ClassicUiTheme.get_stylebox("panel", "ClassicInset").duplicate() as StyleBoxTexture
	setup_inspection_overlay.add_theme_stylebox_override("panel", inspection_surface)
	setup_inspection_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	setup_inspection_overlay.clip_contents = true
	setup_inspection_overlay.z_index = 1
	setup_inspection_overlay.visible = false
	setup_overlay.add_child(setup_inspection_overlay)
	setup_inspection_overlay.position = Vector2.ZERO
	setup_inspection_overlay.size = setup_overlay.size
	setup_inspection_body = VBoxContainer.new()
	setup_inspection_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_inspection_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_inspection_body.add_theme_constant_override("separation", 8)
	setup_inspection_overlay.add_child(setup_inspection_body)

func _inspect_setup_character(character_id: String) -> void:
	setup_inspection_character_id = character_id
	_render_setup_character_inspection()

func _render_setup_character_inspection() -> void:
	if setup_inspection_overlay == null or setup_inspection_body == null or view == null:
		return
	var inspected: CharacterView = null
	for character: CharacterView in view.party_members:
		if character.id == setup_inspection_character_id:
			inspected = character
			break
	if inspected == null:
		close_setup_character_inspection()
		return
	_clear(setup_inspection_body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var back := Button.new()
	back.name = "BackToPartySetup"
	back.text = "Back to party setup"
	back.pressed.connect(close_setup_character_inspection)
	header.add_child(back)
	var heading := _label("Inspect %s" % inspected.name, GOLD, 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	setup_inspection_body.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.name = "CharacterInspectionScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	setup_inspection_body.add_child(scroll)
	_ensure_appearance_textures()
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "PartySetupCharacterSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.present(view.party_members, setup_inspection_character_id, _appearance_textures, settings.text_scale, &"overview", view.portrait_options, view.combat_icon_options, ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance changes are available after beginning the adventure."))
	sheet.character_selected.connect(func(character_id: String) -> void: setup_inspection_character_id = character_id)
	scroll.add_child(sheet)
	setup_inspection_overlay.visible = true
	_focus_first(setup_inspection_overlay)

func close_setup_character_inspection() -> void:
	setup_inspection_character_id = ""
	if setup_inspection_overlay != null:
		setup_inspection_overlay.visible = false
	_focus_first(setup_overlay)
