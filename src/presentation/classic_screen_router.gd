class_name ClassicScreenRouter
extends Control

signal screen_changed(screen_id: StringName)
signal start_requested(package_path: String, seed: int)
signal refresh_requested
signal intent_submitted(intent: PlayerIntent)
signal system_action_requested(action_id: StringName, value: Variant)
signal presentation_setting_changed(setting_id: StringName, value: Variant)

const GOLD := Color("d5b45d")
const INK := Color("17191d")
const PANEL := Color("272b31")
const PANEL_DARK := Color("1d2025")
const MUTED := Color("9aa0a8")

var _view: GameView
var _campaigns: Array[PackageDiscoveryResult] = []
var _screen_id: StringName = &"exploration"
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _body_frame: PanelContainer
var _workspace_view: ClassicRouteScreen
var _campaign_overlay: PanelContainer
var _campaign_list: VBoxContainer
var _campaign_scroll: ScrollContainer
var _campaign_detail: RichTextLabel
var _package_path: LineEdit
var _seed: SpinBox
var _setup_overlay: PanelContainer
var _setup_body: VBoxContainer
var _creator_scroll: ScrollContainer
var _creator: BoxContainer
var _setup_campaign_label: Label
var _setup_restriction_label: Label
var _race_list: ItemList
var _caste_list: ItemList
var _name_edit: LineEdit
var _gender_option: OptionButton
var _portrait_option: OptionButton
var _combat_icon_option: OptionButton
var _party_list: VBoxContainer
var _setup_message: Label
var _review_label: Label
var _spell_label: Label
var _begin_button: Button
var _add_character_button: Button
var _setup_import_button: Button
var _vault_records: Array[CharacterVaultRecord] = []
var _selected_race_id: String = ""
var _selected_caste_id: String = ""
var _settings: PresentationSettings = PresentationSettings.new()
var _media: PackageMediaCatalog
var _route_history: Array[StringName] = []
var _focus_keys: Dictionary = {}
var _workspace_rect := Rect2(220.0, 100.0, 512.0, 430.0)
var _layout_profile: StringName = UiLayoutProfile.STANDARD
var _modal_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _campaign_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _content_parent: Container
var _inventory_query: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The router spans the window for layout only. Its panels and workspace own
	# input; the router itself must not cover menus or other shell controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_body()
	_build_campaign_overlay()
	_build_setup_overlay()
	show_campaign_selection()


func present(view: GameView) -> void:
	_view = view
	if view == null or not view.session_started:
		_body_frame.visible = false
		return
	if view.party_setup_available:
		_campaign_overlay.visible = false
		_setup_overlay.visible = true
		_body_frame.visible = false
		_refresh_setup_options()
		call_deferred("_apply_modal_layouts")
		call_deferred("_focus_first", _setup_overlay)
		return
	_setup_overlay.visible = false
	_campaign_overlay.visible = false
	_render_screen()


func set_campaigns(campaigns: Array[PackageDiscoveryResult]) -> void:
	_campaigns = campaigns.duplicate()
	_campaigns.sort_custom(_campaign_precedes)
	_clear(_campaign_list)
	if _campaigns.is_empty():
		_add_label(_campaign_list, "No installed packages. Open a Providence .realmz2 export.", MUTED)
		call_deferred("_refresh_campaign_layout")
		return
	for campaign: PackageDiscoveryResult in _campaigns:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 48)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [_display_name(campaign), "Ready • %s" % campaign.rules_version if campaign.ready else "Rejected • %s" % campaign.error_message]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = campaign.path
		row.add_child(label)
		var action := Button.new()
		action.text = "Play" if campaign.ready else "Details"
		action.disabled = not campaign.ready
		action.pressed.connect(_campaign_pressed.bind(campaign))
		row.add_child(action)
		_campaign_list.add_child(row)
	# Container minimum-size propagation runs after rows enter the tree. Restore
	# the bounded modal rect once that layout pass has settled.
	call_deferred("_refresh_campaign_layout")


func set_vault_records(records: Array[CharacterVaultRecord]) -> void:
	_vault_records = records.duplicate()
	if _screen_id == &"vault":
		_render_screen()


func set_media_catalog(media: PackageMediaCatalog) -> void:
	_media = media
	if _view != null and _view.session_started:
		_render_screen()


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_settings = settings
	if _screen_id == &"system":
		_render_screen()


func set_layout_profile(profile: UiLayoutProfile, viewport_size: Vector2) -> void:
	if profile == null:
		return
	_layout_profile = profile.id
	var top := profile.menu_height
	var bottom := profile.bottom_height
	_workspace_rect = Rect2(0.0, top, maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top - bottom))
	if _body_frame != null:
		_workspace_view.set_workspace_rect(_workspace_rect)
	_modal_layout_rect = Rect2(12.0, top + 8.0, maxf(320.0, viewport_size.x - profile.party_width - 24.0), maxf(300.0, viewport_size.y - top - 16.0))
	_campaign_layout_rect = ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
	if _setup_overlay != null:
		_creator.vertical = profile.id == UiLayoutProfile.COMPACT
		_creator_scroll.custom_minimum_size.y = 140.0 if profile.id == UiLayoutProfile.COMPACT else 220.0
	_apply_modal_layouts()
	_render_screen()


