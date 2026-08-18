class_name PartySetupCharacterCreationController
extends "res://src/presentation/controllers/party_setup_controller_component.gd"

var _assembly: RefCounted
var _starting_spell_level: int = 0
var _starting_spell_id: String = ""


func _init(state: RefCounted, assembly: RefCounted) -> void:
	super(state)
	_assembly = assembly

func ensure_appearance_textures() -> void:
	_ensure_appearance_textures()

func appearance_textures() -> Dictionary:
	_ensure_appearance_textures()
	return _appearance_textures

func set_appearance_texture(asset_id: String, texture: Texture2D) -> void:
	_appearance_textures[asset_id] = texture

func set_presentation_settings(next_settings: PresentationSettings) -> void:
	if next_settings != null:
		settings = next_settings
	_campaign_library.set_presentation_settings(next_settings)

func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	standalone_character_creation_available = enabled
	standalone_character_creation_reason = reason if not reason.is_empty() else "The Classic character library is unavailable."
	if setup_overlay != null and setup_overlay.visible and setup_mode == &"assembly":
		refresh_setup_options()

func begin_standalone_character_creation() -> void:
	standalone_character_creation_active = true
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()

func finish_standalone_character_creation() -> void:
	standalone_character_creation_active = false
	reset_creator(true)

func refresh_setup_options() -> void:
	if view == null or not view.party_setup_available:
		_campaign_library.set_selected_campaign_summary(null)
		campaign_overlay.tooltip_text = "Select an installed scenario to assemble a party."
		_assembly._refresh_party_list()
		_assembly._refresh_party_setup_options()
		render_creator_step()
		return
	var summary := view.campaign_summary
	_campaign_library.set_selected_campaign_summary(summary)
	if summary != null:
		var title_parts: Array[String] = [summary.title]
		if not summary.version.is_empty():
			title_parts.append("v%s" % summary.version)
		if not summary.author.is_empty():
			title_parts.append("by %s" % summary.author)
		var restriction_text := summary.restriction_description.strip_edges()
		if restriction_text.is_empty():
			restriction_text = "No authored party restrictions."
		var limits := "Up to %d characters" % summary.maximum_party_size
		if summary.maximum_level > 0:
			limits += " • Maximum level %d" % summary.maximum_level
		campaign_overlay.tooltip_text = "%s\n%s\n%s" % [" • ".join(title_parts), restriction_text, limits]
	else:
		campaign_overlay.tooltip_text = "The selected scenario has no campaign summary metadata."
	_assembly._refresh_party_list()
	_assembly._refresh_party_setup_options()
	var setup_count := view.party_members.size()
	_apply_availability(begin_button, &"begin_adventure")
	begin_button.text = "Begin adventure (%d/%d)" % [setup_count, _assembly._maximum_party_size()]
	render_creator_step()

func render_creator_step() -> void:
	if creator_page == null:
		return
	_state.apply_setup_mode_layout()
	if setup_mode == &"assembly":
		_assembly._render_party_assembly()
		return
	create_character_button.visible = false
	begin_button.visible = false
	party_setup_options.visible = false
	creator_steps.visible = true
	creator_action_bar.visible = true
	setup_message.visible = true
	setup_message.tooltip_text = ""
	setup_message.modulate = MUTED
	setup_message.custom_minimum_size.y = 32.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	setup_message.text = _creator_step_message()
	_clear_creator_page()
	for index: int in creator_step_labels.size():
		creator_step_labels[index].modulate = GOLD if index == creator_step else Color("e0e2e5") if index < creator_step else MUTED
	match creator_step:
		0:
			_build_creator_identity()
		1:
			_build_creator_race_class()
		2:
			_build_creator_appearance()
		3:
			_build_creator_review()
		4:
			_build_creator_spells()
	_update_creator_actions()

