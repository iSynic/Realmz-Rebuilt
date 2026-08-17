extends RealmzTestCase

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const PackageOperationStatusScript := preload("res://src/app/package_operation_view.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")
const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func _fixture_request(id: String, kind: StringName, overrides: Dictionary = {}) -> InteractionRequest:
	var payload := ClassicUiFixtureGallery.payload_for(kind)
	payload.merge(overrides, true)
	return InteractionRequest.from_payload(id, kind, payload)


func _buttons_in(root: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in root.find_children("*", "Button", true, false):
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _direct_buttons_in(root: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in root.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _base_buttons_in(root: Node) -> Array[BaseButton]:
	var buttons: Array[BaseButton] = []
	for child: Node in root.find_children("*", "BaseButton", true, false):
		if child is BaseButton:
			buttons.append(child as BaseButton)
	return buttons


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		if child is Label:
			labels.append((child as Label).text)
	return labels


func _visible_labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		if child is Label and (child as Label).visible:
			labels.append((child as Label).text)
	return labels


func _visible_button_texts_in(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for button: Button in _buttons_in(root):
		if button.visible:
			texts.append(button.text)
	return texts


func run() -> void:
	_test_startup_shell()
	_test_startup_party_setup_composition()
	_test_package_operation_presentation()
	_test_primary_workspace_lifecycle()
	_test_layout_profiles()
	_test_settings_schema_and_migration()
	_test_movement_input()
	_test_fast_spell_input()
	_test_fixture_gallery_coverage()
	_test_lifecycle_interaction()
	_test_classic_choice_context()
	_test_battle_weapon_mode_component()
	_test_battle_typed_option_contracts()
	_test_shop_component()
	_test_temple_component()
	_test_bank_component()
	_test_route_catalog()
	_test_save_preview_workspace()
	_test_location_note_workspace()
	_test_player_map_workspace()
	_test_battlefield_presenter()
	_test_combat_targeting_state()
	_test_combat_playback_controller()
	_test_character_creator_workflow()
	_test_character_vault_workspace()
	_test_field_spell_workspace()
	_test_inventory_workspace()
	_test_party_order_workspace()
	_test_character_sheet_workspace()
	_test_scene_composition()
	_test_automatic_workflow_routes()
func _test_startup_party_setup_composition() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var profile := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(960, 600))
	router.set_standalone_character_creation_available(true)
	router.show_campaign_selection()

	var workspace := router.find_child("ScenarioPartyWorkspace", true, false) as Control
	var scenario_pane := router.find_child("ScenarioColumn", true, false) as Control
	var scenario_heading := router.find_child("ScenarioHeading", true, false) as Control
	var character_heading := router.find_child("CharacterFilesHeading", true, false) as Control
	var party_heading := router.find_child("PartyHeading", true, false) as Control
	var character_pane := router.find_child("CharacterFilesPane", true, false) as Control
	var party_pane := router.find_child("CurrentPartyPane", true, false) as Control
	var scenario_style: StyleBox = scenario_pane.get_theme_stylebox("panel") if scenario_pane != null else null
	var character_style: StyleBox = character_pane.get_theme_stylebox("panel") if character_pane != null else null
	var party_style: StyleBox = party_pane.get_theme_stylebox("panel") if party_pane != null else null

	assert_true(workspace != null and workspace is HBoxContainer, "startup party setup mounts one horizontal three-pane workspace")
	assert_equal(workspace.get_child_count() if workspace != null else -1, 3, "startup party setup has exactly Scenarios, Character Files, and Current Party panes")
	assert_true(scenario_pane != null and character_pane != null and party_pane != null and scenario_pane != character_pane and scenario_pane != party_pane and character_pane != party_pane, "the three startup panes are distinct controls")
	assert_true(scenario_pane != null and character_pane != null and party_pane != null and scenario_pane.get_parent() == workspace and character_pane.get_parent() == workspace and party_pane.get_parent() == workspace, "the three startup panes are direct siblings in the full-stage row")
	assert_true(scenario_pane is PanelContainer and character_pane is PanelContainer and party_pane is PanelContainer and scenario_style != null and character_style != null and party_style != null, "each startup pane has a named panel backing instead of relying on the shared slate alone")
	assert_true(scenario_pane != null and character_pane != null and party_pane != null and scenario_pane.custom_minimum_size.x < character_pane.custom_minimum_size.x and scenario_pane.custom_minimum_size.x < party_pane.custom_minimum_size.x and scenario_pane.size_flags_stretch_ratio < character_pane.size_flags_stretch_ratio and scenario_pane.size_flags_stretch_ratio < party_pane.size_flags_stretch_ratio, "Scenarios receives a narrower minimum and stretch share than Character Files and Current Party")
	assert_true(scenario_heading != null and character_heading != null and party_heading != null and absf(scenario_heading.global_position.y - character_heading.global_position.y) <= 1.0 and absf(character_heading.global_position.y - party_heading.global_position.y) <= 1.0, "all three startup pane headings share one aligned top band")
	assert_true(character_heading != null and character_heading.visible and party_heading != null and party_heading.visible, "Character Files and Current Party remain visible in the startup composition")
	var party_slots := router.find_child("PartySlots", true, false)
	assert_equal(party_slots.get_child_count() if party_slots != null else -1, 6, "Current Party keeps all six available positions visible in the startup composition")
	router.free()


func _test_package_operation_presentation() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var canceled := [0]
	router.cancel_package_requested.connect(func() -> void: canceled[0] += 1)
	router.set_package_operation(PackageOperationStatusScript.new(&"running", &"loading", 2, 4, "Loading package 2 of 4"))
	var progress := router.find_child("PackageOperationProgress", true, false) as ProgressBar
	var cancel := router.find_child("CancelPackageOperation", true, false) as Button
	assert_equal([progress.value, progress.max_value], [2.0, 4.0], "package work exposes bounded detached progress")
	assert_not_null(cancel, "package work exposes cancellation")
	cancel.pressed.emit()
	assert_equal(canceled[0], 1, "cancellation remains a host signal")
	router.set_package_operation(PackageOperationStatusScript.new())
	assert_true(router.find_child("CancelPackageOperation", true, false) == null, "completed package work removes transient controls")
	router.free()
func _test_primary_workspace_lifecycle() -> void:
	var router := ClassicScreenRouter.new()
	router.initialize()
	var view := GameView.new(1, true, null)
	view.campaign_id = "workspace-fixture"
	view.rules_version = "realmz-classic-1"
	view.party_summary = PartySummaryView.new()
	router.present(view)
	var entered: Array[StringName] = []
	router.screen_changed.connect(func(route_id: StringName) -> void: entered.append(route_id))
	for route_id: StringName in [&"character", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"exploration", &"combat"]:
		router.open_screen(route_id)
		assert_equal(router.current_screen(), route_id, "route selection commits the requested primary workspace")
		assert_equal(router.primary_workspace_id(), route_id, "the mounted scene and route registry cannot diverge")
		assert_equal(router.mounted_primary_workspace_count(), 1, "a route transition leaves exactly one primary workspace mounted")
		assert_equal(router.primary_workspace_visible(), route_id not in [&"exploration", &"combat"], "only spatial play routes suppress their explanatory workspace body")
	assert_equal(entered, [&"character", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"exploration", &"combat"], "each primary transition publishes exactly one entered route after replacing the prior workspace")
	var setup_view := GameView.new(2, true, null)
	setup_view.party_setup_available = true
	setup_view.party_members = [CharacterView.new(CharacterState.new("closing.hero", "Closing Hero", 10, 10))]
	router.present(setup_view)
	router.show_campaign_selection()
	assert_equal((router.find_child("PartyCount", true, false) as Label).text, "• 1 / 6", "party setup presents the active assembly count")
	router.present(GameView.new(3, false, null))
	router.show_campaign_selection()
	assert_equal((router.find_child("PartyCount", true, false) as Label).text, "• 0 / 6", "ending an adventure clears the setup controller's stale party count")
	router.free()


func _test_startup_shell() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	router.show_splash()
	var profile := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(960, 600))
	router.set_standalone_character_creation_available(true)
	var splash := router.find_child("SplashScreen", true, false) as Control
	assert_true(splash != null and splash.visible, "Realmz Rebuilt opens on its application splash instead of dropping directly into package selection")
	assert_false(router.setup_controller.campaign_overlay.visible, "the campaign library waits for an explicit splash action")
	var choose_scenario := splash.find_child("ChooseScenario", true, false) as Button
	var character_files := splash.find_child("CharacterFiles", true, false) as Button
	assert_not_null(choose_scenario, "the splash exposes scenario selection as a primary path")
	assert_not_null(character_files, "the splash exposes reusable character files independently of party setup")
	choose_scenario.pressed.emit()
	var setup_workspace := router.find_child("PartySetup", true, false) as Control
	var scenario_picker := router.find_child("ScenarioColumn", true, false) as Control
	if scenario_picker == null:
		scenario_picker = router.find_child("CampaignLibrary", true, false) as Control
	assert_true(setup_workspace != null and setup_workspace.visible and not splash.visible, "scenario selection opens the integrated scenario and party setup workspace")
	assert_true(scenario_picker != null and setup_workspace != null and scenario_picker.visible and setup_workspace.is_ancestor_of(scenario_picker), "scenario selection is a left-column picker inside the integrated workspace, not an obsolete separate campaign modal")
	router.set_campaigns([
		CampaignPackageView.new("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2", true, "installed-scenario", "", "", "", "Installed Scenario"),
		CampaignPackageView.new("user://packages/stale.realmz2", false, "stale-scenario", "", "", "Package schema hash does not match the runtime contract mirror.", "Stale Scenario"),
	])
	var scenario_copy: Array[String] = []
	if scenario_picker != null:
		scenario_copy.append_array(_visible_labels_in(scenario_picker))
		scenario_copy.append_array(_visible_button_texts_in(scenario_picker))
	assert_true(router.setup_controller.campaign_list is VBoxContainer and router.setup_controller.campaign_list.get_parent() is ScrollContainer, "installed scenarios use one single-column picker surface")
	assert_false(scenario_copy.any(func(text: String) -> bool: return text.contains("Stale Scenario")), "incompatible installations do not become ordinary scenario rows")
	assert_contains(scenario_picker.tooltip_text, "installation hidden", "the picker preserves incompatible-installation diagnostics in unobtrusive hover text")
	var scenario_buttons: Array[String] = _visible_button_texts_in(scenario_picker) if scenario_picker != null else []
	assert_false(scenario_buttons.any(func(text: String) -> bool: return text == "Play"), "scenario rows do not expose the obsolete per-row Play action")
	var install_buttons: Array[String] = _visible_button_texts_in(scenario_picker) if scenario_picker != null else []
	assert_true(install_buttons.any(func(text: String) -> bool: return text.begins_with("Install .realmz2")), "the external package action uses installation language")
	assert_false(install_buttons.any(func(text: String) -> bool: return text == "Open path" or text.to_lower().contains("play")), "the integrated workspace does not label external installation as Play")
	assert_true(router.find_child("Seed", true, false) == null, "developer seed controls are absent from the ordinary integrated workspace")
	var character_heading: Control = null
	var party_heading: Control = null
	if setup_workspace != null:
		character_heading = setup_workspace.find_child("CharacterFilesHeading", true, false) as Control
		party_heading = setup_workspace.find_child("PartyHeading", true, false) as Control
	assert_true(character_heading != null and party_heading != null, "the pre-session workspace mounts both setup columns before a campaign session exists")
	assert_false(router.setup_controller.create_character_button.disabled, "stock Character Files creation remains available before a scenario is selected")
	assert_true(router.setup_controller.begin_button.disabled, "Begin Adventure remains unavailable until a scenario and party are selected")
	var standalone_requests: Array[int] = [0]
	router.standalone_character_creation_requested.connect(func() -> void: standalone_requests[0] += 1)
	router.setup_controller.create_character_button.pressed.emit()
	assert_equal(standalone_requests[0], 1, "pre-session Create Character requests the application-owned stock creator")
	var empty_party_slots: Node = null
	if setup_workspace != null:
		empty_party_slots = setup_workspace.find_child("PartySlots", true, false)
	assert_not_null(empty_party_slots, "the integrated workspace owns one named Current Party slot list before session preparation")
	assert_equal(empty_party_slots.get_child_count() if empty_party_slots != null else -1, 6, "pre-session Current Party renders all six empty positions")
	if empty_party_slots != null:
		for slot_number: int in range(1, 7):
			assert_not_null(empty_party_slots.find_child("EmptyPartySlot%d" % slot_number, true, false), "pre-session Current Party preserves empty slot %d" % slot_number)
	assert_true(router.handle_back(), "Back from the integrated pre-session workspace returns to the splash")
	assert_true(splash.visible, "the startup flow retains a real front door after backing out of campaign selection")
	var route_changes: Array[StringName] = []
	router.screen_changed.connect(func(screen_id: StringName) -> void: route_changes.append(screen_id))
	character_files.pressed.emit()
	assert_equal(router.current_screen(), &"vault", "Character Files opens the advanced reusable-character workspace")
	assert_true(router.full_stage_overlay_visible(), "Character Files owns the complete stage instead of sharing it with the persistent roster")
	assert_equal(route_changes[-1], &"vault", "opening Character Files notifies the shell so it can suppress persistent play regions")
	assert_true(router.handle_back(), "Back closes the startup Character Files workspace through the public route lifecycle")
	assert_true(splash.visible, "closing startup Character Files restores the splash")
	router.free()


func _test_save_preview_workspace() -> void:
	var view := GameView.new(3, true, null)
	view.campaign_id = "preview-campaign"
	view.rules_version = "realmz-classic-1"
	var current := SaveSlotPreviewScript.new("quick", SaveSlotPreviewScript.PRIMARY, SaveSlotPreviewScript.VALID)
	current.rules_version = view.rules_version
	current.package_hash = "1".repeat(64)
	current.realmz_day = 2
	current.realmz_hour = 7
	current.realmz_minute = 15
	current.map_id = "land:4"
	current.coordinate = Vector2i(12, 9)
	current.character_names = ["Mira", "Borin"]
	current.can_load = true
	var backup := SaveSlotPreviewScript.new("quick", SaveSlotPreviewScript.BACKUP, SaveSlotPreviewScript.VALID)
	backup.rules_version = view.rules_version
	backup.can_load = true
	var corrupt := SaveSlotPreviewScript.new("broken", SaveSlotPreviewScript.PRIMARY, SaveSlotPreviewScript.CORRUPT)
	corrupt.error_message = "This save is corrupt or uses an unsupported schema."
	var controller := SystemWorkspaceController.new()
	var body := VBoxContainer.new()
	controller.set_save_previews([current, backup, corrupt])
	var actions: Array[Dictionary] = []
	controller.action_requested.connect(func(action: StringName, value: Variant) -> void: actions.append({"action": action, "value": value}))
	controller.present(body, view, PresentationSettings.new())
	var buttons := _buttons_in(body)
	var labels := _labels_in(body)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Day 2") and text.contains("land:4 12,9")), "valid save previews expose detached time and location facts")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Mira, Borin")), "valid save previews expose detached party identity")
	var current_load := buttons.filter(func(button: Button) -> bool: return button.text == "Load save")[0] as Button
	var backup_load := buttons.filter(func(button: Button) -> bool: return button.text == "Load backup")[0] as Button
	var disabled_loads := buttons.filter(func(button: Button) -> bool: return button.text == "Load save" and button.disabled)
	assert_equal(disabled_loads.size(), 1, "corrupt records remain visible with a disabled operation")
	assert_true(disabled_loads[0].tooltip_text.contains("corrupt"), "the corrupt record exposes an exact reason")
	current_load.pressed.emit()
	backup_load.pressed.emit()
	assert_equal(actions, [{"action": &"load", "value": "quick"}, {"action": &"load_backup", "value": "quick"}], "current and backup previews emit distinct host operations")
	body.free()