static func campaign_rect_for(profile: UiLayoutProfile, viewport_size: Vector2) -> Rect2:
	var modal_rect := Rect2(12.0, profile.menu_height + 8.0, maxf(320.0, viewport_size.x - profile.party_width - 24.0), maxf(300.0, viewport_size.y - profile.menu_height - 16.0))
	var campaign_width := minf(680.0 * profile.ui_scale, modal_rect.size.x)
	return Rect2(
		Vector2(modal_rect.position.x + (modal_rect.size.x - campaign_width) * 0.5, modal_rect.position.y),
		Vector2(campaign_width, modal_rect.size.y)
	)


func _apply_modal_layouts() -> void:
	if _setup_overlay != null:
		_setup_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_setup_overlay.position = _modal_layout_rect.position
		_setup_overlay.size = _modal_layout_rect.size
	if _campaign_overlay != null:
		_campaign_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_campaign_overlay.position = _campaign_layout_rect.position
		_campaign_overlay.size = _campaign_layout_rect.size


func _refresh_campaign_layout() -> void:
	_apply_modal_layouts()
	_campaign_scroll.scroll_vertical = 0


func _prepare_campaign_selection() -> void:
	_refresh_campaign_layout()
	_focus_first(_campaign_overlay)
	_campaign_scroll.scroll_vertical = 0


func show_campaign_selection() -> void:
	_campaign_overlay.visible = true
	_setup_overlay.visible = false
	_body_frame.visible = false
	call_deferred("_prepare_campaign_selection")


func full_stage_overlay_visible() -> bool:
	return _campaign_overlay != null and _campaign_overlay.visible or _setup_overlay != null and _setup_overlay.visible


func accepts_exploration_input() -> bool:
	return not _campaign_overlay.visible and not _setup_overlay.visible and _screen_id == &"exploration"


func open_screen(screen_id: StringName) -> void:
	if not UiRouteCatalog.has_route(screen_id):
		return
	_store_focus()
	if screen_id != _screen_id:
		_route_history.append(_screen_id)
	_screen_id = screen_id
	_campaign_overlay.visible = false
	_setup_overlay.visible = false
	screen_changed.emit(screen_id)
	_render_screen()


func handle_back() -> bool:
	if _campaign_overlay.visible:
		if _view != null and _view.session_started:
			_campaign_overlay.visible = false
			_render_screen()
			return true
		return false
	if _setup_overlay.visible:
		return false
	if not _route_history.is_empty():
		var previous: StringName = _route_history.pop_back()
		_screen_id = previous
		screen_changed.emit(previous)
		_render_screen()
		return true
	if _screen_id != &"exploration":
		_screen_id = &"exploration"
		screen_changed.emit(_screen_id)
		_render_screen()
		return true
	return false


func current_screen() -> StringName:
	return _screen_id


func _build_body() -> void:
	_mount_workspace(_screen_id)


func _mount_workspace(screen_id: StringName) -> void:
	if _workspace_view != null and _workspace_view.route_id == screen_id:
		return
	if _workspace_view != null:
		remove_child(_workspace_view)
		_workspace_view.queue_free()
	var definition := UiRouteCatalog.route(screen_id)
	var scene := load(String(definition.get("scene", ""))) as PackedScene
	if scene == null:
		push_error("Missing Classic route scene for %s" % screen_id)
		return
	_workspace_view = scene.instantiate() as ClassicRouteScreen
	_workspace_view.name = "WorkspaceFrame"
	add_child(_workspace_view)
	move_child(_workspace_view, 0)
	_workspace_view.set_workspace_rect(_workspace_rect)
	_body_frame = _workspace_view
	_body_scroll = _workspace_view.scroll
	_body = _workspace_view.body


func _build_campaign_overlay() -> void:
	_campaign_overlay = PanelContainer.new()
	_campaign_overlay.name = "CampaignLibrary"
	_campaign_overlay.theme_type_variation = &"ClassicSharedStone"
	_campaign_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_campaign_overlay.offset_left = -300.0
	_campaign_overlay.offset_top = -220.0
	_campaign_overlay.offset_right = 300.0
	_campaign_overlay.offset_bottom = 220.0
	_campaign_overlay.z_index = 30
	add_child(_campaign_overlay)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_campaign_overlay.add_child(column)
	_add_label(column, "Choose a Realmz campaign", GOLD, 24)
	_add_label(column, "Providence packages are validated before play.", MUTED)
	_campaign_list = VBoxContainer.new()
	_campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_scroll = ScrollContainer.new()
	_campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_campaign_scroll.follow_focus = true
	_campaign_scroll.add_child(_campaign_list)
	column.add_child(_campaign_scroll)
	var details := HBoxContainer.new()
	_package_path = LineEdit.new()
	_package_path.placeholder_text = "Path to .realmz2 package"
	_package_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(_package_path)
	_details_button(details)
	column.add_child(details)
	var seed_row := HBoxContainer.new()
	_seed = SpinBox.new()
	_seed.name = "Seed"
	_seed.min_value = 1
	_seed.max_value = 2147483647
	_seed.value = 1
	_seed.tooltip_text = "Deterministic Realmz seed"
	seed_row.add_child(_label("Seed"))
	seed_row.add_child(_seed)
	column.add_child(seed_row)
	var refresh := Button.new()
	refresh.text = "Refresh installed packages"
	refresh.pressed.connect(func() -> void: refresh_requested.emit())
	column.add_child(refresh)


func _details_button(row: HBoxContainer) -> void:
	var open := Button.new()
	open.text = "Open path"
	open.pressed.connect(_open_typed_path)
	row.add_child(open)