func _build_creator_identity() -> void:
	creator_page.add_child(_label("Identity", GOLD, 20))
	var stage := HBoxContainer.new()
	stage.name = "CreatorIdentityStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 12)
	creator_page.add_child(stage)
	var preview := _add_creator_panel(stage, "IdentityPreview", "Character File", 0.65)
	var preview_name := _add_label(preview, draft_name if not draft_name.is_empty() else "Unnamed adventurer", GOLD, 18)
	preview_name.name = "IdentityPreviewName"
	var preview_gender := _add_label(preview, "Male" if draft_gender == 1 else "Female", Color("e0e2e5"), 14)
	preview_gender.name = "IdentityPreviewGender"
	var preview_level := _add_label(preview, "Starting level %d" % draft_starting_level, Color("e0e2e5"), 14)
	preview_level.name = "IdentityPreviewLevel"
	_add_label(preview, "Portrait and battle icon are chosen in Appearance.", MUTED, 12)
	var form := _add_creator_panel(stage, "IdentityFields", "Identity Record", 1.35)
	form.add_child(_label("Name", MUTED, 12))
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.placeholder_text = "Character name"
	name_edit.max_length = 24
	name_edit.text = draft_name
	name_edit.text_changed.connect(func(value: String) -> void:
		draft_name = value
		preview_name.text = value.strip_edges() if not value.strip_edges().is_empty() else "Unnamed adventurer"
	)
	form.add_child(name_edit)
	form.add_child(_label("Gender", MUTED, 12))
	gender_option = OptionButton.new()
	gender_option.name = "CharacterGender"
	gender_option.add_item("Male", 1)
	gender_option.add_item("Female", 2)
	gender_option.select(0 if draft_gender == 1 else 1)
	gender_option.item_selected.connect(func(_index: int) -> void:
		draft_gender = gender_option.get_selected_id()
		preview_gender.text = "Male" if draft_gender == 1 else "Female"
	)
	form.add_child(gender_option)
	form.add_child(_label("Starting Level", MUTED, 12))
	starting_level_option = OptionButton.new()
	starting_level_option.name = "StartingLevel"
	var maximum_level := view.campaign_summary.maximum_level if view != null and view.campaign_summary != null else 0
	for level: int in CharacterRules.STARTING_LEVELS:
		if maximum_level > 0 and level > maximum_level:
			continue
		starting_level_option.add_item("Starting level %d" % level, level)
	var selected_index := starting_level_option.get_item_index(draft_starting_level)
	if selected_index < 0:
		selected_index = 0
		draft_starting_level = starting_level_option.get_item_id(0)
	starting_level_option.select(selected_index)
	starting_level_option.item_selected.connect(func(_index: int) -> void:
		draft_starting_level = starting_level_option.get_selected_id()
		preview_level.text = "Starting level %d" % draft_starting_level
	)
	starting_level_option.tooltip_text = "Castle offers fixed starting levels and runs every intervening ordinary level-up roll. Campaign level restrictions remove unavailable choices."
	form.add_child(starting_level_option)
	var context := _add_label(form, _creation_context(), MUTED, 12)
	context.name = "IdentityCampaignContext"
	_focus_first(creator_page)

