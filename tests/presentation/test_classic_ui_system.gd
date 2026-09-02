extends "res://tests/presentation/classic_ui_test_support.gd"

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")
const RetainedMapSurfaceScript := preload("res://src/presentation/classic_retained_map_surface.gd")
const FastSpellDockScript := preload("res://src/presentation/interaction_components/fast_spell_dock.gd"); const ScrollingTextInteractionScript := preload("res://src/presentation/interaction_components/scrolling_text_interaction.gd")
const InteractionLayoutPolicyScript := preload("res://src/presentation/interaction_layout_policy.gd")

class RejectingSaveRepository extends SaveRepository:
	func save(_campaign_id: String, _slot_id: String, _snapshot: SessionSnapshot) -> bool: last_error = "Injected repository failure."; return false


func run() -> void:
	_test_shared_scrollbar_controls()
	_test_startup_shell()
	_test_layout_profiles()
	_test_settings_schema_and_migration()
	_test_movement_input()
	_test_fast_spell_input()
	_test_fixture_gallery_coverage()
	await _test_treasure_slot_and_pickup_origin()
	_test_lifecycle_interaction()
	await _test_battle_weapon_mode_component()
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
	_test_scroll_case_workspace()
	await _test_inventory_workspace()
	_test_party_order_workspace()
	_test_character_sheet_workspace()
	_test_scene_composition()
	await _test_exploration_map_camera_preserves_viewport_geometry()
	_test_automatic_workflow_routes(); await _test_classic_choice_context()


func _test_startup_shell() -> void:
	var front_door := load("res://src/presentation/startup_front_door.tscn").instantiate() as StartupFrontDoor; (Engine.get_main_loop() as SceneTree).root.add_child(front_door); await (Engine.get_main_loop() as SceneTree).process_frame; var classic_startup := SettingsRepository.new().load_settings().typography_mode == PresentationSettings.TYPOGRAPHY_CLASSIC; var expected_heading := load(ClassicTypography.BLACK_CHANCERY_PATH if classic_startup else ClassicTypography.READABLE_BOLD_PATH) as Font; var expected_body := load(ClassicTypography.THELDROW_PATH if classic_startup else ClassicTypography.READABLE_UI_PATH) as Font; var startup_image := front_door.find_child("StartupSplash", true, false) as TextureRect; var startup_background := front_door.find_child("StartupSplashBackground", true, false) as ColorRect; var startup_timer := front_door.find_child("StartupDuration", true, false) as Timer; var exit_timer := front_door.find_child("SplashExitDelay", true, false) as Timer; var transition_audio := front_door.find_child("StartupLaunchTransition", true, false) as AudioStreamPlayer; var transition_stream := transition_audio.stream as AudioStreamWAV; var launch_music := front_door.find_child("StartupLaunchMusic", true, false) as AudioStreamPlayer; var startup_choose := front_door.find_child("ChooseScenario", true, false) as Button; assert_true(startup_image.visible and startup_background.visible and startup_background.color == Color.BLACK and startup_image.texture.resource_path == "res://src/presentation/assets/ui/intro/rebuilt-launch-splash.jpg" and startup_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and is_equal_approx(startup_timer.wait_time, 3.0) and is_equal_approx(exit_timer.wait_time, 1.513) and not startup_timer.is_stopped() and transition_audio.stream.resource_path.ends_with("snd-624.wav") and transition_stream != null and transition_stream.format == AudioStreamWAV.FORMAT_16_BITS and not transition_stream.stereo and transition_stream.mix_rate == 48000 and launch_music.stream.resource_path.ends_with("snd-20.wav") and startup_choose.disabled and (front_door.find_child("LoadAdventure", true, false) as Button).disabled and (front_door.find_child("CharacterFiles", true, false) as Button).disabled and not (front_door.find_child("Quit", true, false) as Button).disabled and not (front_door.find_child("StartupFailure", true, false) as Control).visible and front_door.find_child("LoadingStatus", true, false) == null, "the lightweight front door immediately reveals its supplied launch card and first Castle-rendered source-backed cue together over opaque black, holds for three seconds before the exit cue, and exposes no routine loading caption while keeping only Quit available"); assert_equal([(front_door.find_child("SplashTitle", true, false) as Label).get_theme_font(&"font").get_font_name(), startup_choose.get_theme_font(&"font").get_font_name(), (front_door.find_child("StartupFailureMessage", true, false) as Label).get_theme_font(&"font").get_font_name()], [expected_heading.get_font_name(), expected_heading.get_font_name() if classic_startup else expected_body.get_font_name(), expected_body.get_font_name()], "the process front door applies the saved shared typography roles before constructing the main menu")
	while not front_door.application_ready(): await (Engine.get_main_loop() as SceneTree).process_frame
	var prepared_front_door_intro := front_door.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation; var prepared_decoder_count := 0; for candidate: Node in (Engine.get_main_loop() as SceneTree).root.find_children("RealmzIntroAnimation", "ClassicIntroAnimation", true, false): if (candidate as ClassicIntroAnimation).resources_prepared(): prepared_decoder_count += 1
	assert_true(front_door.application_ready() and prepared_front_door_intro != null and prepared_front_door_intro.resources_prepared() and prepared_front_door_intro.playback_active() and prepared_front_door_intro.preparation_count() == 1 and prepared_decoder_count == 1, "background application construction leaves exactly one retained intro decoder running behind the opaque launch card"); startup_timer.stop(); startup_timer.timeout.emit(); exit_timer.stop(); exit_timer.timeout.emit(); await (Engine.get_main_loop() as SceneTree).process_frame; assert_true(front_door.menu_visible() and prepared_front_door_intro.playback_active() and prepared_front_door_intro.preparation_count() == 1, "menu reveal exposes an already-playing decoded frame without reopening the OGV"); front_door.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame; var router := ClassicScreenRouter.new(); (Engine.get_main_loop() as SceneTree).root.add_child(router); router.initialize()
	router.show_splash()
	var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(1280, 720))
	router.set_standalone_character_creation_available(true)
	var splash := router.find_child("SplashScreen", true, false) as Control
	assert_true(splash != null and splash.visible, "Realmz Rebuilt opens on its application splash instead of dropping directly into package selection")
	assert_false(router.setup_controller.campaign_overlay.visible, "the campaign library waits for an explicit splash action")
	var choose_scenario := splash.find_child("ChooseScenario", true, false) as Button
	var character_files := splash.find_child("CharacterFiles", true, false) as Button; var load_adventure := splash.find_child("LoadAdventure", true, false) as Button
	var intro_animation := splash.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation; var intro_soundtrack := splash.find_child("RealmzIntroSoundtrack", true, false) as AudioStreamPlayer; assert_true(choose_scenario != null and load_adventure != null, "the splash exposes new and saved adventures as primary paths"); assert_true(splash.find_child("SplashIdentityPanel", true, false) != null and splash.find_child("SplashCommandPanel", true, false) != null and intro_animation != null and intro_animation.resources_prepared() and intro_animation.preparation_count() == 1 and intro_animation.playback_active() and not intro_animation.autoplay and intro_animation.loop and not intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, -80.0) and intro_soundtrack != null and not intro_soundtrack.autoplay and intro_soundtrack.stream == null and is_equal_approx(intro_soundtrack.volume_db, -80.0) and splash.find_child("RealmzIntroOrnament", true, false) is NinePatchRect and splash.find_child("SplashTitle", true, false) != null and splash.find_child("SplashSubtitle", true, false) != null and (splash.find_child("SplashComposition", true, false) as BoxContainer).vertical == false, "the canonical splash retains one already-playing silent video decoder while deferring its independent soundtrack until requested"); intro_animation.toggle_audio(); assert_true(intro_animation.audio_enabled and intro_soundtrack.stream is AudioStreamMP3 and (intro_soundtrack.stream as AudioStreamMP3).loop and is_equal_approx(intro_animation.volume_db, -80.0) and is_equal_approx(intro_soundtrack.volume_db, 0.0), "clicking the video loads and enables only the independent soundtrack at the current master level"); intro_animation.toggle_audio(); assert_true(not intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, -80.0) and intro_soundtrack.stream is AudioStreamMP3 and is_equal_approx(intro_soundtrack.volume_db, -80.0), "clicking again mutes the retained soundtrack without enabling embedded video audio"); router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); assert_true((splash.find_child("SplashComposition", true, false) as BoxContainer).vertical, "the compact splash stacks identity and commands without changing their ownership"); router.set_layout_profile(profile, Vector2(1280, 720))
	assert_not_null(character_files, "the splash exposes reusable character files independently of party setup")
	choose_scenario.pressed.emit()
	var setup_workspace := router.find_child("PartySetup", true, false) as Control
	var scenario_picker := router.find_child("ScenarioColumn", true, false) as Control
	if scenario_picker == null:
		scenario_picker = router.find_child("CampaignLibrary", true, false) as Control
	assert_true(setup_workspace != null and setup_workspace.visible and not splash.visible and intro_animation.resources_prepared() and not intro_animation.playback_active() and intro_animation.preparation_count() == 1 and intro_soundtrack.stream is AudioStreamMP3 and intro_soundtrack.stream_paused, "scenario selection suspends the retained intro resources without creating another decoder")
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
	assert_true(splash.visible and intro_animation.resources_prepared() and intro_animation.playback_active(), "closing startup Character Files restores the retained splash decoder and resumes playback"); var load_view := GameView.new(1, true, null); load_view.party_setup_available = true; load_view.campaign_id = "load-fixture"; load_view.rules_version = "realmz-classic-1"; load_view.campaign_summary = CampaignSummaryView.new(); load_adventure.pressed.emit(); router.present(load_view); assert_true(router.current_screen() == &"system" and router.find_child("LoadSelectedSave", true, false) != null and not _buttons_in(router).any(func(button: Button) -> bool: return button.text == "Quick Save"), "Load saved adventure selects a scenario and then opens package-validated restore records without offering a blocked setup save"); assert_true(router.handle_back() and router.setup_controller.setup_overlay.visible, "Back from pre-adventure saves returns to Begin Adventure"); (router.find_child("LoadSavedAdventure", true, false) as Button).pressed.emit(); assert_equal(router.current_screen(), &"system", "Begin Adventure exposes the same package-bound Save and Load workspace")
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
	var combat_speed_slider := body.find_child("CombatPlaybackSpeedSlider", true, false) as HSlider; combat_speed_slider.value = 150.0; combat_speed_slider.value_changed.emit(150.0); assert_true(["Display", "Audio", "Pacing", "Accessibility", "Controls", "Diagnostics"].all(func(tab: String) -> bool: return body.find_child("%sSettingsPanel" % tab, true, false) != null and body.find_child("%sSettingsScroll" % tab, true, false) is ScrollContainer), "the dedicated Pacing tab remains scroll-reachable beside every settings domain"); assert_true((body.find_child("CombatPlaybackSpeedCaption", true, false) as Label).text.ends_with("150%"), "the combat speed caption updates while the slider is dragged"); assert_true(body.find_child("ExplorationSpeedSlider", true, false) is HSlider, "exploration travel cadence shares the dedicated Pacing tab"); assert_true(load_selected != null and current_row != null and current_row.text.begins_with("Quick Save 1") and backup_row != null and corrupt_row != null and body.find_child("SaveSelectedSlot", true, false) != null and body.find_child("SaveNewSlot", true, false) != null and ["Quick Save 1", "Quick Save 2"].all(func(label: String) -> bool: return _buttons_in(body).any(func(button: Button) -> bool: return button.text == label)) and SystemWorkspaceController.CONTROL_HELP.size() == 5 and SystemWorkspaceController.CONTROL_HELP.all(func(entry: Dictionary) -> bool: return body.find_child("ControlHelp%s" % String(entry["title"]).replace(" ", ""), true, false) != null) and body.find_child("ClassicExplorationVisibility", true, false) is CheckButton and (body.find_child("ClassicExplorationVisibility", true, false) as CheckButton).button_pressed and [body.find_child("InterfaceScalePicker", true, false), body.find_child("TypographyPicker", true, false), body.find_child("WindowModePicker", true, false)].all(func(picker: Node) -> bool: return picker is OptionButton and (picker as OptionButton).theme_type_variation == &"ClassicTheldrowOptionButton") and _buttons_in(body).any(func(button: Button) -> bool: return button.text == "Main Menu"), "the system route documents fixed inputs, preserves Rebuilt Display pickers, and exposes both stable quick slots, named saves, and Main Menu")
	(_buttons_in(body).filter(func(button: Button) -> bool: return button.text == "Quick Save 2")[0] as Button).pressed.emit(); current_row.pressed.emit(); (body.find_child("SaveSelectedSlot", true, false) as Button).pressed.emit(); var slot_name := body.find_child("NewSaveSlotName", true, false) as LineEdit; slot_name.text = "camp-01"; slot_name.text_changed.emit(slot_name.text); (body.find_child("SaveNewSlot", true, false) as Button).pressed.emit(); load_selected.pressed.emit(); backup_row.pressed.emit(); load_selected.pressed.emit()
	corrupt_row.pressed.emit()
	assert_true(load_selected.disabled and load_selected.tooltip_text.contains("corrupt"), "a corrupt selected record remains visible with its exact disabled reason")
	assert_equal(actions, [{"action": &"save", "value": "quick-2"}, {"action": &"save", "value": "quick"}, {"action": &"save", "value": "camp-01"}, {"action": &"load", "value": "quick"}, {"action": &"load_backup", "value": "quick"}], "both stable quick slots plus regular named, selected, current-load, and backup-load controls emit distinct existing host operations")
	body.free(); body = VBoxContainer.new(); controller.set_layout_profile(UiLayoutProfile.COMPACT); var large_text := PresentationSettings.new(); large_text.text_scale = 1.5; controller.present(body, view, large_text); assert_true((body.find_child("ControlHelpExplore", true, false) as PanelContainer).get_child(0).vertical and body.find_child("ControlsSettingsScroll", true, false) is ScrollContainer and body.find_child("PacingSettingsScroll", true, false) is ScrollContainer, "800x600 Classic settings stack control help and retain scroll-reachable Pacing at 150 percent text"); body.free(); body = VBoxContainer.new(); controller.set_layout_profile(UiLayoutProfile.WIDE); controller.set_save_and_quit_mode(true); controller.present(body, view, PresentationSettings.new())
	var save_and_quit := body.find_child("SaveAndQuitSelected", true, false) as Button; (body.find_child("SavePreview_quick_primary", true, false) as Button).pressed.emit(); save_and_quit.pressed.emit(); assert_equal(actions[-1], {"action": &"save_and_quit", "value": "quick"}, "Save and Quit uses the selected slot instead of writing before confirmation closes"); body.free()


func _test_location_note_workspace() -> void:
	var view := GameView.new(4, true, null)
	view.party_summary = PartySummaryView.new()
	view.current_location_note = LocationNoteView.new("land:0", "Giant Mountain", &"land", 0, Vector2i(49, 15), "Watch the ridge.", 0, 0, true)
	view.location_notes = [
		view.current_location_note,
		LocationNoteView.new("land:0", "Giant Mountain", &"land", 0, Vector2i(12, 8), "A safe campsite.", 3, 1),
	]; view.location_notes[1].preview_map = MapView.new("land:0", "Giant Mountain", &"land", 20, 20, Vector2i(12, 8), [], true, [Vector2i(12, 8)], {}, Vector2i.ZERO, 0, 1, true, false, 0, false, true, 3)
	view.journal_entries = [
		JournalEntryView.new(0, ""),
		JournalEntryView.new(4, "The road bends toward the mountain."),
		JournalEntryView.new(2999, "A".repeat(255)),]
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
	var cancel := body.find_child("CancelLocationNoteEdit", true, false) as Button; (body.find_child("LocationNote_1", true, false) as Button).pressed.emit()
	assert_true(editor != null and body.find_child("MapsNotesTabs", true, false) != null and body.find_child("SavedLocationNotes", true, false) != null and body.find_child("JournalEntryDetail", true, false) != null and body.find_child("HistoricalLocationMap", true, false) != null and (body.find_child("LocationNote_1", true, false) as Button).button_pressed and ClassicMapPresenter.darkness_mask_asset_id(3) == "classic-darkness-mask-3", "Maps/Notes selects a saved place, renders its detached recentered map with the saved Classic darkness mask, and retains the current-note editor and authored journal detail")
	assert_equal(editor.text, "Watch the ridge.", "the editor begins from detached committed note text"); assert_true(_labels_in(body).has("Journal entry 0") and (body.find_child("JournalEntryDetailBody", true, false) as VBoxContainer).get_children().any(func(child: Node) -> bool: return child is Label and (child as Label).text.is_empty()), "an empty authored Data SD2 record retains its stable identity and renders as an immutable empty journal page")
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
	assert_true((body.find_child("LocationNote_1", true, false) as Button).text.contains("A safe campsite."), "saved location notes remain readable while only the current record is editable")
	var journal_search := body.find_child("JournalSearch", true, false) as LineEdit; journal_search.text = "mountain"; journal_search.text_changed.emit(journal_search.text); assert_equal(journal_search.theme_type_variation, &"ClassicTheldrowLineEdit", "the Journal search retains the Rebuilt font role"); assert_true(_buttons_in(body).any(func(button: Button) -> bool: return button.text == "Journal entry 4"), "the Journal route labels authored records by their stable source message identity"); assert_equal((body.find_child("JournalEntryRows", true, false) as VBoxContainer).get_children().filter(func(child: Node) -> bool: return child is Control and (child as Control).visible).size(), 1, "the Journal search filters detached source text without gameplay mutation")
	var maximum_entry: Button = _buttons_in(body).filter(func(button: Button) -> bool: return button.text == "Journal entry 2999")[0]; maximum_entry.pressed.emit(); assert_true(_labels_in(body).any(func(text: String) -> bool: return text.length() == 255 and text == "A".repeat(255)), "the maximum 255-byte Data SD2 record remains intact in the scrollable journal detail")
	body.free()