func _build_setup_overlay() -> void:
	_setup_overlay = PanelContainer.new()
	_setup_overlay.name = "PartySetup"
	_setup_overlay.theme_type_variation = &"ClassicSharedStone"
	_setup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_setup_overlay.offset_left = -440.0
	_setup_overlay.offset_top = -238.0
	_setup_overlay.offset_right = 440.0
	_setup_overlay.offset_bottom = 238.0
	_setup_overlay.z_index = 25
	add_child(_setup_overlay)
	_setup_body = VBoxContainer.new()
	_setup_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_setup_body.add_theme_constant_override("separation", 6)
	_setup_overlay.add_child(_setup_body)
	_setup_campaign_label = _add_label(_setup_body, "Assemble your party", GOLD, 24)
	_setup_campaign_label.custom_minimum_size.y = 28.0
	_setup_campaign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_setup_restriction_label = _add_label(_setup_body, "", MUTED)
	_setup_restriction_label.custom_minimum_size.y = 34.0
	_setup_restriction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	steps.custom_minimum_size.y = 24.0
	for step: String in ["1 Identity", "2 Race & Class", "3 Appearance", "4 Review", "5 Spells"]:
		var step_label := _label(step, Color("e7d078") if step.begins_with("1") else MUTED, 13)
		step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		steps.add_child(step_label)
	_setup_body.add_child(steps)
	_creator_scroll = ScrollContainer.new()
	_creator_scroll.name = "CreatorScroll"
	_creator_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_creator_scroll.custom_minimum_size.y = 220.0
	_creator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_creator_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_creator_scroll.follow_focus = true
	_setup_body.add_child(_creator_scroll)
	_creator = BoxContainer.new()
	_creator.custom_minimum_size.y = 360.0
	_creator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_creator.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_creator.add_theme_constant_override("separation", 12)
	_creator_scroll.add_child(_creator)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_label("Race", GOLD))
	_race_list = ItemList.new()
	_race_list.custom_minimum_size.y = 320.0
	_race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_race_list.item_selected.connect(_race_selected)
	left.add_child(_race_list)
	_creator.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_label("Class", GOLD))
	_caste_list = ItemList.new()
	_caste_list.custom_minimum_size.y = 320.0
	_caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_caste_list.item_selected.connect(_caste_selected)
	right.add_child(_caste_list)
	_creator.add_child(right)
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 180.0
	form.add_child(_label("Identity", GOLD))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Character name"
	form.add_child(_name_edit)
	_gender_option = OptionButton.new()
	_gender_option.add_item("Gender 1", 1)
	_gender_option.add_item("Gender 2", 2)
	form.add_child(_gender_option)
	form.add_child(_label("Appearance", GOLD))
	_portrait_option = OptionButton.new()
	_portrait_option.add_item("Portrait: Classic default", 0)
	_portrait_option.tooltip_text = "The package media catalog will provide additional portraits when available."
	_portrait_option.item_selected.connect(func(_index: int) -> void: _update_creator_review())
	form.add_child(_portrait_option)
	_combat_icon_option = OptionButton.new()
	_combat_icon_option.add_item("Combat icon: Classic default", 0)
	_combat_icon_option.tooltip_text = "The package media catalog will provide additional combat icons when available."
	_combat_icon_option.item_selected.connect(func(_index: int) -> void: _update_creator_review())
	form.add_child(_combat_icon_option)
	form.add_child(_label("Review", GOLD))
	_review_label = _add_label(form, "Choose a race and class to review Classic starting values.", MUTED)
	_review_label.custom_minimum_size.y = 44.0
	form.add_child(_label("Spells", GOLD))
	_spell_label = _add_label(form, "Spell eligibility and starting spells are finalized by Classic rules.", MUTED)
	_spell_label.custom_minimum_size.y = 44.0
	form.add_child(_label("Party", GOLD))
	_party_list = VBoxContainer.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(_party_list)
	_creator.add_child(form)
	_setup_message = _add_label(_setup_body, "Choose a race, a class, and a name.", MUTED)
	_setup_message.custom_minimum_size.y = 32.0
	_setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var action_bar := HBoxContainer.new()
	action_bar.alignment = BoxContainer.ALIGNMENT_END
	_add_character_button = Button.new()
	_add_character_button.text = "Add character"
	_add_character_button.pressed.connect(_add_character)
	action_bar.add_child(_add_character_button)
	_setup_import_button = Button.new()
	_setup_import_button.text = "Import from vault"
	_setup_import_button.pressed.connect(_show_vault_for_setup)
	action_bar.add_child(_setup_import_button)
	_setup_body.add_child(action_bar)
	_begin_button = Button.new()
	_begin_button.text = "Begin adventure"
	_begin_button.custom_minimum_size.y = 34.0
	_begin_button.disabled = true
	_begin_button.pressed.connect(_submit_party)
	_setup_body.add_child(_begin_button)
	_setup_body.move_child(_setup_message, 3)
	_setup_body.move_child(action_bar, 4)
	_setup_body.move_child(_begin_button, 5)