func _test_location_note_workspace() -> void:
	var view := GameView.new(4, true, null)
	view.party_summary = PartySummaryView.new()
	view.current_location_note = LocationNoteView.new("land:0", "Giant Mountain", &"land", 0, Vector2i(49, 15), "Watch the ridge.", 0, 0, true)
	view.location_notes = [
		view.current_location_note,
		LocationNoteView.new("land:0", "Giant Mountain", &"land", 0, Vector2i(12, 8), "A safe campsite.", 0, 1),
	]
	view.journal_entries = [
		JournalEntryView.new(4, "The road bends toward the mountain."),
		JournalEntryView.new(19, "A long authored entry remains readable. " + "Detail ".repeat(40)),
	]
	view.set_action_availability(&"set_location_note", true)
	view.set_action_availability(&"open_journal", false, "Authored journal entries are unavailable in this fixture.")
	view.set_action_availability(&"open_maps", false, "Player-map definitions are unavailable in this fixture.")
	var body := VBoxContainer.new()
	var controller := MapsJournalWorkspaceController.new()
	var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	controller.present(body, view, null)
	var editor := body.find_child("CurrentLocationNoteText", true, false) as TextEdit
	var save := body.find_child("SaveLocationNote", true, false) as Button
	var cancel := body.find_child("CancelLocationNoteEdit", true, false) as Button
	assert_not_null(editor, "the Journal route exposes a multiline current-location note editor")
	assert_equal(editor.text, "Watch the ridge.", "the editor begins from detached committed note text")
	assert_true(save.disabled, "an unchanged note cannot emit a redundant mutation")
	editor.text = "Watch the ridge after sundown."
	editor.text_changed.emit()
	assert_false(save.disabled, "changing the local draft enables the typed save action")
	save.pressed.emit()
	assert_equal(intents.size(), 1, "saving a location note emits one typed intent")
	var note_payload := intents[0].payload as PlayerIntent.LocationNotePayload
	assert_equal([intents[0].kind, note_payload.text], [PlayerIntent.Kind.SET_LOCATION_NOTE, "Watch the ridge after sundown."], "the presenter submits only detached text through the settled intent boundary")
	editor.text = "Unsaved change"
	editor.text_changed.emit()
	cancel.pressed.emit()
	assert_equal(editor.text, "Watch the ridge.", "Revert draft restores the last committed note without touching simulation")
	assert_equal(intents.size(), 1, "Revert draft remains presentation-owned")
	editor.text = "é".repeat(128)
	editor.text_changed.emit()
	assert_true(save.disabled, "the note editor prevents an oversized UTF-8 payload before submission")
	var labels := _labels_in(body)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("A safe campsite.")), "saved location notes remain readable while only the current record is editable")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Journal entry 4")), "the Journal route labels authored records by their stable source message identity")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("A long authored entry")), "long authored journal text remains present in the scrollable workspace")
	body.free()