func _test_battle_weapon_mode_component() -> void:
	var request := _fixture_request("battle.commands", InteractionRequest.COMBAT, {"actions": ["finish", "defend", "switch_weapon", "cast_spell", "use_item", "retreat"], "weaponMode": "missile", "weaponSwitch": {"enabled": true, "reason": "", "targetMode": "melee"}, "retreat": {"enabled": false, "reason": "An enemy is too close."}})
	var turn_icon := GradientTexture1D.new(); var component := BattleInteraction.new(); var submitted_bodies: Array[InteractionResponse.Body] = []; component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted_bodies.append(body)); component.theme = load("res://src/presentation/classic_ui_theme.tres"); component.configure({"hero": turn_icon, "monster": turn_icon}); component.build(request)
	var primary := component.find_child("BattlePrimaryCommands", true, false); var secondary := component.find_child("BattleTurnCommands", true, false)
	assert_equal(_buttons_in(primary).map(func(button: Button) -> String: return button.text), ["Weapon: Melee", "Guard", "Fire", "Finish", "Spells", "Scrolls", "Items"], "the compact Action group preserves its fixed source-backed command slots")
	assert_equal(_buttons_in(secondary).map(func(button: Button) -> String: return button.text), ["Auto Turn", "Delay", "Bandage", "Turn Undead", "Undo", "Escape"], "the compact Turn group preserves unavailable commands without reflow")
	var initiative := component.find_child("BattleInitiativeOrder", true, false)
	assert_equal([_direct_buttons_in(initiative).map(func(button: Button) -> String: return button.text), _direct_buttons_in(initiative).all(func(button: Button) -> bool: return button.icon == turn_icon), (component.find_child("ActiveCombatantIcon", true, false) as TextureRect).texture, (component.find_child("InspectedCombatantIcon", true, false) as TextureRect).texture], [["NOW", "NEXT"], true, turn_icon, turn_icon], "the turn summary and compact initiative strip use supplied exact combat icons from the active actor onward")
	var escape := component.find_child("CombatCommandEscape", true, false) as Button
	assert_true(escape.disabled and not escape.tooltip_text.is_empty(), "unavailable retreat carries a typed reason")
	assert_true(_labels_in(component).any(func(text: String) -> bool: return text.contains("Goblin")) and component.get_combined_minimum_size().y <= 190.0, "target facts and both command rows fit the canonical combat region")
	var expanded := BattleInteraction.new(); expanded.theme = load("res://src/presentation/classic_ui_theme.tres"); expanded.configure({"hero": turn_icon, "monster": turn_icon}); expanded.build(request); var expanded_action := expanded.find_child("BattlePrimaryCommandsInset", true, false) as Control; var expanded_attack := expanded.find_child("CombatCommandAttack", true, false) as Button; var expanded_heading := expanded.find_child("BattlePrimaryCommands", true, false).get_child(0) as Label; expanded.set_command_scale(2.0); assert_true(expanded_action.custom_minimum_size.y == 200.0 and expanded_attack.custom_minimum_size.y == 60.0 and expanded_attack.get_theme_font_size("font_size") == 28 and expanded_heading.get_theme_font_size("font_size") == 28 and InteractionLayoutPolicyScript.combat_command_scale(Rect2(0.0, 0.0, 2560.0, 380.0)) == 2.0 and InteractionLayoutPolicyScript.combat_command_scale(Rect2(0.0, 0.0, 2474.0, 285.0)) > 1.9, "surplus combat-console space and live reflow enlarge View, Action, and Tactics sections, controls, and text together up to the exact two-times cap"); expanded.set_command_scale(1.0); assert_true(expanded_action.custom_minimum_size.y == 100.0 and expanded_attack.custom_minimum_size.y == 30.0 and expanded_attack.get_theme_font_size("font_size") == 14, "a live combat-console contraction restores canonical command geometry without rebuilding the interaction"); expanded.free()
	var live_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter; (Engine.get_main_loop() as SceneTree).root.add_child(live_presenter); live_presenter.set_classic_regions(Rect2(0.0, 28.0, 992.0, 502.0), Rect2(8.0, 530.0, 984.0, 190.0), Rect2(0.0, 530.0, 1280.0, 190.0)); live_presenter.present(request); var live_component := live_presenter.find_child("BattleOverview", true, false).get_parent() as BattleInteraction; var live_attack := live_component.find_child("CombatCommandAttack", true, false) as Button; live_presenter.set_classic_regions(Rect2(0.0, 42.0, 1916.0, 753.0), Rect2(12.0, 795.0, 1916.0, 285.0), Rect2(0.0, 795.0, 2474.0, 285.0)); assert_true(live_presenter.find_child("BattleOverview", true, false).get_parent() == live_component and live_attack.custom_minimum_size.y > 57.0 and live_attack.get_theme_font_size("font_size") == 27, "the presenter reapplies wide-region command scale to the existing battle component instead of rebuilding and resetting it"); live_presenter.present(null); live_presenter.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame
	var inspection_panel := component.find_child("BattleCombatantInspection", true, false) as Control
	assert_true(component.open_combatant_inspection("monster") and inspection_panel.visible and not (component.find_child("BattleOverview", true, false) as Control).visible and (component.find_child("BattleInspectionAttacks", true, false) as Button).button_pressed and (component.find_child("BattleInspectionContent", true, false) as Label).text == "Attack 1 • 1–4 damage", "Ctrl-click inspection can replace the command overview with the selected combatant's detached attack rows")
	(component.find_child("BattleInspectionItems", true, false) as Button).pressed.emit(); assert_equal((component.find_child("BattleInspectionContent", true, false) as Label).text, "Short Sword • Equipped", "battle inspection exposes the selected combatant's player-visible item rows")
	(component.find_child("BattleInspectionConditions", true, false) as Button).pressed.emit(); assert_equal((component.find_child("BattleInspectionContent", true, false) as Label).text, "None", "battle inspection keeps an explicit empty condition record")
	var inspection_back := _buttons_in(inspection_panel).filter(func(button: Button) -> bool: return button.text == "Back to battle")[0] as Button; inspection_back.pressed.emit(); assert_true((component.find_child("BattleOverview", true, false) as Control).visible and not inspection_panel.visible and submitted_bodies.is_empty(), "inspection Back restores battle commands without submitting or mutating a combat action")
	assert_true(component.open_combatant_inspection("hero"), "the inspection surface accepts a party combatant selected from the battlefield"); (component.find_child("BattleInspectionConditions", true, false) as Button).pressed.emit(); assert_equal((component.find_child("BattleInspectionContent", true, false) as Label).text, "Blessed", "the same read-only inspection surface works for party combatants")
	assert_false(component.open_combatant_inspection("missing"), "an unknown battlefield identity cannot reopen a stale combatant record")
	component.free()
func _test_battle_typed_option_contracts() -> void:
	var request := _fixture_request("battle.staged-spell", InteractionRequest.COMBAT, {"actions": ["cast_spell", "use_item", "use_scroll"], "spellCasts": [{"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 1, "cost": 2, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 1, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, 0]], "areaRotationOffsets": [[[0, 0]], [[0, 0], [0, 1]], [[0, 0], [1, 0]], [[-1, 0], [0, 0]]], "legalTargetCoordinates": []}, {"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 2, "cost": 4, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 2, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, 0], [0, 1]], "legalTargetCoordinates": []}], "spellCastReason": "", "fastSpells": [{"slot": 0, "spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 1, "enabled": true, "reason": ""}], "itemCasts": [{"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": 1, "targetId": "", "targetName": "Choose battlefield point", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "area", "areaShape": 1, "defaultTargetCoordinate": [45, 45], "areaOffsets": [[0, 0]], "areaRotationOffsets": [[[0, 0]], [[0, 0], [1, 0]]], "legalTargetCoordinates": [], "itemInstanceId": "item.brimstones", "itemId": "classic.item.1", "itemName": "Brimstone Wand", "charges": 3}], "scrollCasts": [], "itemCastReason": "", "scrollCastReason": "No legal scroll."})
	var component := BattleInteraction.new(); component.theme = load("res://src/presentation/classic_ui_theme.tres"); component.build(request)
	var opened := {"actor": "", "options": []}; var target_requests: Array[CombatTargetingRequest] = []; component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: opened["actor"] = actor_id; opened["options"] = options); component.combat_targeting_requested.connect(func(targeting: CombatTargetingRequest) -> void: target_requests.append(targeting))
	(component.find_child("CombatCommandSpells", true, false) as Button).pressed.emit()
	var opened_options: Array[InteractionRequestValue.CastOption] = []; opened_options.assign(opened["options"])
	assert_true(opened_options.size() == 2 and component.find_child("CombatSpellPicker", true, false) == null, "combat casting opens the dedicated spellbook contract instead of generic dropdown controls"); var spell_definition := SpellDefinition.new("classic.spell.1306", 1306, "Brimstones", "Burning stones strike a fixed battlefield area."); spell_definition.in_combat = true; spell_definition.range_min = 1; spell_definition.range_max = 2; spell_definition.damage_min = 2; spell_definition.damage_max = 6; spell_definition.power_damage_min = 1; spell_definition.power_damage_max = 2; spell_definition.duration_min = 1; spell_definition.duration_max = 3; spell_definition.damage_type = 2; var summon_definition := SpellDefinition.new("classic.spell.3502", 3502, "Creature Summon 4", "Summons more powerful creatures."); summon_definition.in_combat = true; var actor_state := CharacterState.new(String(opened["actor"]), "Hero", 10, 10); actor_state.spell_points = 8; actor_state.maximum_spell_points = 12; var actor_view := CharacterView.new(actor_state); var summon_view := SpellView.new(summon_definition); summon_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", false, "This Classic summoning family is not executable for combat character yet (special 58, target type 0)."); actor_view.spells = [SpellView.new(spell_definition), summon_view]
	var spellbook_view := GameView.new(1, true, null); spellbook_view.party_members = [actor_view]
	for power: int in range(3, 8): opened_options.append(InteractionRequestValue.cast_option({"spellId": "classic.spell.1306", "spellName": "Brimstones", "power": power, "cost": power * 2, "targetId": "", "targetName": "All enemies", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "automatic"}, &"spell"))
	var roster := load("res://src/presentation/screens/classic_party_roster.tscn").instantiate() as ClassicPartyRoster; roster.theme = load("res://src/presentation/classic_ui_theme.tres"); roster.size = Vector2(350.0, 560.0); roster.present(spellbook_view); roster.present_combat_spellbook(String(opened["actor"]), opened_options); var spellbook_labels := _labels_in(roster)
	assert_true(roster.find_child("CombatSpellLevels", true, false) != null and roster.find_child("CombatSpellList", true, false) != null and roster.find_child("CombatSpellPowerChoices", true, false) != null and roster.find_child("CombatSpellDetails", true, false) != null and (roster.find_child("CombatSpellbookSelector", true, false) as Control).size_flags_vertical == Control.SIZE_EXPAND_FILL and (roster.find_child("PartyScroll", true, false) as ScrollContainer).vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and (roster.find_child("CombatSpellbookActions", true, false) as Control).get_parent().name == "SpellbookFooter" and (roster.find_child("CombatSpellDetails", true, false) as Control).get_parent().name == "CombatSpellRecords" and (roster.find_child("CombatSpellPowerChoices", true, false) as Control).get_parent().name == "CombatSpellRecords" and (roster.find_child("CombatSpellPowerChoices", true, false) as Control).get_combined_minimum_size().x <= 250.0 and roster.find_child("CombatSpellPower7", true, false) != null and (roster.find_child("CombatSpellList", true, false) as Control).get_child_count() == 1 and roster.get_combined_minimum_size().y <= roster.size.y and spellbook_labels.has("Burning stones strike a fixed battlefield area.") and spellbook_labels.any(func(text: String) -> bool: return text.contains("Cost 2 SP") and text.contains("SP 8/12")), "the spellbook keeps all seven legal powers, dense list, compact record, and fixed actions inside the canonical rail without scrolling")
	var level_five := roster.find_child("SpellLevel5", true, false) as Button; level_five.pressed.emit(); var summon_row := roster.find_child("CombatSpellclassic_spell_3502", true, false) as Button; summon_row.pressed.emit(); assert_true(summon_row.text.contains("Creature Summon 4") and summon_row.text.contains("Unavailable") and not summon_row.disabled and (roster.find_child("CombatSpellAim", true, false) as Button).disabled and _labels_in(roster).any(func(text: String) -> bool: return text.contains("special 58, target type 0")), "known combat spells remain visible and expose the detached exact reason when the tactical resolver cannot supply a legal CastOption")
	(roster.find_child("SpellLevel3", true, false) as Button).pressed.emit()
	var selected := {"option": null}; roster.combat_spell_cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: selected["option"] = option); (roster.find_child("CombatSpellAim", true, false) as Button).pressed.emit()
	component.cast_spell_option(selected["option"] as InteractionRequestValue.CastOption)
	assert_true(component.find_child("ConfirmBattleTarget", true, false).visible and component.find_child("RotateBattleTarget", true, false).visible and target_requests[-1].supports_rotation() and component.get_combined_minimum_size().y <= 190.0, "spellbook selection enters rotatable battlefield targeting while its controls remain inside the canonical combat region"); component.battlefield_targeting_cancelled(); (component.find_child("CombatCommandItems", true, false) as Button).pressed.emit(); (component.find_child("ChooseItemTarget", true, false) as Button).pressed.emit(); assert_true(target_requests[-1].response_body.action == &"use_item" and target_requests[-1].supports_rotation(), "a spatial charged item uses the same authoritative area and rotation targeting contract instead of being forced through combatant selection"); var fast_component := BattleInteraction.new(); fast_component.theme = load("res://src/presentation/classic_ui_theme.tres"); fast_component.build(request); assert_true(fast_component.handle_fast_spell(0, true) and not (fast_component.find_child("BattleOverview", true, false) as Control).visible and (fast_component.find_child("ConfirmBattleTarget", true, false) as Button).text == "Cast spell" and (fast_component.find_child("ConfirmBattleTarget", true, false) as Control).get_parent().get_parent().visible, "Fast Spells reveal the ordinary targeting controls instead of mounting Cast inside a hidden spell panel"); fast_component.free()
	for label: String in ["Scrolls"]: var buttons := _buttons_in(component).filter(func(button: Button) -> bool: return button.text == label); assert_true(buttons.size() == 1 and buttons[0].disabled, "%s has one typed control disabled by core availability" % label)
	roster.free(); component.free()
func _test_shop_component() -> void:
	var request := _fixture_request("shop.fixture", InteractionRequest.SHOP, {
		"partyGold": 19,
		"inflationPercent": 125,
		"identifyPrice": 20,
		"characters": [{"id": "character.one", "name": "Hero", "portraitId": "portrait.fixture", "load": 120, "maximumLoad": 800, "inventory": [
			{"instanceId": "item.unknown", "itemId": "classic.item.40", "name": "Runed wand", "sellPrice": 0, "identified": false, "equipped": false, "charges": 2, "canSell": true, "sellReason": "", "canIdentify": false, "identifyReason": "Identification costs 20 gold.", "description": "Its markings cannot yet be read.", "weight": 20, "facts": [{"label": "Weight", "value": "20"}], "iconResourceType": "cicn", "iconId": 35},
			{"instanceId": "item.equipped", "itemId": "classic.item.1", "name": "Sword", "sellPrice": 25, "identified": true, "equipped": true, "charges": -1, "canSell": false, "sellReason": "Unequip this item before selling it.", "canIdentify": false, "identifyReason": "This item is already identified.", "iconResourceType": "cicn", "iconId": 20},
		]}],
		"stock": [{"stockKey": "base:0", "index": 0, "itemId": "classic.item.5", "name": "Dagger", "buyPrice": 40, "quantity": 1, "canBuy": false, "buyReason": "The party cannot afford this item.", "category": "weapons", "description": "A short blade suited to close work.", "weight": 40, "facts": [{"label": "Damage", "value": "1–4"}], "iconResourceType": "cicn", "iconId": 5}, {"stockKey": "base:200", "index": 200, "itemId": "classic.item.6", "name": "Leather Armor", "buyPrice": 10, "quantity": 1, "canBuy": true, "buyReason": "", "category": "armor", "description": "Flexible leather protection.", "weight": 100, "facts": [{"label": "Armor", "value": "+2"}], "iconResourceType": "cicn", "iconId": 5}],
	})
	var component := ShopInteraction.new(); var responses: Array[InteractionResponse.ShopBody] = []; component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: responses.append(body as InteractionResponse.ShopBody)); component.configure(ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()), false)
	component.build(request); var footer := component.find_child("ShopControls", true, false) as HBoxContainer; var left_controls := component.find_child("ShopLeftControls", true, false) as HBoxContainer; var portrait_selector := component.find_child("ShopperPortraitSelector", true, false) as PanelContainer; var right_controls := component.find_child("ShopRightControls", true, false) as HBoxContainer; assert_true(footer != null and [left_controls.get_parent(), portrait_selector.get_parent(), right_controls.get_parent()].all(func(parent: Node) -> bool: return parent == footer) and [left_controls.get_index(), portrait_selector.get_index(), right_controls.get_index()] == [0, 1, 2] and left_controls.size_flags_horizontal == Control.SIZE_EXPAND_FILL and right_controls.size_flags_horizontal == Control.SIZE_EXPAND_FILL and is_equal_approx(left_controls.size_flags_stretch_ratio, right_controls.size_flags_stretch_ratio), "the shopper portrait matrix sits between equal expanding footer regions so its centerline matches the middle filter divider")
	var ledgers := component.find_child("ShopExchangeLedgers", true, false); var inventory_scroll := component.find_child("InventoryScroll", true, false) as ScrollContainer; var stock_scroll := component.find_child("ShopStockScroll", true, false) as ScrollContainer; assert_true(component.find_child("ShopHeader", true, false) != null and ledgers != null and component.find_child("SelectedInventoryColumn", true, false).get_index() < component.find_child("ShopExchangeDivider", true, false).get_index() and component.find_child("ShopExchangeDivider", true, false).get_index() < component.find_child("ShopStockColumn", true, false).get_index() and component.find_child("ShopControlSpine", true, false) != null and component.find_child("ShopExchangeDivider", true, false).custom_minimum_size.x == 68.0 and component.find_child("ShopControlStrip", true, false).custom_minimum_size.y == 68.0 and component.find_child("ShopDetailStrip", true, false).custom_minimum_size.y == 82.0 and ["ShopLeftLoadPanel", "ShopSelectedShopperPanel", "ShopTransactionContainer", "ShopRouteControls", "ShopRightLoadPanel", "ShopKeeperRestore", "ShopItems", "ShopMoney", "ShopDone", "ShopItemDescription", "ShopItemStats"].all(func(name: String) -> bool: return component.find_child(name, true, false) != null) and [["ShopKeeperRestore", &"command.shop_original"], ["ShopItems", &"command.inventory"], ["ShopMoney", &"command.money"]].all(func(spec: Array) -> bool: var button := component.find_child(spec[0], true, false) as ClassicBitmapButton; return button != null and button.has_visual_art() and button.visual_asset_id == spec[1] and button.custom_minimum_size == Vector2(54.0, 54.0) and button.size_flags_vertical == Control.SIZE_SHRINK_CENTER) and component.find_children("ShopBuyer_*", "Button", true, false).size() == 1 and component.find_children("ShopSeller_*", "Button", true, false).size() == 1 and (component.find_children("ShopBuyer_*", "Button", true, false)[0] as Button).custom_minimum_size == Vector2(18.0, 18.0) and [inventory_scroll.custom_minimum_size.y, stock_scroll.custom_minimum_size.y] == [322.0, 322.0] and inventory_scroll.size_flags_vertical == Control.SIZE_EXPAND_FILL and stock_scroll.size_flags_vertical == Control.SIZE_EXPAND_FILL and component.find_children("*", "ScrollContainer", true, false).size() == 2 and component.size_flags_vertical == Control.SIZE_EXPAND_FILL and (ledgers as HBoxContainer).size_flags_vertical == Control.SIZE_EXPAND_FILL and component.get_combined_minimum_size().y <= 600.0 and InteractionLayoutPolicyScript.interaction_vertical_scroll_mode(request) == ScrollContainer.SCROLL_MODE_DISABLED, "shop gives surplus height only to the ledgers, keeps its compact controls and detail wells bottom-aligned, and preserves square icon routes while only its inventories scroll"); var compact_shop := ShopInteraction.new(); compact_shop.configure(ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()), true); compact_shop.build(request); var compact_routes := [compact_shop.find_child("ShopKeeperRestore", true, false), compact_shop.find_child("ShopItems", true, false), compact_shop.find_child("ShopMoney", true, false)]; assert_true([(compact_shop.find_child("InventoryScroll", true, false) as ScrollContainer).custom_minimum_size.y, (compact_shop.find_child("ShopStockScroll", true, false) as ScrollContainer).custom_minimum_size.y] == [158.0, 158.0] and compact_routes.all(func(button: Control) -> bool: return button.custom_minimum_size == Vector2(46.0, 46.0)) and (compact_shop.find_children("ShopBuyer_*", "Button", true, false)[0] as Button).custom_minimum_size == Vector2(16.0, 16.0) and compact_shop.get_combined_minimum_size().x <= 780.0 and compact_shop.get_combined_minimum_size().y <= 536.0, "the optional compact Shop keeps five visible ledger rows, square compact routes, and every lower strip inside 800x600 while only its inventories scroll"); compact_shop.free(); assert_true(component.find_child("StockIcon_base_0", true, false).find_child("ContentImage", true, false) != null and component.find_child("InventoryIcon_item_unknown", true, false).find_child("ContentImage", true, false) != null and ["weapons", "armor", "limb_armor", "magic", "supplies"].all(func(id: String) -> bool: var button := component.find_child("ShopFilter_%s" % id, true, false) as ClassicBitmapButton; return button != null and button.has_visual_art() and button.visual_asset_id == StringName("inventory.category.%s" % id) and button.custom_minimum_size == Vector2(62.0, 58.0)) and [component.find_child("Stock_base_0", true, false), component.find_child("Inventory_item_unknown", true, false)].all(func(button: Button) -> bool: return button.theme_type_variation == &"ClassicItemLedgerButton" and not button.button_pressed), "shop rows stay unselected on the white ledger while all five narrow divider filters bind cropped native application art inside their caption stages")
	var buy_button := component.find_child("ShopBuy", true, false) as Button; var shop_popover := component.find_child("ClassicItemDetailPopover", true, false); shop_popover.set("modifier_active", true); (component.find_child("Stock_base_0", true, false) as Button).mouse_entered.emit(); assert_true((shop_popover.find_child("ClassicItemDetailPanel", true, false) as PanelContainer).visible and (shop_popover.find_child("ClassicItemDetailTitle", true, false) as Label).text == "Dagger", "Alt-hover presents the selected stock's detached facts in a floating pointer-transparent detail pane without expanding the Shop"); shop_popover.set("modifier_active", false); assert_true(buy_button.disabled and buy_button.tooltip_text.contains("Select shop stock"), "shop opens without inventing a selected first item"); (component.find_child("Stock_base_0", true, false) as Button).pressed.emit(); assert_true(buy_button.disabled and buy_button.tooltip_text.contains("afford"), "selected unaffordable stock exposes its core-owned reason")
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
	(component.find_children("ShopSeller_*", "Button", true, false)[0] as Button).pressed.emit(); assert_true((component.find_child("ShopStockHeading", true, false) as Label).text == "Hero's Pack" and component.find_child("RightInventory_item_unknown", true, false) != null, "the right shopper selector replaces stock with that adventurer's pack"); (component.find_child("ShopKeeperRestore", true, false) as BaseButton).pressed.emit(); var armor_filter := component.find_child("ShopFilter_armor", true, false) as ClassicBitmapButton; armor_filter.command_requested.emit(&"shop.category.armor"); var shop_ledger := component.find_child("ShopStockColumn", true, false); var pack_ledger := component.find_child("SelectedInventoryColumn", true, false); pack_ledger.call("_drop_data", Vector2.ZERO, {"kind": &"shop-stock-item", "sourceId": "shop", "stockKey": "base:200"}); shop_ledger.call("_drop_data", Vector2.ZERO, {"kind": &"shop-inventory-item", "sourceId": "character.one", "instanceId": "item.unknown"}); assert_equal([responses[0].action, responses[0].character_id, responses[0].stock_key, responses[1].action, responses[1].instance_id], [&"buy", "character.one", "base:200", &"sell", "item.unknown"], "Shop Keeper restores stock and dragging either direction submits the exact typed Buy and Sell responses"); component.free()


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
	router.presentation_sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: sounds.append({"soundId": sound_id, "waitForCompletion": wait_for_completion, "stopExisting": stop_existing, "reducedSoundEligible": reduced_sound_eligible}))
	router.open_screen(&"inventory"); router.open_screen(&"inventory"); router.open_screen(&"exploration"); router.open_screen(&"spells"); router.open_screen(&"exploration"); router.open_screen(&"inventory", false); router.open_screen(&"exploration", false)
	router.open_screen(&"services"); router.open_screen(&"services"); router.open_screen(&"exploration")
	assert_equal(sounds, [{"soundId": 20001, "waitForCompletion": false, "stopExisting": false, "reducedSoundEligible": true}, {"soundId": 20002, "waitForCompletion": false, "stopExisting": false, "reducedSoundEligible": true}, {"soundId": 141, "waitForCompletion": false, "stopExisting": false, "reducedSoundEligible": false}, {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "reducedSoundEligible": true}, {"soundId": 141, "waitForCompletion": false, "stopExisting": false, "reducedSoundEligible": false}], "explicit Items, Spells, and Swap opening ambience is Reduced Sound eligible while action/Done sound 141 remains audible")
	view.pending_interaction = _fixture_request("shop.audio", InteractionRequest.SHOP)
	router.present(view)
	router.open_screen(&"services")
	assert_equal(sounds.size(), 5, "a Services route opened for a typed location service does not masquerade as ordinary Swap")
	var audio := ClassicAudioPresenter.new()
	var observed: Array[int] = []
	audio.sound_observed.connect(func(sound_id: int) -> void: observed.append(sound_id))
	audio.set_reduced_sound(true)
	audio.present_sound(3003, null, false, true, true)
	assert_equal([audio.last_sound_id, observed], [0, []], "Reduced Sound suppresses eligible modal ambience before it stops channels or reaches the media path")
	audio.present_sound(141, null, false, false, false)
	assert_equal([audio.last_sound_id, observed], [141, [141]], "Reduced Sound retains action and Done cues that Castle does not gate")
	audio.set_reduced_sound(false); audio.present_sound(3003, null, false, true, true); assert_equal([audio.last_sound_id, observed], [3003, [141, 3003]], "disabling Reduced Sound restores the same explicit workspace audio path")
	audio.free()
	router.free()


