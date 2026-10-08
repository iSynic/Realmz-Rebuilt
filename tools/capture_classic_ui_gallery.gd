extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const OUTPUT_ROOT := "res://artifacts/ui-gallery"
const CHARACTER_VIEW_SCRIPT := preload("res://src/game/characters/character_view.gd")
const PACKAGE_OPERATION_VIEW_SCRIPT := preload("res://src/app/startup/package_operation_view.gd")
const SAVE_SLOT_PREVIEW_SCRIPT := preload("res://src/playthrough/session/save_slot_preview.gd")
const APPLICATION_LIFECYCLE_SCRIPT := preload("res://src/app/platform/application_lifecycle.gd")
const FIXTURE_REQUEST_SCRIPT := preload("res://src/app/platform/runtime_testing_fixture_request.gd")
const DISPLAY_COMPOSITOR_SCENE := preload("res://src/ui/shared/display_compositor.tscn")
const SCENE_PREVIEW_REGISTRY_PATH := "res://addons/realmz_builder/scene_previews.json"
const ScalingAudit := preload("res://tools/ui_scaling_audit.gd")
const SIZING_MATRIX_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(800, 600), Vector2i(1920, 1080), Vector2i(2560, 1392), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]
const SIZING_MATRIX_SURFACES: Array[String] = ["application-shell", "character-sheet", "character-files", "allies", "bestiary", "inventory", "spells", "services", "maps-journal", "system", "campaign-selection", "party-assembly", "party-import-from-save", "character-creation", "shop", "temple", "bank", "treasure", "encounter", "level-up", "pick-lock", "lifecycle-prompts", "scrolling-text", "combat-command-deck", "roster-spellbook"]
var _application: RealmzApplication
var _compositor: DisplayCompositor
var _shell: GameShell
var _router: ScreenNavigator
var _interaction: InteractionPresenter
var _fixture_request: RuntimeTestingFixtureRequest
var _sizing_matrix := false
var _raw_scenes := false
var _stress_roster := false
var _surface_filters: Array[String] = []
var _sizing_matrix_surfaces: Dictionary = {}
var _matrix_metadata: FileAccess
var _raw_scene_metadata: FileAccess
var _audit_scaling := false
var _audit_filter := ""
var _audit_states: Dictionary = {}
var _audit_failures := 0
var _audit_metadata: FileAccess


func _initialize() -> void:
	if not _read_launch_arguments():
		quit(2)
		return
	call_deferred("_capture_gallery")


func _read_launch_arguments() -> bool:
	var arguments := OS.get_cmdline_user_args()
	var fixture_config_path := ""
	var surface_list_seen := false
	var index := 0
	while index < arguments.size():
		match arguments[index]:
			"--audit-scaling":
				_audit_scaling = true
			"--audit-state":
				if index + 1 >= arguments.size(): return false
				index += 1
				_audit_filter = arguments[index]
			"--fixture-config":
				if not fixture_config_path.is_empty() or index + 1 >= arguments.size():
					printerr("FIXTURE_REQUEST_REJECTED: Supply one absolute --fixture-config path.")
					return false
				index += 1
				fixture_config_path = arguments[index]
			"--sizing-matrix":
				if _sizing_matrix:
					printerr("FIXTURE_REQUEST_REJECTED: --sizing-matrix may appear only once.")
					return false
				_sizing_matrix = true
			"--raw-scenes":
				if _raw_scenes:
					printerr("FIXTURE_REQUEST_REJECTED: --raw-scenes may appear only once.")
					return false
				_raw_scenes = true
			"--stress-roster":
				if _stress_roster:
					printerr("FIXTURE_REQUEST_REJECTED: --stress-roster may appear only once.")
					return false
				_stress_roster = true
			"--surface":
				if surface_list_seen or index + 1 >= arguments.size():
					printerr("FIXTURE_REQUEST_REJECTED: Supply one --surface ID[,ID...] list from the registered major surfaces.")
					return false
				surface_list_seen = true
				index += 1
				for requested_surface: String in arguments[index].split(",", true):
					var surface_id := requested_surface.strip_edges()
					if surface_id.is_empty():
						printerr("FIXTURE_REQUEST_REJECTED: --surface contains an empty major surface ID.")
						return false
					if not SIZING_MATRIX_SURFACES.has(surface_id):
						printerr("FIXTURE_REQUEST_REJECTED: Unknown major surface %s." % surface_id)
						return false
					if _surface_filters.has(surface_id):
						printerr("FIXTURE_REQUEST_REJECTED: Duplicate major surface %s." % surface_id)
						return false
					_surface_filters.append(surface_id)
			_:
				printerr("FIXTURE_REQUEST_REJECTED: Unknown gallery argument %s." % arguments[index])
				return false
		index += 1
	if fixture_config_path.is_empty() or not fixture_config_path.is_absolute_path() or not OS.is_debug_build():
		printerr("FIXTURE_REQUEST_REJECTED: A debug build and absolute --fixture-config path are required.")
		return false
	if not _surface_filters.is_empty() and not _sizing_matrix:
		printerr("FIXTURE_REQUEST_REJECTED: --surface requires --sizing-matrix.")
		return false
	if (_audit_scaling and (_sizing_matrix or _raw_scenes)) or (not _audit_filter.is_empty() and not _audit_scaling):
		printerr("FIXTURE_REQUEST_REJECTED: Scaling audit is a separate gallery mode; --audit-state requires --audit-scaling.")
		return false
	if _stress_roster and not _surface_filters.is_empty() and not _surface_filters.has("application-shell"):
		printerr("FIXTURE_REQUEST_REJECTED: --stress-roster can only be paired with --surface application-shell.")
		return false
	var config := FileAccess.open(fixture_config_path, FileAccess.READ)
	if config == null or config.get_length() > 65536:
		printerr("FIXTURE_REQUEST_REJECTED: Fixture configuration is unavailable or too large.")
		return false
	var payload: Variant = JSON.parse_string(config.get_as_text())
	config.close()
	_fixture_request = FIXTURE_REQUEST_SCRIPT.decode(payload) as RuntimeTestingFixtureRequest
	if _fixture_request == null:
		printerr("FIXTURE_REQUEST_REJECTED: Fixture configuration does not satisfy the isolated launch contract.")
		return false
	return true