func _test_player_map_workspace() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "the player-map presentation fixture loads through the independent package boundary")
	if not loaded.is_ok():
		return
	var media := ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new())
	var definition := loaded.content.world.player_map_by_classic_id(1)
	var session := GameSession.new()
	assert_equal(session.start(loaded.content, 1).state, SessionStep.State.COMPLETED, "the player-map view fixture starts from validated content")
	var map_snapshot := session.snapshot()
	map_snapshot.game_state.world.acquire_map(definition.id)
	assert_equal(session.restore(loaded.content, map_snapshot).state, SessionStep.State.COMPLETED, "acquired player-map state enters presentation through the public restore boundary")
	var view := session.view()
	assert_equal([view.acquired_player_maps.size(), view.acquired_player_maps[0].id, view.acquired_player_maps[0].cells.size()], [1, definition.id, 100], "the detached player-map view derives its 320-pixel crop from authoritative topology")
	assert_equal(view.player_map_menu_entries.size(), 4, "the detached menu retains every package player-map slot, not only acquired definitions")
	var body := VBoxContainer.new()
	var controller := MapsJournalWorkspaceController.new()
	controller.present(body, view, media)
	assert_not_null(body.find_child("AcquiredMapChooser", true, false), "the Journal route exposes a presentation-owned acquired-map chooser")
	var map_buttons: Array[Node] = body.find_child("AcquiredMapChooser", true, false).find_children("*", "Button", true, false)
	assert_equal(map_buttons.size(), 4, "Maps/Notes retains acquired and unavailable package menu slots")
	assert_true(map_buttons.any(func(button: Node) -> bool: return (button as Button).disabled and (button as Button).text == "Dungeon map unavailable"), "unacquired slots use their separate Classic unavailable name and cannot open")
	assert_not_null(body.find_child("PlayerMapCanvas", true, false), "the selected crop renders through the dedicated player-map canvas")
	var note := body.find_child("PlayerMapNote", true, false) as Label
	assert_not_null(note, "non-scrolling maps retain their authored note")
	if note != null:
		assert_contains(note.text, "deterministic map", "the displayed note comes from immutable player-map content")
	var immediate := PlayerMapInteraction.new()
	immediate.configure(view, media)
	var payloads: Array[Dictionary] = []
	immediate.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: payloads.append(body.to_data()))
	immediate.build(InteractionRequest.from_payload("player-map.immediate", InteractionRequest.ACKNOWLEDGE, {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id}))
	assert_not_null(immediate.find_child("ImmediatePlayerMap", true, false), "negative opcode 29 uses the same typed presenter as Journal browsing")
	var continue_button := immediate.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return (button as Button).text == "Continue")[0] as Button
	continue_button.pressed.emit()
	assert_equal(payloads, [{}], "the immediate player-map stage emits only the empty acknowledgement accepted by the VM")
	map_snapshot = session.snapshot()
	for player_map_definition: PlayerMapDefinition in loaded.content.world.player_maps():
		map_snapshot.game_state.world.acquire_map(player_map_definition.id)
	assert_equal(session.restore(loaded.content, map_snapshot).state, SessionStep.State.COMPLETED, "the complete acquired-map collection restores through the public session boundary")
	var complete_view := session.view()
	var views_by_mode: Dictionary = {}
	for player_map_view: PlayerMapView in complete_view.acquired_player_maps:
		views_by_mode[player_map_view.mode] = player_map_view
	assert_equal(views_by_mode.keys().size(), 4, "the fixture exercises land crop, dungeon crop, picture, and scrolling-text read models")
	var picture_view := views_by_mode[PlayerMapDefinition.PICTURE] as PlayerMapView
	assert_equal(picture_view.picture_rect, Rect2i(36, 24, 240, 160), "picture-backed maps preserve their authored destination rectangle")
	assert_true(picture_view.party_marker_visible, "picture-backed maps retain source playable-map identity for Castle's party marker")
	var picture_canvas := PlayerMapCanvas.new()
	picture_canvas.present(picture_view, media)
	assert_equal(picture_canvas.custom_minimum_size, Vector2(320, 320), "picture-backed maps use the public fixed Classic canvas contract")
	var dungeon_view := views_by_mode[PlayerMapDefinition.DUNGEON_CROP] as PlayerMapView
	assert_equal([dungeon_view.map_id, dungeon_view.cells.size()], ["dungeon:0", 100], "dungeon crop facts derive from the same authoritative topology as exploration")
	var scrolling_view := views_by_mode[PlayerMapDefinition.SCROLLING_TEXT] as PlayerMapView
	var scrolling_presenter := PlayerMapPresenter.new()
	scrolling_presenter.present(scrolling_view, media)
	assert_not_null(scrolling_presenter.find_child("PlayerMapScrollingText", true, false), "scrolling maps use their dedicated text stage")
	assert_contains((scrolling_presenter.find_child("PlayerMapScrollingText", true, false) as RichTextLabel).text, "turns north", "the exact packaged TEXT resource decodes into the scrolling map stage")
	assert_true(scrolling_presenter.find_child("PlayerMapNote", true, false) == null, "Castle's scrolling map path skips the ordinary map note")
	scrolling_presenter.free()
	picture_canvas.free()
	immediate.free()
	body.free()


func _test_battle_weapon_mode_component() -> void:
	var request := _fixture_request("battle.commands", InteractionRequest.COMBAT, {"actions": ["finish", "defend", "switch_weapon", "cast_spell", "use_item", "retreat"], "weaponMode": "missile", "weaponSwitch": {"enabled": true, "reason": "", "targetMode": "melee"}, "retreat": {"enabled": false, "reason": "An enemy is too close."}})
	var component := BattleInteraction.new()
	component.build(request)
	var buttons := _buttons_in(component)
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Finish"), "combat keeps a distinct Finish command")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Weapon: Melee"), "combat keeps the source-backed weapon toggle")
	var escape := buttons.filter(func(button: Button) -> bool: return button.text == "Escape")
	assert_equal(escape.size(), 1, "combat exposes one Escape command")
	if not escape.is_empty(): assert_true(escape[0].disabled and not escape[0].tooltip_text.is_empty(), "unavailable retreat carries a typed reason")
	assert_false(buttons.any(func(button: Button) -> bool: return button.text.begins_with("N ") or button.text.begins_with("Leave ")), "movement is owned by the battlefield instead of permanent direction buttons")
	assert_true(_labels_in(component).any(func(text: String) -> bool: return text.contains("Goblin")), "the target panel is visible beside the command deck")
	component.free()
func _test_battle_typed_option_contracts() -> void:
	var request := _fixture_request("battle.unavailable", InteractionRequest.COMBAT, {"actions": ["cast_spell", "use_item", "use_scroll"], "spellCasts": [], "itemCasts": [], "scrollCasts": [], "spellCastReason": "No legal spell.", "itemCastReason": "No legal item.", "scrollCastReason": "No legal scroll."})
	var component := BattleInteraction.new()
	component.build(request)
	for label: String in ["Spells", "Items", "Scrolls"]:
		var buttons := _buttons_in(component).filter(func(button: Button) -> bool: return button.text == label)
		assert_equal(buttons.size(), 1, "%s has one typed control" % label)
		if not buttons.is_empty(): assert_true(buttons[0].disabled, "%s is disabled by core availability" % label)
	component.free()
func _test_shop_component() -> void:
	var request := _fixture_request("shop.fixture", InteractionRequest.SHOP, {
		"partyGold": 19,
		"inflationPercent": 125,
		"identifyPrice": 20,
		"characters": [{"id": "character.one", "name": "Hero", "inventory": [
			{"instanceId": "item.unknown", "itemId": "classic.item.40", "name": "Runed wand", "sellPrice": 0, "identified": false, "equipped": false, "charges": 2, "canSell": true, "sellReason": "", "canIdentify": false, "identifyReason": "Identification costs 20 gold."},
			{"instanceId": "item.equipped", "itemId": "classic.item.1", "name": "Sword", "sellPrice": 25, "identified": true, "equipped": true, "charges": -1, "canSell": false, "sellReason": "Unequip this item before selling it.", "canIdentify": false, "identifyReason": "This item is already identified."},
		]}],
		"stock": [{"stockKey": "buyback:classic.item.5", "index": -1, "itemId": "classic.item.5", "name": "Dagger", "buyPrice": 40, "quantity": 1, "canBuy": false, "buyReason": "The party cannot afford this item."}],
	})
	var component := ShopInteraction.new()
	component.build(request)
	var buttons := _direct_buttons_in(component)
	var buy_button: Button = null
	var unknown_sell: Button = null
	var identify_button: Button = null
	var equipped_sell: Button = null
	for button: Button in buttons:
		if button.text.begins_with("Dagger"):
			buy_button = button
		elif button.text.begins_with("Sell Runed wand"):
			unknown_sell = button
		elif button.text.begins_with("Identify Runed wand"):
			identify_button = button
		elif button.text.begins_with("Sell Sword"):
			equipped_sell = button
	assert_not_null(buy_button, "shop buyback stock renders through the typed component")
	assert_true(buy_button.disabled and buy_button.tooltip_text.contains("afford"), "unaffordable stock exposes its core-owned reason")
	assert_not_null(unknown_sell, "unidentified inventory uses the player-knowable item name")
	assert_not_null(identify_button, "unknown items expose paid shop identification")
	assert_true(identify_button.disabled and identify_button.tooltip_text.contains("20 gold"), "paid identification exposes the exact affordability blocker")
	assert_not_null(equipped_sell, "equipped items remain visible in the sale list")
	assert_true(equipped_sell.disabled and equipped_sell.tooltip_text.contains("Unequip"), "ordinary sale cannot bypass the equipment workflow")
	component.free()


func _test_temple_component() -> void:
	var request := _fixture_request("temple.fixture", InteractionRequest.TEMPLE, {
		"costPercent": 125,
		"selectedCharacterId": "character.two",
		"pooledWealth": {"gold": 100, "gems": 0, "jewelry": 0},
		"characters": [
			{"id": "character.one", "name": "Hero", "portraitId": "portrait.hero", "currentHealth": 4, "maximumHealth": 12, "personalGold": 300, "availableGold": 400, "load": 20, "maximumLoad": 100, "conditions": [{"index": 9, "name": "Poisoned", "value": 3}]},
			{"id": "character.two", "name": "Poor Hero", "portraitId": "portrait.poor", "currentHealth": -12, "maximumHealth": 10, "personalGold": 0, "availableGold": 100, "load": 0, "maximumLoad": 100, "conditions": []},
		],
		"services": [
			{"id": "heal-small", "label": "Heal Small Wounds", "description": "Restore 1-8 stamina.", "cost": 312},
			{"id": "revive-dead", "label": "Revive Dead", "description": "Restore an eligible dead character.", "cost": 1875},
		],
	})
	var component := TempleInteraction.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons := _direct_buttons_in(component)
	var heal_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Heal Small Wounds"))[0]
	var revive_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Revive Dead"))[0]
	assert_true(heal_button.disabled, "the request's selected character identity is restored before affordability is rendered")
	assert_true(revive_button.disabled and revive_button.tooltip_text.contains("1875 gold"), "unaffordable temple services remain visible with the exact blocker")
	var picker := component.get_children().filter(func(child: Node) -> bool: return child is OptionButton)[0] as OptionButton
	assert_equal(String(picker.get_selected_metadata()), "character.two", "the presenter preserves the save-owned selected temple character")
	var summary := component.get_children().filter(func(child: Node) -> bool: return child is Label and child.text.contains("Poor Hero"))[0] as Label
	assert_true(summary.text.contains("HP -12/10"), "the temple summary exposes the selected character's source health state")
	picker.select(0)
	picker.item_selected.emit(0)
	assert_false(heal_button.disabled, "changing the selected character recalculates affordability from detached values")
	heal_button.pressed.emit()
	var pool_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Pool party wealth")[0]
	pool_button.pressed.emit()
	assert_equal(submitted, [
		{"action": "service", "serviceId": "heal-small", "characterId": "character.one"},
		{"action": "pool", "characterId": "character.one"},
	], "the temple presenter emits typed service and wealth responses with the current stable character identity")
	component.free()