func _test_route_catalog() -> void:
	assert_equal(UiRouteCatalog.ROUTES.size(), 11, "the canonical route registry contains the eleven implemented workspaces")
	var ids: Dictionary = {}
	var shortcuts: Dictionary = {}
	var primary_count: int = 0
	for route: Dictionary in UiRouteCatalog.ROUTES:
		ids[route["id"]] = true
		shortcuts[route["shortcut"]] = true
		primary_count += 1 if bool(route["primary"]) else 0
		assert_false(String(route.get("description", "")).is_empty(), "every route has presentation guidance")
		assert_true(ResourceLoader.exists(String(route.get("scene", "")), "PackedScene"), "every route owns a scene-backed workspace")
	assert_equal(ids.size(), 11, "route identifiers are unique")
	assert_equal(shortcuts.size(), 10, "route shortcuts are unique except for the two intentionally shortcut-free Allies menu workspaces")
	assert_equal(primary_count, 6, "both supported layout compositions keep six primary workspaces")


func _test_layout_profiles() -> void:
	assert_equal(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.COMPACT, "800x600 uses compact layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1280x720 uses wide layout")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_125), 1.25, "explicit interface density is independent of viewport")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_150), 1.5, "150 percent interface density is supported")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(compact.party_width, 208.0, "compact Classic roster uses the specified width")
	assert_equal(compact.bottom_height, 156.0, "compact Classic textbox uses the specified height"); assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).party_width, 352.0, "canonical widescreen reserves enough width for complete party records"); var full_hd := UiLayoutProfile.for_viewport(Vector2(1920, 1080), PresentationSettings.UI_SCALE_AUTO); assert_equal([full_hd.id, full_hd.ui_scale, full_hd.application_rect], [UiLayoutProfile.WIDE, 1.5, Rect2(0, 0, 1920, 1080)], "Fit uses the complete 16:9 Full HD window at one-and-a-half layout density"); var ultrawide := UiLayoutProfile.for_viewport(Vector2(3440, 1440), PresentationSettings.UI_SCALE_AUTO)
	assert_equal([ultrawide.ui_scale, ultrawide.bitmap_scale, ultrawide.application_rect], [2.0, 2, Rect2(440, 0, 2560, 1440)], "Fit centers one bounded 16:9 application canvas on ultrawide while keeping imported art at exact 2x pixels"); var four_k := UiLayoutProfile.for_viewport(Vector2(3840, 2160), PresentationSettings.UI_SCALE_AUTO); assert_equal([four_k.ui_scale, four_k.bitmap_scale, four_k.application_rect], [3.0, 2, Rect2(0, 0, 3840, 2160)], "4K scales layout geometry to 3x without stretching legacy bitmap art beyond 2x"); assert_equal(UiLayoutProfile.application_rect_for(Vector2(800, 600)), Rect2(0, 0, 800, 600), "the optional 800x600 Classic composition retains its complete 4:3 canvas"); var offset_spell_rect := ClassicScreenRouter.spell_workspace_rect_for(ultrawide, ultrawide.application_rect.size, ultrawide.application_rect.position); assert_equal(offset_spell_rect.position.x, 2160.0, "the wider spell sidebar inherits the bounded canvas origin")
func _test_settings_schema_and_migration() -> void:
	var settings := PresentationSettings.new(); settings.ui_scale_mode = PresentationSettings.UI_SCALE_125; settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.text_scale = 1.5; settings.auto_switch_to_melee = false; settings.exploration_speed_percent = 250; settings.combat_playback_speed_percent = 50
	settings.show_exploration_minimap = true; settings.classic_exploration_visibility = false; settings.autojournal_enabled = false; settings.typography_mode = PresentationSettings.TYPOGRAPHY_READABLE; settings.reduced_sound = true; settings.last_campaign_id = "scenario.fixture"
	var restored := PresentationSettings.from_data(settings.to_data()); assert_not_null(restored, "schema-twelve presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately"); assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent"); assert_false(restored.auto_switch_to_melee, "Auto Weapon Switch persists as an application preference rather than battle state")
	assert_equal([restored.exploration_speed_percent, restored.combat_playback_speed_percent], [250, 50], "exploration and combat visual speeds persist independently of simulation state")
	assert_equal([restored.show_exploration_minimap, restored.classic_exploration_visibility, restored.autojournal_enabled, restored.typography_mode, restored.reduced_sound], [true, false, false, PresentationSettings.TYPOGRAPHY_READABLE, true], "travel preview, Classic-distance fog, Auto Note, typography, and Reduced Sound persist as presentation preferences")
	assert_equal(restored.last_campaign_id, "scenario.fixture", "the last successfully started campaign persists by stable identity rather than install path")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true}); assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density"); assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")
	assert_true(version_two.auto_switch_to_melee, "legacy settings inherit Castle's bundled default-on Auto Weapon Switch preference")
	var version_three := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 3, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_150, "windowMode": PresentationSettings.WINDOWED}); assert_not_null(version_three, "schema-three settings migrate")
	assert_equal([version_three.ui_scale_mode, version_three.auto_switch_to_melee], [PresentationSettings.UI_SCALE_150, true], "schema-three settings preserve prior display fields and inherit Castle's default-on preference")
	var version_four := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 4, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": false}); assert_not_null(version_four, "schema-four settings migrate")
	assert_equal(version_four.exploration_speed_percent, 100, "older settings inherit the stable exploration cadence")
	var version_five := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 5, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200}); assert_equal([version_five.show_exploration_minimap, version_five.autojournal_enabled], [false, false], "schema-five settings migrate to a hidden modern travel aid and Castle's PRFN default-off Auto Note preference")
	var version_six := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 6, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200, "showExplorationMinimap": false, "autojournalEnabled": true}); assert_equal(version_six.typography_mode, PresentationSettings.TYPOGRAPHY_CLASSIC, "existing settings migrate to the Classic typography default")
	var version_seven := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 7, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": false, "uiScaleMode": PresentationSettings.UI_SCALE_100, "windowMode": PresentationSettings.WINDOWED, "autoSwitchToMelee": true, "explorationSpeedPercent": 200, "showExplorationMinimap": false, "autojournalEnabled": true, "typographyMode": PresentationSettings.TYPOGRAPHY_CLASSIC}); assert_equal([version_seven.sound_volume, version_seven.music_volume, version_seven.music_enabled, version_seven.classic_exploration_visibility, version_seven.reduced_sound], [1.0, 0.8, true, true, false], "schema-seven settings migrate to independent audio, Classic exploration visibility, and full modal sound")
	var version_eleven_data := settings.to_data(); version_eleven_data["schemaVersion"] = 11; version_eleven_data.erase("lastCampaignId"); var version_eleven := PresentationSettings.from_data(version_eleven_data); assert_true(version_eleven != null and version_eleven.last_campaign_id.is_empty(), "schema-eleven settings migrate to no campaign prewarm")
	var malformed_current := settings.to_data()
	malformed_current["lastCampaignId"] = 14
	assert_equal(PresentationSettings.from_data(malformed_current), null, "current settings reject a non-string campaign identity")
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
		if pulses.is_empty(): OS.delay_msec(220)
		pulses.append(direction)
		held.advance(1.0)
	)
	held.set_speed_percent(400)
	held.start(&"keyboard", Vector2i.RIGHT)
	assert_equal(pulses, [Vector2i.RIGHT], "the first held movement step is immediate")
	assert_equal(held.active_source(), &"keyboard", "the scheduler exposes its presentation-owned input source")
	held.advance(0.149); assert_equal(pulses.size(), 1, "an ordinary click cannot cross the initial held-repeat threshold")
	held.advance(0.002); assert_equal(pulses.size(), 2, "a deliberate hold begins repeating after 150 milliseconds")
	held.advance(0.011); held.advance(0.002); assert_equal(pulses.size(), 3, "subsequent held steps use the selected 12.5 millisecond cadence")
	held.advance(1.0); assert_equal(pulses.size(), 4, "a slow frame emits one step rather than a queued burst"); held.update(&"keyboard", Vector2i.LEFT); assert_equal(pulses, [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.LEFT], "changing held direction requests the new direction immediately without a release")
	assert_false(held.request_in_progress(), "a synchronous movement callback settles before the next interval begins")
	held.set_speed_percent(25)
	assert_equal(held.interval_seconds(), 0.2, "the slowest movement setting uses the documented 200 millisecond interval"); held.set_speed_percent(100)
	assert_equal(held.interval_seconds(), 0.05, "the default movement setting sustains twenty scheduled steps per second")
	held.stop(&"keyboard")
	held.advance(1.0)
	assert_equal(pulses.size(), 5, "release stops further held movement")
	held.free()