func _add_creator_panel(parent: Container, node_name: String, title: String, stretch: float = 1.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = stretch
	var body := VBoxContainer.new()
	body.name = "%sBody" % node_name
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	body.add_child(_label(title, GOLD, 15))
	parent.add_child(panel)
	return body

func _creation_context() -> String:
	if view == null or view.campaign_summary == null:
		return "Classic Character Files"
	var summary := view.campaign_summary
	var facts: Array[String] = [summary.title]
	if summary.maximum_level > 0:
		facts.append("Maximum level %d" % summary.maximum_level)
	if not summary.restriction_description.strip_edges().is_empty():
		facts.append(summary.restriction_description.strip_edges())
	return " • ".join(facts)

func _build_creator_race_class() -> void:
	creator_page.add_child(_label("Race & Class", GOLD, 20))
	var columns := HBoxContainer.new()
	race_class_columns = columns
	columns.name = "RaceClassSelectors"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	var race_column := _add_creator_panel(columns, "RaceSelectorPanel", "Race", 1.0)
	race_list = ItemList.new()
	race_list.name = "RaceList"
	race_list.custom_minimum_size.y = 170.0
	race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_list.item_selected.connect(_race_selected)
	race_column.add_child(race_list)
	var race_detail := _add_label(race_column, "", Color("e0e2e5"), 13)
	race_detail.name = "RaceDescription"
	race_detail.custom_minimum_size.y = 48.0
	var caste_column := _add_creator_panel(columns, "ClassSelectorPanel", "Class", 1.0)
	caste_list = ItemList.new()
	caste_list.name = "ClassList"
	caste_list.custom_minimum_size.y = 170.0
	caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caste_list.item_selected.connect(_caste_selected)
	caste_column.add_child(caste_list)
	var caste_detail := _add_label(caste_column, "", Color("e0e2e5"), 13)
	caste_detail.name = "ClassDescription"
	caste_detail.custom_minimum_size.y = 48.0
	creator_page.add_child(columns)
	_populate_race_class_options()

func _populate_race_class_options() -> void:
	if view == null or race_list == null or caste_list == null:
		return
	for option: DefinitionOptionView in view.race_options:
		race_list.add_item(option.name)
		var race_index := race_list.item_count - 1
		race_list.set_item_metadata(race_index, option.id)
		var race_restricted := view.campaign_summary != null and view.campaign_summary.banned_races.has(option.id)
		race_list.set_item_tooltip(race_index, "Unavailable in this scenario." if race_restricted else option.description)
		race_list.set_item_disabled(race_index, race_restricted)
	for option: DefinitionOptionView in view.caste_options:
		caste_list.add_item(option.name)
		caste_list.set_item_metadata(caste_list.item_count - 1, option.id)
		caste_list.set_item_tooltip(caste_list.item_count - 1, option.description)
		caste_list.set_item_disabled(caste_list.item_count - 1, view.campaign_summary != null and view.campaign_summary.banned_castes.has(option.id))
	if selected_race_id.is_empty() or not _option_is_enabled(race_list, selected_race_id):
		var first_race := _first_enabled_item(race_list)
		if first_race >= 0:
			selected_race_id = String(race_list.get_item_metadata(first_race))
	_select_item_by_id(race_list, selected_race_id)
	_apply_caste_filter()
	if selected_caste_id.is_empty() or not _option_is_enabled(caste_list, selected_caste_id):
		var first_caste := _first_enabled_item(caste_list)
		if first_caste >= 0:
			selected_caste_id = String(caste_list.get_item_metadata(first_caste))
	_select_item_by_id(caste_list, selected_caste_id)
	_refresh_race_class_details()

func _refresh_race_class_details() -> void:
	var race_detail := creator_page.find_child("RaceDescription", true, false) as Label
	var caste_detail := creator_page.find_child("ClassDescription", true, false) as Label
	var race_option := _definition_option(view.race_options if view != null else [], selected_race_id)
	var caste_option := _definition_option(view.caste_options if view != null else [], selected_caste_id)
	if race_detail != null:
		race_detail.text = race_option.description if race_option != null else ""
		race_detail.visible = not race_detail.text.is_empty()
	if caste_detail != null:
		caste_detail.text = caste_option.description if caste_option != null else ""
		caste_detail.visible = not caste_detail.text.is_empty()

func _definition_option(options: Array[DefinitionOptionView], option_id: String) -> DefinitionOptionView:
	for option: DefinitionOptionView in options:
		if option.id == option_id:
			return option
	return null

func _build_creator_appearance() -> void:
	creator_page.add_child(_label("Appearance", GOLD, 20))
	_add_label(creator_page, "Choose the portrait shown on character screens and the icon used in battle. Castle's six race recommendations appear first.", MUTED)
	_ensure_appearance_textures()
	var appearance_row := HBoxContainer.new()
	appearance_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	appearance_row.add_theme_constant_override("separation", 14)
	var preview_panel := PanelContainer.new()
	preview_panel.name = "AppearancePreview"
	preview_panel.theme_type_variation = &"ClassicInset"
	preview_panel.custom_minimum_size = Vector2(210.0, 250.0)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_column := VBoxContainer.new()
	preview_column.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_column.add_theme_constant_override("separation", 8)
	preview_panel.add_child(preview_column)
	var portrait_heading := _label("Character Portrait", GOLD, 14)
	portrait_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_column.add_child(portrait_heading)
	portrait_preview = TextureRect.new()
	portrait_preview.name = "PortraitPreview"
	portrait_preview.custom_minimum_size = Vector2(176.0, 176.0)
	portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_column.add_child(portrait_preview)
	var icon_row := HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 8)
	combat_icon_preview = TextureRect.new()
	combat_icon_preview.name = "CombatIconPreview"
	combat_icon_preview.custom_minimum_size = Vector2(96.0, 96.0)
	combat_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	combat_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	combat_icon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_row.add_child(combat_icon_preview)
	icon_row.add_child(_label("Battle icon", MUTED, 13))
	preview_column.add_child(icon_row)
	appearance_row.add_child(preview_panel)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	choices.add_child(_label("Portrait", GOLD, 14))
	portrait_option = OptionButton.new()
	portrait_option.name = "PortraitOption"
	portrait_option.fit_to_longest_item = false
	var portrait_options := _sorted_appearance_options(view.portrait_options if view != null else [])
	for option: CharacterAppearanceOptionView in portrait_options:
		_add_appearance_option(portrait_option, option)
	_select_appearance_default(portrait_option, draft_portrait_id, true)
	portrait_option.item_selected.connect(_portrait_selected)
	portrait_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_child(portrait_option)
	choices.add_child(_build_appearance_thumbnail_strip(portrait_option, portrait_options, "PortraitThumbnailStrip", true))
	choices.add_child(_label("Combat Icon", GOLD, 14))
	combat_icon_option = OptionButton.new()
	combat_icon_option.name = "CombatIconOption"
	combat_icon_option.fit_to_longest_item = false
	var combat_options := _sorted_appearance_options(view.combat_icon_options if view != null else [])
	for option: CharacterAppearanceOptionView in combat_options:
		_add_appearance_option(combat_icon_option, option)
	_select_appearance_default(combat_icon_option, draft_combat_icon_id, false)
	combat_icon_option.item_selected.connect(_combat_icon_selected)
	combat_icon_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_child(combat_icon_option)
	choices.add_child(_build_appearance_thumbnail_strip(combat_icon_option, combat_options, "CombatIconThumbnailStrip", false))
	var note := _label("Portraits identify the character in records and party panes. Combat icons are the tactical figures used on the battlefield.", MUTED, 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_child(note)
	appearance_row.add_child(choices)
	creator_page.add_child(appearance_row)
	_refresh_appearance_preview()
	if portrait_options.is_empty() or combat_options.is_empty():
		_add_label(creator_page, "This package does not expose the complete Classic appearance catalog. Character generation is unavailable until the package is re-exported.", ERROR)

func _build_appearance_thumbnail_strip(control: OptionButton, options: Array[CharacterAppearanceOptionView], strip_name: String, portrait: bool) -> Control:
	var panel := PanelContainer.new()
	panel.name = strip_name
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.y = 72.0
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	var selected_id := String(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""
	for option: CharacterAppearanceOptionView in options:
		var choice := Button.new()
		choice.name = "%s_%d" % ["PortraitChoice" if portrait else "CombatIconChoice", option.classic_resource_id]
		choice.custom_minimum_size = Vector2(64.0, 62.0)
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = option.id == selected_id
		var texture := _appearance_textures.get(option.id) as Texture2D
		if texture != null:
			choice.icon = texture
			choice.expand_icon = true
		else:
			choice.text = str(option.classic_resource_id)
		var role := "Portrait" if portrait else "Combat icon"
		var recommendation := " • recommended for this race" if option.is_recommended_for(selected_race_id) else ""
		choice.tooltip_text = "%s • %s %d%s" % [option.label, role, option.classic_resource_id, recommendation]
		choice.pressed.connect(_select_appearance_thumbnail.bind(control, option.id, portrait))
		row.add_child(choice)
	scroll.add_child(row)
	return panel

func _select_appearance_thumbnail(control: OptionButton, option_id: String, portrait: bool) -> void:
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) != option_id:
			continue
		control.select(index)
		if portrait:
			_portrait_selected(index)
		else:
			_combat_icon_selected(index)
		return

func _sorted_appearance_options(source: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result := source.duplicate()
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool:
		var left_recommended := left.is_recommended_for(selected_race_id)
		var right_recommended := right.is_recommended_for(selected_race_id)
		if left_recommended != right_recommended:
			return left_recommended
		return left.classic_resource_id < right.classic_resource_id
	)
	return result

func _add_appearance_option(control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var prefix := "Recommended • " if option.is_recommended_for(selected_race_id) else ""
	var label := "%s%s • CICN %d" % [prefix, option.label, option.classic_resource_id]
	var texture := _appearance_textures.get(option.id) as Texture2D
	if texture != null:
		control.add_icon_item(texture, label)
	else:
		control.add_item(label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, "%s character resource %d" % ["Portrait" if option.kind == CharacterAppearanceDefinition.PORTRAIT else "Combat icon", option.classic_resource_id])

func _select_appearance_default(control: OptionButton, selected_id: String, portrait: bool) -> void:
	if control.item_count == 0:
		return
	var target_id := selected_id
	if target_id.is_empty() and portrait:
		for index: int in control.item_count:
			var option := _appearance_option_by_id(String(control.get_item_metadata(index)), true)
			if option != null and option.is_recommended_for(selected_race_id):
				target_id = option.id
				break
	if target_id.is_empty() and not portrait:
		var portrait_value := _selected_appearance(portrait_option, true)
		if portrait_value != null:
			var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
			for option: CharacterAppearanceOptionView in view.combat_icon_options:
				if option.classic_resource_id == wanted_resource_id:
					target_id = option.id
					break
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) == target_id:
			control.select(index)
			return
	control.select(0)

func _portrait_selected(_index: int) -> void:
	if not combat_icon_touched and combat_icon_option != null:
		var portrait_value := _selected_appearance(portrait_option, true)
		if portrait_value != null:
			var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
			for index: int in combat_icon_option.item_count:
				var icon := _appearance_option_by_id(String(combat_icon_option.get_item_metadata(index)), false)
				if icon != null and icon.classic_resource_id == wanted_resource_id:
					combat_icon_option.select(index)
					break
	_refresh_appearance_preview()

func _combat_icon_selected(_index: int) -> void:
	combat_icon_touched = true
	_refresh_appearance_preview()

func _refresh_appearance_preview() -> void:
	if portrait_preview != null:
		var portrait_id := String(portrait_option.get_item_metadata(portrait_option.selected)) if portrait_option != null and portrait_option.selected >= 0 else ""
		portrait_preview.texture = _appearance_textures.get(portrait_id) as Texture2D
	if combat_icon_preview != null:
		var icon_id := String(combat_icon_option.get_item_metadata(combat_icon_option.selected)) if combat_icon_option != null and combat_icon_option.selected >= 0 else ""
		combat_icon_preview.texture = _appearance_textures.get(icon_id) as Texture2D

func _selected_appearance(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	if control == null or control.selected < 0:
		return null
	return _appearance_option_by_id(String(control.get_item_metadata(control.selected)), portrait)

func _appearance_option_by_id(option_id: String, portrait: bool) -> CharacterAppearanceOptionView:
	var options := view.portrait_options if portrait else view.combat_icon_options
	for option: CharacterAppearanceOptionView in options:
		if option.id == option_id:
			return option
	return null

func _build_creator_review() -> void:
	creator_page.add_child(_label("Review Classic Roll", GOLD, 20))
	review_label = _add_label(creator_page, "Generating the character through Classic rules…", MUTED, 13)
	review_label.name = "ReviewStatus"
	review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_creator_review()
	if view == null or view.character_draft == null:
		return
	var character := view.character_draft
	creator_page.add_child(_build_review_identity(character))
	var records := BoxContainer.new()
	records.name = "ReviewRecordPanels"
	records.vertical = layout_profile == UiLayoutProfile.COMPACT
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 8)
	creator_page.add_child(records)
	_add_review_record(records, "ReviewAttributes", "Attributes", _review_attribute_lines(character))
	_add_review_record(records, "ReviewCombat", "Combat", _review_combat_lines(character))
	_build_review_saves_equipment(records, character)
	var restriction := _add_label(creator_page, _creation_context(), MUTED, 12)
	restriction.name = "ReviewCampaignContext"

func _build_review_identity(character: CharacterView) -> Control:
	_ensure_appearance_textures()
	var panel := PanelContainer.new()
	panel.name = "ReviewIdentity"
	panel.theme_type_variation = &"ClassicInset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var portrait := TextureRect.new()
	portrait.name = "ReviewPortrait"
	portrait.custom_minimum_size = Vector2(80.0, 72.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = _appearance_textures.get(character.portrait_id) as Texture2D
	if portrait.texture != null:
		row.add_child(portrait)
	else:
		portrait.free()
		var unavailable := _label("Portrait unavailable", MUTED, 12)
		unavailable.name = "ReviewPortraitUnavailable"
		unavailable.custom_minimum_size = Vector2(80.0, 72.0)
		row.add_child(unavailable)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(_label(character.name, GOLD, 18))
	identity.add_child(_label("Level %d • %s %s • %s" % [character.level, character.race_name, character.caste_name, character.gender_name], Color("e0e2e5"), 14))
	identity.add_child(_label("Age %d • %s" % [character.age_years, character.age_group_name], MUTED, 12))
	row.add_child(identity)
	var icon := TextureRect.new()
	icon.name = "ReviewCombatIcon"
	icon.custom_minimum_size = Vector2(64.0, 64.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _appearance_textures.get(character.combat_icon_id) as Texture2D
	if icon.texture != null:
		row.add_child(icon)
	else:
		icon.free()
		var unavailable := _label("Battle icon\nunavailable", MUTED, 11)
		unavailable.name = "ReviewCombatIconUnavailable"
		unavailable.custom_minimum_size = Vector2(64.0, 64.0)
		row.add_child(unavailable)
	return panel

func _add_review_record(parent: Container, node_name: String, title: String, lines: Array[String]) -> void:
	var body := _add_creator_panel(parent, node_name, title, 1.0)
	for line: String in lines:
		var label := _add_label(body, line, Color("e0e2e5"), 12)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = line

func _review_attribute_lines(character: CharacterView) -> Array[String]:
	return [
		"Brawn  %d" % character.brawn,
		"Knowledge  %d" % character.knowledge,
		"Judgment  %d" % character.judgment,
		"Agility  %d" % character.agility,
		"Vitality  %d" % character.vitality,
		"Luck  %d" % character.luck,
	]

func _review_combat_lines(character: CharacterView) -> Array[String]:
	return [
		"Stamina  %d/%d" % [character.current_health, character.maximum_health],
		"Spell Points  %d/%d" % [character.spell_points, character.maximum_spell_points],
		"Armor  %d • To Hit  %d" % [character.armor, character.to_hit],
		"Dodge  %d • Missile  %d" % [character.dodge, character.missile],
		"Two-Hand  %d • Hand-to-Hand  %d" % [character.two_hand, character.hand_to_hand],
		"Damage  %+d • Movement  %d" % [character.damage_bonus, character.maximum_movement],
		"Magic Resistance  %d%%" % character.magic_resistance,
	]

func _build_review_saves_equipment(parent: Container, character: CharacterView) -> void:
	var body := _add_creator_panel(parent, "ReviewSavesEquipment", "Saves & Equipment", 1.0)
	for index: int in range(0, character.saving_throws.size(), 2):
		var left: CharacterMetricView = character.saving_throws[index]
		var text := "%s %d" % [left.name, left.value]
		if index + 1 < character.saving_throws.size():
			var right: CharacterMetricView = character.saving_throws[index + 1]
			text += " • %s %d" % [right.name, right.value]
		body.add_child(_label(text, Color("e0e2e5"), 12))
	body.add_child(_label("Starting Equipment", GOLD, 12))
	if character.items.is_empty():
		body.add_child(_label("None", MUTED, 12))
		return
	var item_scroll := ScrollContainer.new()
	item_scroll.name = "ReviewItemScroll"
	item_scroll.custom_minimum_size.y = 72.0
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: ItemView in character.items:
		items.add_child(_review_item_row(item))
	item_scroll.add_child(items)
	body.add_child(item_scroll)

func _review_item_row(item: ItemView) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var asset := media.asset_by_resource(item.icon_resource_type, item.icon_id) if media != null and item.icon_id > 0 else null
	var texture := media.image_texture(asset) if media != null and asset != null else null
	if texture != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28.0, 28.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = texture
		row.add_child(icon)
	else:
		var unavailable := _label("?", MUTED, 14)
		unavailable.custom_minimum_size = Vector2(28.0, 28.0)
		unavailable.tooltip_text = "Item art unavailable for the exact Classic resource."
		row.add_child(unavailable)
	var item_text := _label("%s%s" % ["Equipped • " if item.equipped else "", item.name], Color("e0e2e5"), 12)
	item_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item_text.tooltip_text = item.name
	item_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item_text)
	return row

func _build_creator_spells() -> void:
	creator_page.add_child(_label("Starting Spells", GOLD, 20))
	if view == null or view.character_draft == null:
		var unavailable := _add_creator_panel(creator_page, "StartingSpellUnavailable", "Spell Selection")
		spell_label = _add_label(unavailable, "Generate and review the character before choosing spells.", MUTED)
		return
	if view.character_draft.spellcaster_type < 1 or view.character_draft_spell_points_total < 1:
		var not_applicable := _add_creator_panel(creator_page, "StartingSpellNotApplicable", "No Starting Spells")
		spell_label = _add_label(not_applicable, "%s receives no Classic starting-spell choices." % view.character_draft.name, MUTED)
		return
	if view.character_draft_spell_options.is_empty():
		var missing := _add_creator_panel(creator_page, "StartingSpellUnavailable", "Starting Spells Unavailable")
		spell_label = _add_label(missing, "This caster has selection points, but the package exposes no matching Classic spell records. Finalization is blocked.", ERROR)
		return
	_prepare_starting_spell_selection()
	var workspace := HBoxContainer.new()
	workspace.name = "StartingSpellWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 8)
	creator_page.add_child(workspace)
	var level_rail := _add_creator_panel(workspace, "StartingSpellLevelRail", "Level", 0.38)
	level_rail.custom_minimum_size.x = 72.0
	for level: int in range(1, 8):
		var level_button := Button.new()
		level_button.name = "StartingSpellLevel%d" % level
		level_button.text = str(level)
		level_button.toggle_mode = true
		level_button.button_pressed = level == _starting_spell_level
		level_button.disabled = not _starting_spell_level_available(level)
		level_button.tooltip_text = "No starting spells are available at this level." if level_button.disabled else "Show level %d starting spells." % level
		level_button.pressed.connect(_select_starting_spell_level.bind(level))
		level_rail.add_child(level_button)
	var list_panel := _add_creator_panel(workspace, "StartingSpellListPanel", "Available Spells", 1.05)
	spell_list = ItemList.new()
	spell_list.name = "StartingSpellList"
	spell_list.select_mode = ItemList.SELECT_MULTI
	spell_list.custom_minimum_size = Vector2(180.0, 190.0)
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.level != _starting_spell_level:
			continue
		spell_list.add_item("%s  •  %d point%s" % [option.name, option.selection_cost, "" if option.selection_cost == 1 else "s"])
		var index := spell_list.item_count - 1
		spell_list.set_item_metadata(index, option.id)
		spell_list.set_item_tooltip(index, option.description)
		if option.selected:
			spell_list.select(index, false)
		if not option.selected and option.selection_cost > view.character_draft_spell_points_remaining:
			spell_list.set_item_disabled(index, true)
			spell_list.set_item_tooltip(index, "This spell costs %d points; %d remain." % [option.selection_cost, view.character_draft_spell_points_remaining])
	spell_list.multi_selected.connect(_draft_spell_selection_changed)
	list_panel.add_child(spell_list)
	var detail := _add_creator_panel(workspace, "StartingSpellRecord", "Selected Spell", 1.15)
	var selected := _starting_spell_option(_starting_spell_id)
	if selected == null:
		spell_label = _add_label(detail, "Choose a spell from level %d." % _starting_spell_level, MUTED)
	else:
		spell_label = _add_label(detail, selected.name, GOLD, 18)
		_add_label(detail, "Level %d  •  %d selection point%s" % [selected.level, selected.selection_cost, "" if selected.selection_cost == 1 else "s"], Color("e0e2e5"), 13)
		if not selected.description.strip_edges().is_empty():
			_add_label(detail, selected.description.strip_edges(), Color("e0e2e5"), 13)
		_add_label(detail, "Selected" if selected.selected else "Available", GOLD if selected.selected else MUTED, 13)
	var allowance := PanelContainer.new()
	allowance.name = "StartingSpellAllowance"
	allowance.theme_type_variation = &"ClassicInset"
	allowance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var allowance_row := HBoxContainer.new()
	allowance_row.add_child(_label("Spell allowance", MUTED, 12))
	allowance_row.add_spacer(true)
	allowance_row.add_child(_label("%d of %d points remain" % [view.character_draft_spell_points_remaining, view.character_draft_spell_points_total], GOLD, 14))
	allowance.add_child(allowance_row)
	creator_page.add_child(allowance)

func _prepare_starting_spell_selection() -> void:
	if not _starting_spell_level_available(_starting_spell_level):
		_starting_spell_level = view.character_draft_spell_options[0].level
	var selected := _starting_spell_option(_starting_spell_id)
	if selected == null or selected.level != _starting_spell_level:
		_starting_spell_id = ""
		for option: CharacterSpellOptionView in view.character_draft_spell_options:
			if option.level == _starting_spell_level:
				_starting_spell_id = option.id
				break

func _starting_spell_level_available(level: int) -> bool:
	if view == null:
		return false
	return view.character_draft_spell_options.any(func(option: CharacterSpellOptionView) -> bool: return option.level == level)

func _starting_spell_option(option_id: String) -> CharacterSpellOptionView:
	if view == null:
		return null
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.id == option_id:
			return option
	return null

func _select_starting_spell_level(level: int) -> void:
	if not _starting_spell_level_available(level):
		return
	_starting_spell_level = level
	_starting_spell_id = ""
	render_creator_step()

func creator_next() -> void:
	match creator_step:
		0:
			draft_name = name_edit.text.strip_edges()
			draft_gender = gender_option.get_selected_id()
			draft_starting_level = starting_level_option.get_selected_id()
			if draft_name.is_empty():
				setup_message.text = "Enter a character name before continuing."
				return
			creator_step = 1
		1:
			if selected_race_id.is_empty() or selected_caste_id.is_empty():
				setup_message.text = "Choose both a race and a compatible class."
				return
			creator_step = 2
		2:
			if view != null and view.party_members.size() >= _assembly._maximum_party_size():
				setup_message.text = "This campaign allows no more than %d characters." % _assembly._maximum_party_size()
				return
			var portrait_value := _selected_appearance(portrait_option, true)
			var combat_icon_value := _selected_appearance(combat_icon_option, false)
			if portrait_value == null or combat_icon_value == null:
				setup_message.text = "Choose a package-backed portrait and combat icon before continuing."
				return
			draft_portrait_id = portrait_value.id
			draft_combat_icon_id = combat_icon_value.id
			creator_step = 3
			awaiting_draft_generation = true
			_state.intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))
			return
		3:
			if view == null or view.character_draft == null:
				setup_message.text = "The Classic character roll did not complete. Review the action error before continuing."
				return
			creator_step = 4
		4:
			if view == null or view.character_draft == null:
				return
			if view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0 and view.character_draft_spell_options.is_empty():
				setup_message.text = "Starting spells are unavailable in this package, so this caster cannot be finalized safely."
				return
			awaiting_draft_finalization = true
			_state.intent_submitted.emit(PlayerIntent.finalize_character())
			return
	setup_message.text = _creator_step_message()
	render_creator_step()

