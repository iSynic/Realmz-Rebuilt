class_name ClassicShellPresenter
extends Control

signal start_package_requested(path: String, seed: int)
signal refresh_campaigns_requested
signal intent_submitted(intent: PlayerIntent)
signal save_requested(slot_id: String)
signal load_requested(slot_id: String)
signal topology_debug_changed(enabled: bool)
signal dungeon_3d_changed(enabled: bool)
signal master_volume_changed(value: float)
signal text_scale_changed(value: float)
signal reduced_motion_changed(enabled: bool)

const DEV_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const GOLD: Color = Color("d5b45d")
const INK: Color = Color("17191d")
const PANEL: Color = Color("272b31")
const PANEL_DARK: Color = Color("1d2025")

var _view: GameView
var _status: Label
var _clock: Label
var _gold: Label
var _party_list: VBoxContainer
var _event_log: RichTextLabel
var _picture: TextureRect
var _picture_caption: Label
var _simulation_buttons: Array[Button] = []
var _utility_buttons: Array[Button] = []
var _campaign_overlay: Control
var _campaign_list: VBoxContainer
var _package_path: LineEdit
var _seed: SpinBox
var _modal_overlay: Control
var _modal_title: Label
var _modal_body: VBoxContainer
var _slot_name: LineEdit
var _file_dialog: FileDialog
var _party_rows: VBoxContainer
var _party_setup_prompted: bool = false
var _settings: PresentationSettings = PresentationSettings.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	_build_campaign_overlay()
	_build_modal_overlay()
	_build_file_dialog()
	show_campaign_selection()


func present(game_view: GameView) -> void:
	_view = game_view
	if game_view == null or not game_view.session_started:
		_clock.text = "No active session"
		_gold.text = "Gold —"
		_rebuild_party_list()
		_set_commands_enabled(false, false)
		return
	_campaign_overlay.visible = false
	_clock.text = "Day %d • %02d:00" % [game_view.realmz_day, game_view.realmz_hour]
	_gold.text = "Gold %d" % game_view.pooled_gold
	_rebuild_party_list()
	_set_commands_enabled(game_view.pending_interaction == null and not game_view.party_setup_available, true)
	if game_view.party_setup_available and not _party_setup_prompted:
		_party_setup_prompted = true
		_show_party_creation()


func present_step(step: SessionStep) -> void:
	if step == null:
		return
	if step.state == SessionStep.State.FAILED:
		set_status("Action failed • %s" % step.error_message, true)
		_append_log("[color=#df7b78]Error:[/color] %s" % step.error_message)
		return
	for event: DomainEvent in step.events:
		_present_event(event)


func present_media_events(events: Array[DomainEvent], media: PackageMediaCatalog) -> void:
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind != &"picture_requested":
			continue
		var picture_id := int(event.payload.get("pictureId", 0))
		var asset := media.picture_by_resource_id(picture_id)
		if asset == null:
			continue
		var bytes := media.read_bytes(asset)
		var image := _decode_image(asset, bytes)
		if image == null:
			continue
		_picture.texture = ImageTexture.create_from_image(image)
		_picture_caption.text = asset.label


func apply_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_settings = settings
	var shell_theme := Theme.new()
	shell_theme.default_font_size = int(round(15.0 * settings.text_scale))
	theme = shell_theme


func accepts_exploration_input() -> bool:
	return not _campaign_overlay.visible and not _modal_overlay.visible and not _file_dialog.visible


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.modulate = Color("e88782") if is_error else Color("d8d9d5")


func set_campaigns(campaigns: Array[PackageDiscoveryResult]) -> void:
	_clear_children(_campaign_list)
	if campaigns.is_empty():
		var empty := Label.new()
		empty.text = "No installed packages. Open a Providence .realmz2 export."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_campaign_list.add_child(empty)
		return
	for campaign: PackageDiscoveryResult in campaigns:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 56)
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if campaign.ready:
			details.text = "%s\nReady • %s" % [_campaign_display_name(campaign.campaign_id), campaign.rules_version]
		else:
			details.text = "Rejected package\n%s" % campaign.error_message
		details.tooltip_text = campaign.path
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(details)
		var play := Button.new()
		play.text = "Play" if campaign.ready else "Details"
		play.disabled = not campaign.ready
		play.pressed.connect(_request_start.bind(campaign.path))
		row.add_child(play)
		_campaign_list.add_child(row)