func _test_fast_spell_input() -> void:
	var one := InputEventKey.new(); one.physical_keycode = KEY_1; one.pressed = true; assert_equal(UiInputActions.fast_spell_slot(one), 0, "top-row 1 selects Castle Fast Spell slot one")
	var zero := InputEventKey.new(); zero.physical_keycode = KEY_0; zero.pressed = true; assert_equal(UiInputActions.fast_spell_slot(zero), 9, "top-row 0 selects Castle Fast Spell slot ten")
	zero.ctrl_pressed = true; assert_true(UiInputActions.fast_spell_use_requested(zero), "Ctrl-number is the Windows equivalent of Castle Command-number activation")
	var alt_one := InputEventKey.new(); alt_one.physical_keycode = KEY_1; alt_one.pressed = true; alt_one.alt_pressed = true; assert_equal([UiInputActions.fast_spell_slot(alt_one), UiInputActions.fast_spell_slot(alt_one, true), UiInputActions.combat_fast_spell_use_requested(alt_one)], [-1, 0, true], "Alt-number remains route-owned outside battle and activates the matching battle Fast Spell while the dock modifier is held")
	var keypad := InputEventKey.new(); keypad.physical_keycode = KEY_KP_1; keypad.pressed = true
	assert_equal(UiInputActions.fast_spell_slot(keypad), -1, "numeric keypad movement never aliases a top-row Fast Spell")
	var released := InputEventKey.new(); released.physical_keycode = KEY_2
	assert_equal(UiInputActions.fast_spell_slot(released), -1, "a key release cannot display or activate a Fast Spell a second time")
	var route_binding: Dictionary = UiInputActions.DEFINITIONS.filter(func(definition: Dictionary) -> bool: return definition["id"] == &"ui_screen_explore")[0]; assert_true(bool(route_binding.get("alt", false)) and UiInputActions.DEFINITIONS.any(func(definition: Dictionary) -> bool: return definition["id"] == &"realmz_target" and KEY_T in definition["keys"]) and UiInputActions.DEFINITIONS.any(func(definition: Dictionary) -> bool: return definition["id"] == &"realmz_confirm_target" and KEY_SPACE in definition["keys"]), "route shortcuts remain behind Alt-number while T and Space own Classic combat targeting and confirmation")
	var keypad_bindings: Dictionary = {}
	for definition: Dictionary in UiInputActions.DEFINITIONS:
		keypad_bindings[definition["id"]] = definition["keys"]
	assert_true(KEY_KP_7 in keypad_bindings[&"realmz_move_up_left"], "keypad 7 owns northwest land movement")
	assert_true(KEY_KP_9 in keypad_bindings[&"realmz_move_up_right"], "keypad 9 owns northeast land movement")
	assert_true(KEY_KP_1 in keypad_bindings[&"realmz_move_down_left"], "keypad 1 owns southwest land movement")
	assert_true(KEY_KP_3 in keypad_bindings[&"realmz_move_down_right"], "keypad 3 owns southeast land movement")
	var spell_definition := SpellDefinition.new("classic.spell.1101", 1101, "Discover Magic", "Reveals magic."); assert_equal(SpellView.new(spell_definition).animation_resource_ids, [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039], "ordinary spell views expose Castle's exact eight-frame effect identity for transient Fast Spell previews")
	var bindings: Array[InteractionRequestValue.FastSpell] = [InteractionRequestValue.fast_spell({"slot": 0, "spellId": "classic.spell.1101", "spellName": "Discover Magic", "power": 1, "enabled": true, "reason": ""}), InteractionRequestValue.fast_spell({"slot": 1, "spellId": "classic.spell.1102", "spellName": "Flame Hands", "power": 2, "enabled": false, "reason": "Not enough spell points."})]
	var image := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8); image.fill(Color.WHITE); var preview_frames: Array[Texture2D] = []; for _frame: int in 8: preview_frames.append(ImageTexture.create_from_image(image))
	var dock := FastSpellDockScript.new(); dock.configure(bindings, {"classic.spell.1101": preview_frames}); var stage := Rect2(8.0, 28.0, 984.0, 502.0); dock.set_stage_rect(stage); var activated_slots: Array[int] = []; dock.slot_activated.connect(func(slot_index: int) -> void: activated_slots.append(slot_index))
	assert_true(dock.set_held(true) and dock.visible and dock.position.y >= stage.end.y - 84.0 and dock.position.x >= stage.position.x and dock.position.x + dock.size.x <= stage.end.x, "holding Alt opens one bounded Fast Spell dock over the bottom of the battle canvas")
	var dock_buttons := _buttons_in(dock)
	assert_true(dock_buttons.size() == 2 and not dock_buttons[0].disabled and dock_buttons[1].disabled and dock_buttons[1].tooltip_text.contains("Not enough spell points"), "the dock keeps assigned slot order and visibly preserves authoritative per-cast availability")
	dock_buttons[0].pressed.emit(); assert_equal(activated_slots, [0], "clicking an enabled animation preview activates its ordinary Fast Spell slot")
	dock.set_held(false); assert_false(dock.visible, "releasing Alt removes the transient battle-canvas overlay"); dock.free(); bindings[0].enabled = false; var disabled_dock := FastSpellDockScript.new(); disabled_dock.configure(bindings, {}); disabled_dock.set_stage_rect(stage); assert_true(disabled_dock.set_held(true) and disabled_dock.visible, "Alt still opens assigned Fast Spells when every binding is currently unavailable so their reasons remain discoverable"); disabled_dock.free()


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
	second_item.mouse_entered.emit(); var treasure_popover := ordinary_component.find_child("ClassicItemDetailPopover", true, false); treasure_popover.set("modifier_active", true); assert_true(loot_grid.columns == 16 and loot_grid.get_child_count() == 24 and (ordinary_component.find_child("TreasureHoverCircle_reward_item_2", true, false) as TextureRect).visible and ordinary_component.find_child("TreasureMagicGlow_reward_item_2", true, false) == null and ordinary_component.preferred_initial_focus() == ordinary_component.find_child("TreasureRecipient_hero-0", true, false) and (ordinary_component.find_child("TreasureHoverCircle_reward_item_1", true, false) as TextureRect).visible == false and (ordinary_component.find_child("TreasureSelectedItemName", true, false) as Label).text == "Fixture Wand 2" and ordinary_component.find_child("TreasureItemIdentity", true, false) != null and ordinary_component.find_child("TreasureItemProperties", true, false) != null and ordinary_component.find_child("TreasureCommandPanel", true, false) != null and (ordinary_component.find_child("TreasurePooledWealth", true, false) as Label).text.contains("Gold 125") and (treasure_popover.find_child("ClassicItemDetailPanel", true, false) as PanelContainer).visible and (treasure_popover.find_child("ClassicItemDetailTitle", true, false) as Label).text == "Fixture Wand 2", "ordinary booty uses the wide Classic field, gives initial focus to the selected recipient without falsely circling the first item, and retains hover, nonmagical presentation, floating Alt-detail, selected-record, and denomination details")
	assert_true(_buttons_in(ordinary_component).any(func(button: Button) -> bool: return button.name == "TreasureRecipient_hero-0" and button.button_pressed and button.text.contains("Items") and button.text.contains("Move") and button.text.contains("Load")), "ordinary booty keeps one rules-owned recipient selected with its Classic carrying facts")
	assert_true(_buttons_in(ordinary_component).any(func(button: Button) -> bool: return button.name == "TreasureDone"), "ordinary booty has one typed completion path")
	ordinary_component.free()
	var capacity_component := TreasureDistributionInteraction.new(); capacity_component.configure(item_media, null, false)
	capacity_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unavailable"))
	assert_true(_buttons_in(capacity_component).any(func(button: Button) -> bool: return button.name == "TreasureRecipient_hero-0" and button.disabled and button.tooltip_text.contains("full")), "capacity-blocked booty retains the core-provided disabled reason")
	capacity_component.free(); assert_equal([ClassicTreasureTakeEffect.frame_radii(0), ClassicTreasureTakeEffect.frame_radii(23)], [Vector2(15.0, 23.0), Vector2(38.0, 0.0)], "Treasure pickup ports Castle's exact 24-step expanding color oval and contracting white oval geometry"); var unidentified_component := TreasureDistributionInteraction.new(); unidentified_component.configure(item_media, null, false); unidentified_component.build(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified")); var unidentified_name := unidentified_component.find_child("TreasureSelectedItemName", true, false) as Label; var detected_magic_glow := unidentified_component.find_child("TreasureMagicGlow_reward_item_1", true, false) as TextureRect; var detected_magic_icon := unidentified_component.find_child("TreasureLootIcon_reward_item_1", true, false) as TextureRect; var detect_picker := unidentified_component.find_child("TreasureDetectMagicCaster", true, false) as OptionButton; var identify_picker := unidentified_component.find_child("TreasureIdentifyCaster", true, false) as OptionButton; var hidden_popover := unidentified_component.find_child("ClassicItemDetailPopover", true, false); hidden_popover.set("modifier_active", true); (unidentified_component.find_child("TreasureItem_reward_item_1", true, false) as Button).mouse_entered.emit(); assert_true(unidentified_name.theme_type_variation == &"ClassicUnidentifiedItem" and not unidentified_name.has_theme_color_override("font_color") and detected_magic_glow != null and detected_magic_glow.texture == ClassicUiAssetCatalog.texture(&"loot.item.glow") and detected_magic_icon.custom_minimum_size == Vector2(32.0, 32.0) and detect_picker.theme_type_variation == &"ClassicTheldrowOptionButton" and identify_picker.theme_type_variation == &"ClassicTheldrowOptionButton" and detect_picker.get_item_text(0) == "Hero 1 • SP 30 • Cost 5" and identify_picker.get_item_text(0) == "Hero 1 • SP 30 • Cost 25" and (hidden_popover.find_child("ClassicItemDetailTitle", true, false) as Label).text == "Unknown wand" and (hidden_popover.find_child("ClassicItemDetailDescription", true, false) as Label).text == "Specials are unknown." and not _labels_in(hidden_popover).any(func(text: String) -> bool: return text.contains("+12") or text.contains("3–8")), "Detect Magic gives the item cell Castle's exact blue-green glow behind native-size item art while unidentified naming, Alt-detail privacy, and lore-caster selectors retain their Castle-backed roles and distinguish remaining SP from action cost"); unidentified_component.free()
	var level_component := LevelUpInteraction.new(); var level_request := ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP); level_component.build(level_request)
	assert_true(_labels_in(level_component).any(func(text: String) -> bool: return text.contains("level 5")), "the level result presents its committed character level")
	assert_true(_buttons_in(level_component).any(func(button: Button) -> bool: return button.text == "Continue"), "the level result exposes one typed acknowledgement")
	assert_false(InteractionLayoutPolicyScript.uses_application_workspace(level_request), "a committed level result uses a locked floating modal rather than replacing the application workspace"); assert_equal(InteractionLayoutPolicyScript.preferred_modal_size(level_request, Vector2(984, 494)), Vector2(760, 430), "the level result keeps a compact Castle-shaped modal footprint")
	level_component.free()
	var spell_request := ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"); var spell_body := spell_request.body as InteractionRequest.LevelUpRequestBody; spell_body.point_total = 2; var spell_component := LevelUpInteraction.new(); spell_component.build(spell_request)
	var level_two := spell_component.find_child("LevelSpellLevel2", true, false) as Button; var selected_spell := _buttons_in(spell_component.find_child("LevelSpellList", true, false))[0]; var spell_confirm := spell_component.find_child("LevelSpellConfirm", true, false) as Button; assert_true(spell_component.find_child("LevelSpellLevelRail", true, false) != null and level_two.text == "Level 2" and selected_spell.button_pressed and not selected_spell.disabled and not spell_confirm.disabled and (spell_component.find_child("LevelSpellDescription", true, false) as Label).text.contains("Spell 1") and InteractionLayoutPolicyScript.uses_application_modal_region(spell_request) and InteractionLayoutPolicyScript.preferred_modal_size(spell_request, Vector2(1280, 688)) == Vector2(1080, 668) and InteractionLayoutPolicyScript.preferred_modal_size(spell_request, Vector2(2480, 1360)) == Vector2(1080, 760), "Learn Spells keeps chosen spells removable, shows the supplied application description, permits a banked-point confirmation, uses the available canonical height, and caps its centered modal at tall resolutions"); level_two.pressed.emit(); assert_true(_buttons_in(spell_component.find_child("LevelSpellList", true, false)).any(func(button: Button) -> bool: return button.text.begins_with("Spell 2") and button.theme_type_variation == &"ClassicTheldrowButton" and button.toggle_mode and button.disabled and button.tooltip_text.contains("only 1 remain")) and (spell_component.find_child("LevelSpellDescription", true, false) as Label).text.contains("Spell 2"), "changing levels keeps an unaffordable candidate visible with an exact disabled reason and refreshes its description")
	assert_true((spell_component.find_child("LevelSpellBudgetNotice", true, false) as Label).text.contains("1 point") and spell_confirm.tooltip_text.contains("banked"), "the spell stage explains that unspent points may be banked"); spell_body.spells[1].selected = true; var invalid_component := LevelUpInteraction.new(); invalid_component.build(spell_request); assert_true((invalid_component.find_child("LevelSpellConfirm", true, false) as Button).disabled and (invalid_component.find_child("LevelSpellBudgetNotice", true, false) as Label).text.contains("exceeds"), "an invalid restored selection disables confirmation and explains the over-budget state")
	spell_component.free(); invalid_component.free()
	var roster := load("res://src/presentation/screens/classic_party_roster.tscn").instantiate() as ClassicPartyRoster
	(Engine.get_main_loop() as SceneTree).root.add_child(roster)
	var selection_view := GameView.new(1, true, null); selection_view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)), CharacterView.new(CharacterState.new("mage", "Mage", 6, 9)), CharacterView.new(CharacterState.new("dead", "Dead", -10, 10))]
	var request := _fixture_request("fixture.party-pick", InteractionRequest.CHARACTER_SELECTION, {"count": 2, "eligible": [{"id": "hero", "name": "Hero", "currentHealth": 8, "maximumHealth": 10}, {"id": "mage", "name": "Mage", "currentHealth": 6, "maximumHealth": 9}], "mode": "field-spell", "spellId": "classic.spell.1107", "spellContext": {"actorId": "hero", "actorName": "Hero", "spellId": "classic.spell.1107", "spellName": "Magic Darts", "description": "A compact bolt of magical force.", "iconResourceType": "cicn", "iconId": 0, "power": 2, "spellPointCost": 8, "targetType": 0, "targetSize": 0, "targetCount": 2, "sourceKind": "field-spell"}})
	var selection_component := SelectionInteraction.new(); selection_component.configure(null, selection_view); selection_component.build(request)
	assert_true(not _buttons_in(selection_component).any(func(button: Button) -> bool: return button.name.begins_with("CharacterSelection_")) and selection_component.find_child("SpellTargetContext", true, false) != null and selection_component.find_child("ClassicSpellTargetBadge", true, false) == null and _labels_in(selection_component).any(func(text: String) -> bool: return text.contains("Party roster")), "mandatory character selection keeps spell context in the narrative region while the one authoritative Party roster owns every candidate")
	selection_component.free()
	var ally_request := ClassicUiFixtureGallery.request_for(InteractionRequest.ALLY_SELECTION); var ally_monster := MonsterState.new("ally", "classic.monster.4", "Allied Knight", 8, 10, 1, 1, 0, 0, 0, false); ally_monster.icon_id = 159; var ally_combat := CombatState.new("ally-preview", [ally_monster]); ally_combat.completed = true; ally_combat.outcome = &"victory"; var ally_view := GameView.new(1, true, null); ally_view.combat_view = CombatView.new(ally_combat); var ally_component := SelectionInteraction.new(); ally_component.configure(item_media, ally_view); ally_component.build(ally_request); assert_true(ally_component.find_child("AllyCandidates", true, false) != null and ally_component.find_child("AllySelectionContinue", true, false) != null and (ally_component.find_child("AllyCandidate_ally", true, false) as CheckButton).icon != null, "surviving allies use one dominant candidate workspace with the exact completed-combat icon and a fixed continuation"); assert_true(not InteractionLayoutPolicyScript.uses_full_stage_region(ally_request) and InteractionLayoutPolicyScript.uses_application_modal_region(ally_request), "surviving-allies selection is an application-centered locked Castle modal rather than a stale tactical-stage replacement"); ally_component.free(); var completion_treasure := InteractionRequest.from_payload("fixture.treasure.complete", InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "summary": "One item remains unclaimed."}); var completion_component := TreasureDistributionInteraction.new(); completion_component.configure(item_media, null, false); completion_component.build(completion_treasure); assert_true(completion_component.find_child("TreasureCompletionConfirmation", true, false) != null and _buttons_in(completion_component).any(func(button: Button) -> bool: return button.text == "Return to treasure"), "leave-behind confirmation retains an explicit path back to the Treasure workspace while the gallery owns the real Done-to-confirmation retained-surface rerender"); completion_component.free()
	var selections: Array[Array] = []; var current_characters: Array[String] = []; var activated_characters: Array[String] = []
	roster.character_selection_completed.connect(func(ids: Array[String]) -> void: selections.append(ids)); roster.character_selected.connect(func(id: String) -> void: current_characters.append(id)); roster.character_activated.connect(func(id: String) -> void: activated_characters.append(id))
	roster.set_media_catalog(item_media); roster.present(selection_view, "hero"); var ordinary_rows := _buttons_in(roster); var dead_portrait := ordinary_rows[2].icon.get_image().get_data(); selection_view.party_members[2].current_health = -1; roster.present(selection_view, "hero"); var unconscious_portrait := _buttons_in(roster)[2].icon.get_image().get_data()
	selection_view.party_members[2].current_health = -10; roster.present(selection_view, "hero"); ordinary_rows = _buttons_in(roster); var current_markers := roster.find_children("CurrentCharacterMarker", "ColorRect", true, false).filter(func(marker: Node) -> bool: return (marker as ColorRect).color.a > 0.0); assert_true(ordinary_rows.all(func(button: Button) -> bool: return not button.toggle_mode and not button.button_pressed) and current_markers.size() == 1 and String(current_markers[0].get_meta("character_id")) == "hero" and ordinary_rows[2].icon.get_size() == Vector2(50, 50) and dead_portrait != unconscious_portrait, "the ordinary Party rail marks exactly one current character, shades an unconscious portrait, and adds a distinct skull layer at Castle's exact death threshold"); ordinary_rows[1].pressed.emit(); current_markers = roster.find_children("CurrentCharacterMarker", "ColorRect", true, false).filter(func(marker: Node) -> bool: return (marker as ColorRect).color.a > 0.0); ordinary_rows[1].pressed.emit(); assert_equal([current_characters, activated_characters, current_markers.size(), String(current_markers[0].get_meta("character_id"))], [["mage"], ["mage"], 1, "mage"], "clicking another row moves the current marker, while clicking the current row activates that exact Character record")
	var mage_row_instance_id := ordinary_rows[1].get_instance_id(); selection_view.party_members[1].maximum_spell_points = 100; selection_view.party_members[1].spell_points = 5; roster.present_ordinary_exploration(selection_view, "mage"); ordinary_rows = _buttons_in(roster); assert_true(ordinary_rows[1].get_instance_id() == mage_row_instance_id and ordinary_rows[1].text.contains("SP 5/100"), "an hourly ordinary-movement refresh updates recovered spell points in the existing Party row without rebuilding the roster")
	roster.present_character_selection(request)
	var rows := _buttons_in(roster)
	var initial_cursor_count := roster.find_child("CharacterSelectionCursorCount", true, false) as Label; assert_true(rows[2].disabled and initial_cursor_count != null and initial_cursor_count.visible and initial_cursor_count.text == "2", "the Party-list picker rejects an ineligible character and shows the source count before the first selection")
	rows[1].pressed.emit()
	assert_equal(_labels_in(roster).filter(func(text: String) -> bool: return text == "2"), ["2"], "the first of two Classic picks is stamped with the countdown number two")
	rows = _buttons_in(roster)
	rows[1].pressed.emit()
	assert_true(not _labels_in(rows[1]).has("2") and initial_cursor_count.text == "2", "clicking a numbered portrait removes that pick and restores the cursor's remaining count")
	rows = _buttons_in(roster)
	rows[1].pressed.emit()
	rows = _buttons_in(roster)
	rows[0].pressed.emit()
	assert_equal(selections, [["hero", "mage"]], "the exact source-authored count auto-submits stable identities in Classic party order")
	roster.present_character_selection(null)
	assert_false(_labels_in(roster).any(func(text: String) -> bool: return text in ["1", "2"]), "leaving the interaction clears temporary Party-list numbering")
	roster.free()


func _test_treasure_slot_and_pickup_origin() -> void:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter
	host.add_child(presenter)
	await (Engine.get_main_loop() as SceneTree).process_frame
	presenter.set_classic_regions(Rect2(0.0, 28.0, 928.0, 532.0), Rect2(330.0, 568.0, 620.0, 152.0), Rect2(0.0, 568.0, 1280.0, 152.0))
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new())
	var request := ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized")
	presenter.present(request, "", null, media)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var source := presenter.find_child("TreasureItem_reward_item_2", true, false) as Button
	var original_grid := presenter.find_child("TreasureItemGrid", true, false) as GridContainer
	var original_third := presenter.find_child("TreasureItem_reward_item_3", true, false) as Button
	var source_center := source.get_global_rect().get_center()
	var original_child_count := original_grid.get_child_count()
	var original_third_index := original_third.get_index()
	source.pressed.emit()
	assert_true(presenter.capture_treasure_transfer(), "a committed Treasure assignment captures its source before the request rebuild")
	var payload := (request.body as InteractionRequest.TreasureRequestBody).to_data()
	var remaining_items: Array = payload["items"]
	payload["items"] = remaining_items.filter(func(item: Dictionary) -> bool: return item["instanceId"] != "reward.item.2")
	payload["remaining"] = (payload["items"] as Array).size()
	var updated := InteractionRequest.from_payload("fixture.treasure.after-assignment", InteractionRequest.TREASURE_DISTRIBUTION, payload)
	presenter.present(updated, "", null, media)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var updated_grid := presenter.find_child("TreasureItemGrid", true, false) as GridContainer
	var vacant_second := presenter.find_child("TreasureVacantSlot_reward_item_2", true, false) as Control
	var retained_third := presenter.find_child("TreasureItem_reward_item_3", true, false) as Button
	assert_true(updated.request_id != request.request_id and updated_grid.get_child_count() == original_child_count and vacant_second != null and vacant_second.get_index() == 1 and retained_third.get_index() == original_third_index, "a newly issued post-assignment Treasure request leaves an empty authored slot instead of compacting later loot")
	assert_true(presenter.begin_treasure_transfer(false), "the captured Treasure pickup starts after the committed request is presented")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var effect := presenter.find_child("TreasureTakeEffect", true, false) as Control
	assert_true(effect != null and effect.get_parent() is CanvasLayer and effect.get_global_rect().get_center().is_equal_approx(source_center), "the Treasure pickup overlay remains centered on the clicked item instead of being arranged by the interaction container")
	host.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _test_lifecycle_interaction() -> void:
	var request := ApplicationLifecycleScript.end_adventure_request(false)
	assert_equal([request.body.to_data()["prompt"], request.kind, request.body.to_data()["inCombat"], request.body.to_data()["options"].size(), InteractionLayoutPolicyScript.uses_full_stage_region(request), InteractionLayoutPolicyScript.uses_application_modal_region(request), InteractionLayoutPolicyScript.preferred_modal_size(request, Vector2(1280, 692))], ["Return to the main menu?", InteractionRequest.SESSION_LIFECYCLE, false, 3, false, true, Vector2(560, 220)], "Main Menu exposes save, discard, and cancel together in an application-centered modal tall enough to avoid scrolling")
	assert_not_null(InteractionRequest.from_data(request.to_data()), "the typed lifecycle request retains the established interaction wire shape")
	var component := LifecycleInteractionScript.new()
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	var buttons := _buttons_in(component)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and return", "Return without saving", "Cancel"], "the dedicated presenter does not reinterpret lifecycle choices as scenario options"); assert_true(component.get_combined_minimum_size().y <= 170.0, "the complete Main Menu choice component fits inside its non-scrolling modal allocation")
	assert_true(component.handle_back(), "Escape invokes the declared lifecycle Cancel action"); assert_equal(submitted, [{"action": "cancel"}], "Cancel emits one typed host response")
	assert_equal(ApplicationLifecycleScript.response_action(request, InteractionPresenter.response_for(request, InteractionResponse.LifecycleBody.new(&"cancel"))), &"cancel", "the host accepts only an action declared by its request"); assert_equal(ApplicationLifecycleScript.response_action(request, InteractionResponse.from_data(request.request_id, request.kind, {"action": "invented"})), &"", "undeclared lifecycle actions fail explicitly")
	assert_false(ApplicationLifecycleScript.allows_close(&"save-and-end", false), "a rejected save cannot close the active session"); assert_true(ApplicationLifecycleScript.allows_close(&"save-and-end", true), "a validated save permits the requested close")
	assert_true(ApplicationLifecycleScript.allows_close(&"end-without-saving"), "explicit discard permits close without a repository write"); assert_false(ApplicationLifecycleScript.allows_close(&"cancel"), "Cancel never closes the active session")
	var operation_order: Array[String] = []
	var failed_save := ApplicationLifecycleScript.execute_end_adventure(&"save-and-end", func() -> bool: operation_order.append("save"); return false, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(1))
	assert_equal([failed_save["state"], operation_order], [&"save-failed", ["save"]], "save failure suppresses close instead of tearing down the active session")
	operation_order.clear(); var discarded := ApplicationLifecycleScript.execute_end_adventure(&"end-without-saving", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(2))
	assert_equal([discarded["state"], operation_order], [&"closed", ["close"]], "explicit discard closes once without touching the save repository"); operation_order.clear()
	var hook_request := InteractionRequest.acknowledge("fixture.end-hook", "The End Adventure hook runs."); var pending := ApplicationLifecycleScript.execute_end_adventure(&"end-without-saving", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.waiting(3, hook_request))
	assert_equal([pending["state"], pending["step"].interaction.request_id, operation_order], [&"pending", hook_request.request_id, ["close"]], "the host releases its confirmation while the session owns a saveable End Adventure hook interaction"); operation_order.clear()
	var cancelled := ApplicationLifecycleScript.execute_end_adventure(&"cancel", func() -> bool: operation_order.append("save"); return true, func() -> SessionStep: operation_order.append("close"); return SessionStep.completed(3)); assert_equal([cancelled["state"], operation_order], [&"cancelled", []], "Cancel invokes neither persistence nor session teardown")
	component.free()
	var combat_request := ApplicationLifecycleScript.end_adventure_request(true)
	assert_equal(combat_request.body.to_data()["options"].size(), 2, "battle End Adventure never offers an invalid combat save")
	assert_false(combat_request.body.to_data()["options"].any(func(option: Dictionary) -> bool: return StringName(option["action"]) == &"save-and-end"), "battle End Adventure follows Castle's no-save branch")
	var quit_request := ApplicationLifecycleScript.quit_application_request(true, false)
	assert_equal([quit_request.body.to_data()["operation"], quit_request.body.to_data()["options"].size()], ["quit-application", 3], "field Quit is a distinct typed host operation with save, discard, and cancel")
	var quit_component := LifecycleInteractionScript.new()
	quit_component.build(quit_request)
	buttons = _buttons_in(quit_component)
	assert_equal(buttons.map(func(button: Button) -> String: return button.text), ["Save and Quit", "Quit", "Cancel"], "Quit keeps one compact host question with three content-sized actions"); assert_true(quit_component.find_child("LifecycleActions", true, false) is HBoxContainer and quit_component.find_child("LifecycleConsequence", true, false) == null and InteractionLayoutPolicyScript.interaction_vertical_scroll_mode(quit_request) == ScrollContainer.SCROLL_MODE_DISABLED, "Quit omits duplicate consequence prose, keeps its actions in one centered row, and cannot acquire a content scrollbar")
	assert_equal([InteractionLayoutPolicyScript.preferred_modal_size(quit_request, Vector2(1280.0, 688.0)), InteractionLayoutPolicyScript.preferred_modal_size(quit_request, Vector2(800.0, 568.0))], [Vector2(460.0, 135.0), Vector2(460.0, 135.0)], "Quit retains the same shortest usable content frame at canonical and Classic application sizes")
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


func _test_application_quit_composition() -> void:
	var quit_calls: Array[String] = []; var app := load("res://src/presentation/realmz_application.tscn").instantiate() as RealmzApplication; app.configure_lifecycle_host(SaveHostController.new(RejectingSaveRepository.new()), func() -> void: quit_calls.append("quit")); (Engine.get_main_loop() as SceneTree).root.add_child(app)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var started := app.start_package(FIXTURE_PATH, 271); var shell := app.get_node("ClassicShell") as ClassicApplicationShell; var status := app.get_node("ClassicShell/BottomRegion/BottomRow/NarrativeWell/NarrativeColumn/Facts/Status") as Label; assert_true(started.state != SessionStep.State.FAILED, "the composition-root Quit proof starts the public synthetic package through the real application")
	shell.quit_requested.emit()
	var menu_actions := _direct_buttons_in(app.find_child("LifecycleActions", true, false))
	var quit_presenter := app.get_node("InteractionPanel") as InteractionPresenter
	var quit_scroll := quit_presenter.get_node("InteractionScroll") as ScrollContainer
	assert_equal(menu_actions.map(func(button: Button) -> String: return button.text), ["Save and Quit", "Quit", "Cancel"], "the real System-menu signal reaches the typed field Quit transaction")
	assert_equal([quit_presenter.size.y, quit_scroll.get_v_scroll_bar().visible, menu_actions.all(func(button: Button) -> bool: return button.is_visible_in_tree() and quit_presenter.get_global_rect().encloses(button.get_global_rect()))], [135.0, false, true], "Quit stays at its compact content height with every action visible and no offered scrollbar")
	(menu_actions[0] as Button).pressed.emit()
	shell.save_and_quit_requested.emit("quick")
	assert_true(quit_calls.is_empty() and status.text.begins_with("Save failed"), "an injected repository failure keeps the real application open after Save and Quit")
	app.notification(app.NOTIFICATION_WM_CLOSE_REQUEST); var close_actions := _direct_buttons_in(app.find_child("LifecycleActions", true, false)); assert_equal(close_actions.map(func(button: Button) -> String: return button.text), ["Save and Quit", "Quit", "Cancel"], "the window-close notification reaches the same typed field Quit transaction"); (close_actions[1] as Button).pressed.emit(); assert_equal(quit_calls, ["quit"], "window-close no-save acceptance invokes the configured host termination exactly once"); (app.get_node("InteractionPanel") as InteractionPresenter).present(null); await (Engine.get_main_loop() as SceneTree).process_frame; app.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame


func _test_classic_choice_context() -> void:
	var journal_request := InteractionRequest.from_payload("journal-text", InteractionRequest.ACKNOWLEDGE, {"prompt": "A source message", "journalEligible": true, "journalRecorded": false})
	var journal_component := TextChoiceInteraction.new(); var journal_payloads: Array[Dictionary] = []
	journal_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: journal_payloads.append(body.to_data()))
	journal_component.configure(true); journal_component.build(journal_request); var global_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter; (Engine.get_main_loop() as SceneTree).root.add_child(global_presenter); await (Engine.get_main_loop() as SceneTree).process_frame; var global_responses: Array[InteractionResponse] = []; global_presenter.response_submitted.connect(func(response: InteractionResponse) -> void: global_responses.append(response)); global_presenter.present(InteractionRequest.from_payload("global-text", InteractionRequest.ACKNOWLEDGE, {"prompt": "Click anywhere.", "presentation": "classic-textbox"})); var global_click := InputEventMouseButton.new(); global_click.button_index = MOUSE_BUTTON_LEFT; global_click.pressed = true; assert_true(global_presenter.handle_global_pointer_acknowledgement(global_click) and global_responses.size() == 1, "any application left click advances exactly one positive Classic textbox through the typed response boundary"); global_presenter.present(null); global_presenter.free()
	var journal_buttons: Array[Node] = journal_component.find_children("*", "Button", true, false)
	assert_true(journal_buttons.is_empty() and _labels_in(journal_component).is_empty(), "positive Classic text advances from its narrative surface without consuming narrative height on redundant helper copy or a formal Continue button")
	assert_true(journal_component.submit_acknowledgement(), "the narrative surface owns one typed acknowledgement action")
	assert_equal(journal_payloads, [{"takeNote": true}], "an explicitly enabled Auto Note preference preserves the typed journal flag on ordinary acknowledgement"); journal_component.free(); var default_journal := TextChoiceInteraction.new(); var default_journal_payloads: Array[Dictionary] = []; default_journal.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: default_journal_payloads.append(body.to_data())); default_journal.build(journal_request); assert_true(default_journal.submit_acknowledgement(), "default-off Auto Note retains the ordinary acknowledgement boundary"); assert_equal(default_journal_payloads, [{}], "Castle's PRFN default-off Auto Note advances without a record flag unless the player uses manual N"); default_journal.free()
	var empty_acknowledgement := TextChoiceInteraction.new(); empty_acknowledgement.build(InteractionRequest.acknowledge("empty-text", "")); assert_equal(_buttons_in(empty_acknowledgement).map(func(button: Button) -> String: return button.text), ["Continue"], "an authored empty positive message exposes an explicit acknowledgement instead of an internal interaction label"); empty_acknowledgement.free()
	var scrolling_lines := PackedStringArray()
	for line_index in range(80):
		scrolling_lines.append("Authored scrolling line %d remains visible over Castle's tiled field." % line_index)
	var scrolling_prompt := "\n".join(scrolling_lines)
	var scrolling_request := InteractionRequest.from_payload("scrolling-text", InteractionRequest.ACKNOWLEDGE, {"prompt": scrolling_prompt, "messageId": 1, "presentation": "classic-scrolling-text"})
	var scrolling_loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(scrolling_loaded.is_ok(), "the scrolling-text presentation proof loads the real packaged TEXT fixture")
	var scrolling_resource_request := InteractionRequest.from_payload("scrolling-resource", InteractionRequest.ACKNOWLEDGE, {"prompt": "", "presentation": "classic-scrolling-text", "resourceType": "TEXT", "resourceId": -200})
	var scrolling_component := ScrollingTextInteractionScript.new()
	scrolling_component.theme = load("res://src/presentation/classic_ui_theme.tres") as Theme
	var scrolling_media := ClassicMediaCatalog.new(scrolling_loaded.media, ApplicationMediaCatalog.new())
	scrolling_component.configure(scrolling_media)
	var scrolling_responses: Array[Dictionary] = []
	scrolling_component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: scrolling_responses.append(body.to_data()))
	scrolling_component.build(scrolling_request)
	scrolling_component.size = Vector2(640.0, 420.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(scrolling_component)
	await (Engine.get_main_loop() as SceneTree).process_frame
	scrolling_component.set_process(false)
	var scrolling_text := scrolling_component.find_child("ClassicScrollingText", true, false) as RichTextLabel
	var scrolling_background := scrolling_component.find_child("ClassicScrollingTextBackground", true, false) as TextureRect
	var scroll_bar := scrolling_text.get_v_scroll_bar()
	var scroll_before := scroll_bar.value
	scrolling_component.call("_process", 0.15)
	assert_true(scrolling_text.text == scrolling_prompt and scrolling_text.is_visible_in_tree() and scrolling_text.get_theme_color(&"default_color").get_luminance() < 0.1 and scrolling_background.texture != null and scrolling_background.texture.get_size() == Vector2(64.0, 64.0) and scrolling_background.stretch_mode == TextureRect.STRETCH_TILE and scrolling_background.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED and scroll_bar.max_value > scroll_bar.page and scroll_bar.value >= scroll_before + 3.0 and _buttons_in(scrolling_component).any(func(button: Button) -> bool: return button.text == "Done") and InteractionLayoutPolicyScript.uses_full_stage_region(scrolling_request) and not InteractionLayoutPolicyScript.uses_textbox_region(scrolling_request) and ScrollingTextInteractionScript.automatic_scroll_distance(0.15) == 3.0 and [ScrollingTextInteractionScript.drag_scroll_delta(20.0, 19.0), ScrollingTextInteractionScript.drag_scroll_delta(20.0, 21.0)] == [25.0, -25.0], "opcode 62 displays its exact authored text over tiled application ppat 129 and advances the real text viewport at Castle's automatic and drag cadence")
	var scrolling_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter
	(Engine.get_main_loop() as SceneTree).root.add_child(scrolling_presenter)
	scrolling_presenter.set_classic_regions(Rect2(8.0, 72.0, 912.0, 488.0), Rect2(330.0, 568.0, 620.0, 176.0), Rect2(0.0, 568.0, 1280.0, 184.0))
	scrolling_presenter.present(scrolling_resource_request, "", GameView.new(1, true, null), scrolling_media)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var presented_scrolling_text := scrolling_presenter.find_child("ClassicScrollingText", true, false) as RichTextLabel
	var presented_scrolling_background := scrolling_presenter.find_child("ClassicScrollingTextBackground", true, false) as TextureRect
	var presented_scrolling_well := scrolling_presenter.find_child("ClassicScrollingTextWell", true, false) as PanelContainer
	assert_equal([scrolling_presenter.position, scrolling_presenter.size], [Vector2(8.0, 72.0), Vector2(912.0, 488.0)], "the production interaction presenter places opcode 62 in the complete map-stage region")
	assert_not_null(presented_scrolling_text, "the production interaction presenter mounts the opcode 62 text viewport")
	assert_equal(presented_scrolling_text.text.strip_edges() if presented_scrolling_text != null else "missing", "The fixture road turns north toward Giant Mountain.", "the production interaction presenter resolves opcode 62's exact signed package TEXT resource")
	assert_true(presented_scrolling_text != null and presented_scrolling_text.size.y > 300.0 and presented_scrolling_well != null and presented_scrolling_well.size.y > 300.0, "the opcode 62 text well expands vertically instead of collapsing into an empty strip")
	assert_true(presented_scrolling_background != null and presented_scrolling_background.texture != null, "the production opcode 62 surface retains application ppat 129 behind authored text")
	scrolling_presenter.present(null)
	scrolling_presenter.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(scrolling_component.handle_back() and scrolling_responses == [{}], "scrolling text exposes an Escape-equivalent typed acknowledgement without a generic single-click dismissal")
	scrolling_component.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	var yes_no := TextChoiceInteraction.new(); yes_no.build(InteractionRequest.yes_no("layout-choice", "Continue?", "Yes", "No"))
	var yes_no_grid := yes_no.find_child("ChoiceGrid", true, false) as GridContainer
	assert_true((yes_no.find_child("ChoicePane", true, false) as Control).size_flags_horizontal == Control.SIZE_SHRINK_END and yes_no_grid != null and yes_no_grid.columns == 2 and _buttons_in(yes_no).all(func(button: Button) -> bool: return button.theme_type_variation == &"ClassicChoiceButton" and button.custom_minimum_size.x == 140.0), "binary Classic choices share one lower-right, content-width semantic response row")
	yes_no.free()
	var choices := TextChoiceInteraction.new(); choices.build(InteractionRequest.from_payload("encounter-layout", InteractionRequest.ENCOUNTER_CHOICE, {"prompt": "Choose", "options": [{"label": "Ask"}, {"label": "Buy"}, {"label": "Listen"}], "canBackOut": true})); assert_equal((choices.find_child("ChoiceGrid", true, false) as GridContainer).columns, 1, "authored encounter options form one compact vertical list"); choices.free()
	var hero_spell := SpellDefinition.new("classic.spell.1107", 1107, "Magic Darts", "A compact bolt of magical force."); var mage_spell := SpellDefinition.new("classic.spell.1306", 1306, "Brimstones", "Burning stones strike the target."); var hero_view := CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)); hero_view.spells = [SpellView.new(hero_spell)]; var torch_definition := ItemDefinition.new("classic.item.805", 805, "Torch", "Equipment", "A carried torch."); torch_definition.icon_id = 805; hero_view.items = [ItemView.new(ItemInstance.new("torch.1", torch_definition.id, 4, false, true), torch_definition)]; var mage_view := CharacterView.new(CharacterState.new("mage", "Mage", 8, 10)); mage_view.spells = [SpellView.new(mage_spell)]; var wand_definition := ItemDefinition.new("classic.item.6110", 6110, "Runed wand", "Wand", "A charged runed wand."); wand_definition.icon_id = 6110; mage_view.items = [ItemView.new(ItemInstance.new("wand.1", wand_definition.id, 7, true, true), wand_definition)]; var encounter_view := GameView.new(1, true, null); encounter_view.party_members = [hero_view, mage_view]; var encounter := EncounterInteraction.new(); encounter.configure(null, encounter_view); var encounter_responses: Array[Dictionary] = []; var direct_side_workspaces: Array[Control] = []; encounter.response_body_submitted.connect(func(body: InteractionResponse.ComplexEncounterBody) -> void: encounter_responses.append(body.to_data())); encounter.side_workspace_requested.connect(func(workspace: Control) -> void: direct_side_workspaces.append(workspace)); var encounter_request := ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION); encounter.build(encounter_request)
	var command_strip := encounter.find_child("EncounterCommandStrip", true, false) as GridContainer; assert_true(encounter.find_child("EncounterCommandDeck", true, false) != null and encounter.find_child("EncounterContextDeck", true, false) == null and command_strip != null and command_strip.get_child_count() == 6 and direct_side_workspaces.is_empty(), "complex encounters open on one idle Action, Items, Skills, Speak, Spells, and Stop dock without obscuring the authored prompt or selecting a command")
	(encounter.find_child("EncounterCommandAction", true, false) as ClassicBitmapButton).command_requested.emit(&"action"); var direct_action_workspace := direct_side_workspaces[-1]; assert_true((direct_action_workspace.find_child("EncounterChoiceGrid", true, false) as GridContainer).columns == 1 and direct_action_workspace.find_child("EncounterChoiceScroll", true, false) is ScrollContainer and direct_action_workspace.find_child("EncounterChoiceDone", true, false) is ClassicBitmapButton and direct_action_workspace.find_child("EncounterChoiceStop", true, false) is ClassicBitmapButton and (direct_action_workspace.find_child("EncounterActionInstruction", true, false) as Label).text == "Choose 1 action, then press Done.", "Action opens the Castle-shaped roster sidebar with an independently scrolling choice list plus dedicated square Done and local Stop controls")
	var interaction_host := Control.new(); interaction_host.size = Vector2(1280, 720); (Engine.get_main_loop() as SceneTree).root.add_child(interaction_host); var encounter_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter; interaction_host.add_child(encounter_presenter); await (Engine.get_main_loop() as SceneTree).process_frame; var stage_rect := Rect2(8, 80, 912, 450); var textbox_rect := Rect2(330, 568, 620, 176); encounter_presenter.set_classic_regions(stage_rect, textbox_rect, Rect2(0, 568, 1280, 184)); var item_responses: Array[Dictionary] = []; encounter_presenter.response_submitted.connect(func(response: InteractionResponse) -> void: item_responses.append(response.body.to_data())); encounter_presenter.present(encounter_request, "Previous Action Point narration that must not replace this encounter.", encounter_view); await (Engine.get_main_loop() as SceneTree).process_frame; var encounter_prompt := encounter_presenter.find_child("InteractionPrompt", true, false) as Label; var encounter_shield := interaction_host.find_child("LockedModalShield", true, false) as ColorRect; var encounter_dock := interaction_host.find_child("EncounterCommandDock", true, false) as Control; var encounter_frame_preserves_narrative := encounter_prompt.text == encounter_request.body.prompt_text() and encounter_presenter.position == textbox_rect.position and encounter_presenter.size == textbox_rect.size and interaction_host.find_child("InteractionSideWorkspace", true, false) == null and encounter_dock != null and encounter_dock.position.x == textbox_rect.position.x and encounter_dock.size.x == textbox_rect.size.x and encounter_dock.position.y + encounter_dock.size.y <= textbox_rect.position.y and encounter_shield != null and encounter_shield.color.a == 0.0 and encounter_shield.mouse_filter == Control.MOUSE_FILTER_STOP; (encounter_dock.find_child("EncounterCommandAction", true, false) as ClassicBitmapButton).command_requested.emit(&"action"); var action_sidebar := interaction_host.find_child("InteractionSideWorkspace", true, false) as Control; var action_choice := _direct_buttons_in(action_sidebar.find_child("EncounterChoiceGrid", true, false) as Container)[0]; action_choice.button_pressed = true; action_choice.pressed.emit(); var action_done := action_sidebar.find_child("EncounterChoiceDone", true, false) as ClassicBitmapButton; action_done.command_requested.emit(&"done"); encounter_presenter.present(InteractionRequest.acknowledge("encounter-result", "Nothing happens."), "", encounter_view); await (Engine.get_main_loop() as SceneTree).process_frame; var result_interstitial := interaction_host.find_child("EncounterCommandDock", true, false) == null and interaction_host.find_child("InteractionSideWorkspace", true, false) == null and (encounter_presenter.find_child("InteractionPrompt", true, false) as Label).text == "Nothing happens."; encounter_presenter.present(encounter_request, "", encounter_view); await (Engine.get_main_loop() as SceneTree).process_frame; encounter_dock = interaction_host.find_child("EncounterCommandDock", true, false) as Control; var repeated_idle := encounter_dock != null and interaction_host.find_child("InteractionSideWorkspace", true, false) == null; var item_command := encounter_dock.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton; item_command.command_requested.emit(&"item"); var item_workspace := interaction_host.find_child("InteractionApplicationWorkspace", true, false); var encounter_item_choose := item_workspace.find_child("EncounterItemChoose", true, false) as ClassicBitmapButton; var item_is_standard: bool = item_workspace != null and item_workspace.size == Vector2(1280.0, 680.0) and item_workspace.find_child("EncounterItemsBack", true, false) != null and encounter_item_choose.custom_minimum_size.x == 150.0 and ["CastleInventoryMainSplit", "InventoryItemBrowser", "InventoryCharacterCommandRail", "InventoryItemInspector"].all(func(node_name: String) -> bool: return item_workspace.find_child(node_name, true, false) != null); (item_workspace.find_child("InventoryCharacter_mage", true, false) as Button).pressed.emit(); await (Engine.get_main_loop() as SceneTree).process_frame; item_workspace = interaction_host.find_child("InteractionApplicationWorkspace", true, false); (item_workspace.find_child("EncounterItemChoose", true, false) as ClassicBitmapButton).command_requested.emit(&"inventory.action.use"); await (Engine.get_main_loop() as SceneTree).process_frame; encounter_presenter.present(encounter_request, "Choose a spell.", encounter_view); encounter_dock = interaction_host.find_child("EncounterCommandDock", true, false) as Control; var spell_command := encounter_dock.find_child("EncounterCommandSpell", true, false) as ClassicBitmapButton; spell_command.command_requested.emit(&"spell"); var spell_sidebar := interaction_host.find_child("InteractionSideWorkspace", true, false) as Control; var caster_picker := spell_sidebar.find_child("SpellCharacterSelector", true, false) as OptionButton; var caster_count := caster_picker.item_count; caster_picker.select(1); caster_picker.item_selected.emit(1); await (Engine.get_main_loop() as SceneTree).process_frame; spell_sidebar = interaction_host.find_child("InteractionSideWorkspace", true, false) as Control; caster_picker = spell_sidebar.find_child("SpellCharacterSelector", true, false) as OptionButton; var level_three := spell_sidebar.find_child("SpellLevel3", true, false) as Button; var spell_choose := spell_sidebar.find_child("EncounterSpellChoose", true, false) as ClassicBitmapButton; spell_choose.pressed.emit(); var spell_is_standard := caster_count == 2 and caster_picker.selected == 1 and spell_sidebar.position == Vector2(928, 72) and spell_sidebar.size == Vector2(352, 680) and spell_sidebar.find_child("InteractionSideWorkspaceScroll", true, false) != null and spell_sidebar.find_child("ClassicSpellbookWorkspace", true, false) != null and spell_sidebar.find_child("KnownSpellList", true, false) != null and level_three.button_pressed and _buttons_in(spell_sidebar).any(func(button: Button) -> bool: return button.text.begins_with("Brimstones")) and item_responses[-1] == {"action": "spell", "classicSpellId": 1306, "characterId": "mage"}; interaction_host.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame; assert_true(encounter_frame_preserves_narrative and item_responses[0] == {"action": "choice", "slots": [0]} and result_interstitial and repeated_idle and item_is_standard and item_responses[1] == {"action": "item", "classicItemId": 6110, "characterId": "mage", "instanceId": "wand.1"} and spell_is_standard, "Action submission removes the dock/sidebar for the result acknowledgement and a repeated encounter restores its idle dock; Items still reuse the full standard workspace and Spells the caster-aware roster sidebar")
	var word_command := encounter.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton; word_command.command_requested.emit(&"word"); var word_entry := encounter.find_child("EncounterWord", true, false) as LineEdit
	assert_true(InteractionLayoutPolicyScript.uses_textbox_region(encounter_request) and not InteractionLayoutPolicyScript.uses_application_modal_region(encounter_request) and word_entry != null and word_entry.max_length == 39 and word_entry.theme_type_variation == &"ClassicTheldrowLineEdit" and encounter.find_child("EncounterWordActions", true, false) != null and _buttons_in(encounter).any(func(button: Button) -> bool: return button.text == "Speak") and encounter.handle_back() and encounter_responses[-1] == {"action": "back"}, "Encounter Speak uses the narrative well under the persistent command dock while Escape invokes authored Stop after local task unwind"); direct_action_workspace.free(); encounter.free()
	var thief := ThiefEncounterInteraction.new(); thief.build(ClassicUiFixtureGallery.request_for(InteractionRequest.THIEF_ENCOUNTER)); var thief_selector := thief.find_child("ThiefCharacterSelectorRow", true, false) as HBoxContainer; assert_true(thief.find_child("ThiefCharacterNavigator", true, false) != null and thief_selector != null and thief_selector.alignment == BoxContainer.ALIGNMENT_CENTER and thief_selector.get_child(0).name == "ThiefPreviousCharacter" and thief_selector.get_child(1).name == "ThiefCharacterPortrait" and thief_selector.get_child(2).name == "ThiefNextCharacter" and thief.find_child("ThiefActionPane", true, false) != null and thief.find_child("ThiefActionGrid", true, false) != null, "Encounter Skills center a tight previous, portrait, next selector above one content-sized source-valued action pane"); thief.free()


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
	var map_presenter := ClassicMapPresenter.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(map_presenter)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_not_null(map_presenter, "the canonical application owns one clipped exploration map presenter")
	if map_presenter == null:
		return
	map_presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	map_presenter.position = expected_viewport_rect.position
	map_presenter.size = expected_viewport_rect.size
	var viewport_rect := Rect2(map_presenter.position, map_presenter.size)
	var viewport_parent := map_presenter.get_parent()
	var viewport_cells := ClassicMapPresenter.viewport_cells_for(map_presenter.size, map_presenter.map_origin.y, map_presenter.cell_size); var projection_cells := ClassicMapPresenter.projection_cells_for(map_presenter.size, map_presenter.map_origin.y, map_presenter.cell_size)
	var draw_origin := ClassicMapPresenter.map_draw_origin_for(map_presenter.size, map_presenter.map_origin, map_presenter.cell_size, viewport_cells)
	var map_size := Vector2i(90, 90)
	var positions: Array[Vector2i] = [Vector2i(0, 45), Vector2i(45, 45), Vector2i(89, 45), Vector2i(45, 0), Vector2i(45, 89)]
	var cameras: Array[Vector2i] = []
	var party_rects: Array[Rect2] = []
	var retained_surface: Control
	for child: Node in map_presenter.get_children():
		if child.get_script() == RetainedMapSurfaceScript:
			retained_surface = child as Control
			break
	assert_true(retained_surface != null and retained_surface.find_children("*", "TileMapLayer", true, false).size() == 9 and not retained_surface.find_children("*", "Camera2D", true, false).is_empty() and not retained_surface.find_children("*", "SubViewport", true, false).is_empty() and projection_cells == viewport_cells + Vector2i(2, 2), "exploration owns one clipped retained SubViewport with base, six feature, marker, and fog TileMapLayer surfaces plus a Camera2D and one preprojected guard cell on every edge")
	var retained_base_layer := retained_surface.find_children("*", "TileMapLayer", true, false)[0] if retained_surface != null else null
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
	var darkness_surface := Rect2(0.0, 0.0, 100.0, 80.0)
	var darkness_lit_rect := Rect2(20.0, 10.0, 40.0, 30.0)
	var darkness_blackout: Array[Rect2] = RetainedMapSurfaceScript.darkness_blackout_rects(darkness_surface, darkness_lit_rect)
	var blackout_area: float = darkness_blackout.reduce(func(total: float, rect: Rect2) -> float: return total + rect.get_area(), 0.0)
	var memory_coordinates: Dictionary = {Vector2i(10, 10): true, Vector2i(11, 10): true, Vector2i(13, 10): true}
	var memory_rects: Array[Rect2] = RetainedMapSurfaceScript.darkness_memory_rects(Rect2(0.0, 0.0, 128.0, 64.0), Vector2i(10, 10), Vector2i(4, 2), 32.0, memory_coordinates)
	assert_true(is_equal_approx(blackout_area, darkness_surface.get_area() - darkness_lit_rect.get_area()) and darkness_blackout.any(func(rect: Rect2) -> bool: return rect.position == Vector2.ZERO and rect.size == Vector2(100.0, 10.0)), "darkness blacks the complete retained surface outside the torch mask, including fractional canvas edges that contain projection guard cells")
	assert_equal([ClassicMapPresenter.darkness_mask_rect(Rect2(100.0, 100.0, 32.0, 32.0)), RetainedMapSurfaceScript.darkness_memory_opacity(), memory_rects], [Rect2(-60.0, -60.0, 320.0, 320.0), 0.8, [Rect2(0.0, 0.0, 64.0, 32.0), Rect2(96.0, 0.0, 32.0, 32.0)]], "the fixed Classic darkness mask keeps its source-aligned party anchor while contiguous discovered terrain remains beneath its authored veil")
	assert_true(party_rects[0].position.x != party_rects[2].position.x and party_rects[0].size == party_rects[2].size and ClassicMapPresenter.classic_visible_rect(Vector2i(45, 45), map_size) == Rect2i(37, 39, 15, 13) and ClassicMapPresenter.classic_visible_rect(Vector2i.ZERO, map_size) == Rect2i(0, 0, 15, 13) and ClassicMapPresenter.land_discovery_coordinates([Vector2i(45, 45)], map_size).has(Vector2i(37, 39)) and ClassicMapPresenter.land_discovery_coordinates([Vector2i(45, 45)], map_size).has(Vector2i(51, 51)) and not ClassicMapPresenter.land_discovery_coordinates([Vector2i(45, 45)], map_size).has(Vector2i(36, 39)) and [ClassicMapPresenter.facing_label(Vector2i.UP), ClassicMapPresenter.facing_label(Vector2i.DOWN + Vector2i.LEFT)].all(func(label: String) -> bool: return label in ["N", "SW"]) and ClassicUiAssetCatalog.texture(&"map.party.camp") != null and ResourceLoader.exists("res://src/presentation/assets/ui/classic-exploration-surround-tile.png", "Texture2D"), "map presentation preserves viewport geometry, Castle's 15x13 current and remembered views, seamless unrevealed surround, exact camp-marker availability, and typed cardinal/intercardinal facing labels")
	assert_true(party_rects[3].position.y != party_rects[4].position.y and party_rects[3].size == party_rects[4].size, "north/south movement translates the party cell inside the viewport without changing cell geometry")
	assert_true(retained_surface != null and retained_base_layer == retained_surface.find_children("*", "TileMapLayer", true, false)[0], "ordinary camera movement retains the same map layers instead of rebuilding renderer nodes")
	var first_room := Vector2i(45, 45); var remembered_room := Vector2i(46, 45); var los_seen: Array[Vector2i] = [first_room, remembered_room]
	var first_los_cells: Array[MapCellView] = [MapCellView.new(first_room, "fixture.terrain", 1, "fixture.tileset", true, false, true, true, false, false, [], {}, {}, {}), MapCellView.new(remembered_room, "fixture.terrain", 1, "fixture.tileset", true, false, false, true, false, false, [], {}, {}, {})]
	var first_los_view := MapView.new("fixture.los", "LOS Rooms", &"land", map_size.x, map_size.y, first_room, first_los_cells, false, los_seen, {}, Vector2i.ZERO, -1, 1, true, false, -1, false, true, -1, true, los_seen)
	map_presenter.present(GameView.new(2, true, null, first_los_view.map_id, first_room, 0, 12, 0, first_los_view)); var los_blackout := retained_surface.find_child("LineOfSightBlackoutLayer", true, false) as TileMapLayer; var remembered_room_initial_blackout := los_blackout.get_cell_source_id(remembered_room)
	var room_delta := MapPresentationDelta.new(first_los_view.map_id, first_room, remembered_room, [], [], [first_room, remembered_room]); var second_los_cells: Array[MapCellView] = [MapCellView.new(first_room, "fixture.terrain", 1, "fixture.tileset", true, false, false, true, false, false, [], {}, {}, {}), MapCellView.new(remembered_room, "fixture.terrain", 1, "fixture.tileset", true, false, true, true, false, false, [], {}, {}, {})]
	var second_los_view := MapView.new(first_los_view.map_id, first_los_view.map_name, &"land", map_size.x, map_size.y, remembered_room, second_los_cells, false, los_seen, {}, Vector2i.RIGHT, -1, 1, true, false, -1, false, true, -1, true, los_seen, room_delta)
	map_presenter.present(GameView.new(3, true, null, second_los_view.map_id, remembered_room, 0, 12, 0, second_los_view)); assert_equal([remembered_room_initial_blackout, los_blackout.get_cell_source_id(first_room), los_blackout.get_cell_source_id(remembered_room), ClassicMapPresenter.los_cell_requires_blackout(true, false), ClassicMapPresenter.los_cell_requires_blackout(false, false)], [0, 0, -1, true, false], "the live LOS projection blacks a previously seen room, blacks the room just left, and incrementally reveals only the newly visible room")
	var package := PackageRepository.new().load_package("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"); assert_true(package.is_ok(), "the retained dungeon proof loads the validated package fixture")
	if package.is_ok():
		map_presenter.set_media_catalog(ClassicMediaCatalog.new(package.media, null))
		var dungeon_cells: Array[MapCellView] = [MapCellView.new(Vector2i.ZERO, "classic.dungeon.floor", 1, "dungeon-top-down-302", true, false, true, true, false, false, [], {}, {}, {}), MapCellView.new(Vector2i.RIGHT, "classic.dungeon.floor", 1, "dungeon-top-down-302", true, false, true, true, false, false, [&"column"], {}, {}, {})]
		var dungeon_view := MapView.new("dungeon:retained", "Retained Dungeon", &"dungeon", 3, 2, Vector2i.ZERO, dungeon_cells)
		map_presenter.present(GameView.new(4, true, null, dungeon_view.map_id, dungeon_view.party_coordinate, 0, 0, 0, dungeon_view))
		var dungeon_base_layer := retained_surface.find_children("*", "TileMapLayer", true, false)[0] as TileMapLayer; var dungeon_source_id := dungeon_base_layer.get_cell_source_id(Vector2i.ZERO); var dungeon_source := dungeon_base_layer.tile_set.get_source(dungeon_source_id) as TileSetAtlasSource if dungeon_source_id >= 0 else null
		assert_true(dungeon_source != null and dungeon_source.texture_region_size == Vector2i(32, 32) and dungeon_source.texture.get_size() == Vector2(128, 128), "the retained 2D renderer expands every native 16x16 dungeon atlas tile to one complete 32x32 map cell")
		assert_equal(dungeon_base_layer.map_to_local(Vector2i.RIGHT) - dungeon_base_layer.map_to_local(Vector2i.ZERO), Vector2(32, 0), "adjacent retained dungeon cells remain contiguous on the 32-pixel exploration grid")
	map_presenter.get_parent().remove_child(map_presenter)
	map_presenter.free()


