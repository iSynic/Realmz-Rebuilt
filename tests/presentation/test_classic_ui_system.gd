extends RealmzTestCase

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const PackageOperationStatusScript := preload("res://src/app/package_operation_view.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")
const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func _fixture_request(id: String, kind: StringName, overrides: Dictionary = {}) -> InteractionRequest:
	var payload := ClassicUiFixtureGallery.payload_for(kind)
	payload.merge(overrides, true)
	return InteractionRequest.from_payload(id, kind, payload)


func run() -> void:
	_test_startup_shell()
	_test_startup_party_setup_composition()
	_test_route_catalog()
	_test_primary_workspace_lifecycle()
	_test_layout_profiles()
	_test_settings_schema_and_migration()
	_test_movement_input()
	_test_fast_spell_input()
	_test_safe_item_display()
	_test_action_availability()
	_test_fixture_gallery_coverage()
	_test_interaction_identity()
	_test_interaction_scroll_resets_for_new_request()
	_test_lifecycle_interaction()
	_test_classic_choice_context()
	_test_battle_weapon_mode_component()
	_test_battle_typed_option_contracts()
	_test_shop_component()
	_test_temple_component()
	_test_bank_component()
	_test_money_workspace_audio()
	_test_classic_application_media()
	_test_classic_asset_catalog()
	_test_stone_surface_tiling()
	_test_spatial_stage_visibility()
	_test_exploration_map_camera_preserves_viewport_geometry()
	_test_battlefield_presenter()
	_test_combat_targeting_state()
	_test_combat_playback_controller()
	_test_automatic_workflow_routes()
	_test_character_creator_workflow()
	_test_begin_adventure_closes_setup_vault()
	_test_character_vault_workspace()
	_test_field_spell_workspace()
	_test_inventory_workspace()
	_test_money_workspace()
	_test_exploration_money_and_service_commands()
	_test_party_order_workspace()
	_test_character_sheet_workspace()
	_test_party_roster()
	_test_scene_composition()
	_test_package_operation_presentation()
	_test_save_preview_workspace()
	_test_location_note_workspace()
	_test_player_map_workspace()


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
	var cancel_count: Array[int] = [0]
	router.cancel_package_requested.connect(func() -> void: cancel_count[0] += 1)
	var status := PackageOperationStatusScript.new(&"running", &"validating-integrity", 2, 5, "Validating package files 2 of 5…")
	assert_equal(status.progress_ratio(), 0.4, "package operation progress is detached and bounded")
	router.set_package_operation(status)
	var operation_label := router.find_child("PackageOperationStatus", true, false) as Label
	var progress := router.find_child("PackageOperationProgress", true, false) as ProgressBar
	var cancel := router.find_child("CancelPackageOperation", true, false) as Button
	assert_not_null(operation_label, "campaign library exposes active package validation status")
	assert_equal(operation_label.text, status.message, "campaign library renders the worker-owned progress message")
	assert_not_null(progress, "campaign library exposes package validation progress")
	assert_equal([progress.value, progress.max_value], [2.0, 5.0], "package progress renders detached completed and total units")
	assert_not_null(cancel, "active package validation exposes an explicit Cancel action")
	cancel.pressed.emit()
	assert_equal(cancel_count[0], 1, "package Cancel crosses one host signal without mutating a session")
	router.set_package_operation(PackageOperationStatusScript.new())
	assert_equal(router.find_child("CancelPackageOperation", true, false), null, "completed package work removes the transient Cancel action")
	router.free()

	var integrated_router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(integrated_router)
	integrated_router.initialize()
	var profile := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	integrated_router.set_layout_profile(profile, Vector2(960, 600))
	integrated_router.show_campaign_selection()
	integrated_router.set_package_operation(PackageOperationStatusScript.new(&"running", &"loading", 1, 3, "Loading scenario package and preparing its campaign records…"))
	var scenario_column := integrated_router.find_child("ScenarioColumn", true, false) as Control
	var loading_label := integrated_router.find_child("PackageOperationStatus", true, false) as Label
	var operation_controls := integrated_router.find_child("PackageOperationControls", true, false) as Control
	var loading_progress := integrated_router.find_child("PackageOperationProgress", true, false) as ProgressBar
	var loading_cancel := integrated_router.find_child("CancelPackageOperation", true, false) as Button
	var character_heading := integrated_router.find_child("CharacterFilesHeading", true, false) as Control
	var character_column := character_heading.get_parent() as Control if character_heading != null else null
	var party_heading := integrated_router.find_child("PartyHeading", true, false) as Control
	var party_column := party_heading.get_parent() as Control if party_heading != null else null
	var operation_row := integrated_router.find_child("PackageOperationRow", true, false) as Control
	var intended_scenario_width := ClassicScreenRouter.campaign_rect_for(profile, Vector2(960, 600)).size.x
	assert_true(loading_label != null and loading_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and operation_row != null and operation_row is VBoxContainer and operation_controls != null and operation_controls is HBoxContainer and operation_row.get_child_count() == 2 and operation_row.get_child(0) == loading_label and operation_row.get_child(1) == operation_controls and scenario_column != null and scenario_column.get_combined_minimum_size().x >= 200.0, "integrated package loading copy keeps a practical horizontal Scenarios width instead of collapsing to one-character lines")
	assert_true(operation_controls != null and loading_progress != null and loading_cancel != null and operation_controls.get_combined_minimum_size().x <= intended_scenario_width and scenario_column != null and scenario_column.get_combined_minimum_size().x <= intended_scenario_width, "progress and Cancel fit inside the intended bounded Scenarios share")
	assert_true(character_heading != null and character_heading.visible and character_column != null and character_column.get_combined_minimum_size().x > 0.0 and party_heading != null and party_heading.visible and party_column != null and party_column.get_combined_minimum_size().x > 0.0, "package loading keeps the Character Files and Current Party columns mounted and visible")
	integrated_router.free()


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
		for node: Node in scenario_picker.find_children("*", "Label", true, false):
			var label := node as Label
			if label.visible:
				scenario_copy.append(label.text)
		for node: Node in scenario_picker.find_children("*", "Button", true, false):
			var button := node as Button
			if button.visible:
				scenario_copy.append(button.text)
	assert_true(router.setup_controller.campaign_list is VBoxContainer and router.setup_controller.campaign_list.get_parent() is ScrollContainer, "installed scenarios use one single-column picker surface")
	assert_false(scenario_copy.any(func(text: String) -> bool: return text.contains("Stale Scenario")), "incompatible installations do not become ordinary scenario rows")
	assert_contains(scenario_picker.tooltip_text, "installation hidden", "the picker preserves incompatible-installation diagnostics in unobtrusive hover text")
	var scenario_buttons: Array[String] = []
	if scenario_picker != null:
		for node: Node in scenario_picker.find_children("*", "Button", true, false):
			var button := node as Button
			if button.visible:
				scenario_buttons.append(button.text)
	assert_false(scenario_buttons.any(func(text: String) -> bool: return text == "Play"), "scenario rows do not expose the obsolete per-row Play action")
	var install_buttons: Array[String] = []
	if scenario_picker != null:
		for node: Node in scenario_picker.find_children("*", "Button", true, false):
			var button := node as Button
			if button.visible:
				install_buttons.append(button.text)
	assert_true(install_buttons.any(func(text: String) -> bool: return text.begins_with("Install .realmz2")), "the external package action uses installation language")
	assert_false(install_buttons.any(func(text: String) -> bool: return text == "Open path" or text.to_lower().contains("play")), "the integrated workspace does not label external installation as Play")
	var setup_seed: Node = null
	if setup_workspace != null:
		setup_seed = setup_workspace.find_child("Seed", true, false)
	assert_true(setup_seed == null, "developer seed controls are absent from the ordinary scenario and party workspace")
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