func show_campaign_selection() -> void:
	_party_setup_prompted = false
	_campaign_overlay.visible = true
	_modal_overlay.visible = false
	_package_path.text = DEV_FIXTURE_PATH if OS.is_debug_build() else ""
	set_status("Choose a validated Realmz 2.0 package")


func _build_shell() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var top := _panel(Rect2(0, 0, 960, 58), PANEL_DARK)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 20)
	top.add_child(top_row)
	var title := Label.new()
	title.text = "REALMZ"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	top_row.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(_status)
	_clock = Label.new()
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(_clock)
	_gold = Label.new()
	_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold.add_theme_color_override("font_color", GOLD)
	top_row.add_child(_gold)

	var party_panel := _panel(Rect2(0, 58, 205, 542), PANEL)
	var party_column := VBoxContainer.new()
	party_panel.add_child(party_column)
	party_column.add_child(_section_title("Party"))
	_party_list = VBoxContainer.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_column.add_child(_party_list)

	var event_panel := _panel(Rect2(735, 58, 225, 542), PANEL)
	var event_column := VBoxContainer.new()
	event_panel.add_child(event_column)
	event_column.add_child(_section_title("Chronicle"))
	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(0, 84)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	event_column.add_child(_picture)
	_picture_caption = Label.new()
	_picture_caption.text = "No picture"
	_picture_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picture_caption.add_theme_color_override("font_color", Color("8f949b"))
	event_column.add_child(_picture_caption)
	_event_log = RichTextLabel.new()
	_event_log.bbcode_enabled = true
	_event_log.fit_content = false
	_event_log.scroll_active = true
	_event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_column.add_child(_event_log)

	var commands := _panel(Rect2(205, 510, 530, 90), PANEL_DARK)
	var command_column := VBoxContainer.new()
	commands.add_child(command_column)
	var first_row := HBoxContainer.new()
	var second_row := HBoxContainer.new()
	command_column.add_child(first_row)
	command_column.add_child(second_row)
	_add_command(first_row, "Search", func() -> void: intent_submitted.emit(PlayerIntent.new(PlayerIntent.Kind.SEARCH)), true)
	_add_command(first_row, "Camp", func() -> void: intent_submitted.emit(PlayerIntent.camp()), true)
	_add_command(first_row, "Character", _show_first_character)
	_add_command(first_row, "Inventory", _show_inventory)
	_add_command(first_row, "Spells", _show_spells)
	_add_command(second_row, "Save", _show_save)
	_add_command(second_row, "Load", _show_load)
	_add_command(second_row, "Settings", _show_settings)
	_add_command(second_row, "Campaigns", show_campaign_selection)


func _build_campaign_overlay() -> void:
	_campaign_overlay = Control.new()
	_campaign_overlay.z_index = 50
	_campaign_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_campaign_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_campaign_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.05, 0.06, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_campaign_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(180, 75)
	panel.size = Vector2(600, 450)
	_campaign_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := _section_title("Choose a Realmz campaign")
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Providence compiles immutable .realmz2 packages. Packages are fully validated before play."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle)
	var campaign_scroll := ScrollContainer.new()
	campaign_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(campaign_scroll)
	_campaign_list = VBoxContainer.new()
	_campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_list.add_theme_constant_override("separation", 8)
	campaign_scroll.add_child(_campaign_list)
	var path_row := HBoxContainer.new()
	_package_path = LineEdit.new()
	_package_path.placeholder_text = "Path to .realmz2 package"
	_package_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_package_path)
	var browse := Button.new()
	browse.text = "Open…"
	browse.pressed.connect(func() -> void: _file_dialog.popup_centered_ratio(0.75))
	path_row.add_child(browse)
	column.add_child(path_row)
	var launch_row := HBoxContainer.new()
	_seed = SpinBox.new()
	_seed.min_value = 1
	_seed.max_value = 2147483646
	_seed.value = 1
	_seed.prefix = "Seed "
	launch_row.add_child(_seed)
	var launch := Button.new()
	launch.text = "Begin campaign"
	launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch.pressed.connect(func() -> void: _request_start(_package_path.text))
	launch_row.add_child(launch)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(func() -> void: refresh_campaigns_requested.emit())
	launch_row.add_child(refresh)
	column.add_child(launch_row)