func _test_bank_component() -> void:
	var request := _fixture_request("bank.fixture", InteractionRequest.BANK, {
		"selectedCharacterId": "character.one",
		"pooledWealth": {"gold": 35, "gems": 2, "jewelry": 1},
		"bankedWealth": {"gold": 0, "gems": 0, "jewelry": 0},
		"pool": {"enabled": true, "reason": ""},
		"share": {"enabled": false, "reason": "No adventurer can carry another pooled denomination."},
		"characters": [{
			"id": "character.one",
			"name": "Hero",
			"wealth": {"gold": 10, "gems": 1, "jewelry": 0},
			"load": 11,
			"maximumLoad": 20,
			"transfers": [
				{"denomination": "gold", "amount": 5, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
				{"denomination": "gems", "amount": 1, "toPool": {"enabled": true, "reason": ""}, "toCharacter": {"enabled": true, "reason": ""}},
				{"denomination": "jewelry", "amount": 1, "toPool": {"enabled": false, "reason": "Hero does not carry that amount."}, "toCharacter": {"enabled": false, "reason": "Hero cannot carry that denomination."}},
			],
		}],
	})
	var component := BankInteraction.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons := _buttons_in(component)
	var labels := _labels_in(component)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("35 gold") and text.contains("2 gems") and text.contains("1 jewelry")), "bank workspace renders every pooled denomination")
	var share_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Share pooled wealth")[0]
	assert_true(share_button.disabled and share_button.tooltip_text.contains("can carry"), "bank workspace displays the core-owned Share blocker")
	var to_character: Array[Button] = buttons.filter(func(button: Button) -> bool: return button.text == "To Hero")
	assert_equal(to_character.size(), 3, "bank-backed Swap exposes all three Classic denomination transfers")
	assert_true(to_character[2].disabled and to_character[2].tooltip_text.contains("cannot carry"), "bank presentation does not duplicate jewelry capacity rules")
	to_character[0].pressed.emit()
	var leave_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Done")[0]
	leave_button.pressed.emit()
	assert_equal(submitted, [
		{"action": "to-character", "characterId": "character.one", "denomination": "gold", "amount": 5},
		{"action": "leave"},
	], "bank presenter emits exact typed Swap and Done responses")
	component.free()

	var departure_request := InteractionRequest.from_payload("departure.fixture", InteractionRequest.POOLED_WEALTH_DEPARTURE, request.body.to_data().merged({"mode": "departure"}, true))
	var departure_component := BankInteraction.new()
	var departure_payloads: Array[Dictionary] = []
	departure_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: departure_payloads.append(body.to_data()))
	departure_component.build(departure_request)
	var departure_labels := _labels_in(departure_component)
	assert_true(departure_labels.any(func(text: String) -> bool: return text.contains("Distribute pooled wealth before leaving")), "pooled departure renders its distinct Classic workflow heading")
	assert_true(departure_labels.any(func(text: String) -> bool: return text.contains("continues this movement attempt")), "pooled departure explains the ordinary checkmoneypool Done outcome")
	assert_false(departure_labels.any(func(text: String) -> bool: return text.contains("Deposited until departure")), "pooled departure does not present bank-only state as part of no-bank Swap")
	var departure_done := departure_component.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return (button as Button).text == "Done")[0] as Button
	departure_done.pressed.emit()
	assert_equal(departure_payloads, [{"action": "leave"}], "pooled departure emits the same exact typed Done payload as Swap")
	var typed_response := InteractionPresenter.response_for(departure_request, InteractionResponse.BankBody.new(&"leave"))
	assert_equal([typed_response.request_id, typed_response.kind, typed_response.body.to_data()], ["departure.fixture", InteractionRequest.POOLED_WEALTH_DEPARTURE, {"action": "leave"}], "pooled departure preserves request identity through the typed presenter boundary")
	departure_component.free()


func _test_money_workspace_audio() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var view := GameView.new(1, true, null)
	view.campaign_summary = CampaignSummaryView.new()
	router.present(view)
	var sounds: Array[Dictionary] = []
	router.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool) -> void: sounds.append({"soundId": sound_id, "waitForCompletion": wait_for_completion, "stopExisting": stop_existing}))
	router.open_screen(&"services")
	router.open_screen(&"services")
	router.open_screen(&"exploration")
	assert_equal(sounds, [
		{"soundId": 141, "waitForCompletion": false, "stopExisting": false},
		{"soundId": 3003, "waitForCompletion": false, "stopExisting": true},
		{"soundId": 141, "waitForCompletion": false, "stopExisting": false},
	], "ordinary Swap route requests the source button, quiet-and-open, and Done sequence without duplicates")
	view.pending_interaction = _fixture_request("shop.audio", InteractionRequest.SHOP)
	router.present(view)
	router.open_screen(&"services")
	assert_equal(sounds.size(), 3, "a Services route opened for a typed location service does not masquerade as ordinary Swap")
	var audio := ClassicAudioPresenter.new()
	var observed: Array[int] = []
	audio.sound_observed.connect(func(sound_id: int) -> void: observed.append(sound_id))
	audio._processing_sounds = true
	audio._pending_sounds.append({"stream": null, "waitForCompletion": true})
	audio.present_sound(3003, null, false, true)
	assert_equal([audio.last_sound_id, observed], [3003, [3003]], "presentation-owned workspace audio uses the same explicit audio presenter path as session events")
	assert_false(audio._processing_sounds, "quiet-and-open cancels an in-flight wait state instead of deadlocking the sound queue")
	assert_true(audio._pending_sounds.is_empty(), "quiet-and-open discards pre-modal queued sounds")
	audio.free()
	router.free()


func _test_route_catalog() -> void:
	assert_equal(UiRouteCatalog.ROUTES.size(), 9, "the canonical route registry contains all nine workspaces")
	var ids: Dictionary = {}
	var shortcuts: Dictionary = {}
	var primary_count: int = 0
	for route: Dictionary in UiRouteCatalog.ROUTES:
		ids[route["id"]] = true
		shortcuts[route["shortcut"]] = true
		primary_count += 1 if bool(route["primary"]) else 0
		assert_false(String(route.get("description", "")).is_empty(), "every route has presentation guidance")
		assert_true(ResourceLoader.exists(String(route.get("scene", "")), "PackedScene"), "every route owns a scene-backed workspace")
	assert_equal(ids.size(), 9, "route identifiers are unique")
	assert_equal(shortcuts.size(), 9, "route shortcuts are unique")
	assert_equal(primary_count, 6, "compact and standard layouts keep six primary workspaces")


func _test_layout_profiles() -> void:
	assert_equal(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.COMPACT, "800x600 uses compact layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.STANDARD, "960x600 uses standard layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1280x720 uses wide layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1920, 1080), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1920x1080 remains wide after automatic density")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_125), 1.25, "explicit interface density is independent of viewport")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_150), 1.5, "150 percent interface density is supported")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(compact.party_width, 208.0, "compact Classic roster uses the specified width")
	assert_equal(compact.bottom_height, 156.0, "compact Classic textbox uses the specified height")
	var standard := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(standard.party_width, 256.0, "standard Classic roster uses the specified width")
	assert_equal(standard.bottom_height, 176.0, "standard Classic textbox uses the specified height")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1600, 900), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 2, "large automatic layouts may use exact 2x bitmap controls")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1599, 899), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 1, "bitmap controls remain 1x below the approved threshold")


func _test_settings_schema_and_migration() -> void:
	var settings := PresentationSettings.new()
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_125
	settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.text_scale = 1.5
	settings.auto_switch_to_melee = false
	settings.exploration_speed_percent = 250
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-five presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately")
	assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent")
	assert_false(restored.auto_switch_to_melee, "Auto Weapon Switch persists as an application preference rather than battle state")
	assert_equal(restored.exploration_speed_percent, 250, "exploration speed persists independently of simulation state")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true})
	assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density")
	assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")
	assert_true(version_two.auto_switch_to_melee, "legacy settings inherit Castle's bundled default-on Auto Weapon Switch preference")
	var version_three := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 3, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_150, "windowMode": PresentationSettings.WINDOWED})
	assert_not_null(version_three, "schema-three settings migrate")
	assert_equal([version_three.ui_scale_mode, version_three.auto_switch_to_melee], [PresentationSettings.UI_SCALE_150, true], "schema-three settings preserve prior display fields and inherit Castle's default-on preference")
	var version_four := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 4, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": false})
	assert_not_null(version_four, "schema-four settings migrate")
	assert_equal(version_four.exploration_speed_percent, 100, "older settings inherit the stable exploration cadence")
	var malformed_current := settings.to_data()
	malformed_current.erase("autoSwitchToMelee")
	assert_equal(PresentationSettings.from_data(malformed_current), null, "schema-four settings reject a missing Auto Weapon Switch field")
	var move_body := InteractionResponse.CombatBody.new(&"move", "character.test")
	move_body.destination = Vector2i(46, 45)
	move_body.has_destination = true
	var preferred_move := RealmzApplication.combat_body_with_preferences(move_body, restored)
	assert_false(preferred_move.auto_switch_to_melee, "the application injects the persisted preference only into a typed manual movement response")
	var attack_body := InteractionResponse.CombatBody.new(&"attack", "character.test", "monster.test")
	var preferred_attack := RealmzApplication.combat_body_with_preferences(attack_body, restored)
	assert_false(preferred_attack.auto_switch_to_melee, "direct attacks and automatic combat paths never consult Auto Weapon Switch")