func _capture_gallery() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	if _audit_scaling:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ScalingAudit.OUTPUT_ROOT))
		var ignore_file := FileAccess.open(ScalingAudit.OUTPUT_ROOT.path_join(".gdignore"), FileAccess.WRITE)
		assert(ignore_file != null, "Unable to exclude scaling captures from Godot imports.")
		ignore_file.close()
		_audit_metadata = FileAccess.open(ScalingAudit.OUTPUT_ROOT.path_join("results.jsonl"), FileAccess.WRITE)
		assert(_audit_metadata != null, "Unable to create scaling audit metadata.")
	if _sizing_matrix:
		_matrix_metadata = FileAccess.open(ProjectSettings.globalize_path("%s/sizing-matrix.jsonl" % OUTPUT_ROOT), FileAccess.WRITE)
		assert(_matrix_metadata != null, "Unable to create sizing-matrix metadata.")
	if _raw_scenes:
		_raw_scene_metadata = FileAccess.open(ProjectSettings.globalize_path("%s/raw-scenes.jsonl" % OUTPUT_ROOT), FileAccess.WRITE)
		assert(_raw_scene_metadata != null, "Unable to create raw-scene metadata.")
	_compositor = DISPLAY_COMPOSITOR_SCENE.instantiate() as DisplayCompositor
	_compositor.get_node("Content/StartupFrontDoor").free()
	root.add_child(_compositor)
	await process_frame
	_application = load("res://src/ui/shell/realmz_application.tscn").instantiate() as RealmzApplication
	_application.set_meta(&"runtime_testing_fixture", _fixture_request)
	_application.set_meta(&"startup_splash_suppressed", true)
	_application.set_meta(&"startup_front_door_revealed", true)
	DisplayServer.window_set_title("Realmz Rebuilt — TEST FIXTURE %s — UI Gallery" % _fixture_request.fixture_id.left(8))
	_compositor.source_viewport().add_child(_application)
	_shell = _application.get_node("GameShell") as GameShell
	_router = _shell.get_node("ScreenNavigator") as ScreenNavigator
	_interaction = _application.get_node("InteractionPanel") as InteractionPresenter
	var application_deadline := Time.get_ticks_msec() + 30000
	while not _application.character_files.library_ready() and Time.get_ticks_msec() < application_deadline: await process_frame
	assert(_application.character_files.library_ready() and _application.character_files.library_content() != null, "UI gallery could not load the built-in Classic definitions.")
	await _close_prepared_fixture_adventure()
	if _raw_scenes:
		await _capture_raw_scenes()
	await _settle()
	await _resize(Vector2i(800, 600))
	await _capture("compact-campaign-800x600")
	await _resize(Vector2i(1280, 720))
	Input.warp_mouse(Vector2(520, 18))
	await _settle()
	await _capture("canonical-campaign-menu-hover-1280x720")
	_router.show_campaign_selection()
	_router.setup_controller.campaign_library.set_package_operation(PACKAGE_OPERATION_VIEW_SCRIPT.new(&"running", &"validating_media", 7, 12, "Validating packaged media 7 of 12"))
	await _settle()
	await _capture("canonical-package-install-progress-1280x720")
	_router.setup_controller.campaign_library.set_package_operation(PACKAGE_OPERATION_VIEW_SCRIPT.new())
	_router.setup_controller.show_party_import({"phase": "selection", "sources": [], "message": "Choose a saved adventure. Its world state stays behind."})
	await _settle()
	await _capture("canonical-party-import-from-save-1280x720")
	_router.setup_controller.close_party_import()
	var package_step := _application.start_package(FIXTURE_PATH, 1); assert(package_step.state != SessionStep.State.FAILED, "Unable to start the UI gallery fixture: %s" % package_step.error_message)
	await _settle()
	await _capture_compact_canonical("compact-party-setup-800x600", "canonical-party-setup-1280x720")
	await _resize(Vector2i(800, 600))
	var setup_view := _application.session_controller.view()
	var setup := _router.setup_controller
	var inspection_state := CharacterState.new("gallery.setup.inspect", "Ari", 18, 18)
	inspection_state.race_id = setup_view.race_options[0].id
	inspection_state.caste_id = setup_view.caste_options[0].id
	inspection_state.portrait_id = setup_view.portrait_options[0].id if not setup_view.portrait_options.is_empty() else ""
	inspection_state.combat_icon_id = setup_view.combat_icon_options[0].id if not setup_view.combat_icon_options.is_empty() else ""
	setup_view.party_members = [CharacterView.new(inspection_state, _application.get("_active_content") as RealmzContent)]
	_shell.present(setup_view)
	var setup_inspect := _button_named(setup.party_list, "View")
	if setup_inspect != null:
		setup_inspect.pressed.emit(); await _settle(); await _capture_compact_canonical("compact-party-setup-inspection-800x600", "canonical-party-setup-inspection-1280x720")
		var setup_back := _button_named(setup.setup_inspection_overlay, "Back to party setup")
		if setup_back != null:
			setup_back.pressed.emit()
	setup_view.party_members.clear(); _shell.present(setup_view)
	setup.create_character_button.pressed.emit()
	await _settle()
	await _capture_compact_canonical("compact-character-creator-identity-800x600", "canonical-character-creator-identity-1280x720")
	setup.selected_race_id = setup_view.race_options[0].id
	setup.selected_caste_id = setup_view.caste_options[0].id
	setup.creator_step = 1
	setup.character_creation.render_creator_step(); await _settle()
	await _capture_canonical_compact("canonical-character-creator-race-class-1280x720", "compact-character-creator-race-class-800x600")
	setup.creator_step = 2
	setup.character_creation.render_creator_step(); await _settle()
	await _capture_canonical_compact("canonical-character-creator-appearance-1280x720", "compact-character-creator-appearance-800x600")
	var review_state := CharacterState.new("gallery.creator", "Ari", 18, 18)
	review_state.race_id = setup_view.race_options[0].id
	review_state.caste_id = setup_view.caste_options[0].id
	review_state.portrait_id = setup_view.portrait_options[0].id if not setup_view.portrait_options.is_empty() else ""
	review_state.combat_icon_id = setup_view.combat_icon_options[0].id if not setup_view.combat_icon_options.is_empty() else ""
	setup_view.character_draft = CharacterView.new(review_state, _application.get("_active_content") as RealmzContent)
	setup.creator_step = 3
	setup.character_creation.render_creator_step(); await _settle()
	await _capture_canonical_compact("canonical-character-creator-review-1280x720", "compact-character-creator-review-800x600")
	review_state.spellcaster_type = 1
	setup_view.character_draft = CharacterView.new(review_state, _application.get("_active_content") as RealmzContent)
	setup_view.character_draft_spell_points_total = 4
	setup_view.character_draft_spell_points_remaining = 3
	setup_view.character_draft_spell_options = [CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1101", 1101, "Discover Magic", "Reveals magical influences affecting the caster."), 1, true), CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1107", 1107, "Magic Darts", "A compact bolt of magical force."), 1, false), CharacterSpellOptionView.new(SpellDefinition.new("classic.spell.1201", 1201, "Flame Hands", "Calls a brief fan of flame."), 2, false)]
	setup.creator_step = 4
	setup.character_creation.render_creator_step()
	await _settle()
	await _capture_canonical_compact("canonical-character-creator-spells-1280x720", "compact-character-creator-spells-800x600")
	setup.character_creation.reset_creator(true)
	await _settle()
	var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	_application.session_controller.submit_intent(PartyIntents.create([member]))
	await _settle()
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"exploration"); await _settle()
	_shell.controller.open_workspace_radial(); await _settle(); await _capture("canonical-controller-workspaces-wheel-1280x720"); _shell.controller.cancel_radial(); _shell.controller.open_action_radial(); await _settle(); await _capture("canonical-controller-actions-wheel-1280x720"); _shell.controller.cancel_radial(); _shell.controller.open_top_menu(); _shell.controller.move_top_menu(Vector2i.RIGHT); _shell.controller.move_top_menu(Vector2i.DOWN); await _settle(); await _capture("canonical-controller-top-menu-1280x720"); _shell.controller.back_top_menu(); _shell.controller.back_top_menu(); await _resize(Vector2i(800, 600)); _shell.controller.open_workspace_radial(); await _settle(); await _capture("classic-controller-workspaces-wheel-800x600"); _shell.controller.cancel_radial(); _shell.controller.open_top_menu(); _shell.controller.move_top_menu(Vector2i.DOWN); await _settle(); await _capture("classic-controller-top-menu-800x600"); _shell.controller.back_top_menu(); _shell.controller.back_top_menu(); await _resize(Vector2i(1280, 720))
	var explore_view := _application.session_controller.view() as GameView
	explore_view.party_summary.condition_values[ConditionRules.PARTY_SEARCHING] = -1
	_shell.present(explore_view); await _settle(); await _capture_canonical_compact("canonical-search-effect-1280x720", "compact-search-effect-800x600")
	explore_view.party_summary.condition_values[ConditionRules.PARTY_SEARCHING] = 0
	explore_view.party_summary.camping = true; _shell.present(GameView.new(0, false, null)); _shell.present(explore_view); await _settle(); await _capture("canonical-camp-mode-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-camp-mode-800x600"); await _resize(Vector2i(1280, 720))
	explore_view.party_summary.camping = false; _shell.present(GameView.new(0, false, null)); _shell.present(explore_view); await _settle()
	_interaction.present(InteractionRequest.acknowledge("gallery-edge-to-edge", "The party follows the old road toward Northgate."))
	await _settle()
	await _capture_canonical_compact("canonical-acknowledge-edge-to-edge-1280x720", "classic-acknowledge-800x600")
	_interaction.present(null)
	var gallery_view: Variant = _application.session_controller.view()
	var gallery_media := _application.presentation_media.catalog()
	var scrolling_gallery_text := "<<< Click & Drag Mouse To Move About >>>\n<<< Double Click To End This Message >>>\n\nYou can edit this text via a Resource editor.\n\nInside the scenario is an authored TEXT resource. Opcode 62 displays that exact text as a scrolling message instead of a normal map.\n\nThis passage continues so the stage visibly advances over Castle's tiled background. ".repeat(5)
	_interaction.present(InteractionRequest.from_payload("gallery-scrolling-text", InteractionRequest.ACKNOWLEDGE, {"prompt": scrolling_gallery_text, "messageId": 1, "presentation": "classic-scrolling-text"}), "", gallery_view, gallery_media)
	await _settle()
	await _capture_canonical_compact("canonical-scrolling-text-1280x720", "classic-scrolling-text-800x600")
	_interaction.present(null)
	if not gallery_view.party_members.is_empty():
		var active_content: Variant = _application.get("_active_content")
		var definition: Variant = active_content.items.item_by_id("classic.item.901")
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
		member_state.portrait_id = setup_view.portrait_options[member_index].id if member_index < setup_view.portrait_options.size() else gallery_view.party_members[0].portrait_id
		member_state.armor = member_index
		gallery_view.party_members.append(CHARACTER_VIEW_SCRIPT.new(member_state, _application.get("_active_content")))
	assert(gallery_view.party_members.size() == 6, "The application-shell representative requires the full six-member gallery party.")
	_router.open_screen(&"exploration")
	_shell.present(gallery_view)
	await _settle()
	if _stress_roster:
		await _capture_stress_roster(gallery_view)
	await _capture("canonical-explore-1280x720")
	if gallery_view.party_members.size() == 6 and gallery_view.party_members[0].items.size() > 1:
		var right_trade_item: ItemView = gallery_view.party_members[0].items.pop_back()
		gallery_view.party_members[1].items.append(right_trade_item)
		for left_trade_item: ItemView in gallery_view.party_members[0].items:
			left_trade_item.description = "This carefully maintained traveling implement has a long description so the Trade layout must keep every line visible beneath the two packs without scrolling the outer workspace. Its maker recorded the material, handling, provenance, and practical use in unusually thorough detail."
			left_trade_item.actions.trade = ActionAvailabilityView.new(&"trade_item", true)
			left_trade_item.actions.trade_targets = [ItemTransferTargetView.new(gallery_view.party_members[1].id, gallery_view.party_members[1].name, true, "", 0, left_trade_item.weight, 1000)]
			var layout_facts: Array[ItemFactView] = [ItemFactView.new(&"weight", "Weight", "100"), ItemFactView.new(&"hands", "Hands", "1"), ItemFactView.new(&"damage", "Damage", "3–14"), ItemFactView.new(&"damage-bonus", "Damage bonus", "+2")]
			left_trade_item.facts = layout_facts
		right_trade_item.actions.trade = ActionAvailabilityView.new(&"trade_item", true)
		right_trade_item.actions.trade_targets = [ItemTransferTargetView.new(gallery_view.party_members[0].id, gallery_view.party_members[0].name, true, "", 0, right_trade_item.weight, 1000)]
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
	_shell.present(gallery_view)
	await _settle()
	var trade_button := _base_button_with_tooltip(_router, "Open the two-pack Trade workspace")
	assert(trade_button is ClassicBitmapButton and not trade_button.disabled, "UI gallery Trade source item was not selectable.")
	(trade_button as ClassicBitmapButton).command_requested.emit(&"inventory.action.trade")
	await _settle()
	await _capture("wide-inventory-trade-1280x720")
	await _resize(Vector2i(800, 600))
	if _router.find_child("InventoryTradeWorkspace", true, false) == null:
		_shell.present(gallery_view)
		await _settle()
		trade_button = _base_button_with_tooltip(_router, "Open the two-pack Trade workspace")
		assert(trade_button is ClassicBitmapButton and not trade_button.disabled, "UI gallery compact Trade source item was not selectable.")
		(trade_button as ClassicBitmapButton).command_requested.emit(&"inventory.action.trade")
		await _settle()
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
	var known_tab := _button_named(_router, "Known Spells")
	if known_tab != null:
		known_tab.pressed.emit(); await _settle()
	await _resize(Vector2i(800, 600))
	await _capture("classic-spells-800x600")
	await _resize(Vector2i(1280, 720))
	gallery_view.current_location_note = LocationNoteView.new("land:0", "Land level 0", &"land", 0, Vector2i(1, 1), "Watch the northern road.", 0, 0, true)
	var gallery_location_notes: Array[LocationNoteView] = [gallery_view.current_location_note, LocationNoteView.new("land:0", "Land level 0", &"land", 0, Vector2i(4, 6), "A sheltered campsite near the old road.", 0, 1)]; gallery_view.location_notes = gallery_location_notes
	var gallery_journal_entries: Array[JournalEntryView] = [JournalEntryView.new(4, "The road bends toward the mountain."), JournalEntryView.new(19, "A long authored entry remains readable. " + "The party follows the old ridge road while the storm closes in. ".repeat(8))]; gallery_view.journal_entries = gallery_journal_entries
	var map_snapshot := _application.session_controller.session().snapshot(); var player_map_definition: PlayerMapDefinition = _application.get("_active_content").world.player_map_by_classic_id(1)
	map_snapshot.game_state.world.exploration.acquire_map(player_map_definition.id)
	var map_session := GameSession.new(); map_session.restore(_application.get("_active_content"), map_snapshot); var map_view := map_session.view()
	gallery_view.player_map_menu_entries = map_view.player_map_menu_entries; gallery_view.acquired_player_maps = map_view.acquired_player_maps; gallery_view.party_summary.acquired_map_ids = map_view.party_summary.acquired_map_ids
	_shell.present(gallery_view)
	_router.open_screen(&"journal")
	await _settle()
	await _capture_canonical_compact("wide-journal-1280x720", "classic-journal-800x600")
	var maps_notes_tabs := _router.find_child("MapsNotesTabs", true, false) as TabContainer
	(maps_notes_tabs.get_parent() as MapsNotesWorkspace).select_section(1); await _settle(); await _capture("canonical-player-maps-1280x720"); await _resize(Vector2i(800, 600))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	(maps_notes_tabs.get_parent() as MapsNotesWorkspace).select_section(1); await _settle(); await _capture("classic-player-maps-800x600"); await _resize(Vector2i(1280, 720))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	(maps_notes_tabs.get_parent() as MapsNotesWorkspace).select_section(0); await _settle(); await _capture_canonical_compact("canonical-player-places-1280x720", "classic-player-places-800x600"); maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	(maps_notes_tabs.get_parent() as MapsNotesWorkspace).select_section(2); ((_router.find_child("JournalEntryRows", true, false).get_child(1)).get_node("Content/Open") as Button).pressed.emit(); await _settle(); await _capture("canonical-authored-journal-1280x720"); await _resize(Vector2i(800, 600))
	maps_notes_tabs = _router.find_child("MapsNotesTabs", true, false) as TabContainer
	(maps_notes_tabs.get_parent() as MapsNotesWorkspace).select_section(2); await _settle(); await _capture("classic-authored-journal-800x600"); await _resize(Vector2i(1280, 720))
	_router.open_screen(&"exploration"); await _settle()
	var gallery_choice := InteractionRequest.from_payload("gallery-classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"}); _shell.status.append_narrative("Will you enter the ruined keep?"); _shell.status._latest_classic_text = "Will you enter the ruined keep?"; _shell.status.present_choice_context(gallery_choice); _interaction.present(gallery_choice, _shell.status.latest_classic_text()); await _settle()
	await _capture_canonical_compact("wide-classic-choice-context-1280x720", "classic-choice-context-800x600")
	var encounter_request := ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION); var encounter_body := encounter_request.body as ComplexEncounterRequestBody; var gallery_encounter_item: ItemView = gallery_view.party_members[0].items[0]; encounter_body.items[0].character_id = gallery_view.party_members[0].id; encounter_body.items[0].instance_id = gallery_encounter_item.instance_id; encounter_body.items[0].classic_id = gallery_encounter_item.classic_id; encounter_body.items[0].name = gallery_encounter_item.name; encounter_body.items[0].icon_resource_type = gallery_encounter_item.icon_resource_type; encounter_body.items[0].icon_id = gallery_encounter_item.icon_id; encounter_body.items[0].charges = gallery_encounter_item.charges; encounter_body.items[0].equipped = gallery_encounter_item.equipped; _interaction.present(encounter_request, "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-encounter-1280x720")
	var word_command := _application.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton
	word_command.command_requested.emit(&"word"); await _settle(); await _capture("wide-encounter-word-entry-1280x720")
	var item_command := _application.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton
	item_command.command_requested.emit(&"item"); await _settle(); await _capture("wide-encounter-item-picker-1280x720")
	var spell_command := _application.find_child("EncounterCommandSpell", true, false) as ClassicBitmapButton
	spell_command.command_requested.emit(&"spell"); await _settle(); await _capture_canonical_compact_leave("wide-encounter-spell-picker-1280x720", "classic-encounter-spell-picker-800x600")
	word_command = _application.find_child("EncounterCommandWord", true, false) as ClassicBitmapButton
	word_command.command_requested.emit(&"word"); await _settle(); await _capture("classic-encounter-word-entry-800x600")
	item_command = _application.find_child("EncounterCommandItem", true, false) as ClassicBitmapButton
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
			var age_body := interaction_request.body as AgeUpdateRequestBody
			age_body.character_id = gallery_view.party_members[0].id; age_body.character_name = gallery_view.party_members[0].name; age_body.portrait_id = gallery_view.party_members[0].portrait_id; age_body.combat_icon_id = gallery_view.party_members[0].combat_icon_id
		if interaction_kind == InteractionRequest.PICK_LOCK and not gallery_view.party_members.is_empty():
			var lock_body := interaction_request.body as PickLockRequestBody
			lock_body.character_id = gallery_view.party_members[0].id; lock_body.character_name = gallery_view.party_members[0].name; lock_body.portrait_id = gallery_view.party_members[0].portrait_id
		if interaction_kind == InteractionRequest.CHARACTER_SELECTION and not gallery_view.party_members.is_empty():
			var selection_body := interaction_request.body as CharacterSelectionRequestBody
			selection_body.eligible[0].id = gallery_view.party_members[0].id; selection_body.eligible[0].name = gallery_view.party_members[0].name
			_shell.roster.present_character_selection(interaction_request)
		_interaction.present(interaction_request, "", gallery_view, gallery_media)
		await _settle()
		await _capture("wide-interaction-%s-1280x720" % String(interaction_kind).replace("_", "-"))
		if interaction_kind == InteractionRequest.AGE_UPDATE:
			await _resize(Vector2i(800, 600)); await _capture("classic-age-update-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.THIEF_ENCOUNTER:
			await _resize(Vector2i(800, 600)); await _capture("classic-interaction-thief-encounter-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.CHARACTER_SELECTION:
			await _capture_canonical_compact("wide-field-spell-target-1280x720", "classic-field-spell-target-800x600")
			_shell.roster.present_character_selection(null)
		if interaction_kind == InteractionRequest.ALLY_SELECTION:
			await _resize(Vector2i(800, 600)); await _capture("classic-surviving-allies-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind == InteractionRequest.PICK_LOCK:
			await _resize(Vector2i(800, 600)); await _capture("classic-pick-lock-800x600"); await _resize(Vector2i(1280, 720))
		if interaction_kind in [InteractionRequest.TEMPLE, InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE]:
			await _resize(Vector2i(800, 600)); _interaction.present(interaction_request, "", gallery_view, gallery_media); await _settle(); await _capture("classic-interaction-%s-800x600" % String(interaction_kind).replace("_", "-")); await _resize(Vector2i(1280, 720))
	await _resize(Vector2i(800, 600))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized" if _audit_scaling else &"nominal"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("classic-treasure-distribution-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized" if _audit_scaling else &"nominal"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-treasure-distribution-1280x720"); _interaction.set_block_signals(true); (_interaction.find_child("TreasureDone", true, false) as Button).pressed.emit(); _interaction.set_block_signals(false); var treasure_completion := InteractionRequest.from_payload("gallery.treasure.completion", InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "summary": "One item remains unclaimed. Leave it behind?"}); _interaction.present(treasure_completion, "", gallery_view, gallery_media); await _settle(); await _capture("wide-treasure-completion-modal-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-treasure-completion-modal-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-treasure-unidentified-1280x720"); await _resize(Vector2i(800, 600)); _interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified"), "", gallery_view, gallery_media); await _settle(); await _capture("classic-treasure-unidentified-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"), "", gallery_view, gallery_media)
	await _settle()
	await _capture("wide-fumble-recovery-1280x720"); await _resize(Vector2i(800, 600)); _interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"), "", gallery_view, gallery_media); await _settle(); await _capture("classic-fumble-recovery-800x600"); await _resize(Vector2i(1280, 720))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP)); await _settle(); await _capture_canonical_compact("wide-level-result-1280x720", "classic-level-result-800x600")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified")); await _settle(); await _capture_canonical_compact("wide-level-spells-1280x720", "classic-level-spells-800x600")
	_interaction.present(null)
	_shell.present(gallery_view)
	_router.open_screen(&"character")
	await _settle()
	await _capture_canonical_compact("canonical-character-overview-1280x720", "classic-character-overview-800x600")
	await _capture_character_section("Conditions & Saves", "conditions")
	await _capture_character_section("Abilities", "abilities")
	var spell_character_button := _button_named(_router, "Elian")
	if spell_character_button != null:
		spell_character_button.pressed.emit()
	await _capture_character_section("Spells", "spells")
	var first_character_button := _button_named(_router, "Ari")
	if first_character_button != null:
		first_character_button.pressed.emit()
	await _capture_character_section("Appearance", "appearance")
	await _capture_character_section("Lifetime Record", "lifetime-record")
	await _capture_character_section("Race, Class & Aging", "background")
	await _capture_character_section("Equipment", "equipment")
	_router.open_screen(&"allies")
	await _settle()
	await _capture("canonical-allies-empty-1280x720")
	var ally_definition: Variant = _application.get("_active_content").combat.monster_by_classic_id(1)
	if ally_definition != null:
		var ally := MonsterState.new("gallery-ally", ally_definition.id, "Rook, Northgate Scout", 12, 15, ally_definition.hit_dice, ally_definition.agility, ally_definition.armor, ally_definition.magic_resistance, ally_definition.spell_points, false)
		ally.icon_id = ally_definition.icon_id
		var gallery_allies: Array[MonsterView] = [MonsterView.new(ally, ally_definition, _application.get("_active_content"))]
		gallery_view.party_allies = gallery_allies
		_shell.present(gallery_view)
		await _settle()
		await _capture_canonical_compact("canonical-allies-populated-1280x720", "classic-allies-populated-800x600")
	_router.open_screen(&"bestiary")
	await _settle()
	await _capture("canonical-bestiary-1280x720")
	if not gallery_view.party_members.is_empty():
		var vault_revisions: Array[CharacterVaultRevisionView] = []
		for index: int in mini(6, gallery_view.party_members.size()):
			var character: CharacterView = gallery_view.party_members[index]
			var vault_revision := CharacterVaultRevisionView.new()
			vault_revision.character_id = character.id; vault_revision.revision_hash = String.chr(97 + index).repeat(64)
			vault_revision.name = character.name; vault_revision.level = character.level; vault_revision.race_id = character.race_id; vault_revision.caste_id = character.caste_id; vault_revision.portrait_id = character.portrait_id; vault_revision.is_current = true; vault_revision.eligible = true; vault_revision.character = character
			vault_revisions.append(vault_revision)
		_router.set_vault_revisions(vault_revisions)
		_router.open_screen(&"vault")
		await _settle()
		await _capture("canonical-character-files-1280x720")
		var vault_inspect := _button_named(_router, "Inspect")
		if vault_inspect != null:
			vault_inspect.pressed.emit(); await _settle(); await _capture_canonical_compact("canonical-character-file-inspection-1280x720", "classic-character-file-inspection-800x600")
		var vault_back := _button_named(_router, "Back to character vault"); if vault_back != null: vault_back.pressed.emit(); await _settle()
	await _resize(Vector2i(800, 600)); await _capture("classic-character-files-800x600")
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("classic-six-member-roster-800x600")
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
	await _capture_canonical_compact("wide-party-wealth-1280x720", "classic-party-wealth-800x600")
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
	var combat_media := _application.presentation_media.catalog()
	var combat_request := ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT)
	var combat_body := combat_request.body as CombatRequestBody
	var gallery_hero_id: String = gallery_view.party_members[0].id
	var gallery_monster_id: String = combat_fixture.monsters[0].id
	combat_body.actor_id = gallery_hero_id; combat_body.combatants[0].id = gallery_hero_id; combat_body.combatants[1].id = gallery_monster_id; combat_body.targets[0].id = gallery_monster_id
	_interaction.present(combat_request, "", gallery_view, combat_media)
	await _settle()
	await _capture("canonical-combat-tactical-workspace-1280x720")
	_application._battlefield_presenter.interaction.toggle_reveal_friends()
	await _settle()
	await _capture("canonical-combat-reveal-friends-1280x720")
	_application._battlefield_presenter.interaction.toggle_reveal_friends()
	_application._battlefield_presenter.interaction.set_movement_costs_visible(true)
	await _settle()
	await _capture("canonical-combat-movement-aid-1280x720")
	_application._battlefield_presenter.interaction.set_movement_costs_visible(false)
	await _resize(Vector2i(800, 600)); _application._battlefield_presenter.visible = true
	await _settle()
	await _capture("classic-combat-tactical-workspace-800x600")
	var spells_button := _interaction.find_child("CombatCommandSpells", true, false) as Button
	if spells_button != null and not spells_button.disabled:
		spells_button.pressed.emit(); await _settle(); _application._battlefield_presenter.visible = true; await _settle()
		await _capture("classic-combat-spellbook-800x600")
		await _resize(Vector2i(1280, 720)); _application._battlefield_presenter.visible = true; await _settle()
		await _capture("canonical-combat-spellbook-1280x720")
		var aim_button := _shell.find_child("CombatSpellAim", true, false) as Button
		if aim_button != null and not aim_button.disabled:
			aim_button.pressed.emit(); await _settle(); _application._battlefield_presenter.visible = true; await _settle(); await _capture("canonical-combat-targeting-1280x720")
			await _resize(Vector2i(800, 600)); _application._battlefield_presenter.visible = true; await _settle(); await _capture("classic-combat-targeting-800x600"); await _resize(Vector2i(1280, 720)); _application._battlefield_presenter.visible = true; await _settle()
			_application._battlefield_presenter.interaction.cancel_targeting()
	_interaction.present(combat_request, "", gallery_view, combat_media)
	var battle_entry := CombatPlaybackFrame.new(&"battle_cue", 0.28); battle_entry.display_text = "Battle begins"
	_application._battlefield_presenter.present_playback_frame(battle_entry); _interaction.present_combat_playback_mask(battle_entry); await _settle(); await _capture("canonical-combat-entry-1280x720")
	var automatic_move := CombatPlaybackFrame.new(&"move_start", 0.02); automatic_move.actor_id = gallery_hero_id; automatic_move.from_coordinate = Vector2i(45, 45); automatic_move.to_coordinate = Vector2i(46, 45); automatic_move.automatic = true
	_application._battlefield_presenter.present_playback_frame(automatic_move); _interaction.update_combat_playback_frame(automatic_move); var actor_cue := CombatPlaybackFrame.new(&"actor_cue", 0.2); actor_cue.actor_id = gallery_hero_id; actor_cue.display_text = "Now acting"; actor_cue.automatic = true; _interaction.update_combat_playback_frame(actor_cue); var attack_cue := CombatPlaybackFrame.new(&"melee_attack", 0.2); attack_cue.actor_id = gallery_hero_id; attack_cue.target_id = gallery_monster_id; attack_cue.automatic = true; _interaction.update_combat_playback_frame(attack_cue); var result_cue := CombatPlaybackFrame.new(&"result", 0.2); result_cue.actor_id = gallery_hero_id; result_cue.target_id = gallery_monster_id; result_cue.display_text = "4 damage"; result_cue.automatic = true; _interaction.update_combat_playback_frame(result_cue); await _settle(); await _capture("canonical-combat-auto-playback-1280x720"); await _resize(Vector2i(800, 600)); _application._battlefield_presenter.visible = true; await _settle(); await _capture("classic-combat-auto-playback-800x600"); await _resize(Vector2i(1280, 720)); _application._battlefield_presenter.visible = true; await _settle(); _interaction.queue_classic_flash_messages([{"text": "New Combat Round.", "soundId": 139, "autoCloseSeconds": 2.0}]); await _settle(); await _capture("canonical-combat-new-round-1280x720"); await create_timer(2.1).timeout
	var victory_cue := CombatPlaybackFrame.new(&"battle_cue", 0.28); victory_cue.display_text = "Victory"
	_application._battlefield_presenter.present_playback_frame(victory_cue); _interaction.update_combat_playback_frame(victory_cue); await _settle(); await _capture("canonical-combat-terminal-cue-1280x720")
	_application._battlefield_presenter.clear_playback_frame()
	_interaction.present(null)
	gallery_view.combat_view = null
	_application._map_presenter.present(gallery_view); _shell.present(gallery_view); await _resize(Vector2i(1280, 720)); await _settle()
	var current_save := SAVE_SLOT_PREVIEW_SCRIPT.new("C", SAVE_SLOT_PREVIEW_SCRIPT.PRIMARY, SAVE_SLOT_PREVIEW_SCRIPT.VALID); current_save.rules_version = gallery_view.rules_version; current_save.package_hash = "1".repeat(64); current_save.realmz_day = 5; current_save.realmz_hour = 15; current_save.realmz_minute = 55; current_save.map_id = "land:0"; current_save.coordinate = Vector2i(49, 15); current_save.character_names = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]; current_save.can_load = true; current_save.map_preview_jpeg = _application._map_presenter.save_map_preview_jpeg(); assert(not current_save.map_preview_jpeg.is_empty(), "Save gallery needs a rendered overworld JPEG.")
	var backup_save := SAVE_SLOT_PREVIEW_SCRIPT.new("C", SAVE_SLOT_PREVIEW_SCRIPT.BACKUP, SAVE_SLOT_PREVIEW_SCRIPT.VALID); backup_save.rules_version = gallery_view.rules_version; backup_save.character_names = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]; backup_save.can_load = true
	var corrupt_save := SAVE_SLOT_PREVIEW_SCRIPT.new("broken", SAVE_SLOT_PREVIEW_SCRIPT.PRIMARY, SAVE_SLOT_PREVIEW_SCRIPT.CORRUPT); corrupt_save.error_message = "This save is corrupt or uses an unsupported schema. The active session is unchanged."
	_router.content_presenter.set_save_previews([current_save, backup_save, corrupt_save], "C", "C")
	_router.open_screen(&"save_load")
	await _settle()
	await _capture_canonical_compact("canonical-save-modal-1280x720", "compact-save-modal-800x600")
	var corrupt_row := _router.find_child("SavePreview_broken_primary", true, false) as Button
	corrupt_row.pressed.emit(); await _settle(); await _capture("canonical-system-corrupt-save-1280x720"); _router.content_presenter.set_save_previews([current_save, backup_save], "C", "C"); _router.open_screen(&"system")
	var system_tabs := _router.find_child("SystemWorkspaceTabs", true, false) as TabContainer
	for index: int in range(1, 6):
		(system_tabs.get_parent().get_parent() as SystemPreferencesLayout).show_category(SystemPreferencesLayout.PREFERENCE_SECTIONS[index - 1]); await _settle(); await _capture("canonical-system-%s-1280x720" % ["display", "audio", "accessibility", "controls", "diagnostics"][index - 1])
	system_tabs.current_tab = 2; await _settle(); (_router.find_child("OpenMusicPlaylist", true, false) as Button).pressed.emit(); await _settle(); await _capture("canonical-music-playlist-1280x720"); (_shell.find_child("MusicDone", true, false) as Button).pressed.emit(); await _settle()
	await _resize(Vector2i(800, 600)); _router.open_screen(&"system"); await _settle(); system_tabs = _router.find_child("SystemWorkspaceTabs", true, false) as TabContainer
	for index: int in range(0, 6):
		(system_tabs.get_parent().get_parent() as SystemPreferencesLayout).show_saves() if index == 0 else (system_tabs.get_parent().get_parent() as SystemPreferencesLayout).show_category(SystemPreferencesLayout.PREFERENCE_SECTIONS[index - 1]); await _settle(); await _capture("classic-system-%s-800x600" % ["save-load", "display", "audio", "accessibility", "controls", "diagnostics"][index])
	system_tabs.current_tab = 2; await _settle(); (_router.find_child("OpenMusicPlaylist", true, false) as Button).pressed.emit(); await _settle(); await _capture("classic-music-playlist-800x600"); (_shell.find_child("MusicDone", true, false) as Button).pressed.emit(); await _settle()
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_150, PresentationSettings.DISPLAY_INTEGER_CANVAS, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.5)
	_router.open_screen(&"system")
	await _settle()
	await _capture("compact-system-ui150-text150-800x600")
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_INTEGER_CANVAS, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
	await _resize(Vector2i(1280, 720)); _router.open_screen(&"exploration")
	_interaction.present(APPLICATION_LIFECYCLE_SCRIPT.end_adventure_request(false), "", gallery_view, gallery_media); await _settle(); await _capture_canonical_compact("canonical-end-adventure-1280x720", "classic-end-adventure-800x600")
	await _resize(Vector2i(1280, 720)); _interaction.present(APPLICATION_LIFECYCLE_SCRIPT.quit_application_request(true, false), "", gallery_view, gallery_media); await _settle(); await _capture("canonical-quit-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-quit-800x600")
	_interaction.present(null); _router.content_presenter.set_save_and_quit_mode(true); await _resize(Vector2i(1280, 720)); _router.open_screen(&"system"); await _settle(); await _capture("canonical-save-and-quit-1280x720"); await _resize(Vector2i(800, 600)); await _capture("classic-save-and-quit-800x600"); _router.content_presenter.set_save_and_quit_mode(false); _router.open_screen(&"exploration"); _shell.present(gallery_view); await _resize(Vector2i(1920, 1080)); await _capture("fit-explore-1920x1080"); await _resize(Vector2i(3440, 1440)); await _capture("fit-explore-ultrawide-3440x1440"); await _resize(Vector2i(3840, 2160)); await _capture("fit-explore-4k-3840x2160")
	_application.queue_free()
	await process_frame
	if _sizing_matrix:
		var required_surfaces: Array[String] = _surface_filters.duplicate() if not _surface_filters.is_empty() else SIZING_MATRIX_SURFACES
		for surface_id: String in required_surfaces:
			assert(_sizing_matrix_surfaces.has(surface_id), "Sizing matrix did not capture major surface %s." % surface_id)
		assert(_sizing_matrix_surfaces.size() == required_surfaces.size(), "Sizing matrix captured %d major surfaces; expected exactly %d." % [_sizing_matrix_surfaces.size(), required_surfaces.size()])
		_matrix_metadata.close()
	if _raw_scenes:
		_raw_scene_metadata.close()
	if _audit_scaling:
		_audit_metadata.close()
		assert(not _audit_states.is_empty(), "Scaling audit did not match any prepared gallery state.")
		print("SCALING AUDIT: %d states, %d samples, %d samples with unreachable controls" % [_audit_states.size(), _audit_states.size() * ScalingAudit.SETTINGS.size(), _audit_failures])
	quit(1 if _audit_failures else 0)


