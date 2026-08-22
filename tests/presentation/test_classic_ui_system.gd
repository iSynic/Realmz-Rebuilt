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


func _visible_control_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in root.find_children("*", "Control", true, false):
		if child is Label and child.visible:
			texts.append(child.text)
		elif child is Button and child.visible:
			texts.append(child.text)
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
	_test_bank_component(); _test_money_workspace()
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
	var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(1280, 720))
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
	router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); assert_true((router.find_child("PackageInstallRow", true, false) as BoxContainer).vertical and router.find_child("ExperienceRatio", true, false) != null, "compact setup stacks installation controls while preserving a dedicated source-calculated experience fact")
	var setup_view := GameView.new(1, true, null); setup_view.party_setup_available = true; setup_view.party_setup = PartySetupView.new(); setup_view.campaign_summary = CampaignSummaryView.new(); setup_view.party_members = [CharacterView.new(CharacterState.new("setup.inspect", "Ari", 12, 12))]; router.present(setup_view); router.show_campaign_selection(); var inspect := _buttons_in(router.find_child("PartySlots", true, false)).filter(func(button: Button) -> bool: return button.text in ["View", "Inspect"])[0] as Button; inspect.pressed.emit(); assert_true((router.find_child("PartySetupCharacterInspection", true, false) as Control).visible and router.find_child("BackToPartySetup", true, false) != null and router.find_child("CharacterInspectionScroll", true, false) != null and router.find_child("PartySetupCharacterSheet", true, false) != null, "setup inspection owns one opaque clipped full-stage record with one return action")
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
	assert_equal([progress.value, progress.max_value], [2.0, 4.0], "package work exposes bounded detached progress"); assert_true(router.find_child("PackageOperationPhase", true, false) != null and (router.find_child("PackageOperationHost", true, false) as Control).visible and not router.setup_controller.campaign_scroll.is_ancestor_of(progress) and (router.find_child("InstallPackage", true, false) as Button).disabled and (router.find_child("RefreshScenarios", true, false) as Button).disabled, "package work owns one fixed status host and suppresses competing library actions")
	assert_not_null(cancel, "package work exposes cancellation")
	cancel.pressed.emit()
	assert_equal(canceled[0], 1, "cancellation remains a host signal")
	router.set_package_operation(PackageOperationStatusScript.new())
	assert_true(router.find_child("CancelPackageOperation", true, false) == null, "completed package work removes transient controls")
	router.free()
func _test_primary_workspace_lifecycle() -> void:
	var router := ClassicScreenRouter.new(); (Engine.get_main_loop() as SceneTree).root.add_child(router)
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
		assert_equal(router.primary_workspace_visible(), route_id not in [&"exploration", &"combat"], "only spatial play routes suppress their explanatory workspace body"); var route_back := router.find_child("RouteBackAction", true, false) as Button; assert_true(route_back != null and route_back.visible == (route_id not in [&"exploration", &"combat", &"vault"]) and (route_id not in [&"inventory", &"spells"] or router.find_child("WorkspaceFooter", true, false) != null) and (route_id != &"inventory" or route_back.text == "Done"), "route %s keeps one task-appropriate visible Done or Back action (label=%s, footer=%s)" % [route_id, route_back.text, str(router.find_child("WorkspaceFooter", true, false) != null)])
	assert_equal(entered, [&"character", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"exploration", &"combat"], "each primary transition publishes exactly one entered route after replacing the prior workspace"); router.open_screen(&"system"); (router.find_child("RouteBackAction", true, false) as Button).pressed.emit(); assert_equal(router.current_screen(), &"combat", "the persistent route Back action follows the same history path as Escape")
	var setup_view := GameView.new(2, true, null); setup_view.campaign_summary = CampaignSummaryView.new(); setup_view.campaign_summary.campaign_id = "workspace-fixture"; setup_view.campaign_summary.title = "Workspace Scenario"; setup_view.campaign_summary.version = "6.0.0"; setup_view.campaign_summary.author = "Fantasoft"; setup_view.campaign_summary.restriction_description = "Up to six adventurers."; setup_view.campaign_summary.recommended_party_levels = 18; setup_view.campaign_summary.guidance_authored = true
	setup_view.party_setup_available = true
	setup_view.party_members = [CharacterView.new(CharacterState.new("closing.hero", "Closing Hero", 10, 10))]
	router.present(setup_view)
	router.show_campaign_selection()
	assert_equal((router.find_child("PartyCount", true, false) as Label).text, "• 1 / 6", "party setup presents the active assembly count"); assert_true(router.find_child("SelectedScenarioSummary", true, false) != null and _labels_in(router).has("Workspace Scenario") and _labels_in(router).any(func(text: String) -> bool: return text.contains("recommended party total 18")), "the selected scenario exposes its detached identity, restrictions, and level guidance inside the narrow scenario pane")
	router.present(GameView.new(3, false, null))
	router.show_campaign_selection()
	assert_equal((router.find_child("PartyCount", true, false) as Label).text, "• 0 / 6", "ending an adventure clears the setup controller's stale party count")
	router.free()


func _test_startup_shell() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	router.show_splash()
	var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(1280, 720))
	router.set_standalone_character_creation_available(true)
	var splash := router.find_child("SplashScreen", true, false) as Control
	assert_true(splash != null and splash.visible, "Realmz Rebuilt opens on its application splash instead of dropping directly into package selection")
	assert_false(router.setup_controller.campaign_overlay.visible, "the campaign library waits for an explicit splash action")
	var choose_scenario := splash.find_child("ChooseScenario", true, false) as Button
	var character_files := splash.find_child("CharacterFiles", true, false) as Button
	var intro_animation := splash.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation; assert_not_null(choose_scenario, "the splash exposes scenario selection as a primary path"); assert_true(splash.find_child("SplashIdentityPanel", true, false) != null and splash.find_child("SplashCommandPanel", true, false) != null and intro_animation != null and intro_animation.stream != null and intro_animation.autoplay and intro_animation.loop and not intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, -80.0) and splash.find_child("RealmzIntroOrnament", true, false) is NinePatchRect and splash.find_child("SplashTitle", true, false) != null and splash.find_child("SplashSubtitle", true, false) != null and (splash.find_child("SplashComposition", true, false) as BoxContainer).vertical == false, "the canonical splash starts one clickable framed native video loop muted beside one anchored command stack"); intro_animation.toggle_audio(); assert_true(intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, 0.0), "click-toggle audio follows the current master level"); router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); assert_true((splash.find_child("SplashComposition", true, false) as BoxContainer).vertical, "the compact splash stacks identity and commands without changing their ownership"); router.set_layout_profile(profile, Vector2(1280, 720))
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
	var scenario_controls: Array[String] = _visible_control_texts(scenario_picker) if scenario_picker != null else []
	assert_true(router.setup_controller.campaign_list is VBoxContainer and router.setup_controller.campaign_list.get_parent() is ScrollContainer, "installed scenarios use one single-column picker surface")
	assert_false(scenario_controls.any(func(text: String) -> bool: return text.contains("Stale Scenario")), "incompatible installations do not become ordinary scenario rows")
	assert_contains(scenario_picker.tooltip_text, "installation hidden", "the picker preserves incompatible-installation diagnostics in unobtrusive hover text")
	assert_false(scenario_controls.any(func(text: String) -> bool: return text == "Play"), "scenario rows do not expose the obsolete per-row Play action")
	var install_dialog := router.find_child("InstallScenarioDialog", true, false) as FileDialog; assert_true(scenario_controls.any(func(text: String) -> bool: return text == "Install Scenario") and install_dialog != null and install_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE and install_dialog.filters.has("*.realmz2 ; Realmz Rebuilt Scenario"), "the external package action opens a typed Realmz Rebuilt scenario picker")
	assert_false(scenario_controls.any(func(text: String) -> bool: return text == "Open path" or text.to_lower().contains("play")) or router.find_child("PackagePath", true, false) != null, "the integrated workspace exposes neither developer paths nor Play language")
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
	var labels := _labels_in(body)
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Day 2") and text.contains("land:4 12,9")), "valid save previews expose detached time and location facts")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Mira, Borin")), "valid save previews expose detached party identity")
	var load_selected := body.find_child("LoadSelectedSave", true, false) as Button; var current_row := body.find_child("SavePreview_quick_primary", true, false) as Button; var backup_row := body.find_child("SavePreview_quick_backup", true, false) as Button; var corrupt_row := body.find_child("SavePreview_broken_primary", true, false) as Button
	assert_true(load_selected != null and current_row != null and backup_row != null and corrupt_row != null and body.find_child("DisplaySettingsPanel", true, false) != null and body.find_child("AudioSettingsPanel", true, false) != null and body.find_child("AccessibilitySettingsPanel", true, false) != null and body.find_child("ControlsSettingsPanel", true, false) != null and body.find_child("DiagnosticsSettingsPanel", true, false) != null, "system route separates save records and each presentation preference domain into stable workspaces")
	current_row.pressed.emit(); load_selected.pressed.emit(); backup_row.pressed.emit(); load_selected.pressed.emit()
	corrupt_row.pressed.emit()
	assert_true(load_selected.disabled and load_selected.tooltip_text.contains("corrupt"), "a corrupt selected record remains visible with its exact disabled reason")
	assert_equal(actions, [{"action": &"load", "value": "quick"}, {"action": &"load_backup", "value": "quick"}], "current and backup previews emit distinct host operations")
	body.free(); body = VBoxContainer.new(); controller.set_save_and_quit_mode(true); controller.present(body, view, PresentationSettings.new())
	var save_and_quit := body.find_child("SaveAndQuitSelected", true, false) as Button; (body.find_child("SavePreview_quick_primary", true, false) as Button).pressed.emit(); save_and_quit.pressed.emit(); assert_equal(actions[-1], {"action": &"save_and_quit", "value": "quick"}, "Save and Quit uses the selected slot instead of writing before confirmation closes"); body.free()


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
	assert_true(editor != null and body.find_child("MapsNotesTabs", true, false) != null and body.find_child("SavedLocationNotes", true, false) != null and body.find_child("JournalEntryDetail", true, false) != null, "Maps/Notes separates saved places, maps, and authored journal detail while retaining the location editor")
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
	var turn_icon := GradientTexture1D.new(); var component := BattleInteraction.new(); component.theme = load("res://src/presentation/classic_ui_theme.tres"); component.configure({"hero": turn_icon, "monster": turn_icon}); component.build(request)
	var primary := component.find_child("BattlePrimaryCommands", true, false); var secondary := component.find_child("BattleTurnCommands", true, false)
	assert_equal(_buttons_in(primary).map(func(button: Button) -> String: return button.text), ["Weapon: Melee", "Guard", "Fire", "Finish", "Spells", "Scrolls", "Items"], "the compact Action group preserves its fixed source-backed command slots")
	assert_equal(_buttons_in(secondary).map(func(button: Button) -> String: return button.text), ["Auto Turn", "Delay", "Bandage", "Turn Undead", "Undo", "Escape"], "the compact Turn group preserves unavailable commands without reflow")
	var initiative := component.find_child("BattleInitiativeOrder", true, false)
	assert_equal([_direct_buttons_in(initiative).map(func(button: Button) -> String: return button.text), _direct_buttons_in(initiative).all(func(button: Button) -> bool: return button.icon == turn_icon), (component.find_child("ActiveCombatantIcon", true, false) as TextureRect).texture, (component.find_child("InspectedCombatantIcon", true, false) as TextureRect).texture], [["NOW", "NEXT"], true, turn_icon, turn_icon], "the turn summary and compact initiative strip use supplied exact combat icons from the active actor onward")
	var escape := component.find_child("CombatCommandEscape", true, false) as Button
	assert_true(escape.disabled and not escape.tooltip_text.is_empty(), "unavailable retreat carries a typed reason")
	assert_true(_labels_in(component).any(func(text: String) -> bool: return text.contains("Goblin")) and component.get_combined_minimum_size().y <= 190.0, "target facts and both command rows fit the canonical combat region")
	component.free()
