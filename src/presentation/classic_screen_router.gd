class_name ClassicScreenRouter
extends Control

signal screen_changed(screen_id: StringName)
signal start_requested(package_path: String, seed: int)
signal refresh_requested
signal intent_submitted(intent: PlayerIntent)

const GOLD := Color("d5b45d")
const INK := Color("17191d")
const PANEL := Color("272b31")
const PANEL_DARK := Color("1d2025")
const MUTED := Color("9aa0a8")

const SCREEN_DEFINITIONS := [

	{"id": &"exploration", "label": "Explore", "description": "Move, search, camp, and follow the scenario."},
	{"id": &"character", "label": "Characters", "description": "Inspect statistics, conditions, allies, and equipment."},
	{"id": &"vault", "label": "Vault", "description": "Import and review reusable character revisions."},
	{"id": &"inventory", "label": "Inventory", "description": "Equip, identify, use, trade, and store items."},
	{"id": &"spells", "label": "Spells", "description": "Review known spells, powers, costs, and targets."},
	{"id": &"services", "label": "Services", "description": "Visit shops, temples, banks, and storage."},
	{"id": &"combat", "label": "Battle", "description": "Choose actors, movement, targets, and combat actions."},
	{"id": &"journal", "label": "Journal", "description": "Review maps, notes, history, and campaign state."},
	{"id": &"system", "label": "System", "description": "Save, load, settings, and readiness diagnostics."},
]

var _view: GameView
var _campaigns: Array[PackageDiscoveryResult] = []
var _screen_id: StringName = &"exploration"
var _body: VBoxContainer
var _navigation: HBoxContainer
var _campaign_overlay: PanelContainer
var _campaign_list: VBoxContainer
var _campaign_detail: RichTextLabel
var _package_path: LineEdit
var _seed: SpinBox
var _setup_overlay: PanelContainer
var _setup_body: VBoxContainer
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
var _party_specs: Array[CharacterCreationSpec] = []
var _vault_records: Array[CharacterVaultRecord] = []
var _selected_race_id: String = ""
var _selected_caste_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_navigation()
	_build_body()
	_build_campaign_overlay()
	_build_setup_overlay()
	show_campaign_selection()


func present(view: GameView) -> void:
	_view = view
	if view == null or not view.session_started:
		return
	if view.party_setup_available:
		_campaign_overlay.visible = false
		_setup_overlay.visible = true
		_refresh_setup_options()
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
		return
	for campaign: PackageDiscoveryResult in _campaigns:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 48)
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


func set_vault_records(records: Array[CharacterVaultRecord]) -> void:
	_vault_records = records.duplicate()
	if _screen_id == &"vault":
		_render_screen()


func show_campaign_selection() -> void:
	_campaign_overlay.visible = true
	_setup_overlay.visible = false
	set_process_input(false)


func accepts_exploration_input() -> bool:
	return not _campaign_overlay.visible and not _setup_overlay.visible and _screen_id == &"exploration"


func open_screen(screen_id: StringName) -> void:
	for definition: Dictionary in SCREEN_DEFINITIONS:
		if definition["id"] == screen_id:
			_screen_id = screen_id
			screen_changed.emit(screen_id)
			_render_screen()
			return