func _test_interaction_scroll_resets_for_new_request() -> void:
	var scene := load("res://src/presentation/interaction_presenter.tscn") as PackedScene
	var presenter := scene.instantiate() as InteractionPresenter
	var scroll := presenter.get_node("InteractionScroll") as ScrollContainer
	presenter._prompt = presenter.get_node("InteractionScroll/InteractionContent/InteractionPrompt") as Label
	presenter._heading = presenter.get_node("InteractionScroll/InteractionContent/InteractionHeading") as Label
	presenter._options = presenter.get_node("InteractionScroll/InteractionContent/InteractionOptions") as VBoxContainer
	presenter._scroll = scroll
	presenter._stage_opaque_backing = presenter.get_node("StageOpaqueBacking") as ColorRect
	presenter._stage_backing = presenter.get_node("StageBacking") as TextureRect
	presenter.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION))
	scroll.scroll_vertical = 294
	presenter.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unavailable"))
	assert_equal([scroll.scroll_horizontal, scroll.scroll_vertical], [0, 0], "a newly presented interaction starts at its title and current item instead of inheriting focus-driven scroll")
	presenter.free()


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
	var buttons: Array[Button] = []
	var labels: Array[String] = []
	for node: Node in body.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	for node: Node in body.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
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
	var labels: Array[String] = []
	for node: Node in body.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
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
	session._state.world.acquire_map(definition.id)
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
	for player_map_definition: PlayerMapDefinition in loaded.content.world.player_maps():
		session._state.world.acquire_map(player_map_definition.id)
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
	assert_not_null(picture_canvas._texture_for(picture_view.picture_asset_id), "required player-map PICT media decodes through its exact package asset")
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
	var request := _fixture_request("battle.weapon-mode", InteractionRequest.COMBAT, {
		"round": 2,
		"actorId": "character.archer",
		"attackUnitsRemaining": 2,
		"movementRemaining": 8,
		"enemiesRemaining": 1,
		"actions": ["switch_weapon", "cast_spell", "use_item", "finish", "defend", "retreat"],
		"weaponMode": "missile",
		"weaponSwitch": {"enabled": true, "targetMode": "melee", "reason": ""},
		"rangedAttack": {"enabled": false, "reason": "Missile range, line of sight, and projectile resolution are unavailable."},
		"retreat": {"enabled": false, "reason": "An enemy is too close.", "nearestEnemyRange": 1},
		"combatants": [
			{"id": "character.archer", "kind": "character", "name": "Archer", "currentHealth": 9, "maximumHealth": 10, "spellPoints": 6, "maximumSpellPoints": 8, "armor": 7, "magicResistance": 12, "attacks": "2", "movement": 8, "maximumMovement": 12, "traitor": false, "helpless": false, "conditions": ["Speedy"]},
			{"id": "monster.target", "kind": "monster", "name": "Target", "currentHealth": 5, "maximumHealth": 5, "spellPoints": 0, "maximumSpellPoints": 0, "armor": 11, "magicResistance": 25, "hitDice": 3, "attacks": "2", "movement": 9, "maximumMovement": 9, "traitor": false, "helpless": false, "weapon": "Claws", "weaponCharges": 4, "range": 7, "blocked": true, "conditions": ["Poisoned"], "immunities": ["Heat"], "vulnerabilities": ["Cold"]},
		],
		"targets": [{"id": "monster.target", "name": "Target", "currentHealth": 5, "maximumHealth": 5}],
		"spellCasts": [
			{"spellId": "spell.flame", "spellName": "Flame", "power": 2, "cost": 4, "targetId": "monster.target", "targetName": "Target", "targetCurrentHealth": 5, "targetMaximumHealth": 5, "targetMode": "combatant"},
			{"spellId": "spell.wave", "spellName": "Wave", "power": 1, "cost": 3, "targetId": "", "targetName": "Everybody", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "automatic"},
			{"spellId": "spell.burst", "spellName": "Burst", "power": 3, "cost": 6, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 3, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, -1], [-1, 0], [0, 0], [1, 0], [0, 1]], "legalTargetCoordinates": [[45, 45], [47, 43]]},
			{"spellId": "spell.darts", "spellName": "Darts", "power": 3, "cost": 6, "targetId": "", "targetName": "Choose up to 3 actors", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "sequence", "maximumTargets": 3, "targetCandidates": [
				{"id": "monster.target", "kind": "monster", "name": "Target", "currentHealth": 5, "maximumHealth": 5},
				{"id": "character.ally", "kind": "character", "name": "Ally", "currentHealth": 8, "maximumHealth": 10},
			]},
		],
		"itemCasts": [
			{"itemInstanceId": "item.wand.instance", "itemId": "item.wand", "itemName": "Runed Wand", "charges": 3, "spellId": "spell.flame", "spellName": "Flame", "power": 2, "targetId": "monster.target", "targetName": "Target", "targetCurrentHealth": 5, "targetMaximumHealth": 5, "targetMode": "combatant"},
		],
		"movement": [
			{"direction": [0, -1], "destination": [45, 44], "cost": 1, "enabled": true, "reasonCode": "", "reason": "", "retreat": false, "forcedRetreat": false, "attackTargetId": "", "attackTargetName": ""},
			{"direction": [1, 0], "destination": [46, 45], "cost": 1, "enabled": false, "reasonCode": "occupied", "reason": "Destination occupied.", "retreat": false, "forcedRetreat": false, "attackTargetId": "", "attackTargetName": ""},
			{"direction": [-1, 0], "destination": [1, 45], "cost": 0, "enabled": true, "reasonCode": "", "reason": "", "retreat": true, "forcedRetreat": false, "attackTargetId": "", "attackTargetName": ""},
		],
	})
	var component := BattleInteraction.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons: Array[Button] = []
	for child: Node in component.find_children("*", "Button", true, false):
		buttons.append(child as Button)
	assert_false(buttons.any(func(button: Button) -> bool: return button.text.begins_with("Attack ")), "missile mode renders no melee attack target buttons")
	var fire_button: Button = null
	var switch_button: Button = null
	var finish_button: Button = null
	var escape_button: Button = null
	var spell_mode_button: Button = null
	var item_mode_button: Button = null
	var cast_button: Button = null
	var use_item_button: Button = null
	var center_button: Button = null
	var reveal_button: Button = null
	for button: Button in buttons:
		if button.text == "Fire":
			fire_button = button
		elif button.text == "Weapon: Melee":
			switch_button = button
		elif button.text == "Finish":
			finish_button = button
		elif button.text == "Escape":
			escape_button = button
		elif button.text == "Spells":
			spell_mode_button = button
		elif button.text == "Items":
			item_mode_button = button
		elif button.text == "Choose spell target on battlefield":
			cast_button = button
		elif button.text == "Use selected item":
			use_item_button = button
		elif button.text == "Center Active":
			center_button = button
		elif button.text == "Reveal Friends":
			reveal_button = button
	assert_not_null(fire_button, "the unresolved ranged action remains visible instead of silently disappearing")
	assert_true(fire_button.disabled and not fire_button.tooltip_text.is_empty(), "the disabled Fire action exposes the typed tactical blocker")
	assert_not_null(switch_button, "the source-backed no-cost mode toggle remains available")
	assert_false(buttons.any(func(button: Button) -> bool: return button.text.begins_with("N ") or button.text.begins_with("Leave ")), "spatial movement is no longer duplicated as eight permanent direction buttons")
	assert_not_null(finish_button, "the Classic Finish command remains distinct from Defend")
	assert_true(escape_button != null and escape_button.disabled and escape_button.tooltip_text == "An enemy is too close.", "the explicit Escape control exposes the core-owned unavailable reason")
	assert_not_null(spell_mode_button, "the full-width command deck exposes the spell workflow")
	assert_not_null(item_mode_button, "the full-width command deck exposes the item workflow")
	assert_not_null(cast_button, "the battle component exposes a core-proven spell, power, and target option")
	assert_not_null(use_item_button, "the battle component exposes a core-proven charged item, power, and target option")
	assert_false(buttons.any(func(button: Button) -> bool: return button.text == "Add target"), "repeated spell targets are selected in order on the battlefield rather than in a duplicate list")
	assert_not_null(center_button, "the battle deck exposes Castle's presentation-owned active-actor centering command")
	assert_not_null(reveal_button, "the battle deck exposes Castle's presentation-owned Reveal Friends command")
	var battle_labels := component.find_children("*", "Label", true, false)
	assert_true(battle_labels.any(func(label: Label) -> bool: return label.text.contains("Shown • Target") and label.text.contains("AR 11") and label.text.contains("Range 7 • Blocked") and label.text.contains("Claws (4)") and label.text.contains("Immune: Heat") and label.text.contains("Vulnerable: Cold")), "the source-backed shown-combatant panel exposes target range, LOS, armor, resistance, weapon charges, condition, immunity, and vulnerability facts")
	assert_true(battle_labels.any(func(label: Label) -> bool: return label.text.contains("Enemies left • 1")), "the active combat summary exposes the core-counted opposing force")
	for unavailable_label: String in ["Auto", "Delay", "Undo", "Bandage", "Turn Undead"]:
		var matching_buttons := buttons.filter(func(button: Button) -> bool: return button.text == unavailable_label)
		assert_equal(matching_buttons.size(), 1, "%s remains visible in the Classic command deck" % unavailable_label)
		if not matching_buttons.is_empty():
			assert_true(matching_buttons[0].disabled and not matching_buttons[0].tooltip_text.is_empty(), "%s exposes an explicit typed-workflow gap instead of a fake mutation" % unavailable_label)
	var command_request := _fixture_request("battle.command-parity", InteractionRequest.COMBAT, {
		"actorId": "character.priest",
		"actions": ["finish", "defend", "auto", "delay", "bandage", "turn_undead", "undo"],
		"autoTurn": {"enabled": true, "reason": ""},
		"delay": {"enabled": true, "reason": ""},
		"bandage": {"enabled": true, "reason": "", "targets": [{"id": "character.bleeding", "name": "Bleeding Hero", "currentHealth": -2, "maximumHealth": 20}]},
		"turnUndead": {"enabled": true, "reason": "", "targets": [{"id": "monster.undead", "name": "Undead", "hitDice": 3, "magicResistance": 10}]},
		"undo": {"enabled": true, "reason": ""},
	})
	var command_component := BattleInteraction.new()
	var command_payloads: Array[Dictionary] = []
	command_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: command_payloads.append(body.to_data()))
	command_component.build(command_request)
	var command_buttons: Array[Button] = []
	for child: Node in command_component.find_children("*", "Button", true, false):
		command_buttons.append(child as Button)
	var auto_button := command_buttons.filter(func(button: Button) -> bool: return button.text == "Auto")[0] as Button
	var delay_button := command_buttons.filter(func(button: Button) -> bool: return button.text == "Delay")[0] as Button
	var bandage_button := command_buttons.filter(func(button: Button) -> bool: return button.text == "Bandage")[0] as Button
	var turn_button := command_buttons.filter(func(button: Button) -> bool: return button.text == "Turn Undead (1)")[0] as Button
	var undo_button := command_buttons.filter(func(button: Button) -> bool: return button.text == "Undo")[0] as Button
	assert_equal([auto_button.disabled, delay_button.disabled, bandage_button.disabled, turn_button.disabled, undo_button.disabled], [false, false, false, false, false], "typed combat command availability enables Auto, Delay, Bandage, Turn Undead, and Undo without presenter-side rules")
	auto_button.pressed.emit()
	delay_button.pressed.emit()
	turn_button.pressed.emit()
	undo_button.pressed.emit()
	bandage_button.pressed.emit()
	var bandage_submit := command_buttons.filter(func(button: Button) -> bool: return button.text == "Bandage selected character")[0] as Button
	bandage_submit.pressed.emit()
	assert_equal(command_payloads, [
		{"actorId": "character.priest", "action": "auto", "targetId": ""},
		{"actorId": "character.priest", "action": "delay", "targetId": ""},
		{"actorId": "character.priest", "action": "turn_undead", "targetId": ""},
		{"actorId": "character.priest", "action": "undo", "targetId": ""},
		{"actorId": "character.priest", "action": "bandage", "targetId": "character.bleeding"},
	], "the command deck returns only typed command and stable recipient identity payloads")
	command_component.free()
	var targeting_requests: Array[CombatTargetingRequest] = []
	var focus_events: Array[Array] = []
	var reveal_events: Array[bool] = []
	component.combat_targeting_requested.connect(func(targeting_request: CombatTargetingRequest) -> void: targeting_requests.append(targeting_request))
	component.combatant_focus_requested.connect(func(combatant_id: String, play_sound: bool) -> void: focus_events.append([combatant_id, play_sound]))
	component.reveal_friends_requested.connect(func() -> void: reveal_events.append(true))
	center_button.pressed.emit()
	reveal_button.pressed.emit()
	assert_equal([focus_events, reveal_events.size()], [[['character.archer', true]], 1], "Center and Reveal remain explicit presentation events rather than gameplay responses")
	assert_equal([cast_button.get_parent().visible, use_item_button.get_parent().get_parent().visible], [false, false], "secondary battle workflows begin collapsed instead of overflowing the battlefield")
	assert_true(component.accepts_spatial_input(), "ordinary battle commands leave keyboard and battlefield movement active")
	var overview := spell_mode_button.get_parent().get_parent() as Control
	var spell_panel := cast_button.get_parent() as VBoxContainer
	var spell_back := spell_panel.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Back to battle")[0] as Button
	spell_mode_button.pressed.emit()
	assert_true(spell_panel.visible and not overview.visible, "Spells replaces the battle overview so its controls stay inside the fixed Classic command region")
	assert_true(spell_panel.get_combined_minimum_size().y <= 160.0, "the default spell chooser fits the 960x600 combat region's usable height")
	assert_false(component.accepts_spatial_input(), "an open spell workflow owns direction keys and prevents accidental tactical movement")
	spell_back.pressed.emit()
	assert_true(overview.visible and not spell_panel.visible and component.accepts_spatial_input(), "Back to battle restores the tactical overview and spatial input")
	spell_mode_button.pressed.emit()
	var spell_picker := component.find_children("*", "OptionButton", true, false).filter(func(control: OptionButton) -> bool: return control.get_parent() == spell_panel)[0] as OptionButton
	assert_equal(spell_picker.get_item_text(1), "Wave • P1 • 3 SP → Everybody", "automatic group spells render their typed label without fabricating one target's HP")
	switch_button.pressed.emit()
	spell_picker.select(1)
	spell_picker.item_selected.emit(1)
	assert_equal(cast_button.text, "Cast selected spell", "automatic group spells commit without inventing a board target")
	cast_button.pressed.emit()
	spell_picker.select(0)
	spell_picker.item_selected.emit(0)
	cast_button.pressed.emit()
	var combatant_configuration := targeting_requests[-1]
	assert_equal([combatant_configuration.mode, combatant_configuration.candidate_ids], [&"combatant", ["monster.target"]], "single-target casting opens a battlefield-native picker with only core-proven candidates")
	spell_picker.select(2)
	spell_picker.item_selected.emit(2)
	cast_button.pressed.emit()
	var area_configuration := targeting_requests[-1]
	assert_equal([area_configuration.mode, area_configuration.area_offsets, area_configuration.legal_coordinates], [&"area", [Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN], [Vector2i(45, 45), Vector2i(47, 43)]], "area targeting carries the exact core-provided mask and legal centers instead of coordinate spin boxes")
	assert_equal(component.find_children("*", "SpinBox", true, false).size(), 0, "combat targeting no longer exposes coordinate spin boxes")
	spell_picker.select(3)
	spell_picker.item_selected.emit(3)
	cast_button.pressed.emit()
	var sequence_configuration := targeting_requests[-1]
	assert_equal([sequence_configuration.mode, sequence_configuration.candidate_ids, sequence_configuration.maximum_targets], [&"sequence", ["monster.target", "character.ally"], 3], "repeated spells preserve the rules-owned candidates and maximum for ordered battlefield clicks")
	item_mode_button.pressed.emit()
	assert_true(use_item_button.get_parent().get_parent().visible and not cast_button.get_parent().visible, "Items replaces the prior secondary workflow instead of stacking beneath it")
	assert_false(component.accepts_spatial_input(), "an open item workflow suppresses spatial battle input")
	use_item_button.pressed.emit()
	var item_configuration := targeting_requests[-1]
	assert_equal([item_configuration.mode, item_configuration.candidate_ids, item_configuration.response_body.item_instance_id], [&"combatant", ["monster.target"], "item.wand.instance"], "combat items use the same battlefield-native target contract")
	assert_equal(submitted, [
		{"actorId": "character.archer", "action": "switch_weapon", "targetId": ""},
		{"actorId": "character.archer", "action": "cast_spell", "targetId": "", "spellId": "spell.wave", "power": 1},
	], "only targetless commands submit directly; targeted actions wait for the battlefield-owned confirmation")
	component.free()

	var melee_request := _fixture_request("battle.collision-melee", InteractionRequest.COMBAT, {
		"actorId": "character.fighter",
		"actions": ["finish", "defend"],
		"weaponMode": "melee",
		"meleeAttackReason": "",
		"targets": [{"id": "monster.contact", "name": "Ogre", "currentHealth": 12, "maximumHealth": 12}],
		"movement": [{"direction": [1, 0], "destination": [46, 45], "cost": 3, "enabled": true, "reasonCode": "", "reason": "", "retreat": false, "forcedRetreat": false, "attackTargetId": "monster.contact", "attackTargetName": "Ogre"}],
	})
	var melee_component := BattleInteraction.new()
	var melee_submitted: Array[Dictionary] = []
	melee_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: melee_submitted.append(body.to_data()))
	melee_component.build(melee_request)
	var melee_buttons: Array[Node] = melee_component.find_children("*", "Button", true, false)
	assert_false(melee_buttons.any(func(button: Button) -> bool: return button.text == "Attack E"), "collision melee remains on the tactical board rather than reappearing as a directional command button")
	assert_equal(melee_submitted, [], "building the spatial melee command surface does not mutate combat")
	melee_component.free()


func _test_battle_typed_option_contracts() -> void:
	var unavailable_request := _fixture_request("battle.typed-unavailable", InteractionRequest.COMBAT, {
		"actorId": "character.caster",
		"actions": ["cast_spell", "use_item", "use_scroll"],
		"spellCasts": [],
		"itemCasts": [],
		"scrollCasts": [],
		"spellCastReason": "No legal Classic combat spell is available.",
		"itemCastReason": "No carried item has a supported Classic combat use.",
		"scrollCastReason": "The equipped scroll case contains no combat-ready spells.",
	})
	var unavailable_component := BattleInteraction.new()
	unavailable_component.build(unavailable_request)
	var unavailable_buttons: Array[Button] = []
	for child: Node in unavailable_component.find_children("*", "Button", true, false):
		unavailable_buttons.append(child as Button)
	var unavailable_spell := unavailable_buttons.filter(func(button: Button) -> bool: return button.text == "Spells")[0] as Button
	var unavailable_item := unavailable_buttons.filter(func(button: Button) -> bool: return button.text == "Items")[0] as Button
	var unavailable_scroll := unavailable_buttons.filter(func(button: Button) -> bool: return button.text == "Scrolls")[0] as Button
	assert_equal([unavailable_spell.disabled, unavailable_item.disabled, unavailable_scroll.disabled], [true, true, true], "typed combat spell, item, and scroll workflows remain disabled when the core supplies no legal options")
	assert_equal([unavailable_spell.tooltip_text, unavailable_item.tooltip_text, unavailable_scroll.tooltip_text], ["No legal Classic combat spell is available.", "No carried item has a supported Classic combat use.", "The equipped scroll case contains no combat-ready spells."], "disabled combat magic workflows expose the exact core-owned reasons")
	unavailable_component.free()

	var option_request := _fixture_request("battle.typed-options", InteractionRequest.COMBAT, {
		"actorId": "character.caster",
		"actions": ["cast_spell", "use_item", "use_scroll"],
		"spellCasts": [
			{"spellId": "spell.arc", "spellName": "Arc", "power": 2, "cost": 4, "targetId": "target.second", "targetName": "Second", "targetCurrentHealth": 7, "targetMaximumHealth": 7, "targetMode": "combatant"},
			{"spellId": "spell.arc", "spellName": "Arc", "power": 2, "cost": 4, "targetId": "target.first", "targetName": "First", "targetCurrentHealth": 6, "targetMaximumHealth": 6, "targetMode": "combatant"},
		],
		"itemCasts": [
			{"itemInstanceId": "item.wand.instance", "itemId": "item.wand", "itemName": "Runed Wand", "charges": 2, "spellId": "spell.arc", "spellName": "Arc", "power": 2, "targetId": "target.second", "targetName": "Second", "targetCurrentHealth": 7, "targetMaximumHealth": 7, "targetMode": "combatant"},
			{"itemInstanceId": "item.wand.instance", "itemId": "item.wand", "itemName": "Runed Wand", "charges": 2, "spellId": "spell.arc", "spellName": "Arc", "power": 2, "targetId": "target.first", "targetName": "First", "targetCurrentHealth": 6, "targetMaximumHealth": 6, "targetMode": "combatant"},
		],
		"scrollCasts": [
			{"scrollSlot": 2, "spellId": "spell.arc", "spellName": "Arc", "power": 2, "targetId": "target.second", "targetName": "Second", "targetCurrentHealth": 7, "targetMaximumHealth": 7, "targetMode": "combatant"},
			{"scrollSlot": 2, "spellId": "spell.arc", "spellName": "Arc", "power": 2, "targetId": "target.first", "targetName": "First", "targetCurrentHealth": 6, "targetMaximumHealth": 6, "targetMode": "combatant"},
		],
	})
	var option_component := BattleInteraction.new()
	var targeting_requests: Array[CombatTargetingRequest] = []
	option_component.combat_targeting_requested.connect(func(targeting_request: CombatTargetingRequest) -> void: targeting_requests.append(targeting_request))
	option_component.build(option_request)
	var option_buttons: Array[Button] = []
	for child: Node in option_component.find_children("*", "Button", true, false):
		option_buttons.append(child as Button)
	var spell_mode := option_buttons.filter(func(button: Button) -> bool: return button.text == "Spells")[0] as Button
	var item_mode := option_buttons.filter(func(button: Button) -> bool: return button.text == "Items")[0] as Button
	var scroll_mode := option_buttons.filter(func(button: Button) -> bool: return button.text == "Scrolls")[0] as Button
	spell_mode.pressed.emit()
	var spell_picker := option_component.find_children("*", "OptionButton", true, false).filter(func(control: OptionButton) -> bool: return control.get_parent() is VBoxContainer)[0] as OptionButton
	var cast_button := spell_picker.get_parent().find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Choose spell target on battlefield")[0] as Button
	cast_button.pressed.emit()
	var spell_configuration := targeting_requests[-1]
	assert_equal(spell_configuration.candidate_ids, ["target.second", "target.first"], "combat spell targeting preserves the typed legal target IDs and their supplied order")
	item_mode.pressed.emit()
	var item_picker := option_component.find_children("*", "OptionButton", true, false).filter(func(control: OptionButton) -> bool: return control.get_parent() is HBoxContainer)[0] as OptionButton
	var use_item_button := item_picker.get_parent().find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Use selected item")[0] as Button
	use_item_button.pressed.emit()
	var item_configuration := targeting_requests[-1]
	assert_equal([item_configuration.candidate_ids, item_configuration.response_body.item_instance_id], [["target.second", "target.first"], "item.wand.instance"], "combat item targeting preserves the typed legal target IDs and selected stable item instance")
	scroll_mode.pressed.emit()
	var scroll_picker := option_component.find_child("CombatScrollPicker", true, false) as OptionButton
	var use_scroll_button := scroll_picker.get_parent().find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Choose scroll target on battlefield")[0] as Button
	use_scroll_button.pressed.emit()
	var scroll_configuration := targeting_requests[-1]
	assert_equal([scroll_configuration.candidate_ids, scroll_configuration.response_body.scroll_slot], [["target.second", "target.first"], 2], "combat scroll targeting preserves source order and the exact fixed scroll slot")
	option_component.free()


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
	var buttons: Array[Button] = []
	for child: Node in component.get_children():
		if child is Button:
			buttons.append(child)
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
	var buttons: Array[Button] = []
	for child: Node in component.get_children():
		if child is Button:
			buttons.append(child)
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
	var buttons: Array[Button] = []
	for node: Node in component.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var labels: Array[String] = []
	for node: Node in component.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
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
	var departure_labels: Array[String] = []
	for node: Node in departure_component.find_children("*", "Label", true, false):
		departure_labels.append((node as Label).text)
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