func _close_prepared_fixture_adventure() -> void:
	if not _application.session_controller.view().session_started:
		return
	_application.lifecycle_host.request_end_adventure()
	await _settle()
	var response := InteractionResponse.new(
		APPLICATION_LIFECYCLE_SCRIPT.END_ADVENTURE_REQUEST_ID,
		InteractionRequest.SESSION_LIFECYCLE,
		InteractionResponse.LifecycleBody.new(APPLICATION_LIFECYCLE_SCRIPT.END_WITHOUT_SAVING)
	)
	_application.lifecycle_host.respond(response)
	await _settle()
	assert(not _application.session_controller.view().session_started, "The isolated fixture adventure could not be closed through the application lifecycle.")


func _capture_raw_scenes() -> void:
	await _resize(Vector2i(1280, 720))
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
	_application.visible = false
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENE_PREVIEW_REGISTRY_PATH))
	assert(registry is Dictionary and registry.get("sceneContracts") is Dictionary and registry.get("scenes") is Array, "Scene preview registry is malformed.")
	var viewport := _compositor.source_viewport()
	for entry: Variant in registry["scenes"]:
		assert(entry is Dictionary and entry.get("id") is String and entry.get("scene") is String, "Scene preview registry has an invalid scene entry.")
		var surface_id: String = entry["id"]
		if not _surface_filters.is_empty() and not _surface_filters.has(surface_id):
			continue
		var scene_contract: Dictionary = registry["sceneContracts"].get(surface_id, {})
		var raw_anchors: Variant = scene_contract.get("rawSceneNodes")
		assert(raw_anchors is Array, "Scene preview registry is missing raw anchors for %s." % surface_id)
		var packed := load("res://%s" % entry["scene"]) as PackedScene
		assert(packed != null, "Raw scene is unavailable for %s." % surface_id)
		var raw_root := packed.instantiate()
		assert(raw_root is Control, "Raw scene %s has a non-Control root and cannot be mounted in the gallery." % surface_id)
		var raw_control := raw_root as Control
		raw_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		raw_control.theme = _shell.theme
		raw_control.visible = true
		viewport.add_child(raw_control)
		await _settle()
		var raw_display_adaptations := _apply_raw_display_adaptations(surface_id, raw_control)
		await _settle()
		await _save_capture("raw-%s" % surface_id, "")
		var resolved_anchors: Array[Dictionary] = []
		for anchor: Variant in raw_anchors:
			assert(anchor is String, "Raw scene anchor must be a string for %s." % surface_id)
			var resolved_nodes: Array[Dictionary] = []
			for node: Node in _resolve_raw_anchor_nodes(raw_control, anchor):
				resolved_nodes.append({"name": str(node.name), "class": node.get_class(), "relativePath": str(raw_control.get_path_to(node)), "visible": (node as Control).visible if node is Control else true})
			resolved_anchors.append({"registeredAnchor": anchor, "nodes": resolved_nodes})
		var actual_window := DisplayServer.window_get_size()
		_raw_scene_metadata.store_line(JSON.stringify({"surfaceId": surface_id, "scene": entry["scene"], "rawSceneNodes": raw_anchors, "resolvedStableNodes": resolved_anchors, "rawDisplayAdaptations": raw_display_adaptations, "editorLikeDisplay": true, "actualWindow": [actual_window.x, actual_window.y], "boundPreview": false}))
		raw_control.queue_free()
		await process_frame
	_application.visible = true
	await _settle()