func _build_modal_overlay() -> void:
	_modal_overlay = Control.new()
	_modal_overlay.z_index = 50
	_modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_overlay.visible = false
	add_child(_modal_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.03, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(150, 70)
	panel.size = Vector2(660, 470)
	_modal_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header := HBoxContainer.new()
	_modal_title = _section_title("Realmz")
	_modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_modal_title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_modal)
	header.add_child(close)
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_modal_body = VBoxContainer.new()
	_modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_modal_body)


func _build_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.realmz2 ; Realmz Remake 2.0 Package"])
	_file_dialog.file_selected.connect(func(path: String) -> void: _package_path.text = path)
	add_child(_file_dialog)


func _panel(rect: Rect2, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("3b4048")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _add_command(parent: HBoxContainer, label: String, callback: Callable, mutates_simulation: bool = false) -> void:
	var button := Button.new()
	button.text = label
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 30
	button.pressed.connect(callback)
	parent.add_child(button)
	if mutates_simulation:
		_simulation_buttons.append(button)
	else:
		_utility_buttons.append(button)


func _set_commands_enabled(simulation_enabled: bool, session_started: bool) -> void:
	for button: Button in _simulation_buttons:
		button.disabled = not simulation_enabled
	for button: Button in _utility_buttons:
		button.disabled = not session_started


func _rebuild_party_list() -> void:
	_clear_children(_party_list)
	if _view == null or not _view.session_started:
		return
	for character: CharacterView in _view.party_members:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s\nHP %d/%d • SP %d/%d" % [character.name, character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points]
		button.tooltip_text = "Level %d • %s" % [character.level, character.caste_id]
		button.pressed.connect(_show_character.bind(character))
		_party_list.add_child(button)


func _show_first_character() -> void:
	if _view != null and not _view.party_members.is_empty():
		_show_character(_view.party_members[0])


func _show_character(character: CharacterView) -> void:
	_open_modal(character.name)
	_add_text("Level %d • XP %d" % [character.level, character.experience])
	_add_text("Race %s • Caste %s" % [character.race_id, character.caste_id])
	_add_text("Brawn %d   Knowledge %d   Judgment %d" % [character.brawn, character.knowledge, character.judgment])
	_add_text("Agility %d   Vitality %d   Luck %d" % [character.agility, character.vitality, character.luck])
	_add_text("Armor %d • Movement %d/%d • Load %d/%d" % [character.armor, character.movement, character.maximum_movement, character.carried_load, character.maximum_load])


func _show_inventory() -> void:
	_open_modal("Inventory")
	if _view == null:
		return
	var any := false
	for character: CharacterView in _view.party_members:
		_modal_body.add_child(_section_title(character.name))
		for item: ItemView in character.items:
			any = true
			var row := HBoxContainer.new()
			var text := Label.new()
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.text = "%s%s • charges %d • weight %d" % [item.name, " [equipped]" if item.equipped else "", item.charges, item.weight]
			row.add_child(text)
			var use := Button.new()
			use.text = "Use"
			use.disabled = not item.usable or _view.pending_interaction != null
			use.pressed.connect(_use_item.bind(item.instance_id))
			row.add_child(use)
			_modal_body.add_child(row)
	if not any:
		_add_text("The party carries no items.")


func _show_spells() -> void:
	_open_modal("Spells")
	if _view == null:
		return
	var any := false
	for character: CharacterView in _view.party_members:
		if character.spells.is_empty():
			continue
		_modal_body.add_child(_section_title(character.name))
		for spell: SpellView in character.spells:
			any = true
			var row := HBoxContainer.new()
			var text := Label.new()
			text.text = "%s • cost %d" % [spell.name, spell.cost]
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
			var cast := Button.new()
			cast.text = "Cast"
			cast.disabled = _view.combat_view == null or _view.combat_view.monsters.is_empty()
			cast.pressed.connect(_cast_spell.bind(spell.id, character.id))
			row.add_child(cast)
			_modal_body.add_child(row)
	if not any:
		_add_text("No party member currently knows a spell.")


func _show_save() -> void:
	_show_slot_dialog("Save game", true)


func _show_load() -> void:
	_show_slot_dialog("Load game", false)


func _show_slot_dialog(title: String, saving: bool) -> void:
	_open_modal(title)
	_slot_name = LineEdit.new()
	_slot_name.text = "quick"
	_slot_name.placeholder_text = "Save slot"
	_modal_body.add_child(_slot_name)
	var action := Button.new()
	action.text = "Save" if saving else "Load"
	action.pressed.connect(_submit_slot.bind(saving))
	_modal_body.add_child(action)


func _show_settings() -> void:
	_open_modal("Settings")
	var debug := CheckButton.new()
	debug.text = "Show topology movement / LOS / random-region facts"
	debug.button_pressed = _settings.topology_debug
	debug.toggled.connect(func(enabled: bool) -> void: topology_debug_changed.emit(enabled))
	_modal_body.add_child(debug)
	var dungeon_3d := CheckButton.new()
	dungeon_3d.text = "Use topology-derived 3D view in dungeons"
	dungeon_3d.button_pressed = _settings.dungeon_3d
	dungeon_3d.toggled.connect(func(enabled: bool) -> void: dungeon_3d_changed.emit(enabled))
	_modal_body.add_child(dungeon_3d)
	var volume_label := Label.new()
	volume_label.text = "Master volume"
	_modal_body.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.05
	volume.value = _settings.master_volume
	volume.value_changed.connect(func(value: float) -> void: master_volume_changed.emit(value))
	_modal_body.add_child(volume)
	var scale_label := Label.new()
	scale_label.text = "Text scale"
	_modal_body.add_child(scale_label)
	var text_scale_slider := HSlider.new()
	text_scale_slider.min_value = 0.8
	text_scale_slider.max_value = 1.5
	text_scale_slider.step = 0.1
	text_scale_slider.value = _settings.text_scale
	text_scale_slider.value_changed.connect(func(value: float) -> void: text_scale_changed.emit(value))
	_modal_body.add_child(text_scale_slider)
	var reduced := CheckButton.new()
	reduced.text = "Reduce cosmetic motion"
	reduced.button_pressed = _settings.reduced_motion
	reduced.toggled.connect(func(enabled: bool) -> void: reduced_motion_changed.emit(enabled))
	_modal_body.add_child(reduced)
	_add_text("Accessibility and presentation settings never alter Realmz rules.")


func _show_party_creation() -> void:
	_open_modal("Create your party")
	var help := Label.new()
	help.text = "Create one to six adventurers. Attributes, stamina, spell energy, and starting equipment are rolled by the deterministic Realmz rules."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body.add_child(help)
	_party_rows = VBoxContainer.new()
	_modal_body.add_child(_party_rows)
	_add_party_row()
	var controls := HBoxContainer.new()
	var add := Button.new()
	add.text = "Add adventurer"
	add.pressed.connect(_add_party_row)
	controls.add_child(add)
	var begin := Button.new()
	begin.text = "Begin adventure"
	begin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	begin.pressed.connect(_submit_party)
	controls.add_child(begin)
	_modal_body.add_child(controls)


func _add_party_row() -> void:
	if _party_rows.get_child_count() >= 6 or _view == null or _view.race_options.is_empty() or _view.caste_options.is_empty():
		return
	var row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.text = "Adventurer %d" % (_party_rows.get_child_count() + 1)
	name_edit.custom_minimum_size.x = 150
	row.add_child(name_edit)
	var race := OptionButton.new()
	for option: DefinitionOptionView in _view.race_options:
		race.add_item(option.name)
		race.set_item_metadata(race.item_count - 1, option.id)
	row.add_child(race)
	var caste := OptionButton.new()
	for option: DefinitionOptionView in _view.caste_options:
		caste.add_item(option.name)
		caste.set_item_metadata(caste.item_count - 1, option.id)
	row.add_child(caste)
	var gender := OptionButton.new()
	gender.add_item("Male", 1)
	gender.add_item("Female", 2)
	row.add_child(gender)
	var remove := Button.new()
	remove.text = "−"
	remove.pressed.connect(_remove_party_row.bind(row))
	row.add_child(remove)
	row.set_meta("name", name_edit)
	row.set_meta("race", race)
	row.set_meta("caste", caste)
	row.set_meta("gender", gender)
	_party_rows.add_child(row)


func _submit_party() -> void:
	var specs: Array[CharacterCreationSpec] = []
	for child: Node in _party_rows.get_children():
		var row := child as HBoxContainer
		var name_edit := row.get_meta("name") as LineEdit
		var race := row.get_meta("race") as OptionButton
		var caste := row.get_meta("caste") as OptionButton
		var gender := row.get_meta("gender") as OptionButton
		specs.append(CharacterCreationSpec.new(name_edit.text, String(race.get_selected_metadata()), String(caste.get_selected_metadata()), gender.get_selected_id()))
	intent_submitted.emit(PlayerIntent.create_party(specs))
	_close_modal()


func _remove_party_row(row: HBoxContainer) -> void:
	if _party_rows.get_child_count() > 1:
		row.queue_free()


func _use_item(instance_id: String) -> void:
	intent_submitted.emit(PlayerIntent.use_item(instance_id))
	_close_modal()


func _cast_spell(spell_id: String, character_id: String) -> void:
	if _view == null or _view.combat_view == null or _view.combat_view.monsters.is_empty():
		return
	intent_submitted.emit(PlayerIntent.cast_spell(spell_id, character_id, _view.combat_view.monsters[0].id))
	_close_modal()


func _submit_slot(saving: bool) -> void:
	var slot := _slot_name.text.strip_edges()
	if slot.is_empty():
		return
	if saving:
		save_requested.emit(slot)
	else:
		load_requested.emit(slot)
	_close_modal()


func _open_modal(title: String) -> void:
	_campaign_overlay.visible = false
	_modal_overlay.visible = true
	_modal_title.text = title
	_clear_children(_modal_body)


func _close_modal() -> void:
	_modal_overlay.visible = false
	get_viewport().gui_release_focus()


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_body.add_child(label)


func _request_start(path: String) -> void:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		set_status("Choose a .realmz2 package first", true)
		return
	_party_setup_prompted = false
	start_package_requested.emit(trimmed, int(_seed.value))


func _campaign_display_name(campaign_id: String) -> String:
	var display_name := campaign_id.trim_prefix("scenario-").trim_prefix("realmz2-")
	if display_name.is_empty():
		return campaign_id
	return display_name.replace("-", " ").capitalize()


func _present_event(event: DomainEvent) -> void:
	match event.kind:
		&"message_shown":
			var text := String(event.payload.get("text", "Message"))
			set_status(text)
			_append_log(text)
		&"picture_requested":
			_picture.texture = null
			_picture_caption.text = "Picture %d" % int(event.payload.get("pictureId", 0))
			_append_log("Picture %d requested" % int(event.payload.get("pictureId", 0)))
		&"sound_requested":
			_append_log("Sound %d requested" % int(event.payload.get("soundId", 0)))
		&"party_created":
			set_status("Party created • the adventure begins")
			_append_log("The party enters the realm.")
		&"party_moved":
			set_status("%s • %d,%d" % [_view.party_map_id if _view != null else "Map", int(event.payload.get("x", 0)), int(event.payload.get("y", 0))])
		&"battle_started":
			_append_log("[color=#d5b45d]Battle begins.[/color]")
		&"battle_completed":
			_append_log("Battle completed • %s" % event.payload.get("outcome", "resolved"))
		_:
			_append_log(String(event.kind).replace("_", " ").capitalize())


func _decode_image(asset: PackageMediaAsset, bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	var mime := asset.mime_type.to_lower()
	var extension := asset.path.get_extension().to_lower()
	var error := ERR_UNAVAILABLE
	if mime == "image/png" or extension == "png":
		error = image.load_png_from_buffer(bytes)
	elif mime in ["image/jpeg", "image/jpg"] or extension in ["jpg", "jpeg"]:
		error = image.load_jpg_from_buffer(bytes)
	elif mime == "image/webp" or extension == "webp":
		error = image.load_webp_from_buffer(bytes)
	elif mime == "image/svg+xml" or extension == "svg":
		error = image.load_svg_from_buffer(bytes)
	return image if error == OK else null


func _append_log(text: String) -> void:
	_event_log.append_text("• %s\n" % text)
	_event_log.scroll_to_line(_event_log.get_line_count())


static func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
