extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const OUTPUT_ROOT := "res://artifacts/ui-gallery"
const CHARACTER_VIEW_SCRIPT := preload("res://src/core/view/character_view.gd")
const PACKAGE_OPERATION_VIEW_SCRIPT := preload("res://src/app/package_operation_view.gd")
const SAVE_SLOT_PREVIEW_SCRIPT := preload("res://src/core/view/save_slot_preview.gd")
const APPLICATION_LIFECYCLE_SCRIPT := preload("res://src/app/application_lifecycle.gd")

var _application: RealmzApplication
var _shell: ClassicApplicationShell
var _router: ClassicScreenRouter
var _interaction: InteractionPresenter


func _initialize() -> void:
	call_deferred("_capture_gallery")


func _capture_gallery() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	_application = load("res://src/presentation/realmz_application.tscn").instantiate() as RealmzApplication
	root.add_child(_application)
	_shell = _application.get_node("ClassicShell") as ClassicApplicationShell
	_router = _shell.get_node("ScreenRouter") as ClassicScreenRouter
	_interaction = _application.get_node("InteractionPanel") as InteractionPresenter
	await _settle()
	await _resize(Vector2i(800, 600))
	await _capture("compact-campaign-800x600")
	await _resize(Vector2i(1280, 720))
	Input.warp_mouse(Vector2(520, 18))
	await _settle()
	await _capture("canonical-campaign-menu-hover-1280x720")
	_router.show_campaign_selection()
	_router.set_package_operation(PACKAGE_OPERATION_VIEW_SCRIPT.new(&"running", &"validating_media", 7, 12, "Validating packaged media 7 of 12"))
	await _settle()
	await _capture("canonical-package-install-progress-1280x720")
	_router.set_package_operation(PACKAGE_OPERATION_VIEW_SCRIPT.new())
	await _resize(Vector2i(800, 600))
	_application.start_package(FIXTURE_PATH, 1)
	await _settle()
	await _capture("compact-party-setup-800x600")
	await _resize(Vector2i(1280, 720))
	await _capture("canonical-party-setup-1280x720")
	await _resize(Vector2i(800, 600))
	var setup_view := _application.session_controller.view()
	var setup := _router.setup_controller
	var inspection_state := CharacterState.new("gallery.setup.inspect", "Ari", 18, 18)
	inspection_state.race_id = setup_view.race_options[0].id
	inspection_state.caste_id = setup_view.caste_options[0].id
	inspection_state.portrait_id = setup_view.portrait_options[0].id if not setup_view.portrait_options.is_empty() else ""
	inspection_state.combat_icon_id = setup_view.combat_icon_options[0].id if not setup_view.combat_icon_options.is_empty() else ""
	setup_view.party_members = [CharacterView.new(inspection_state)]
	_shell.present(setup_view)
	var setup_inspect := _button_named(setup.party_list, "View")
	if setup_inspect != null:
		setup_inspect.pressed.emit(); await _settle(); await _capture("compact-party-setup-inspection-800x600")
		await _resize(Vector2i(1280, 720)); await _capture("canonical-party-setup-inspection-1280x720")
		var setup_back := _button_named(setup.setup_inspection_overlay, "Back to party setup")
		if setup_back != null:
			setup_back.pressed.emit()
	setup_view.party_members.clear(); _shell.present(setup_view); await _resize(Vector2i(800, 600))
	setup.create_character_button.pressed.emit()
	await _settle()
	await _capture("compact-character-creator-identity-800x600")
	await _resize(Vector2i(1280, 720))
	await _capture("canonical-character-creator-identity-1280x720")
	setup.selected_race_id = setup_view.race_options[0].id
	setup.selected_caste_id = setup_view.caste_options[0].id
	setup.creator_step = 1
	setup.render_creator_step()
	await _capture("canonical-character-creator-race-class-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("compact-character-creator-race-class-800x600")
	await _resize(Vector2i(1280, 720))
	setup.creator_step = 2
	setup.render_creator_step()
	await _settle()
	await _capture("canonical-character-creator-appearance-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("compact-character-creator-appearance-800x600"); await _resize(Vector2i(1280, 720))
	var review_state := CharacterState.new("gallery.creator", "Ari", 18, 18)
	review_state.race_id = setup_view.race_options[0].id
	review_state.caste_id = setup_view.caste_options[0].id
	review_state.portrait_id = setup_view.portrait_options[0].id if not setup_view.portrait_options.is_empty() else ""
	review_state.combat_icon_id = setup_view.combat_icon_options[0].id if not setup_view.combat_icon_options.is_empty() else ""
	setup_view.character_draft = CharacterView.new(review_state)
	setup.creator_step = 3
	setup.render_creator_step()
	await _capture("canonical-character-creator-review-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("compact-character-creator-review-800x600")
	review_state.spellcaster_type = 1
	setup_view.character_draft = CharacterView.new(review_state)
	setup_view.character_draft_spell_points_total = 4
	setup_view.character_draft_spell_points_remaining = 3
	setup_view.character_draft_spell_options = [CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1101", 1101, "Discover Magic", "Reveals magical influences affecting the caster."), 1, true), CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1107", 1107, "Magic Darts", "A compact bolt of magical force."), 1, false), CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1201", 1201, "Flame Hands", "Calls a brief fan of flame."), 2, false)]
	setup.creator_step = 4
	setup.render_creator_step()
	await _resize(Vector2i(1280, 720))
	await _capture("canonical-character-creator-spells-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("compact-character-creator-spells-800x600")
	setup.reset_creator(true)
	await _settle()
	var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	_application.session_controller.submit_intent(PlayerIntent.create_party([member]))
	await _settle()
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"exploration"); await _settle(); await _capture("canonical-explore-1280x720")
	var explore_view := _application.session_controller.view() as GameView
	explore_view.party_summary.condition_values[ConditionRules.PARTY_SEARCHING] = -1
	_shell.present(explore_view); await _settle(); await _capture("canonical-search-effect-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("compact-search-effect-800x600"); await _resize(Vector2i(1280, 720))
	explore_view.party_summary.condition_values[ConditionRules.PARTY_SEARCHING] = 0
	explore_view.party_summary.camping = true; _shell.present(GameView.new(0, false, null)); _shell.present(explore_view); await _settle(); await _capture("canonical-camp-mode-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-camp-mode-800x600"); await _resize(Vector2i(1280, 720))
	explore_view.party_summary.camping = false; _shell.present(GameView.new(0, false, null)); _shell.present(explore_view); await _settle()
	_interaction.present(InteractionRequest.acknowledge("gallery-edge-to-edge", "The party follows the old road toward Northgate."))
	await _settle()
	await _capture("canonical-acknowledge-edge-to-edge-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-acknowledge-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(null)
	var gallery_view: Variant = _application.session_controller.view()
	var gallery_media := _application.presentation_coordinator.get("_media") as ClassicMediaCatalog
	var scrolling_gallery_text := "<<< Click & Drag Mouse To Move About >>>\n<<< Double Click To End This Message >>>\n\nYou can edit this text via a Resource editor.\n\nInside the scenario is an authored TEXT resource. Opcode 62 displays that exact text as a scrolling message instead of a normal map.\n\nThis passage continues so the stage visibly advances over Castle's tiled background. ".repeat(5)
	_interaction.present(InteractionRequest.from_payload("gallery-scrolling-text", InteractionRequest.ACKNOWLEDGE, {"prompt": scrolling_gallery_text, "messageId": 1, "presentation": "classic-scrolling-text"}), "", gallery_view, gallery_media)
	await _settle()
	await _capture("canonical-scrolling-text-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-scrolling-text-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(null)
	if not gallery_view.party_members.is_empty():
		var active_content: Variant = _application.get("_active_content")
		var definition: Variant = active_content.item_by_id("classic.item.901")
		if definition != null:
			for index: int in 18:
				var gallery_item := ItemView.new(ItemInstance.new("gallery-item-%d" % index, definition.id, maxi(1, definition.initial_charges), index < 6, index % 3 != 0), definition)
				gallery_item.actions.split = ActionAvailabilityView.new(&"split_item", true)
				gallery_view.party_members[0].items.append(gallery_item)
		var gallery_conditions: Array[CharacterMetricView] = [CharacterMetricView.new(&"condition-13", 13, "Cold Protection", 2, "Value 2"), CharacterMetricView.new(&"condition-27", 27, "Blind", -1, "Permanent")]
		gallery_view.party_members[0].conditions = gallery_conditions
		var gallery_modifiers: Array[CharacterMetricView] = [CharacterMetricView.new(&"special-undead", 1, "Undead", 2), CharacterMetricView.new(&"special-large", 6, "Large Creature", 1)]
		var gallery_abilities: Array[CharacterMetricView] = [CharacterMetricView.new(&"ability-detect", 4, "Detect Secret", 3), CharacterMetricView.new(&"ability-lock", 11, "Pick Lock", 2)]
		gallery_view.party_members[0].special_modifiers = gallery_modifiers
		gallery_view.party_members[0].abilities = gallery_abilities
	var gallery_names: Array[String] = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]
	while gallery_view.party_members.size() < 6 and not gallery_view.party_members.is_empty():
		var member_index: int = int(gallery_view.party_members.size())
		var member_state := CharacterState.new("gallery-member-%d" % member_index, gallery_names[member_index], 8 + member_index, 10 + member_index)
		member_state.race_id = gallery_view.party_members[0].race_id
		member_state.caste_id = gallery_view.party_members[0].caste_id
		member_state.armor = member_index
		gallery_view.party_members.append(CHARACTER_VIEW_SCRIPT.new(member_state, _application.get("_active_content")))
	if gallery_view.party_members.size() == 6 and gallery_view.party_members[0].items.size() > 1: var left_trade_item: ItemView = gallery_view.party_members[0].items[0]; var right_trade_item: ItemView = gallery_view.party_members[0].items.pop_back(); gallery_view.party_members[1].items.append(right_trade_item); left_trade_item.actions.trade = ActionAvailabilityView.new(&"trade_item", true); left_trade_item.actions.trade_targets = [ItemTransferTargetView.new(gallery_view.party_members[1].id, gallery_view.party_members[1].name, true, "", 0, left_trade_item.weight, 1000)]; right_trade_item.actions.trade = ActionAvailabilityView.new(&"trade_item", true); right_trade_item.actions.trade_targets = [ItemTransferTargetView.new(gallery_view.party_members[0].id, gallery_view.party_members[0].name, true, "", 0, right_trade_item.weight, 1000)]
	if gallery_view.party_members.size() > 4:
		var gallery_spells: Array[SpellView] = []
		for spell_data: Dictionary in [
			{"id": 1101, "name": "Discover Magic", "cost": 2, "target": 5, "description": "Reveals magical influences affecting the caster."},
			{"id": 1107, "name": "Magic Darts", "cost": 4, "target": 1, "description": "A compact bolt of magical force for one target."},
			{"id": 1309, "name": "Plane of Force", "cost": 4, "target": 3, "size": 10, "queueIcon": 15, "canRotate": true, "description": "A persistent force wall follows the selected Classic orientation."},
			{"id": 1304, "name": "Circle of Renewal", "cost": 5, "target": 9, "description": "Restores friendly combatants within the spell's reach."},
			{"id": 1602, "name": "Energy Storm", "cost": 10, "target": 10, "description": "A violent magical storm strikes every enemy."},
		]:
			var spell_definition := SpellDefinition.new("classic.spell.%d" % int(spell_data.id), int(spell_data.id), String(spell_data.name), String(spell_data.description))
			spell_definition.cost = int(spell_data.cost); spell_definition.range_min = 1; spell_definition.range_max = 2; spell_definition.duration_min = 1; spell_definition.duration_max = 3; spell_definition.damage_min = 2; spell_definition.damage_max = 6; spell_definition.power_damage_min = 1; spell_definition.power_damage_max = 2; spell_definition.target_type = int(spell_data.target); spell_definition.size = int(spell_data.get("size", 0)); spell_definition.queue_icon = int(spell_data.get("queueIcon", 0)); spell_definition.can_rotate = bool(spell_data.get("canRotate", false)); spell_definition.damage_type = 1
			var spell_view := SpellView.new(spell_definition)
			spell_view.power_levels = [1, 2, 3, 4, 5, 6, 7]; spell_view.scroll_power_levels = [1, 2, 3]; spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true); spell_view.make_scroll = ActionAvailabilityView.new(&"make_scroll", true)
			gallery_spells.append(spell_view)
		gallery_view.party_members[4].spell_points = 40
		gallery_view.party_members[4].maximum_spell_points = 50
		gallery_view.party_members[4].spells = gallery_spells
		gallery_view.party_members[0].spell_points = 8
		gallery_view.party_members[0].maximum_spell_points = 12
		gallery_view.party_members[0].spells = gallery_spells
	_shell.present(gallery_view)
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"inventory")
	await _settle()
	await _capture("wide-dense-inventory-1280x720")
	var split_button := _base_button_with_tooltip(_router, "Split")
	if split_button is ClassicBitmapButton:
		(split_button as ClassicBitmapButton).command_requested.emit(&"inventory.action.split"); await _settle(); await _capture("wide-inventory-operation-1280x720")
		var cancel_operation := _button_named(_router, "Cancel")
		if cancel_operation != null:
			cancel_operation.pressed.emit(); await _settle()
	var trade_button := _base_button_with_tooltip(_router, "Open the two-pack Trade workspace")
	if trade_button is ClassicBitmapButton and not trade_button.disabled:
		(trade_button as ClassicBitmapButton).command_requested.emit(&"inventory.action.trade"); await _settle(); await _capture("wide-inventory-trade-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-inventory-trade-800x600")
	var cancel_trade := _button_named(_router, "Items")
	if cancel_trade != null:
		cancel_trade.pressed.emit(); await _settle()
	await _capture("classic-dense-inventory-800x600")
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"spells")
	await _settle()
	await _capture("wide-spells-1280x720")
	var fast_tab := _button_named(_router, "Fast Spells (1–0)")
	if fast_tab != null:
		fast_tab.pressed.emit(); await _settle(); await _capture("wide-fast-spells-1280x720")
	var scroll_tab := _button_named(_router, "Scrolls")
	if scroll_tab != null:
		scroll_tab.pressed.emit(); await _settle(); await _capture("wide-scroll-case-1280x720")
	var known_tab := _button_named(_router, "Known")
	if known_tab != null:
		known_tab.pressed.emit(); await _settle()
	await _resize(Vector2i(800, 600))
	await _capture("classic-spells-800x600")
	await _resize(Vector2i(1280, 720))
	gallery_view.current_location_note = LocationNoteView.new("land:0", "Land level 0", &"land", 0, Vector2i(1, 1), "Watch the northern road.", 0, 0, true)
	var gallery_location_notes: Array[LocationNoteView] = [gallery_view.current_location_note, LocationNoteView.new("land:0", "Land level 0", &"land", 0, Vector2i(4, 6), "A sheltered campsite near the old road.", 0, 1)]; gallery_view.location_notes = gallery_location_notes
	var gallery_journal_entries: Array[JournalEntryView] = [JournalEntryView.new(4, "The road bends toward the mountain."), JournalEntryView.new(19, "A long authored entry remains readable. " + "The party follows the old ridge road while the storm closes in. ".repeat(8))]; gallery_view.journal_entries = gallery_journal_entries
	var map_snapshot := _application.session_controller.session().snapshot(); var player_map_definition: PlayerMapDefinition = _application.get("_active_content").world.player_map_by_classic_id(1)
	map_snapshot.game_state.world.acquire_map(player_map_definition.id)
	var map_session := GameSession.new(); map_session.restore(_application.get("_active_content"), map_snapshot); var map_view := map_session.view()
	gallery_view.player_map_menu_entries = map_view.player_map_menu_entries; gallery_view.acquired_player_maps = map_view.acquired_player_maps; gallery_view.party_summary.acquired_map_ids = map_view.party_summary.acquired_map_ids
	_shell.present(gallery_view)
	_router.open_screen(&"journal")
	await _settle()
	await _capture("wide-journal-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-journal-800x600")
	await _resize(Vector2i(1280, 720))
	var maps_notes_tabs := _router.find_child("MapsNotesTabs", true, false) as TabContainer
	maps_notes_tabs.current_tab = 1; await _settle(); await _capture("canonical-player-maps-1280x720"); await _resize(Vector2i(800, 600))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	maps_notes_tabs.current_tab = 1; await _settle(); await _capture("classic-player-maps-800x600"); await _resize(Vector2i(1280, 720))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	maps_notes_tabs.current_tab = 2; await _settle(); await _capture("canonical-authored-journal-1280x720"); await _resize(Vector2i(800, 600))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	maps_notes_tabs.current_tab = 2; await _settle(); await _capture("classic-authored-journal-800x600"); await _resize(Vector2i(1280, 720))
	_router.open_screen(&"exploration"); await _settle()
	_interaction.present(InteractionRequest.from_payload("gallery-classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"}), "Will you enter the ruined keep?")
	await _settle()
	await _capture("wide-classic-choice-context-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("classic-choice-context-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION))
	await _settle()
	await _capture("wide-encounter-1280x720")
	var word_command := _interaction.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton
	word_command.command_requested.emit(&"word"); await _settle(); await _capture("wide-encounter-word-entry-1280x720")
	var item_command := _interaction.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton
	item_command.command_requested.emit(&"item"); await _settle(); await _capture("wide-encounter-item-picker-1280x720")
	var spell_command := _interaction.find_child("EncounterCommandSpell", true, false) as ClassicBitmapButton
	spell_command.command_requested.emit(&"spell"); await _settle(); await _capture("wide-encounter-spell-picker-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-encounter-spell-picker-800x600")
	word_command = _interaction.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton
	word_command.command_requested.emit(&"word"); await _settle(); await _capture("classic-encounter-word-entry-800x600")
	item_command = _interaction.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton
	item_command.command_requested.emit(&"item"); await _settle(); await _capture("classic-encounter-item-picker-800x600")
	await _resize(Vector2i(1280, 720))
	for interaction_kind: StringName in [
		InteractionRequest.AGE_UPDATE,
		InteractionRequest.INDEXED_CHOICE,
		InteractionRequest.ENCOUNTER_CHOICE,
		InteractionRequest.CHARACTER_SELECTION,
		InteractionRequest.ALLY_SELECTION,
		InteractionRequest.THIEF_ENCOUNTER,
		InteractionRequest.PICK_LOCK,
		InteractionRequest.TEMPLE,
		InteractionRequest.BANK,
		InteractionRequest.POOLED_WEALTH_DEPARTURE,
		InteractionRequest.SESSION_LIFECYCLE,
	]:
		var interaction_request := ClassicUiFixtureGallery.request_for(interaction_kind)
		if interaction_kind == InteractionRequest.AGE_UPDATE and not gallery_view.party_members.is_empty():
			var age_body := interaction_request.body as InteractionRequest.AgeUpdateBody
			age_body.character_id = gallery_view.party_members[0].id; age_body.character_name = gallery_view.party_members[0].name; age_body.portrait_id = gallery_view.party_members[0].portrait_id; age_body.combat_icon_id = gallery_view.party_members[0].combat_icon_id
		if interaction_kind == InteractionRequest.PICK_LOCK and not gallery_view.party_members.is_empty():
			var lock_body := interaction_request.body as InteractionRequest.PickLockRequestBody
			lock_body.character_id = gallery_view.party_members[0].id; lock_body.character_name = gallery_view.party_members[0].name; lock_body.portrait_id = gallery_view.party_members[0].portrait_id
		if interaction_kind == InteractionRequest.CHARACTER_SELECTION and not gallery_view.party_members.is_empty():
			var selection_body := interaction_request.body as InteractionRequest.CharacterSelectionRequestBody
			selection_body.eligible[0].id = gallery_view.party_members[0].id; selection_body.eligible[0].name = gallery_view.party_members[0].name
			_shell.present_character_selection(interaction_request)
		_interaction.present(interaction_request, "", gallery_view, gallery_media)
		await _settle()
		await _capture("wide-interaction-%s-1280x720" % String(interaction_kind).replace("_", "-"))
		if interaction_kind == InteractionRequest.AGE_UPDATE:
			await _resize(Vector2i(800, 600)); await _capture("classic-age-update-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.THIEF_ENCOUNTER:
			await _resize(Vector2i(800, 600)); await _capture("classic-interaction-thief-encounter-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.CHARACTER_SELECTION:
			await _capture("wide-field-spell-target-1280x720")
			await _resize(Vector2i(800, 600)); await _capture("classic-field-spell-target-800x600"); await _resize(Vector2i(1280, 720))
			_shell.present_character_selection(null)
		if interaction_kind == InteractionRequest.ALLY_SELECTION:
			await _resize(Vector2i(800, 600)); await _capture("classic-surviving-allies-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.PICK_LOCK:
			await _resize(Vector2i(800, 600)); await _capture("classic-pick-lock-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind in [InteractionRequest.TEMPLE, InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE]:
			await _resize(Vector2i(800, 600)); _interaction.present(interaction_request, "", gallery_view, gallery_media); await _settle(); await _capture("classic-interaction-%s-800x600" % String(interaction_kind).replace("_", "-")); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION), "", gallery_view, gallery_media)
	await _resize(Vector2i(800, 600))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION), "", gallery_view, gallery_media)
	await _settle()
	await _capture("classic-treasure-distribution-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-treasure-distribution-1280x720"); _interaction.set_block_signals(true); (_interaction.find_child("TreasureDone", true, false) as Button).pressed.emit(); _interaction.set_block_signals(false); var treasure_completion := InteractionRequest.from_payload("gallery.treasure.completion", InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "summary": "One item remains unclaimed. Leave it behind?"}); _interaction.present(treasure_completion, "", gallery_view, gallery_media); await _settle(); await _capture("wide-treasure-completion-modal-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-treasure-completion-modal-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-treasure-unidentified-1280x720")
	await _resize(Vector2i(800, 600)); _interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified"), "", gallery_view, gallery_media); await _settle(); await _capture("classic-treasure-unidentified-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-fumble-recovery-1280x720")
	await _resize(Vector2i(800, 600)); _interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"), "", gallery_view, gallery_media); await _settle(); await _capture("classic-fumble-recovery-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP))
	await _settle()
	await _capture("wide-level-result-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("classic-level-result-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"))
	await _settle()
	await _capture("wide-level-spells-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("classic-level-spells-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(null)
	_shell.present(gallery_view)
	_router.open_screen(&"character")
	await _settle()
	await _capture("canonical-character-overview-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-overview-800x600")
	await _resize(Vector2i(1280, 720))
	var conditions_button := _button_named(_router, "Conditions & Saves")
	if conditions_button != null:
		conditions_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-conditions-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-conditions-800x600")
	await _resize(Vector2i(1280, 720))
	var abilities_button := _button_named(_router, "Abilities")
	if abilities_button != null:
		abilities_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-abilities-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-abilities-800x600")
	await _resize(Vector2i(1280, 720))
	var spell_character_button := _button_named(_router, "Elian")
	if spell_character_button != null:
		spell_character_button.pressed.emit()
	var character_spells_button := _button_named(_router, "Spells")
	if character_spells_button != null:
		character_spells_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-spells-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-spells-800x600")
	await _resize(Vector2i(1280, 720))
	var first_character_button := _button_named(_router, "Ari")
	if first_character_button != null:
		first_character_button.pressed.emit()
	var appearance_button := _button_named(_router, "Appearance")
	if appearance_button != null:
		appearance_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-appearance-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-appearance-800x600")
	await _resize(Vector2i(1280, 720))
	var record_button := _button_named(_router, "Lifetime Record")
	if record_button != null:
		record_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-lifetime-record-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-lifetime-record-800x600")
	await _resize(Vector2i(1280, 720))
	var background_button := _button_named(_router, "Race, Class & Aging")
	if background_button != null:
		background_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-background-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-background-800x600")
	await _resize(Vector2i(1280, 720))
	var equipment_button := _button_named(_router, "Equipment")
	if equipment_button != null:
		equipment_button.pressed.emit()
		await _settle()
		await _capture("canonical-character-equipment-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-character-equipment-800x600")
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"allies")
	await _settle()
	await _capture("canonical-allies-empty-1280x720")
	var ally_definition: Variant = _application.get("_active_content").monster_by_classic_id(1)
	if ally_definition != null:
		var ally := MonsterState.new("gallery-ally", ally_definition.id, "Rook, Northgate Scout", 12, 15, ally_definition.hit_dice, ally_definition.agility, ally_definition.armor, ally_definition.magic_resistance, ally_definition.spell_points, false)
		ally.icon_id = ally_definition.icon_id
		var gallery_allies: Array[MonsterView] = [MonsterView.new(ally, ally_definition, _application.get("_active_content"))]
		gallery_view.party_allies = gallery_allies
		_shell.present(gallery_view)
		await _settle()
		await _capture("canonical-allies-populated-1280x720")
		await _resize(Vector2i(800, 600)); await _capture("classic-allies-populated-800x600"); await _resize(Vector2i(1280, 720))
	if not gallery_view.party_members.is_empty():
		var vault_revision := CharacterVaultRevisionView.new()
		vault_revision.character_id = gallery_view.party_members[0].id
		vault_revision.revision_hash = "a".repeat(64)
		vault_revision.name = gallery_view.party_members[0].name
		vault_revision.level = gallery_view.party_members[0].level
		vault_revision.race_id = gallery_view.party_members[0].race_id
		vault_revision.caste_id = gallery_view.party_members[0].caste_id
		vault_revision.portrait_id = gallery_view.party_members[0].portrait_id
		vault_revision.is_current = true
		vault_revision.eligible = true
		vault_revision.character = gallery_view.party_members[0]
		_router.set_vault_revisions([vault_revision])
		_router.open_screen(&"vault")
		await _settle()
		await _capture("canonical-character-files-1280x720")
		var vault_inspect := _button_named(_router, "Inspect")
		if vault_inspect != null:
			vault_inspect.pressed.emit(); await _settle(); await _capture("canonical-character-file-inspection-1280x720")
			await _resize(Vector2i(800, 600)); await _capture("classic-character-file-inspection-800x600"); await _resize(Vector2i(1280, 720))
	await _resize(Vector2i(800, 600)); await _capture("classic-character-files-800x600")
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("classic-six-member-roster-800x600")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP), "", gallery_view, gallery_media)
	await _resize(Vector2i(800, 600))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP), "", gallery_view, gallery_media)
	await _settle()
	await _capture("classic-shop-interaction-800x600")
	var shop_tabs := _interaction.find_child("ShopBrowserTabs", true, false) as TabContainer
	if shop_tabs != null and shop_tabs.get_tab_count() > 1:
		shop_tabs.current_tab = 1; await _settle(); await _capture("classic-shop-pack-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP), "", gallery_view, gallery_media)
	await _settle()
	await _capture("canonical-shop-interaction-1280x720")
	_interaction.present(null)
	gallery_view.services.clear()
	_shell.present(gallery_view)
	_router.open_screen(&"services")
	await _settle()
	await _capture("wide-party-wealth-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("classic-party-wealth-800x600"); await _resize(Vector2i(1280, 720))
	var service := ServiceView.new()
	service.service_id = "gallery-shop"
	service.service_kind = &"shop"
	service.title = "Shop"
	service.actions = [&"buy", &"sell", &"identify", &"leave"]
	service.disabled_reasons[&"identify"] = "This shop does not identify items."
	gallery_view.services.clear()
	gallery_view.services.append(service)
	_shell.present(gallery_view)
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"services")
	await _settle()
	await _capture("canonical-location-service-1280x720")
	var combat_fixture := _combat_view(gallery_view)
	gallery_view.combat_view = combat_fixture
	_router.open_screen(&"combat")
	_application._battlefield_presenter.present(gallery_view)
	_application._battlefield_presenter.visible = true
	var combat_media := _application.presentation_coordinator.package_media()
	var combat_request := ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	var combat_body := combat_request.body as InteractionRequest.CombatRequestBody
	var gallery_hero_id: String = gallery_view.party_members[0].id
	var gallery_monster_id: String = combat_fixture.monsters[0].id
	combat_body.actor_id = gallery_hero_id; combat_body.combatants[0].id = gallery_hero_id; combat_body.combatants[1].id = gallery_monster_id; combat_body.targets[0].id = gallery_monster_id
	_interaction.present(combat_request, "", gallery_view, combat_media)
	await _settle()
	await _capture("canonical-combat-tactical-workspace-1280x720")
	_application._battlefield_presenter.toggle_reveal_friends()
	await _settle()
	await _capture("canonical-combat-reveal-friends-1280x720")
	_application._battlefield_presenter.toggle_reveal_friends()
	_application._battlefield_presenter.set_movement_costs_visible(true)
	await _settle()
	await _capture("canonical-combat-movement-aid-1280x720")
	_application._battlefield_presenter.set_movement_costs_visible(false)
	await _resize(Vector2i(800, 600))
	await _settle()
	await _capture("classic-combat-tactical-workspace-800x600")
	var spells_button := _interaction.find_child("CombatCommandSpells", true, false) as Button
	if spells_button != null and not spells_button.disabled:
		spells_button.pressed.emit()
		await _settle()
		await _capture("classic-combat-spellbook-800x600")
		await _resize(Vector2i(1280, 720))
		await _capture("canonical-combat-spellbook-1280x720")
		var aim_button := _shell.find_child("CombatSpellAim", true, false) as Button
		if aim_button != null and not aim_button.disabled:
			aim_button.pressed.emit(); await _settle(); await _capture("canonical-combat-targeting-1280x720")
			await _resize(Vector2i(800, 600)); await _capture("classic-combat-targeting-800x600"); await _resize(Vector2i(1280, 720))
			_application._battlefield_presenter.cancel_targeting()
	_interaction.present(combat_request, "", gallery_view, combat_media)
	var battle_entry := CombatPlaybackFrame.new(&"battle_cue", 0.28); battle_entry.display_text = "Battle begins"
	_application._battlefield_presenter.present_playback_frame(battle_entry); _interaction.present_combat_playback_mask(battle_entry); await _settle(); await _capture("canonical-combat-entry-1280x720")
	var automatic_move := CombatPlaybackFrame.new(&"move_start", 0.02); automatic_move.actor_id = gallery_hero_id; automatic_move.from_coordinate = Vector2i(45, 45); automatic_move.to_coordinate = Vector2i(46, 45); automatic_move.automatic = true
	_application._battlefield_presenter.present_playback_frame(automatic_move); _interaction.update_combat_playback_frame(automatic_move); await _settle(); await _capture("canonical-combat-auto-playback-1280x720")
	var victory_cue := CombatPlaybackFrame.new(&"battle_cue", 0.28); victory_cue.display_text = "Victory"
	_application._battlefield_presenter.present_playback_frame(victory_cue); _interaction.update_combat_playback_frame(victory_cue); await _settle(); await _capture("canonical-combat-terminal-cue-1280x720")
	_application._battlefield_presenter.clear_playback_frame()
	_interaction.present(null)
	gallery_view.combat_view = null
	await _resize(Vector2i(1280, 720))
	var current_save := SAVE_SLOT_PREVIEW_SCRIPT.new("quick", SAVE_SLOT_PREVIEW_SCRIPT.PRIMARY, SAVE_SLOT_PREVIEW_SCRIPT.VALID); current_save.rules_version = gallery_view.rules_version; current_save.package_hash = "1".repeat(64); current_save.realmz_day = 5; current_save.realmz_hour = 15; current_save.realmz_minute = 55; current_save.map_id = "land:0"; current_save.coordinate = Vector2i(49, 15); current_save.character_names = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]; current_save.can_load = true
	var backup_save := SAVE_SLOT_PREVIEW_SCRIPT.new("quick", SAVE_SLOT_PREVIEW_SCRIPT.BACKUP, SAVE_SLOT_PREVIEW_SCRIPT.VALID); backup_save.rules_version = gallery_view.rules_version; backup_save.character_names = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]; backup_save.can_load = true
	var corrupt_save := SAVE_SLOT_PREVIEW_SCRIPT.new("broken", SAVE_SLOT_PREVIEW_SCRIPT.PRIMARY, SAVE_SLOT_PREVIEW_SCRIPT.CORRUPT); corrupt_save.error_message = "This save is corrupt or uses an unsupported schema. The active session is unchanged."
	_router.set_save_previews([current_save, backup_save, corrupt_save])
	_router.open_screen(&"system")
	await _settle()
	await _capture("canonical-system-1280x720")
	var corrupt_row := _router.find_child("SavePreview_broken_primary", true, false) as Button
	corrupt_row.pressed.emit(); await _settle(); await _capture("canonical-system-corrupt-save-1280x720")
	var system_tabs := _router.find_child("SystemWorkspaceTabs", true, false) as TabContainer
	for index: int in range(1, 7):
		system_tabs.current_tab = index; await _settle(); await _capture("canonical-system-%s-1280x720" % ["display", "audio", "pacing", "accessibility", "controls", "diagnostics"][index - 1])
	system_tabs.current_tab = 2; await _settle(); (_router.find_child("OpenMusicPlaylist", true, false) as Button).pressed.emit(); await _settle(); await _capture("canonical-music-playlist-1280x720"); (_shell.find_child("MusicDone", true, false) as Button).pressed.emit(); await _settle()
	await _resize(Vector2i(800, 600)); _router.open_screen(&"system"); await _settle(); system_tabs = _router.find_child("SystemWorkspaceTabs", true, false) as TabContainer
	for index: int in range(0, 7):
		system_tabs.current_tab = index; await _settle(); await _capture("classic-system-%s-800x600" % ["save-load", "display", "audio", "pacing", "accessibility", "controls", "diagnostics"][index])
	system_tabs.current_tab = 2; await _settle(); (_router.find_child("OpenMusicPlaylist", true, false) as Button).pressed.emit(); await _settle(); await _capture("classic-music-playlist-800x600"); (_shell.find_child("MusicDone", true, false) as Button).pressed.emit(); await _settle()
	var settings := PresentationSettings.new()
	settings.text_scale = 1.5
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_150
	_shell.apply_settings(settings)
	_router.open_screen(&"system")
	await _settle()
	await _capture("compact-system-ui150-text150-800x600")
	_shell.apply_settings(PresentationSettings.new()); await _resize(Vector2i(1280, 720)); _router.open_screen(&"exploration")
	_interaction.present(APPLICATION_LIFECYCLE_SCRIPT.end_adventure_request(false), "", gallery_view, gallery_media); await _settle(); await _capture("canonical-end-adventure-1280x720")
	await _resize(Vector2i(800, 600)); await _capture("classic-end-adventure-800x600")
	await _resize(Vector2i(1280, 720)); _interaction.present(APPLICATION_LIFECYCLE_SCRIPT.quit_application_request(true, false), "", gallery_view, gallery_media); await _settle(); await _capture("canonical-quit-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-quit-800x600")
	_interaction.present(null); _router.set_save_and_quit_mode(true); await _resize(Vector2i(1280, 720)); _router.open_screen(&"system"); await _settle(); await _capture("canonical-save-and-quit-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-save-and-quit-800x600"); _router.set_save_and_quit_mode(false); _router.open_screen(&"exploration"); _shell.present(gallery_view); await _resize(Vector2i(1920, 1080)); await _capture("fit-explore-1920x1080"); await _resize(Vector2i(3440, 1440)); await _capture("fit-explore-ultrawide-3440x1440"); await _resize(Vector2i(3840, 2160)); await _capture("fit-explore-4k-3840x2160")
	_application.queue_free()
	await process_frame
	quit(0)


