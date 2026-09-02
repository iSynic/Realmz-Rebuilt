class_name PartySetupAssemblyController
extends "res://src/presentation/controllers/party_setup_controller_component.gd"

const PartySetupPartySlotScript := preload("res://src/presentation/party_setup_party_slot.gd")

var _inspection: RefCounted
var _stored_revision_signature: String = ""
var _stored_character_page: int = 0
var _party_slots: Array[Control] = []
var _party_slots_owner: PartySetupPartyList


func _init(state: RefCounted, inspection: RefCounted) -> void:
	super(state)
	_inspection = inspection


func _inspect_setup_character(character_id: String) -> void:
	_inspection._inspect_setup_character(character_id)

func _refresh_party_list() -> void:
	if party_list == null:
		return
	_ensure_party_slots()
	_ensure_appearance_textures()
	var import_available: bool = view != null and view.availability(&"import_vault_character").enabled and view.party_members.size() < _maximum_party_size()
	var import_reason := "" if import_available else "The party cannot accept another stored character right now."
	party_list.configure_drop_target(import_available, import_reason)
	var party_count := setup_overlay.find_child("PartyCount", true, false) as Label
	if party_count != null:
		party_count.text = "• %d / %d" % [view.party_members.size() if view != null else 0, _maximum_party_size()]
	for slot_index: int in _maximum_party_size():
		var character: CharacterView = view.party_members[slot_index] if view != null and view.party_setup_available and slot_index < view.party_members.size() else null
		var portrait: Texture2D = (_appearance_textures.get(character.portrait_id) as Texture2D) if character != null else null
		var remove_availability := view.availability(&"remove_party_member") if view != null else ActionAvailabilityView.new(&"remove_party_member", false, "No active setup.")
		_party_slots[slot_index].call("configure", slot_index, character, portrait, layout_profile == UiLayoutProfile.COMPACT, remove_availability)


func _ensure_party_slots() -> void:
	if _party_slots_owner == party_list and _party_slots.size() == _maximum_party_size():
		return
	_clear(party_list); _party_slots.clear(); _party_slots_owner = party_list
	for slot_index: int in _maximum_party_size():
		var slot := PartySetupPartySlotScript.new() as Control
		slot.name = "PartySlot%d" % (slot_index + 1); slot.inspect_requested.connect(_inspect_setup_character); slot.remove_requested.connect(_remove_setup_character); party_list.add_child(slot); _party_slots.append(slot)