func creator_back() -> void:
	if creator_step <= 0:
		return
	if creator_step == 3 and view != null and view.character_draft != null:
		creator_step = 2
		_state.intent_submitted.emit(PlayerIntent.cancel_character_draft())
		return
	creator_step -= 1
	setup_message.text = _creator_step_message()
	render_creator_step()

func _cancel_creator() -> void:
	var had_generated_draft := view != null and view.character_draft != null
	reset_creator(true)
	if had_generated_draft:
		_state.intent_submitted.emit(PlayerIntent.cancel_character_draft())
	if standalone_character_creation_active:
		_state.standalone_character_creation_cancelled.emit()
	elif not had_generated_draft:
		render_creator_step()

func reset_creator(return_to_assembly: bool = false) -> void:
	if return_to_assembly:
		setup_mode = &"assembly"
	creator_step = 0
	draft_name = ""
	draft_gender = 1
	draft_starting_level = 1
	draft_portrait_id = ""
	draft_combat_icon_id = ""
	combat_icon_touched = false
	selected_race_id = ""
	selected_caste_id = ""
	awaiting_draft_generation = false
	awaiting_draft_finalization = false
	if setup_message != null:
		setup_message.text = "Choose stored characters or create a new one." if setup_mode == &"assembly" else "Enter a name to begin creating another character."