func _test_battle_typed_option_contracts() -> void:
	var request := _fixture_request("battle.staged-spell", InteractionRequest.COMBAT, {"actions": ["cast_spell", "use_item", "use_scroll"], "spellCasts": [{"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 1, "cost": 2, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 1, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, 0]], "legalTargetCoordinates": []}, {"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 2, "cost": 4, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 2, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, 0], [0, 1]], "legalTargetCoordinates": []}], "spellCastReason": "", "itemCasts": [], "scrollCasts": [], "itemCastReason": "No legal item.", "scrollCastReason": "No legal scroll."})
	var component := BattleInteraction.new(); component.theme = load("res://src/presentation/classic_ui_theme.tres"); component.build(request)
	var opened := {"actor": "", "options": []}; component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: opened["actor"] = actor_id; opened["options"] = options)
	(component.find_child("CombatCommandSpells", true, false) as Button).pressed.emit()
	var opened_options: Array[InteractionRequestValue.CastOption] = []; opened_options.assign(opened["options"])
	assert_true(opened_options.size() == 2 and component.find_child("CombatSpellPicker", true, false) == null, "combat casting opens the dedicated spellbook contract instead of generic dropdown controls")
	var spell_definition := SpellDefinition.new("classic.spell.1306", 1306, "Brimstones", "Burning stones strike a fixed battlefield area."); spell_definition.in_combat = true; spell_definition.range_min = 1; spell_definition.range_max = 2; spell_definition.damage_min = 2; spell_definition.damage_max = 6; spell_definition.power_damage_min = 1; spell_definition.power_damage_max = 2; spell_definition.duration_min = 1; spell_definition.duration_max = 3; spell_definition.damage_type = 2; var summon_definition := SpellDefinition.new("classic.spell.3502", 3502, "Creature Summon 4", "Summons more powerful creatures."); summon_definition.in_combat = true; var actor_state := CharacterState.new(String(opened["actor"]), "Hero", 10, 10); actor_state.spell_points = 8; actor_state.maximum_spell_points = 12; var actor_view := CharacterView.new(actor_state); actor_view.spells = [SpellView.new(spell_definition), SpellView.new(summon_definition)]
	var spellbook_view := GameView.new(1, true, null); spellbook_view.party_members = [actor_view]; var roster := load("res://src/presentation/screens/classic_party_roster.tscn").instantiate() as ClassicPartyRoster; roster.present(spellbook_view); roster.present_combat_spellbook(String(opened["actor"]), opened_options); var spellbook_labels := _labels_in(roster)
	assert_true(roster.find_child("CombatSpellLevels", true, false) != null and roster.find_child("CombatSpellList", true, false) != null and roster.find_child("CombatSpellPowerChoices", true, false) != null and roster.find_child("CombatSpellDetails", true, false) != null and (roster.find_child("CombatSpellbookActions", true, false) as Control).get_parent().name == "SpellbookFooter" and spellbook_labels.has("Burning stones strike a fixed battlefield area.") and spellbook_labels.any(func(text: String) -> bool: return text.contains("Cost 2 SP") and text.contains("SP 8/12")), "the spellbook reuses Classic level and power art, persistent spell toggles, Realmz-owned descriptions, source-backed facts, and a fixed action footer in the right rail")
	var level_five := roster.find_child("SpellLevel5", true, false) as Button; level_five.pressed.emit(); var summon_row := roster.find_child("CombatSpellclassic_spell_3502", true, false) as Button; summon_row.pressed.emit(); assert_true(summon_row.text.contains("Creature Summon 4") and summon_row.text.contains("Unavailable") and not summon_row.disabled and (roster.find_child("CombatSpellAim", true, false) as Button).disabled and _labels_in(roster).any(func(text: String) -> bool: return text.to_lower().contains("no rules-legal power or tactical target")), "known combat spells remain visible and inspectable when the tactical resolver cannot supply a legal CastOption")
	(roster.find_child("SpellLevel3", true, false) as Button).pressed.emit()
	var selected := {"option": null}; roster.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: selected["option"] = option); (roster.find_child("CombatSpellAim", true, false) as Button).pressed.emit()
	component.cast_spell_option(selected["option"] as InteractionRequestValue.CastOption)
	assert_true(component.find_child("ConfirmBattleTarget", true, false).visible and component.get_combined_minimum_size().y <= 190.0, "spellbook selection enters battlefield targeting while confirmation remains inside the canonical combat region")
	for label: String in ["Items", "Scrolls"]:
		var buttons := _buttons_in(component).filter(func(button: Button) -> bool: return button.text == label)
		assert_true(buttons.size() == 1 and buttons[0].disabled, "%s has one typed control disabled by core availability" % label)
	roster.free(); component.free()
func _test_shop_component() -> void:
	var request := _fixture_request("shop.fixture", InteractionRequest.SHOP, {
		"partyGold": 19,
		"inflationPercent": 125,
		"identifyPrice": 20,
		"characters": [{"id": "character.one", "name": "Hero", "inventory": [
			{"instanceId": "item.unknown", "itemId": "classic.item.40", "name": "Runed wand", "sellPrice": 0, "identified": false, "equipped": false, "charges": 2, "canSell": true, "sellReason": "", "canIdentify": false, "identifyReason": "Identification costs 20 gold.", "iconResourceType": "cicn", "iconId": 35},
			{"instanceId": "item.equipped", "itemId": "classic.item.1", "name": "Sword", "sellPrice": 25, "identified": true, "equipped": true, "charges": -1, "canSell": false, "sellReason": "Unequip this item before selling it.", "canIdentify": false, "identifyReason": "This item is already identified.", "iconResourceType": "cicn", "iconId": 20},
		]}],
		"stock": [{"stockKey": "buyback:classic.item.5", "index": -1, "itemId": "classic.item.5", "name": "Dagger", "buyPrice": 40, "quantity": 1, "canBuy": false, "buyReason": "The party cannot afford this item.", "iconResourceType": "cicn", "iconId": 5}],
	})
	var component := ShopInteraction.new(); component.configure(ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()), false)
	component.build(request)
	assert_true(component.find_child("ShopHeader", true, false) != null and component.find_child("ShopStockColumn", true, false) != null and component.find_child("SelectedInventoryColumn", true, false) != null and component.find_child("ItemInspectorRail", true, false) != null and component.find_child("ShopFooter", true, false) != null, "shop keeps stock, pack, selected record, and transaction actions in stable regions"); assert_true(component.find_child("StockIcon_buyback_classic_item_5", true, false).find_child("ContentImage", true, false) != null and component.find_child("InventoryIcon_item_unknown", true, false).find_child("ContentImage", true, false) != null, "shop stock and carried items resolve their exact typed CICNs through the shared application catalog")
	var buy_button := component.find_child("ShopBuy", true, false) as Button
	assert_true(buy_button.disabled and buy_button.tooltip_text.contains("afford"), "unaffordable stock exposes its core-owned reason")
	var unknown_item := component.find_child("Inventory_item_unknown", true, false) as Button
	assert_not_null(unknown_item, "unidentified inventory uses the player-knowable item name")
	unknown_item.pressed.emit()
	var sell_button := component.find_child("ShopSellSelected", true, false) as Button
	var identify_button := component.find_child("ShopIdentify", true, false) as Button
	assert_true(not sell_button.disabled, "a sellable carried item can be selected from the persistent pack column")
	assert_true(identify_button.disabled and identify_button.tooltip_text.contains("20 gold"), "paid identification exposes the exact affordability blocker")
	var equipped_item := component.find_child("Inventory_item_equipped", true, false) as Button
	assert_not_null(equipped_item, "equipped items remain visible in the pack")
	equipped_item.pressed.emit()
	assert_true(sell_button.disabled and sell_button.tooltip_text.contains("Unequip"), "ordinary sale cannot bypass the equipment workflow")
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
	var buttons := _buttons_in(component)
	var heal_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Heal Small Wounds"))[0]
	var revive_button: Button = buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Revive Dead"))[0]
	var purchase_button: Button = component.find_child("TemplePurchase", true, false) as Button
	assert_false(heal_button.disabled or revive_button.disabled, "temple services remain available for inspection independent of affordability")
	assert_true(purchase_button.disabled and purchase_button.tooltip_text.contains("312"), "the request's selected character identity drives the exact purchase blocker")
	assert_true(_labels_in(component).any(func(text: String) -> bool: return text == "Poor Hero"), "the presenter restores the save-owned selected temple character")
	assert_true(_labels_in(component).any(func(text: String) -> bool: return text.contains("HP -12/10")), "the temple inspector exposes the selected character's source health state")
	revive_button.pressed.emit(); assert_true(purchase_button.disabled and purchase_button.tooltip_text.contains("1875 gold"), "unaffordable temple services retain their exact cost blocker")
	var hero_button: Button = component.find_child("TempleCharacter_character_one", true, false) as Button
	hero_button.pressed.emit(); heal_button.pressed.emit()
	assert_false(purchase_button.disabled, "changing the selected character recalculates affordability from detached values")
	purchase_button.pressed.emit()
	var pool_button: Button = component.find_child("TemplePool", true, false) as Button
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
	router.open_screen(&"inventory"); router.open_screen(&"inventory"); router.open_screen(&"exploration"); router.open_screen(&"spells"); router.open_screen(&"exploration"); router.open_screen(&"inventory", false); router.open_screen(&"exploration", false)
	router.open_screen(&"services"); router.open_screen(&"services"); router.open_screen(&"exploration")
	assert_equal(sounds, [{"soundId": 20001, "waitForCompletion": false, "stopExisting": false}, {"soundId": 20002, "waitForCompletion": false, "stopExisting": false}, {"soundId": 141, "waitForCompletion": false, "stopExisting": false}, {"soundId": 3003, "waitForCompletion": false, "stopExisting": true}, {"soundId": 141, "waitForCompletion": false, "stopExisting": false}], "explicit Items and Spells openings request their Castle cues once, automatic routing is quiet, and ordinary Swap retains its source sequence")
	view.pending_interaction = _fixture_request("shop.audio", InteractionRequest.SHOP)
	router.present(view)
	router.open_screen(&"services")
	assert_equal(sounds.size(), 5, "a Services route opened for a typed location service does not masquerade as ordinary Swap")
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
	assert_equal(UiRouteCatalog.ROUTES.size(), 10, "the canonical route registry contains the ten implemented workspaces")
	var ids: Dictionary = {}
	var shortcuts: Dictionary = {}
	var primary_count: int = 0
	for route: Dictionary in UiRouteCatalog.ROUTES:
		ids[route["id"]] = true
		shortcuts[route["shortcut"]] = true
		primary_count += 1 if bool(route["primary"]) else 0
		assert_false(String(route.get("description", "")).is_empty(), "every route has presentation guidance")
		assert_true(ResourceLoader.exists(String(route.get("scene", "")), "PackedScene"), "every route owns a scene-backed workspace")
	assert_equal(ids.size(), 10, "route identifiers are unique")
	assert_equal(shortcuts.size(), 10, "route shortcuts are unique, including the one shortcut-free menu workspace")
	assert_equal(primary_count, 6, "both supported layout compositions keep six primary workspaces")