func _refresh_setup_options() -> void:
	if _view == null:
		return
	var summary := _view.campaign_summary
	if summary != null:
		var title_parts: Array[String] = [summary.title]
		if not summary.version.is_empty():
			title_parts.append("v%s" % summary.version)
		if not summary.author.is_empty():
			title_parts.append("by %s" % summary.author)
		_setup_campaign_label.text = " • ".join(title_parts)
		var restriction_text := summary.restriction_description.strip_edges()
		if restriction_text.is_empty():
			restriction_text = "No authored party restrictions."
		var limits := "Up to %d characters" % summary.maximum_party_size
		if summary.maximum_level > 0:
			limits += " • Maximum level %d" % summary.maximum_level
		_setup_restriction_label.text = "%s\n%s" % [restriction_text, limits]
	else:
		_setup_campaign_label.text = "Assemble your party"
		_setup_restriction_label.text = "No campaign metadata is available."
	_race_list.clear()
	for option: DefinitionOptionView in _view.race_options:
		_race_list.add_item(option.name)
		_race_list.set_item_metadata(_race_list.item_count - 1, option.id)
		_race_list.set_item_tooltip(_race_list.item_count - 1, option.description)
		_race_list.set_item_disabled(_race_list.item_count - 1, _view.campaign_summary != null and _view.campaign_summary.banned_races.has(option.id))
	_caste_list.clear()
	for option: DefinitionOptionView in _view.caste_options:
		_caste_list.add_item(option.name)
		_caste_list.set_item_metadata(_caste_list.item_count - 1, option.id)
		_caste_list.set_item_tooltip(_caste_list.item_count - 1, option.description)
		_caste_list.set_item_disabled(_caste_list.item_count - 1, _view.campaign_summary != null and _view.campaign_summary.banned_castes.has(option.id))
	if _race_list.item_count > 0 and (_selected_race_id.is_empty() or not _option_is_enabled(_race_list, _selected_race_id)):
		var first_race := _first_enabled_item(_race_list)
		if first_race >= 0:
			_race_list.select(first_race)
			_race_selected(first_race)
	else:
		_apply_caste_filter()
	if _caste_list.item_count > 0 and (_selected_caste_id.is_empty() or not _option_is_enabled(_caste_list, _selected_caste_id)):
		var first_caste := _first_enabled_item(_caste_list)
		if first_caste >= 0:
			_caste_list.select(first_caste)
			_caste_selected(first_caste)
	_refresh_party_list()
	var setup_count := _view.party_members.size()
	_apply_availability(_add_character_button, &"finalize_character")
	_apply_availability(_setup_import_button, &"import_vault_character")
	_apply_availability(_begin_button, &"begin_adventure")
	_begin_button.text = "Begin adventure (%d/%d)" % [setup_count, _maximum_party_size()]
	_update_creator_review()


func _race_selected(index: int) -> void:
	if index < 0 or _race_list.is_item_disabled(index):
		return
	_selected_race_id = String(_race_list.get_item_metadata(index))
	_apply_caste_filter()
	_setup_message.text = "Race selected. Classes unavailable to this race are disabled on the right."
	_update_creator_review()


func _caste_selected(index: int) -> void:
	if index < 0 or _caste_list.is_item_disabled(index):
		return
	_selected_caste_id = String(_caste_list.get_item_metadata(index))
	_setup_message.text = "Class selected. Review the character before adding them."
	_update_creator_review()