func _build_navigation() -> void:
	_navigation = HBoxContainer.new()
	_navigation.name = "ScreenNavigation"
	_navigation.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_navigation.offset_top = 58.0
	_navigation.offset_bottom = 94.0
	_navigation.add_theme_constant_override("separation", 4)
	add_child(_navigation)
	for definition: Dictionary in SCREEN_DEFINITIONS:
		var button := Button.new()
		button.text = String(definition["label"])
		button.tooltip_text = String(definition["description"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(open_screen.bind(StringName(definition["id"])))
		_navigation.add_child(button)


func _build_body() -> void:
	_body = VBoxContainer.new()
	_body.name = "ScreenBody"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_top = 100.0
	_body.offset_bottom = -8.0
	_body.offset_left = 220.0
	_body.offset_right = -228.0
	_body.add_theme_constant_override("separation", 12)
	add_child(_body)


func _build_campaign_overlay() -> void:
	_campaign_overlay = PanelContainer.new()
	_campaign_overlay.name = "CampaignLibrary"
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
	_campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_campaign_list)
	var details := HBoxContainer.new()
	_package_path = LineEdit.new()
	_package_path.placeholder_text = "Path to .realmz2 package"
	_package_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_setup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_setup_overlay.offset_left = -440.0
	_setup_overlay.offset_top = -280.0
	_setup_overlay.offset_right = 440.0
	_setup_overlay.offset_bottom = 280.0
	_setup_overlay.z_index = 25
	add_child(_setup_overlay)
	_setup_body = VBoxContainer.new()
	_setup_body.add_theme_constant_override("separation", 8)
	_setup_overlay.add_child(_setup_body)
	_setup_campaign_label = _add_label(_setup_body, "Assemble your party", GOLD, 24)
	_setup_campaign_label.custom_minimum_size.y = 28.0
	_setup_restriction_label = _add_label(_setup_body, "", MUTED)
	_setup_restriction_label.custom_minimum_size.y = 34.0
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	for step: String in ["1 Identity", "2 Race & Class", "3 Appearance", "4 Review", "5 Spells"]:
		var step_label := _label(step, Color("e7d078") if step.begins_with("1") else MUTED, 13)
		step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		steps.add_child(step_label)
	_setup_body.add_child(steps)
	var creator := HBoxContainer.new()
	creator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	creator.add_theme_constant_override("separation", 12)
	_setup_body.add_child(creator)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_label("Race", GOLD))
	_race_list = ItemList.new()
	_race_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_race_list.item_selected.connect(_race_selected)
	left.add_child(_race_list)
	creator.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_label("Class", GOLD))
	_caste_list = ItemList.new()
	_caste_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_caste_list.item_selected.connect(_caste_selected)
	right.add_child(_caste_list)
	creator.add_child(right)
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
	var add_member := Button.new()
	add_member.text = "Add character"
	add_member.pressed.connect(_add_character)
	form.add_child(add_member)
	var import_member := Button.new()
	import_member.text = "Import from vault"
	import_member.pressed.connect(_show_vault_for_setup)
	form.add_child(import_member)
	form.add_child(_label("Party", GOLD))
	_party_list = VBoxContainer.new()
	_party_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form.add_child(_party_list)
	creator.add_child(form)
	_setup_message = _add_label(_setup_body, "Choose a race, a class, and a name.", MUTED)
	_setup_message.custom_minimum_size.y = 30.0
	_begin_button = Button.new()
	_begin_button.text = "Begin adventure"
	_begin_button.disabled = true
	_begin_button.pressed.connect(_submit_party)
	_setup_body.add_child(_begin_button)


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
	_begin_button.disabled = _party_specs.is_empty() and not _has_imported_party_member()
	_begin_button.text = "Begin adventure (%d/%d)" % [_party_specs.size() + (1 if _has_imported_party_member() else 0), _maximum_party_size()]
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
	if _has_imported_party_member():
		_setup_message.text = "Imported characters are already in the party. Begin the adventure or start a new party setup."
		return
	if _selected_race_id.is_empty() or _selected_caste_id.is_empty():
		_setup_message.text = "Choose both a race and a class."
		return
	var name := _name_edit.text.strip_edges()
	if name.is_empty():
		name = "Adventurer %d" % (_party_specs.size() + 1)
	if _party_specs.size() >= _maximum_party_size():
		_setup_message.text = "This campaign allows no more than %d characters." % _maximum_party_size()
		return
	var portrait_id := "" if _portrait_option.get_selected_id() == 0 else str(_portrait_option.get_selected_id())
	var combat_icon_id := "" if _combat_icon_option.get_selected_id() == 0 else str(_combat_icon_option.get_selected_id())
	_party_specs.append(CharacterCreationSpec.new(name, _selected_race_id, _selected_caste_id, _gender_option.get_selected_id(), portrait_id, combat_icon_id))
	_refresh_party_list()
	_name_edit.clear()
	_begin_button.disabled = _party_specs.is_empty()
	_begin_button.text = "Begin adventure (%d/%d)" % [_party_specs.size(), _maximum_party_size()]
	_setup_message.text = "Character added. Add another or begin the adventure."
	_update_creator_review()