func _apply_raw_display_adaptations(surface_id: String, raw_root: Control) -> Array[Dictionary]:
	var adaptations: Array[Dictionary] = []
	match surface_id:
		"application-shell":
			_set_raw_visibility(raw_root, "StageFrame", true, adaptations)
			_set_raw_visibility(raw_root, "BottomRegion", true, adaptations)
			_set_raw_visibility(raw_root, "PartyRoster", true, adaptations)
			_set_raw_visibility(raw_root, "ScreenNavigator", true, adaptations)
			_set_raw_visibility(raw_root, "ScreenNavigator/OverlayHost/SplashScreen", false, adaptations)
		"party-import-from-save":
			# The production root starts hidden and is shown only after host data is bound.
			# Expose its authored dialog frame here without populating any party rows.
			_set_raw_visibility(raw_root, ".", true, adaptations)
		"lifecycle-prompts":
			# Show the authored end-adventure variant; response buttons remain unbound.
			_set_raw_visibility(raw_root, "LifecycleConsequence", true, adaptations)
			_set_raw_visibility(raw_root, "LifecycleVerticalActions", true, adaptations)
			_set_raw_visibility(raw_root, "LifecycleActions", false, adaptations)
	return adaptations


func _set_raw_visibility(raw_root: Control, node_path: String, desired: bool, adaptations: Array[Dictionary]) -> void:
	var node: Node = raw_root if node_path == "." else raw_root.get_node_or_null(node_path)
	assert(node is Control, "Raw-scene display adaptation target %s is missing for %s." % [node_path, raw_root.name])
	var control := node as Control
	var previous := control.visible
	control.visible = desired
	adaptations.append({"nodePath": node_path, "visibleBefore": previous, "visibleAfter": desired})