func _render_party_assembly() -> void:
	var campaign_setup := view != null and view.party_setup_available and not standalone_character_creation_active
	var party_full := campaign_setup and view.party_members.size() >= _maximum_party_size()
	create_character_button.visible = true
	begin_button.visible = true
	create_character_button.disabled = party_full or (not campaign_setup and not standalone_character_creation_available)
	if party_full:
		create_character_button.tooltip_text = "This party already has %d characters." % _maximum_party_size()
	elif campaign_setup:
		create_character_button.tooltip_text = "Create a character using this scenario's standard or custom race and class definitions."
	elif standalone_character_creation_available:
		create_character_button.tooltip_text = "Create a reusable Character File with the built-in Realmz races and classes."
	else:
		create_character_button.tooltip_text = standalone_character_creation_reason
	creator_steps.visible = false
	creator_action_bar.visible = false
	party_setup_options.visible = view != null and view.party_setup_available
	setup_message.visible = false
	var current_revisions := _current_vault_revisions()
	_clamp_stored_character_page(current_revisions.size())
	var visible_revision_asset_ids: Array[String] = []
	for revision: CharacterVaultRevisionView in _stored_character_page_items(current_revisions):
		var portrait_id := revision.character.portrait_id if revision.character != null else revision.portrait_id
		if not portrait_id.is_empty():
			visible_revision_asset_ids.append(portrait_id)
		if revision.character != null and not revision.character.combat_icon_id.is_empty():
			visible_revision_asset_ids.append(revision.character.combat_icon_id)
	_ensure_appearance_textures(visible_revision_asset_ids)
	var next_signature := "%s:%s:%d" % [_vault_signature(current_revisions), str(layout_profile), _stored_character_page]
	if stored_character_list != null and is_instance_valid(stored_character_list) and stored_character_list.is_inside_tree() and next_signature == _stored_revision_signature:
		_refresh_stored_character_rows(current_revisions, campaign_setup, party_full)
		return
	_clear_creator_page()
	var heading := CenterContainer.new()
	heading.name = "CharacterFilesHeading"
	heading.custom_minimum_size.y = 28.0
	var heading_content := HBoxContainer.new()
	heading_content.add_child(_label("Character Files", GOLD, 20))
	var character_count := _label("• %d available" % _current_vault_revisions().size(), MUTED, 13)
	character_count.name = "CharacterFileCount"
	heading_content.add_child(character_count)
	heading.add_child(heading_content)
	creator_page.add_child(heading)
	stored_character_list = VBoxContainer.new()
	stored_character_list.name = "StoredCharacterList"
	stored_character_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stored_character_list.add_theme_constant_override("separation", 2)
	creator_page.add_child(stored_character_list)
	_stored_revision_signature = next_signature
	if current_revisions.is_empty():
		var empty := _label("No Character Files yet. Create one here.", MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stored_character_list.add_child(empty)
		return
	var global_available: ActionAvailabilityView = view.availability(&"import_vault_character") if campaign_setup else ActionAvailabilityView.new(&"import_vault_character", false, "Choose a scenario before adding a Character File to a party.")
	for revision: CharacterVaultRevisionView in _stored_character_page_items(current_revisions):
		var reason := ""
		if not campaign_setup:
			reason = global_available.reason
		elif not revision.eligible:
			reason = "\n".join(revision.eligibility_reasons)
		elif not global_available.enabled:
			reason = global_available.reason
		elif party_full:
			reason = "This party already has %d characters." % _maximum_party_size()
		var row := PartySetupCharacterRowScript.new()
		row.name = "StoredCharacter_%s" % revision.character_id.validate_node_name()
		var portrait_id := revision.character.portrait_id if revision.character != null else revision.portrait_id
		var portrait := _appearance_textures.get(portrait_id) as Texture2D
		row.configure(revision, campaign_setup and revision.eligible and global_available.enabled and not party_full, reason, portrait)
		row.import_requested.connect(_import_stored_character)
		stored_character_list.add_child(row)
	_add_stored_character_pager(current_revisions.size())


func _refresh_stored_character_rows(current_revisions: Array[CharacterVaultRevisionView], campaign_setup: bool, party_full: bool) -> void:
	var count_label := creator_page.find_child("CharacterFileCount", true, false) as Label
	if count_label != null:
		count_label.text = "• %d available" % current_revisions.size()
	var global_available: ActionAvailabilityView = view.availability(&"import_vault_character") if campaign_setup else ActionAvailabilityView.new(&"import_vault_character", false, "Choose a scenario before adding a Character File to a party.")
	var visible_revisions := _stored_character_page_items(current_revisions)
	for index: int in visible_revisions.size():
		var revision := visible_revisions[index]
		var row := stored_character_list.get_child(index) as PartySetupCharacterRow
		if row == null:
			continue
		var reason := ""
		if not campaign_setup:
			reason = global_available.reason
		elif not revision.eligible:
			reason = "\n".join(revision.eligibility_reasons)
		elif not global_available.enabled:
			reason = global_available.reason
		elif party_full:
			reason = "This party already has %d characters." % _maximum_party_size()
		var portrait_id := revision.character.portrait_id if revision.character != null else revision.portrait_id
		row.configure(revision, campaign_setup and revision.eligible and global_available.enabled and not party_full, reason, _appearance_textures.get(portrait_id) as Texture2D)


func _stored_character_page_size() -> int:
	return 6 if layout_profile == UiLayoutProfile.COMPACT else 9


func _clamp_stored_character_page(item_count: int) -> void:
	var page_count := maxi(1, ceili(float(item_count) / float(_stored_character_page_size())))
	_stored_character_page = clampi(_stored_character_page, 0, page_count - 1)


func _stored_character_page_items(revisions: Array[CharacterVaultRevisionView]) -> Array[CharacterVaultRevisionView]:
	_clamp_stored_character_page(revisions.size())
	var page_size := _stored_character_page_size()
	var start := _stored_character_page * page_size
	var result: Array[CharacterVaultRevisionView] = []
	for index: int in range(start, mini(start + page_size, revisions.size())):
		result.append(revisions[index])
	return result


func _add_stored_character_pager(item_count: int) -> void:
	var page_size := _stored_character_page_size()
	var page_count := maxi(1, ceili(float(item_count) / float(page_size)))
	if page_count <= 1:
		return
	var pager := HBoxContainer.new()
	pager.name = "CharacterFilePager"
	pager.add_theme_constant_override("separation", 6)
	var previous := Button.new()
	previous.text = "Previous"
	previous.disabled = _stored_character_page == 0
	previous.pressed.connect(_change_stored_character_page.bind(-1))
	pager.add_child(previous)
	var page_label := _label("Page %d of %d" % [_stored_character_page + 1, page_count], MUTED, 12)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(page_label)
	var next := Button.new()
	next.text = "Next"
	next.disabled = _stored_character_page >= page_count - 1
	next.pressed.connect(_change_stored_character_page.bind(1))
	pager.add_child(next)
	creator_page.add_child(pager)


func _change_stored_character_page(offset: int) -> void:
	_stored_character_page += offset
	_stored_revision_signature = ""
	_render_party_assembly()


static func _vault_signature(revisions: Array[CharacterVaultRevisionView]) -> String:
	var parts: PackedStringArray = []
	for revision: CharacterVaultRevisionView in revisions:
		parts.append("%s:%s" % [revision.character_id, revision.revision_hash])
	return "|".join(parts)

func render_party_assembly() -> void:
	_render_party_assembly()

func _refresh_party_setup_options() -> void:
	if difficulty_option == null:
		return
	if view == null or not view.party_setup_available or view.party_setup == null:
		party_setup_options.visible = false
		begin_button.disabled = true
		begin_button.text = "Begin adventure (0/6)"
		return
	party_setup_options.visible = setup_mode == &"assembly"
	monster_set_option.clear()
	var ordered_monster_sets: Array[int] = []
	for preferred_set_id: int in [0, -1, 1]:
		if view.party_setup.available_monster_sets.has(preferred_set_id):
			ordered_monster_sets.append(preferred_set_id)
	for set_id: int in view.party_setup.available_monster_sets:
		if not ordered_monster_sets.has(set_id):
			ordered_monster_sets.append(set_id)
	for set_id: int in ordered_monster_sets:
		monster_set_option.add_item(PartySetupView.monster_set_name(set_id))
		monster_set_option.set_item_metadata(monster_set_option.item_count - 1, set_id)
	_select_option_metadata(monster_set_option, view.party_setup.monster_set)
	_select_option_metadata(difficulty_option, view.party_setup.difficulty)
	var summary := view.campaign_summary
	var maximum := "None" if summary == null or summary.maximum_party_levels <= 0 else str(summary.maximum_party_levels)
	var recommended := "—" if summary == null or not summary.guidance_authored or summary.recommended_party_levels <= 0 else str(summary.recommended_party_levels)
	var gained := "—" if view.party_setup.experience_percent <= 0 else "%d%%" % view.party_setup.experience_percent
	party_guidance_label.text = "Maximum %s  •  Recommended %s  •  Current %d" % [maximum, recommended, view.party_setup.current_party_levels]
	var experience_ratio := party_setup_options.find_child("ExperienceRatio", true, false) as Label
	if experience_ratio != null:
		experience_ratio.text = "Experience gained at %s" % gained

func _party_setup_option_changed(_index: int) -> void:
	if view == null or view.party_setup == null:
		return
	var difficulty := int(difficulty_option.get_item_metadata(difficulty_option.selected))
	var monster_set := int(monster_set_option.get_item_metadata(monster_set_option.selected))
	_state.intent_submitted.emit(PlayerIntent.set_party_setup_options(difficulty, monster_set))

func party_setup_option_changed(index: int) -> void:
	_party_setup_option_changed(index)

func _current_vault_revisions() -> Array[CharacterVaultRevisionView]:
	var current_revisions: Array[CharacterVaultRevisionView] = []
	for revision: CharacterVaultRevisionView in vault_revisions:
		if revision.is_current and not revision.archived:
			current_revisions.append(revision)
	current_revisions.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	return current_revisions

func _import_stored_character(character_id: String, revision_hash: String) -> void:
	_state.intent_submitted.emit(PlayerIntent.import_vault_character(character_id, revision_hash))

func _remove_setup_character(character_id: String) -> void:
	_state.intent_submitted.emit(PlayerIntent.remove_party_member(character_id))

func submit_party() -> void:
	if view == null or view.party_members.is_empty():
		return
	_state.intent_submitted.emit(PlayerIntent.begin_adventure())

func _maximum_party_size() -> int:
	if view == null or view.campaign_summary == null:
		return 6
	return clampi(view.campaign_summary.maximum_party_size, 1, 6)