func _resize(size: Vector2i) -> void:
	root.size = size
	DisplayServer.window_set_size(size)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUTPUT_ROOT, label]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		printerr("Unable to save UI gallery frame %s: %s" % [label, error_string(error)])
	else:
		print("CAPTURED: %s" % path)


func _button_named(parent: Node, text: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		if node is Button and (node as Button).text == text:
			return node as Button
	return null


func _base_button_with_tooltip(parent: Node, tooltip: String) -> BaseButton:
	for node: Node in parent.find_children("*", "BaseButton", true, false):
		if node is BaseButton and (node as BaseButton).tooltip_text == tooltip:
			return node as BaseButton
	return null


func _combat_view(game_view: Variant) -> CombatView:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(232)
	for y: int in range(38, 53):
		for x: int in range(36, 55):
			tiles[y * BattlefieldState.SIZE + x] = 1 + posmod(x * 7 + y * 11, 200)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var hero_view: Variant = game_view.party_members[0]
	var hero := CharacterState.new(hero_view.id, hero_view.name, hero_view.current_health, hero_view.maximum_health)
	hero.combat_icon_id = hero_view.combat_icon_id
	hero.movement = 8
	hero.maximum_movement = 10
	battlefield.place_character(hero.id, Vector2i(45, 45))
	var monster := MonsterState.new("gallery.goblin", "classic.monster.1", "Goblin Raider", 8, 10)
	monster.icon_id = 9001
	battlefield.place_monster(monster.id, Vector2i(47, 45), 0)
	var combat := CombatState.new("classic.battle.gallery", [monster], 0, battlefield)
	combat.set_turn_order([hero.id, monster.id]); combat.queue_persistent_field("classic.spell.1309", hero.id, Vector2i(49, 45), 0, 10, 15, 1, 3, 2)
	var result := CombatView.new(combat, [hero], _application.get("_active_content"))
	result.attack_units_remaining = 2
	result.movement_remaining = 8
	result.legal_actions = [&"defend", &"finish"]
	result.targets = [MonsterView.new(monster)]
	result.movement_options = [
		CombatMoveOptionView.new(Vector2i(-1, -1), BattlefieldStepResult.permitted(Vector2i(44, 44), 1)),
		CombatMoveOptionView.new(Vector2i.UP, BattlefieldStepResult.permitted(Vector2i(45, 44), 1)),
		CombatMoveOptionView.new(Vector2i(1, -1), BattlefieldStepResult.permitted(Vector2i(46, 44), 1)),
		CombatMoveOptionView.new(Vector2i.LEFT, BattlefieldStepResult.permitted(Vector2i(44, 45), 1)),
		CombatMoveOptionView.new(Vector2i.RIGHT, BattlefieldStepResult.blocked(&"occupied", Vector2i(46, 45), monster.id), false, false, monster.id, monster.name),
		CombatMoveOptionView.new(Vector2i(-1, 1), BattlefieldStepResult.permitted(Vector2i(44, 46), 2)),
		CombatMoveOptionView.new(Vector2i.DOWN, BattlefieldStepResult.permitted(Vector2i(45, 46), 1)),
		CombatMoveOptionView.new(Vector2i.ONE, BattlefieldStepResult.permitted(Vector2i(46, 46), 2)),
	]
	return result
