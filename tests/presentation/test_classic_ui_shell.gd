extends "res://tests/presentation/classic_ui_test_support.gd"

const PackageOperationStatusScript := preload("res://src/app/package_operation_view.gd")
const ApplicationLifecycleScript := preload("res://src/app/application_lifecycle.gd")
const InteractionLayoutPolicyScript := preload("res://src/presentation/interaction_layout_policy.gd")


func run() -> void:
	_test_startup_party_setup_composition()
	_test_package_operation_presentation()
	_test_primary_workspace_lifecycle()

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
	var presenter := load("res://src/presentation/interaction_presenter.tscn").instantiate() as InteractionPresenter
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
	assert_true(character_heading != null and character_heading.visible and party_heading != null and party_heading.visible, "Character Files and Current Party remain visible in the startup composition"); var party_slots := router.find_child("PartySlots", true, false)
	assert_equal(party_slots.get_child_count() if party_slots != null else -1, 6, "Current Party keeps all six available positions visible in the startup composition")
	var initial_party_slot_ids: Array[int] = []; for slot: Node in party_slots.get_children(): initial_party_slot_ids.append(slot.get_instance_id())
	router.set_layout_profile(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO), Vector2(800, 600)); assert_true((router.find_child("PackageInstallRow", true, false) as BoxContainer).vertical and router.find_child("ExperienceRatio", true, false) != null, "compact setup stacks installation controls while preserving a dedicated source-calculated experience fact")
	var setup_view := GameView.new(1, true, null); setup_view.party_setup_available = true; setup_view.party_setup = PartySetupView.new(); setup_view.campaign_summary = CampaignSummaryView.new(); setup_view.party_members = [CharacterView.new(CharacterState.new("setup.inspect", "Ari", 12, 12))]; router.present(setup_view); router.show_campaign_selection(); var updated_party_slot_ids: Array[int] = []; for slot: Node in party_slots.get_children(): updated_party_slot_ids.append(slot.get_instance_id())
	assert_equal(updated_party_slot_ids, initial_party_slot_ids, "party insertion updates one retained six-slot control set instead of rebuilding the pane"); var inspect := _buttons_in(router.find_child("PartySlots", true, false)).filter(func(button: Button) -> bool: return button.text in ["View", "Inspect"])[0] as Button; inspect.pressed.emit(); assert_true((router.find_child("PartySetupCharacterInspection", true, false) as Control).visible and router.find_child("BackToPartySetup", true, false) != null and router.find_child("CharacterInspectionScroll", true, false) != null and router.find_child("PartySetupCharacterSheet", true, false) != null, "setup inspection owns one opaque clipped full-stage record with one return action"); router.free()


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
	view.party_summary = PartySummaryView.new(); view.party_members = [CharacterView.new(CharacterState.new("hero", "Hero", 8, 10)), CharacterView.new(CharacterState.new("mage", "Mage", 6, 9))]
	router.present(view); assert_true(router.select_character("mage"), "the persistent Party current-member identity can seed the Character workspace")
	var entered: Array[StringName] = []
	router.screen_changed.connect(func(route_id: StringName) -> void: entered.append(route_id))
	for route_id: StringName in [&"character", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"exploration", &"combat"]:
		router.open_screen(route_id)
		assert_equal(router.current_screen(), route_id, "route selection commits the requested primary workspace")
		assert_equal(router.primary_workspace_id(), route_id, "the mounted scene and route registry cannot diverge")
		assert_equal(router.mounted_primary_workspace_count(), 1, "a route transition leaves exactly one primary workspace mounted")
		assert_equal(router.primary_workspace_visible(), route_id not in [&"exploration", &"combat"], "only spatial play routes suppress their explanatory workspace body"); var route_back := router.find_child("RouteBackAction", true, false) as Button; var spell_screen := router.find_child("WorkspaceFrame", true, false) as ClassicRouteScreen if route_id == &"spells" else null; var context_actions := spell_screen.context_action_control() if spell_screen != null else null; var spell_title := spell_screen.find_child("ScreenTitle", true, false) as Control if spell_screen != null else null; var header_rule := spell_screen.find_child("HeaderRule", true, false) as Control if spell_screen != null else null; var inventory_done := router.find_child("InventoryDone", true, false) as Button if route_id == &"inventory" else null; var inventory_record := router.find_child("InventoryItemInspector", true, false) as Control if route_id == &"inventory" else null; assert_true(route_back != null and route_back.visible == (route_id not in [&"exploration", &"combat", &"vault", &"inventory"]) and (route_id != &"spells" or router.find_child("WorkspaceFooter", true, false) != null and context_actions != null and spell_title != null and not spell_title.visible and header_rule != null and not header_rule.visible) and (route_id != &"inventory" or inventory_done != null and inventory_done.visible and inventory_record != null and inventory_record.is_ancestor_of(inventory_done) and router.find_child("WorkspaceFooter", true, false) == null) and (route_id != &"character" or _buttons_in(router.find_child("CharacterPicker", true, false)).any(func(button: Button) -> bool: return button.text == "Mage" and button.button_pressed)), "route %s keeps one task-appropriate visible Done or Back action, integrates Inventory Done into its record, opens the current Character, and gives Spells a fixed action footer without a redundant route heading" % route_id)
	assert_equal(entered, [&"character", &"inventory", &"spells", &"services", &"journal", &"system", &"vault", &"exploration", &"combat"], "each primary transition publishes exactly one entered route after replacing the prior workspace"); router.open_screen(&"system"); var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new()); router.set_media_catalog(media); var retained_system_tabs := router.find_child("SystemWorkspaceTabs", true, false); router.set_media_catalog(media); assert_true(retained_system_tabs != null and router.find_child("SystemWorkspaceTabs", true, false) == retained_system_tabs, "reusing one effective media catalog preserves the mounted route content instead of rebuilding it during ordinary movement events"); (router.find_child("RouteBackAction", true, false) as Button).pressed.emit(); assert_equal(router.current_screen(), &"combat", "the persistent route Back action follows the same history path as Escape")
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