func _test_battlefield_presenter() -> void:
	var presenter := ClassicBattlefieldPresenter.new(); var control_size := Vector2(912.0, 486.0); var visible_cells := ClassicBattlefieldPresenter.viewport_cells_for(control_size)
	assert_equal(visible_cells, Vector2i(28, 14), "battlefield uses every complete native cell available in the responsive camera window")
	var tracked_camera := Vector2i(30, 34); var draw_origin := ClassicBattlefieldPresenter.battlefield_draw_origin(control_size, visible_cells); var rendered_coordinate := Vector2i(40, 39); var rendered_point := ClassicBattlefieldPresenter.cell_rect(rendered_coordinate, tracked_camera, draw_origin).get_center()
	assert_true(ClassicBattlefieldPresenter.coordinate_for_point(rendered_point, tracked_camera, visible_cells, control_size) == rendered_coordinate and ClassicBattlefieldPresenter.click_direction_for_point(ClassicBattlefieldPresenter.cell_rect(rendered_coordinate, tracked_camera, draw_origin), rendered_point + Vector2(90.0, -65.0)) == Vector2i(1, -1) and ClassicBattlefieldPresenter.tracked_camera_top_left(tracked_camera, Vector2i(tracked_camera.x + visible_cells.x - 1, 39), visible_cells) == ClassicBattlefieldPresenter.camera_top_left(Vector2i(tracked_camera.x + visible_cells.x - 1, 39), visible_cells), "battlefield input uses the rendered camera and eight centered sectors while edge focus recenters the view")
	var large_move := CombatPlaybackFrame.new(&"move_start", 1.0); large_move.from_coordinate = Vector2i(10, 10); large_move.to_coordinate = Vector2i(11, 10); large_move.progress = 0.5; assert_equal([ClassicBattlefieldPresenter.footprint_rect([], Vector2i.ZERO, Vector2.ZERO), ClassicBattlefieldPresenter.moving_footprint_rect(BattlefieldState.footprint_cells(Vector2i(10, 10), 3), Vector2i(10, 10), large_move, Vector2i.ZERO, Vector2.ZERO), ClassicBattlefieldPresenter.classic_monster_icon_id(384, true)], [Rect2(), Rect2(304.0, 288.0, 64.0, 64.0), 692], "terminal playback tolerates a removed combatant while a moving two-by-two monster preserves its upper-left footprint offset and authored right-facing CICN")
	var view := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	presenter.present(view)
	presenter.set_movement_costs_visible(true)
	var playback_move := CombatPlaybackFrame.new(&"move_start", 0.18); playback_move.actor_id = "hero"; playback_move.camera_focus_id = "hero"; presenter.focus_combatant("monster"); presenter.present_playback_frame(playback_move); presenter.clear_playback_frame(); assert_true(presenter.movement_costs_visible() and view.combat_view.persistent_fields.size() == 1 and view.combat_view.persistent_fields[0].affected_coordinates == [Vector2i(45, 44), Vector2i(45, 45)] and ClassicBattlefieldPresenter.persistent_field_tile_id(view.combat_view.persistent_fields[0].queue_icon) == 214 and String(presenter.get("_camera_focus_id")).is_empty() and ClassicBattlefieldPresenter.camera_focus_id_for(presenter.playback_frame(), String(presenter.get("_camera_focus_id")), view.combat_view.active_actor_id) == "hero", "the battlefield renders detached persistent-field cells and committed playback retires stale target focus so consecutive actions remain centered on the active actor"); presenter.free()
func _test_combat_targeting_state() -> void:
	var body := InteractionResponse.CombatBody.new(&"cast_spell", "hero"); body.spell_id = "spell.darts"; var request := CombatTargetingRequest.new(&"sequence", body); request.candidate_ids.assign(["monster.one", "ally.one"]); request.maximum_targets = 1
	var state := CombatTargetingState.new(request)
	assert_equal([state.select_combatant("ally.one"), state.select_combatant("monster.one"), state.committed_body().target_ids, state.target_with_keyboard(), state.selected_ids], [true, false, ["ally.one"], true, ["monster.one"]], "typed sequence targeting enforces its maximum while T cycles the supplied legal target identities")
	var area_request := CombatTargetingRequest.new(&"area", body); area_request.validation_deferred = true; area_request.default_target_coordinate = Vector2i(45, 45); area_request.area_offsets = [Vector2i.ZERO]; area_request.area_rotation_offsets = [[Vector2i.ZERO], [Vector2i.ZERO, Vector2i.RIGHT]]
	var area_state := CombatTargetingState.new(area_request); assert_equal([area_state.hovered_coordinate, area_state.selected_coordinate, area_state.can_confirm(), area_state.target_with_keyboard(), area_state.selected_coordinate, area_state.can_confirm()], [Vector2i(45, 45), Vector2i(-1, -1), false, true, Vector2i(45, 45), true], "an area spell previews its default center and T marks that center for Space confirmation")
	assert_true(area_state.select_coordinate(Vector2i(44, 45)) and area_state.can_confirm(), "staged area targeting accepts a battlefield center without precomputing every legal center"); assert_true(area_state.rotate_area() and area_state.area_offsets == [Vector2i.ZERO, Vector2i.RIGHT] and area_state.committed_body().rotation == 1, "area targeting cycles only request-provided Data AD masks and commits the selected rotation")
	assert_equal(area_state.committed_body().target_coordinate, Vector2i(44, 45), "deferred targeting preserves the selected center for authoritative submit-time validation")
	var sequence_request := CombatTargetingRequest.new(&"coordinate_sequence", body); sequence_request.maximum_targets = 2; sequence_request.default_target_coordinate = Vector2i(44, 46); sequence_request.validation_deferred = true; var sequence_state := CombatTargetingState.new(sequence_request); assert_true(sequence_state.target_with_keyboard() and sequence_state.select_coordinate(Vector2i(43, 46)), "T and battlefield selection build an ordered summon-space sequence"); assert_false(sequence_state.select_coordinate(Vector2i(42, 46)), "summon-space targeting enforces the rules-owned maximum")
	assert_equal(sequence_state.committed_body().target_coordinates, [Vector2i(44, 46), Vector2i(43, 46)], "Space confirmation preserves ordered summon coordinates for the authoritative combat response"); assert_true(sequence_state.select_coordinate(Vector2i(44, 46)) and sequence_state.committed_body().target_coordinates == [Vector2i(43, 46)], "selecting an occupied sequence entry again removes it without reordering the remaining spaces")
func _test_combat_playback_controller() -> void:
	var previous := _combat_playback_view(20, Vector2i(45, 45), Vector2i(47, 45), &"active")
	var final := _combat_playback_view(12, Vector2i(46, 45), Vector2i(47, 45), &"active")
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_auto_started", {"actorId": "hero"}), DomainEvent.new(&"combatant_moved", {"actorId": "hero", "from": [45, 45], "to": [46, 45]}), DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 8, "classicResultEffectResourceId": 160}), DomainEvent.new(&"combat_spell_cast", {"actorId": "hero", "targetId": "monster", "spellId": "spell.test", "spellName": "Magic Darts"}), DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "monster", "spellId": "spell.test", "spellName": "Magic Darts", "resisted": true, "classicResolutionEffectResourceIds": [12032, 12033, 12034, 12035, 12036, 12037, 12038, 12039]}), DomainEvent.new(&"combat_auto_completed", {"actorId": "hero"})]
	var controller := CombatPlaybackController.new(); controller.set_speed_percent(50)
	var frames: Array[CombatPlaybackFrame] = []
	controller.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: frames.append(frame))
	assert_true(controller.begin(previous, events, final, false), "combat events create one presentation playback transaction")
	while controller.is_active(): controller.advance(1.0, false)
	var kinds: Array[StringName] = []
	for frame: CombatPlaybackFrame in frames:
		kinds.append(frame.kind)
	assert_true(kinds.has(&"move_start") and kinds.has(&"melee_attack") and is_equal_approx(frames[0].duration_seconds, 0.18) and frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"move_start" and frame.automatic and InteractionPresenter.playback_status_text(frame).begins_with("Auto Turn") and InteractionPresenter.playback_status_text(frame).contains("Esc cancels Party Auto")), "the persisted 50-percent combat speed keeps automatic movement readable while retaining distinct frames and the full-party safety hatch")
	assert_equal(kinds.count(&"spell_effect"), 8, "source-backed spell resolution retains its eight-frame family")
	assert_true(frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"spell_cast" and frame.display_text == "Cast Magic Darts") and frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"spell_effect" and frame.display_text == "Magic Darts"), "spell playback identifies the source-backed effect instead of presenting anonymous art")
	assert_true(frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result" and frame.display_text == "8"), "damage is shown once over the target")
	var buff_playback := CombatPlaybackController.new(); var buff_frames: Array[CombatPlaybackFrame] = []; buff_playback.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: buff_frames.append(frame)); assert_true(buff_playback.begin(previous, [DomainEvent.new(&"combat_spell_resolved", {"actorId": "hero", "targetId": "hero", "appliedCondition": ConditionRules.ATTACK_BONUS, "duration": 7})], final, false), "a successful combat buff enters ordinary playback"); while buff_playback.is_active(): buff_playback.advance(1.0, false); assert_true(buff_frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result" and frame.result_kind == &"condition" and frame.display_text == "Condition applied"), "a successful combat buff is presented as an applied condition instead of the damage-only No effect fallback")
	assert_equal(controller.base_view, previous, "playback retains the previous battlefield until visuals settle")
	var lethal_final := _combat_playback_view(0, Vector2i(46, 45), Vector2i(47, 45), &"active"); lethal_final.combat_view.round_number = 2; lethal_final.combat_view.active_actor_id = "hero.next"; var lethal := CombatPlaybackController.new(); var lethal_frames: Array[CombatPlaybackFrame] = []; lethal.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: lethal_frames.append(frame)); assert_true(lethal.begin(previous, [DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 20, "defeated": true})], lethal_final, false), "a lethal action owns playback through the following turn cue")
	while lethal.is_active(): lethal.advance(1.0, false)
	var lethal_attacks := lethal_frames.filter(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"melee_attack")
	var lethal_results := lethal_frames.filter(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result")
	var lethal_defeats := lethal_frames.filter(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"defeat")
	var next_actor_cues := lethal_frames.filter(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"actor_cue")
	assert_true(not lethal_attacks.is_empty() and not (lethal_attacks[0] as CombatPlaybackFrame).hides("monster") and not lethal_results.is_empty() and (lethal_results[0] as CombatPlaybackFrame).hides("monster") and not lethal_defeats.is_empty() and (lethal_defeats[0] as CombatPlaybackFrame).hides("monster") and not next_actor_cues.is_empty() and (next_actor_cues[-1] as CombatPlaybackFrame).hides("monster"), "a lethal target remains visible through the attack itself, disappears on the first committed result frame, and cannot flash back during defeat or the next-turn cue")
	var destroyed := CombatPlaybackController.new(); var destroyed_frames: Array[CombatPlaybackFrame] = []; destroyed.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void: if frame.progress == 0.0: destroyed_frames.append(frame)); assert_true(destroyed.begin(previous, [DomainEvent.new(&"combat_turn_undead_resolved", {"actorId": "hero", "targetId": "monster", "result": "destroyed"})], lethal_final, false), "a destroyed undead target enters ordinary committed playback"); while destroyed.is_active(): destroyed.advance(1.0, false); assert_true(destroyed_frames.any(func(frame: CombatPlaybackFrame) -> bool: return frame.kind == &"result" and frame.result_kind == &"destroyed" and frame.hides("monster")), "Turn Undead destruction removes the enemy icon on its result frame rather than one frame later")
	var reduced := CombatPlaybackController.new()
	assert_true(reduced.begin(previous, events, final, true), "reduced motion keeps the same presentation boundary")
	while reduced.is_active(): reduced.advance(1.0, false)
	assert_false(reduced.is_active(), "reduced motion settles without a simulation mutation")
	var toggle_events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 139, "source": "classic-combat-auto-toggle"}), DomainEvent.new(&"combat_auto_changed", {"characterId": "hero", "enabled": false})]
	assert_false(CombatPlaybackController.new().begin(previous, toggle_events, final, false), "an Auto toggle sound does not open another playback mask"); var debug_events: Array[DomainEvent] = [DomainEvent.new(&"combat_auto_started", {"actorId": "hero"}), DomainEvent.new(&"combatant_moved", {"actorId": "hero", "to": [46, 45]}), DomainEvent.new(&"combat_attack_resolved", {"actorId": "hero", "targetId": "monster", "hit": true, "damage": 8}), DomainEvent.new(&"combat_spell_cast", {"actorId": "hero", "targetId": "monster", "spellId": "spell.test", "spellName": "Magic Darts"}), DomainEvent.new(&"combat_auto_choice_rejected", {"actorId": "hero", "action": "cast_spell", "message": "No legal target remains."})]; assert_equal(DebugToolsHost.auto_action_lines(debug_events, final, null), ["Hero moved to 46,45.", "Hero attacked Goblin for 8 damage.", "Hero cast spell.test on Goblin."], "the compact debug Auto history translates committed movement, attack, and spell events without inspecting simulation state"); var readable_lines := DebugToolsHost.action_lines(debug_events, final, null); assert_true(readable_lines.any(func(line: String) -> bool: return line.contains("Hero moved to 46,45")) and readable_lines.any(func(line: String) -> bool: return line.contains("Hero") and line.contains("Magic Darts") and line.contains("Goblin")) and readable_lines.any(func(line: String) -> bool: return line.contains("could not cast spell") and line.contains("No legal target remains")), "the full console names combatants, actions, spell identities, destinations, and rejected Auto choices"); assert_true(DebugToolsHost.action_lines([DomainEvent.new(&"reward_opened", {"experienceShare": 250})])[0].contains("reward_opened") and DebugToolsHost.action_lines([DomainEvent.new(&"reward_opened", {"experienceShare": 250})])[0].contains("250"), "the full debug console retains every committed event kind and payload rather than filtering the game-action stream"); var matte_image := Image.create(3, 3, false, Image.FORMAT_RGBA8); matte_image.fill(Color.WHITE); matte_image.set_pixel(1, 1, Color.RED); var matte_texture := ClassicBattlefieldPresenter.remove_opaque_white_matte(ImageTexture.create_from_image(matte_image)); var cleaned := matte_texture.get_image(); assert_equal([cleaned.get_pixel(0, 0).a, cleaned.get_pixel(1, 1)], [0.0, Color.RED], "effect matte cleanup removes only border-connected opaque white while preserving the spell art"); var debug_dialog := DebugToolsDialog.new(); debug_dialog.call("_ready"); var warp_x := debug_dialog.find_child("WarpX", true, false) as SpinBox; var warp_y := debug_dialog.find_child("WarpY", true, false) as SpinBox; assert_true(warp_x != null and warp_y != null and warp_x.editable and warp_y.editable and warp_x.update_on_text_changed and warp_y.update_on_text_changed and warp_x.get_line_edit().select_all_on_focus, "debug warp coordinates accept direct selected text entry as well as spinner arrows"); debug_dialog.show(); debug_dialog.close_dialog(); assert_false(debug_dialog.visible, "the public debug dialog Close path releases the modal immediately"); debug_dialog.free()
	var spell_outcome_lines := DebugToolsHost.action_lines([DomainEvent.new(&"combat_spell_resolved", {"spellName": "Magic Darts", "targetId": "monster", "damage": 8, "healing": 0}), DomainEvent.new(&"combat_spell_resolved", {"spellName": "Discover Magic", "targetId": "monster", "damage": 0, "healing": 0, "detectedMagicItemCount": 3}), DomainEvent.new(&"combat_spell_resolved", {"spellName": "Inert Spell", "targetId": "monster", "damage": 0, "healing": 0})]); assert_equal(spell_outcome_lines, ["[COMBAT] Magic Darts → monster: 8 damage.", "[COMBAT] Discover Magic → monster: 3 magical items detected.", "[COMBAT] Inert Spell → monster: no effect."], "the debug console reports the actual spell outcome instead of treating every zero-valued healing field as healing")