func _test_movement_input() -> void:
	UiInputActions.ensure_defaults()
	var expected: Dictionary = {
		&"realmz_move_up": Vector2i.UP,
		&"realmz_move_up_right": Vector2i(1, -1),
		&"realmz_move_right": Vector2i.RIGHT,
		&"realmz_move_down_right": Vector2i(1, 1),
		&"realmz_move_down": Vector2i.DOWN,
		&"realmz_move_down_left": Vector2i(-1, 1),
		&"realmz_move_left": Vector2i.LEFT,
		&"realmz_move_up_left": Vector2i(-1, -1),
	}
	for action: StringName in expected:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		assert_equal(UiInputActions.movement_direction(event), expected[action], "%s resolves to its complete movement vector" % action)
		event.pressed = false
		assert_equal(UiInputActions.released_movement_direction(event), expected[action], "%s release stops the matching held movement" % action)
	var held := HeldMovementControllerScript.new()
	var pulses: Array[Vector2i] = []
	held.movement_requested.connect(func(direction: Vector2i) -> void:
		pulses.append(direction)
		held.advance(1.0)
	)
	held.set_speed_percent(400)
	held.start(&"keyboard", Vector2i.RIGHT)
	assert_equal(pulses, [Vector2i.RIGHT], "the first held movement step is immediate")
	assert_equal(held.active_source(), &"keyboard", "the scheduler exposes its presentation-owned input source")
	held.advance(0.049)
	assert_equal(pulses.size(), 1, "the 400 percent cadence waits for its complete interval")
	held.advance(0.002)
	assert_equal(pulses.size(), 2, "the 400 percent cadence repeats after 50 milliseconds")
	held.advance(1.0)
	assert_equal(pulses.size(), 3, "a slow frame emits one step rather than a queued burst")
	assert_false(held.request_in_progress(), "a synchronous movement callback settles before the next interval begins")
	held.set_speed_percent(25)
	assert_equal(held.interval_seconds(), 0.8, "the slowest movement setting uses the documented 800 millisecond interval")
	held.set_speed_percent(100)
	assert_equal(held.interval_seconds(), 0.2, "the default movement setting sustains five scheduled steps per second")
	held.stop(&"keyboard")
	held.advance(1.0)
	assert_equal(pulses.size(), 3, "release stops further held movement")
	held.free()


func _test_fast_spell_input() -> void:
	var one := InputEventKey.new()
	one.physical_keycode = KEY_1
	one.pressed = true
	assert_equal(UiInputActions.fast_spell_slot(one), 0, "top-row 1 selects Castle Fast Spell slot one")
	var zero := InputEventKey.new()
	zero.physical_keycode = KEY_0
	zero.pressed = true
	assert_equal(UiInputActions.fast_spell_slot(zero), 9, "top-row 0 selects Castle Fast Spell slot ten")
	zero.ctrl_pressed = true
	assert_true(UiInputActions.fast_spell_use_requested(zero), "Ctrl-number is the Windows equivalent of Castle Command-number activation")
	var keypad := InputEventKey.new()
	keypad.physical_keycode = KEY_KP_1
	keypad.pressed = true
	assert_equal(UiInputActions.fast_spell_slot(keypad), -1, "numeric keypad movement never aliases a top-row Fast Spell")
	var released := InputEventKey.new()
	released.physical_keycode = KEY_2
	assert_equal(UiInputActions.fast_spell_slot(released), -1, "a key release cannot display or activate a Fast Spell a second time")
	var route_binding: Dictionary = UiInputActions.DEFINITIONS.filter(func(definition: Dictionary) -> bool: return definition["id"] == &"ui_screen_explore")[0]
	assert_true(bool(route_binding.get("alt", false)), "Rebuilt route shortcuts move behind Alt-number so Classic Fast Spells own bare 1–0")
	var keypad_bindings: Dictionary = {}
	for definition: Dictionary in UiInputActions.DEFINITIONS:
		keypad_bindings[definition["id"]] = definition["keys"]
	assert_true(KEY_KP_7 in keypad_bindings[&"realmz_move_up_left"], "keypad 7 owns northwest land movement")
	assert_true(KEY_KP_9 in keypad_bindings[&"realmz_move_up_right"], "keypad 9 owns northeast land movement")
	assert_true(KEY_KP_1 in keypad_bindings[&"realmz_move_down_left"], "keypad 1 owns southwest land movement")
	assert_true(KEY_KP_3 in keypad_bindings[&"realmz_move_down_right"], "keypad 3 owns southeast land movement")


func _test_safe_item_display() -> void:
	var definition := ItemDefinition.new("classic.item.607", 607, "Improvement", "Potion", "Raises a random attribute.")
	definition.icon_id = 555
	definition.cost = 7500
	definition.initial_charges = 1
	definition.item_type = 21
	definition.cursed_item_id = "classic.item.608"
	var hidden := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, false), definition)
	assert_equal(hidden.name, "Potion", "unidentified items expose only the player-knowable name")
	assert_false(hidden.description.contains("random attribute"), "unidentified items do not leak effect text")
	assert_equal(hidden.value, 0, "unidentified items do not leak identified value")
	assert_equal(hidden.definition_id, "", "unidentified items do not leak stable definition identity")
	assert_equal(hidden.classic_id, 0, "unidentified items do not leak Classic item identity")
	assert_equal(hidden.icon_id, 555, "the authored content icon identity remains available to presentation")
	assert_equal(hidden.icon_resource_type, "cicn", "item icons carry Castle's exact lowercase resource type for collision-free lookup")
	assert_equal(hidden.item_type, 21, "the player-visible item type remains available while identity is hidden")
	var known := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, true), definition)
	assert_equal(known.name, "Improvement", "identified items expose their identified name")
	assert_contains(known.description, "random attribute", "identified items expose their description")
	assert_equal(known.definition_id, definition.id, "identified items expose their stable definition identity")
	definition.hands = 1
	definition.damage_bonus = 2
	definition.vs_small = 6
	definition.magic_resistance_bonus = 5
	definition.heat = 4
	definition.special_1 = 121
	known = ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, true), definition)
	assert_true(known.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Damage" and fact.value == "3–8"), "identified Describe facts preserve Castle's damage-range convention")
	assert_true(known.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Magic resistance" and fact.value == "+5"), "identified Describe facts expose source-backed magical modifiers")
	assert_true(known.properties.any(func(property: String) -> bool: return property.contains("special damage")), "identified Describe facts expose Castle's special-damage notice")
	assert_true(known.properties.any(func(property: String) -> bool: return property.contains("to-hit bonus")), "identified Describe facts expose Castle's penetration-weapon explanation")
	var still_hidden := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, false), definition)
	assert_false(still_hidden.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Magic resistance"), "unidentified Describe facts do not reveal identified-only modifiers")
	assert_true(still_hidden.facts.any(func(fact: ItemFactView) -> bool: return fact.label == "Damage"), "Castle's always-visible damage range remains visible before identification")
	var decoy := ItemDefinition.new("classic.item.608", 608, "Fine Blade", "Sword", "A finely balanced sword.")
	decoy.icon_id = 999
	decoy.damage_bonus = 1
	decoy.vs_small = 4
	var cursed := ItemDefinition.new("classic.item.609", 609, "Cursed Blade", "Sword", "The revealed blade drains its bearer.")
	cursed.icon_id = 555
	cursed.damage_bonus = -2
	cursed.vs_small = 8
	cursed.cursed_item_id = decoy.id
	var content := RealmzContent.new("item-display", "0".repeat(64), "item-display", "realmz-classic-1", "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [], [], [decoy, cursed])
	var bearer := CharacterState.new("item-display.character", "Bearer", 10, 10)
	bearer.set_inventory([ItemInstance.new("item-display.curse", cursed.id, 0, false, true)])
	var concealed := CharacterView.new(bearer, content).items[0]
	assert_equal([concealed.name, concealed.icon_id, concealed.definition_id], [decoy.name, cursed.icon_id, decoy.id], "an unworn cursed item uses Castle's linked decoy record while retaining the original icon")
	assert_false(concealed.curse_revealed, "the detached view does not disclose an unworn curse")
	bearer.inventory()[0].equipped = true
	var revealed := CharacterView.new(bearer, content).items[0]
	assert_equal([revealed.name, revealed.icon_id, revealed.definition_id], [cursed.name, cursed.icon_id, cursed.id], "wearing a cursed item reveals the original record Castle actually applies")
	assert_true(revealed.curse_revealed and revealed.properties.any(func(property: String) -> bool: return property.contains("cannot be removed")), "a revealed curse explains its source-backed removal restriction")


func _test_action_availability() -> void:
	var view := GameView.new(1, true, null)
	view.set_action_availability(&"search", true)
	assert_true(view.availability(&"search").enabled, "declared available actions are enabled")
	assert_equal(view.availability(&"search").reason, "", "enabled actions carry no misleading disabled reason")
	var unknown := view.availability(&"imaginary_action")
	assert_false(unknown.enabled, "undeclared actions remain disabled")
	assert_contains(unknown.reason, "unavailable", "undeclared actions explain their state")


func _test_fixture_gallery_coverage() -> void:
	for interaction: StringName in ClassicUiFixtureGallery.INTERACTIONS:
		var request := ClassicUiFixtureGallery.request_for(interaction)
		assert_not_null(request, "gallery interaction %s decodes through its exact typed contract" % interaction)
		if request != null:
			assert_true(request.is_supported_kind(), "gallery interaction %s is a supported typed request" % interaction)
	var age_component := AgeUpdateInteraction.new()
	age_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.AGE_UPDATE))
	assert_true(age_component.get_child_count() >= 4, "the Classic age update renders identity, band, changed statistics, and a response")
	assert_true(age_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Continue"), "the blocking age update exposes one keyboard-focusable continuation")
	age_component.free()
	var recovery_component := TreasureDistributionInteraction.new()
	recovery_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"))
	assert_equal(recovery_component.get_child_count(), 3, "battle recovery renders item detail, an eligible recipient, and leave-behind action")
	assert_true(recovery_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("7 charges")), "battle recovery exposes the exact preserved charge count")
	assert_true(recovery_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and not child.disabled), "nominal battle recovery exposes its rules-authorized recipient as an active control")
	recovery_component.free()
	var ordinary_component := TreasureDistributionInteraction.new()
	ordinary_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION))
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("125 gold")), "ordinary booty exposes the detached pooled denominations")
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and not child.disabled), "ordinary booty exposes rules-owned exact-item assignment")
	assert_true(ordinary_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Done"), "ordinary booty has one typed completion path")
	ordinary_component.free()
	var capacity_component := TreasureDistributionInteraction.new()
	capacity_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unavailable"))
	assert_true(capacity_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Give to Hero" and child.disabled and child.tooltip_text.contains("full")), "capacity-blocked booty retains the core-provided disabled reason")
	capacity_component.free()
	var level_component := LevelUpInteraction.new()
	level_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP))
	assert_true(level_component.get_children().any(func(child: Node) -> bool: return child is Label and child.text.contains("level 5")), "the level result presents its committed character level")
	assert_true(level_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Continue"), "the level result exposes one typed acknowledgement")
	level_component.free()
	var spell_component := LevelUpInteraction.new()
	spell_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"))
	assert_true(spell_component.get_children().any(func(child: Node) -> bool: return child is ItemList and child.item_count == 4), "the level spell stage renders the complete detached candidate list")
	assert_true(spell_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Confirm spell selection"), "the spell stage exposes one typed confirmation")
	spell_component.free()
	var roster := load("res://src/presentation/screens/classic_party_roster.tscn").instantiate() as ClassicPartyRoster
	(Engine.get_main_loop() as SceneTree).root.add_child(roster)
	var selection_view := GameView.new(1, true, null)
	selection_view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)), CharacterView.new(CharacterState.new("mage", "Mage", 6, 9)), CharacterView.new(CharacterState.new("dead", "Dead", 0, 10))]
	var request := _fixture_request("fixture.party-pick", InteractionRequest.CHARACTER_SELECTION, {"count": 2, "eligible": [{"id": "hero", "name": "Hero", "currentHealth": 8, "maximumHealth": 10}, {"id": "mage", "name": "Mage", "currentHealth": 6, "maximumHealth": 9}]})
	var selection_component := SelectionInteraction.new()
	selection_component.build(request)
	assert_true(_buttons_in(selection_component).is_empty(), "the mandatory Classic character check exposes no cancel or premature-submit control")
	selection_component.free()
	var selections: Array[Array] = []
	roster.character_selection_completed.connect(func(ids: Array[String]) -> void: selections.append(ids))
	roster.present(selection_view)
	roster.present_character_selection(request)
	var rows := _buttons_in(roster)
	assert_true(rows[2].disabled, "the Party-list picker visibly rejects a character absent from the typed eligibility set")
	rows[1].pressed.emit()
	assert_equal(_labels_in(roster).filter(func(text: String) -> bool: return text == "2"), ["2"], "the first of two Classic picks is stamped with the countdown number two")
	rows = _buttons_in(roster)
	rows[1].pressed.emit()
	assert_false(_labels_in(roster).has("2"), "clicking a numbered portrait removes that pick and restores the remaining count")
	rows = _buttons_in(roster)
	rows[1].pressed.emit()
	rows = _buttons_in(roster)
	rows[0].pressed.emit()
	assert_equal(selections, [["hero", "mage"]], "the exact source-authored count auto-submits stable identities in Classic party order")
	roster.present_character_selection(null)
	assert_false(_labels_in(roster).any(func(text: String) -> bool: return text in ["1", "2"]), "leaving the interaction clears temporary Party-list numbering")
	roster.free()