func _test_classic_application_media() -> void:
	var application_media := ApplicationMediaCatalog.new()
	assert_true(application_media.is_valid(), "the complete versioned Classic application media manifest loads independently of a campaign package")
	assert_equal(application_media.assets().size(), 287, "the application catalog owns the complete pinned sound bank and source-backed combat icon families")
	var built_in := application_media.asset_by_resource("snd ", 147)
	assert_not_null(built_in, "a built-in interface sound resolves by its exact Classic resource type and ID")
	assert_true(application_media.asset_by_resource("SND ", 147) == null, "application media preserves Classic resource type case")
	assert_not_null(application_media.audio_stream(built_in), "a committed application WAV loads through Godot's resource importer")
	var spell_frame := application_media.asset_by_resource("cicn", 12032)
	assert_not_null(spell_frame, "a proven built-in spell-resolution frame resolves independently of campaign media")
	assert_equal([spell_frame.kind, spell_frame.width, spell_frame.height], ["icon", 32, 32], "application spell frames retain their decoded native dimensions")
	assert_true(application_media.asset_by_resource("cicn", 11992) == null, "lookStart zero retains Castle's absent cast-start family instead of substituting another effect")

	var package_override := MediaAsset.new("scenario-snd-147", "Scenario sound 147", "sound", "audio/wav", "snd ", 147, 0, "1".repeat(64), "assets/media/scenario-147.wav", 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, -1)
	var layered := ClassicMediaCatalog.new(PackageMediaCatalog.new("", "package-hash", [package_override]), application_media)
	assert_equal(layered.asset_by_resource("snd ", 147), package_override, "an exact scenario resource overrides the application fallback like Castle's later-opened resource fork")
	var override_diagnostic := layered.resolution_diagnostic("snd ", 147, "test-sound")
	assert_equal([override_diagnostic["sourceOwner"], override_diagnostic["resolvedAssetId"]], ["scenario-package", package_override.id], "resolution diagnostics expose scenario ownership without numeric-ID guessing")
	var fallback_diagnostic := layered.resolution_diagnostic("snd ", 30005, "test-sound")
	assert_equal([fallback_diagnostic["sourceOwner"], fallback_diagnostic["resolvedAssetId"]], ["classic-application", "realmz-application-snd-30005"], "an absent scenario key resolves through the application catalog with explicit ownership")

	var duplicate_override := MediaAsset.new("scenario-snd-147-duplicate", "Duplicate scenario sound 147", "sound", "audio/wav", "snd ", 147, 0, "2".repeat(64), "assets/media/scenario-147-duplicate.wav", 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, -1)
	var ambiguous := ClassicMediaCatalog.new(PackageMediaCatalog.new("", "package-hash", [package_override, duplicate_override]), application_media)
	assert_true(ambiguous.asset_by_resource("snd ", 147) == null, "an ambiguous scenario key never falls through to a plausible built-in sound")
	assert_equal([ambiguous.resolution_diagnostic("snd ", 147, "test-sound")["status"], ambiguous.resolution_diagnostic("snd ", 147, "test-sound")["sourceOwner"]], ["ambiguous", "scenario-package"], "developer diagnostics preserve malformed package ambiguity")


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
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-four presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately")
	assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent")
	assert_false(restored.auto_switch_to_melee, "Auto Weapon Switch persists as an application preference rather than battle state")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true})
	assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density")
	assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")
	assert_true(version_two.auto_switch_to_melee, "legacy settings inherit Castle's bundled default-on Auto Weapon Switch preference")
	var version_three := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 3, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_150, "windowMode": PresentationSettings.WINDOWED})
	assert_not_null(version_three, "schema-three settings migrate")
	assert_equal([version_three.ui_scale_mode, version_three.auto_switch_to_melee], [PresentationSettings.UI_SCALE_150, true], "schema-three settings preserve prior display fields and inherit Castle's default-on preference")
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


func _test_interaction_identity() -> void:
	var request := InteractionRequest.yes_no("request-identity", "Proceed?", "Yes", "No")
	var response := InteractionPresenter.response_for(request, InteractionResponse.YesNoBody.new(true))
	assert_equal(response.request_id, request.request_id, "interaction response preserves request identity")
	assert_equal(response.kind, request.kind, "interaction response preserves request kind")
	assert_true(response.body is InteractionResponse.YesNoBody and (response.body as InteractionResponse.YesNoBody).accepted, "interaction response preserves the exact typed selection")


func _test_lifecycle_interaction() -> void:
	var request := ApplicationLifecycleScript.end_adventure_request(false)
	assert_equal([request.kind, request.body.to_data()["inCombat"], request.body.to_data()["options"].size()], [InteractionRequest.SESSION_LIFECYCLE, false, 3], "field End Adventure exposes explicit save, discard, and cancel operations")
	assert_not_null(InteractionRequest.from_data(request.to_data()), "the typed lifecycle request retains the established interaction wire shape")
	var component := LifecycleInteractionScript.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons: Array[Button] = []
	for node: Node in component.find_children("*", "Button", true, false):
		buttons.append(node as Button)
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
	buttons.clear()
	for node: Node in quit_component.find_children("*", "Button", true, false):
		buttons.append(node as Button)
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


func _test_classic_asset_catalog() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/classic-ui-assets.json"))
	assert_equal(manifest["source_commit"], "86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61", "Classic controls retain exact Remake commit provenance")
	assert_equal(manifest["assets"].size(), 62, "the curated Classic UI and map-marker corpus is complete")
	var ids: Dictionary = {}
	for entry: Dictionary in manifest["assets"]:
		ids[entry["id"]] = true
		assert_true(ResourceLoader.exists(entry["path"], "Texture2D"), "Classic bitmap exists: %s" % entry["id"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["native_width"]), "Classic bitmap width is unchanged: %s" % entry["id"])
		assert_equal(texture.get_height(), int(entry["native_height"]), "Classic bitmap height is unchanged: %s" % entry["id"])
		assert_equal(_sha256(entry["path"]), entry["sha256"], "Classic bitmap hash is unchanged: %s" % entry["id"])
		assert_equal(entry["rendering"]["allowed_scales"], [1.0, 2.0], "Classic bitmap scaling remains integral")
		assert_false(bool(entry["rendering"]["source_pixels_modified"]), "Classic source pixels are never repainted")
	assert_equal(ids.size(), manifest["assets"].size(), "Classic semantic asset IDs are unique")
	assert_not_null(ClassicUiAssetCatalog.texture(&"command.camp"), "runtime asset catalog resolves the Camp bitmap")
	assert_not_null(ClassicUiAssetCatalog.texture(&"command.rest"), "runtime asset catalog resolves the separate held-Rest bitmap")
	var left_party_marker_id: StringName = ClassicMapPresenter.PARTY_MARKER_LEFT_ASSET_ID
	var right_party_marker_id: StringName = ClassicMapPresenter.PARTY_MARKER_RIGHT_ASSET_ID
	var left_party_marker: Dictionary = ClassicUiAssetCatalog.definition(left_party_marker_id)
	var right_party_marker: Dictionary = ClassicUiAssetCatalog.definition(right_party_marker_id)
	assert_not_null(ClassicUiAssetCatalog.texture(left_party_marker_id), "the land presenter resolves the left-facing mounted Classic party CICN")
	assert_not_null(ClassicUiAssetCatalog.texture(right_party_marker_id), "the land presenter resolves the right-facing mounted Classic party CICN")
	assert_equal(ClassicUiAssetCatalog.native_size(left_party_marker_id), Vector2i(32, 32), "the left-facing mounted party CICN retains its native map-cell dimensions")
	assert_equal(ClassicUiAssetCatalog.native_size(right_party_marker_id), Vector2i(32, 32), "the right-facing mounted party CICN retains its native map-cell dimensions")
	assert_equal(int(left_party_marker["source_resource_id"]), 175, "left-facing party-marker provenance records exact built-in CICN 175")
	assert_equal(int(right_party_marker["source_resource_id"]), 186, "right-facing party-marker provenance records exact built-in CICN 186")
	assert_equal(ClassicMapPresenter.party_marker_asset_id_for_direction(Vector2i(-1, 0), right_party_marker_id), left_party_marker_id, "westward movement selects the left-facing mounted party CICN")
	assert_equal(ClassicMapPresenter.party_marker_asset_id_for_direction(Vector2i(1, 0), left_party_marker_id), right_party_marker_id, "eastward movement selects the right-facing mounted party CICN")
	assert_equal(ClassicMapPresenter.party_marker_asset_id_for_direction(Vector2i(0, -1), left_party_marker_id), left_party_marker_id, "northward movement preserves the prior left-facing party CICN")
	assert_equal(ClassicMapPresenter.party_marker_asset_id_for_direction(Vector2i(0, 1), right_party_marker_id), right_party_marker_id, "southward movement preserves the prior right-facing party CICN")
	var party_marker := ClassicUiAssetCatalog.definition(ClassicMapPresenter.PARTY_MARKER_ASSET_ID)
	assert_not_null(ClassicUiAssetCatalog.texture(ClassicMapPresenter.PARTY_MARKER_ASSET_ID), "the land presenter resolves the built-in mounted Classic party CICN")
	assert_equal(ClassicUiAssetCatalog.native_size(ClassicMapPresenter.PARTY_MARKER_ASSET_ID), Vector2i(32, 32), "the mounted party CICN retains its native map-cell dimensions")
	assert_equal(party_marker["source_path"], "base/Realmz/Data Files/The Family Jewels.rsrc", "party-marker bytes come from the pinned base-game resource fork rather than a scenario-local CICN collision")
	assert_equal(party_marker["source_resource_type"], "cicn", "party-marker provenance records its Classic resource type")
	assert_equal(int(party_marker["source_resource_id"]), 186, "party-marker provenance records the exact built-in CICN ID")
	assert_equal(party_marker["source_file_sha256"], "8dbae6c6a418c82250dca93937c5958dacea9874d654c62da4e4dafa184dc85c", "party-marker provenance pins the complete resource-fork bytes")
	assert_equal(party_marker["classic_evidence"]["status"], "source-control-flow", "party-marker semantics are labeled from Castle source rather than inferred from a filename")
	assert_equal(party_marker["classic_evidence"]["commit"], "491816ad60037394f92c428e99c004494d3c28b3", "party-marker behavior retains its pinned Castle evidence commit")
	var fonts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/fonts/font-assets.json"))
	assert_equal(fonts["source_commit"], "2d85e20401920891efb7cd6272d6339685df2820", "bundled fonts retain pinned source provenance")
	for entry: Dictionary in fonts["assets"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "bundled font or license hash matches: %s" % entry["id"])


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _test_stone_surface_tiling() -> void:
	var tile_path := "res://src/presentation/assets/ui/classic-charcoal-slate-tile.png"
	var tile_texture := load(tile_path) as Texture2D
	var tile_image := tile_texture.get_image()
	assert_not_null(tile_image, "the derived seamless stone tile loads")
	assert_equal(tile_image.get_size(), Vector2i(512, 512), "the tiled surface retains the selected 512-pixel texture scale")
	var horizontal_edges_match := true
	var vertical_edges_match := true
	for coordinate: int in range(tile_image.get_height()):
		horizontal_edges_match = horizontal_edges_match and tile_image.get_pixel(0, coordinate) == tile_image.get_pixel(tile_image.get_width() - 1, coordinate)
	for coordinate: int in range(tile_image.get_width()):
		vertical_edges_match = vertical_edges_match and tile_image.get_pixel(coordinate, 0) == tile_image.get_pixel(coordinate, tile_image.get_height() - 1)
	assert_true(horizontal_edges_match, "the derived stone tile has identical left and right edge pixels")
	assert_true(vertical_edges_match, "the derived stone tile has identical top and bottom edge pixels")
	for frame_path: String in ["res://src/presentation/assets/ui/classic-raised-frame.png", "res://src/presentation/assets/ui/classic-inset-frame.png"]:
		var frame_image := (load(frame_path) as Texture2D).get_image()
		for corner: Vector2i in [Vector2i.ZERO, Vector2i(frame_image.get_width() - 1, 0), Vector2i(0, frame_image.get_height() - 1), frame_image.get_size() - Vector2i.ONE]:
			assert_equal(frame_image.get_pixelv(corner).a, 1.0, "generated bevel owns opaque slate at %s corner %s" % [frame_path, str(corner)])
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	var stone := application.get_node("StoneTexture") as TextureRect
	assert_equal(stone.texture.resource_path, tile_path, "the application background uses the seamless derived tile")
	assert_equal(int(stone.stretch_mode), 1, "the application background tiles instead of scaling")
	assert_equal(int(stone.texture_repeat), 2, "the application background enables texture repeat sampling")
	var stage_frame := application.get_node("ClassicShell/StageFrame") as NinePatchRect
	assert_equal(int(stage_frame.axis_stretch_horizontal), 1, "stage-frame horizontal edges tile instead of stretching")
	assert_equal(int(stage_frame.axis_stretch_vertical), 1, "stage-frame vertical edges tile instead of stretching")
	assert_equal(stage_frame.patch_margin_right, 0, "the stage frame leaves its shared roster boundary open")
	assert_true(stage_frame.texture is AtlasTexture and (stage_frame.texture as AtlasTexture).region.size.x == 520.0, "the open-right stage frame crops only the source texture's eight-pixel right edge")
	application.free()
	var ui_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	var popup_panel := ui_theme.get_stylebox("panel", "PopupMenu") as StyleBoxFlat
	assert_true(popup_panel != null and popup_panel.bg_color.a == 1.0, "open menus own an opaque background through the complete popup rectangle")
	assert_true(popup_panel.get_border_width(SIDE_LEFT) > 0 and popup_panel.get_border_width(SIDE_RIGHT) > 0, "popup backgrounds include their outer edge instead of exposing a transparent fringe")
	var menu_normal := ui_theme.get_stylebox("normal", "MenuButton")
	for menu_state: StringName in [&"hover", &"pressed", &"disabled"]:
		var menu_style := ui_theme.get_stylebox(menu_state, "MenuButton")
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_equal(menu_style.get_content_margin(side), menu_normal.get_content_margin(side), "MenuButton %s keeps the measured text margins on every side" % menu_state)
	var open_right_style := ui_theme.get_stylebox("panel", "ClassicOpenRight") as StyleBoxTexture
	assert_true(open_right_style != null and open_right_style.get_texture_margin(SIDE_RIGHT) == 0.0, "shared-stage panels use the open-right frame variation instead of drawing a vertical seam")
	assert_true(ui_theme.get_stylebox("panel", "ClassicSharedStone") is StyleBoxEmpty, "stage overlays expose the already aligned root stone instead of restarting the texture inside another panel")
	var tiled_styles: Array[StyleBox] = [
		ui_theme.get_stylebox("panel", "PanelContainer"),
		ui_theme.get_stylebox("panel", "ClassicInset"),
		ui_theme.get_stylebox("normal", "Button"),
		ui_theme.get_stylebox("hover", "Button"),
		ui_theme.get_stylebox("pressed", "Button"),
		ui_theme.get_stylebox("disabled", "Button"),
	]
	for style: StyleBox in tiled_styles:
		assert_true(style is StyleBoxTexture, "stone-backed panels and buttons use texture styleboxes")
		if style is StyleBoxTexture:
			assert_equal(int(style.axis_stretch_horizontal), 1, "stone stylebox centers tile horizontally")
			assert_equal(int(style.axis_stretch_vertical), 1, "stone stylebox centers tile vertically")