func _apply_caste_filter() -> void:
	if _view == null or _caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in _view.race_options:
		if option.id == _selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	for index: int in _caste_list.item_count:
		var caste_id := String(_caste_list.get_item_metadata(index))
		var restricted := _view.campaign_summary != null and _view.campaign_summary.banned_castes.has(caste_id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(caste_id)
		_caste_list.set_item_disabled(index, restricted or not compatible)
	if not _selected_caste_id.is_empty() and not _option_is_enabled(_caste_list, _selected_caste_id):
		_selected_caste_id = ""
		var first_caste := _first_enabled_item(_caste_list)
		if first_caste >= 0:
			_caste_list.select(first_caste)
			_caste_selected(first_caste)


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


func _add_character() -> void:
	if _selected_race_id.is_empty() or _selected_caste_id.is_empty():
		_setup_message.text = "Choose both a race and a class."
		return
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		name = "Adventurer %d" % (_view.party_members.size() + 1)
	if _view.party_members.size() >= _maximum_party_size():
		_setup_message.text = "This campaign allows no more than %d characters." % _maximum_party_size()
		return
	var portrait_id := "" if _portrait_option.get_selected_id() == 0 else str(_portrait_option.get_selected_id())
	var combat_icon_id := "" if _combat_icon_option.get_selected_id() == 0 else str(_combat_icon_option.get_selected_id())
	intent_submitted.emit(PlayerIntent.finalize_character(CharacterCreationSpec.new(name, _selected_race_id, _selected_caste_id, _gender_option.get_selected_id(), portrait_id, combat_icon_id)))
	_name_edit.clear()


func _refresh_party_list() -> void:
	_clear(_party_list)
	if _view != null:
		for character: CharacterView in _view.party_members:
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label := Label.new()
			label.text = "%d. %s" % [_party_list.get_child_count() + 1, character.name]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.modulate = Color("e0e2e5")
			row.add_child(label)
			var remove_button := Button.new()
			remove_button.text = "Remove"
			_apply_availability(remove_button, &"remove_party_member")
			remove_button.pressed.connect(_remove_setup_character.bind(character.id))
			row.add_child(remove_button)
			_party_list.add_child(row)


func _remove_setup_character(character_id: String) -> void:
	intent_submitted.emit(PlayerIntent.remove_party_member(character_id))


func _submit_party() -> void:
	if _view == null or _view.party_members.is_empty():
		return
	intent_submitted.emit(PlayerIntent.begin_adventure())


func _maximum_party_size() -> int:
	if _view == null or _view.campaign_summary == null:
		return 6
	return clampi(_view.campaign_summary.maximum_party_size, 1, 6)


func _update_creator_review() -> void:
	if _review_label == null:
		return
	var race_name := _option_name(_race_list, _selected_race_id)
	var caste_name := _option_name(_caste_list, _selected_caste_id)
	if race_name.is_empty() or caste_name.is_empty():
		_review_label.text = "Choose a race and class to review Classic starting values."
		_spell_label.text = "Spell eligibility and starting spells are finalized by Classic rules."
		return
	_review_label.text = "%s %s\nName: %s" % [race_name, caste_name, _name_edit.text.strip_edges() if _name_edit != null and not _name_edit.text.strip_edges().is_empty() else "Adventurer"]
	var portrait_label := _portrait_option.get_item_text(_portrait_option.selected) if _portrait_option != null and _portrait_option.selected >= 0 else "Classic default"
	var icon_label := _combat_icon_option.get_item_text(_combat_icon_option.selected) if _combat_icon_option != null and _combat_icon_option.selected >= 0 else "Classic default"
	_review_label.text += "\n%s • %s" % [portrait_label, icon_label]
	_spell_label.text = "Spells: Classic caste eligibility will be checked when the character is created."


func _option_name(list: ItemList, option_id: String) -> String:
	if list == null or option_id.is_empty():
		return ""
	for index: int in list.item_count:
		if String(list.get_item_metadata(index)) == option_id:
			return list.get_item_text(index)
	return ""


func _campaign_pressed(campaign: PackageDiscoveryResult) -> void:
	if not campaign.ready:
		return
	start_requested.emit(campaign.path, int(_seed.value) if _seed != null else 1)


func _open_typed_path() -> void:
	var path := _package_path.text.strip_edges()
	if not path.is_empty():
		start_requested.emit(path, int(_seed.value))


func _render_screen() -> void:
	_mount_workspace(_screen_id)
	if _body == null:
		return
	_clear(_body)
	_content_parent = _body
	_body_frame.visible = not _campaign_overlay.visible and not _setup_overlay.visible and _screen_id != &"exploration"
	if _screen_id == &"exploration":
		return
	if _view == null or not _view.session_started:
		_add_label(_body, "No active session. Choose a validated campaign to begin.", MUTED)
		return
	match _screen_id:
		&"exploration":
			_add_card("Exploration", "The map presenter occupies the central Classic viewport. Use the command rail and textbox overlay for player-facing actions.", "Day %d • %02d:00" % [_view.realmz_day, _view.realmz_hour])
		&"character":
			_render_characters()
		&"vault":
			_render_vault()
		&"inventory":
			_render_inventory()
		&"spells":
			_render_spells()
		&"combat":
			_render_combat()
		&"services":
			_render_services()
		&"journal":
			_render_journal()
		&"system":
			_render_system()
	_assign_focus_keys(_body)
	call_deferred("_restore_focus")


func _render_characters() -> void:
	if _view.party_members.is_empty():
		_add_empty_state("No characters", "Begin a campaign or import an eligible vault character.")
		return
	for character: CharacterView in _view.party_members:
		var detail := "HP %d/%d • SP %d/%d • Armor %d • Move %d/%d\nAge %d • %s • Level %d\nBrawn %d • Knowledge %d • Judgment %d • Agility %d • Vitality %d • Luck %d\nTo hit %d • Dodge %d • Missile %d • Hand to hand %d • Magic resistance %d\nLoad %d/%d • Experience %d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor, character.movement, character.maximum_movement, character.age_years, character.age_group_name, character.level, character.brawn, character.knowledge, character.judgment, character.agility, character.vitality, character.luck, character.to_hit, character.dodge, character.missile, character.hand_to_hand, character.magic_resistance, character.carried_load, character.maximum_load, character.experience]
		_add_card(character.name, "Level %d • %s / %s" % [character.level, character.race_name, character.caste_name], detail)
		var conditions: Array[String] = []
		for index: int in character.condition_values.size():
			if character.condition_values[index] != 0:
				conditions.append("%d:%d" % [index, character.condition_values[index]])
		_add_label(_body, "Conditions: %s" % ["None" if conditions.is_empty() else ", ".join(conditions)], MUTED, 13)


func _render_vault() -> void:
	if _vault_records.is_empty():
		_add_empty_state("Character vault is empty", "No immutable .r2char revisions are installed. Vault publishing is not implemented in this gameplay slice.")
		return
	for record: CharacterVaultRecord in _vault_records:
		var eligibility := "Revision %s • %s" % [record.revision_hash.left(12), record.source_campaign_id]
		_add_card(record.state.name, eligibility, "Level %d • %s / %s" % [record.state.level, record.state.race_id, record.state.caste_id])
		var import_button := Button.new()
		import_button.text = "Import %s" % record.state.name
		import_button.tooltip_text = eligibility
		_apply_availability(import_button, &"import_vault_character")
		import_button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.import_vault_character(record.character_id, record.revision_hash)))
		_mark_focus(import_button, "vault:%s" % record.revision_hash)
		_body.add_child(import_button)