func _test_layout_profiles() -> void:
	assert_equal(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.COMPACT, "800x600 uses compact layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1280x720 uses wide layout")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_125), 1.25, "explicit interface density is independent of viewport")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_150), 1.5, "150 percent interface density is supported")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(compact.party_width, 208.0, "compact Classic roster uses the specified width")
	assert_equal(compact.bottom_height, 156.0, "compact Classic textbox uses the specified height"); assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).party_width, 352.0, "canonical widescreen reserves enough width for complete party records"); var full_hd := UiLayoutProfile.for_viewport(Vector2(1920, 1080), PresentationSettings.UI_SCALE_AUTO); assert_equal([full_hd.id, full_hd.ui_scale, full_hd.application_rect], [UiLayoutProfile.WIDE, 1.5, Rect2(0, 0, 1920, 1080)], "Fit uses the complete 16:9 Full HD window at one-and-a-half layout density"); var ultrawide := UiLayoutProfile.for_viewport(Vector2(3440, 1440), PresentationSettings.UI_SCALE_AUTO)
	assert_equal([ultrawide.ui_scale, ultrawide.bitmap_scale, ultrawide.application_rect], [2.0, 2, Rect2(440, 0, 2560, 1440)], "Fit centers one bounded 16:9 application canvas on ultrawide while keeping imported art at exact 2x pixels"); var four_k := UiLayoutProfile.for_viewport(Vector2(3840, 2160), PresentationSettings.UI_SCALE_AUTO); assert_equal([four_k.ui_scale, four_k.bitmap_scale, four_k.application_rect], [3.0, 2, Rect2(0, 0, 3840, 2160)], "4K scales layout geometry to 3x without stretching legacy bitmap art beyond 2x"); assert_equal(UiLayoutProfile.application_rect_for(Vector2(800, 600)), Rect2(0, 0, 800, 600), "the optional 800x600 Classic composition retains its complete 4:3 canvas"); var offset_spell_rect := ClassicScreenRouter.spell_workspace_rect_for(ultrawide, ultrawide.application_rect.size, ultrawide.application_rect.position); assert_equal(offset_spell_rect.position.x, 2296.0, "roster-replacement workspaces inherit the bounded canvas origin")
func _test_settings_schema_and_migration() -> void:
	var settings := PresentationSettings.new(); settings.ui_scale_mode = PresentationSettings.UI_SCALE_125; settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.text_scale = 1.5; settings.auto_switch_to_melee = false; settings.exploration_speed_percent = 250
	settings.show_exploration_minimap = true; settings.autojournal_enabled = false; settings.typography_mode = PresentationSettings.TYPOGRAPHY_READABLE
	var restored := PresentationSettings.from_data(settings.to_data()); assert_not_null(restored, "schema-eight presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately"); assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent"); assert_false(restored.auto_switch_to_melee, "Auto Weapon Switch persists as an application preference rather than battle state")
	assert_equal(restored.exploration_speed_percent, 250, "exploration speed persists independently of simulation state")
	assert_equal([restored.show_exploration_minimap, restored.autojournal_enabled, restored.typography_mode], [true, false, PresentationSettings.TYPOGRAPHY_READABLE], "travel preview, Auto Note, and typography persist as presentation preferences")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true}); assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density"); assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")
	assert_true(version_two.auto_switch_to_melee, "legacy settings inherit Castle's bundled default-on Auto Weapon Switch preference")
	var version_three := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 3, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_150, "windowMode": PresentationSettings.WINDOWED}); assert_not_null(version_three, "schema-three settings migrate")
	assert_equal([version_three.ui_scale_mode, version_three.auto_switch_to_melee], [PresentationSettings.UI_SCALE_150, true], "schema-three settings preserve prior display fields and inherit Castle's default-on preference")
	var version_four := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 4, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": false}); assert_not_null(version_four, "schema-four settings migrate")
	assert_equal(version_four.exploration_speed_percent, 100, "older settings inherit the stable exploration cadence")
	var version_five := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 5, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200}); assert_equal([version_five.show_exploration_minimap, version_five.autojournal_enabled], [false, true], "schema-five settings migrate to a hidden modern travel aid and the requested Auto Note default")
	var version_six := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 6, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200, "showExplorationMinimap": false, "autojournalEnabled": true}); assert_equal(version_six.typography_mode, PresentationSettings.TYPOGRAPHY_CLASSIC, "existing settings migrate to the Classic typography default")
	var version_seven := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 7, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200, "showExplorationMinimap": false, "autojournalEnabled": true, "typographyMode": PresentationSettings.TYPOGRAPHY_CLASSIC}); assert_equal([version_seven.sound_volume, version_seven.music_volume, version_seven.music_enabled], [1.0, 0.8, true], "schema-seven settings migrate to independent effects and music defaults")
	var malformed_current := settings.to_data()
	malformed_current.erase("autojournalEnabled")
	assert_equal(PresentationSettings.from_data(malformed_current), null, "current settings reject an incomplete preference record")
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
	held.advance(0.299); assert_equal(pulses.size(), 1, "an ordinary click cannot cross the initial held-repeat threshold")
	held.advance(0.002); assert_equal(pulses.size(), 2, "a deliberate hold begins repeating after 300 milliseconds")
	held.advance(0.049); held.advance(0.002); assert_equal(pulses.size(), 3, "subsequent held steps use the selected 50 millisecond cadence")
	held.advance(1.0); assert_equal(pulses.size(), 4, "a slow frame emits one step rather than a queued burst")
	assert_false(held.request_in_progress(), "a synchronous movement callback settles before the next interval begins")
	held.set_speed_percent(25)
	assert_equal(held.interval_seconds(), 0.8, "the slowest movement setting uses the documented 800 millisecond interval")
	held.set_speed_percent(100)
	assert_equal(held.interval_seconds(), 0.2, "the default movement setting sustains five scheduled steps per second")
	held.stop(&"keyboard")
	held.advance(1.0)
	assert_equal(pulses.size(), 4, "release stops further held movement")
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


