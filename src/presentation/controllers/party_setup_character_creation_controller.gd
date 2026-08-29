class_name PartySetupCharacterCreationController
extends "res://src/presentation/controllers/party_setup_controller_component.gd"

const SpellSelectionChrome := preload("res://src/presentation/controllers/classic_spell_selection_chrome.gd")
const SpellEffectPreview := preload("res://src/presentation/classic_spell_effect_preview.gd")

var _assembly: RefCounted
var _starting_spell_level: int = 0
var _starting_spell_id: String = ""
var _portrait_page: int = 0
var _combat_icon_page: int = 0

const APPEARANCE_COLUMNS: int = 6
const APPEARANCE_ROWS_PER_PAGE: int = 2


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
	setup_message.visible = false
	setup_message.tooltip_text = ""
	setup_message.modulate = MUTED
	setup_message.custom_minimum_size.y = 32.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	setup_message.text = ""
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
	name_edit.theme_type_variation = &"ClassicTheldrowLineEdit"
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
	gender_option.theme_type_variation = &"ClassicTheldrowOptionButton"
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
	starting_level_option.theme_type_variation = &"ClassicTheldrowOptionButton"
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

func _add_creator_panel(parent: Container, node_name: String, title: String, stretch: float = 1.0, title_asset_id: StringName = &"") -> VBoxContainer:
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
	if not title_asset_id.is_empty():
		body.add_child(_classic_ui_art(title_asset_id, Vector2(68.0, 18.0)))
	elif not title.is_empty():
		body.add_child(_label(title, GOLD, 15))
	parent.add_child(panel)
	return body