func _test_spatial_stage_visibility() -> void:
	var active_view := GameView.new(1, true, null)
	assert_true(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, true), "the map may render only inside an active Explore play stage")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, false), "full-stage campaign and party-setup overlays suppress the map beneath their shared-stone surface")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"inventory", active_view, true), "non-Explore workspaces suppress spatial renderers")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", GameView.new(0, false, null), true), "an inactive session cannot expose a stale map")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, true), "the battle stage does not appear without detached battlefield facts")
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var combat := CombatState.new("classic.battle.visibility", [], 0, battlefield)
	active_view.combat_view = CombatView.new(combat)
	assert_true(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, true), "the tactical board appears only on the active combat route")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"exploration", active_view, true), "combat facts do not replace the exploration map outside the combat route")
	assert_false(PresentationCoordinator.should_show_battle_stage(&"combat", active_view, false), "full-stage overlays suppress the tactical board")


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
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	assert_true(battlefield.place_character("hero", Vector2i(45, 45)), "battlefield presenter fixture places its active character")
	var monster := MonsterState.new("monster", "classic.monster.1", "Goblin", 4, 4)
	monster.icon_id = 384
	assert_true(battlefield.place_monster(monster.id, Vector2i(47, 45), 0), "battlefield presenter fixture places its target")
	var combat := CombatState.new("classic.battle.presenter", [monster], 0, battlefield)
	combat.set_turn_order(["hero", "monster"])
	var character := CharacterState.new("hero", "Hero", 10, 10)
	var character_views: Array[CharacterView] = [CharacterView.new(character)]
	var combat_view := CombatView.new(combat, [character])
	assert_equal(combat_view.monsters[0].icon_resource_type, "cicn", "monster actors retain Castle's exact lowercase cicn resource type")
	assert_equal(ClassicBattlefieldPresenter.actor_position(combat_view, character_views, "hero"), Vector2i(45, 45), "the camera reads the active character's detached battlefield coordinate")
	assert_equal(ClassicBattlefieldPresenter.actor_position(combat_view, character_views, "monster"), Vector2i(47, 45), "monster turns use the same detached battlefield coordinate source")
	assert_equal(ClassicBattlefieldPresenter.actor_name(combat_view, character_views, "monster"), "Goblin", "the tactical header resolves actor names from detached combatants")
	assert_equal(ClassicBattlefieldPresenter.viewport_cells_for(Vector2(704.0, 396.0)), Vector2i(16, 11), "the Classic tactical viewport keeps native 32-pixel cells and bounds its visible window")
	assert_equal(ClassicBattlefieldPresenter.camera_top_left(Vector2i(45, 45), Vector2i(16, 14)), Vector2i(37, 38), "the active actor remains centered in the ordinary battlefield window")
	assert_equal(ClassicBattlefieldPresenter.camera_top_left(Vector2i(1, 1), Vector2i(16, 14)), Vector2i.ZERO, "battlefield camera centering clamps safely at the 90 by 90 edge")
	assert_true(ClassicBattlefieldPresenter.coordinate_is_visible(Vector2i(45, 45), Vector2i(37, 38), Vector2i(16, 14)), "the active actor lies inside its centered tactical camera")
	assert_equal(ClassicBattlefieldPresenter.click_direction(Vector2i(45, 45), Vector2i(52, 39)), Vector2i(1, -1), "a distant north-east battlefield click selects one north-east step")
	assert_equal(ClassicBattlefieldPresenter.click_direction(Vector2i(45, 45), Vector2i(38, 45)), Vector2i.LEFT, "a distant west battlefield click selects one west step")
	assert_equal(ClassicBattlefieldPresenter.click_direction(Vector2i(45, 45), Vector2i(45, 45)), Vector2i.ZERO, "clicking the active actor does not invent a movement direction")
	var active_cell := Rect2(Vector2(100.0, 100.0), Vector2(32.0, 32.0))
	assert_equal(ClassicBattlefieldPresenter.click_direction_for_point(active_cell, Vector2(180.0, 40.0)), Vector2i(1, -1), "Castle's raw-pointer partition projects a distant north-east click onto one diagonal step")
	assert_equal(ClassicBattlefieldPresenter.click_direction_for_point(active_cell, active_cell.end), Vector2i.ZERO, "Castle's strict comparisons keep the exact lower-right active-cell boundary neutral")
	assert_equal(ClassicBattlefieldPresenter.click_direction_for_point(active_cell, active_cell.end + Vector2.ONE), Vector2i(1, 1), "one pixel beyond both active-cell boundaries selects south-east")
	combat_view.movement_options.append(CombatMoveOptionView.new(Vector2i.RIGHT, BattlefieldStepResult.permitted(Vector2i(46, 45), 2)))
	var game_view := GameView.new(1, true, null)
	game_view.party_members = character_views
	game_view.combat_view = combat_view
	var presenter := ClassicBattlefieldPresenter.new()
	presenter.size = Vector2(704.0, 396.0)
	presenter.present(game_view)
	assert_false(presenter.movement_costs_visible(), "movement costs stay off the tactical art during ordinary combat")
	presenter.set_movement_costs_visible(true)
	assert_true(presenter.movement_costs_visible(), "the explicit inspection state reveals typed movement costs without changing combat")
	var payloads: Array[Dictionary] = []
	presenter.combat_body_submitted.connect(func(body: InteractionResponse.CombatBody) -> void: payloads.append(body.to_data()))
	assert_true(presenter.submit_movement_direction(Vector2i.RIGHT), "keyboard movement selects the matching core-provided tactical option")
	assert_equal(payloads, [{"actorId": "hero", "action": "move", "targetId": "", "destination": [46, 45]}], "the spatial battlefield emits the existing typed combat response payload")
	assert_false(presenter.submit_movement_direction(Vector2i.LEFT), "the battlefield cannot fabricate a movement option absent from the detached view")
	var attack_targeting := CombatTargetingRequest.new(&"combatant", InteractionResponse.CombatBody.new(&"attack", "hero"))
	attack_targeting.candidate_ids.assign(["monster"])
	assert_true(presenter.begin_targeting(attack_targeting), "the tactical board accepts a typed target mode")
	presenter._targeting.select_combatant("monster")
	assert_false(presenter.submit_movement_direction(Vector2i.RIGHT), "target mode suppresses ordinary tactical movement")
	assert_true(presenter.confirm_targeting(), "a legal board selection confirms through the ordinary combat response path")
	assert_equal(payloads[-1], {"actorId": "hero", "action": "attack", "targetId": "monster"}, "battlefield confirmation supplies only the selected stable target ID")
	presenter.free()


func _test_combat_targeting_state() -> void:
	var sequence_body := InteractionResponse.CombatBody.new(&"cast_spell", "hero")
	sequence_body.spell_id = "spell.darts"
	sequence_body.power = 3
	var sequence_request := CombatTargetingRequest.new(&"sequence", sequence_body)
	sequence_request.candidate_ids.assign(["monster.one", "ally.one", "monster.two"])
	sequence_request.maximum_targets = 2
	var sequence := CombatTargetingState.new(sequence_request)
	assert_true(sequence.select_combatant("ally.one"), "the first repeated-spell click is accepted from the typed candidate set")
	assert_true(sequence.select_combatant("monster.one"), "the second repeated-spell click preserves its selection order")
	assert_false(sequence.select_combatant("monster.two"), "the presentation-owned selector enforces the core-provided maximum without submitting")
	assert_equal(sequence.committed_body().target_ids, ["ally.one", "monster.one"], "repeated spell confirmation preserves click order")
	assert_true(sequence.select_combatant("ally.one"), "clicking an already selected repeated target removes it without a session action")
	assert_equal(sequence.committed_body().target_ids, ["monster.one"], "removal does not reorder the remaining repeated targets")

	var area_body := InteractionResponse.CombatBody.new(&"cast_spell", "hero")
	area_body.spell_id = "spell.burst"
	area_body.power = 2
	var area_request := CombatTargetingRequest.new(&"area", area_body)
	area_request.area_offsets.assign([Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT])
	area_request.legal_coordinates.assign([Vector2i(45, 45)])
	var area := CombatTargetingState.new(area_request)
	assert_false(area.select_coordinate(Vector2i(46, 45)), "an area center absent from the rules-owned legal set cannot be confirmed")
	assert_true(area.select_coordinate(Vector2i(45, 45)), "a rules-owned legal area center remains presentation selectable")
	assert_equal(area.committed_body().to_data(), {"actorId": "hero", "action": "cast_spell", "spellId": "spell.burst", "power": 2, "targetId": "", "targetCoordinate": [45, 45], "rotation": 0}, "area confirmation returns the exact coordinate and fixed rotation ABI")