func _test_fixture_gallery_coverage() -> void:
	for interaction: StringName in ClassicUiFixtureGallery.INTERACTIONS:
		var request := ClassicUiFixtureGallery.request_for(interaction)
		assert_not_null(request, "gallery interaction %s decodes through its exact typed contract" % interaction)
		if request != null:
			assert_true(request.is_supported_kind(), "gallery interaction %s is a supported typed request" % interaction)
	var age_component := AgeUpdateInteraction.new()
	age_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.AGE_UPDATE))
	assert_true(age_component.find_child("AgeIdentityPanel", true, false) != null and age_component.find_child("AgeChangeGrid", true, false) != null, "the Classic age update renders identity, age band, and changed statistics as one contained workspace")
	assert_true(age_component.get_children().any(func(child: Node) -> bool: return child is Button and child.text == "Continue"), "the blocking age update exposes one keyboard-focusable continuation")
	age_component.free()
	var item_media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); var recovery_component := TreasureDistributionInteraction.new(); recovery_component.configure(item_media, null, false)
	recovery_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"))
	assert_true(recovery_component.find_child("TreasureItemColumn", true, false) != null and recovery_component.find_child("TreasureRecipientColumn", true, false) != null and recovery_component.find_child("TreasureCommandColumn", true, false) == null and recovery_component.find_child("TreasureLootField", true, false) != null and recovery_component.find_child("TreasureFooter", true, false) != null, "the legacy save-v4 fumble request remains renderable as a focused exact-item recovery adapter"); assert_true(recovery_component.find_child("TreasureItemIcon", true, false) != null, "legacy recovery renders the exact item CICN above the typed recipient controls")
	assert_true(_labels_in(recovery_component).any(func(text: String) -> bool: return text.contains("7 charges")), "battle recovery exposes the exact preserved charge count")
	assert_true(_buttons_in(recovery_component).any(func(button: Button) -> bool: return button.text.begins_with("Recover to Hero") and not button.disabled), "nominal battle recovery exposes its rules-authorized recipient as an explicit recovery control")
	recovery_component.free()
	var ordinary_component := TreasureDistributionInteraction.new(); ordinary_component.configure(item_media, null, false)
	ordinary_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized")); var loot_grid := ordinary_component.find_child("TreasureItemGrid", true, false) as GridContainer; var second_item := ordinary_component.find_child("TreasureItem_reward_item_2", true, false) as Button
	second_item.mouse_entered.emit(); assert_true(loot_grid.columns == 16 and loot_grid.get_child_count() == 24 and (ordinary_component.find_child("TreasureHoverCircle_reward_item_2", true, false) as TextureRect).visible and (ordinary_component.find_child("TreasureSelectedItemName", true, false) as Label).text == "Fixture Wand 2" and ordinary_component.find_child("TreasureItemIdentity", true, false) != null and ordinary_component.find_child("TreasureItemProperties", true, false) != null and ordinary_component.find_child("TreasureCommandPanel", true, false) != null and (ordinary_component.find_child("TreasurePooledWealth", true, false) as Label).text.contains("Gold 125"), "ordinary booty uses the wide Classic field, presents every item, and retains hover, selected-record, and denomination details")
	assert_true(_buttons_in(ordinary_component).any(func(button: Button) -> bool: return button.name == "TreasureRecipient_hero-0" and button.button_pressed and button.text.contains("Items") and button.text.contains("Move") and button.text.contains("Load")), "ordinary booty keeps one rules-owned recipient selected with its Classic carrying facts")
	assert_true(_buttons_in(ordinary_component).any(func(button: Button) -> bool: return button.name == "TreasureDone"), "ordinary booty has one typed completion path")
	ordinary_component.free()
	var capacity_component := TreasureDistributionInteraction.new(); capacity_component.configure(item_media, null, false)
	capacity_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unavailable"))
	assert_true(_buttons_in(capacity_component).any(func(button: Button) -> bool: return button.name == "TreasureRecipient_hero-0" and button.disabled and button.tooltip_text.contains("full")), "capacity-blocked booty retains the core-provided disabled reason")
	capacity_component.free(); var unidentified_component := TreasureDistributionInteraction.new(); unidentified_component.configure(item_media, null, false); unidentified_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified")); var unidentified_name := unidentified_component.find_child("TreasureSelectedItemName", true, false) as Label; assert_true(unidentified_name.theme_type_variation == &"ClassicUnidentifiedItem" and not unidentified_name.has_theme_color_override("font_color") and (unidentified_component.find_child("TreasureDetectMagicCaster", true, false) as OptionButton).theme_type_variation == &"ClassicTheldrowOptionButton" and (unidentified_component.find_child("TreasureIdentifyCaster", true, false) as OptionButton).theme_type_variation == &"ClassicTheldrowOptionButton", "unidentified Treasure naming and lore-caster selectors use their Castle-backed typography roles without masking the hollow face"); unidentified_component.free()
	var level_component := LevelUpInteraction.new(); var level_request := ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP); level_component.build(level_request)
	assert_true(_labels_in(level_component).any(func(text: String) -> bool: return text.contains("level 5")), "the level result presents its committed character level")
	assert_true(_buttons_in(level_component).any(func(button: Button) -> bool: return button.text == "Continue"), "the level result exposes one typed acknowledgement")
	assert_false(InteractionPresenter.uses_application_workspace(level_request), "a committed level result uses a locked floating modal rather than replacing the application workspace"); assert_equal(InteractionPresenter.preferred_modal_size(level_request, Vector2(984, 494)), Vector2(760, 430), "the level result keeps a compact Castle-shaped modal footprint")
	level_component.free()
	var spell_request := ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"); var spell_component := LevelUpInteraction.new(); spell_component.build(spell_request)
	var level_two := spell_component.find_child("LevelSpellLevel2", true, false) as Button; assert_true(spell_component.find_child("LevelSpellLevelRail", true, false) != null and level_two.text == "Level 2" and _buttons_in(spell_component.find_child("LevelSpellList", true, false)).filter(func(button: Button) -> bool: return button.has_meta(&"spell_id")).size() == 1 and InteractionPresenter.uses_application_modal_region(spell_request) and InteractionPresenter.preferred_modal_size(spell_request, Vector2(1280, 688)) == Vector2(1080, 668), "Learn Spells uses the full application-height locked modal and one shared gradient level rail rather than flattening every candidate"); level_two.pressed.emit(); assert_true(_buttons_in(spell_component.find_child("LevelSpellList", true, false)).any(func(button: Button) -> bool: return button.text.begins_with("Spell 2") and button.theme_type_variation == &"ClassicTheldrowButton" and button.toggle_mode), "changing Learn Spell levels preserves the shared pressed spell controls")
	assert_true(_buttons_in(spell_component).any(func(button: Button) -> bool: return button.text == "Confirm spell selection"), "the spell stage exposes one typed confirmation")
	spell_component.free()
	var roster := load("res://src/presentation/screens/classic_party_roster.tscn").instantiate() as ClassicPartyRoster
	(Engine.get_main_loop() as SceneTree).root.add_child(roster)
	var selection_view := GameView.new(1, true, null)
	selection_view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)), CharacterView.new(CharacterState.new("mage", "Mage", 6, 9)), CharacterView.new(CharacterState.new("dead", "Dead", 0, 10))]
	var request := _fixture_request("fixture.party-pick", InteractionRequest.CHARACTER_SELECTION, {"count": 2, "eligible": [{"id": "hero", "name": "Hero", "currentHealth": 8, "maximumHealth": 10}, {"id": "mage", "name": "Mage", "currentHealth": 6, "maximumHealth": 9}], "mode": "field-spell", "spellId": "classic.spell.1107", "spellContext": {"actorId": "hero", "actorName": "Hero", "spellId": "classic.spell.1107", "spellName": "Magic Darts", "description": "A compact bolt of magical force.", "iconResourceType": "cicn", "iconId": 0, "power": 2, "spellPointCost": 8, "targetType": 0, "targetSize": 0, "targetCount": 2, "sourceKind": "field-spell"}})
	var selection_component := SelectionInteraction.new(); selection_component.build(request)
	assert_true(_buttons_in(selection_component).is_empty() and selection_component.find_child("SpellTargetContext", true, false) != null, "the mandatory picker keeps the selected spell record visible without exposing cancel or premature submit")
	selection_component.free()
	var ally_request := ClassicUiFixtureGallery.request_for(InteractionRequest.ALLY_SELECTION); var ally_component := SelectionInteraction.new(); ally_component.build(ally_request); assert_true(ally_component.find_child("AllyCandidates", true, false) != null and ally_component.find_child("AllySelectionContinue", true, false) != null, "surviving allies use one dominant candidate workspace with a fixed continuation"); assert_false(InteractionPresenter.uses_full_stage_region(ally_request), "surviving-allies selection is a locked Castle modal rather than a stale tactical-stage replacement"); ally_component.free(); var completion_treasure := InteractionRequest.from_payload("fixture.treasure.complete", InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "summary": "One item remains unclaimed."}); var completion_component := TreasureDistributionInteraction.new(); completion_component.configure(item_media, null, false); completion_component.build(completion_treasure); assert_true(completion_component.find_child("TreasureCompletionConfirmation", true, false) != null and _buttons_in(completion_component).any(func(button: Button) -> bool: return button.text == "Return to treasure"), "leave-behind confirmation retains an explicit path back to the Treasure workspace while the gallery owns the real Done-to-confirmation retained-surface rerender"); completion_component.free()
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
	assert_equal([request.kind, request.body.to_data()["inCombat"], request.body.to_data()["options"].size(), InteractionPresenter.uses_full_stage_region(request)], [InteractionRequest.SESSION_LIFECYCLE, false, 3, false], "field End Adventure exposes explicit save, discard, and cancel operations in a compact modal")
	assert_not_null(InteractionRequest.from_data(request.to_data()), "the typed lifecycle request retains the established interaction wire shape")
	var component := LifecycleInteractionScript.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons := _buttons_in(component)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and end adventure", "End adventure without saving", "Cancel"], "the dedicated presenter does not reinterpret lifecycle choices as scenario options")
	assert_true(component.handle_back(), "Escape invokes the declared lifecycle Cancel action")
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
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and Quit", "Quit", "Cancel"], "Quit keeps one compact host question with three content-sized actions"); assert_true(quit_component.find_child("LifecycleActions", true, false) is HBoxContainer and quit_component.find_child("LifecycleConsequence", true, false) == null, "Quit omits duplicate consequence prose and keeps its actions in one centered row")
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
	var idle_quit := ApplicationLifecycleScript.quit_application_request(false, false); assert_equal(idle_quit.body.to_data()["options"].size(), 2, "Quit without an active session offers only quit and cancel"); assert_equal([RealmzApplication.interaction_response_owner(true, true), RealmzApplication.interaction_response_owner(false, true), RealmzApplication.interaction_response_owner(false, false)], [&"host", &"standalone-creator", &"session"], "a host Quit confirmation owns its response before standalone character creation or campaign-session interactions")
	quit_component.free()

