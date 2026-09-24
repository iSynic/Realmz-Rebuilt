extends "res://tests/presentation/classic_ui_test_support.gd"

const PackageOperationStatusScript := preload("res://src/app/startup/package_operation_view.gd")
const ApplicationLifecycleScript := preload("res://src/app/platform/application_lifecycle.gd")
const InteractionLayoutPolicyScript := preload("res://src/ui/shared/interactions/interaction_layout_policy.gd")


func run() -> void:
	await _test_top_menu_consolidation_and_pointer_ownership()
	_test_startup_party_setup_composition()
	_test_package_operation_presentation()
	await _test_primary_workspace_lifecycle()


func _test_top_menu_consolidation_and_pointer_ownership() -> void:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var shell := load("res://src/ui/shell/game_shell.tscn").instantiate() as GameShell
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(shell)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var row := shell.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow") as HBoxContainer
	var headings: Array[MenuButton] = []
	for child: Node in row.get_children():
		if child is MenuButton:
			headings.append(child as MenuButton)
	assert_equal(headings.map(func(menu: MenuButton) -> String: return menu.text), ["Game", "Adventure", "Party", "Settings", "Help"], "the desktop strip presents exactly the five coordinated headings")
	var game := headings[0]
	var settings := headings[3]
	assert_true(game.get_popup().item_count == 6 and game.get_popup().get_item_text(1) == "Save & Load…" and game.get_popup().is_item_disabled(1) and game.get_popup().get_item_text(2) == "Quicksave A" and game.get_popup().get_item_text(3) == "Quickload A", "Game exposes one quicksave and quickload for the active slot alongside its campaign, save, and exit choices")
	assert_true(headings[1].get_popup().get_item_text(9) == "Bestiary" and headings[1].get_popup().get_item_text(10) == "Maps and Notes" and headings[2].get_popup().get_item_text(5) == "Current Allies", "Adventure owns Bestiary and Maps while Party owns Current Allies")
	assert_true(settings.get_popup().get_item_text(0) == "Preferences…" and settings.get_popup().get_item_text(7) == "Playlist…" and headings[1].get_popup().get_item_text(1) == "Move To" and headings[1].get_popup().is_item_checkable(1) and not headings[1].get_popup().is_item_checked(1) and headings[4].get_popup().get_item_text(0) == "About Realmz Rebuilt", "Settings keeps preferences and music, Adventure exposes default-off Move To, and Help keeps About")
	var menu_controller := shell.get("_menu_controller") as GameShellMenuController
	var pointer_click := InputEventMouseButton.new()
	pointer_click.button_index = MOUSE_BUTTON_LEFT
	pointer_click.pressed = true
	game.get_popup().emit_signal("about_to_popup")
	assert_true(menu_controller.owns_native_menu_input() and menu_controller.handle_host_input(InputEventKey.new()), "native dropdown input is held out of gameplay and remains available to GUI controls")
	pointer_click.position = Vector2(600, 400)
	assert_true(menu_controller.handle_host_input(pointer_click) and not menu_controller.owns_native_menu_input() and shell.get_viewport().is_input_handled(), "outside dismissal releases dropdown ownership and consumes its click before map input")
	game.get_popup().emit_signal("popup_hide")
	assert_false(menu_controller.owns_native_menu_input(), "closing the native dropdown releases gameplay-input ownership")
	assert_true(shell.controller.open_top_menu() and shell.controller.move_top_menu(Vector2i.DOWN), "the controller opens the same catalog through the scene-owned menu overlay")
	var overlay := shell.find_child("ControllerTopMenuOverlay", true, false) as ControllerTopMenuOverlay
	assert_true(overlay.visible and (overlay.find_child("Heading", true, false) as Label).text == "Game", "controller traversal starts on the first consolidated heading")
	shell.controller.move_top_menu(Vector2i.DOWN)
	assert_true((overlay.find_child("Reason", true, false) as Label).visible, "disabled Game entries remain selectable with their existing reason")
	pointer_click.position = game.get_global_rect().get_center()
	assert_true(menu_controller.handle_host_input(pointer_click) and not shell.controller.top_menu_is_open(), "mouse takeover closes controller menu ownership while suppressing the click from gameplay")
	host.size = Vector2(800.0, 600.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var compact := shell.get_node("%CompactMenu") as MenuButton
	assert_true(compact.visible and compact.get_popup().item_count > 20 and compact.get_popup().get_item_text(0).begins_with("Game — ") and compact.get_popup().get_item_text(6).begins_with("Adventure — "), "the compact menu flattens the same catalog while retaining each destination group")
	assert_true(not compact.get_popup().exclusive and headings.all(func(menu: MenuButton) -> bool: return not menu.get_popup().exclusive and not menu.switch_on_hover), "embedded dropdowns keep compositor input forwarding available and heading changes remain controller-managed")
	host.free()
	await (Engine.get_main_loop() as SceneTree).process_frame

func _test_interaction_layout_policy() -> void:
	var textbox := InteractionRequest.acknowledge("layout.textbox", "Narration")
	var floating := InteractionRequest.yes_no("layout.floating", "Continue?", "Yes", "No")
	var combat := ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	var lifecycle := ApplicationLifecycleScript.end_adventure_request(true)
	var treasure := ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION)
	var scrolling := InteractionRequest.from_payload("layout.scrolling", InteractionRequest.ACKNOWLEDGE, {"prompt": "Chronicle", "presentation": "classic-scrolling-text"})
	var application_size := Vector2(1280.0, 688.0)
	assert_true(InteractionLayoutPolicyScript.uses_textbox_region(textbox) and not InteractionLayoutPolicyScript.uses_full_stage_region(textbox), "ordinary narration remains in the Castle textbox region")
	assert_true(InteractionLayoutPolicyScript.uses_floating_choice_modal(floating) and InteractionLayoutPolicyScript.floating_choice_rect(Rect2(0.0, 28.0, 992.0, 502.0), Rect2(286.0, 530.0, 620.0, 190.0), Vector2(286.0, 46.0)).size == Vector2(520.0, 116.0), "indexed choices retain their compact floating geometry")
	assert_equal(InteractionLayoutPolicyScript.interaction_region(combat, Rect2(8.0, 530.0, 984.0, 182.0), Rect2(0.0, 530.0, 1280.0, 190.0)), Rect2(0.0, 530.0, 1280.0, 190.0), "combat commands retain the full-width footer region")
	assert_true(InteractionLayoutPolicyScript.uses_application_modal_region(lifecycle) and InteractionLayoutPolicyScript.preferred_modal_size(lifecycle, application_size) == Vector2(560.0, 220.0), "lifecycle questions retain their application-centered size")
	assert_true(InteractionLayoutPolicyScript.uses_application_workspace(treasure) and InteractionLayoutPolicyScript.uses_full_stage_region(treasure), "Treasure retains the full application workspace")
	assert_true(InteractionLayoutPolicyScript.uses_full_stage_region(scrolling) and not InteractionLayoutPolicyScript.uses_textbox_region(scrolling), "Classic scrolling text retains the full-stage region")