func _test_lifecycle_interaction() -> void:
	var request := ApplicationLifecycleScript.end_adventure_request(false)
	assert_equal([request.kind, request.body.to_data()["inCombat"], request.body.to_data()["options"].size()], [InteractionRequest.SESSION_LIFECYCLE, false, 3], "field End Adventure exposes explicit save, discard, and cancel operations")
	assert_not_null(InteractionRequest.from_data(request.to_data()), "the typed lifecycle request retains the established interaction wire shape")
	var component := LifecycleInteractionScript.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons := _buttons_in(component)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and end adventure", "End adventure without saving", "Cancel"], "the dedicated presenter does not reinterpret lifecycle choices as scenario options")
	buttons[2].pressed.emit()
	assert_equal(submitted, [{"action": "cancel"}], "Cancel emits one typed host response")
	assert_equal(ApplicationLifecycleScript.response_action(request, InteractionPresenter.response_for(request, InteractionResponse.LifecycleBody.new(&"cancel"))), &"cancel", "the host accepts only an action declared by its request")
	assert_equal(ApplicationLifecycleScript.response_action(request, InteractionResponse.from_data(request.request_id, request.kind, {"action": "invented"})), &"", "undeclared lifecycle actions fail explicitly")
	assert_false(ApplicationLifecycleScript.allows_close(&"save-and-end", false), "a rejected save cannot close the active session")
	assert_true(ApplicationLifecycleScript.allows_close(&"save-and-end", true), "a validated save permits the requested close")
	assert_true(ApplicationLifecycleScript.allows_close(&"end-without-saving"), "explicit discard permits close without a repository write")
	assert_false(ApplicationLifecycleScript.allows_close(&"cancel"), "Cancel never closes the active session")
	var operation_order: Array[String] = []
	var failed_save := ApplicationLifecycleScript.execute_end_adventure(&"save-and-end", func() -> bool: operation_order.append("save"); return false, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(1))
	assert_equal([failed_save["state"], operation_order], [&"save-failed", ["save"]], "save failure suppresses close instead of tearing down the active session")
	operation_order.clear()
	var discarded := ApplicationLifecycleScript.execute_end_adventure(&"end-without-saving", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(2))
	assert_equal([discarded["state"], operation_order], [&"closed", ["close"]], "explicit discard closes once without touching the save repository")
	operation_order.clear()
	var hook_request := InteractionRequest.acknowledge("fixture.end-hook", "The End Adventure hook runs.")
	var pending := ApplicationLifecycleScript.execute_end_adventure(&"end-without-saving", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.waiting(3, hook_request))
	assert_equal([pending["state"], pending["step"].interaction.request_id, operation_order], [&"pending", hook_request.request_id, ["close"]], "the host releases its confirmation while the session owns a saveable End Adventure hook interaction")
	operation_order.clear()
	var cancelled := ApplicationLifecycleScript.execute_end_adventure(&"cancel", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(3))
	assert_equal([cancelled["state"], operation_order], [&"cancelled", []], "Cancel invokes neither persistence nor session teardown")
	component.free()
	var combat_request := ApplicationLifecycleScript.end_adventure_request(true)
	assert_equal(combat_request.body.to_data()["options"].size(), 2, "battle End Adventure never offers an invalid combat save")
	assert_false(combat_request.body.to_data()["options"].any(func(option: Dictionary) -> bool: return StringName(option["action"]) == &"save-and-end"), "battle End Adventure follows Castle's no-save branch")
	var quit_request := ApplicationLifecycleScript.quit_application_request(true, false)
	assert_equal([quit_request.body.to_data()["operation"], quit_request.body.to_data()["options"].size()], ["quit-application", 3], "field Quit is a distinct typed host operation with save, discard, and cancel")
	var quit_component := LifecycleInteractionScript.new()
	quit_component.build(quit_request)
	buttons = _buttons_in(quit_component)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and quit Realmz Rebuilt", "Quit Realmz Rebuilt", "Cancel"], "Quit uses explicit modern host wording instead of pretending to know Castle's resource text")
	var quit_order: Array[String] = []
	assert_equal(ApplicationLifecycleScript.execute_quit(&"save-and-quit", func() -> bool: quit_order.append("save"); return false, func() -> void: quit_order.append("quit")), &"save-failed", "failed Quit save keeps the application open")
	assert_equal(quit_order, ["save"], "failed Quit save never invokes process termination")
	quit_order.clear()
	assert_equal(ApplicationLifecycleScript.execute_quit(&"quit-without-saving", func() -> bool: quit_order.append("save"); return true, func() -> void: quit_order.append("quit")), &"quit-requested", "explicit no-save Quit requests process termination")
	assert_equal(quit_order, ["quit"], "no-save Quit bypasses persistence")
	quit_order.clear()
	assert_equal(ApplicationLifecycleScript.execute_quit(&"cancel", func() -> bool: quit_order.append("save"); return true, func() -> void: quit_order.append("quit")), &"cancelled", "Quit Cancel leaves both persistence and process state untouched")
	assert_equal(quit_order, [], "Quit Cancel invokes no host operations")
	var combat_quit := ApplicationLifecycleScript.quit_application_request(true, true)
	assert_equal(combat_quit.body.to_data()["options"].size(), 2, "battle Quit preserves Castle's confirm-or-cancel shape without offering save")
	assert_false(combat_quit.body.to_data()["options"].any(func(option: Dictionary) -> bool: return StringName(option["action"]) == &"save-and-quit"), "battle Quit cannot save before termination")
	var idle_quit := ApplicationLifecycleScript.quit_application_request(false, false)
	assert_equal(idle_quit.body.to_data()["options"].size(), 2, "Quit without an active session offers only quit and cancel")
	quit_component.free()