func _reroll_character() -> void:
	if creator_step != 3 or view == null or view.character_draft == null:
		return
	awaiting_draft_generation = true
	_state.intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))

func _draft_spell_selection_changed(index: int, selected: bool) -> void:
	if spell_list == null:
		return
	_starting_spell_id = String(spell_list.get_item_metadata(index))
	var selected_ids: Array[String] = []
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.level != _starting_spell_level and option.selected:
			selected_ids.append(option.id)
	for item_index: int in spell_list.item_count:
		if spell_list.is_selected(item_index) or item_index == index and selected:
			selected_ids.append(String(spell_list.get_item_metadata(item_index)))
	_state.intent_submitted.emit(PlayerIntent.set_character_draft_spells(selected_ids))

func _character_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(draft_name, selected_race_id, selected_caste_id, draft_gender, draft_portrait_id, draft_combat_icon_id, draft_starting_level)

func _creator_step_message() -> String:
	var final_step := "Choose starting spells, then create the Character File." if standalone_character_creation_active else "Choose starting spells, then add the character to the party."
	return ["Enter the character's identity.", "Choose a race, then a compatible class.", "Choose the character's appearance.", "Review or reroll the generated Classic character.", final_step][creator_step]

func _update_creator_actions() -> void:
	if creator_back_button == null:
		return
	creator_back_button.disabled = creator_step == 0
	add_character_button.visible = creator_step == 3
	_apply_availability(add_character_button, &"generate_character_draft")
	if creator_step == 4:
		creator_next_button.text = "Create Character File" if standalone_character_creation_active else "Add to party"
	elif creator_step == 3 and view != null and view.character_draft != null and view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0:
		creator_next_button.text = "Choose spells"
	else:
		creator_next_button.text = "Continue"
	if creator_step == 4:
		_apply_availability(creator_next_button, &"finalize_character")
	else:
		creator_next_button.disabled = false
		creator_next_button.tooltip_text = ""
	creator_cancel_button.disabled = false