func _test_combat_playback_controller() -> void:
	var previous := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	var final := _combat_playback_view(12, Vector2i(46, 45), Vector2i(47, 45), &"active")
	final.combat_view.round_number = 2
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"combatant_moved", {"actorId": "hero", "from": [45, 45], "to": [46, 45], "automatic": false}),
		DomainEvent.new(&"sound_requested", {"soundId": 632, "waitForCompletion": false}),
		DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 8, "defeated": false, "classicResultEffectResourceId": 160}),
		DomainEvent.new(&"combat_projectile_resolved", {"actorId": "monster", "targetId": "hero", "hit": false, "damage": 0, "defeated": false}),
		DomainEvent.new(&"combat_spell_cast", {"actorId": "hero", "targetId": "monster", "classicEffectResourceId": 12000}),
		DomainEvent.new(&"combat_spell_projectile", {"actorId": "hero", "targetId": "monster", "classicBattleTileId": 201}),
		DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 4, "healing": 0, "resisted": false, "saved": false, "defeated": false, "classicResolutionEffectResourceIds": [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039]}),
		DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 12, "defeated": true}),
	]
	var controller := CombatPlaybackController.new()
	var observed_frames: Array[Dictionary] = []
	var observed_sounds: Array[int] = []
	controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0:
			observed_frames.append({"kind": frame.kind, "text": frame.display_text, "effect": frame.effect_resource_id, "target": frame.target_id, "hidden": frame.hidden_combatant_ids.duplicate()})
	)
	controller.sound_requested.connect(func(event: DomainEvent) -> void: observed_sounds.append(int(event.payload.get("soundId", 0))))
	assert_true(controller.begin(previous, events, final, false), "ordered combat events create a presentation-owned playback transaction")
	assert_true(controller.base_view == previous, "playback retains the previous detached battlefield while committed results are presented")
	while controller.is_active():
		controller.advance(1.0, false)
	var frame_kinds: Array = observed_frames.map(func(frame: Dictionary) -> StringName: return frame["kind"])
	assert_true(frame_kinds.has(&"move_start") and frame_kinds.has(&"move_end"), "movement presents one transient step before the committed destination settles")
	assert_true(frame_kinds.has(&"melee_attack") and frame_kinds.has(&"projectile") and frame_kinds.has(&"spell_projectile"), "melee, missile, and Classic spell projectiles use distinct playback frames")
	assert_equal(frame_kinds.count(&"spell_effect"), 8, "a source-provided Classic spell resolution family presents all eight frames")
	assert_equal(observed_frames.filter(func(frame: Dictionary) -> bool: return frame["kind"] == &"result" and frame["text"] == "8").size(), 1, "damage appears once as a fixed over-target result")
	assert_equal(observed_frames.filter(func(frame: Dictionary) -> bool: return frame["kind"] == &"result" and frame["effect"] == 160).size(), 1, "an armed hit retains Castle's exact result-effect resource for presentation")
	assert_equal(observed_frames.filter(func(frame: Dictionary) -> bool: return frame["kind"] == &"result" and frame["text"] == "Miss").size(), 1, "miss feedback is represented without inventing damage")
	assert_equal(observed_sounds, [632], "sound requests retain their event position and are not bulk-played twice")
	assert_true(frame_kinds.has(&"defeat") and observed_frames[-1]["kind"] == &"actor_cue", "defeat settles before the next-round active-actor cue")

	var enemy_movement := CombatPlaybackController.new()
	var enemy_focus_ids: Array[String] = []
	enemy_movement.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0 and frame.kind != &"actor_cue":
			enemy_focus_ids.append(frame.camera_focus_id)
	)
	assert_true(enemy_movement.begin(previous, [
		DomainEvent.new(&"combatant_moved", {"actorId": "monster", "from": [47, 45], "to": [46, 45], "automatic": true}),
		DomainEvent.new(&"sound_requested", {"soundId": 150, "waitForCompletion": false}),
		DomainEvent.new(&"combatant_moved", {"actorId": "monster", "from": [46, 45], "to": [45, 45], "automatic": true}),
		DomainEvent.new(&"sound_requested", {"soundId": 150, "waitForCompletion": false}),
	], final, false), "multi-step enemy movement creates one ordered playback transaction")
	while enemy_movement.is_active():
		enemy_movement.advance(1.0, false)
	assert_true(not enemy_focus_ids.is_empty() and enemy_focus_ids.all(func(focus_id: String) -> bool: return focus_id == "monster"), "actorless sound frames retain the moving enemy camera focus between adjacent steps")
	var inspected_frame := CombatPlaybackFrame.new(&"move_start", 0.1)
	inspected_frame.camera_focus_id = "monster"
	assert_equal(ClassicBattlefieldPresenter.camera_focus_id_for(inspected_frame, "hero", "hero"), "monster", "combat playback temporarily owns camera focus over a previously inspected combatant")
	var centered_camera := ClassicBattlefieldPresenter.tracked_camera_top_left(Vector2i(-1, -1), Vector2i(47, 45), Vector2i(16, 14))
	assert_equal(ClassicBattlefieldPresenter.tracked_camera_top_left(centered_camera, Vector2i(46, 45), Vector2i(16, 14)), centered_camera, "one-square movement inside the tactical window does not recenter the entire battlefield")
	assert_equal(ClassicBattlefieldPresenter.tracked_camera_top_left(centered_camera, Vector2i(55, 45), Vector2i(16, 14)), ClassicBattlefieldPresenter.camera_top_left(Vector2i(55, 45), Vector2i(16, 14)), "movement recenters only after the actor reaches the current tactical-window edge")
	assert_equal(ClassicBattlefieldPresenter.tracked_camera_top_left(centered_camera, Vector2i(46, 45), Vector2i(16, 14), true), ClassicBattlefieldPresenter.camera_top_left(Vector2i(46, 45), Vector2i(16, 14)), "a turn or explicit focus change still recenters immediately")

	var defeated_spell := CombatPlaybackController.new()
	var defeated_spell_frames: Array[StringName] = []
	defeated_spell.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0:
			defeated_spell_frames.append(frame.kind)
	)
	assert_true(defeated_spell.begin(previous, [DomainEvent.new(&"combat_spell_cast", {"actorId": "hero", "targetId": "monster", "classicEffectResourceId": 12000}), DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "damage": 20, "defeated": true, "classicResolutionEffectResourceIds": [12032, 12033]})], final, false), "a lethal spell still creates its committed result playback")
	while defeated_spell.is_active():
		defeated_spell.advance(1.0, false)
	assert_equal(defeated_spell_frames.count(&"spell_effect"), 0, "Castle's lethal spell path bypasses the ordinary post-result effect family")

	var healing_controller := CombatPlaybackController.new()
	var healing_texts: Array[String] = []
	healing_controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0 and frame.kind == &"result":
			healing_texts.append(frame.display_text)
	)
	assert_true(healing_controller.begin(previous, [DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "hero", "healing": 5, "damage": -5}), DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "resisted": true})], final, false), "healing and resistance feedback share the ordered playback boundary")
	while healing_controller.is_active():
		healing_controller.advance(1.0, false)
	assert_equal(healing_texts, ["+5", "Resist"], "healing and resistance retain distinct fixed result labels")

	var terminal := GameView.new(3, true, null)
	var terminal_controller := CombatPlaybackController.new()
	assert_true(terminal_controller.begin(previous, [DomainEvent.new(&"battle_completed", {"outcome": "victory"})], terminal, false), "terminal combat keeps the previous board available while the final view has already left battle")
	assert_true(terminal_controller.base_view == previous, "terminal playback does not expose the reward workspace before battle visuals settle")
	assert_true(terminal_controller.skip(), "Space-equivalent playback skip settles presentation without a session mutation")
	assert_false(terminal_controller.is_active(), "skipping ends only the cosmetic playback transaction")

	var reduced := CombatPlaybackController.new()
	var reduced_sounds: Array[int] = []
	reduced.sound_requested.connect(func(event: DomainEvent) -> void: reduced_sounds.append(int(event.payload.get("soundId", 0))))
	assert_true(reduced.begin(previous, [DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 3}), DomainEvent.new(&"sound_requested", {"soundId": 650})], final, true), "reduced motion retains the committed playback boundary")
	assert_equal(reduced.frame_count(), 2, "reduced motion keeps ordered audio plus one visual settlement frame")
	while reduced.is_active():
		reduced.advance(1.0, false)
	assert_equal(reduced_sounds, [650], "reduced motion does not drop combat audio")

	var synchronous := CombatPlaybackController.new()
	var synchronous_frames: Array[StringName] = []
	synchronous.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0:
			synchronous_frames.append(frame.kind)
	)
	assert_true(synchronous.begin(previous, [DomainEvent.new(&"sound_requested", {"soundId": 651, "waitForCompletion": true}), DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 3})], final, false), "synchronous Classic audio remains ordered within combat playback")
	synchronous.advance(1.0, false)
	assert_equal(synchronous_frames, [&"sound"], "the synchronous sound frame starts at its ordered event position")
	synchronous.advance(1.0, true)
	assert_equal(synchronous_frames, [&"sound"], "a blocking synchronous sound prevents the next visual frame from becoming visible")
	synchronous.advance(1.0, false)
	assert_equal(synchronous_frames, [&"sound", &"melee_attack"], "visual playback resumes only after the synchronous sound completes")

	var undo_controller := CombatPlaybackController.new()
	var undo_frames: Array[CombatPlaybackFrame] = []
	undo_controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0:
			undo_frames.append(frame)
	)
	assert_true(undo_controller.begin(final, [DomainEvent.new(&"combat_turn_undone", {"actorId": "hero", "from": [46, 45], "to": [45, 45]})], previous, false), "Undo uses the same presentation-only movement playback boundary")
	while undo_controller.is_active():
		undo_controller.advance(1.0, false)
	var undo_move_frames := undo_frames.filter(func(frame: CombatPlaybackFrame) -> bool: return frame.kind in [&"move_start", &"move_end"])
	assert_equal(undo_move_frames.map(func(frame: CombatPlaybackFrame) -> StringName: return frame.kind), [&"move_start", &"move_end"], "Undo presents one reverse battlefield step without advancing simulation")
	assert_equal([undo_move_frames[0].from_coordinate, undo_move_frames[0].to_coordinate], [Vector2i(46, 45), Vector2i(45, 45)], "Undo playback preserves the detached source and destination coordinates")


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
	var setup := router.setup_controller
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var view := GameView.new(1, true, null)
	view.campaign_id = "fixture-creator"
	view.party_setup_available = true
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.title = "Creator Fixture"
	view.campaign_summary.maximum_party_size = 6
	view.campaign_summary.maximum_level = 7
	view.campaign_summary.recommended_party_levels = 6
	view.campaign_summary.maximum_party_levels = 12
	view.campaign_summary.guidance_authored = true
	view.party_setup = PartySetupView.new()
	view.party_setup.available_monster_sets = [0, -1, 1]
	view.party_setup.current_party_levels = 9
	view.party_setup.experience_percent = 66
	view.race_options = [DefinitionOptionView.new("race.human", "Human", "Adaptable.", ["caste.sorcerer"])]
	view.caste_options = [DefinitionOptionView.new("caste.sorcerer", "Sorcerer", "Arcane caster.", ["race.human"])]
	view.portrait_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.human.1", "Human 1", CharacterAppearanceDefinition.PORTRAIT, 257, ["race.human"]))]
	view.combat_icon_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("icon.human.1", "Human 1", CharacterAppearanceDefinition.COMBAT_ICON, 9000, ["race.human"]))]
	var setup_member := CharacterState.new("party.setup.inspection", "Iris", 9, 9)
	setup_member.race_id = "race.human"
	setup_member.caste_id = "caste.sorcerer"
	view.party_members = [CharacterView.new(setup_member)]
	for action_id: StringName in [&"generate_character_draft", &"cancel_character_draft", &"set_character_draft_spells", &"finalize_character", &"import_vault_character", &"begin_adventure", &"remove_party_member"]:
		view.set_action_availability(action_id, action_id in [&"generate_character_draft", &"import_vault_character"], "Unavailable in this fixture state.")
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	var stored := CharacterVaultRevisionView.new()
	stored.character_id = "vault.stored.mira"
	stored.revision_hash = "d".repeat(64)
	stored.name = "Stored Mira"
	stored.level = 3
	stored.race_id = "race.human"
	stored.caste_id = "caste.sorcerer"
	stored.is_current = true
	stored.eligible = true
	var stored_state := CharacterState.new(stored.character_id, stored.name, 8, 8)
	stored_state.level = stored.level
	stored_state.race_id = stored.race_id
	stored_state.caste_id = stored.caste_id
	stored_state.portrait_id = "portrait.human.1"
	stored_state.combat_icon_id = "icon.human.1"
	stored.character = CharacterView.new(stored_state)
	var icon_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	icon_image.fill(Color("67b789"))
	var icon_texture := ImageTexture.create_from_image(icon_image)
	setup.set_appearance_texture(stored_state.portrait_id, icon_texture)
	(view.party_members[0] as CharacterView).portrait_id = stored_state.portrait_id
	router.set_vault_revisions([stored])
	router.present(view)
	var standard_profile := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(standard_profile, Vector2(960, 600))
	assert_equal(setup.setup_overlay.size.x, 936.0, "party assembly covers the complete application width instead of duplicating the persistent in-game roster")
	var setup_surface := setup.setup_overlay.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(setup_surface != null and setup_surface.bg_color.a == 0.0, "party setup exposes the one root-aligned slate tile instead of replacing it with a flat fill")
	assert_equal(setup.setup_mode, &"assembly", "party setup opens on stored-character assembly instead of forcing the creator")
	router.present_party_setup_status("Action failed • That vault character is already represented in the party.", true)
	assert_true(setup.setup_message.visible, "party setup exposes action failures inside its full-stage surface instead of hiding them in the suppressed shell status region")
	assert_equal(setup.setup_message.text, "Action failed • That vault character is already represented in the party.", "party setup preserves the core rejection reason rather than making Add appear inert")
	assert_equal(setup.setup_message.modulate, ClassicScreenRouter.ERROR, "party setup distinguishes a rejected import from ordinary helper text")
	setup.render_party_assembly()
	assert_false(setup.setup_message.visible, "a committed party refresh clears the previous inline setup failure")
	assert_true(setup.setup_overlay.visible and setup.setup_overlay.find_child("ScenarioPartyWorkspace", true, false) != null, "a party-setup GameView keeps the integrated full-stage workspace visible")
	assert_not_null(setup.setup_overlay.find_child("CharacterFilesHeading", true, false), "party-setup GameView keeps the eligible Character Files column mounted")
	assert_not_null(setup.setup_overlay.find_child("PartyHeading", true, false), "party-setup GameView keeps the Current Party column mounted")
	assert_true(setup.setup_overlay.find_children("*", "Button", true, false).all(func(button: Button) -> bool:
		var lower := button.text.to_lower()
		return not lower.contains("archive") and not lower.contains("revision history") and not lower.contains("restore as current")
	), "ordinary party assembly does not expose revision, archive, or restore controls")
	assert_not_null(setup.stored_character_list, "stored characters remain visible beside the six party slots")
	assert_equal(setup.party_list.get_child_count(), 6, "party assembly always exposes the campaign's complete slot capacity")
	var party_scroll := setup.party_list.get_parent() as ScrollContainer
	var party_heading_control := party_scroll.get_parent().get_node("PartyHeading") as Control
	var party_controls_height: float = setup.party_list.get_combined_minimum_size().y + party_heading_control.custom_minimum_size.y + setup.party_setup_options.get_combined_minimum_size().y + setup.begin_button.custom_minimum_size.y
	assert_true(party_controls_height <= setup.setup_overlay.size.y - 20.0, "all six party positions, setup options, and Begin action fit the standard 960 by 600 assembly viewport without scrolling")
	assert_equal(party_scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "the six-slot Current Party surface never hides its final member behind a scrollbar")
	assert_equal([setup.difficulty_option.item_count, setup.monster_set_option.item_count], [5, 3], "party assembly exposes all five Classic difficulty choices and only packaged monster sets")
	assert_equal([setup.monster_set_option.get_item_text(0), setup.monster_set_option.get_item_text(1), setup.monster_set_option.get_item_text(2)], ["Normal Monsters", "Mega Monsters", "Monster Monsters"], "Monster Set is presented in Classic's Normal, Mega, Monster order")
	assert_true(setup.party_guidance_label.text.contains("Maximum 12") and setup.party_guidance_label.text.contains("Recommended 6") and setup.party_guidance_label.text.contains("Current 9") and setup.party_guidance_label.text.contains("66%"), "aggregate level and experience guidance is visible beside setup options")
	var setup_intent_count := intents.size()
	setup.difficulty_option.select(3)
	setup.party_setup_option_changed(3)
	var setup_payload := intents[-1].payload as PlayerIntent.PartySetupOptionsPayload
	assert_equal([intents.size(), intents[-1].kind, setup_payload.difficulty, setup_payload.monster_set], [setup_intent_count + 1, PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS, 1, 0], "party option changes emit stable typed values rather than widget indexes")
	var stored_row := setup.stored_character_list.find_child("StoredCharacter_*", false, false) as PartySetupCharacterRow
	assert_not_null(stored_row, "the current eligible stored revision is an ordinary Add row")
	var stored_portrait := stored_row.find_child("Portrait", true, false) as TextureRect
	assert_not_null(stored_portrait, "each Character Files row exposes the stored character's portrait surface")
	assert_equal(stored_portrait.texture, icon_texture, "Character Files uses the in-game portrait rather than a tactical CICN or placeholder")
	assert_equal(stored_portrait.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "party-picker portraits retain crisp Classic pixels without filtered outlines")
	assert_equal(stored_portrait.custom_minimum_size, Vector2(44.0, 44.0), "Character Files keeps each native 44 by 44 portrait at full size")
	assert_equal([stored_row.mouse_filter, stored_portrait.mouse_filter, (stored_row.find_child("Summary", true, false) as Label).mouse_filter], [Control.MOUSE_FILTER_STOP, Control.MOUSE_FILTER_IGNORE, Control.MOUSE_FILTER_IGNORE], "the visible portrait and summary route drag gestures to the draggable Character Files row")
	var party_portrait := setup.party_list.find_child("Portrait", true, false) as TextureRect
	assert_not_null(party_portrait, "each occupied party position reserves the same portrait surface")
	assert_equal(party_portrait.texture, icon_texture, "the assembled party repeats the exact character portrait for visual matching")
	assert_equal(party_portrait.custom_minimum_size, Vector2(44.0, 44.0), "Current Party also keeps the native portrait at full size")
	var drag_cursor := stored_row._make_drag_cursor_texture()
	assert_not_null(drag_cursor, "dragging a stored character converts the exact portrait into a hardware cursor texture")
	assert_equal(drag_cursor.get_size(), Vector2(2.0, 2.0), "the drag cursor preserves the source portrait dimensions")
	assert_true(absf(drag_cursor.get_image().get_pixel(0, 0).a - 0.62) < 0.005, "the hardware drag cursor is translucent so the drop destination stays visible")
	var character_pane := setup.setup_overlay.find_child("CharacterFilesPane", true, false) as Control
	var party_pane := setup.setup_overlay.find_child("CurrentPartyPane", true, false) as Control
	assert_equal(character_pane.size_flags_stretch_ratio, party_pane.size_flags_stretch_ratio, "Character Files and Current Party receive identical horizontal layout weight")
	var character_heading := setup.setup_overlay.find_child("CharacterFilesHeading", true, false) as CenterContainer
	var party_heading := setup.setup_overlay.find_child("PartyHeading", true, false) as CenterContainer
	assert_equal([character_heading.custom_minimum_size.y, party_heading.custom_minimum_size.y], [28.0, 28.0], "both transfer sections use identically sized centered headings")
	var stored_scroll := setup.setup_overlay.find_child("StoredCharacterScroll", true, false) as ScrollContainer
	var party_slot_scroll := setup.setup_overlay.find_child("PartySlotScroll", true, false) as ScrollContainer
	assert_true(stored_scroll != null and party_slot_scroll != null and stored_scroll.get_parent() == character_heading.get_parent() and party_slot_scroll.get_parent() == party_heading.get_parent(), "Character Files and Current Party lists remain directly beneath their aligned headings")
	var add_stored := stored_row.find_child("AddCharacter", true, false) as Button
	assert_not_null(add_stored, "the balanced Character Files row keeps an explicit Add action")
	assert_true(add_stored != null and not add_stored.disabled, "an eligible Character Files revision remains importable in party setup")
	add_stored.pressed.emit()
	var clicked_import := intents[-1].payload as PlayerIntent.VaultImportPayload
	assert_equal([intents[-1].kind, clicked_import.character_id, clicked_import.revision_hash], [PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, stored.character_id, stored.revision_hash], "click Add submits the stable stored-character revision through the existing typed intent")
	var intent_count_before_drop := intents.size()
	assert_true(setup.party_list._can_drop_data(Vector2.ZERO, stored_row.drag_payload()), "the real draggable row payload is accepted by the complete party-list drop surface")
	setup.party_list._drop_data(Vector2.ZERO, {"kind": "party-setup-character", "characterId": stored.character_id, "revisionHash": stored.revision_hash})
	assert_equal([intents.size(), intents[-1].kind, (intents[-1].payload as PlayerIntent.VaultImportPayload).character_id], [intent_count_before_drop + 1, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, stored.character_id], "dragging onto the party list is a pointer convenience over the same typed import path")
	var inspect_setup := setup.party_list.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Inspect")[0] as Button
	var intent_count_before_inspection := intents.size()
	inspect_setup.pressed.emit()
	assert_true(setup.setup_inspection_overlay.visible, "party setup can open a complete detached character inspection surface before play")
	var inspection_surface := setup.setup_inspection_overlay.get_theme_stylebox("panel") as StyleBoxTexture
	assert_true(inspection_surface != null and inspection_surface.texture.resource_path.ends_with("classic-inset-frame.png"), "party inspection owns an opaque slate-backed inset instead of compositing its sheet over party assembly")
	assert_equal([setup.setup_inspection_overlay.position, setup.setup_inspection_overlay.size, setup.setup_inspection_overlay.z_index, setup.setup_inspection_overlay.clip_contents], [Vector2.ZERO, setup.setup_overlay.size, 1, true], "party inspection fills and clips to the complete setup viewport above its assembly content")
	assert_not_null(setup.setup_inspection_overlay.find_child("PartySetupCharacterSheet", true, false), "setup inspection reuses the complete Classic character sheet instead of a second summary path")
	assert_equal(intents.size(), intent_count_before_inspection, "opening and browsing setup inspection cannot mutate the session")
	assert_true(router.handle_back(), "Back closes setup character inspection before leaving party setup")
	assert_false(setup.setup_inspection_overlay.visible, "closing inspection restores the creator and party assembly surface")
	var create_button: Button = setup.create_character_button
	assert_not_null(create_button, "Create new character is an explicit secondary party-assembly action")
	create_button.pressed.emit()
	assert_equal([setup.setup_mode, setup.creator_step], [&"creator", 0], "Create switches the left pane to Identity while retaining the party pane")
	assert_not_null(setup.creator_page.get_node_or_null("CharacterName"), "Identity alone owns the character-name field")
	assert_false(setup.creator_cancel_button.disabled, "a pristine Identity step can always cancel back to Character Files")
	setup.creator_cancel_button.pressed.emit()
	assert_equal(setup.setup_mode, &"assembly", "Cancel character immediately restores Character Files without requiring a draft mutation")
	assert_true(setup.stored_character_list.visible, "canceling creation restores the stored-character picker")
	create_button.pressed.emit()
	var starting_level := setup.creator_page.get_node_or_null("StartingLevel") as OptionButton
	assert_not_null(starting_level, "Identity exposes the Classic starting-level boundary instead of silently omitting it")
	assert_equal([starting_level.get_item_id(0), starting_level.get_item_id(1), starting_level.get_item_id(2), starting_level.get_item_id(3)], [1, 3, 5, 7], "Identity exposes Castle's fixed choices only through the campaign's maximum level")
	assert_false(starting_level.disabled, "source-backed higher-level creation is an ordinary selectable campaign workflow")
	starting_level.select(starting_level.get_item_index(3))
	assert_equal(setup.creator_page.find_children("*", "ItemList", true, false).size(), 0, "Identity does not spill race, class, or spell lists into the same viewport")
	setup.draft_name = "Mira"
	setup.name_edit.text = "Mira"
	setup.creator_next()
	assert_equal(setup.creator_step, 1, "Continue advances from Identity to Race and Class")
	assert_equal([setup.race_list.get_item_text(0), setup.caste_list.get_item_text(0)], ["Human", "Sorcerer"], "Race renders on the left and filters the class list on the right")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	setup.apply_creator_layout(compact.id)
	assert_true(setup.creator.vertical and setup.race_class_columns.vertical, "compact setup stacks both the creator-party split and Race-Class columns instead of clipping them")
	setup.creator_next()
	assert_equal(setup.creator_step, 2, "Race and Class advances to the dedicated Appearance page")
	setup.creator_next()
	assert_equal(setup.creator_step, 3, "Appearance advances to Review only after requesting a core-owned roll")
	assert_equal(intents[-1].kind, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, "Review is populated through the typed draft-generation intent")
	var draft_payload := intents[-1].payload as PlayerIntent.CharacterDraftPayload
	assert_equal([draft_payload.spec.portrait_id, draft_payload.spec.combat_icon_id], ["portrait.human.1", "icon.human.1"], "Appearance emits stable package identities rather than filenames or numeric widget IDs")
	assert_equal(draft_payload.spec.starting_level, 3, "the selected fixed level crosses the typed intent boundary without presentation-side leveling")
	var generated := CharacterState.new("party.character.1", "Mira", 8, 8)
	generated.race_id = "race.human"
	generated.caste_id = "caste.sorcerer"
	generated.gender = 2
	generated.brawn = 11
	generated.knowledge = 17
	generated.judgment = 14
	generated.agility = 13
	generated.vitality = 12
	generated.luck = 9
	generated.maximum_spell_points = 21
	generated.spell_points = 21
	generated.spellcaster_type = 1
	generated.two_hand = 34
	view.character_draft = CharacterView.new(generated)
	view.character_draft_spell_points_total = 4
	view.character_draft_spell_points_remaining = 4
	var spell := SpellDefinition.new("classic.spell.1101", 1101, "Flame")
	view.character_draft_spell_options = [CharacterSpellOptionView.new(spell, 1, false)]
	view.set_action_availability(&"finalize_character", true)
	router.present(view)
	assert_true(setup.review_label.text.contains("Brawn 11") and setup.review_label.text.contains("SP 21/21") and setup.review_label.text.contains("Two-Hand 34"), "Review renders the generated character and its source-owned combat statistics rather than a pre-roll placeholder")
	assert_equal(setup.setup_message.text, "Review or reroll the generated Classic character.", "the setup guidance advances with the asynchronously populated Review page")
	setup.creator_next()
	assert_equal(setup.creator_step, 4, "Review advances to the dedicated starting-spell page")
	assert_equal(setup.spell_list.item_count, 1, "the spell page renders core-provided Classic options and selection costs")
	setup.creator_next()
	assert_equal(intents[-1].kind, PlayerIntent.Kind.FINALIZE_CHARACTER, "Add to party accepts the reviewed draft without carrying another creation specification")
	router.free()