func _test_classic_choice_context() -> void:
	var journal_request := InteractionRequest.from_payload("journal-text", InteractionRequest.ACKNOWLEDGE, {"prompt": "A source message", "journalEligible": true, "journalRecorded": false})
	var journal_component := TextChoiceInteraction.new(); var journal_payloads: Array[Dictionary] = []
	journal_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: journal_payloads.append(body.to_data()))
	journal_component.configure(true); journal_component.build(journal_request)
	var journal_buttons: Array[Node] = journal_component.find_children("*", "Button", true, false)
	assert_equal(journal_buttons.map(func(button: Button) -> String: return button.text), ["Continue"], "Auto Note keeps one compact acknowledgement instead of a separate invented Take note command")
	(journal_buttons[0] as Button).pressed.emit()
	assert_equal(journal_payloads, [{"takeNote": true}], "Auto Note preserves the typed journal flag on ordinary acknowledgement")
	journal_component.free()
	var yes_no := TextChoiceInteraction.new()
	yes_no.build(InteractionRequest.yes_no("layout-choice", "Continue?", "Yes", "No"))
	var yes_no_grid := yes_no.find_child("ChoiceGrid", true, false) as GridContainer
	assert_true(yes_no.find_child("ChoicePane", true, false) != null and yes_no_grid != null and yes_no_grid.columns == 2 and _buttons_in(yes_no).all(func(button: Button) -> bool: return button.theme_type_variation == &"ClassicChoiceButton"), "binary Classic choices share one backed compact semantic response row")
	yes_no.free()
	var encounter := EncounterInteraction.new(); var encounter_responses: Array[StringName] = []; var side_workspaces: Array[Control] = []; var side_closes: Array[bool] = []; encounter.response_body_submitted.connect(func(body: InteractionResponse.ComplexEncounterBody) -> void: encounter_responses.append(body.action)); encounter.side_workspace_requested.connect(func(workspace: Control) -> void: side_workspaces.append(workspace)); encounter.side_workspace_closed.connect(func() -> void: side_closes.append(true)); var encounter_request := ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION); encounter.build(encounter_request)
	var command_strip := encounter.find_child("EncounterCommandStrip", true, false) as GridContainer; assert_true(encounter.find_child("EncounterCommandDeck", true, false) != null and encounter.find_child("EncounterContextDeck", true, false) != null and command_strip != null and command_strip.get_child_count() == 6, "complex encounters preserve one backed Action, Items, Skills, Speak, Spells, and Stop command strip above one contextual task pane")
	assert_not_null(encounter.find_child("EncounterChoiceGrid", true, false), "the selected encounter command owns a compact contextual response pane")
	var item_command := encounter.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton; item_command.command_requested.emit(&"item"); var item_is_internal := encounter.find_child("EncounterCatalogList", true, false) != null and encounter.find_child("EncounterCatalogRecord", true, false) != null and encounter.find_child("EncounterCatalogActions", true, false) != null and encounter.handle_back(); var spell_command := encounter.find_child("EncounterCommandSpell", true, false) as ClassicBitmapButton; spell_command.command_requested.emit(&"spell"); var level_three := side_workspaces[0].find_child("EncounterSpellLevel3", true, false) as Button; level_three.pressed.emit(); var spell_is_external := side_workspaces.size() == 1 and encounter.find_child("EncounterCatalogList", true, false) == null and side_workspaces[0].find_child("EncounterCatalogList", true, false) != null and level_three.button_pressed and _buttons_in(side_workspaces[0]).any(func(button: Button) -> bool: return button.text == "Brimstones") and not _buttons_in(side_workspaces[0]).any(func(button: Button) -> bool: return button.text == "Magic Darts") and encounter.handle_back() and side_closes.size() == 1; assert_true(item_is_internal and spell_is_external, "Encounter keeps item selection in its modal, replaces the Party roster with a level-filtered spellbook, and unwinds either local task before leaving"); side_workspaces[0].free()
	var word_command := encounter.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton; word_command.command_requested.emit(&"word"); var word_entry := encounter.find_child("EncounterWord", true, false) as LineEdit
	assert_true(not InteractionPresenter.uses_textbox_region(encounter_request) and word_entry != null and word_entry.max_length == 39 and word_entry.theme_type_variation == &"ClassicTheldrowLineEdit" and encounter.find_child("EncounterWordActions", true, false) != null and _buttons_in(encounter).any(func(button: Button) -> bool: return button.text == "Speak") and encounter.handle_back() and encounter_responses == [&"back"], "Encounter is a floating modal; Speak uses Theldrow and Escape invokes authored Stop after local task unwind"); encounter.free()
	var thief := ThiefEncounterInteraction.new(); thief.build(ClassicUiFixtureGallery.request_for(InteractionRequest.THIEF_ENCOUNTER)); assert_true(thief.find_child("ThiefCharacterPane", true, false) != null and thief.find_child("ThiefActionPane", true, false) != null and thief.find_child("ThiefActionGrid", true, false) != null, "thief selection keeps exact portraits and source-owned skill values in separate character and action panes"); thief.free()


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _test_exploration_map_camera_preserves_viewport_geometry() -> void:
	var viewport_size := Vector2(1280.0, 720.0)
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
	assert_true(party_rects[0].position.x != party_rects[2].position.x and party_rects[0].size == party_rects[2].size and [ClassicMapPresenter.facing_label(Vector2i.UP), ClassicMapPresenter.facing_label(Vector2i.DOWN + Vector2i.LEFT)].all(func(label: String) -> bool: return label in ["N", "SW"]) and ClassicUiAssetCatalog.texture(&"map.party.camp") != null, "map presentation preserves viewport geometry, exact camp-marker availability, and typed cardinal/intercardinal facing labels")
	assert_true(party_rects[3].position.y != party_rects[4].position.y and party_rects[3].size == party_rects[4].size, "north/south movement translates the party cell inside the viewport without changing cell geometry")
	application.free()


func _test_battlefield_presenter() -> void:
	var presenter := ClassicBattlefieldPresenter.new(); var control_size := Vector2(912.0, 486.0); var visible_cells := ClassicBattlefieldPresenter.viewport_cells_for(control_size)
	assert_equal(visible_cells, Vector2i(25, 14), "canonical battlefield uses a native-pixel widescreen camera window")
	var tracked_camera := Vector2i(30, 34); var draw_origin := ClassicBattlefieldPresenter.battlefield_draw_origin(control_size, visible_cells); var rendered_coordinate := Vector2i(40, 39); var rendered_point := ClassicBattlefieldPresenter.cell_rect(rendered_coordinate, tracked_camera, draw_origin).get_center()
	assert_true(ClassicBattlefieldPresenter.coordinate_for_point(rendered_point, tracked_camera, visible_cells, control_size) == rendered_coordinate and ClassicBattlefieldPresenter.click_direction_for_point(ClassicBattlefieldPresenter.cell_rect(rendered_coordinate, tracked_camera, draw_origin), rendered_point + Vector2(90.0, -65.0)) == Vector2i(1, -1) and ClassicBattlefieldPresenter.tracked_camera_top_left(tracked_camera, Vector2i(tracked_camera.x + visible_cells.x - 1, 39), visible_cells) == ClassicBattlefieldPresenter.camera_top_left(Vector2i(tracked_camera.x + visible_cells.x - 1, 39), visible_cells), "battlefield input uses the rendered camera and eight centered sectors while edge focus recenters the view")
	assert_equal(ClassicBattlefieldPresenter.footprint_rect([], Vector2i.ZERO, Vector2.ZERO), Rect2(), "terminal playback tolerates a combatant whose committed battlefield footprint has already been removed")
	var view := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	presenter.present(view)
	presenter.set_movement_costs_visible(true)
	assert_true(presenter.movement_costs_visible(), "movement costs are an explicit presentation aid"); presenter.free()
func _test_combat_targeting_state() -> void:
	var body := InteractionResponse.CombatBody.new(&"cast_spell", "hero")
	body.spell_id = "spell.darts"
	var request := CombatTargetingRequest.new(&"sequence", body); request.candidate_ids.assign(["monster.one", "ally.one"]); request.maximum_targets = 1
	var state := CombatTargetingState.new(request)
	assert_equal([state.select_combatant("ally.one"), state.select_combatant("monster.one"), state.committed_body().target_ids], [true, false, ["ally.one"]], "typed sequence targeting enforces its maximum and preserves selected identity")
	var area_request := CombatTargetingRequest.new(&"area", body); area_request.validation_deferred = true; area_request.default_target_coordinate = Vector2i(45, 45)
	var area_state := CombatTargetingState.new(area_request); assert_equal([area_state.hovered_coordinate, area_state.selected_coordinate, area_state.can_confirm()], [Vector2i(45, 45), Vector2i(-1, -1), false], "an area spell previews its default center without committing it before the player clicks")
	assert_true(area_state.select_coordinate(Vector2i(44, 45)) and area_state.can_confirm(), "staged area targeting accepts a battlefield center without precomputing every legal center")
	assert_equal(area_state.committed_body().target_coordinate, Vector2i(44, 45), "deferred targeting preserves the selected center for authoritative submit-time validation")
func _test_combat_playback_controller() -> void:
	var previous := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	var final := _combat_playback_view(12, Vector2i(46, 45), Vector2i(47, 45), &"active")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_auto_started", {"actorId": "hero"}), DomainEvent.new(&"combatant_moved", {"actorId": "hero", "from": [45, 45], "to": [46, 45]}), DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 8, "classicResultEffectResourceId": 160}), DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "resisted": true, "classicResolutionEffectResourceIds": [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039]}), DomainEvent.new(&"combat_auto_completed", {"actorId": "hero"})]
	var controller := CombatPlaybackController.new()
	var frames: Array[CombatPlaybackFrame] = []
	controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: frames.append(frame))
	assert_true(controller.begin(previous, events, final, false), "combat events create one presentation playback transaction")
	while controller.is_active(): controller.advance(1.0, false)
	var kinds: Array[StringName] = []
	for frame: CombatPlaybackFrame in frames:
		kinds.append(frame.kind)
	assert_true(kinds.has(&"move_start") and kinds.has(&"melee_attack") and frames[0].duration_seconds < 0.08 and frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"move_start" and frame.automatic and InteractionPresenter.playback_status_text(frame).begins_with("Auto Turn") and InteractionPresenter.playback_status_text(frame).contains("Esc cancels Party Auto")), "automatic movement and physical results retain distinct accelerated frames and expose the full-party safety hatch")
	assert_equal(kinds.count(&"spell_effect"), 8, "source-backed spell resolution retains its eight-frame family")
	assert_true(frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result" and frame.display_text == "8"), "damage is shown once over the target")
	assert_equal(controller.base_view, previous, "playback retains the previous battlefield until visuals settle")
	var reduced := CombatPlaybackController.new()
	assert_true(reduced.begin(previous, events, final, true), "reduced motion keeps the same presentation boundary")
	while reduced.is_active(): reduced.advance(1.0, false)
	assert_false(reduced.is_active(), "reduced motion settles without a simulation mutation")
	var toggle_events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 139, "source": "classic-combat-auto-toggle"}), DomainEvent.new(&"combat_auto_changed", {"characterId": "hero", "enabled": false})]
	assert_false(CombatPlaybackController.new().begin(previous, toggle_events, final, false), "an Auto toggle sound does not open another playback mask")
