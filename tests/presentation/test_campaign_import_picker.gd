extends "res://tests/presentation/classic_ui_test_support.gd"

func run() -> void:
	await _test_startup_shell()
	await _test_campaign_import_states()
	await _test_removal_compositor_input()


func _test_removal_compositor_input() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var compositor := instantiate_ui_scene("res://src/ui/shared/display_compositor.tscn") as DisplayCompositor
	compositor.get_node("Content/StartupFrontDoor").free()
	compositor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	compositor.size = Vector2(2560, 1440)
	tree.root.add_child(compositor)
	await tree.process_frame
	var panel := instantiate_ui_scene("res://src/ui/setup/campaign_selection_panel.tscn") as Control
	compositor.source_viewport().add_child(panel)
	panel.size = Vector2(400, 650)
	var dialog := panel.get_node("%RemoveScenarioDialog") as CampaignRemovalDialog
	var removals: Array[String] = []
	dialog.removal_confirmed.connect(func(id: String) -> void: removals.append(id))
	var background := panel.get_node("%ImportScenario") as Button
	var background_clicks: Array[int] = [0]
	background.pressed.connect(func() -> void: background_clicks[0] += 1)
	for mode: String in [PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.DISPLAY_INTEGER_WINDOW]:
		compositor.configure(mode, PresentationSettings.SMOOTHING_OFF)
		for action: String in ["cancel", "escape", "close", "outside", "confirm"]:
			dialog.present("fixture-import", "Fixture import")
			await tree.process_frame
			await tree.process_frame
			if action == "escape":
				var key := InputEventKey.new()
				key.keycode = KEY_ESCAPE
				key.pressed = true
				Input.parse_input_event(key)
				await tree.process_frame
				key = key.duplicate()
				key.pressed = false
				Input.parse_input_event(key)
				await tree.process_frame
			else:
				var point := Vector2(dialog.position) + dialog.get_cancel_button().get_global_rect().get_center()
				if action == "confirm": point = Vector2(dialog.position) + dialog.get_ok_button().get_global_rect().get_center()
				if action == "outside": point = background.get_global_rect().get_center()
				if action == "close": point = Vector2(dialog.position) + Vector2(dialog.size.x - dialog.get_theme_constant("close_h_offset"), -dialog.get_theme_constant("close_v_offset"))
				await _send_window_click(compositor.logical_to_window_rect(Rect2(point, Vector2.ONE)).position)
			await tree.process_frame
			assert_false(dialog.visible, "%s dismisses removal through the %s compositor input path" % [action, mode])
			dialog.hide()
		assert_equal(background_clicks[0], 0, "outside dismissal never activates the covered scenario controls")
	assert_equal(removals, ["fixture-import", "fixture-import"], "only the confirmation clicks remove a campaign, once per click")
	await _send_window_click(compositor.logical_to_window_rect(background.get_global_rect()).get_center())
	assert_equal(background_clicks[0], 1, "scenario controls respond again after the confirmation closes")
	compositor.queue_free()
	await tree.process_frame


func _send_window_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await (Engine.get_main_loop() as SceneTree).process_frame
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await (Engine.get_main_loop() as SceneTree).process_frame