func _refresh_party_list() -> void:
	_clear(_party_list)
	if _view != null:
		for character: CharacterView in _view.party_members:
			if character.id == "party.starting.adventurer":
				continue
			_add_label(_party_list, "Imported • %s" % character.name, Color("e0e2e5"))
	for index: int in _party_specs.size():
		var spec := _party_specs[index]
		_add_label(_party_list, "%d. %s" % [index + 1, spec.name], Color("e0e2e5"))


func _submit_party() -> void:
	if _has_imported_party_member() and _party_specs.is_empty():
		intent_submitted.emit(PlayerIntent.begin_adventure())
		return
	if _has_imported_party_member():
		_setup_message.text = "Finish the imported party before creating another character."
		return
	if _party_specs.is_empty():
		return
	intent_submitted.emit(PlayerIntent.create_party(_party_specs))


func _has_imported_party_member() -> bool:
	if _view == null:
		return false
	for character: CharacterView in _view.party_members:
		if character.id != "party.starting.adventurer":
			return true
	return false


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
	start_requested.emit(campaign.path, 1)


func _open_typed_path() -> void:
	var path := _package_path.text.strip_edges()
	if not path.is_empty():
		start_requested.emit(path, int(_seed.value))


func _render_screen() -> void:
	if _body == null:
		return
	_clear(_body)
	var title := _display_screen_label(_screen_id)
	_add_label(_body, title, GOLD, 24)
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
			_add_card("Services", "Shops, temples, banks, storage, and treasure screens use the same typed workspace boundary.", "No service interaction is active at this location.")
		&"journal":
			_add_card("Journal & maps", "Classic notes, acquired maps, and event history are presentation workspaces over detached session views.", "Journal data will appear here when supplied by the package.")
		&"system":
			_add_card("System", "Save/load, settings, readiness, and diagnostics belong to the application shell, not to scenario code.", "Package: %s\nRules: %s" % [_view.campaign_id, _view.rules_version])


func _render_characters() -> void:
	for character: CharacterView in _view.party_members:
		_add_card(character.name, "Level %d • %s / %s" % [character.level, character.race_id, character.caste_id], "HP %d/%d • SP %d/%d • Armor %d" % [character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.armor])


func _render_vault() -> void:
	if _vault_records.is_empty():
		_add_card("Character vault", "No published character revisions are installed.", "Create a character and publish it at a committed boundary.")
		return
	for record: CharacterVaultRecord in _vault_records:
		var eligibility := "Revision %s • %s" % [record.revision_hash.left(12), record.source_campaign_id]
		var import_button := Button.new()
		import_button.text = "Import %s" % record.state.name
		import_button.tooltip_text = eligibility
		import_button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.import_vault_character(record.character_id, record.revision_hash)))
		_body.add_child(import_button)


func _show_vault_for_setup() -> void:
	_setup_overlay.visible = false
	_campaign_overlay.visible = false
	_screen_id = &"vault"
	_render_screen()


func _render_inventory() -> void:
	for character: CharacterView in _view.party_members:
		for item: ItemView in character.items:
			_add_card(item.name, character.name, "Charges %d • %s" % [item.charges, "Equipped" if item.equipped else "Carried"])
	if _view.party_members.is_empty():
		_add_card("Inventory", "The party has no characters.", "")


func _render_spells() -> void:
	for character: CharacterView in _view.party_members:
		for spell: SpellView in character.spells:
			_add_card(spell.name, character.name, "Cost %d" % spell.cost)
	if _view.party_members.is_empty():
		_add_card("Spellbook", "The party has no characters.", "")


func _render_combat() -> void:
	if _view.combat_view == null:
		_add_card("Battle", "No battle is active.", "The tactical workspace is ready for a typed combat view.")
		return
	_add_card("Battle %s" % _view.combat_view.battle_id, "Round %d • Active %s" % [_view.combat_view.round_number, _view.combat_view.active_actor_id], "Outcome: %s" % _view.combat_view.outcome)


func _add_card(title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	_body.add_child(panel)


func _display_screen_label(screen_id: StringName) -> String:
	for definition: Dictionary in SCREEN_DEFINITIONS:
		if definition["id"] == screen_id:
			return String(definition["label"])
	return "Realmz"


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
	label.add_theme_font_size_override("font_size", size)
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		child.queue_free()