func _resolve_raw_anchor_nodes(raw_root: Control, anchor: String) -> Array[Node]:
	var matches: Array[Node] = []
	if anchor.ends_with("*"):
		var prefix := anchor.trim_suffix("*")
		var candidates: Array[Node] = [raw_root]
		candidates.append_array(raw_root.find_children("*", "", true, false))
		for node: Node in candidates:
			if str(node.name).begins_with(prefix):
				matches.append(node)
	else:
		var found := raw_root.find_child(anchor, true, false)
		if found != null:
			matches.append(found)
	return matches


func _capture_compact_canonical(compact_label: String, canonical_label: String) -> void:
	await _resize(Vector2i(800, 600)); await _capture(compact_label); await _resize(Vector2i(1280, 720)); await _capture(canonical_label)


func _capture_canonical_compact(canonical_label: String, compact_label: String) -> void:
	await _capture(canonical_label); await _resize(Vector2i(800, 600)); await _capture(compact_label); await _resize(Vector2i(1280, 720))


func _capture_optional_canonical_compact(canonical_label: String, compact_label: String, capture_canonical: bool) -> void:
	if capture_canonical: await _capture(canonical_label)
	await _resize(Vector2i(800, 600)); await _capture(compact_label); await _resize(Vector2i(1280, 720))