func _test_classic_choice_context() -> void:
	var journal_request := InteractionRequest.from_payload("journal-text", InteractionRequest.ACKNOWLEDGE, {"prompt": "A source message", "journalEligible": true, "journalRecorded": false})
	var journal_component := TextChoiceInteraction.new()
	var journal_payloads: Array[Dictionary] = []
	journal_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: journal_payloads.append(body.to_data()))
	journal_component.build(journal_request)
	var journal_buttons: Array[Node] = journal_component.find_children("*", "Button", true, false)
	assert_equal(journal_buttons.map(func(button: Button) -> String: return button.text), ["Take note", "Continue"], "eligible Classic text offers source-shaped journal discovery before ordinary continuation")
	(journal_buttons[0] as Button).pressed.emit()
	assert_equal(journal_payloads, [{"takeNote": true}], "Take note emits only the typed acknowledgement selection")
	journal_component.free()


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _test_exploration_map_camera_preserves_viewport_geometry() -> void:
	var viewport_size := Vector2(960.0, 600.0)
	var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
	var stage_rect := Rect2(
		Vector2(0.0, profile.menu_height),
		Vector2(
			maxf(320.0, viewport_size.x - profile.party_width),
			maxf(220.0, viewport_size.y - profile.menu_height - profile.bottom_height)
		)
	)
	var expected_viewport_rect := stage_rect.grow(-8.0)
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	var map_presenter := application.get_node("ExplorationMap") as ClassicMapPresenter
	assert_not_null(map_presenter, "the canonical application owns one clipped exploration map presenter")
	if map_presenter == null:
		application.free()
		return
	map_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	map_presenter.position = expected_viewport_rect.position
	map_presenter.size = expected_viewport_rect.size
	var viewport_rect := Rect2(map_presenter.position, map_presenter.size)
	var viewport_parent := map_presenter.get_parent()
	var viewport_cells := ClassicMapPresenter.viewport_cells_for(map_presenter.size, map_presenter.map_origin.y, map_presenter.cell_size)
	var draw_origin := ClassicMapPresenter.map_draw_origin_for(map_presenter.size, map_presenter.map_origin, map_presenter.cell_size, viewport_cells)
	var map_size := Vector2i(90, 90)
	var positions: Array[Vector2i] = [Vector2i(0, 45), Vector2i(45, 45), Vector2i(89, 45), Vector2i(45, 0), Vector2i(45, 89)]
	var cameras: Array[Vector2i] = []
	var party_rects: Array[Rect2] = []
	for coordinate: Vector2i in positions:
		var cells: Array[MapCellView] = [MapCellView.new(coordinate, "fixture.terrain", 1, "fixture.tileset", true, false, true, true, false, false, [], {}, {}, {})]
		var map_view := MapView.new("fixture.map", "Synthetic Map", &"land", map_size.x, map_size.y, coordinate, cells)
		map_presenter.present(GameView.new(1, true, null, "fixture.map", coordinate, 0, 12, 0, map_view))
		var camera := ClassicMapPresenter.camera_top_left(coordinate, map_size, viewport_cells)
		cameras.append(camera)
		party_rects.append(Rect2(draw_origin + Vector2(coordinate - camera) * map_presenter.cell_size, Vector2.ONE * map_presenter.cell_size))
		assert_equal(Rect2(map_presenter.position, map_presenter.size), viewport_rect, "party position %s does not move or shrink the exploration viewport" % coordinate)
		assert_equal(map_presenter.get_parent(), viewport_parent, "party position %s preserves the viewport's clipping-control owner" % coordinate)
		assert_true(map_presenter.clip_contents, "party position %s preserves viewport clipping" % coordinate)
		assert_equal(ClassicMapPresenter.viewport_cells_for(map_presenter.size, map_presenter.map_origin.y, map_presenter.cell_size), viewport_cells, "party position %s keeps the bounded cell window" % coordinate)
		assert_equal(ClassicMapPresenter.map_draw_origin_for(map_presenter.size, map_presenter.map_origin, map_presenter.cell_size, viewport_cells), draw_origin, "party position %s keeps the map draw origin inside the fixed viewport" % coordinate)

	assert_true(cameras[0].x != cameras[1].x and cameras[1].x != cameras[2].x, "west, center, and east positions change only the internal horizontal camera offset")
	assert_true(cameras[3].y != cameras[4].y, "north and south positions change only the internal vertical camera offset")
	assert_true(party_rects[0].position.x != party_rects[2].position.x and party_rects[0].size == party_rects[2].size, "east-edge movement translates the party cell inside the viewport without changing cell geometry")
	assert_true(party_rects[3].position.y != party_rects[4].position.y and party_rects[3].size == party_rects[4].size, "north/south movement translates the party cell inside the viewport without changing cell geometry")
	application.free()


func _test_battlefield_presenter() -> void:
	var presenter := ClassicBattlefieldPresenter.new()
	assert_equal(ClassicBattlefieldPresenter.viewport_cells_for(Vector2(704.0, 396.0)), Vector2i(16, 11), "battlefield keeps native cell bounds")
	assert_equal(ClassicBattlefieldPresenter.click_direction(Vector2i(45, 45), Vector2i(52, 39)), Vector2i(1, -1), "distant clicks map to one tactical direction")
	assert_equal(ClassicBattlefieldPresenter.footprint_rect([], Vector2i.ZERO, Vector2.ZERO), Rect2(), "terminal playback tolerates a combatant whose committed battlefield footprint has already been removed")
	var view := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	presenter.present(view)
	presenter.set_movement_costs_visible(true)
	assert_true(presenter.movement_costs_visible(), "movement costs are an explicit presentation aid")
	presenter.free()
func _test_combat_targeting_state() -> void:
	var body := InteractionResponse.CombatBody.new(&"cast_spell", "hero")
	body.spell_id = "spell.darts"
	var request := CombatTargetingRequest.new(&"sequence", body)
	request.candidate_ids.assign(["monster.one", "ally.one"])
	request.maximum_targets = 1
	var state := CombatTargetingState.new(request)
	assert_true(state.select_combatant("ally.one"), "typed candidates accept a legal target")
	assert_false(state.select_combatant("monster.one"), "the core-provided maximum is enforced")
	assert_equal(state.committed_body().target_ids, ["ally.one"], "target confirmation preserves selected identity")
func _test_combat_playback_controller() -> void:
	var previous := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	var final := _combat_playback_view(12, Vector2i(46, 45), Vector2i(47, 45), &"active")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combatant_moved", {"actorId": "hero", "from": [45, 45], "to": [46, 45]}), DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 8, "classicResultEffectResourceId": 160}), DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "resisted": true, "classicResolutionEffectResourceIds": [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039]})]
	var controller := CombatPlaybackController.new()
	var frames: Array[CombatPlaybackFrame] = []
	controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: frames.append(frame))
	assert_true(controller.begin(previous, events, final, false), "combat events create one presentation playback transaction")
	while controller.is_active(): controller.advance(1.0, false)
	var kinds: Array[StringName] = []
	for frame: CombatPlaybackFrame in frames:
		kinds.append(frame.kind)
	assert_true(kinds.has(&"move_start") and kinds.has(&"melee_attack"), "movement and physical results have distinct frames")
	assert_equal(kinds.count(&"spell_effect"), 8, "source-backed spell resolution retains its eight-frame family")
	assert_true(frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result" and frame.display_text == "8"), "damage is shown once over the target")
	assert_equal(controller.base_view, previous, "playback retains the previous battlefield until visuals settle")
	var reduced := CombatPlaybackController.new()
	assert_true(reduced.begin(previous, events, final, true), "reduced motion keeps the same presentation boundary")
	while reduced.is_active(): reduced.advance(1.0, false)
	assert_false(reduced.is_active(), "reduced motion settles without a simulation mutation")
func _combat_playback_view(monster_health: int, hero_position: Vector2i, monster_position: Vector2i, outcome: StringName) -> GameView:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	assert_true(battlefield.place_character("hero", hero_position), "playback fixture places the party actor")
	var monster := MonsterState.new("monster", "classic.monster.1", "Goblin", monster_health, 20)
	monster.icon_id = 384
	assert_true(battlefield.place_monster(monster.id, monster_position, 0), "playback fixture places the target")
	var combat := CombatState.new("classic.battle.playback", [monster], 0, battlefield)
	combat.set_turn_order(["hero", "monster"])
	combat.outcome = outcome
	var character := CharacterState.new("hero", "Hero", 10, 10)
	var view := GameView.new(1, true, null)
	view.party_members = [CharacterView.new(character)]
	view.combat_view = CombatView.new(combat, [character])
	return view


func _test_character_creator_workflow() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var setup := router.setup_controller
	var view := GameView.new(1, true, null)
	view.campaign_id = "creator.fixture"
	view.party_setup_available = true
	view.party_setup = PartySetupView.new()
	view.party_setup.available_monster_sets = [0, -1, 1]
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.maximum_party_size = 6
	view.campaign_summary.maximum_level = 7
	view.race_options = [DefinitionOptionView.new("race.human", "Human", "Adaptable.", ["caste.sorcerer"])]
	view.caste_options = [DefinitionOptionView.new("caste.sorcerer", "Sorcerer", "Arcane caster.", ["race.human"])]
	router.present(view)
	assert_equal(setup.party_list.get_child_count(), 6, "creator retains six party positions")
	var prior_character_list: VBoxContainer = setup.stored_character_list
	setup.create_character_button.pressed.emit()
	assert_equal(setup.setup_mode, &"creator", "creator opens from party assembly")
	prior_character_list.free()
	assert_true(setup.creator_cancel_button != null and not setup.creator_cancel_button.disabled, "creator can be canceled before draft mutation")
	setup.creator_cancel_button.pressed.emit()
	assert_equal(setup.setup_mode, &"assembly", "creator cancellation rebuilds assembly after its prior dynamic controls are freed")
	router.free()
func _test_character_vault_workspace() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var view := GameView.new(1, true, null)
	view.campaign_id = "vault.fixture"
	view.party_setup_available = true
	var revision := CharacterVaultRevisionView.new()
	revision.character_id = "vault.character"
	revision.revision_hash = "a".repeat(64)
	revision.name = "Vault Hero"
	revision.level = 3
	revision.eligible = true
	router.set_vault_revisions([revision])
	router.present(view)
	router.open_screen(&"vault")
	assert_true(router.full_stage_overlay_visible(), "Character Files owns the complete stage")
	var buttons := _buttons_in(router)
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Inspect character"), "vault exposes mutation-free inspection")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Import this revision"), "vault exposes explicit import")
	router.free()
func _test_field_spell_workspace() -> void:
	var body := VBoxContainer.new()
	var controller := SpellsWorkspaceController.new()
	var view := GameView.new(5, true, null)
	var character_view := CharacterView.new(CharacterState.new("caster", "Aster", 12, 12))
	var definition := SpellDefinition.new("classic.spell.field", 1101, "Field Bolt")
	definition.cost = 2
	var spell_view := SpellView.new(definition)
	spell_view.power_levels = [1, 2]
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true)
	character_view.spells = [spell_view]
	view.party_members = [character_view]
	view.set_action_availability(&"cast_spell", true)
	controller.present(body, view, null, 1.0)
	assert_true(_buttons_in(body).any(func(button: Button) -> bool: return button.text.contains("Cast")), "spell workspace exposes a typed field cast")
	assert_true(body.find_children("*", "OptionButton", true, false).size() >= 1, "spellbook retains explicit selection controls")
	body.free()