func _combat_playback_view(monster_health: int, hero_position: Vector2i, monster_position: Vector2i, outcome: StringName) -> GameView:
	var tiles: Array[int] = []; tiles.resize(BattlefieldState.CELL_COUNT); tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	assert_true(battlefield.place_character("hero", hero_position), "playback fixture places the party actor")
	var monster := MonsterState.new("monster", "classic.monster.1", "Goblin", monster_health, 20); monster.icon_id = 384
	assert_true(battlefield.place_monster(monster.id, monster_position, 0), "playback fixture places the target")
	var combat := CombatState.new("classic.battle.playback", [monster], 0, battlefield); combat.set_turn_order(["hero", "monster"]); combat.outcome = outcome
	var character := CharacterState.new("hero", "Hero", 10, 10)
	var view := GameView.new(1, true, null); view.party_members = [CharacterView.new(character)]; view.combat_view = CombatView.new(combat, [character])
	return view


func _test_character_creator_workflow() -> void:
	var router := ClassicScreenRouter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var setup := router.setup_controller
	var creator_intents: Array[PlayerIntent] = []
	setup.intent_submitted.connect(func(intent: PlayerIntent) -> void: creator_intents.append(intent))
	var view := GameView.new(1, true, null); view.campaign_id = "creator.fixture"; view.party_setup_available = true
	view.party_setup = PartySetupView.new()
	view.party_setup.available_monster_sets = [0, -1, 1]
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.maximum_party_size = 6
	view.campaign_summary.maximum_level = 7
	view.race_options = [DefinitionOptionView.new("race.human", "Human", "Adaptable.", ["caste.sorcerer"], ["Movement 10", "Attacks 1 • Maximum 1"]), DefinitionOptionView.new("race.2", "Race 2")]
	view.caste_options = [DefinitionOptionView.new("caste.sorcerer", "Sorcerer", "", ["race.human"], ["Stamina d6 initially • d4 per level"]), DefinitionOptionView.new("caste.2", "Caste 2")]
	view.portrait_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.257", "Human portrait", CharacterAppearanceDefinition.PORTRAIT, 257, ["race.human"])), CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("portrait.263", "Alternate portrait", CharacterAppearanceDefinition.PORTRAIT, 263))]; view.combat_icon_options = [CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("icon.9000", "Human tactical icon", CharacterAppearanceDefinition.COMBAT_ICON, 9000, ["race.human"])), CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new("icon.9006", "Alternate tactical icon", CharacterAppearanceDefinition.COMBAT_ICON, 9006))]
	router.present(view)
	assert_true(setup.party_list.get_child_count() == 6 and setup.monster_set_option.theme_type_variation == &"ClassicTheldrowOptionButton" and setup.difficulty_option.theme_type_variation == &"ClassicTheldrowOptionButton", "party setup retains six positions and presents both Classic selectors in Theldrow")
	var prior_character_list: VBoxContainer = setup.stored_character_list; setup.create_character_button.pressed.emit()
	assert_equal(setup.setup_mode, &"creator", "creator opens from party assembly"); assert_true(not setup.party_pane.visible and setup.creator.size_flags_vertical == Control.SIZE_EXPAND_FILL and setup.creator_page.size_flags_vertical == Control.SIZE_EXPAND_FILL and setup.creator_page.find_child("IdentityPreview", true, false) != null and setup.creator_page.find_child("IdentityFields", true, false) != null and setup.creator_page.find_child("IdentityCampaignContext", true, false) != null and setup.name_edit.theme_type_variation == &"ClassicTheldrowLineEdit" and setup.gender_option.theme_type_variation == &"ClassicTheldrowOptionButton" and setup.starting_level_option.theme_type_variation == &"ClassicTheldrowOptionButton" and setup.creator_cancel_button.theme_type_variation == &"ClassicTheldrowButton" and setup.creator_back_button.theme_type_variation == &"ClassicTheldrowButton" and setup.creator_next_button.theme_type_variation == &"ClassicTheldrowButton", "character creation owns the full setup stage and uses Theldrow for its identity controls and actions")
	prior_character_list.free(); setup.name_edit.text = "Ari"; setup.creator_next_button.pressed.emit(); var race_button := setup.race_list.option_button("race.human"); var caste_button := setup.caste_list.option_button("caste.sorcerer"); var race_detail_panel := setup.creator_page.find_child("RaceDetailPanel", true, false) as Control; var caste_detail_panel := setup.creator_page.find_child("CasteDetailPanel", true, false) as Control; var caste_description := setup.creator_page.find_child("CasteDescription", true, false) as Label; assert_true(setup.creator_page.find_child("RaceSelectorPanel", true, false) != null and setup.creator_page.find_child("CasteSelectorPanel", true, false) != null and setup.race_list.item_count == 1 and setup.caste_list.item_count == 1 and race_button != null and race_button.toggle_mode and race_button.button_pressed and caste_button != null and caste_button.toggle_mode and caste_button.button_pressed and race_detail_panel != null and race_detail_panel.size_flags_stretch_ratio == 2.0 and caste_detail_panel != null and caste_detail_panel.size_flags_stretch_ratio == 2.0 and (setup.creator_page.find_child("RaceDetailName", true, false) as Label).text == "Human" and (setup.creator_page.find_child("RaceDescription", true, false) as Label).text == "Adaptable." and (setup.creator_page.find_child("RaceFacts", true, false) as Label).text.contains("Movement 10") and (setup.creator_page.find_child("RaceRelations", true, false) as Label).text.contains("Sorcerer") and caste_description.text.is_empty() and not caste_description.visible and (setup.creator_page.find_child("CasteFacts", true, false) as Label).text.contains("Stamina d6"), "Race and Caste pair narrow pressed selectors with authored descriptions only when present and source-backed rule facts while literal fallback records stay out of ordinary creation")
	setup.creator_step = 2; setup.render_creator_step(); var portrait_race_label := setup.creator_page.find_child("PortraitRaceLabel0", true, false) as Label; var portrait_other_label := setup.creator_page.find_child("PortraitRaceLabel1", true, false) as Label; assert_true(setup.creator_page.find_child("AppearancePreview", true, false) != null and setup.creator_page.find_child("PortraitThumbnailStrip", true, false) != null and setup.creator_page.find_child("CombatIconThumbnailStrip", true, false) != null and setup.creator_page.find_child("PortraitChoice_257", true, false) != null and setup.creator_page.find_child("CombatIconChoice_9000", true, false) != null and portrait_race_label != null and portrait_race_label.text == "Human" and portrait_other_label != null and portrait_other_label.text == "Classic catalog", "Appearance pairs large exact-media previews with deterministic explicitly labelled race rows")
	assert_true(setup.creator_cancel_button != null and not setup.creator_cancel_button.disabled, "creator can be canceled before draft mutation")
	setup.creator_cancel_button.pressed.emit(); assert_equal(setup.setup_mode, &"assembly", "creator cancellation rebuilds assembly after its prior dynamic controls are freed"); var spell_state := CharacterState.new("creator.spells", "Ari", 12, 12); spell_state.spellcaster_type = 1; view.character_draft = CharacterView.new(spell_state); view.character_draft_spell_points_total = 3; view.character_draft_spell_points_remaining = 2
	view.character_draft_spell_options = [CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1101", 1101, "Discover Magic", "Reveals magic."), 1, true), CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1102", 1102, "Flame Hands", "Calls flame."), 2, false)]; setup.setup_mode = &"creator"; setup.creator_step = 4; setup.render_creator_step()
	var spell_buttons := _buttons_in(setup.creator_page); var selected_spells := spell_buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Discover Magic")); var available_spells := spell_buttons.filter(func(button: Button) -> bool: return button.text.begins_with("Flame Hands")); var selected_spell := selected_spells[0] as Button if not selected_spells.is_empty() else null; var available_spell := available_spells[0] as Button if not available_spells.is_empty() else null; var spell_description := setup.creator_page.find_child("StartingSpellDescription", true, false) as Label; var spell_animation := setup.creator_page.find_child("StartingSpellAnimation", true, false)
	assert_true(setup.creator_page.find_child("StartingSpellLevelRail", true, false) != null and setup.creator_page.find_child("StartingSpellListPanel", true, false) != null and setup.creator_page.find_child("StartingSpellRecord", true, false) != null and setup.creator_page.find_child("StartingSpellAllowance", true, false) != null and selected_spell != null and selected_spell.toggle_mode and selected_spell.button_pressed and available_spell != null and spell_description != null and spell_description.text == "Reveals magic." and spell_description.get_theme_font_size(&"font_size") >= 16 and spell_animation == null and view.character_draft_spell_options[0].animation_resource_ids == [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039], "Starting Spells reuses one expanding level/list/detail hierarchy with readable descriptions, exact Classic frame identities, no unresolved preview, and ordinary pressed toggle state"); available_spell.pressed.emit(); var spell_payload := creator_intents[-1].payload as PlayerIntent.StringListPayload; assert_equal(spell_payload.values, ["classic.spell.1101", "classic.spell.1102"], "ordinary spell toggles preserve selections on the current and hidden levels without a modifier key")
	var app_spell_media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); var valid_spell_preview := ClassicSpellEffectPreview.new(); var incomplete_spell_preview := ClassicSpellEffectPreview.new(); assert_true(valid_spell_preview.present(app_spell_media, "cicn", [12088, 12089, 12090, 12091, 12092, 12093, 12094, 12095]) and valid_spell_preview.find_child("StartingSpellAnimationFrames", true, false) is TextureRect and not incomplete_spell_preview.present(app_spell_media, "cicn", [11992, 11993, 11994, 11995, 11996, 11997, 11998, 11999]), "spell previews require one complete meaningful Castle-backed eight-frame sequence and omit unavailable identities"); valid_spell_preview.free(); incomplete_spell_preview.free(); router.free()
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
	revision.level = 3; revision.eligible = true
	var stored_state := CharacterState.new("vault.character", "Vault Hero", 18, 18); stored_state.level = 3; stored_state.race_id = "race.human"; stored_state.caste_id = "caste.fighter"; stored_state.portrait_id = "portrait.vault"; stored_state.combat_icon_id = "icon.vault"; revision.character = CharacterView.new(stored_state)
	router.set_vault_revisions([revision])
	router.present(view)
	router.open_screen(&"vault")
	assert_true(router.full_stage_overlay_visible(), "Character Files owns the complete stage")
	var buttons := _buttons_in(router); var file_list := router.find_child("CharacterFileList", true, false) as GridContainer; assert_true(buttons.any(func(button: Button) -> bool: return button.text == "Add to party") and file_list != null and file_list.columns == 2 and router.find_child("StoredAppearancePair", true, false) != null and router.find_child("CharacterFileActions", true, false) != null, "Character Files foregrounds reusable character cards, exact appearance roles, and current actions while revision history stays secondary")
	var inspect := buttons.filter(func(button: Button) -> bool: return button.text == "Inspect")[0] as Button; inspect.pressed.emit(); assert_true(router.find_child("VaultCharacterSheet", true, false) != null and router.find_child("CharacterIdentity", true, false) != null and router.find_child("PortraitMedia", true, false) != null and router.find_child("CombatIconMedia", true, false) != null and _buttons_in(router).any(func(button: Button) -> bool: return button.text == "Back to character vault"), "stored-character inspection replaces the library with one opaque complete sheet, stable tabs, exact appearance roles, and one Back action")
	router.free(); var review_router := ClassicScreenRouter.new(); (Engine.get_main_loop() as SceneTree).root.add_child(review_router); review_router.initialize(); var review_setup := review_router.setup_controller; var review_view := GameView.new(2, true, null); review_view.party_setup_available = true; review_view.campaign_summary = CampaignSummaryView.new(); review_view.character_draft = CharacterView.new(CharacterState.new("creator.review", "Ari", 12, 12)); review_setup.setup_mode = &"creator"; review_setup.creator_step = 3; review_setup.layout_profile = UiLayoutProfile.COMPACT; review_router.present(review_view); assert_true(review_setup.creator_page.find_child("CreatorReviewSheet", true, false) != null and review_setup.creator_page.find_child("CharacterPicker", true, false) == null and review_setup.creator_page.find_child("CharacterSheetWorkspace", true, false) != null and ["OverviewAttributes", "OverviewCombat", "OverviewStatus"].all(func(node_name: String) -> bool: return review_setup.creator_page.find_child(node_name, true, false) != null), "Review reuses the complete detached character sheet without a redundant party picker so rerolls expose their full overview facts"); review_router.free()