func _capture_character_section(button_label: String, capture_name: String) -> void:
	var button := _button_named(_router, button_label)
	if button != null:
		button.pressed.emit()
		await _settle()
	await _capture_optional_canonical_compact("canonical-character-%s-1280x720" % capture_name, "classic-character-%s-800x600" % capture_name, button != null)


func _capture_canonical_compact_leave(canonical_label: String, compact_label: String) -> void:
	await _capture(canonical_label); await _resize(Vector2i(800, 600)); await _capture(compact_label)


func _resize(size: Vector2i) -> void:
	root.size = size
	DisplayServer.window_set_size(size)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	if _audit_scaling:
		var state := ScalingAudit.state_key(label)
		if not state.is_empty() and (_audit_filter.is_empty() or Array(_audit_filter.split(",", false)).any(func(filter: String) -> bool: return state.contains(filter))) and not _audit_states.has(state):
			_audit_states[state] = true
			await _capture_scaling_audit(state)
		return
	if _sizing_matrix:
		var surface_id := _surface_id_for_capture(label)
		if surface_id.is_empty() or (not _surface_filters.is_empty() and not _surface_filters.has(surface_id)) or _sizing_matrix_surfaces.has(surface_id):
			return
		_sizing_matrix_surfaces[surface_id] = true
		await _capture_sizing_surface(surface_id)
		return
	if not _surface_filters.is_empty() and not _surface_filters.has(_surface_id_for_capture(label)):
		return
	await _save_capture(label, "")