func _test_inventory_workspace() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-ui", 10, "Longsword", "Sword", "A balanced sword.")
	var source := CharacterState.new("source", "Alis", 10, 10)
	var view := GameView.new(4, true, null)
	var source_view := CharacterView.new(source)
	var item_view := ItemView.new(ItemInstance.new("inventory.item", definition.id, 0, false, true), definition)
	item_view.actions.equip = ActionAvailabilityView.new(&"equip_item", true)
	item_view.actions.split = ActionAvailabilityView.new(&"split_item", true)
	item_view.actions.join = ActionAvailabilityView.new(&"join_item", true)
	item_view.actions.use = ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
	source_view.items = [item_view]
	view.party_members = [source_view]
	var body := VBoxContainer.new()
	var controller := InventoryWorkspaceController.new()
	controller.present(body, view, null, 1.0)
	var buttons := _base_buttons_in(body)
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Longsword")), "inventory renders a selectable carried item")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text == "Equip"), "inventory exposes the typed Equip action")
	assert_true(["Split", "Join"].all(func(label: String) -> bool: return buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text == label and not button.disabled)), "inventory exposes core-authorized stack actions")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text.contains("not implemented")), "unsafe use remains visible with a core-owned reason")
	body.free()
func _test_money_workspace() -> void:
	var source := CharacterState.new("money.ui.source", "Alis", 10, 10)
	source.money = WealthState.new(10, 2, 1)
	source.carried_load = 27
	source.maximum_load = 100
	var destination := CharacterState.new("money.ui.destination", "Borin", 10, 10)
	destination.maximum_load = 100
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = 15
	workspace.pooled_gems = 1
	workspace.pooled_jewelry = 1
	workspace.banked_gold = 50
	workspace.pool = ActionAvailabilityView.new(&"money_action", true)
	workspace.share = ActionAvailabilityView.new(&"money_action", false, "No adventurer can carry another pooled denomination.")
	var source_view := MoneyCharacterView.new(source)
	source_view.transfers = [
		MoneyTransferView.new(&"gold", 5, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", true)),
		MoneyTransferView.new(&"gems", 1, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", true)),
		MoneyTransferView.new(&"jewelry", 1, ActionAvailabilityView.new(&"money_action", true), ActionAvailabilityView.new(&"money_action", false, "Alis cannot carry that denomination.")),
	]
	var destination_view := MoneyCharacterView.new(destination)
	workspace.characters = [source_view, destination_view]
	var view := GameView.new(5, true, null)
	view.money_workspace = workspace
	view.set_action_availability(&"money_action", true)
	view.set_action_availability(&"service_action", false, "No location service is available.")
	var body := VBoxContainer.new()
	var controller := ServicesWorkspaceController.new()
	var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	controller.present(body, view)
	var buttons := _buttons_in(body)
	var labels := _labels_in(body)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("15 gold") and text.contains("1 jewelry")), "money workspace renders every detached pooled denomination")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Banked: 50 gold")), "banked wealth remains visible without being merged into ordinary Swap")
	var pool_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Pool party wealth")[0]
	var share_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Share pooled wealth")[0]
	assert_false(pool_button.disabled, "core-authorized Pool is actionable")
	assert_true(share_button.disabled and share_button.tooltip_text.contains("No adventurer can carry"), "core-owned Share blocker remains visible")
	var to_pool_buttons := buttons.filter(func(button: Button) -> bool: return button.text == "To pool")
	var to_character_buttons := buttons.filter(func(button: Button) -> bool: return button.text == "To Alis")
	assert_equal([to_pool_buttons.size(), to_character_buttons.size()], [3, 3], "Swap presents all three Classic denominations for the selected character")
	assert_true(to_character_buttons[2].disabled and to_character_buttons[2].tooltip_text.contains("cannot carry"), "presentation does not recreate jewelry capacity rules")
	pool_button.pressed.emit()
	to_pool_buttons[0].pressed.emit()
	to_character_buttons[0].pressed.emit()
	assert_equal(intents.size(), 3, "money controls emit exactly one typed intent per mutation")
	var pool_payload := intents[0].payload as PlayerIntent.MoneyPayload
	var to_pool_payload := intents[1].payload as PlayerIntent.MoneyPayload
	var to_character_payload := intents[2].payload as PlayerIntent.MoneyPayload
	assert_equal([intents[0].kind, pool_payload.action], [PlayerIntent.Kind.MONEY_ACTION, &"pool"], "Pool crosses the typed money boundary")
	assert_equal([to_pool_payload.action, to_pool_payload.character_id, to_pool_payload.denomination, to_pool_payload.amount], [&"to-pool", source.id, "gold", 5], "character-to-pool Swap carries stable identity and exact Classic increment")
	assert_equal([to_character_payload.action, to_character_payload.character_id, to_character_payload.denomination, to_character_payload.amount], [&"to-character", source.id, "gold", 5], "pool-to-character Swap carries stable identity and exact Classic increment")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Done"), "Swap has a presentation-only cancellation path with no gameplay mutation")
	body.free()


func _test_party_order_workspace() -> void:
	var view := GameView.new(8, true, null)
	view.party_members = [CharacterView.new(CharacterState.new("alis", "Alis", 10, 10)), CharacterView.new(CharacterState.new("borin", "Borin", 12, 12))]
	view.set_action_availability(&"reorder_party", true)
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router.present(view)
	router.open_screen(&"character")
	var move := _buttons_in(router).filter(func(button: Button) -> bool: return button.text == "Move Down" and not button.disabled)
	assert_equal(move.size(), 1, "party order exposes one enabled move control")
	move[0].pressed.emit()
	assert_equal(intents.size(), 0, "reordering stages locally")
	var apply := _buttons_in(router).filter(func(button: Button) -> bool: return button.text == "Apply Party Order")
	assert_equal(apply.size(), 1, "reordering has one typed commit action")
	apply[0].pressed.emit()
	assert_equal(intents.size(), 1, "Apply emits one public reorder intent")
	router.free()
func _test_character_sheet_workspace() -> void:
	var character := CharacterState.new("character.sheet", "Long Character Name", -10, 18)
	character.gender = 2
	character.level = 7
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.2"
	var view := CharacterView.new(character)
	assert_equal(view.gender_name, "Female", "the detached sheet preserves Classic identity")
	var sheet := ClassicCharacterSheet.new()
	sheet.present([view], view.id, {}, 1.0, &"overview", [], [], ActionAvailabilityView.new(&"change_character_appearance", true))
	for label: String in ["Overview", "Conditions & Saves", "Equipment", "Abilities", "Spells", "Appearance", "Race, Class & Aging", "Lifetime Record"]:
		assert_true(_buttons_in(sheet).any(func(button: Button) -> bool: return button.text == label), "sheet exposes %s" % label)
	sheet.free()
func _test_scene_composition() -> void:
	var scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell.get_node_or_null("ScreenRouter"), "the shell owns one workspace router")
	assert_not_null(shell.get_node_or_null("BottomRegion/BottomRow/NarrativeWell"), "the shell owns a narrative well")
	var backing := shell.get_node("PictureStage/PictureBacking") as TextureRect
	assert_equal(backing.stretch_mode, TextureRect.STRETCH_TILE, "picture backing fills without stretching")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(960, 600), Vector2(1280, 720), Vector2(1920, 1080)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
		assert_true(rect.position.x >= 0.0 and rect.end.x <= viewport_size.x - profile.party_width, "campaign layout stays clear of the roster at %s" % viewport_size)
	shell.free()
func _test_automatic_workflow_routes() -> void:
	var terminal_step := SessionStep.completed(1, [DomainEvent.new(&"session_ended", {"reason": "party-defeat"})])
	assert_true(RealmzApplication.should_defer_session_close(terminal_step, true), "terminal host navigation waits until committed combat playback releases its retained battlefield")
	assert_false(RealmzApplication.should_defer_session_close(terminal_step, false), "terminal host navigation proceeds immediately when no presentation playback owns the prior view")
	var no_session := GameView.new(0, false, null)
	assert_equal(ClassicApplicationShell.route_change_reason(no_session), "Choose a campaign first.", "gameplay routes are disabled on the splash and campaign library")
	var setup_view := GameView.new(1, true, null)
	setup_view.party_setup_available = true
	assert_equal(ClassicApplicationShell.route_change_reason(setup_view), "Begin the adventure first.", "Explore and other browsing routes stay disabled until party setup commits Begin Adventure")
	var view := GameView.new(1, true, null)
	view.combat_view = CombatView.new(CombatState.new("classic.battle.route"))
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"exploration", view), &"combat", "battle setup opens the tactical workspace")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"combat", "battle setup replaces a browsing workspace so combat controls cannot overlap it")
	view.pending_interaction = ClassicUiFixtureGallery.request_for(InteractionRequest.ALLY_SELECTION)
	assert_equal(ClassicApplicationShell.route_change_reason(view), "Resolve the current interaction first.", "a mandatory post-battle response disables misleading route changes such as Adventure Explore")
	view.pending_interaction = null
	view.combat_view = null
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"combat", view), &"exploration", "completed battle cleanup returns the ordinary shell to exploration")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"inventory", "ordinary non-combat workspaces remain presentation-owned")
	view.pending_interaction = _fixture_request("shop.route", InteractionRequest.SHOP)
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"exploration", view), &"services", "application services open their dedicated workspace")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"services", "a service interaction replaces an unrelated browsing workspace")
	view.pending_interaction = null
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"services", view, true), &"exploration", "completing a contextual service returns to exploration instead of leaving its interaction workspace open")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"services", view, false), &"services", "ordinary Money browsing remains open until the player chooses Done")
	view.pending_interaction = InteractionRequest.yes_no("action-point.route", "Will you approach?", "Yes", "No")
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"exploration", "an Action Point interaction returns an unrelated browsing workspace to exploration")
	view.pending_interaction = null
	assert_equal(ClassicApplicationShell.automatic_workflow_route(&"inventory", view), &"inventory", "free browsing remains presentation-owned after the interaction closes")