func _test_startup_shell() -> void:
	var front_door := load("res://src/ui/setup/startup_front_door.tscn").instantiate() as StartupFrontDoor; (Engine.get_main_loop() as SceneTree).root.add_child(front_door); await (Engine.get_main_loop() as SceneTree).process_frame; var classic_startup := SettingsRepository.new().load_settings().typography_mode == PresentationSettings.TYPOGRAPHY_CLASSIC; var expected_heading := load(ClassicTypography.BLACK_CHANCERY_PATH if classic_startup else ClassicTypography.READABLE_BOLD_PATH) as Font; var expected_body := load(ClassicTypography.THELDROW_PATH if classic_startup else ClassicTypography.READABLE_UI_PATH) as Font; var startup_image := front_door.find_child("StartupSplash", true, false) as TextureRect; var startup_background := front_door.find_child("StartupSplashBackground", true, false) as ColorRect; var startup_timer := front_door.find_child("StartupDuration", true, false) as Timer; var exit_timer := front_door.find_child("SplashExitDelay", true, false) as Timer; var transition_audio := front_door.find_child("StartupLaunchTransition", true, false) as AudioStreamPlayer; var transition_stream := transition_audio.stream as AudioStreamWAV; var launch_music := front_door.find_child("StartupLaunchMusic", true, false) as AudioStreamPlayer; var startup_choose := front_door.find_child("ChooseScenario", true, false) as Button; assert_true(startup_image.visible and startup_background.visible and startup_background.color == Color.BLACK and startup_image.texture.resource_path == "res://src/ui/shared/assets/ui/intro/rebuilt-launch-splash.jpg" and startup_image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and is_equal_approx(startup_timer.wait_time, 3.0) and is_equal_approx(exit_timer.wait_time, 1.513) and not startup_timer.is_stopped() and transition_audio.stream.resource_path.ends_with("snd-624.wav") and transition_stream != null and transition_stream.format == AudioStreamWAV.FORMAT_16_BITS and not transition_stream.stereo and transition_stream.mix_rate == 48000 and launch_music.stream.resource_path.ends_with("snd-20.wav") and startup_choose.disabled and (front_door.find_child("LoadAdventure", true, false) as Button).disabled and (front_door.find_child("CharacterFiles", true, false) as Button).disabled and not (front_door.find_child("Quit", true, false) as Button).disabled and not (front_door.find_child("StartupFailure", true, false) as Control).visible and front_door.find_child("LoadingStatus", true, false) == null, "the lightweight front door immediately reveals its supplied launch card and first Castle-rendered source-backed cue together over opaque black, holds for three seconds before the exit cue, and exposes no routine loading caption while keeping only Quit available"); assert_equal([(front_door.find_child("SplashTitle", true, false) as Label).get_theme_font(&"font").get_font_name(), startup_choose.get_theme_font(&"font").get_font_name(), (front_door.find_child("StartupFailureMessage", true, false) as Label).get_theme_font(&"font").get_font_name()], [expected_heading.get_font_name(), expected_heading.get_font_name() if classic_startup else expected_body.get_font_name(), expected_body.get_font_name()], "the process front door applies the saved shared typography roles before constructing the main menu")
	while not front_door.application_ready(): await (Engine.get_main_loop() as SceneTree).process_frame
	var retail_host := front_door.get("_startup_diagnostics") as DebugToolsHost; retail_host.set("_developer_tools_enabled", false); (front_door.find_child("DebugToolsDialog", true, false) as DebugToolsDialog).configure_capabilities(false); var front_door_f12 := InputEventKey.new(); front_door_f12.physical_keycode = KEY_F12; front_door_f12.pressed = true; front_door.call("_input", front_door_f12); var startup_diagnostics := front_door.find_child("DebugToolsDialog", true, false) as DebugToolsDialog; assert_true(startup_diagnostics != null and startup_diagnostics.visible, "a raw physical F12 opens the retail diagnostics surface while the front door still owns input"); front_door.call("_input", front_door_f12); assert_true(startup_diagnostics.visible, "a repeated or polled key-down cannot immediately close the diagnostics surface"); var front_door_f12_release := InputEventKey.new(); front_door_f12_release.physical_keycode = KEY_F12; front_door_f12_release.pressed = false; front_door.call("_input", front_door_f12_release); front_door.call("_input", front_door_f12); assert_false(startup_diagnostics.visible, "a released and pressed raw F12 closes the shared diagnostics surface before application handoff"); await (Engine.get_main_loop() as SceneTree).process_frame
	var loaded_application := front_door.get("_application") as Control; var owned_intro_candidates: Array[Node] = front_door.find_children("RealmzIntroAnimation", "ClassicIntroAnimation", true, false); owned_intro_candidates.append_array(loaded_application.find_children("RealmzIntroAnimation", "ClassicIntroAnimation", true, false)); var prepared_front_door_intro := front_door.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation; var prepared_decoder_count := owned_intro_candidates.filter(func(candidate: Node) -> bool: return (candidate as ClassicIntroAnimation).resources_prepared()).size()
	assert_equal([front_door.application_ready(), prepared_front_door_intro != null, prepared_front_door_intro.resources_prepared() if prepared_front_door_intro != null else false, prepared_front_door_intro.playback_active() if prepared_front_door_intro != null else false, prepared_front_door_intro.preparation_count() if prepared_front_door_intro != null else -1, prepared_decoder_count], [true, true, true, true, 1, 1], "background application construction leaves exactly one retained intro decoder running behind the opaque launch card"); startup_timer.stop(); startup_timer.timeout.emit(); exit_timer.stop(); exit_timer.timeout.emit(); await (Engine.get_main_loop() as SceneTree).process_frame; assert_true(front_door.menu_visible() and prepared_front_door_intro.playback_active() and prepared_front_door_intro.preparation_count() == 1, "menu reveal exposes an already-playing decoded frame without reopening the OGV"); assert_false(loaded_application.is_processing_input(), "the hidden application cannot consume front-door controller events"); assert_equal(front_door.get_viewport().gui_get_focus_owner(), startup_choose, "the interactive front door gives controller focus to Choose a scenario"); var startup_navigation := InputEventJoypadButton.new(); startup_navigation.device = 0; startup_navigation.button_index = JOY_BUTTON_DPAD_DOWN; startup_navigation.pressed = true; front_door.get_viewport().push_input(startup_navigation); assert_equal(front_door.get_viewport().gui_get_focus_owner(), front_door.find_child("LoadAdventure", true, false), "viewport controller Down selects Load saved adventure"); startup_navigation.pressed = false; front_door.get_viewport().push_input(startup_navigation); startup_navigation.button_index = JOY_BUTTON_DPAD_UP; startup_navigation.pressed = true; front_door.get_viewport().push_input(startup_navigation); assert_equal(front_door.get_viewport().gui_get_focus_owner(), startup_choose, "viewport controller Up returns to Choose a scenario"); startup_navigation.pressed = false; front_door.get_viewport().push_input(startup_navigation); var startup_south := InputEventJoypadButton.new(); startup_south.device = 0; startup_south.button_index = JOY_BUTTON_A; startup_south.pressed = true; front_door.get_viewport().push_input(startup_south); assert_true(front_door.is_inside_tree() and not loaded_application.visible, "controller activation defers startup ownership transfer until the complete South-button event has settled"); await (Engine.get_main_loop() as SceneTree).process_frame; assert_true(loaded_application.visible and loaded_application.is_inside_tree(), "controller South enters the retained application through Choose a scenario without keyboard or pointer input"); startup_south.pressed = false; loaded_application.get_viewport().push_input(startup_south); await (Engine.get_main_loop() as SceneTree).process_frame; assert_true((loaded_application as RealmzApplication).get_node("GameShell").navigator.setup_controller.setup_overlay.is_visible_in_tree(), "the viewport confirmation reaches scenario selection after the startup bridge consumes its route"); loaded_application.queue_free(); await (Engine.get_main_loop() as SceneTree).process_frame; await (Engine.get_main_loop() as SceneTree).process_frame; var router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator; (Engine.get_main_loop() as SceneTree).root.add_child(router); router.initialize()
	router.show_splash()
	var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(1280, 720))
	router.setup_controller.character_creation.set_standalone_character_creation_available(true)
	var splash := router.find_child("SplashScreen", true, false) as Control
	assert_true(splash != null and splash.visible, "Realmz Rebuilt opens on its application splash instead of dropping directly into package selection")
	assert_false(router.setup_controller.campaign_overlay.visible, "the campaign library waits for an explicit splash action")
	var choose_scenario := splash.find_child("ChooseScenario", true, false) as Button
	var character_files := splash.find_child("CharacterFiles", true, false) as Button; var load_adventure := splash.find_child("LoadAdventure", true, false) as Button
	var intro_animation := splash.find_child("RealmzIntroAnimation", true, false) as ClassicIntroAnimation; var intro_soundtrack := splash.find_child("RealmzIntroSoundtrack", true, false) as AudioStreamPlayer; assert_true(choose_scenario != null and load_adventure != null, "the splash exposes new and saved adventures as primary paths"); assert_true(splash.find_child("SplashIdentityPanel", true, false) != null and splash.find_child("SplashCommandPanel", true, false) != null and intro_animation != null and intro_animation.resources_prepared() and intro_animation.preparation_count() == 1 and intro_animation.playback_active() and not intro_animation.autoplay and intro_animation.loop and not intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, -80.0) and intro_soundtrack != null and not intro_soundtrack.autoplay and intro_soundtrack.stream == null and is_equal_approx(intro_soundtrack.volume_db, -80.0) and splash.find_child("RealmzIntroOrnament", true, false) is NinePatchRect and splash.find_child("SplashTitle", true, false) != null and splash.find_child("SplashSubtitle", true, false) != null and (splash.find_child("SplashComposition", true, false) as BoxContainer).vertical == false, "the canonical splash retains one already-playing silent video decoder while deferring its independent soundtrack until requested"); intro_animation.toggle_audio(); assert_true(intro_animation.audio_enabled and intro_soundtrack.stream is AudioStreamMP3 and (intro_soundtrack.stream as AudioStreamMP3).loop and is_equal_approx(intro_animation.volume_db, -80.0) and is_equal_approx(intro_soundtrack.volume_db, 0.0), "clicking the video loads and enables only the independent soundtrack at the current master level"); intro_animation.toggle_audio(); assert_true(not intro_animation.audio_enabled and is_equal_approx(intro_animation.volume_db, -80.0) and intro_soundtrack.stream is AudioStreamMP3 and is_equal_approx(intro_soundtrack.volume_db, -80.0), "clicking again mutes the retained soundtrack without enabling embedded video audio"); router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); await (Engine.get_main_loop() as SceneTree).process_frame; await (Engine.get_main_loop() as SceneTree).process_frame; assert_true(not (splash.find_child("SplashComposition", true, false) as BoxContainer).vertical and Rect2(Vector2.ZERO, Vector2(800, 600)).encloses((splash.get_node("%Quit") as Button).get_global_rect()), "the compact front door keeps identity beside every visible startup command, including Quit"); router.set_layout_profile(profile, Vector2(1280, 720))
	assert_not_null(character_files, "the splash exposes reusable character files independently of party setup")
	choose_scenario.pressed.emit()
	var setup_workspace := router.find_child("PartySetup", true, false) as Control
	var scenario_picker := router.find_child("ScenarioColumn", true, false) as Control
	if scenario_picker == null:
		scenario_picker = router.find_child("CampaignLibrary", true, false) as Control
	assert_true(setup_workspace != null and setup_workspace.visible and not splash.visible and intro_animation.resources_prepared() and not intro_animation.playback_active() and intro_animation.preparation_count() == 1 and intro_soundtrack.stream is AudioStreamMP3 and intro_soundtrack.stream_paused, "scenario selection suspends the retained intro resources without creating another decoder")
	assert_true(scenario_picker != null and setup_workspace != null and scenario_picker.visible and setup_workspace.is_ancestor_of(scenario_picker), "scenario selection is a left-column picker inside the integrated workspace, not an obsolete separate campaign modal")
	router.setup_controller.campaign_library.set_campaigns([
		CampaignPackageView.new("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2", true, "installed-scenario", "", "", "", "Installed Scenario"),
		CampaignPackageView.new("user://packages/stale.realmz2", false, "stale-scenario", "", "", "Package schema hash does not match the runtime contract mirror.", "Stale Scenario"),
	])
	var scenario_controls: Array[String] = _visible_control_texts(scenario_picker) if scenario_picker != null else []
	assert_true(router.setup_controller.campaign_list is VBoxContainer and router.setup_controller.campaign_list.get_parent() is ScrollContainer, "installed scenarios use one single-column picker surface")
	var stale_row := router.find_child("Scenario_stale-scenario", true, false) as Control
	var stale_launch: Button = stale_row.find_child("LaunchCampaign", true, false) as Button if stale_row != null else null
	assert_true(stale_launch != null and stale_launch.tooltip_text.contains("Package schema hash does not match the runtime contract mirror."), "incompatible installations remain inspectable with their exact readiness reason")
	assert_false(scenario_controls.any(func(text: String) -> bool: return text == "Play"), "scenario rows do not expose the obsolete per-row Play action")
	var install_dialog := router.find_child("InstallScenarioDialog", true, false) as FileDialog; assert_true(scenario_controls.any(func(text: String) -> bool: return text == "Install .realmz2") and install_dialog != null and install_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE and install_dialog.filters.has("*.realmz2 ; Realmz Rebuilt Scenario"), "the external package action opens a typed Realmz Rebuilt scenario picker")
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
	assert_true(router.full_stage_overlay_visible, "Character Files owns the complete stage instead of sharing it with the persistent roster")
	assert_equal(route_changes[-1], &"vault", "opening Character Files notifies the shell so it can suppress persistent play regions")
	assert_true(router.handle_back(), "Back closes the startup Character Files workspace through the public route lifecycle")
	assert_true(splash.visible and intro_animation.resources_prepared() and intro_animation.playback_active(), "closing startup Character Files restores the retained splash decoder and resumes playback"); var load_view := GameView.new(1, true, null); load_view.party_setup_available = true; load_view.campaign_id = "load-fixture"; load_view.rules_version = "realmz-classic-1"; load_view.campaign_summary = CampaignSummaryView.new(); load_adventure.pressed.emit(); router.present(load_view); assert_true(router.current_screen() == &"save_load" and router.find_child("LoadSelectedSave", true, false) != null and not _buttons_in(router).any(func(button: Button) -> bool: return button.text == "Quick Save"), "Load saved adventure selects a scenario and then opens package-validated restore records without offering a blocked setup save"); assert_true(router.handle_back() and router.setup_controller.setup_overlay.visible, "Back from pre-adventure saves returns to Begin Adventure"); (router.find_child("LoadSavedAdventure", true, false) as Button).pressed.emit(); assert_equal(router.current_screen(), &"save_load", "Begin Adventure exposes the same package-bound Save and Load workspace")
	router.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _test_campaign_import_states() -> void:
	var router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var library := router.setup_controller.campaign_library
	var main_campaign := CampaignPackageView.new("res://campaigns/main.realmz2", true, "main-campaign", "main-hash", "", "", "Main Campaign")
	main_campaign.origin = "main"
	var campaigns: Array[CampaignPackageView] = [main_campaign]
	for index in range(12):
		campaigns.append(CampaignPackageView.new("user://campaigns/imported-%02d.realmz2" % index, true, "imported-%02d" % index, "hash-%02d" % index, "", "", "Imported %02d" % index))
	campaigns[1].revisions = [{"package_hash": "hash-00", "version_label": "Author version 2"}, {"package_hash": "older-hash", "imported_at": ""}]
	var broken := CampaignPackageView.new("user://campaigns/broken.realmz2", false, "broken-campaign", "", "", "Required Data ED3 is missing from this scenario.", "Broken Campaign")
	campaigns.append(broken)
	library.set_campaigns(campaigns)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var main_rows := router.find_child("MainCampaignRows", true, false) as VBoxContainer
	var imported_rows := router.find_child("ImportedCampaignRows", true, false) as VBoxContainer
	var scroll := router.find_child("CampaignScroll", true, false) as ScrollContainer
	assert_true(main_rows != null and main_rows.get_child_count() == 1 and imported_rows != null and imported_rows.get_child_count() == 13, "main scenarios keep their own group while imported campaigns include every installed row")
	library.select_imported_package(campaigns[1].path)
	var panel := library.campaign_overlay as CampaignSelectionPanel
	var version_picker := panel.get_node("%CampaignRevision") as OptionButton
	assert_true(version_picker.visible and version_picker.tooltip_text == "Version for Imported 00" and version_picker.get_item_text(0) == "Author version 2", "selected campaign dock names its version selector and preserves authored labels")
	assert_false((imported_rows.find_child("Scenario_imported-00", false, false).get_node("%LaunchCampaign") as Button).button_pressed, "revealing an imported package does not falsely mark an unprepared session selected")
	for mode: String in [PresentationSettings.TYPOGRAPHY_CLASSIC, PresentationSettings.TYPOGRAPHY_READABLE]:
		var preferences := PresentationSettings.new()
		preferences.typography_mode = mode
		panel.theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres"), preferences)
		assert_equal(version_picker.get_theme_font("font").get_font_name(), (panel.get_node("%CampaignDockStatus") as Label).get_theme_font("font").get_font_name(), "version selector follows selected body typography")
	var removals: Array[String] = []
	library.removal_requested.connect(func(id: String) -> void: removals.append(id))
	var remove_dialog := panel.get_node("%RemoveScenarioDialog") as ConfirmationDialog
	(panel.get_node("%RemoveCampaign") as Button).pressed.emit()
	assert_true(remove_dialog.visible and remove_dialog.dialog_text.contains("Imported 00") and removals.is_empty(), "removal names the campaign and waits for confirmation")
	remove_dialog.hide()
	assert_true(removals.is_empty(), "cancelling removal preserves the library")
	(panel.get_node("%RemoveCampaign") as Button).pressed.emit()
	remove_dialog.confirmed.emit()
	remove_dialog.hide()
	assert_equal(removals, ["imported-00"], "confirmation emits only the imported campaign identity")
	var broken_row := imported_rows.find_child("Scenario_broken-campaign", false, false) as Control
	(broken_row.get_node("%LaunchCampaign") as Button).pressed.emit()
	assert_true((panel.get_node("%CampaignDockStatus") as Label).text == broken.error_message and (panel.get_node("%RemoveCampaign") as Button).visible, "unavailable imports expose the exact readiness reason and remain removable")
	var import_button := router.find_child("ImportScenario", true, false) as Button
	var import_dialog := router.find_child("ImportScenarioDialog", true, false) as FileDialog
	assert_true(import_button != null and import_dialog != null and import_dialog.file_mode == FileDialog.FILE_MODE_OPEN_DIR and import_dialog.use_native_dialog and import_dialog.ok_button_text == "Import", "folder import requires the native directory picker and its explicit Import action")
	var imported_directories: Array[String] = []
	library.import_requested.connect(func(directory: String) -> void: imported_directories.append(directory))
	import_button.pressed.emit()
	assert_true(import_dialog.visible, "Import Scenario opens the directory picker")
	import_dialog.dir_selected.emit("user://incoming/folder")
	assert_equal(imported_directories, ["user://incoming/folder"], "confirming the directory requests import without changing the active campaign")
	await (Engine.get_main_loop() as SceneTree).process_frame
	scroll.scroll_vertical = 120
	var progress := PackageOperationView.new(PackageOperationView.RUNNING, &"converting", 1, 3, "Converting scenario…", &"", "user://incoming/folder", &"import_scenario")
	library.set_package_operation(progress)
	assert_true(import_button.disabled and (imported_rows.get_child(0).get_node("%LaunchCampaign") as Button).disabled, "an active import disables new imports and scenario launches")
	var retained_row_id: int = imported_rows.get_child(0).get_instance_id()
	scroll.scroll_vertical = 80
	var next_progress := PackageOperationView.new(PackageOperationView.RUNNING, &"converting", 2, 3, "Converting scenario…", &"", "user://incoming/folder", &"import_scenario")
	library.set_package_operation(next_progress)
	assert_equal([imported_rows.get_child(0).get_instance_id(), scroll.scroll_vertical], [retained_row_id, 80], "progress refreshes preserve campaign row instances and picker scroll position")
	var succeeded := PackageOperationView.new(PackageOperationView.SUCCEEDED, &"complete", 3, 3, "Scenario imported with compatibility warnings.", &"", "user://incoming/folder", &"import_scenario")
	succeeded.diagnostic_details = ["Optional portrait reference was unavailable.", "One deferred legacy reference remains."]
	library.set_package_operation(succeeded)
	var status := router.find_child("PackageOperationStatus", true, false) as Label
	var diagnostics_toggle := router.find_child("PackageWarningDetailsToggle", true, false) as Button
	var diagnostics := router.find_child("PackageWarningDetails", true, false) as RichTextLabel
	assert_true(status != null and status.text == succeeded.message and diagnostics_toggle != null and diagnostics_toggle.visible, "successful import displays its operation message and actual diagnostics affordance")
	diagnostics_toggle.pressed.emit()
	assert_true(diagnostics.visible and diagnostics.text == "\n".join(succeeded.diagnostic_details), "expanding import diagnostics shows the supplied detail strings without reconstructing them")
	var failed := PackageOperationView.new(PackageOperationView.FAILED, &"preflight", 1, 3, "Scenario import failed.", &"invalid_source", "user://incoming/folder", &"import_scenario")
	failed.startup_candidates = ["START.SCN", "START2.SCN"]
	library.set_package_operation(failed)
	var retry := router.find_child("RetryPackageOperation", true, false) as Button
	retry.pressed.emit()
	assert_equal(imported_directories, ["user://incoming/folder", "user://incoming/folder"], "retrying an import failure routes the original folder back to the importer")
	var startup_selector := router.find_child("StartupCandidateSelector", true, false) as OptionButton
	var startup_button := router.find_child("UseStartupCandidate", true, false) as Button
	var startup_choices: Array[Array] = []
	library.startup_selection_requested.connect(func(directory: String, startup_file: String) -> void: startup_choices.append([directory, startup_file]))
	startup_selector.select(1)
	startup_button.pressed.emit()
	assert_true(startup_selector.visible and startup_button.visible and startup_choices == [["user://incoming/folder", "START2.SCN"]], "an ambiguous folder import exposes its selected valid startup basename for a direct retry")
	import_dialog.hide()
	router.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