func _test_begin_adventure_closes_setup_vault() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var setup_view := GameView.new(1, true, null)
	setup_view.campaign_id = "fixture-setup-route"
	setup_view.party_setup_available = true
	setup_view.campaign_summary = CampaignSummaryView.new()
	setup_view.campaign_summary.title = "Setup Route Fixture"
	setup_view.party_members = [CharacterView.new(CharacterState.new("party.route.hero", "Klang", 12, 12))]
	setup_view.set_action_availability(&"import_vault_character", true)
	router.present(setup_view)
	router.open_screen(&"vault")
	assert_equal(router.current_screen(), &"vault", "party setup may open the character vault before play")

	var active_view := GameView.new(2, true, null)
	active_view.campaign_id = setup_view.campaign_id
	active_view.campaign_summary = setup_view.campaign_summary
	active_view.party_members = setup_view.party_members
	router.present(active_view)
	assert_equal(router.current_screen(), &"exploration", "completing party setup dismisses the setup-only vault and opens exploration")
	assert_false(router.full_stage_overlay_visible(), "no setup or campaign overlay survives the Begin Adventure boundary")
	assert_true(router.accepts_exploration_input(), "the newly active campaign accepts exploration input immediately")
	router.open_screen(&"character")
	router.present(active_view)
	assert_equal(router.current_screen(), &"character", "ordinary active-session refreshes preserve the deliberately opened primary workspace")
	router.free()


func _test_character_vault_workspace() -> void:
	var source_character := CharacterState.new("vault.hero", "Mira", 10, 10)
	source_character.level = 3
	source_character.race_id = "classic.race.1"
	source_character.caste_id = "classic.caste.6"
	var source_record := CharacterVaultRecord.new(source_character.id, "realmz-classic-1", "source-campaign", "b".repeat(64), source_character)
	source_record.revision_hash = "a".repeat(64)
	var source_eligibility := CharacterVaultEligibility.new()
	source_eligibility.reasons.append("Source-backed mismatch reason")
	var detached_revision := CharacterVaultRevisionView.from_record(source_record, source_eligibility, true, false)
	assert_equal(detached_revision.eligibility_reasons, ["Source-backed mismatch reason"], "vault eligibility converts into a typed detached reason array")
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var view := GameView.new(3, true, null)
	view.campaign_id = "fixture-vault"
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.title = "Vault Campaign"
	view.set_action_availability(&"import_vault_character", true)
	router.present(view)
	var current := CharacterVaultRevisionView.new()
	current.character_id = "vault.hero"
	current.revision_hash = "a".repeat(64)
	current.name = "Mira"
	current.level = 3
	current.race_id = "classic.race.1"
	current.caste_id = "classic.caste.6"
	current.portrait_id = "realmz-portrait-257"
	current.source_campaign_id = "source-campaign"
	current.source_package_hash = "b".repeat(64)
	current.publication_label = "Created after the first expedition"
	current.is_current = true
	current.eligible = true
	current.character = CharacterView.new(source_character)
	var archived := CharacterVaultRevisionView.new()
	archived.character_id = current.character_id
	archived.revision_hash = "c".repeat(64)
	archived.name = current.name
	archived.level = 2
	archived.race_id = current.race_id
	archived.caste_id = current.caste_id
	archived.source_campaign_id = current.source_campaign_id
	archived.source_package_hash = current.source_package_hash
	archived.archived = true
	archived.eligibility_reasons = ["Item 'classic.item.missing' is not defined by this campaign."]
	archived.character = CharacterView.new(source_character)
	router.set_vault_revisions([current, archived])
	router.open_screen(&"vault")
	var vault_body := router.find_child("ScreenBody", true, false) as VBoxContainer
	var labels: Array[String] = []
	for node: Node in router.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Eligibility for Vault Campaign")), "the vault states which campaign owns the current eligibility decision")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("classic.item.missing")), "an ineligible revision exposes its exact package mismatch")
	var restore_events: Array[Array] = []
	router.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: restore_events.append([character_id, revision_hash]))
	var import_buttons: Array[Button] = []
	var inspect_buttons: Array[Button] = []
	var back_button: Button
	var archive_button: Button
	var restore_button: Button
	for node: Node in router.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Back":
			back_button = button
		elif button.text == "Import this revision":
			import_buttons.append(button)
		elif button.text == "Inspect character":
			inspect_buttons.append(button)
		elif button.text == "Archive character":
			archive_button = button
		elif button.text == "Restore as current":
			restore_button = button
	assert_equal(import_buttons.size(), 2, "each immutable revision renders its own import decision")
	assert_equal(inspect_buttons.size(), 2, "eligible and ineligible vault revisions both expose mutation-free inspection")
	assert_not_null(back_button, "vault workspace exposes a visible return action")
	assert_true(import_buttons.any(func(button: Button) -> bool: return not button.disabled), "the current eligible revision can be imported")
	assert_true(import_buttons.any(func(button: Button) -> bool: return button.disabled and button.tooltip_text.contains("Restore")), "archived revisions must be restored before import")
	assert_not_null(archive_button, "the current revision exposes recoverable archive rather than delete")
	assert_not_null(restore_button, "archived history exposes an explicit recovery action")
	inspect_buttons[-1].pressed.emit()
	assert_not_null(vault_body.find_child("VaultCharacterSheet", true, false), "vault inspection reuses the complete detached character sheet")
	var inspection_labels := vault_body.find_children("*", "Label", true, false)
	assert_true(inspection_labels.any(func(label: Label) -> bool: return label.text.contains("Not eligible") or label.text.contains("classic.item.missing")), "ineligible inspection keeps exact campaign mismatch reasons visible")
	var inspection_back := vault_body.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Back to character vault")[0] as Button
	inspection_back.pressed.emit()
	assert_true(vault_body.find_children("*", "Button", true, false).any(func(button: Button) -> bool: return button.text == "Inspect character"), "Back returns from vault inspection to the revision list")
	var refreshed_restore := vault_body.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Restore as current")[0] as Button
	refreshed_restore.pressed.emit()
	assert_equal(restore_events, [[archived.character_id, archived.revision_hash]], "recovery identifies the exact immutable revision")
	router.free()