func _test_classic_click_modal() -> void:
	var parent := Control.new()
	parent.size = Vector2(1280.0, 720.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(parent)
	var presenter := load("res://src/ui/shared/interactions/interaction_presenter.tscn").instantiate() as InteractionPresenter
	parent.add_child(presenter)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var stage_rect := Rect2(0.0, 28.0, 992.0, 502.0)
	var textbox_rect := Rect2(286.0, 530.0, 620.0, 190.0)
	presenter.set_classic_regions(stage_rect, textbox_rect, Rect2(0.0, 530.0, 1280.0, 190.0))
	var responses: Array[InteractionResponse] = []
	presenter.response_submitted.connect(func(response: InteractionResponse) -> void: responses.append(response))
	var request := InteractionRequest.from_payload("classic-click", InteractionRequest.ACKNOWLEDGE, {"prompt": "Continue", "presentation": "classic-click-modal"})
	presenter.present(request)
	var expected := InteractionLayoutPolicyScript.classic_click_modal_rect(Rect2(0.0, 28.0, 1280.0, 692.0), textbox_rect)
	var shield := parent.get_node_or_null("LockedModalShield") as Control
	assert_true(InteractionLayoutPolicyScript.uses_classic_click_modal(request) and presenter.position == expected.position and presenter.size == expected.size and expected.size == Vector2(174.0, 60.0) and presenter.theme_type_variation == &"ClassicInset" and shield != null and shield.visible, "opcode 26 uses the narrow half-height blocking click-modal geometry instead of the narrative well (expected %s at %s; got %s at %s)" % [expected.size, expected.position, presenter.size, presenter.position])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_true(presenter.handle_global_pointer_acknowledgement(click) and responses.size() == 1 and parent.get_node_or_null("LockedModalShield") == null, "the compact click modal advances once from Castle's application-wide pointer acknowledgement and releases its input shield")
	parent.free()


func _test_startup_party_setup_composition() -> void:
	var router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO)
	router.set_layout_profile(profile, Vector2(1280, 720))
	router.setup_controller.character_creation.set_standalone_character_creation_available(true)
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
	assert_true(character_heading != null and character_heading.visible and party_heading != null and party_heading.visible, "Character Files and Current Party remain visible in the startup composition"); var party_slots := router.find_child("PartySlots", true, false)
	assert_equal(party_slots.get_child_count() if party_slots != null else -1, 6, "Current Party keeps all six available positions visible in the startup composition")
	var initial_party_slot_ids: Array[int] = []; for slot: Node in party_slots.get_children(): initial_party_slot_ids.append(slot.get_instance_id())
	router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); assert_true((router.find_child("PackageInstallRow", true, false) as BoxContainer).vertical and router.find_child("ExperienceRatio", true, false) != null, "compact setup stacks installation controls while preserving a dedicated source-calculated experience fact")
	var setup_view := GameView.new(1, true, null); setup_view.party_setup_available = true; setup_view.party_setup = PartySetupView.new(); setup_view.campaign_summary = CampaignSummaryView.new(); setup_view.party_members = [CharacterView.new(CharacterState.new("setup.inspect", "Ari", 12, 12))]; router.present(setup_view); router.show_campaign_selection(); var updated_party_slot_ids: Array[int] = []; for slot: Node in party_slots.get_children(): updated_party_slot_ids.append(slot.get_instance_id())
	assert_equal(updated_party_slot_ids, initial_party_slot_ids, "party insertion updates one retained six-slot control set instead of rebuilding the pane"); var inspect := _buttons_in(router.find_child("PartySlots", true, false)).filter(func(button: Button) -> bool: return button.text in ["View", "Inspect"])[0] as Button; inspect.pressed.emit(); assert_true((router.find_child("PartySetupCharacterInspection", true, false) as Control).visible and router.find_child("BackToPartySetup", true, false) != null and router.find_child("CharacterInspectionScroll", true, false) != null and router.find_child("PartySetupCharacterSheet", true, false) != null, "setup inspection owns one opaque clipped full-stage record with one return action"); router.free()