func _capture_scaling_audit(state: String) -> void:
	var original_size := DisplayServer.window_get_size()
	var visibility: Array[bool] = [_application._map_presenter.visible, _application._battlefield_presenter.visible, (_application.get("_dungeon_presenter") as Control).visible]
	for setting: Array in ScalingAudit.SETTINGS:
		var dimensions: Vector2i = setting[0]
		await _resize(dimensions)
		await _apply_sizing_settings(setting[1], setting[3], PresentationSettings.TYPOGRAPHY_CLASSIC, setting[2])
		await _restore_capture_visibility(visibility)
		var failures := ScalingAudit.inspect(_application)
		var profile := _shell.get("_profile") as UiLayoutProfile
		var label := "%s-%dx%d-%s-text%d-%s" % [state, dimensions.x, dimensions.y, setting[1], int(setting[2] * 100), setting[3]]
		var image := root.get_texture().get_image()
		assert(image != null and not image.is_empty(), "Scaling audit requires a graphical driver.")
		assert(image.save_png(ScalingAudit.OUTPUT_ROOT.path_join(label + ".png")) == OK, "Scaling audit capture failed.")
		_audit_metadata.store_line(JSON.stringify({"state": state, "capture": label, "actualWindow": [root.size.x, root.size.y], "profile": profile.id, "effectiveScale": profile.ui_scale, "fontScale": profile.font_scale, "failures": failures}))
		_audit_metadata.flush()
		if not failures.is_empty(): _audit_failures += 1
		print("SCALING %s: %s (%d bounds failures)" % ["PASS" if failures.is_empty() else "FAIL", label, failures.size()])
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
	await _resize(original_size)
	await _restore_capture_visibility(visibility)


func _surface_id_for_capture(label: String) -> String:
	var representatives := {
		"canonical-explore-1280x720": "application-shell",
		"canonical-character-overview-1280x720": "character-sheet",
		"canonical-character-files-1280x720": "character-files",
		"canonical-allies-populated-1280x720": "allies",
		"canonical-bestiary-1280x720": "bestiary",
		"wide-dense-inventory-1280x720": "inventory",
		"wide-spells-1280x720": "spells",
		"canonical-location-service-1280x720": "services",
		"wide-journal-1280x720": "maps-journal",
		"canonical-system-display-1280x720": "system",
		"canonical-campaign-menu-hover-1280x720": "campaign-selection",
		"canonical-party-setup-1280x720": "party-assembly",
		"canonical-party-import-from-save-1280x720": "party-import-from-save",
		"canonical-character-creator-review-1280x720": "character-creation",
		"canonical-shop-interaction-1280x720": "shop",
		"wide-treasure-distribution-1280x720": "treasure",
		"wide-encounter-1280x720": "encounter",
		"wide-level-result-1280x720": "level-up",
		"canonical-end-adventure-1280x720": "lifecycle-prompts",
		"canonical-scrolling-text-1280x720": "scrolling-text",
		"canonical-combat-tactical-workspace-1280x720": "combat-command-deck",
		"canonical-combat-spellbook-1280x720": "roster-spellbook",
	}
	if representatives.has(label):
		return representatives[label]
	if label.begins_with("wide-interaction-temple-"):
		return "temple"
	if label.begins_with("wide-interaction-bank-"):
		return "bank"
	if label.begins_with("wide-interaction-pick-lock-"):
		return "pick-lock"
	return ""