func _test_field_spell_workspace() -> void:
	var body := VBoxContainer.new()
	var controller := SpellsWorkspaceController.new()
	var view := GameView.new(5, true, null)
	var character_view := CharacterView.new(CharacterState.new("caster", "Aster", 12, 12))
	var definition := SpellDefinition.new("classic.spell.field", 1101, "Field Bolt")
	var spell_view := SpellView.new(definition)
	spell_view.power_levels = [1, 2]
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true)
	character_view.spells = [spell_view]
	view.party_members = [character_view]
	var submitted: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: submitted.append(intent))
	controller.present(body, view, null, 1.0)
	var cast := body.find_child("SpellCastAction", true, false) as BaseButton; var level_one := body.find_child("SpellLevel1", true, false) as Button; assert_true(cast != null and body.find_child("SpellCharacterSelector", true, false) != null and body.find_child("SpellLevelRail", true, false) != null and body.find_child("SelectedSpellRecord", true, false) != null and level_one.text == "Level 1", "roster-side spellbook keeps caster, Castle-labelled level rail, record, and fixed Cast controls together"); cast.pressed.emit()
	var cast_payload := submitted[0].payload as PlayerIntent.SpellPayload
	assert_equal([cast_payload.operation, cast_payload.caster_id, cast_payload.spell_id, cast_payload.power], [&"cast", "caster", "classic.spell.field", 1], "compact spell action preserves the selected caster, spell, and power")
	body.free()