func _test_package_operation_presentation() -> void:
	var router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator
	(Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var canceled := [0]
	var retried: Array[String] = []
	router.cancel_package_requested.connect(func() -> void: canceled[0] += 1)
	router.start_requested.connect(func(path: String, _seed: int) -> void: retried.append(path))
	router.setup_controller.campaign_library.set_package_operation(PackageOperationStatusScript.new(&"running", &"loading", 2, 4, "Loading package 2 of 4"))
	var progress := router.find_child("PackageOperationProgress", true, false) as ProgressBar
	var cancel := router.find_child("CancelPackageOperation", true, false) as Button
	assert_equal([progress.value, progress.max_value], [2.0, 4.0], "package work exposes bounded detached progress"); assert_true(router.find_child("PackageOperationPhase", true, false) != null and (router.find_child("PackageOperationHost", true, false) as Control).visible and not router.setup_controller.campaign_scroll.is_ancestor_of(progress) and (router.find_child("InstallPackage", true, false) as Button).disabled and (router.find_child("RefreshScenarios", true, false) as Button).disabled, "package work owns one fixed status host and suppresses competing library actions")
	assert_not_null(cancel, "package work exposes cancellation")
	cancel.pressed.emit()
	assert_equal(canceled[0], 1, "cancellation remains a host signal")
	var failed_path := "user://incoming/broken.realmz2"
	router.setup_controller.campaign_library.set_package_operation(PackageOperationStatusScript.new(&"failed", &"validating_content", 4, 9, "Map 3 references an unknown trigger.", &"package_validation_failed", failed_path, &"install_scenario"))
	var details := router.find_child("PackageFailureDetails", true, false) as Label
	var retry := router.find_child("RetryPackageOperation", true, false) as Button
	var dismiss := router.find_child("DismissPackageFailure", true, false) as Button
	assert_true(details.visible and details.text.contains("Install Scenario") and details.text.contains(failed_path) and details.text.contains("package_validation_failed"), "a terminal package failure retains its operation, exact affected package, and typed error code")
	retry.pressed.emit()
	assert_equal(retried, [failed_path], "Try Again resubmits the retained package through the ordinary start owner exactly once")
	dismiss.pressed.emit()
	assert_true(not (router.find_child("PackageOperationHost", true, false) as Control).visible, "Choose Another dismisses only the retained failure presentation and leaves the campaign selector available")
	router.setup_controller.campaign_library.set_package_operation(PackageOperationStatusScript.new())
	assert_true(not (router.find_child("PackageOperationHost", true, false) as Control).visible and not (router.find_child("InstallPackage", true, false) as Button).disabled and not (router.find_child("RefreshScenarios", true, false) as Button).disabled, "completed package work hides its authored status and restores library actions")
	router.free()


func _test_primary_workspace_lifecycle() -> void:
	var router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator; (Engine.get_main_loop() as SceneTree).root.add_child(router)
	router.initialize()
	var view := GameView.new(1, true, null)
	view.campaign_id = "workspace-fixture"
	view.rules_version = "realmz-classic-1"
	view.party_summary = PartySummaryView.new(); view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)), CharacterView.new(CharacterState.new("mage", "Mage", 6, 9))]
	router.present(view); assert_true(router.content_presenter.select_character("mage"), "the persistent Party current-member identity can seed the Character workspace")
	var entered: Array[StringName] = []; var focused: Array[StringName] = []
	router.screen_changed.connect(func(route_id: StringName) -> void: entered.append(route_id)); router.workspace_focus_restored.connect(func(route_id: StringName, _key: String) -> void: focused.append(route_id))
	for route_id: StringName in [&"character", &"allies", &"bestiary", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"save_load", &"exploration", &"save_load", &"combat"]:
		focused.clear(); router.refresh_current_workspace(); router.open_screen(route_id); await (Engine.get_main_loop() as SceneTree).process_frame
		assert_equal(router.current_screen(), route_id, "route selection commits the requested primary workspace")
		var shell_mode := route_id in [&"exploration", &"combat"]
		assert_equal(router.primary_workspace_id(), &"" if shell_mode else route_id, "only workspace routes mount a primary scene")
		assert_equal(router.mounted_primary_workspace_count(), 0 if shell_mode else 1, "a route transition mounts exactly one workspace or no scene for a shell mode")
		assert_equal([router.primary_workspace_visible(), focused, (router.get_node("SaveModalShield") as Control).visible], [not shell_mode, [] if shell_mode else [route_id], route_id == &"save_load"], "only the current workspace restores deferred focus; shell modes discard superseded workspace work")
		if shell_mode:
			assert_true(router.find_child("WorkspaceFrame", true, false) == null, "shell modes do not leave a hidden explanatory scene in the tree")
			continue
		var route_back := router.find_child("RouteBackAction", true, false) as Button; var spell_screen := router.find_child("WorkspaceFrame", true, false) as ScreenFrame if route_id == &"spells" else null; var context_actions := spell_screen.context_action_control() if spell_screen != null else null; var spell_footer := spell_screen.find_child("WorkspaceFooter", true, false) as Control if spell_screen != null else null; var spell_title := spell_screen.find_child("ScreenTitle", true, false) as Control if spell_screen != null else null; var header_rule := spell_screen.find_child("HeaderRule", true, false) as Control if spell_screen != null else null; var inventory_done := router.find_child("InventoryDone", true, false) as Button if route_id == &"inventory" else null; var inventory_record := router.find_child("InventoryItemInspector", true, false) as Control if route_id == &"inventory" else null; var services_done := router.find_child("MoneyDone", true, false) as Button if route_id == &"services" else null; assert_true(route_back != null and route_back.visible == (route_id not in [&"vault", &"inventory", &"services"]) and (route_id != &"spells" or spell_footer != null and spell_footer.get_parent().name == &"WorkspaceColumn" and spell_footer.custom_minimum_size.y == 50.0 and context_actions != null and spell_title != null and not spell_title.visible and header_rule != null and not header_rule.visible) and (route_id != &"inventory" or inventory_done != null and inventory_done.visible and inventory_record != null and inventory_record.is_ancestor_of(inventory_done) and router.find_child("WorkspaceFooter", true, false) == null) and (route_id != &"services" or services_done != null and services_done.visible and services_done.get_parent().name == &"MoneyPartyArea") and (route_id != &"character" or _buttons_in(router.find_child("CharacterPicker", true, false)).any(func(button: Button) -> bool: return button.text == "Mage" and button.button_pressed)), "route %s keeps one task-appropriate visible Done or Back action, integrates Inventory and Party Wealth Done into fixed records, opens the current Character, and gives Spells a fixed in-flow action footer without a redundant route heading" % route_id)
		if route_id == &"inventory":
			var inventory_regions := [router.find_child("InventoryMainSplit", true, false), router.find_child("InventoryItemBrowser", true, false), router.find_child("InventoryCharacterCommandRail", true, false), router.find_child("InventoryItemInspector", true, false)]
			var inventory_region_ids := inventory_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(inventory_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and inventory_region_ids == inventory_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Inventory rerenders records inside stable scene-authored regions")
		if route_id == &"character":
			var character_regions := [router.find_child("PartyOrderArea", true, false), router.find_child("CharacterSheetArea", true, false)]
			var character_region_ids := character_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(character_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and character_region_ids == character_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Character rerenders records inside stable scene-authored regions")
		if route_id in [&"allies", &"bestiary"]:
			var creature_regions := [router.find_child("CreatureColumns", true, false), router.find_child("CreatureListPanel", true, false), router.find_child("CreatureDetailPanel", true, false)]
			var creature_region_ids := creature_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(creature_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and creature_region_ids == creature_regions.map(func(region: Node) -> int: return region.get_instance_id()), "%s rerenders records inside stable scene-authored regions" % route_id)
		if route_id == &"services":
			var money_regions := [router.find_child("MoneyColumn", true, false), router.find_child("MoneyPoolPane", true, false), router.find_child("MoneyPartyPane", true, false), router.find_child("MoneySwapPane", true, false)]
			var money_region_ids := money_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(money_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and money_region_ids == money_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Party Wealth rerenders records inside stable scene-authored regions")
		if route_id == &"journal":
			var journal_regions := [router.find_child("MapsNotesSummary", true, false), router.find_child("MapsNotesTabs", true, false), router.find_child("Places", true, false), router.find_child("Maps", true, false), router.find_child("Journal", true, false)]
			var journal_region_ids := journal_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(journal_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and journal_region_ids == journal_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Maps / Notes rerenders records inside stable scene-authored tab regions")
		if route_id == &"spells":
			var spell_regions := [router.find_child("Caster", true, false), router.find_child("Sections", true, false), router.find_child("SpellcastingBlockedNotice", true, false), router.find_child("ClassicSpellbookWorkspace", true, false)]
			var spell_region_ids := spell_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(spell_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and spell_region_ids == spell_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Spells rerenders records inside stable scene-authored regions")
		if route_id == &"system":
			var system_regions := [router.find_child("SystemSummary", true, false), router.find_child("SystemWorkspaceTabs", true, false), router.find_child("Save & Load", true, false), router.find_child("Display", true, false), router.find_child("Audio", true, false), router.find_child("Pacing", true, false), router.find_child("Accessibility", true, false), router.find_child("Controls", true, false), router.find_child("Diagnostics", true, false)]
			var system_region_ids := system_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(system_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and system_region_ids == system_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Preferences and Game rerenders records inside stable scene-authored tab regions")
		if route_id == &"vault":
			var vault_regions := [router.find_child("VaultHeaderArea", true, false), router.find_child("VaultListArea", true, false), router.find_child("VaultHistoryArea", true, false), router.find_child("VaultInspectionArea", true, false)]
			var vault_region_ids := vault_regions.map(func(region: Node) -> int: return region.get_instance_id())
			router.present(view)
			assert_true(vault_regions.all(func(region: Node) -> bool: return is_instance_valid(region)) and vault_region_ids == vault_regions.map(func(region: Node) -> int: return region.get_instance_id()), "Character Files rerenders records inside stable scene-authored regions")
	assert_equal(entered, [&"character", &"allies", &"bestiary", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"save_load", &"exploration", &"save_load", &"combat"], "each primary transition publishes exactly one entered route after replacing the prior workspace"); router.open_screen(&"save_load"); var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); router.set_media_catalog(media); var retained_system_tabs := router.find_child("SystemWorkspaceTabs", true, false); router.set_media_catalog(media); assert_true(retained_system_tabs != null and router.find_child("SystemWorkspaceTabs", true, false) == retained_system_tabs, "reusing one effective media catalog preserves the mounted route content instead of rebuilding it during ordinary movement events"); (router.find_child("RouteBackAction", true, false) as Button).pressed.emit(); assert_equal([router.current_screen(), (router.get_node("SaveModalShield") as Control).visible], [&"combat", false], "Back returns to combat and releases the save modal shield")
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