func _capture_sizing_surface(surface_id: String) -> void:
	var original_size := DisplayServer.window_get_size()
	var spatial_visibility: Array[bool] = [_application._map_presenter.visible, _application._battlefield_presenter.visible, (_application.get("_dungeon_presenter") as Control).visible]
	for size: Vector2i in SIZING_MATRIX_SIZES:
		await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
		await _resize(size)
		await _restore_capture_visibility(spatial_visibility)
		await _save_capture("%s-%dx%d-auto-responsive-classic" % [surface_id, size.x, size.y], surface_id)
	if surface_id == "application-shell":
		await _resize(Vector2i(2560, 1392))
		for display_mode: String in [PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.DISPLAY_INTEGER_WINDOW, PresentationSettings.DISPLAY_INTEGER_CANVAS, PresentationSettings.DISPLAY_FILL_WINDOW]:
			for typography: String in [PresentationSettings.TYPOGRAPHY_CLASSIC, PresentationSettings.TYPOGRAPHY_READABLE]:
				await _apply_sizing_settings(PresentationSettings.UI_SCALE_150, display_mode, typography, 1.5)
				await _restore_capture_visibility(spatial_visibility)
				await _save_capture("application-shell-2560x1392-manual150-maxtext-%s-%s" % [display_mode, typography], surface_id)
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
	await _resize(original_size)
	await _restore_capture_visibility(spatial_visibility)


func _restore_capture_visibility(spatial_visibility: Array[bool]) -> void:
	# Gallery-only detached combat views must survive the live session's resize visibility refresh.
	_application._map_presenter.visible = spatial_visibility[0]
	_application._battlefield_presenter.visible = spatial_visibility[1]
	(_application.get("_dungeon_presenter") as Control).visible = spatial_visibility[2]
	(_application.get("_spatial_layout") as ApplicationSpatialLayout).sync_display_world_region(_compositor, _application.get("_presentation_settings") as PresentationSettings)
	await _settle()


func _capture_stress_roster(gallery_view: GameView) -> void:
	assert(gallery_view.party_members.size() == 6, "Stress roster capture requires six populated party rows.")
	var stress_names: Array[String] = ["Alaric Willowmere of Northgate", "Beatrice Ashenford, Warden of the Vale", "Corvin Thistlewick the Far-Seeing", "Drusilla Vexmoor of the Western March", "Elias Greenbriar, Keeper of the Old Road", "Farael Brightforge the Unbroken"]
	var original_characters: Array[Dictionary] = []
	for index: int in 6:
		var character: CharacterView = gallery_view.party_members[index]
		assert(not character.portrait_id.is_empty(), "Stress roster row %d must retain a source portrait identity." % (index + 1))
		original_characters.append({"name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points})
		character.name = stress_names[index]
		character.current_health = 876543 - index
		character.maximum_health = 987654 - index
		character.spell_points = 654321 - index
		character.maximum_spell_points = 765432 - index
	var narrative := _shell.find_child("NarrativeText", true, false) as RichTextLabel
	var old_narrative_text := narrative.text
	var old_narrative_history := str(_shell.status.get("_narrative_history"))
	_shell.status.set("_narrative_history", "")
	narrative.text = ""
	_shell.status.append_narrative(("Six travelers cross the northern road together, each carrying a separate account of the weather, the pass ahead, and the lights moving along the ridge. ").repeat(4))
	_shell.present(gallery_view)
	await _settle()
	var original_window := DisplayServer.window_get_size()
	for size: Vector2i in [Vector2i(800, 600), Vector2i(1280, 720), Vector2i(2560, 1392)]:
		await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
		await _resize(size)
		await _save_capture("stress-roster-%dx%d-default" % [size.x, size.y], "")
		await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.5)
		await _resize(size)
		await _save_capture("stress-roster-%dx%d-maxtext" % [size.x, size.y], "")
	for index: int in 6:
		var character: CharacterView = gallery_view.party_members[index]
		var original: Dictionary = original_characters[index]
		character.name = original["name"]
		character.current_health = original["currentHealth"]
		character.maximum_health = original["maximumHealth"]
		character.spell_points = original["spellPoints"]
		character.maximum_spell_points = original["maximumSpellPoints"]
	_shell.status.set("_narrative_history", old_narrative_history)
	narrative.text = old_narrative_text
	await _apply_sizing_settings(PresentationSettings.UI_SCALE_AUTO, PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.TYPOGRAPHY_CLASSIC, 1.0)
	await _resize(original_window)
	_shell.present(gallery_view)
	await _settle()


func _apply_sizing_settings(scale_mode: String, display_mode: String, typography: String, text_scale: float) -> void:
	var settings := _application.get("_presentation_settings") as PresentationSettings
	settings.ui_scale_mode = scale_mode
	settings.display_scaling_mode = display_mode
	settings.typography_mode = typography
	settings.text_scale = text_scale
	_compositor.configure(display_mode, settings.pixel_art_smoothing, settings.crt_enabled, settings.crt_shader, settings.crt_area)
	_shell.apply_settings(settings)
	_interaction.set_text_scale(text_scale)
	var spatial_layout: Object = _application.get("_spatial_layout")
	spatial_layout.set_world_zoom(settings.world_zoom if display_mode == PresentationSettings.DISPLAY_INTEGER_CANVAS else 1)
	await _settle()


func _save_capture(label: String, surface_id: String) -> void:
	var viewport_texture := root.get_texture(); assert(viewport_texture != null, "UI gallery requires a graphical display driver."); var image := viewport_texture.get_image(); assert(image != null and not image.is_empty(), "UI gallery could not capture rendered frame %s." % label)
	var path := "%s/%s.png" % [OUTPUT_ROOT, label]; var error := image.save_png(ProjectSettings.globalize_path(path))
	assert(error == OK, "Unable to save UI gallery frame %s: %s" % [label, error_string(error)])
	if label.begins_with("stress-roster-"):
		var boundaries: Dictionary = {}
		for control_name: String in ["BottomRegion", "NarrativeWell", "CommandPanel", "PartyEffectsRow", "CommandGrid", "EffectsPanel", "TorchDock"]:
			var control := _shell.get_node("%" + control_name) as Control
			var minimum := control.get_combined_minimum_size()
			boundaries[control_name] = {"minimum": [minimum.x, minimum.y], "position": [control.global_position.x, control.global_position.y], "size": [control.size.x, control.size.y]}
		print("UI_SIZING_BOUNDARIES: %s • %s" % [label, JSON.stringify(boundaries)])
	if not surface_id.is_empty():
		var profile := _shell.get("_profile") as UiLayoutProfile
		var settings := _application.get("_presentation_settings") as PresentationSettings
		var actual_window := DisplayServer.window_get_size()
		var metadata := {"surfaceNames": [surface_id], "capture": label, "actualWindow": [actual_window.x, actual_window.y], "profile": String(profile.id), "effectiveScale": profile.ui_scale, "requestedScale": profile.requested_scale, "fontScale": profile.font_scale, "uiScaleMode": settings.ui_scale_mode, "textScale": settings.text_scale, "typography": settings.typography_mode, "displayMode": settings.display_scaling_mode}
		_matrix_metadata.store_line(JSON.stringify(metadata))
		print("CAPTURED: %s • %s • %s" % [path, surface_id, actual_window])
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
	tiles.resize(BattlefieldGrid.CELL_COUNT)
	tiles.fill(232)
	for y: int in range(38, 53):
		for x: int in range(36, 55):
			tiles[y * BattlefieldGrid.SIZE + x] = 1 + posmod(x * 7 + y * 11, 200)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var hero_view: Variant = game_view.party_members[0]
	var hero := CharacterState.new(hero_view.id, hero_view.name, hero_view.current_health, hero_view.maximum_health)
	hero.combat_icon_id = hero_view.combat_icon_id
	hero.movement = 8
	hero.maximum_movement = 10
	battlefield.actors.place_character(hero.id, Vector2i(45, 45))
	var monster := MonsterState.new("gallery.goblin", "classic.monster.1", "Goblin Raider", 8, 10)
	monster.icon_id = 9001
	battlefield.actors.place_monster(monster.id, Vector2i(47, 45), 0)
	var combat := CombatState.new("classic.battle.1", [monster], 0, battlefield)
	combat.set_turn_order([hero.id, monster.id]); combat.spell_runtime.queue_persistent_field("classic.spell.1309", hero.id, Vector2i(49, 45), 0, 10, 15, 1, 3, 2)
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