func _combat_playback_view(monster_health: int, hero_position: Vector2i, monster_position: Vector2i, outcome: StringName) -> GameView:
	var tiles: Array[int] = []; tiles.resize(BattlefieldState.CELL_COUNT); tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	assert_true(battlefield.place_character("hero", hero_position), "playback fixture places the party actor")
	var monster := MonsterState.new("monster", "classic.monster.1", "Goblin", monster_health, 20); monster.icon_id = 384
	assert_true(battlefield.place_monster(monster.id, monster_position, 0), "playback fixture places the target")
	var combat := CombatState.new("classic.battle.playback", [monster], 0, battlefield); combat.set_turn_order(["hero", "monster"]); assert_not_null(combat.queue_persistent_field("classic.spell.field", "hero", Vector2i(45, 45), 1, 16, 14, 1, 0, 2), "playback fixture queues one source-shaped persistent field"); combat.outcome = outcome
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
	var definition := SpellDefinition.new("classic.spell.field", 1101, "Field Bolt", "A compact field spell description."); definition.target_type = 10
	var spell_view := SpellView.new(definition)
	spell_view.power_levels = [1, 2]
	spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", true)
	character_view.spells = [spell_view]; for index: int in range(2, 12): character_view.spells.append(SpellView.new(SpellDefinition.new("classic.spell.field.%d" % index, 1100 + index, "Field Spell %d" % index, "Another compact field spell description."))); character_view.fast_spells = [FastSpellBindingView.new(0, FastSpellBindingState.new(definition.id, 1), definition)]
	view.party_members = [character_view]; view.set_action_availability(&"set_fast_spell", true)
	var submitted: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: submitted.append(intent))
	var fixed_actions := HBoxContainer.new(); controller.present(body, view, null, 1.0, fixed_actions)
	var cast := fixed_actions.find_child("SpellCastAction", true, false) as BaseButton; var level_one := body.find_child("SpellLevel1", true, false) as Button; var spell_rows := _buttons_in(body.find_child("KnownSpellList", true, false)).filter(func(button: Button) -> bool: return button.name.begins_with("KnownSpell_")); var target_badge := body.find_child("ClassicSpellTargetBadge", true, false) as PanelContainer; assert_true(cast != null and cast.get_parent().get_parent() == fixed_actions and body.find_child("SpellCharacterSelector", true, false) != null and body.find_child("SpellLevelRail", true, false) != null and body.find_child("LevelStructuredSpellbook", true, false) is HBoxContainer and body.find_child("KnownSpellList", true, false).size_flags_stretch_ratio == 2.5 and body.find_child("SelectedSpellRecord", true, false).size_flags_vertical == Control.SIZE_FILL and spell_rows.size() == 11 and spell_rows.all(func(button: Button) -> bool: return button.custom_minimum_size.y == 21.0) and level_one.text == "Level 1" and target_badge.theme_type_variation == &"ClassicSpellTargetBadge" and target_badge.get_meta(&"target_asset_id") == &"spells.target.all_enemy" and (target_badge.find_child("ClassicSpellTargetText", true, false) as TextureRect).material is ShaderMaterial, "the field spellbook keeps eleven dense same-level rows beside its Classic level rail while Cast remains fixed and gradient target lettering is cut onto native slate chrome"); cast.pressed.emit()
	var cast_payload := submitted[0].payload as PlayerIntent.SpellPayload
	assert_equal([cast_payload.operation, cast_payload.caster_id, cast_payload.spell_id, cast_payload.power], [&"cast", "caster", "classic.spell.field", 1], "compact spell action preserves the selected caster, spell, and power"); _buttons_in(body).filter(func(button: Button) -> bool: return button.text == "Fast Spells (1–0)")[0].pressed.emit(); for child: Node in body.get_children(): child.free(); controller.present(body, view, null, 1.0, fixed_actions)
	var fast_picker := body.find_child("FastSpellPicker0", true, false) as OptionButton; fast_picker.select(2); fast_picker.item_selected.emit(2); var fast_payload := submitted[1].payload as PlayerIntent.SpellPayload; assert_true(not fast_picker.fit_to_longest_item and not _buttons_in(body).any(func(button: Button) -> bool: return button.text == "Set") and [submitted[1].kind, fast_payload.spell_id, fast_payload.power] == [PlayerIntent.Kind.SET_FAST_SPELL, definition.id, 2], "choosing a Fast Spell immediately emits its binding without a per-row Set action or a width-expanding longest-item minimum"); _buttons_in(body).filter(func(button: Button) -> bool: return button.text == "Clear")[0].pressed.emit(); assert_true((submitted[2].payload as PlayerIntent.SpellPayload).spell_id.is_empty(), "Clear immediately removes the assigned Fast Spell while Back remains navigation only"); body.free(); fixed_actions.free(); var blocked_body := VBoxContainer.new(); var blocked_actions := HBoxContainer.new(); var blocked_controller := SpellsWorkspaceController.new(); var blocked_view := GameView.new(6, true, null); blocked_view.character_spellcasting_blocked = true; spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, "Classic scenario state currently blocks character spellcasting."); blocked_view.party_members = [character_view]; blocked_controller.present(blocked_body, blocked_view, null, 1.0, blocked_actions); var blocked_rows := _buttons_in(blocked_body.find_child("KnownSpellList", true, false)).filter(func(button: Button) -> bool: return button.name.begins_with("KnownSpell_")); var blocked_cast := blocked_actions.find_child("SpellCastAction", true, false) as BaseButton; assert_true(blocked_body.find_child("SpellcastingBlockedNotice", true, false) != null and (blocked_body.find_child("SpellcastingBlockedNoticeText", true, false) as Label).text == "Spellcasting is disabled in this area." and blocked_rows.all(func(button: Button) -> bool: return button.modulate.r < 0.7 and not button.disabled) and blocked_cast.disabled, "opcode 69 leaves the spellbook browsable while visibly muting spell records, showing a persistent warning, and retaining rules-owned Cast denial"); blocked_body.free(); blocked_actions.free()


func _test_scroll_case_workspace() -> void:
	var body := VBoxContainer.new(); var controller := SpellsWorkspaceController.new(); var view := GameView.new(5, true, null); var definition := SpellDefinition.new("classic.spell.scroll", 1112, "Battle Scroll", "A combat-only scroll.")
	var character_view := CharacterView.new(CharacterState.new("caster", "Aster", 12, 12)); var scroll_view := SpellScrollView.new(0, SpellScrollState.new(definition.id, 1), definition); scroll_view.discard = ActionAvailabilityView.new(&"cast_spell", true); character_view.scrolls = [scroll_view]; view.party_members = [character_view]
	var submitted: Array[PlayerIntent] = []; controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: submitted.append(intent)); controller.present(body, view, null, 1.0); _buttons_in(body).filter(func(button: Button) -> bool: return button.text == "Scroll Case")[0].pressed.emit(); for child: Node in body.get_children(): child.free(); controller.present(body, view, null, 1.0)
	var discard := body.find_child("DiscardScroll0", true, false) as Button; assert_true(discard != null and not discard.disabled and body.find_child("UseScroll0", true, false) != null, "the five-slot case keeps separate Use and source-backed Discard actions"); discard.pressed.emit(); assert_equal([(submitted[0].payload as PlayerIntent.SpellPayload).operation, (submitted[0].payload as PlayerIntent.SpellPayload).scroll_slot], [&"use-scroll", 0], "Discard enters the same typed scroll transaction that owns its confirmation"); body.free()