func _show_vault_for_setup() -> void:
	_setup_overlay.visible = false
	_campaign_overlay.visible = false
	_screen_id = &"vault"
	_render_screen()


func _render_inventory() -> void:
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	var search := LineEdit.new()
	search.placeholder_text = "Filter visible item names…"
	search.text = _inventory_query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_submitted.connect(func(value: String) -> void:
		_inventory_query = value.strip_edges()
		_render_screen()
	)
	filter_row.add_child(search)
	var clear_filter := Button.new()
	clear_filter.text = "Clear"
	clear_filter.disabled = _inventory_query.is_empty()
	clear_filter.pressed.connect(func() -> void:
		_inventory_query = ""
		_render_screen()
	)
	filter_row.add_child(clear_filter)
	_body.add_child(filter_row)
	var categories := HFlowContainer.new()
	categories.add_theme_constant_override("h_separation", 4)
	categories.add_theme_constant_override("v_separation", 4)
	for category: Dictionary in [
		{"asset": &"inventory.category.weapons", "label": "Weapons"},
		{"asset": &"inventory.category.armor", "label": "Armor"},
		{"asset": &"inventory.category.limb_armor", "label": "Limb armor"},
		{"asset": &"inventory.category.magic", "label": "Magic"},
		{"asset": &"inventory.category.supplies", "label": "Supplies"},
	]:
		var category_button := _bitmap_button(StringName(category["asset"]), String(category["label"]))
		category_button.disabled = true
		category_button.tooltip_text = "%s filtering is unavailable until the detached view supplies the canonical Classic category mapping." % category["label"]
		categories.add_child(category_button)
	_body.add_child(categories)
	var any_items := false
	for character: CharacterView in _view.party_members:
		_add_section_heading(character.name, "%d/%d load" % [character.carried_load, character.maximum_load])
		for item: ItemView in character.items:
			if not _inventory_query.is_empty() and item.name.findn(_inventory_query) < 0:
				continue
			any_items = true
			_add_content_card(item.icon_resource_type, item.icon_id, item.name, "%s • %s" % [character.name, "Identified" if item.identified else "Unidentified"], "%s\nCharges %d • Weight %d • Value %s" % [item.description, item.charges, item.weight, str(item.value) if item.identified else "Unknown"])
			var actions := HFlowContainer.new()
			actions.add_theme_constant_override("h_separation", 5)
			actions.add_theme_constant_override("v_separation", 5)
			_add_disabled_action(actions, "Unequip" if item.equipped else "Equip", &"unequip_item" if item.equipped else &"equip_item")
			_add_bitmap_intent_action(actions, &"inventory.action.use", "Use", &"use_item", PlayerIntent.use_item(item.instance_id))
			_add_bitmap_intent_action(actions, &"inventory.action.identify", "Identify", &"identify_item", PlayerIntent.item_action(PlayerIntent.Kind.IDENTIFY_ITEM, item.instance_id, character.id))
			_add_bitmap_intent_action(actions, &"inventory.action.join", "Join", &"join_item", PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, item.instance_id, character.id))
			_add_bitmap_intent_action(actions, &"inventory.action.split", "Split", &"split_item", PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, item.instance_id, character.id))
			_add_bitmap_intent_action(actions, &"inventory.action.drop", "Drop", &"drop_item", PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, item.instance_id, character.id))
			_add_disabled_action(actions, "Trade", &"trade_item")
			_add_disabled_action(actions, "Store", &"store_item")
			_body.add_child(actions)
	if _view.party_members.is_empty():
		_add_empty_state("No party inventory", "The party has no characters.")
	elif not any_items:
		_add_empty_state("Inventory is empty", "No character is carrying an item.")


func _render_spells() -> void:
	var any_spells := false
	for character: CharacterView in _view.party_members:
		_add_section_heading(character.name, "SP %d/%d" % [character.spell_points, character.maximum_spell_points])
		for spell: SpellView in character.spells:
			any_spells = true
			var context := "Combat%s • Camp%s" % [" yes" if spell.castable_in_combat else " no", " yes" if spell.castable_in_camp else " no"]
			_add_content_card(spell.icon_resource_type, spell.icon_id, spell.name, "%s • Cost %d" % [character.name, spell.cost], "%s\nRange %d–%d • Duration %d–%d • %s" % [spell.description, spell.range_min, spell.range_max, spell.duration_min, spell.duration_max, context])
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 5)
			row.add_theme_constant_override("v_separation", 5)
			_add_disabled_action(row, "Choose power", &"select_spell_power")
			_add_disabled_action(row, "Choose target", &"select_spell_target")
			_add_bitmap_intent_action(row, &"spells.action.cast", "Cast", &"cast_spell", PlayerIntent.cast_spell(spell.id, character.id))
			var abort := _bitmap_button(&"spells.action.abort", "Abort")
			abort.tooltip_text = "Return to exploration without casting."
			abort.command_requested.connect(func(_command_id: StringName) -> void: open_screen(&"exploration"))
			row.add_child(abort)
			_body.add_child(row)
	if _view.party_members.is_empty():
		_add_empty_state("No spellbooks", "The party has no characters.")
	elif not any_spells:
		_add_empty_state("No known spells", "No party member currently knows a spell.")