func _classic_ui_art(asset_id: StringName, minimum_size: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = ClassicUiAssetCatalog.texture(asset_id)
	art.custom_minimum_size = minimum_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return art

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
	creator_page.add_child(_label("Race & Caste", GOLD, 20))
	var columns := HBoxContainer.new()
	race_caste_columns = columns
	columns.name = "RaceCasteSelectors"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	var race_column := _add_creator_panel(columns, "RaceSelectorPanel", "Race", 1.0)
	var race_record := HBoxContainer.new()
	race_record.name = "RaceSelectorRecord"
	race_record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_record.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_record.add_theme_constant_override("separation", 8)
	race_column.add_child(race_record)
	race_list = ClassicDefinitionToggleList.new()
	race_list.name = "RaceList"
	race_list.custom_minimum_size = Vector2(150.0, 300.0)
	race_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	race_list.size_flags_stretch_ratio = 1.0
	race_list.option_selected.connect(_race_selected)
	race_record.add_child(race_list)
	var race_detail_panel := _add_creator_panel(race_record, "RaceDetailPanel", "Selected Race", 2.0)
	var race_detail_name := _add_label(race_detail_panel, "", GOLD, 18)
	race_detail_name.name = "RaceDetailName"
	var race_detail := _add_label(race_detail_panel, "", Color("e0e2e5"), 15)
	race_detail.name = "RaceDescription"
	race_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var race_facts := _add_label(race_detail_panel, "", Color("e0e2e5"), 13)
	race_facts.name = "RaceFacts"
	race_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var race_relations := _add_label(race_detail_panel, "", MUTED, 13)
	race_relations.name = "RaceRelations"
	race_relations.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var caste_column := _add_creator_panel(columns, "CasteSelectorPanel", "Caste", 1.0)
	var caste_record := HBoxContainer.new()
	caste_record.name = "CasteSelectorRecord"
	caste_record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caste_record.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caste_record.add_theme_constant_override("separation", 8)
	caste_column.add_child(caste_record)
	caste_list = ClassicDefinitionToggleList.new()
	caste_list.name = "CasteList"
	caste_list.custom_minimum_size = Vector2(150.0, 300.0)
	caste_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	caste_list.size_flags_stretch_ratio = 1.0
	caste_list.option_selected.connect(_caste_selected)
	caste_record.add_child(caste_list)
	var caste_detail_panel := _add_creator_panel(caste_record, "CasteDetailPanel", "Selected Caste", 2.0)
	var caste_detail_name := _add_label(caste_detail_panel, "", GOLD, 18)
	caste_detail_name.name = "CasteDetailName"
	var caste_detail := _add_label(caste_detail_panel, "", Color("e0e2e5"), 15)
	caste_detail.name = "CasteDescription"
	caste_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var caste_facts := _add_label(caste_detail_panel, "", Color("e0e2e5"), 13)
	caste_facts.name = "CasteFacts"
	caste_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var caste_relations := _add_label(caste_detail_panel, "", MUTED, 13)
	caste_relations.name = "CasteRelations"
	caste_relations.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	creator_page.add_child(columns)
	_populate_race_class_options()

func _populate_race_class_options() -> void:
	if view == null or race_list == null or caste_list == null:
		return
	for option: DefinitionOptionView in view.race_options:
		if _placeholder_definition_name(option.name, "Race"):
			continue
		var race_restricted := view.campaign_summary != null and view.campaign_summary.banned_races.has(option.id)
		race_list.add_option(option.id, option.name, "Unavailable in this scenario." if race_restricted else option.description, not race_restricted, option.id == selected_race_id)
	if selected_race_id.is_empty() or not race_list.is_enabled(selected_race_id):
		selected_race_id = race_list.first_enabled_id()
	race_list.select_id(selected_race_id)
	_rebuild_caste_options()
	if selected_caste_id.is_empty() or not caste_list.is_enabled(selected_caste_id):
		selected_caste_id = caste_list.first_enabled_id()
	caste_list.select_id(selected_caste_id)
	_refresh_race_class_details()

func _refresh_race_class_details() -> void:
	var race_detail_name := creator_page.find_child("RaceDetailName", true, false) as Label
	var race_detail := creator_page.find_child("RaceDescription", true, false) as Label
	var race_facts := creator_page.find_child("RaceFacts", true, false) as Label
	var race_relations := creator_page.find_child("RaceRelations", true, false) as Label
	var caste_detail_name := creator_page.find_child("CasteDetailName", true, false) as Label
	var caste_detail := creator_page.find_child("CasteDescription", true, false) as Label
	var caste_facts := creator_page.find_child("CasteFacts", true, false) as Label
	var caste_relations := creator_page.find_child("CasteRelations", true, false) as Label
	var race_option := _definition_option(view.race_options if view != null else [], selected_race_id)
	var caste_option := _definition_option(view.caste_options if view != null else [], selected_caste_id)
	if race_detail_name != null:
		race_detail_name.text = race_option.name if race_option != null else "No race selected"
	if race_detail != null:
		race_detail.text = race_option.description if race_option != null else ""
		race_detail.visible = not race_detail.text.is_empty()
	if race_facts != null:
		race_facts.text = "\n".join(race_option.facts) if race_option != null else ""
		race_facts.visible = not race_facts.text.is_empty()
	if race_relations != null:
		race_relations.text = _related_definition_text("Compatible Castes", view.caste_options if view != null else [], race_option.related_ids if race_option != null else [])
	if caste_detail_name != null:
		caste_detail_name.text = caste_option.name if caste_option != null else "No caste selected"
	if caste_detail != null:
		caste_detail.text = caste_option.description if caste_option != null else ""
		caste_detail.visible = not caste_detail.text.is_empty()
	if caste_facts != null:
		caste_facts.text = "\n".join(caste_option.facts) if caste_option != null else ""
		caste_facts.visible = not caste_facts.text.is_empty()
	if caste_relations != null:
		caste_relations.text = _related_definition_text("Compatible Races", view.race_options if view != null else [], caste_option.related_ids if caste_option != null else [])


func _related_definition_text(heading: String, options: Array[DefinitionOptionView], related_ids: Array[String]) -> String:
	var names: Array[String] = []
	for option: DefinitionOptionView in options:
		if related_ids.has(option.id) and not _placeholder_definition_name(option.name, "Race") and not _placeholder_definition_name(option.name, "Caste"):
			names.append(option.name)
	names.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	return "%s\n%s" % [heading, ", ".join(names)] if not names.is_empty() else ""

func _placeholder_definition_name(display_name: String, prefix: String) -> bool:
	if not display_name.begins_with(prefix + " "):
		return false
	return display_name.trim_prefix(prefix + " ").is_valid_int()

func _definition_option(options: Array[DefinitionOptionView], option_id: String) -> DefinitionOptionView:
	for option: DefinitionOptionView in options:
		if option.id == option_id:
			return option
	return null

func _build_creator_appearance() -> void:
	creator_page.add_child(_label("Appearance", GOLD, 20))
	var selected_asset_ids: Array[String] = []
	if not draft_portrait_id.is_empty(): selected_asset_ids.append(draft_portrait_id)
	if not draft_combat_icon_id.is_empty(): selected_asset_ids.append(draft_combat_icon_id)
	_ensure_appearance_textures(selected_asset_ids)
	var appearance_row := HBoxContainer.new()
	appearance_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	appearance_row.add_theme_constant_override("separation", 14)
	var preview_panel := PanelContainer.new()
	preview_panel.name = "AppearancePreview"
	preview_panel.theme_type_variation = &"ClassicInset"
	preview_panel.custom_minimum_size = Vector2(220.0, 300.0)
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
	portrait_option = OptionButton.new()
	portrait_option.name = "PortraitOption"
	portrait_option.fit_to_longest_item = false
	var portrait_options := _sorted_appearance_options(view.portrait_options if view != null else [])
	for option: CharacterAppearanceOptionView in portrait_options:
		_add_appearance_option(portrait_option, option)
	_select_appearance_default(portrait_option, draft_portrait_id, true)
	if portrait_option.selected >= 0:
		draft_portrait_id = String(portrait_option.get_item_metadata(portrait_option.selected))
	portrait_option.visible = false
	choices.add_child(portrait_option)
	choices.add_child(_build_appearance_thumbnail_strip(portrait_option, portrait_options, "PortraitThumbnailStrip", true))
	combat_icon_option = OptionButton.new()
	combat_icon_option.name = "CombatIconOption"
	combat_icon_option.fit_to_longest_item = false
	var combat_options := _sorted_appearance_options(view.combat_icon_options if view != null else [])
	for option: CharacterAppearanceOptionView in combat_options:
		_add_appearance_option(combat_icon_option, option)
	_select_appearance_default(combat_icon_option, draft_combat_icon_id, false)
	if combat_icon_option.selected >= 0:
		draft_combat_icon_id = String(combat_icon_option.get_item_metadata(combat_icon_option.selected))
	combat_icon_option.visible = false
	choices.add_child(combat_icon_option)
	choices.add_child(_build_appearance_thumbnail_strip(combat_icon_option, combat_options, "CombatIconThumbnailStrip", false))
	appearance_row.add_child(choices)
	creator_page.add_child(appearance_row)
	_refresh_appearance_preview()
	if portrait_options.is_empty() or combat_options.is_empty():
		_add_label(creator_page, "This package does not expose the complete Classic appearance catalog. Character generation is unavailable until the package is re-exported.", ERROR)

func _build_appearance_thumbnail_strip(control: OptionButton, options: Array[CharacterAppearanceOptionView], strip_name: String, portrait: bool) -> Control:
	var panel := PanelContainer.new()
	panel.name = strip_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_child(_label("Portraits" if portrait else "Combat Icons", GOLD, 15))
	header.add_spacer(true)
	var rows := _appearance_rows(options)
	var page := _portrait_page if portrait else _combat_icon_page
	var page_count := maxi(1, int(ceil(float(rows.size()) / float(APPEARANCE_ROWS_PER_PAGE))))
	page = clampi(page, 0, page_count - 1)
	if portrait:
		_portrait_page = page
	else:
		_combat_icon_page = page
	var previous := Button.new()
	previous.text = "Previous"
	previous.disabled = page == 0
	previous.pressed.connect(_change_appearance_page.bind(-1, portrait))
	header.add_child(previous)
	header.add_child(_label("Page %d of %d" % [page + 1, page_count], MUTED, 12))
	var next_button := Button.new()
	next_button.text = "Next"
	next_button.disabled = page >= page_count - 1
	next_button.pressed.connect(_change_appearance_page.bind(1, portrait))
	header.add_child(next_button)
	body.add_child(header)
	var group := ButtonGroup.new()
	var selected_id := String(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""
	var start_row := page * APPEARANCE_ROWS_PER_PAGE
	var finish_row := mini(start_row + APPEARANCE_ROWS_PER_PAGE, rows.size())
	var visible_asset_ids: Array[String] = []
	for row_index: int in range(start_row, finish_row):
		for option: CharacterAppearanceOptionView in (rows[row_index]["options"] as Array):
			visible_asset_ids.append(option.id)
	_ensure_appearance_textures(visible_asset_ids)
	for row_index: int in range(start_row, finish_row):
		var row_record: Dictionary = rows[row_index]
		var row_section := VBoxContainer.new()
		row_section.name = "%sRaceRow%d" % ["Portrait" if portrait else "CombatIcon", row_index]
		row_section.add_theme_constant_override("separation", 2)
		var row_label := _label(String(row_record["label"]), MUTED, 12)
		row_label.name = "%sRaceLabel%d" % ["Portrait" if portrait else "CombatIcon", row_index]
		row_section.add_child(row_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_section.add_child(row)
		body.add_child(row_section)
		var row_options: Array = row_record["options"] as Array
		for column_index: int in APPEARANCE_COLUMNS:
			if column_index >= row_options.size():
				var spacer := Control.new()
				spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spacer)
				continue
			var option: CharacterAppearanceOptionView = row_options[column_index]
			var choice := Button.new()
			choice.name = "%s_%d" % ["PortraitChoice" if portrait else "CombatIconChoice", option.classic_resource_id]
			choice.custom_minimum_size = Vector2(72.0, 72.0)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice.toggle_mode = true
			choice.button_group = group
			choice.button_pressed = option.id == selected_id
			choice.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var texture := _appearance_textures.get(option.id) as Texture2D
			if texture != null:
				choice.icon = texture
				choice.expand_icon = true
			else:
				choice.text = "Unavailable"
			choice.tooltip_text = option.label
			choice.pressed.connect(_select_appearance_thumbnail.bind(control, option.id, portrait))
			row.add_child(choice)
	if rows.is_empty():
		body.add_child(_label("No exact Classic appearance media is available.", MUTED, 12))
	return panel


func _appearance_rows(options: Array[CharacterAppearanceOptionView]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ordered_races: Array[DefinitionOptionView] = []
	if view != null:
		for race: DefinitionOptionView in view.race_options:
			if race.id == selected_race_id:
				ordered_races.push_front(race)
			else:
				ordered_races.append(race)
	var assigned: Dictionary = {}
	for race: DefinitionOptionView in ordered_races:
		var recommended: Array[CharacterAppearanceOptionView] = []
		for option: CharacterAppearanceOptionView in options:
			if option.is_recommended_for(race.id):
				recommended.append(option)
				assigned[option.id] = true
		_append_appearance_rows(rows, race.name, recommended)
	var ungrouped: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if not assigned.has(option.id):
			ungrouped.append(option)
	_append_appearance_rows(rows, "Classic catalog", ungrouped)
	return rows


func _append_appearance_rows(rows: Array[Dictionary], label: String, options: Array[CharacterAppearanceOptionView]) -> void:
	for start: int in range(0, options.size(), APPEARANCE_COLUMNS):
		var chunk: Array[CharacterAppearanceOptionView] = []
		for option_index: int in range(start, mini(start + APPEARANCE_COLUMNS, options.size())):
			chunk.append(options[option_index])
		rows.append({"label": label, "options": chunk})

func _change_appearance_page(delta: int, portrait: bool) -> void:
	if portrait:
		_portrait_page += delta
	else:
		_combat_icon_page += delta
	render_creator_step()

func _select_appearance_thumbnail(control: OptionButton, option_id: String, portrait: bool) -> void:
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) != option_id:
			continue
		control.select(index)
		if portrait:
			draft_portrait_id = option_id
			_portrait_selected(index)
		else:
			draft_combat_icon_id = option_id
			_combat_icon_selected(index)
		render_creator_step()
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
	var label := option.label
	var texture := _appearance_textures.get(option.id) as Texture2D
	if texture != null:
		control.add_icon_item(texture, label)
	else:
		control.add_item(label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, option.label)

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
					draft_combat_icon_id = icon.id
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
	var review_asset_ids: Array[String] = [character.portrait_id, character.combat_icon_id]
	_ensure_appearance_textures(review_asset_ids)
	var sheet := ClassicCharacterSheet.new()
	sheet.name = "CreatorReviewSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var characters: Array[CharacterView] = [character]
	sheet.present(
		characters,
		character.id,
		_appearance_textures,
		settings.text_scale if settings != null else 1.0,
		&"overview",
		view.portrait_options,
		view.combat_icon_options,
		ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance is selected in the previous creator stage."),
		media,
		layout_profile,
		false
	)
	creator_page.add_child(sheet)

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
	var level_rail := _add_creator_panel(workspace, "StartingSpellLevelRail", "", 0.38, &"spells.label.level")
	level_rail.custom_minimum_size.x = 72.0
	for level: int in range(1, 8):
		var level_button := SpellSelectionChrome.level_button(
			level,
			level == _starting_spell_level,
			_starting_spell_level_available(level),
			_select_starting_spell_level.bind(level),
			"No starting spells are available at this level."
		)
		level_button.name = "StartingSpellLevel%d" % level
		level_rail.add_child(level_button)
	var list_panel := _add_creator_panel(workspace, "StartingSpellListPanel", "Available Spells", 1.05)
	var spell_scroll := ScrollContainer.new()
	spell_scroll.name = "StartingSpellScroll"
	spell_scroll.custom_minimum_size = Vector2(260.0, 300.0)
	spell_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spell_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	spell_list = VBoxContainer.new()
	spell_list.name = "StartingSpellList"
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_list.add_theme_constant_override("separation", 3)
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.level != _starting_spell_level:
			continue
		var enabled := option.selected or option.selection_cost <= view.character_draft_spell_points_remaining
		var tooltip := option.description if enabled else "This spell costs %d points; %d remain." % [option.selection_cost, view.character_draft_spell_points_remaining]
		var button := SpellSelectionChrome.spell_button(
			"StartingSpell_%s" % option.id,
			"%s   %d point%s" % [option.name, option.selection_cost, "" if option.selection_cost == 1 else "s"],
			option.selected,
			enabled,
			tooltip,
			_draft_spell_toggled.bind(option.id, not option.selected),
			ClassicUiAssetCatalog.texture(&"spells.button.available" if option.selected else &"spells.button.unavailable")
		)
		spell_list.add_child(button)
	spell_scroll.add_child(spell_list)
	list_panel.add_child(spell_scroll)
	var detail := _add_creator_panel(workspace, "StartingSpellRecord", "Selected Spell", 1.15)
	var selected := _starting_spell_option(_starting_spell_id)
	if selected == null:
		spell_label = _add_label(detail, "Choose a spell from level %d." % _starting_spell_level, MUTED)
	else:
		spell_label = _add_label(detail, selected.name, GOLD, 18)
		_add_label(detail, "Level %d  •  %d selection point%s" % [selected.level, selected.selection_cost, "" if selected.selection_cost == 1 else "s"], Color("e0e2e5"), 13)
		var preview := SpellEffectPreview.new()
		if preview.present(media, selected.animation_resource_type, selected.animation_resource_ids):
			detail.add_child(preview)
		else:
			preview.free()
		var description_heading := _label("Description", GOLD, 13)
		detail.add_child(description_heading)
		var description := selected.description.strip_edges()
		var description_label := _add_label(detail, description if not description.is_empty() else "Description unavailable.", Color("e0e2e5") if not description.is_empty() else MUTED, 16)
		description_label.name = "StartingSpellDescription"
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
				_show_creator_error("Enter a character name before continuing.")
				return
			creator_step = 1
		1:
			if selected_race_id.is_empty() or selected_caste_id.is_empty():
				_show_creator_error("Choose both a race and a compatible caste.")
				return
			creator_step = 2
		2:
			if view != null and view.party_members.size() >= _assembly._maximum_party_size():
				_show_creator_error("This campaign allows no more than %d characters." % _assembly._maximum_party_size())
				return
			var portrait_value := _selected_appearance(portrait_option, true)
			var combat_icon_value := _selected_appearance(combat_icon_option, false)
			if portrait_value == null or combat_icon_value == null:
				_show_creator_error("Choose a portrait and combat icon before continuing.")
				return
			draft_portrait_id = portrait_value.id
			draft_combat_icon_id = combat_icon_value.id
			creator_step = 3
			awaiting_draft_generation = true
			_state.intent_submitted.emit(PlayerIntent.generate_character_draft(_character_creation_spec()))
			return
		3:
			if view == null or view.character_draft == null:
				_show_creator_error("The Classic character roll did not complete. Review the action error before continuing.")
				return
			creator_step = 4
		4:
			if view == null or view.character_draft == null:
				return
			if view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0 and view.character_draft_spell_options.is_empty():
				_show_creator_error("Starting spells are unavailable in this package, so this caster cannot be finalized safely.")
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

func _draft_spell_toggled(option_id: String, selected: bool) -> void:
	_starting_spell_id = option_id
	var selected_ids: Array[String] = []
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.id == option_id:
			if selected:
				selected_ids.append(option.id)
		elif option.selected:
			selected_ids.append(option.id)
	_state.intent_submitted.emit(PlayerIntent.set_character_draft_spells(selected_ids))

func _character_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(draft_name, selected_race_id, selected_caste_id, draft_gender, draft_portrait_id, draft_combat_icon_id, draft_starting_level)

func _creator_step_message() -> String:
	var final_step := "Choose starting spells, then create the Character File." if standalone_character_creation_active else "Choose starting spells, then add the character to the party."
	return ["Enter the character's identity.", "Choose a race and caste.", "Choose the character's appearance.", "Review the generated Classic character.", final_step][creator_step]

func _show_creator_error(message: String) -> void:
	setup_message.text = message
	setup_message.modulate = ERROR
	setup_message.visible = true

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

func _race_selected(selected_id: String) -> void:
	if not race_list.is_enabled(selected_id):
		return
	if selected_id != selected_race_id:
		draft_portrait_id = ""
		draft_combat_icon_id = ""
		combat_icon_touched = false
		_portrait_page = 0
		_combat_icon_page = 0
	selected_race_id = selected_id
	race_list.select_id(selected_race_id)
	_rebuild_caste_options()
	_refresh_race_class_details()

func _caste_selected(selected_id: String) -> void:
	if not caste_list.is_enabled(selected_id):
		return
	selected_caste_id = selected_id
	caste_list.select_id(selected_caste_id)
	_refresh_race_class_details()

func _rebuild_caste_options() -> void:
	if view == null or caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in view.race_options:
		if option.id == selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	var ordered: Array[DefinitionOptionView] = []
	for option: DefinitionOptionView in view.caste_options:
		if not _placeholder_definition_name(option.name, "Caste"):
			ordered.append(option)
	ordered.sort_custom(func(left: DefinitionOptionView, right: DefinitionOptionView) -> bool:
		var left_compatible := allowed_castes.is_empty() or allowed_castes.has(left.id)
		var right_compatible := allowed_castes.is_empty() or allowed_castes.has(right.id)
		if left_compatible != right_compatible:
			return left_compatible
		return left.name.naturalnocasecmp_to(right.name) < 0
	)
	caste_list.clear_options()
	for definition: DefinitionOptionView in ordered:
		var restricted := view.campaign_summary != null and view.campaign_summary.banned_castes.has(definition.id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(definition.id)
		var tooltip := definition.description
		if restricted:
			tooltip = "Unavailable in this scenario."
		elif not compatible:
			tooltip = "Unavailable to the selected race."
		caste_list.add_option(definition.id, definition.name, tooltip, not restricted and compatible, definition.id == selected_caste_id)
	if not selected_caste_id.is_empty() and not caste_list.is_enabled(selected_caste_id):
		selected_caste_id = ""
		selected_caste_id = caste_list.first_enabled_id()
	caste_list.select_id(selected_caste_id)

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
	_state.apply_setup_mode_layout()

func apply_creator_layout(profile_id: StringName) -> void:
	_apply_creator_layout(profile_id)