func _test_inventory_workspace() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-ui", 10, "Longsword", "Sword", "A balanced sword."); definition.icon_id = 20; definition.vs_small = 10
	var source := CharacterState.new("source", "Alis", 10, 10); var destination := CharacterState.new("destination", "Borin", 12, 12)
	var view := GameView.new(4, true, null)
	var source_view := CharacterView.new(source); var destination_view := CharacterView.new(destination)
	var item_view := ItemView.new(ItemInstance.new("inventory.item", definition.id, 0, false, true), definition)
	item_view.actions.equip = ActionAvailabilityView.new(&"equip_item", true); item_view.actions.split = ActionAvailabilityView.new(&"split_item", true); item_view.actions.join = ActionAvailabilityView.new(&"join_item", true)
	item_view.actions.use = ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
	item_view.actions.trade = ActionAvailabilityView.new(&"trade_item", true); item_view.actions.trade_targets = [ItemTransferTargetView.new(destination.id, destination.name, true, "", 12, 17, 100)]
	var destination_item_view := ItemView.new(ItemInstance.new("inventory.item.return", definition.id, 0, false, true), definition); destination_item_view.actions.trade = ActionAvailabilityView.new(&"trade_item", true); destination_item_view.actions.trade_targets = [ItemTransferTargetView.new(source.id, source.name, true, "", 10, 15, 100)]; source_view.items = [item_view]; for index: int in range(1, 14): source_view.items.append(ItemView.new(ItemInstance.new("inventory.item.%d" % index, definition.id, 0, false, true), definition)); destination_view.items = [destination_item_view]
	view.party_members = [source_view, destination_view]
	var body := VBoxContainer.new(); body.custom_minimum_size = Vector2(1200.0, 620.0); (Engine.get_main_loop() as SceneTree).root.add_child(body)
	var controller := InventoryWorkspaceController.new(); var intents: Array[PlayerIntent] = []; var back_requests := [0]
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	controller.back_requested.connect(func() -> void: back_requests[0] += 1)
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); controller.present(body, view, media, 1.0); await (Engine.get_main_loop() as SceneTree).process_frame
	var buttons := _base_buttons_in(body); var ledger_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	assert_true(buttons.any(func(button: BaseButton) -> bool: return button is Button and (button as Button).text.contains("Longsword") and (button as Button).theme_type_variation == &"ClassicItemLedgerButton") and ledger_theme.get_color(&"font_hover_pressed_color", &"ClassicItemLedgerButton") == Color(0.34, 0.25, 0.02, 1) and (body.find_child("InventoryItemBrowser", true, false) as PanelContainer).theme_type_variation == &"ClassicItemLedger" and (body.find_child("InventoryItemLineFact", true, false) as Label).text == "Damage 1–10", "inventory renders selectable carried items with dark selected-hover text and detached Classic line facts on the paper-white Black Chancery ledger")
	var item_scroll := body.find_child("InventoryItemScroll", true, false) as ScrollContainer; item_scroll.scroll_vertical = mini(120, int(item_scroll.get_v_scroll_bar().max_value - item_scroll.get_v_scroll_bar().page)); await (Engine.get_main_loop() as SceneTree).process_frame; var retained_scroll := item_scroll.scroll_vertical; var item_buttons := _buttons_in(body).filter(func(button: Button) -> bool: return button.name.begins_with("InventoryItem_")); item_buttons[-1].pressed.emit(); controller.present(body, view, media, 1.0); await (Engine.get_main_loop() as SceneTree).process_frame; var restored_scroll := body.find_child("InventoryItemScroll", true, false) as ScrollContainer; assert_true(retained_scroll > 0 and restored_scroll.scroll_vertical == retained_scroll, "selecting an item refreshes its exact detail and actions without returning the carried-item ledger to the top"); (body.find_child("InventoryItem_inventory_item", true, false) as Button).pressed.emit(); controller.present(body, view, media, 1.0); await (Engine.get_main_loop() as SceneTree).process_frame; buttons = _base_buttons_in(body)
	var inventory_popover := body.find_child("ClassicItemDetailPopover", true, false); inventory_popover.set("modifier_active", true); (body.find_child("InventoryItem_inventory_item", true, false) as Control).mouse_entered.emit(); var item_inspector := body.find_child("InventoryItemInspector", true, false) as Control; var inventory_done := body.find_child("InventoryDone", true, false) as Button; assert_true(["CastleInventoryMainSplit", "InventoryItemBrowser", "InventoryCharacterCommandRail", "InventoryCharacterFacts", "InventoryActionDock", "InventoryCharacterSelector", "InventoryItemInspector", "InventorySelectedItemRecord"].all(func(node_name: String) -> bool: return body.find_child(node_name, true, false) != null) and item_inspector.is_ancestor_of(inventory_done) and (inventory_popover.find_child("ClassicItemDetailPanel", true, false) as PanelContainer).visible and (inventory_popover.find_child("ClassicItemDetailTitle", true, false) as Label).text == "Longsword" and (inventory_popover.find_child("ClassicItemDetailDescription", true, false) as Label).text == "A balanced sword.", "inventory follows Castle's hierarchy, keeps Done inside the lower item record, and exposes only its detached item record in the shared Alt-hover pane"); inventory_done.pressed.emit(); assert_equal(back_requests[0], 1, "the record-integrated Inventory Done action follows the controller's ordinary Back path"); assert_true(buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text == "Equip"), "inventory exposes the typed Equip action"); assert_true(body.find_children("ContentImage", "TextureRect", true, false).size() == source_view.items.size() + 2 and body.find_children("ContentImage", "TextureRect", true, false).all(func(image: TextureRect) -> bool: return image.custom_minimum_size.x > 0.0) and body.find_children("ContentImageUnavailable", "Label", true, false).is_empty(), "inventory keeps each exact item image visibly sized in the list, record, and transient detail without exposing a variable-width resource ID")
	var split_action := buttons.filter(func(button: BaseButton) -> bool: return button.tooltip_text == "Split" and not button.disabled)[0] as ClassicBitmapButton; assert_true(split_action != null and split_action.custom_minimum_size == Vector2(62.0, 56.0) and buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text == "Join" and not button.disabled) and buttons.any(func(button: BaseButton) -> bool: return button.tooltip_text.contains("not implemented")), "inventory exposes core-authorized stack actions and source-owned unavailable reasons on one text-led Rebuilt slate button geometry"); split_action.command_requested.emit(&"inventory.action.split"); controller.present(body, view, media, 1.0)
	assert_true(body.find_child("InventoryOperationStage", true, false) != null and _labels_in(body).any(func(text: String) -> bool: return text.contains("Split this charged record")), "one stable operation stage keeps exact item facts and conservative consequence copy")
	var cancel_operation := _buttons_in(body.find_child("InventoryOperationActions", true, false)).filter(func(button: Button) -> bool: return button.text == "Cancel")[0] as Button; cancel_operation.pressed.emit(); controller.present(body, view, media, 1.0); buttons = _base_buttons_in(body); var trade := buttons.filter(func(button: BaseButton) -> bool: return button.tooltip_text == "Open the two-pack Trade workspace")[0] as ClassicBitmapButton; trade.command_requested.emit(&"inventory.action.trade"); controller.present(body, view, media, 1.0); var destination_ledger := body.find_child("InventoryTradeLedger_destination", true, false); var source_ledger := body.find_child("InventoryTradeLedger_source", true, false); var trade_rows := _buttons_in(body).filter(func(button: Button) -> bool: return button.name.begins_with("InventoryTradeItem_")); assert_true(body.find_child("InventoryTradeLedgers", true, false) != null and body.find_child("InventoryTradeDivider", true, false) != null and body.find_child("InventoryTradePortraitMatrix", true, false).get_child_count() == view.party_members.size() * 2 and body.find_child("InventoryTradeActions", true, false) == null and trade_rows.all(func(button: Button) -> bool: return not button.toggle_mode and not button.button_pressed) and destination_ledger.call("_can_drop_data", Vector2.ZERO, {"kind": &"inventory-trade-item", "sourceId": source.id, "instanceId": item_view.instance_id}), "Trade presents two tall white ledgers, independent duplicated portrait selectors, no selected first row, and no click-transfer fallback"); destination_ledger.call("_drop_data", Vector2.ZERO, {"kind": &"inventory-trade-item", "sourceId": source.id, "instanceId": item_view.instance_id}); source_ledger.call("_drop_data", Vector2.ZERO, {"kind": &"inventory-trade-item", "sourceId": destination.id, "instanceId": destination_item_view.instance_id})
	assert_equal([intents.size(), intents[0].kind, intents[0].payload.actor_id, intents[0].payload.destination_character_id, intents[1].payload.actor_id, intents[1].payload.destination_character_id], [2, PlayerIntent.Kind.TRADE_ITEM, source.id, destination.id, destination.id, source.id], "dragging either direction emits exact bidirectional typed transfers without closing the workspace")
	body.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame
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
	controller.present(body, view, ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()))
	var buttons := _buttons_in(body)
	var labels := _labels_in(body)
	var pool_pane := body.find_child("MoneyPoolPane", true, false) as PanelContainer; var party_pane := body.find_child("MoneyPartyPane", true, false) as PanelContainer; var swap_pane := body.find_child("MoneySwapPane", true, false) as PanelContainer; var wealth_icons := body.find_children("Money*Icon", "ClassicContentIcon", true, false); var theme := load("res://src/presentation/classic_ui_theme.tres") as Theme; assert_true(pool_pane != null and party_pane != null and swap_pane != null and body.find_child("MoneyPoolSummary", true, false) != null and body.find_child("MoneyExchangeWorkspace", true, false) != null and body.find_child("MoneySelectedSummary", true, false) != null and pool_pane.theme_type_variation == &"ClassicInset" and party_pane.theme_type_variation == &"ClassicInset" and swap_pane.theme_type_variation == &"ClassicInset" and ["Gold", "Gems", "Jewelry", "15"].all(func(text: String) -> bool: return labels.has(text)) and wealth_icons.size() == 9 and wealth_icons.all(func(icon: Node) -> bool: return icon.find_child("ContentImage", true, false) != null) and _buttons_in(party_pane).all(func(button: Button) -> bool: return button.theme_type_variation == &"ClassicMoneyLedgerButton") and theme.get_color(&"font_color", &"ClassicMoneyLedgerButton").get_luminance() > 0.75 and theme.get_color(&"font_pressed_color", &"ClassicMoneyLedgerButton").get_luminance() > 0.65 and [ServicesWorkspaceController.wealth_resource_id(&"gold"), ServicesWorkspaceController.wealth_resource_id(&"gems"), ServicesWorkspaceController.wealth_resource_id(&"jewelry")] == [2002, 2011, 2012], "money workspace uses slate-readable ledger chrome and exact Classic gold, gem, and jewelry art across its pool, selected-character, and transfer records")
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
	character.gender = 2; character.level = 7; character.race_id = "classic.race.1"; character.caste_id = "classic.caste.2"; character.prestige_penalty = 4; character.lifetime_record.add_damage_given(44, true, true); character.lifetime_record.add_damage_taken(4, true); character.lifetime_record.record_spell_cast()
	var view := CharacterView.new(character)
	view.items = [ItemView.new(ItemInstance.new("equipped-sword", "classic.item.1", 0, true, true), ItemDefinition.new("classic.item.1", 1, "Longsword", "Sword")), ItemView.new(ItemInstance.new("carried-torch", "classic.item.805", 6, false, true), ItemDefinition.new("classic.item.805", 805, "Torch", "Equipment"))]; assert_equal(view.gender_name, "Female", "the detached sheet preserves Classic identity")
	var sheet := ClassicCharacterSheet.new(); sheet.present([view], view.id, {}, 1.0, &"equipment", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT)
	for label: String in ["Overview", "Conditions & Saves", "Equipment", "Abilities", "Spells", "Appearance", "Race, Caste & Aging", "Lifetime Record"]: assert_true(_buttons_in(sheet).any(func(button: Button) -> bool: return button.text == label), "sheet exposes %s" % label)
	assert_true(sheet.find_child("EquippedItems", true, false) != null and sheet.find_child("CarriedItems", true, false) != null, "equipment separates exact equipped instances from the carried pack in compact composition")
	sheet.present([view], view.id, {}, 1.0, &"overview", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(["OverviewAttributes", "OverviewCombat", "OverviewStatus"].all(func(node_name: String) -> bool: return sheet.find_child(node_name, true, false) != null), "overview keeps identity, combat, and resource records in three stable wide regions")
	sheet.present([view], view.id, {}, 1.0, &"conditions", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT); assert_true(sheet.find_child("ConditionsRegion", true, false) != null and sheet.find_child("SavingThrowsRegion", true, false) != null, "conditions and all saving throws retain separate compact records")
	sheet.present([view], view.id, {}, 1.0, &"abilities", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(sheet.find_child("SpecialModifiersRegion", true, false) != null and sheet.find_child("SpecialAbilitiesRegion", true, false) != null, "special modifiers and abilities retain separate wide records"); sheet.present([view], view.id, {}, 1.0, &"background", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(["RaceRegion", "CasteRegion", "AgingRegion"].all(func(node_name: String) -> bool: return sheet.find_child(node_name, true, false) != null), "race, caste, and aging retain separate source-backed records"); sheet.present([view], view.id, {}, 1.0, &"spells", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); assert_true(sheet.find_child("KnownSpellRegion", true, false) != null and sheet.find_child("ScrollCaseRegion", true, false) != null, "known spells and the fixed scroll case retain separate records"); sheet.present([view], view.id, {}, 1.0, &"appearance", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.COMPACT); assert_true(sheet.find_child("PortraitAppearanceRegion", true, false) != null and sheet.find_child("CombatIconAppearanceRegion", true, false) != null and sheet.find_child("DiscardAppearanceChanges", true, false) != null, "appearance preserves two independent exact-media roles and one local discard action"); sheet.present([view], view.id, {}, 1.0, &"record", [], [], ActionAvailabilityView.new(&"change_character_appearance", true), null, UiLayoutProfile.WIDE); var restored_record := CharacterState.from_data(JSON.parse_string(JSON.stringify(character.to_data()))); assert_true(sheet.find_child("LifetimeRecord", true, false) != null and view.prestige == -3 and restored_record.lifetime_record.to_data() == character.lifetime_record.to_data(), "the detached sheet shows Castle prestige from typed lifetime counters and the complete record survives serialization")
	sheet.free()
func _test_scene_composition() -> void:
	var scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell.get_node_or_null("ScreenRouter"), "the shell owns one workspace router"); assert_true(shell.get_node_or_null("BottomRegion/BottomRow/NarrativeWell") != null and shell.get_node_or_null("ActivityIndicator/ActivityIconCenter/ActivityIcon") is TextureRect and (shell.get_node("ScreenRouter") as Control).z_index > (shell.get_node("BottomRegion") as Control).z_index, "the shell keeps its narrative well beneath routed side workspaces and owns one separate transient activity-glyph surface")
	assert_true(["WorldCommandHeading", "CommandHeading", "EffectsHeading"].all(func(node_name: String) -> bool: return shell.find_child(node_name, true, false) == null), "the exploration footer presents Adventure, Party, and Effects controls without redundant section titles")
	assert_true(shell.get_node_or_null("BottomRegion/BottomRow/WorldCommandPanel") != null and shell.get_node_or_null("BottomRegion/BottomRow/CommandPanel") != null and shell.find_child("Light", true, false) != null and shell.find_child("FatigueBar", true, false) is ProgressBar and [(shell.find_child("FatigueBar", true, false) as ProgressBar).min_value, (shell.find_child("FatigueBar", true, false) as ProgressBar).max_value, (shell.find_child("FatigueBar", true, false) as ProgressBar).show_percentage] == [4.0, 135.0, false], "exploration dedicates separate footer panes to world and party commands while surfacing typed light state and Castle's bounded fatigue gauge")
	var party_effects_row := shell.find_child("PartyEffectsRow", true, false) as BoxContainer; var party_command_column := shell.find_child("PartyCommandColumn", true, false) as VBoxContainer; var effects_panel := shell.find_child("EffectsPanel", true, false) as PanelContainer; var effects_grid := shell.find_child("EffectsGrid", true, false) as GridContainer; assert_true(party_effects_row != null and not party_effects_row.vertical and party_command_column != null and party_command_column.get_parent() == party_effects_row and effects_panel.get_parent() == party_effects_row and party_command_column.get_index() < effects_panel.get_index() and effects_panel.size_flags_horizontal == Control.SIZE_SHRINK_CENTER and effects_panel.size_flags_vertical == Control.SIZE_SHRINK_CENTER and effects_grid.columns == 4 and [ClassicApplicationShell.party_effect_icon_size(1), ClassicApplicationShell.party_effect_icon_size(2)] == [32.0, 64.0] and [ClassicApplicationShell.party_effect_slot_size(1), ClassicApplicationShell.party_effect_slot_size(2)] == [36.0, 68.0] and [ClassicApplicationShell.party_effect_resource_id(1, 0), ClassicApplicationShell.party_effect_resource_id(8, 7)] == [14000, 14063] and ClassicApplicationShell.HELD_COMMAND_INTERVAL <= 1.0 / 60.0, "the wide Party footer places a compact 2-by-2 command block left of Castle's native-pixel 4-by-2 animated effects bank while held Rest/Area Search retain one-tick non-catching-up cadence")
	var exploration_commands := ClassicCommandCatalog.for_context(&"exploration"); assert_true([&"search_mode", &"contextual", &"camp", &"heal"].all(func(id: StringName) -> bool: return exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == id and definition["group"] == &"world")) and ClassicCommandCatalog.command(&"camp")["asset_id"] == &"command.camp" and ClassicCommandCatalog.command(&"camp")["art_region"] == [9, 3, 32, 33] and ClassicCommandCatalog.command(&"contextual")["asset_id"] == &"command.encounter_original" and ClassicCommandCatalog.command(&"contextual")["art_mask"] == &"circle" and ClassicUiAssetCatalog.definition(&"command.shop_original").get("source_resource_id", -1) == 225 and ClassicUiAssetCatalog.texture(&"command.shop_original") != null and load("res://src/presentation/assets/ui/commands/shop.png") is Texture2D and ClassicCommandCatalog.command(&"heal")["asset_path"] == "res://src/presentation/assets/ui/commands/heal.png" and ClassicCommandCatalog.command(&"heal")["art_region"] == [13, 18, 47, 40] and ClassicCommandCatalog.command(&"heal")["hold_repeat"] and not ClassicApplicationShell.should_stop_held_command_on_button_up(true) and ClassicApplicationShell.should_stop_held_command_on_button_up(false) and [ClassicApplicationShell.command_route(&"money"), ClassicApplicationShell.command_route(&"inventory"), ClassicApplicationShell.command_route(&"spells"), ClassicApplicationShell.command_route(&"maps")].all(func(route: StringName) -> bool: return not route.is_empty()), "World and Party controls separate exact or app-owned command art from live captions while retaining stable routes and pressed identities"); assert_equal([ClassicApplicationShell.command_activation_sound_id(&"rest", false), ClassicApplicationShell.command_activation_sound_id(&"area_search", false), ClassicApplicationShell.command_activation_sound_id(&"rest", true), ClassicApplicationShell.command_activation_sound_id(&"contextual", false)], [6001, 6001, 0, 141], "held Rest and Area Search request Castle sound 6001 once while Castle's shared contextual control requests sound 141 on activation")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"settings" and definition["group"] == &"world"), "preferences remain with Adventure and system controls instead of displacing party actions")
	assert_true(exploration_commands.any(func(definition: Dictionary) -> bool: return definition["id"] == &"inventory" and definition["group"] == &"party"), "party workspaces remain grouped beside the narrative well")
	var world_panel := shell.get_node("BottomRegion/BottomRow/WorldCommandPanel") as Control
	var narrative_well := shell.get_node("BottomRegion/BottomRow/NarrativeWell") as Control
	var party_panel := shell.get_node("BottomRegion/BottomRow/CommandPanel") as Control
	var world_frame := shell.find_child("WorldCommandDeckFrame", true, false) as PanelContainer; var party_frame := shell.find_child("CommandDeckFrame", true, false) as PanelContainer; var world_grid := shell.find_child("WorldCommandGrid", true, false) as GridContainer; var party_grid := shell.find_child("CommandGrid", true, false) as GridContainer; assert_equal([world_panel.size_flags_horizontal, narrative_well.size_flags_horizontal, party_panel.size_flags_horizontal, world_grid.size_flags_horizontal, party_grid.size_flags_horizontal, party_grid.columns], [Control.SIZE_EXPAND_FILL, Control.SIZE_EXPAND_FILL, Control.SIZE_EXPAND_FILL, Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_CENTER, 2], "the wide footer expands two equal command regions around the wider narrative and centers its 4-by-2 Adventure and 2-by-2 Party button grids"); assert_true(is_equal_approx(world_panel.size_flags_stretch_ratio, party_panel.size_flags_stretch_ratio) and narrative_well.size_flags_stretch_ratio > world_panel.size_flags_stretch_ratio and world_frame.theme_type_variation == &"ClassicFooterCommandWell" and party_frame.theme_type_variation == &"ClassicFooterCommandWell" and shell.find_child("WorldCommandDeckCenter", true, false) is CenterContainer and shell.find_child("CommandDeckCenter", true, false) is CenterContainer and exploration_commands.filter(func(definition: Dictionary) -> bool: return definition.get("group", &"party") == &"world").size() == 8 and exploration_commands.filter(func(definition: Dictionary) -> bool: return definition.get("group", &"party") == &"party").size() == 4, "Adventure and Party use tight content-sized inset frames around complete centered command groups while the narrative receives the wider share")
	assert_equal(RealmzApplication.classic_textbox_rect(Rect2(0.0, 32.0, 992.0, 498.0), 190.0, 1280.0), Rect2(0.0, 530.0, 1280.0, 190.0), "the application retains one full-width fallback until the shell's exact narrative well settles")
	var backing := shell.get_node("PictureStage/PictureBacking") as TextureRect; var roster := shell.get_node("PartyRoster") as PanelContainer; var picture_caption := shell.get_node("PictureStage/PictureMargin/PictureColumn/PictureCaption") as Label
	assert_true(backing.stretch_mode == TextureRect.STRETCH_TILE and not picture_caption.visible and roster.theme_type_variation == &"ClassicInset" and [shell.get_node("PictureStage"), shell.get_node("PictureStage/PictureMargin"), shell.get_node("PictureStage/PictureMargin/PictureColumn"), shell.get_node("PictureStage/PictureMargin/PictureColumn/Picture")].all(func(node: Node) -> bool: return (node as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE), "picture presentation uses owned Classic framing, exposes no package media IDs, and passes the next exploration input through to dismiss it by committed movement")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(1280, 720)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size); var spell_rect := ClassicScreenRouter.spell_workspace_rect_for(profile, viewport_size); var expected_spell_width := (288.0 if profile.id == UiLayoutProfile.COMPACT else 420.0) * profile.ui_scale
		assert_true(rect.position.x >= 0.0 and rect.end.x <= viewport_size.x - profile.party_width and spell_rect == Rect2(viewport_size.x - expected_spell_width, profile.menu_height, expected_spell_width, viewport_size.y - profile.menu_height) and ClassicApplicationShell.exploration_footer_width(viewport_size, profile, &"spells") == spell_rect.position.x and ClassicApplicationShell.exploration_footer_width(viewport_size, profile, &"exploration") == viewport_size.x, "field spellcasting owns the complete right edge while the footer ends at its left edge at %s" % viewport_size)
	assert_equal([ClassicApplicationShell.party_roster_height(720.0, 28.0, 502.0, true), ClassicApplicationShell.party_roster_z_index(true)], [692.0, 81], "combat spellcasting expands above the inert Party-command footer and owns the complete right rail"); assert_equal([ClassicApplicationShell.party_roster_height(720.0, 28.0, 502.0, false), ClassicApplicationShell.party_roster_z_index(false)], [502.0, 14], "closing the combat spellbook restores the ordinary six-character roster stage"); assert_equal([ClassicApplicationShell.combat_spellbook_roster_width(800.0, 208.0, 1.0, true), ClassicApplicationShell.combat_spellbook_roster_width(800.0, 208.0, 1.0, false), ClassicApplicationShell.combat_spellbook_roster_width(1280.0, 352.0, 1.0, true), ClassicApplicationShell.combat_spellbook_stage_width(592.0, 800.0, 352.0), ClassicApplicationShell.combat_spellbook_stage_width(928.0, 1280.0, 352.0)], [352.0, 208.0, 352.0, 448.0, 928.0], "combat spellcasting overlays enough of the compact battlefield to keep its complete selector and all targeting actions inside the viewport, then restores the ordinary roster width")
	var modal_parent := Control.new(); var modal_presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter; modal_parent.add_child(modal_presenter); var textbox_overlay_style := InteractionLayoutPolicyScript.textbox_theme_variation(); var combat_footer_style := InteractionLayoutPolicyScript.textbox_theme_variation(ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)); modal_presenter.call("_update_modal_shield", true); var modal_shield := modal_parent.get_node("LockedModalShield") as Control; var first_order := [modal_shield.get_index(), modal_presenter.get_index()]; modal_presenter.call("_update_modal_shield", true); var repeated_order := [modal_shield.get_index(), modal_presenter.get_index()]; var floating_choice_rect := InteractionLayoutPolicyScript.floating_choice_rect(Rect2(0.0, 28.0, 992.0, 502.0), Rect2(286.0, 530.0, 620.0, 190.0), Vector2(286.0, 46.0)); var compact_choice_rect := InteractionLayoutPolicyScript.floating_choice_rect(Rect2(0.0, 28.0, 592.0, 410.0), Rect2(10.0, 438.0, 780.0, 162.0), Vector2(286.0, 46.0)); assert_true(textbox_overlay_style == &"ClassicTextboxOverlay" and combat_footer_style == &"ClassicOpenRight" and first_order[0] < first_order[1] and repeated_order[0] < repeated_order[1] and repeated_order == first_order and InteractionLayoutPolicyScript.uses_floating_choice_modal(InteractionRequest.yes_no("floating-choice", "Do you follow him?", "Yes", "No")) and floating_choice_rect.end.y <= 522.0 and floating_choice_rect.size == Vector2(520.0, 116.0) and compact_choice_rect.end.x <= 582.0 and compact_choice_rect.end.y <= 430.0, "narrative interactions use one opaque textbox surface, combat exposes the textured command slate, locked modals retain pointer order, and AP choices stay together above the narrative region in both supported profiles"); var flash_sounds: Array[int] = []; modal_presenter.presentation_sound_requested.connect(func(sound_id: int) -> void: flash_sounds.append(sound_id)); modal_presenter.queue_classic_flash_messages([{"text": "Map one", "soundId": 30005}, {"text": "Map two", "soundId": 30005}, {"text": "Map three", "soundId": 30005}]); var flash_panel := modal_parent.find_child("ClassicFlashMessage", true, false) as PanelContainer; var flash_continue := modal_parent.find_child("ClassicFlashContinue", true, false) as Button; flash_continue.pressed.emit(); var second_flash := modal_parent.find_child("ClassicFlashMessage", true, false) as PanelContainer; var second_text := (modal_parent.find_child("ClassicFlashText", true, false) as Label).text; flash_continue.pressed.emit(); var third_flash := modal_parent.find_child("ClassicFlashMessage", true, false) as PanelContainer; assert_true(flash_panel == second_flash and second_flash == third_flash and third_flash.size == Vector2(520.0, 118.0) and second_text == "Map two" and (modal_parent.find_child("ClassicFlashText", true, false) as Label).text == "Map three" and flash_sounds == [30005, 30005, 30005], "source-owned flash messages reuse one compact ordered click boundary and play their cue once per displayed record"); modal_parent.free()
	var spatial_view := GameView.new(1, true, null); var locked_dungeon := MapView.new("dungeon:test", "Locked Dungeon", &"dungeon", 1, 1, Vector2i.ZERO, [], false, [], {}, Vector2i.ZERO, -1, 1, false, false, -1, true, true); spatial_view.party_map_id = locked_dungeon.map_id; spatial_view.map_view = locked_dungeon; assert_true(PresentationCoordinator.should_show_exploration_stage(&"spells", spatial_view, true) and not PresentationCoordinator.dungeon_view_toggle_available(locked_dungeon) and ClassicApplicationShell.location_fact_text(spatial_view) == "dungeon:test • ?,? • Compass N", "field Spells preserves the live exploration renderer, a locked dungeon requires Wizard's Eye before Space exposes the overhead view, and authored coordinate/compass flags alter only their footer facts"); locked_dungeon.wizard_eye_active = true; locked_dungeon.coordinates_hidden = false; locked_dungeon.compass_enabled = false; assert_true(PresentationCoordinator.dungeon_view_toggle_available(locked_dungeon) and ClassicApplicationShell.location_fact_text(spatial_view) == "dungeon:test • 0,0", "Wizard's Eye restores Castle's overhead-view toggle while a disabled compass leaves the exact coordinates visible without a direction fact"); shell.free()
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
	var move_intent := RealmzApplication.direct_combat_intent(move_body); assert_equal([move_intent.kind, move_intent.payload.actor_id, move_intent.payload.destination, move_intent.payload.auto_switch_to_melee], [PlayerIntent.Kind.COMBAT_MOVE, "character.route", Vector2i(4, 7), true], "the direct command deck submits the same typed combat-move intent and host preference as battlefield input"); var summon_item_body := InteractionResponse.CombatBody.new(&"use_item", "character.route"); summon_item_body.item_instance_id = "instance.summon"; summon_item_body.target_coordinates.assign([Vector2i(44, 46), Vector2i(43, 46)]); var summon_item_intent := RealmzApplication.direct_combat_intent(summon_item_body); assert_equal([summon_item_intent.kind, summon_item_intent.payload.item_id, summon_item_intent.payload.target_coordinates], [PlayerIntent.Kind.USE_ITEM_ON_TARGET, "instance.summon", [Vector2i(44, 46), Vector2i(43, 46)]], "the direct item route preserves ordered summon anchors through its typed intent")
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