func _render_combat() -> void:
	if _view.combat_view == null:
		_add_empty_state("No battle is active", "Battlefield positions and tactical actions appear here when combat begins.")
		return
	var combat := _view.combat_view
	_add_card("Battle %s" % combat.battle_id, "Round %d • Active %s" % [combat.round_number, combat.active_actor_id], "Outcome: %s" % ["In progress" if combat.outcome == &"" else String(combat.outcome)])
	_add_section_heading("Turn order", " → ".join(combat.turn_order))
	for monster: MonsterView in combat.monsters:
		_add_content_card(monster.icon_resource_type, monster.icon_id, monster.name, "Enemy" if monster.traitor else "Ally", "HP %d/%d" % [monster.current_health, monster.maximum_health])
	var legal := HBoxContainer.new()
	for action: StringName in combat.legal_actions:
		var button := Button.new()
		button.text = String(action).capitalize()
		_apply_availability(button, &"choose_combat_action")
		legal.add_child(button)
	_body.add_child(legal)
	var enabled_moves := combat.movement_options.filter(func(option: CombatMoveOptionView) -> bool: return option.enabled).size()
	_add_card("Tactical movement", "%d of %d adjacent steps available" % [enabled_moves, combat.movement_options.size()], "Choose a source-probed step through the active Battle interaction. Withdrawal-producing steps remain disabled until their reaction sequence is implemented.")


func _render_services() -> void:
	if _view.services.is_empty():
		_add_empty_state("No active service", "Shops, temples, banks, storage, and treasure open here only when the session supplies a typed service interaction.")
		for title: String in ["Shop", "Temple", "Bank", "Storage", "Treasure"]:
			_add_card(title, "Unavailable at this location", "No service facts were supplied; Realmz 2 does not infer availability from the map or scenario name.")
		return
	for service: ServiceView in _view.services:
		_add_card(service.title, String(service.service_kind).replace("_", " ").capitalize(), "Available actions: %s" % [", ".join(service.actions)])
		for action: StringName in service.actions:
			var button := Button.new()
			button.text = String(action).capitalize()
			var reason := String(service.disabled_reasons.get(action, ""))
			button.disabled = not reason.is_empty()
			button.tooltip_text = reason
			_body.add_child(button)


func _render_journal() -> void:
	_add_section_heading("Acquired maps", "%d available" % _view.party_summary.acquired_map_ids.size() if _view.party_summary != null else "0 available")
	if _view.party_summary == null or _view.party_summary.acquired_map_ids.is_empty():
		_add_empty_state("No acquired maps", "Maps appear only after the session records their acquisition.")
	else:
		for map_id: String in _view.party_summary.acquired_map_ids:
			_add_card(map_id, "Acquired map", "Map viewing is not implemented in the current gameplay slice.")
	_add_section_heading("Journal entries", "%d entries" % _view.journal_entries.size())
	if _view.journal_entries.is_empty():
		_add_empty_state("The journal is empty", "No journal records were supplied by the current session.")
	else:
		for entry: JournalEntryView in _view.journal_entries:
			_add_card(entry.title, "Day %d • %s" % [entry.day, entry.map_id], entry.text)
	_add_disabled_action(_body, "Open Classic journal", &"open_journal")
	_add_disabled_action(_body, "Open acquired maps", &"open_maps")


func _render_system() -> void:
	_add_card("Current campaign", _view.campaign_summary.title if _view.campaign_summary != null else _view.campaign_id, "Package %s\nRules %s" % [_view.campaign_summary.package_hash if _view.campaign_summary != null else "Unavailable", _view.rules_version])
	_add_section_heading("Save and restore", "Committed session boundaries only")
	var save_row := HBoxContainer.new()
	var save := Button.new()
	save.text = "Quick save"
	save.pressed.connect(func() -> void: system_action_requested.emit(&"save", "quick"))
	save_row.add_child(save)
	var load := Button.new()
	load.text = "Quick load"
	load.pressed.connect(func() -> void: system_action_requested.emit(&"load", "quick"))
	save_row.add_child(load)
	var campaigns := Button.new()
	campaigns.text = "Campaign library"
	campaigns.pressed.connect(func() -> void: system_action_requested.emit(&"campaigns", null))
	save_row.add_child(campaigns)
	_body.add_child(save_row)
	_add_section_heading("Display", "Interface scale and text size are independent")
	var ui_scale := OptionButton.new()
	for entry: Dictionary in [{"label": "UI scale: Auto", "id": PresentationSettings.UI_SCALE_AUTO}, {"label": "UI scale: 100%", "id": PresentationSettings.UI_SCALE_100}, {"label": "UI scale: 125%", "id": PresentationSettings.UI_SCALE_125}, {"label": "UI scale: 150%", "id": PresentationSettings.UI_SCALE_150}]:
		ui_scale.add_item(entry["label"])
		ui_scale.set_item_metadata(ui_scale.item_count - 1, entry["id"])
		if entry["id"] == _settings.ui_scale_mode:
			ui_scale.select(ui_scale.item_count - 1)
	ui_scale.item_selected.connect(func(index: int) -> void: presentation_setting_changed.emit(&"ui_scale_mode", String(ui_scale.get_item_metadata(index))))
	_body.add_child(ui_scale)
	var text_scale := HSlider.new()
	text_scale.min_value = 0.8
	text_scale.max_value = 1.5
	text_scale.step = 0.1
	text_scale.value = _settings.text_scale
	text_scale.tooltip_text = "Text scale %d%%" % int(round(_settings.text_scale * 100.0))
	text_scale.value_changed.connect(func(value: float) -> void: presentation_setting_changed.emit(&"text_scale", value))
	_body.add_child(text_scale)
	var window_mode := OptionButton.new()
	window_mode.add_item("Windowed")
	window_mode.set_item_metadata(0, PresentationSettings.WINDOWED)
	window_mode.add_item("Borderless fullscreen")
	window_mode.set_item_metadata(1, PresentationSettings.BORDERLESS_FULLSCREEN)
	window_mode.select(1 if _settings.window_mode == PresentationSettings.BORDERLESS_FULLSCREEN else 0)
	window_mode.item_selected.connect(func(index: int) -> void: presentation_setting_changed.emit(&"window_mode", String(window_mode.get_item_metadata(index))))
	_body.add_child(window_mode)
	_add_section_heading("Accessibility and presentation", "These preferences never change simulation")
	_add_setting_toggle("Reduced motion", _settings.reduced_motion, &"reduced_motion")
	_add_setting_toggle("Use topology-derived 3D dungeons", _settings.dungeon_3d, &"dungeon_3d")
	_add_setting_toggle("Show topology diagnostics", _settings.topology_debug, &"topology_debug")
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = _settings.master_volume
	volume.tooltip_text = "Master volume"
	volume.value_changed.connect(func(value: float) -> void: presentation_setting_changed.emit(&"master_volume", value))
	_body.add_child(volume)