func _test_inventory_workspace() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-ui", 10, "Longsword", "Sword", "A balanced sword."); definition.icon_id = 20; definition.vs_small = 10
	var source := CharacterState.new("source", "Alis", 10, 10); var destination := CharacterState.new("destination", "Borin", 12, 12)
	var view := GameView.new(4, true, null)
	var source_view := CharacterView.new(source); var destination_view := CharacterView.new(destination)
	var item_view := ItemView.new(ItemInstance.new("inventory.item", definition.id, 0, false, true), definition)
	item_view.actions.equip = ActionAvailabilityView.new(&"equip_item", true); item_view.actions.split = ActionAvailabilityView.new(&"split_item", true); item_view.actions.join = ActionAvailabilityView.new(&"join_item", true)
	item_view.actions.use = ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
	item_view.actions.trade = ActionAvailabilityView.new(&"trade_item", true); item_view.actions.trade_targets = [ItemTransferTargetView.new(destination.id, destination.name, true, "", 12, 17, 100)]
	source_view.items = [item_view]
	view.party_members = [source_view, destination_view]
	var body := VBoxContainer.new()
	var controller := InventoryWorkspaceController.new(); var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); controller.present(body, view, media, 1.0)
	var buttons := _base_buttons_in(body)
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Longsword") and (button as Button).theme_type_variation == &"ClassicItemLedgerButton") and (body.find_child("InventoryItemBrowser", true, false) as PanelContainer).theme_type_variation == &"ClassicItemLedger" and (body.find_child("InventoryItemLineFact", true, false) as Label).text == "Damage 1–10", "inventory renders selectable carried items and detached Classic line facts on the paper-white Black Chancery ledger")
	assert_true(["CastleInventoryMainSplit", "InventoryItemBrowser", "InventoryCharacterCommandRail", "InventoryCharacterFacts", "InventoryActionDock", "InventoryCharacterSelector", "InventoryItemInspector", "InventorySelectedItemRecord"].all(func(node_name: String) -> bool: return body.find_child(node_name, true, false) != null), "inventory follows Castle's icon-led pack, character command rail, integrated party selector, and full-width selected-item record hierarchy"); assert_true(buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text == "Equip"), "inventory exposes the typed Equip action"); assert_true(body.find_children("ContentImage", "TextureRect", true, false).size() == 2 and body.find_children("ContentImage", "TextureRect", true, false).all(func(image: TextureRect) -> bool: return image.custom_minimum_size.x > 0.0) and body.find_children("ContentImageUnavailable", "Label", true, false).is_empty(), "inventory keeps each exact item image visibly sized in both list and record without exposing a variable-width resource ID")
	var split_action := buttons.filter(func(button: BaseButton) -> bool: return button.tooltip_text == "Split" and not button.disabled)[0] as ClassicBitmapButton; assert_true(split_action != null and split_action.custom_minimum_size == Vector2(62.0, 56.0) and buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text == "Join" and not button.disabled) and buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text.contains("not implemented")), "inventory exposes core-authorized stack actions and source-owned unavailable reasons on one text-led Rebuilt slate button geometry"); split_action.command_requested.emit(&"inventory.action.split"); controller.present(body, view, media, 1.0)
	assert_true(body.find_child("InventoryOperationStage", true, false) != null and _labels_in(body).any(func(text: String) -> bool: return text.contains("Split this charged record")), "one stable operation stage keeps exact item facts and conservative consequence copy")
	var cancel_operation := _buttons_in(body.find_child("InventoryOperationActions", true, false)).filter(func(button: Button) -> bool: return button.text == "Cancel")[0] as Button; cancel_operation.pressed.emit(); controller.present(body, view, media, 1.0); buttons = _base_buttons_in(body); var trade := buttons.filter(func(button: BaseButton) -> bool: return button.tooltip_text == "Choose a recipient from the Party roster")[0] as ClassicBitmapButton; trade.command_requested.emit(&"inventory.action.trade"); controller.present(body, view, media, 1.0); var recipients := body.find_child("InventoryTradeRecipients", true, false); var recipient := _buttons_in(recipients).filter(func(button: Button) -> bool: return button.text == destination.name)[0] as Button; assert_true(_labels_in(recipients).has("12 → 17 / 100"), "Trade renders core-projected current, resulting, and maximum recipient load beside the exact selected item"); recipient.pressed.emit(); controller.present(body, view, media, 1.0); var transfer := _buttons_in(body.find_child("InventoryTradeActions", true, false)).filter(func(button: Button) -> bool: return button.text == "Transfer")[0] as Button; transfer.pressed.emit()
	assert_equal([intents.size(), intents[0].kind], [1, PlayerIntent.Kind.TRADE_ITEM], "item-local recipient selection emits one typed transfer")
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
	assert_true(body.find_child("MoneyPoolPane", true, false) != null and body.find_child("MoneyPartyPane", true, false) != null and body.find_child("MoneySwapPane", true, false) != null and ["Gold", "Gems", "Jewelry", "15"].all(func(text: String) -> bool: return labels.has(text)), "money workspace separates the detached pool, adventurers, and exact-denomination Swap records")
	assert_true(labels.any(func(text: String) -> bool: return text.contains("Banked") and text.contains("50 gold")), "banked wealth remains visible without being merged into ordinary Swap")
	var pool_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Pool")[0]
	var share_button: Button = buttons.filter(func(button: Button) -> bool: return button.text == "Share")[0]
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
	router.open_screen(&"character"); (_buttons_in(router).filter(func(button: Button) -> bool: return button.text == "Reorder Party")[0] as Button).pressed.emit()
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
	character.gender = 2; character.level = 7; character.race_id = "classic.race.1"; character.caste_id = "classic.caste.2"
	var view := CharacterView.new(character)
	view.items = [ItemView.new(ItemInstance.new("equipped-sword", "classic.item.1", 0, true, true), ItemDefinition.new("classic.item.1", 1, "Longsword", "Sword")), ItemView.new(ItemInstance.new("carried-torch", "classic.item.805", 6, false, true), ItemDefinition.new("classic.item.805", 805, "Torch", "Equipment"))]; assert_equal(view.gender_name, "Female", "the detached sheet preserves Classic identity")
	var sheet := ClassicCharacterSheet.new(); sheet.present([view], view.id, {}, 1.0, &"equipment", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT)
	for label: String in ["Overview", "Conditions & Saves", "Equipment", "Abilities", "Spells", "Appearance", "Race, Caste & Aging", "Lifetime Record"]: assert_true(_buttons_in(sheet).any(func(button: Button) -> bool: return button.text == label), "sheet exposes %s" % label)
	assert_true(sheet.find_child("EquippedItems", true, false) != null and sheet.find_child("CarriedItems", true, false) != null, "equipment separates exact equipped instances from the carried pack in compact composition")
	sheet.present([view], view.id, {}, 1.0, &"overview", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(["OverviewAttributes", "OverviewCombat", "OverviewStatus"].all(func(node_name: String) -> bool: return sheet.find_child(node_name, true, false) != null), "overview keeps identity, combat, and resource records in three stable wide regions")
	sheet.present([view], view.id, {}, 1.0, &"conditions", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT); assert_true(sheet.find_child("ConditionsRegion", true, false) != null and sheet.find_child("SavingThrowsRegion", true, false) != null, "conditions and all saving throws retain separate compact records")
	sheet.present([view], view.id, {}, 1.0, &"abilities", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(sheet.find_child("SpecialModifiersRegion", true, false) != null and sheet.find_child("SpecialAbilitiesRegion", true, false) != null, "special modifiers and abilities retain separate wide records"); sheet.present([view], view.id, {}, 1.0, &"background", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(["RaceRegion", "CasteRegion", "AgingRegion"].all(func(node_name: String) -> bool: return sheet.find_child(node_name, true, false) != null), "race, caste, and aging retain separate source-backed records"); sheet.present([view], view.id, {}, 1.0, &"spells", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(sheet.find_child("KnownSpellRegion", true, false) != null and sheet.find_child("ScrollCaseRegion", true, false) != null, "known spells and the fixed scroll case retain separate records"); sheet.present([view], view.id, {}, 1.0, &"appearance", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT); assert_true(sheet.find_child("PortraitAppearanceRegion", true, false) != null and sheet.find_child("CombatIconAppearanceRegion", true, false) != null and sheet.find_child("DiscardAppearanceChanges", true, false) != null, "appearance preserves two independent exact-media roles and one local discard action"); sheet.present([view], view.id, {}, 1.0, &"record", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_not_null(sheet.find_child("LifetimeRecordUnavailable", true, false), "missing lifetime ownership produces one explicit unavailable record rather than invented zeroes")
	sheet.free()
func _test_scene_composition() -> void:
	var scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell.get_node_or_null("ScreenRouter"), "the shell owns one workspace router")
	assert_not_null(shell.get_node_or_null("BottomRegion/BottomRow/NarrativeWell"), "the shell owns a narrative well")
	assert_true(shell.get_node_or_null("BottomRegion/BottomRow/WorldCommandPanel") != null and shell.get_node_or_null("BottomRegion/BottomRow/CommandPanel") != null and shell.find_child("Light", true, false) != null, "exploration dedicates separate footer panes to world and party commands while surfacing typed light state")
	var exploration_commands := ClassicCommandCatalog.for_context(&"exploration")
	assert_true([&"search_mode", &"contextual", &"camp", &"heal"].all(func(id: StringName) -> bool: return exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == id and definition["group"] == &"world")) and ClassicCommandCatalog.command(&"camp")["asset_id"] == &"command.camp" and ClassicCommandCatalog.command(&"contextual")["symbol"] == &"yin_yang" and ClassicCommandCatalog.command(&"heal")["hold_repeat"] and not ClassicApplicationShell.should_stop_held_command_on_button_up(true) and ClassicApplicationShell.should_stop_held_command_on_button_up(false) and [ClassicApplicationShell.command_route(&"money"), ClassicApplicationShell.command_route(&"inventory"), ClassicApplicationShell.command_route(&"spells"), ClassicApplicationShell.command_route(&"maps")].all(func(route: StringName) -> bool: return not route.is_empty()), "Search, source-shaped Encounter, rerender-safe held Heal, persistent Camp, and routed Party controls own stable pressed identities"); assert_equal([ClassicApplicationShell.held_command_start_sound_id(&"rest", false), ClassicApplicationShell.held_command_start_sound_id(&"area_search", false), ClassicApplicationShell.held_command_start_sound_id(&"rest", true)], [6001, 6001, 0], "Rest and Area Search request Castle sound 6001 once when a held cycle starts and stay quiet on repeat pulses")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"settings" and definition["group"] == &"world"), "preferences remain with Adventure and system controls instead of displacing party actions")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"inventory" and definition["group"] == &"party"), "party workspaces remain grouped beside the narrative well")
	var world_panel := shell.get_node("BottomRegion/BottomRow/WorldCommandPanel") as Control
	var narrative_well := shell.get_node("BottomRegion/BottomRow/NarrativeWell") as Control
	var party_panel := shell.get_node("BottomRegion/BottomRow/CommandPanel") as Control
	assert_equal([world_panel.size_flags_horizontal, narrative_well.size_flags_horizontal, party_panel.size_flags_horizontal], [Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_CENTER, Control.SIZE_EXPAND_FILL], "the wide footer gives spare width to both command panes while keeping the Classic narrative measure fixed")
	assert_equal(RealmzApplication.classic_textbox_rect(Rect2(0.0, 32.0, 992.0, 498.0), 190.0, 1280.0), Rect2(0.0, 530.0, 1280.0, 190.0), "Classic narrative interactions own the complete bottom stage rather than only the map column")
	var backing := shell.get_node("PictureStage/PictureBacking") as TextureRect; var roster := shell.get_node("PartyRoster") as PanelContainer; var picture_caption := shell.get_node("PictureStage/PictureMargin/PictureColumn/PictureCaption") as Label
	assert_true(backing.stretch_mode == TextureRect.STRETCH_TILE and not picture_caption.visible and roster.theme_type_variation == &"ClassicInset", "picture and roster stages use owned Classic framing without exposing package media IDs")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(1280, 720)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
		assert_true(rect.position.x >= 0.0 and rect.end.x <= viewport_size.x - profile.party_width and ClassicScreenRouter.spell_workspace_rect_for(profile, viewport_size) == Rect2(viewport_size.x - profile.party_width, profile.menu_height, profile.party_width, viewport_size.y - profile.menu_height), "campaign layout stays clear while field spellcasting owns the full right column at %s" % viewport_size)
	assert_equal([ClassicApplicationShell.party_roster_height(720.0, 28.0, 502.0, true), ClassicApplicationShell.party_roster_z_index(true)], [692.0, 81], "combat spellcasting expands above the inert Party-command footer and owns the complete right rail"); assert_equal([ClassicApplicationShell.party_roster_height(720.0, 28.0, 502.0, false), ClassicApplicationShell.party_roster_z_index(false)], [502.0, 14], "closing the combat spellbook restores the ordinary six-character roster stage")
	var modal_parent := Control.new(); var modal_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter; modal_parent.add_child(modal_presenter); modal_presenter.call("_update_modal_shield", true); var modal_shield := modal_parent.get_node("LockedModalShield") as Control; var first_order := [modal_shield.get_index(), modal_presenter.get_index()]; modal_presenter.call("_update_modal_shield", true); var repeated_order := [modal_shield.get_index(), modal_presenter.get_index()]; assert_true(first_order[0] < first_order[1] and repeated_order[0] < repeated_order[1] and repeated_order == first_order, "rerendering a locked modal keeps its pointer-blocking shield behind the clickable presenter instead of swapping their input order"); modal_parent.free()
	var spatial_view := GameView.new(1, true, null); assert_true(PresentationCoordinator.should_show_exploration_stage(&"spells", spatial_view, true), "field Spells preserves the live exploration renderer beneath its Party-side spellbook"); shell.free()
func _test_automatic_workflow_routes() -> void:
	var terminal_step := SessionStep.completed(1, [DomainEvent.new(&"session_ended", {"reason": "party-defeat"})])
	assert_true(RealmzApplication.should_defer_session_close(terminal_step, true), "terminal host navigation waits until committed combat playback releases its retained battlefield")
	assert_false(RealmzApplication.should_defer_session_close(terminal_step, false), "terminal host navigation proceeds immediately when no presentation playback owns the prior view")
	var no_session := GameView.new(0, false, null)
	assert_equal(ClassicApplicationShell.route_change_reason(no_session), "Choose a campaign first.", "gameplay routes are disabled on the splash and campaign library")
	var setup_view := GameView.new(1, true, null)
	setup_view.party_setup_available = true
	assert_equal(ClassicApplicationShell.route_change_reason(setup_view), "Begin the adventure first.", "Explore and other browsing routes stay disabled until party setup commits Begin Adventure")
	var view := GameView.new(1, true, null); view.combat_view = CombatView.new(CombatState.new("classic.battle.route")); view.combat_action_request = ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	assert_equal(view.active_interaction_request(), view.combat_action_request, "direct combat exposes its detached command request without fabricating a pending VM interaction")
	var move_body := InteractionResponse.CombatBody.new(&"move", "character.route"); move_body.destination = Vector2i(4, 7); move_body.has_destination = true; move_body.auto_switch_to_melee = true
	var move_intent := RealmzApplication.direct_combat_intent(move_body); assert_equal([move_intent.kind, move_intent.payload.actor_id, move_intent.payload.destination, move_intent.payload.auto_switch_to_melee], [PlayerIntent.Kind.COMBAT_MOVE, "character.route", Vector2i(4, 7), true], "the direct command deck submits the same typed combat-move intent and host preference as battlefield input")
	var queued_off := RealmzApplication.combat_auto_change_to_queue(PlayerIntent.set_combat_auto("hero", false), true)
	var auto_view := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active"); auto_view.combat_view.auto_character_ids = ["hero"]; auto_view.combat_action_request = ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	var persistent_response := RealmzApplication.persistent_auto_response(auto_view)
	assert_true(queued_off == {"characterId": "hero", "enabled": false} and RealmzApplication.combat_auto_change_to_queue(PlayerIntent.set_combat_auto("hero", false), false).is_empty() and RealmzApplication.combat_auto_abort_ids(auto_view, {"queued": true}) == ["hero", "queued"] and persistent_response != null and (persistent_response.body as InteractionResponse.CombatBody).actor_id == "hero", "the host queues individual manual control, can enumerate a full-party Escape abort, and prepares only the next Auto activation")
	assert_equal([ClassicApplicationShell.automatic_workflow_route(&"exploration", view), ClassicApplicationShell.automatic_workflow_route(&"inventory", view)], [&"combat", &"combat"], "battle setup replaces exploration or browsing with the tactical workspace")
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