func _test_field_spell_workspace() -> void:
	var body := VBoxContainer.new()
	var controller := SpellsWorkspaceController.new()
	var view := GameView.new(5, true, null)
	view.party_summary = PartySummaryView.new()
	view.party_summary.camping = false
	var character := CharacterState.new("field.caster", "Aster", 12, 12)
	character.spell_points = 12
	character.maximum_spell_points = 12
	var character_view := CharacterView.new(character)
	var definition := SpellDefinition.new("classic.spell.field", 1101, "Field Bolt", "A bounded source-backed field spell.")
	definition.cost = 2
	definition.in_camp = true
	var spell_view := SpellView.new(definition)
	spell_view.power_levels = [1, 2]
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true)
	spell_view.scroll_power_levels = [1, 2]
	spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", true)
	character_view.spells.append(spell_view)
	character.bind_fast_spell(0, definition.id, 2)
	character_view.fast_spells = []
	for index: int in 10:
		character_view.fast_spells.append(FastSpellBindingView.new(index, character.fast_spell_at(index), definition if index == 0 else null))
	character_view.fast_spells[0].activation = ActionAvailabilityView.new(&"cast_spell", true)
	character.write_scroll(0, definition.id, 2)
	character_view.scrolls = [SpellScrollView.new(0, character.scroll_at(0), definition)]
	character_view.scrolls[0].use = ActionAvailabilityView.new(&"cast_spell", true)
	view.party_members = [character_view]
	view.set_action_availability(&"cast_spell", true)
	view.set_action_availability(&"set_fast_spell", true)
	var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	controller.present(body, view, null, 1.0)
	var cast_power_two: Button = null
	var make_power_two: Button = null
	var use_scroll: Button = null
	var scroll_slot_label: Label = null
	var fast_slot_label: Label = null
	for label: Label in body.find_children("*", "Label", true, false):
		if label.text.begins_with("Slot 1"):
			if label.text == "Slot 1":
				fast_slot_label = label
			else:
				scroll_slot_label = label
	for button: Button in body.find_children("*", "Button", true, false):
		if button.text == "Cast P2 (4 SP)":
			cast_power_two = button
		if button.text == "Make P2 Scroll (8 SP)":
			make_power_two = button
		if button.text == "Use":
			use_scroll = button
	assert_not_null(cast_power_two, "the field spell workspace renders explicit power and cost choices")
	assert_not_null(make_power_two, "the field spell workspace renders source-backed scroll scribing cost choices")
	assert_not_null(use_scroll, "the field spell workspace renders the character's fixed scroll-case slots")
	assert_not_null(scroll_slot_label, "the field spell workspace labels each fixed scroll slot")
	assert_not_null(fast_slot_label, "the spellbook renders all ten character-owned Fast Spell rows")
	assert_equal(body.find_children("*", "OptionButton", true, false).filter(func(option: OptionButton) -> bool: return option.get_parent() is HBoxContainer).size(), 10, "each Fast Spell slot exposes one explicit binding picker")
	if scroll_slot_label != null:
		assert_true(scroll_slot_label.get_parent() is HBoxContainer, "scroll-slot identity and action share one fixed row instead of reflowing into narrow columns")
		assert_equal(scroll_slot_label.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "scroll-slot text receives the row's available width at the minimum viewport")
	if cast_power_two != null:
		cast_power_two.pressed.emit()
	if make_power_two != null:
		make_power_two.pressed.emit()
	if use_scroll != null:
		use_scroll.pressed.emit()
	assert_equal(intents.size(), 3, "field cast, scroll scribing, and scroll use each emit one intent")
	if intents.size() == 3:
		var cast_payload := intents[0].payload as PlayerIntent.SpellPayload
		var scribe_payload := intents[1].payload as PlayerIntent.SpellPayload
		var scroll_payload := intents[2].payload as PlayerIntent.SpellPayload
		assert_equal([intents[0].kind, cast_payload.power], [PlayerIntent.Kind.CAST_SPELL, 2], "the selected field power crosses the typed intent boundary")
		assert_equal([scribe_payload.operation, scribe_payload.power], [&"make-scroll", 2], "scroll scribing crosses the same typed spell intent boundary")
		assert_equal([scroll_payload.operation, scroll_payload.scroll_slot], [&"use-scroll", 0], "scroll use carries the exact fixed slot through the typed intent boundary")
	body.free()


func _test_inventory_workspace() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-ui", 10, "Longsword", "Sword", "A balanced one-handed sword.")
	definition.icon_id = 321
	definition.item_type = 2
	definition.weight = 12
	definition.cost = 45
	definition.damage_bonus = 2
	definition.vs_small = 6
	var source := CharacterState.new("inventory.ui.source", "Alis", 10, 10)
	source.maximum_load = 100
	source.carried_load = 12
	source.set_inventory([ItemInstance.new("inventory.ui.item", definition.id, 0, false, true)])
	var destination := CharacterState.new("inventory.ui.destination", "Borin", 10, 10)
	destination.maximum_load = 100
	var source_view := CharacterView.new(source)
	source_view.items.clear()
	var item_view := ItemView.new(source.inventory()[0], definition)
	item_view.actions.equip = ActionAvailabilityView.new(&"equip_item", true)
	item_view.actions.use = ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
	item_view.actions.drop = ActionAvailabilityView.new(&"drop_item", true)
	item_view.actions.trade = ActionAvailabilityView.new(&"trade_item", true)
	item_view.actions.trade_targets.append(ItemTransferTargetView.new(destination.id, destination.name, true))
	source_view.items.append(item_view)
	var view := GameView.new(4, true, null)
	view.party_members = [source_view, CharacterView.new(destination)]
	var workspace := InventoryWorkspaceController.new()
	var body := VBoxContainer.new()
	var intents: Array[PlayerIntent] = []
	workspace.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	workspace.present(body, view, null, 1.0)
	var buttons: Array[BaseButton] = []
	var labels: Array[String] = []
	for node: Node in body.find_children("*", "BaseButton", true, false):
		buttons.append(node as BaseButton)
	for node: Node in body.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Alis") and (button as Button).text.contains("12/100")), "inventory workspace selects a character before an item")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Longsword")), "inventory workspace renders a selectable carried-item list")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text == "Equip" and not button.disabled), "an action without donor bitmap art remains visible as a labeled typed control")
	var trade_button: BaseButton = null
	for button: BaseButton in buttons:
		if button is Button and (button as Button).text == "Give to Borin":
			trade_button = button
	assert_not_null(trade_button, "inventory workspace exposes each typed trade recipient")
	assert_true(trade_button != null and not trade_button.disabled, "a rules-authorized trade recipient is actionable")
	assert_false(buttons.any(func(button: BaseButton) -> bool: return (button is Button and (button as Button).text == "Store") or button.tooltip_text == "Store"), "ordinary inventory does not invent Remake's non-Classic player stash")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("opcode 36 equipment escrow")), "the workspace explains why scenario-owned equipment escrow is not a stash")
	assert_true(labels.any(func(text: String) -> bool: return text == "Classic record"), "inventory inspection presents the source-backed item record as a distinct section")
	assert_true(labels.any(func(text: String) -> bool: return text == "Damage"), "inventory inspection presents Castle's damage record")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Use — This item's use effect is not implemented")), "disabled item actions remain readable without relying on hover tooltips")
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text.contains("use effect") and button.tooltip_text.contains("not implemented")), "unsafe item use remains visible with an exact disabled reason")
	if trade_button != null:
		trade_button.pressed.emit()
	assert_equal(intents.size(), 1, "trade emits exactly one typed intent")
	if not intents.is_empty():
		assert_equal(intents[0].kind, PlayerIntent.Kind.TRADE_ITEM, "trade never mutates gameplay from presentation")
		assert_equal((intents[0].payload as PlayerIntent.ItemActionPayload).destination_character_id, destination.id, "trade intent carries the stable recipient identity")
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
	var buttons: Array[Button] = []
	var labels: Array[String] = []
	for node: Node in body.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	for node: Node in body.find_children("*", "Label", true, false):
		labels.append((node as Label).text)
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


func _test_exploration_money_and_service_commands() -> void:
	var exploration_commands := ClassicCommandCatalog.for_context(&"exploration")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"money" and definition["availability"] == &"money_action"), "ordinary exploration exposes Castle's Money/Swap workspace without a hidden route shortcut")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"service" and definition["availability"] == &"service_action"), "ordinary exploration exposes the current location service")


func _test_party_order_workspace() -> void:
	var alis := CharacterState.new("party.order.alis", "Alis", 10, 10)
	alis.level = 2
	alis.caste_id = "fighter"
	var borin := CharacterState.new("party.order.borin", "Borin", 12, 12)
	borin.level = 3
	borin.caste_id = "priest"
	var cerys := CharacterState.new("party.order.cerys", "Cerys", 8, 8)
	cerys.level = 4
	cerys.caste_id = "sorcerer"
	var view := GameView.new(8, true, null)
	view.campaign_id = "party-order-fixture"
	view.party_members = [CharacterView.new(alis), CharacterView.new(borin), CharacterView.new(cerys)]
	view.set_action_availability(&"reorder_party", true)
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var intents: Array[PlayerIntent] = []
	router.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	router.present(view)
	router.open_screen(&"character")
	assert_equal(router.party_order_draft_ids(), [alis.id, borin.id, cerys.id], "the Party Order workspace starts from detached session order")
	var buttons: Array[Button] = []
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var first_down: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down" and not button.disabled)[0]
	first_down.pressed.emit()
	assert_equal(router.party_order_draft_ids(), [borin.id, alis.id, cerys.id], "Move Down changes presentation-owned draft order only")
	assert_equal(intents.size(), 0, "staging a slot move cannot mutate the session")
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var cancel: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Cancel Order Changes")[0]
	assert_false(cancel.disabled, "a changed draft exposes safe cancellation")
	cancel.pressed.emit()
	assert_equal(router.party_order_draft_ids(), [alis.id, borin.id, cerys.id], "Cancel restores detached order without reproducing Castle's cleared-track write")
	assert_equal(intents.size(), 0, "Cancel emits no gameplay intent")
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	first_down = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down" and not button.disabled)[0]
	first_down.pressed.emit()
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var apply: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Apply Party Order")[0]
	assert_false(apply.disabled, "a changed complete permutation can be applied")
	apply.pressed.emit()
	assert_equal(intents.size(), 1, "Apply emits exactly one typed mutation")
	assert_equal([intents[0].kind, (intents[0].payload as PlayerIntent.StringListPayload).values], [PlayerIntent.Kind.REORDER_PARTY, [borin.id, alis.id, cerys.id]], "the presenter emits the complete stable-ID permutation")
	view.set_action_availability(&"reorder_party", false, "Party order is unavailable during battle.")
	router.present(view)
	buttons.clear()
	for node: Node in router.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	var blocked_move: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Move Down")[0]
	assert_true(blocked_move.disabled and blocked_move.tooltip_text.contains("battle"), "unavailable Party Order remains visible with the core-owned reason")
	router.free()


func _test_character_sheet_workspace() -> void:
	var character := CharacterState.new("character.sheet", "A Character Name Long Enough To Exercise Responsive Wrapping", -10, 18)
	character.level = 7
	character.experience = 12_345
	character.age_days = 37 * 365
	character.age_group = 3
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.2"
	character.gender = 2
	character.brawn = 17
	character.knowledge = 14
	character.judgment = 13
	character.agility = 16
	character.vitality = 15
	character.luck = 12
	character.to_hit = 28
	character.dodge = 31
	character.missile = 24
	character.two_hand = 9
	character.hand_to_hand = 4
	character.damage_bonus = 3
	character.armor = 42
	character.magic_resistance = 11
	character.normal_attacks = 2
	character.attack_bonus = 1
	character.spell_points = 9
	character.maximum_spell_points = 22
	character.maximum_movement = 14
	character.carried_load = 63
	character.maximum_load = 120
	character.money.gold = 77
	character.money.gems = 2
	character.money.jewelry = 1
	character.portrait_id = "portrait.257"
	character.combat_icon_id = "combat-icon.9000"
	character.conditions.set_value(ConditionRules.TANGLED, 4)
	character.conditions.set_value(ConditionRules.SHIELD_FROM_HITS, 2)
	character.conditions.set_value(9, 3)
	character.conditions.set_value(ConditionRules.STRONG, 1)
	character.conditions.set_value(26, -1)
	character.conditions.set_value(ConditionRules.HINDERED_ATTACKS, 3)
	character.conditions.set_value(ConditionRules.HINDERED_DEFENSE, 2)
	character.conditions.set_value(ConditionRules.DEFENSE_BONUS, 5)
	character.set_save_value(0, 61)
	character.set_special_value(1, -2)
	character.set_ability_value(4, 35)
	character.set_ability_value(13, 18)
	var changes: Array[PackedInt32Array] = []
	for band_index: int in 5:
		var row := PackedInt32Array()
		row.resize(15)
		row.fill(0)
		row[band_index] = band_index + 1
		changes.append(row)
	var race := RaceDefinition.new(character.race_id, 1, "Human", [], [], [], [], [], [Vector2i(10, 19), Vector2i(20, 29), Vector2i(30, 39), Vector2i(40, 49), Vector2i(50, 59)], changes, 90, false, 12, 5, 3, 4, 2, 5, true, 0, 0, 0, 0, "A long source-backed race description used to prove wrapping.")
	var caste := CasteDefinition.new(character.caste_id, 2, "Fighter", [], [], [], [], Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 1, 2, 1, 2, 3, 4, 1, 5, 0, true, true, 0, 0, 0, Vector2i.ZERO, "A source-backed class description.")
	var content := RealmzContent.new("character-sheet", "0".repeat(64), "sheet", "realmz-classic-1", "", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [race], [caste])
	var character_view := CharacterView.new(character, content)
	assert_equal([character_view.gender_name, character_view.attacks_per_round, character_view.attack_bonus, character_view.defense_bonus, character_view.gold, character_view.gems, character_view.jewelry], ["Female", "3/2", 36, 45, 77, 2, 1], "the detached sheet preserves Castle identity, computed display bonuses, attack cadence, and three personal money denominations")
	assert_true(character_view.conditions.any(func(metric: CharacterMetricView) -> bool: return metric.name == "Poisoned"), "conditions use Castle names instead of leaking raw slots into presentation")
	assert_true(character_view.conditions.any(func(metric: CharacterMetricView) -> bool: return metric.name == "Turned to Stone" and metric.detail == "Permanent"), "signed permanent conditions remain explicit")
	assert_equal([character_view.saving_throws.size(), character_view.saving_throws[0].name, character_view.saving_throws[0].value], [8, "Charm", 61], "all eight Classic saving throws are detached with stable labels")
	assert_equal([character_view.special_modifiers[0].name, character_view.special_modifiers[0].value, character_view.abilities[0].name, character_view.abilities[1].name], ["Undead", -2, "Detect Secret", "Turn Undead"], "source-backed special and ability identities remain distinct")
	assert_equal([character_view.age_bands.size(), character_view.age_bands[2].active, character_view.age_bands[2].changes[2].value], [5, true, 3], "the read model derives the active age band without mutating session state")
	assert_equal(character.age_group, 3, "opening character details cannot reproduce Castle's inspection-time age-group write")
	assert_false(character_view.record_available, "untracked lifetime prestige history remains explicitly unavailable")
	assert_true(character_view.record_unavailable_reason.to_lower().contains("lifetime combat history"), "the prestige gap has a concrete player-facing reason")
	var sheet := ClassicCharacterSheet.new()
	var selections: Array[String] = []
	var appearance_changes: Array[Dictionary] = []
	sheet.character_selected.connect(func(character_id: String) -> void: selections.append(character_id))
	sheet.appearance_change_requested.connect(func(character_id: String, appearance_kind: StringName, appearance_id: String) -> void: appearance_changes.append({"characterId": character_id, "kind": appearance_kind, "appearanceId": appearance_id}))
	var portrait_options: Array[CharacterAppearanceOptionView] = [
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.257", "Portrait 257", CharacterAppearanceDefinition.PORTRAIT, 257, [character.race_id])),
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.258", "Portrait 258 with a deliberately long package label", CharacterAppearanceDefinition.PORTRAIT, 258, [character.race_id])),
	]
	var icon_options: Array[CharacterAppearanceOptionView] = [
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("combat-icon.9000", "Combat icon 9000", CharacterAppearanceDefinition.COMBAT_ICON, 9000, [character.race_id])),
		CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("combat-icon.9001", "Combat icon 9001", CharacterAppearanceDefinition.COMBAT_ICON, 9001, [character.race_id])),
	]
	sheet.present([character_view], character_view.id, {}, 1.0, &"overview", portrait_options, icon_options, ActionAvailabilityView.new(&"change_character_appearance", true))
	var buttons: Array[Button] = []
	for node: Node in sheet.find_children("*", "Button", true, false):
		buttons.append(node as Button)
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Overview"), "the sheet exposes a bounded overview tab")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Conditions & Saves"), "the sheet exposes conditions and all saves without raw indices")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Equipment"), "the sheet retains the Classic equipment subworkspace")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Abilities"), "the sheet retains source special and ability values")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Spells"), "the sheet exposes known spells and scroll slots")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Appearance"), "the sheet exposes the separate Classic portrait and tactical-icon workspace")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Race, Class & Aging"), "the sheet exposes source-backed definitions and all five age bands")
	assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Lifetime Record"), "the missing prestige record remains visible rather than silently omitted")
	var equipment_button := buttons.filter(func(button: Button) -> bool: return button.text == "Equipment")[0] as Button
	equipment_button.pressed.emit()
	var equipment_heading_detail := sheet.find_child("HeadingDetail", true, false) as Label
	assert_not_null(equipment_heading_detail, "the equipment heading exposes its slot-count detail")
	assert_equal(equipment_heading_detail.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "heading details reserve horizontal space instead of collapsing into one-character columns at 960x600")
	var record_button := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Lifetime Record")[0] as Button
	record_button.pressed.emit()
	var labels := sheet.find_children("*", "Label", true, false)
	assert_true(labels.any(func(label: Label) -> bool: return label.text.to_lower().contains("lifetime combat history")), "the Record tab explains why Castle prestige cannot yet be calculated")
	assert_equal(selections.size(), 0, "tab navigation is presentation-owned and cannot mutate the session")
	var appearance_button := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Appearance")[0] as Button
	appearance_button.pressed.emit()
	var portrait_picker := sheet.find_child("PortraitPicker", true, false) as OptionButton
	assert_not_null(portrait_picker, "the Appearance tab mounts a package-backed portrait picker")
	assert_equal(portrait_picker.item_count, 2, "the picker exposes every detached portrait option")
	portrait_picker.select(1)
	portrait_picker.item_selected.emit(1)
	assert_equal(appearance_changes.size(), 0, "previewing a portrait remains presentation-only")
	var apply_portrait := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Apply Portrait")[0] as Button
	assert_false(apply_portrait.disabled, "a changed portrait enables the explicit commit action")
	apply_portrait.pressed.emit()
	assert_equal(appearance_changes, [{"characterId": character_view.id, "kind": CharacterAppearanceDefinition.PORTRAIT, "appearanceId": "portrait.258"}], "Apply emits one typed stable-ID portrait request")
	var icon_picker := sheet.find_child("CombaticonPicker", true, false) as OptionButton
	assert_not_null(icon_picker, "the Appearance tab keeps combat-icon selection independent")
	icon_picker.select(1)
	icon_picker.item_selected.emit(1)
	var discard := sheet.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.text == "Discard Appearance Changes")[0] as Button
	discard.pressed.emit()
	assert_equal(appearance_changes.size(), 1, "Discard restores local previews without emitting another mutation")
	sheet.free()