func _add_card(title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	_content_parent.add_child(panel)


func _add_content_card(resource_type: String, icon_id: int, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(_content_icon(resource_type, icon_id))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	row.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	_content_parent.add_child(panel)


func _content_icon(resource_type: String, resource_id: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	var asset: PackageMediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	if asset != null:
		var bytes := _media.read_bytes(asset)
		var image := Image.new()
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png":
				error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				error = image.load_jpg_from_buffer(bytes)
			"webp":
				error = image.load_webp_from_buffer(bytes)
		if error == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			texture.tooltip_text = asset.label
			frame.add_child(texture)
			return frame
	var fallback := Label.new()
	fallback.text = "◈\n%d" % resource_id if resource_id != 0 else "◈"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	fallback.tooltip_text = "Package media unavailable for %s %d." % [resource_type, resource_id] if resource_id != 0 else "No package media identity was supplied."
	frame.add_child(fallback)
	return frame


func _add_section_heading(title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	_body.add_child(row)


func _add_empty_state(title: String, detail: String) -> void:
	_add_card(title, detail, "Realmz 2 shows only facts supplied by the detached session view.")


func _add_disabled_action(parent: Container, label: String, action_id: StringName) -> Button:
	var button := Button.new()
	button.text = label
	_apply_availability(button, action_id)
	parent.add_child(button)
	return button


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.configure({
		"id": asset_id,
		"asset_id": asset_id,
		"tooltip": label,
		"accelerator": "",
	}, 1)
	return button


func _add_bitmap_intent_action(parent: Container, asset_id: StringName, label: String, action_id: StringName, intent: PlayerIntent) -> ClassicBitmapButton:
	var button := _bitmap_button(asset_id, label)
	_apply_availability(button, action_id)
	if not button.disabled:
		button.command_requested.connect(func(_command_id: StringName) -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _apply_availability(button: BaseButton, action_id: StringName) -> void:
	var availability := _view.availability(action_id) if _view != null else ActionAvailabilityView.new(action_id, false, "No active session.")
	button.disabled = not availability.enabled
	button.tooltip_text = availability.reason if not availability.enabled else ""


func _add_setting_toggle(label: String, enabled: bool, setting_id: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.text = label
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: presentation_setting_changed.emit(setting_id, value))
	_body.add_child(toggle)


func _screen_definition(screen_id: StringName) -> Dictionary:
	return UiRouteCatalog.route(screen_id)


func _display_screen_label(screen_id: StringName) -> String:
	var definition := _screen_definition(screen_id)
	if not definition.is_empty():
		return String(definition["label"])
	return "Realmz"


func _mark_focus(control: Control, key: String) -> void:
	control.set_meta("focus_key", key)


func _assign_focus_keys(parent: Node, next_index: int = 0) -> int:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			if not child.has_meta("focus_key"):
				child.set_meta("focus_key", "%s:%d" % [_screen_id, next_index])
			next_index += 1
		next_index = _assign_focus_keys(child, next_index)
	return next_index


func _store_focus() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner) and owner.has_meta("focus_key"):
		_focus_keys[_screen_id] = String(owner.get_meta("focus_key"))


func _restore_focus() -> void:
	var wanted := String(_focus_keys.get(_screen_id, ""))
	if not wanted.is_empty():
		var focus_match := _find_focus_key(_body, wanted)
		if focus_match != null:
			focus_match.grab_focus()
			return
	_focus_first(_body)


func _find_focus_key(parent: Node, key: String) -> Control:
	for child: Node in parent.get_children():
		if child is Control and child.has_meta("focus_key") and String(child.get_meta("focus_key")) == key:
			return child
		var nested := _find_focus_key(child, key)
		if nested != null:
			return nested
	return null


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null and parent.is_ancestor_of(owner):
			return


func _display_name(campaign: PackageDiscoveryResult) -> String:
	return campaign.campaign_id.replace("-", " ").capitalize()


func _campaign_precedes(left: PackageDiscoveryResult, right: PackageDiscoveryResult) -> bool:
	if left.ready != right.ready:
		return left.ready
	return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _settings.text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