func _race_selected(index: int) -> void:
	if index < 0 or race_list.is_item_disabled(index):
		return
	var selected_id := String(race_list.get_item_metadata(index))
	if selected_id != selected_race_id:
		draft_portrait_id = ""
		draft_combat_icon_id = ""
		combat_icon_touched = false
	selected_race_id = selected_id
	_apply_caste_filter()
	_refresh_race_class_details()
	setup_message.text = "Race selected. Classes unavailable to this race are disabled on the right."

func _caste_selected(index: int) -> void:
	if index < 0 or caste_list.is_item_disabled(index):
		return
	selected_caste_id = String(caste_list.get_item_metadata(index))
	_refresh_race_class_details()
	setup_message.text = "Class selected. Continue to appearance when ready."

func _apply_caste_filter() -> void:
	if view == null or caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in view.race_options:
		if option.id == selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	for index: int in caste_list.item_count:
		var caste_id := String(caste_list.get_item_metadata(index))
		var restricted := view.campaign_summary != null and view.campaign_summary.banned_castes.has(caste_id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(caste_id)
		caste_list.set_item_disabled(index, restricted or not compatible)
		var definition := _definition_option(view.caste_options, caste_id)
		var tooltip := definition.description if definition != null else ""
		if restricted:
			tooltip = "Unavailable in this scenario."
		elif not compatible:
			tooltip = "Unavailable to the selected race."
		caste_list.set_item_tooltip(index, tooltip)
	if not selected_caste_id.is_empty() and not _option_is_enabled(caste_list, selected_caste_id):
		selected_caste_id = ""
		var first_caste := _first_enabled_item(caste_list)
		if first_caste >= 0:
			selected_caste_id = String(caste_list.get_item_metadata(first_caste))
	_select_item_by_id(caste_list, selected_caste_id)

func _select_item_by_id(list: ItemList, option_id: String) -> void:
	if list == null or option_id.is_empty():
		return
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			list.select(index)
			return

func _option_is_enabled(list: ItemList, option_id: String) -> bool:
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			return not list.is_item_disabled(index)
	return false

func _first_enabled_item(list: ItemList) -> int:
	for index: int in list.item_count:
		if not list.is_item_disabled(index):
			return index
	return -1

func _start_creator() -> void:
	if view == null or not view.party_setup_available:
		if standalone_character_creation_available:
			_state.standalone_character_creation_requested.emit()
			return
		setup_message.text = standalone_character_creation_reason
		return
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()

func _update_creator_review() -> void:
	if review_label == null:
		return
	if view == null or view.character_draft == null:
		review_label.text = "The Classic character roll has not completed."
		review_label.visible = true
		return
	review_label.text = ""
	review_label.visible = false

func _apply_creator_layout(profile_id: StringName) -> void:
	if creator != null:
		creator.vertical = profile_id == UiLayoutProfile.COMPACT
	var review_records: BoxContainer
	if creator_page != null:
		review_records = creator_page.find_child("ReviewRecordPanels", true, false) as BoxContainer
	if review_records != null:
		review_records.vertical = profile_id == UiLayoutProfile.COMPACT
	_state.apply_setup_mode_layout()

func apply_creator_layout(profile_id: StringName) -> void:
	_apply_creator_layout(profile_id)