func _test_party_roster() -> void:
	var roster_scene := load("res://src/presentation/screens/classic_party_roster.tscn") as PackedScene
	var roster := roster_scene.instantiate() as ClassicPartyRoster
	roster._heading = roster.get_node("RosterColumn/Heading") as Label
	roster._party_list = roster.get_node("RosterColumn/PartyScroll/PartyList") as VBoxContainer
	var character := CharacterState.new("party.roster", "Mira", 10, 10)
	character.race_id = "classic.race.1"
	character.caste_id = "classic.caste.6"
	var view := GameView.new(1, true, null)
	view.party_members = [CharacterView.new(character)]
	roster.present(view)
	var rows := roster.find_children("*", "Button", true, false)
	assert_equal(rows.size(), 1, "the populated roster creates one character control")
	if not rows.is_empty():
		var row := rows[0] as Button
		assert_equal(row.get_theme_constant("icon_max_width"), 42, "portrait width uses the supported Button theme constant")
	var combat := CombatState.new("battle.roster-auto")
	combat.set_turn_order([character.id])
	view.combat_view = CombatView.new(combat)
	view.combat_view.auto_character_ids = [character.id]
	roster.present(view)
	var toggles := roster.find_children("CombatAuto", "CheckButton", true, false)
	assert_equal(toggles.size(), 1, "the combat roster exposes one persistent Auto toggle per party member")
	if not toggles.is_empty():
		assert_true((toggles[0] as CheckButton).button_pressed and not (toggles[0] as CheckButton).disabled, "a live character's saved persistent Auto state is visible and actionable")
	character.current_health = 0
	view.party_members = [CharacterView.new(character)]
	roster.present(view)
	var dead_toggles := roster.find_children("CombatAuto", "CheckButton", true, false)
	assert_equal(dead_toggles.size(), 1, "the dead roster row retains an explanatory Auto control")
	if not dead_toggles.is_empty():
		assert_true((dead_toggles[0] as CheckButton).disabled and not (dead_toggles[0] as CheckButton).tooltip_text.is_empty(), "dead characters cannot submit a core-rejected persistent Auto toggle")
	roster.free()


func _test_scene_composition() -> void:
	var shell_scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := shell_scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell, "the canonical application shell is scene-backed")
	var router := shell.get_node("ScreenRouter") as Control
	var roster := shell.get_node("PartyRoster") as Control
	var bottom_region := shell.get_node("BottomRegion") as Control
	assert_not_null(router, "the shell owns one workspace router")
	assert_not_null(shell.get_node("PartyRoster"), "the shell owns the persistent six-slot roster")
	assert_true((roster as PanelContainer).get_theme_stylebox("panel") is StyleBoxEmpty, "the roster shares the uninterrupted root stone surface instead of restarting a second framed tile at the stage boundary")
	assert_equal((bottom_region as PanelContainer).theme_type_variation, &"ClassicOpenRight", "the bottom narrative region also leaves the shared roster boundary open")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/NarrativeWell"), "the shell owns a Classic narrative well")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/CommandPanel"), "the shell owns a contextual command deck")
	var picture_backing := shell.get_node("PictureStage/PictureBacking") as TextureRect
	var picture_frame := shell.get_node("PictureStage/PictureFrame") as NinePatchRect
	assert_equal(int(picture_backing.stretch_mode), TextureRect.STRETCH_TILE, "scenario-picture stone fills the complete overlay without stretching")
	assert_equal(int(picture_backing.texture_repeat), CanvasItem.TEXTURE_REPEAT_ENABLED, "scenario-picture backing repeats seamlessly beneath transparent bevel pixels")
	assert_false(picture_frame.draw_center, "the scenario-picture bevel is an overlay around the independently filled stone center")
	assert_true(picture_frame.get_index() > shell.get_node("PictureStage/PictureMargin").get_index(), "the bevel draws over the filled picture surface without exposing the map between layers")
	assert_equal(shell.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the structural shell cannot mask earlier root-level interaction controls")
	assert_equal(router.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the full-window router cannot mask menus or sibling controls")
	assert_true(router.get_index() > roster.get_index() and router.get_index() > bottom_region.get_index(), "modal router children are ordered above roster and textbox input regions")
	assert_true(router.z_index > bottom_region.z_index, "workspace controls remain clickable where a scrolling route extends into the persistent bottom-region rows")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(960, 600), Vector2(1280, 720), Vector2(1920, 1080)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var campaign_rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
		var stage_width := viewport_size.x - profile.party_width
		assert_true(campaign_rect.position.x >= 0.0 and campaign_rect.position.x + campaign_rect.size.x <= stage_width, "campaign controls stay out of the roster hit region at %s" % str(viewport_size))
		assert_true(campaign_rect.position.y >= profile.menu_height and campaign_rect.position.y + campaign_rect.size.y <= viewport_size.y, "campaign controls stay inside the viewport at %s" % str(viewport_size))
		var vault_router := ClassicScreenRouter.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(vault_router)
		vault_router.initialize()
		vault_router.set_layout_profile(profile, viewport_size)
		vault_router.open_screen(&"vault")
		var vault_workspaces := vault_router.get_children().filter(func(child: Node) -> bool: return child is ClassicRouteScreen)
		var vault_workspace := vault_workspaces[0] as ClassicRouteScreen if not vault_workspaces.is_empty() else null
		var modal_rect := Rect2(12.0, profile.menu_height + 8.0, viewport_size.x - 24.0, viewport_size.y - profile.menu_height - 16.0)
		var expected_vault_rect := Rect2(modal_rect.position + Vector2(8.0, 8.0), modal_rect.size - Vector2(16.0, 16.0))
		assert_not_null(vault_workspace, "Character Files mounts one typed primary workspace at %s" % str(viewport_size))
		if vault_workspace != null:
			assert_equal([vault_workspace.position, vault_workspace.size], [expected_vault_rect.position, expected_vault_rect.size], "Character Files receives the complete stage width at %s" % str(viewport_size))
		assert_true(vault_router.full_stage_overlay_visible(), "Character Files suppresses the roster, textbox, and command deck at %s" % str(viewport_size))
		vault_router.free()
	assert_false(shell.has_node("TopBar"), "the dashboard title bar is removed")
	assert_false(shell.has_node("RightPanel"), "the persistent Chronicle column is removed")
	shell.free()
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	assert_true(application.get_node("InteractionPanel").get_index() > application.get_node("ClassicShell").get_index(), "AP and encounter presenter controls are ordered above the shell for mouse input")
	assert_true(application.get_node("BattlefieldMap") is ClassicBattlefieldPresenter, "the root application owns one detached tactical battlefield presenter")
	var application_shell := application.get_node("ClassicShell") as Control
	var application_router := application.get_node("ClassicShell/ScreenRouter") as Control
	var interaction := application.get_node("InteractionPanel") as InteractionPresenter
	interaction.visible = true
	assert_true(interaction.get_index() > application.get_node("BattlefieldMap").get_index(), "a visible mandatory interaction claims pointer order above the tactical battlefield")
	assert_true(interaction.z_index > CampaignPartySetupController.MAXIMUM_MODAL_Z_INDEX + application_router.z_index + application_shell.z_index, "the dedicated interaction layer draws above every nested setup modal instead of allowing stale workspace labels through")
	assert_equal(interaction.mouse_filter, Control.MOUSE_FILTER_STOP, "the blocking interaction surface, not its decorative backing, owns every pointer inside the tactical stage")
	var standard_textbox_rect := RealmzApplication.classic_textbox_rect(Rect2(0.0, 28.0, 704.0, 396.0), 176.0)
	assert_equal(standard_textbox_rect, Rect2(0.0, 424.0, 704.0, 176.0), "textbox interactions replace the complete shell bottom region without exposing an inset frame")
	assert_true(InteractionPresenter.uses_textbox_region(InteractionRequest.acknowledge("edge-to-edge", "Continue")), "Classic acknowledgements use the edge-to-edge textbox surface")
	var combat_request := ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	assert_true(InteractionPresenter.uses_textbox_region(combat_request), "battle controls occupy the bottom Classic control region without replacing the tactical board")
	var combat_rect := RealmzApplication.classic_combat_rect(Vector2(960.0, 600.0), 176.0)
	assert_equal(combat_rect, Rect2(0.0, 424.0, 960.0, 176.0), "combat claims the full Classic lower edge instead of stopping at the map-stage width")
	assert_equal(InteractionPresenter.interaction_region(combat_request, standard_textbox_rect, Rect2(0.0, 28.0, 704.0, 396.0), combat_rect), combat_rect, "the battle command deck uses the full-width lower control region")
	assert_equal(InteractionPresenter.interaction_region(InteractionRequest.acknowledge("edge-to-edge", "Continue"), standard_textbox_rect, Rect2(0.0, 28.0, 704.0, 396.0)), standard_textbox_rect, "ordinary Classic text retains the source-shaped textbox height")
	assert_true(InteractionPresenter.uses_full_stage_region(ClassicUiFixtureGallery.request_for(InteractionRequest.ALLY_SELECTION)), "a genuine post-battle ally choice replaces the complete tactical stage instead of clipping its old heading")
	var ally_opaque_backing := interaction.get_node("StageOpaqueBacking") as ColorRect
	assert_equal(ally_opaque_backing.color.a, 1.0, "full-stage interactions mask every stale tactical or route label before drawing their stone surface")
	var ally_stage_backing := interaction.get_node("StageBacking") as TextureRect
	assert_equal([ally_stage_backing.stretch_mode, ally_stage_backing.texture_repeat], [TextureRect.STRETCH_TILE, CanvasItem.TEXTURE_REPEAT_ENABLED], "full-stage interactions own one seamless opaque surface over stale tactical content")
	assert_false(InteractionPresenter.uses_textbox_region(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP)), "stage interactions retain their independent inset frame")
	assert_equal(interaction.custom_minimum_size, Vector2.ZERO, "textbox interactions may shrink to the bottom-region rectangle instead of retaining a stage-modal minimum")
	assert_false((interaction.get_node("InteractionScroll/InteractionContent/InteractionHeading") as Label).visible, "the unused narrative heading consumes no textbox height")
	application.free()
	var texture_path := "res://src/presentation/assets/ui/classic-charcoal-slate.png"
	assert_true(ResourceLoader.exists(texture_path, "Texture2D"), "the selected low-contrast stone texture imports as a Godot texture")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/ui/spritecook-assets.json"))
	assert_equal(manifest["schema_version"], 4, "the chrome manifest records the opaque-bevel derivation contract")
	assert_equal(manifest["selected_asset"]["asset_id"], "3f355030-0f8c-4d4e-b079-26ba8d3dbc32", "the committed texture retains selected SpriteCook provenance")
	assert_equal(manifest["files"].size(), 4, "the selected surface, seamless tile, and two deterministic frames ship together")
	for entry: Dictionary in manifest["files"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "generated stone surface hash matches its manifest: %s" % entry["path"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["width"]), "generated stone surface width matches its manifest: %s" % entry["path"])
		assert_equal(texture.get_height(), int(entry["height"]), "generated stone surface height matches its manifest: %s" % entry["path"])


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
