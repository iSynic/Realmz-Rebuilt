## Verifies editor-only fixtures through the same production binders used at runtime.

extends RealmzTestCase

const PREVIEW_FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
const AUTHORING_SAMPLES := preload("res://addons/realmz_builder/realmz_builder_authoring_samples.gd")
var _surfaces: Dictionary = {}
var _contracts: Dictionary = {}
var _profiles: Array[String] = []
var _editor_records: Dictionary = {}


func run() -> void:
	_test_editor_sample_snapshot()
	await _test_editable_authoring_samples()
	await _test_compact_authoring_samples()
	await _test_inventory_preview_geometry()
	await _test_modular_authoring_roundtrip()
	_test_theme_inheritance_through_authored_scene()
	_test_modular_theme_inheritance()
	_test_all_profiles_bind_through_production_components()
	_test_representative_collections_and_modes()
	_test_character_facts_survive_rebinding()
	_test_fixed_slot_controls_survive_rebinding()


func _test_editor_sample_snapshot() -> void:
	var file := FileAccess.open_compressed("res://addons/realmz_builder/editor_samples.json.gz", FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	assert_not_null(file, "editor-safe sample snapshot is available")
	if file == null:
		return
	var samples: Dictionary = JSON.parse_string(file.get_as_text())
	_editor_records = samples
	assert_equal(samples.size(), 175, "editor samples cover the 30 registered screens and supported states")
	for profile: String in ["Wide", "Compact", "Long Content", "Unavailable", "Error"]:
		var records: Array = samples["scrolling-text/%s" % profile]
		assert_true(records.any(func(record: Dictionary) -> bool: return str(record.path).ends_with("/ClassicScrollingText") and str(record.properties).contains("Chronicle") or profile == "Error" and str(record.properties).contains("archivist")), "scrolling-text %s has representative editor text on the authored node" % profile)
	var inventory := (load("res://src/ui/inventory/inventory_screen.tscn") as PackedScene).instantiate() as Control
	var rows := inventory.find_child("ItemList", true, false) as Container
	var original_count := rows.get_child_count()
	var projection := AUTHORING_SAMPLES.new()
	var inventory_records: Array = samples["inventory/Wide"]
	projection.populate_snapshot(inventory, inventory_records)
	assert_true(rows.get_child_count() > original_count and rows.get_children().any(func(row: Node) -> bool: return row.owner == null), "Inventory projects ownerless variable rows into its edited production scene")
	projection.clear()
	assert_equal(rows.get_child_count(), original_count, "clearing the Inventory sample restores its authored row host")
	inventory.free()
	var shell := (load("res://src/ui/shell/game_shell.tscn") as PackedScene).instantiate() as Control
	var shell_projection := AUTHORING_SAMPLES.new()
	var shell_records: Array = samples["application-shell/Wide"]
	shell_projection.populate_snapshot(shell, shell_records)
	var portrait := shell.get_node("PartyRoster/RosterColumn/PartyScroll/PartyList/Position1/Member/Character") as Button
	var search := shell.find_child("SearchModeCommand", true, false) as Control
	var icon := search.get_node_or_null("CommandMargin/CommandContent/IconStage/__BuilderSampleIcon") as TextureRect
	assert_true(shell.theme != null and portrait.icon != null and icon != null and icon.texture != null and icon.owner == null, "editor snapshot provides inherited Classic type, stock portraits, and ownerless command artwork")
	shell_projection.clear()
	assert_true(shell.theme == null and portrait.icon == null and search.get_node_or_null("CommandMargin/CommandContent/IconStage/__BuilderSampleIcon") == null, "preview theme, portraits, and command artwork are removed before save")
	shell.free()


func _test_editable_authoring_samples() -> void:
	var scene := load("res://src/ui/setup/party_setup_workspace.tscn") as PackedScene
	var edited := scene.instantiate() as PartySetupWorkspace
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(edited)
	var title := edited.find_child("SelectedScenarioTitle", true, false) as Label
	var original_text := title.text
	var original_rows := (edited.find_child("ImportedCampaignRows", true, false) as Container).get_child_count()
	var begin_action := edited.find_child("BeginAdventure", true, false) as BaseButton
	var original_disabled := begin_action.disabled
	var original_tooltip := begin_action.tooltip_text
	var samples := AUTHORING_SAMPLES.new()
	var wide_records: Array = _editor_records["party-assembly/Wide"]
	samples.populate_snapshot(edited, wide_records)
	await root.get_tree().process_frame
	var authored_rows := edited.find_child("ImportedCampaignRows", true, false) as Container
	assert_true(title.text != original_text and authored_rows.get_child_count() > original_rows and authored_rows.get_children().all(func(row: Node) -> bool: return row.owner == null) and not begin_action.disabled, "the edited production scene shows detached sample data and action availability without owning rows")
	title.add_theme_color_override(&"font_color", Color.RED)
	samples.clear()
	await root.get_tree().process_frame
	assert_true(title.text == original_text and authored_rows.get_child_count() == original_rows and title.get_theme_color(&"font_color") == Color.RED and begin_action.disabled == original_disabled and begin_action.tooltip_text == original_tooltip, "clearing editor samples restores data and action availability while preserving an authored visual edit")
	var scenario_column := edited.find_child("ScenarioColumn", true, false) as Control
	var authored_width := scenario_column.custom_minimum_size.x
	var history := UndoRedo.new()
	history.create_action("Resize authored scenario column")
	history.add_do_property(scenario_column, "custom_minimum_size", Vector2(authored_width + 12.0, scenario_column.custom_minimum_size.y))
	history.add_undo_property(scenario_column, "custom_minimum_size", scenario_column.custom_minimum_size)
	history.commit_action()
	history.undo()
	assert_equal(scenario_column.custom_minimum_size.x, authored_width, "an authored layout change remains undoable after clearing sample data")
	history.redo()
	history.free()
	edited.free()


func _test_compact_authoring_samples() -> void:
	var scene := load("res://src/ui/setup/party_setup_workspace.tscn") as PackedScene
	var edited := scene.instantiate() as PartySetupWorkspace
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(edited)
	var authored_size := edited.size
	var authored_scenario_width := (edited.find_child("ScenarioColumn", true, false) as Control).custom_minimum_size.x
	var samples := AUTHORING_SAMPLES.new()
	var compact_records: Array = _editor_records["party-assembly/Compact"]
	samples.populate_snapshot(edited, compact_records)
	await root.get_tree().process_frame
	var scenario := edited.find_child("ScenarioColumn", true, false) as Control
	var imported := edited.find_child("ImportedCampaignRows", true, false) as Control
	assert_true(edited.size == Vector2(800.0, 600.0) and scenario.custom_minimum_size.x == edited.compact_scenario_minimum_width and imported.visible and imported.get_child_count() > 0, "Compact samples show the owning screen's complete reflow and populated scenario browser")
	samples.clear()
	await root.get_tree().process_frame
	assert_true(edited.size == authored_size and scenario.custom_minimum_size.x == authored_scenario_width and imported.get_child_count() == 0, "clearing Compact samples restores the authored Wide scene without keeping fixture rows")
	edited.free()


func _test_inventory_preview_geometry() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	tree.root.add_child(viewport)
	var edited := (load("res://src/ui/inventory/inventory_screen.tscn") as PackedScene).instantiate() as InventoryScreen
	edited.size = Vector2(1280, 720)
	viewport.add_child(edited)
	await tree.process_frame
	var clip := edited.get_node("WorkspaceColumn/BodyClip") as Control
	var scroll := edited.scroll_control()
	var inspector := edited.item_inspector_panel()
	var samples := AUTHORING_SAMPLES.new()
	for profile: String in ["Wide", "Long Content", "Empty", "Wide"]:
		var inventory_records: Array = _editor_records["inventory/%s" % profile]
		samples.populate_snapshot(edited, inventory_records)
		await tree.process_frame
		assert_true(scroll.offset_right == 0.0 and scroll.offset_bottom == 0.0 and scroll.size == clip.size, "%s Inventory sample retains authored scroll geometry" % profile)
		if profile == "Wide":
			assert_true(inspector.global_position.y + inspector.size.y <= clip.global_position.y + clip.size.y, "Inventory inspector remains inside the authored Wide screen")
		samples.clear()
	viewport.queue_free()


func _test_modular_authoring_roundtrip() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scene := load("res://src/ui/shell/modular_hud.tscn") as PackedScene
	var edited := scene.instantiate() as ModularHud
	tree.root.add_child(edited)
	var world := edited.get_node("World") as Control
	var authored_position := world.position
	var roster_panel := edited.get_node("Roster") as Control
	var authored_roster_position := roster_panel.position
	var samples := AUTHORING_SAMPLES.new()
	var modular_records: Array = _editor_records["modular-hud/Compact"]
	samples.populate_snapshot(edited, modular_records)
	await tree.process_frame
	var icon := edited.find_child("CampCommand", true, false) as ClassicBitmapButton
	assert_true(roster_panel.position != authored_roster_position and icon.get_node_or_null("CommandMargin/CommandContent/IconStage/__BuilderSampleIcon") != null, "the edited Modular screen shows the Compact panel positions and original command art")
	samples.clear()
	await tree.process_frame
	assert_true(roster_panel.position == authored_roster_position and icon.get_node_or_null("CommandMargin/CommandContent/IconStage/__BuilderSampleIcon") == null, "clearing Modular samples restores authored placement and removes temporary command art")
	world.position.x += 12.0
	var local_surface := world.get_node("Surface") as PanelContainer
	var local_style := StyleBoxFlat.new()
	local_style.bg_color = Color(0.2, 0.4, 0.6)
	local_surface.add_theme_stylebox_override(&"panel", local_style)
	var packed := PackedScene.new()
	assert_equal(packed.pack(edited), OK, "the edited Modular production scene packs after sample cleanup")
	var saved_path := "user://realmz-modular-authoring-roundtrip.tscn"
	assert_equal(ResourceSaver.save(packed, saved_path), OK, "the edited Modular production scene saves")
	var reopened := (ResourceLoader.load(saved_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as ModularHud
	assert_true((reopened.get_node("World") as Control).position.x == authored_position.x + 12.0 and (reopened.get_node("World/Surface") as PanelContainer).get_theme_stylebox("panel") is StyleBoxFlat, "reopening retains Modular layout and appearance edits")
	edited.free()
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child(host)
	var shell := (load("res://src/ui/shell/game_shell.tscn") as PackedScene).instantiate() as GameShell
	var old_hud := shell.get_node("ModularHud")
	shell.remove_child(old_hud)
	old_hud.free()
	reopened.name = "ModularHud"
	reopened.visible = false
	shell.add_child(reopened)
	reopened.owner = shell
	reopened.unique_name_in_owner = true
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(shell)
	await tree.process_frame
	var view := GameView.new(1, true, null)
	view.campaign_id = "modular-authoring-fixture"
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.title = "Modular Authoring Fixture"
	view.party_summary = PartySummaryView.new()
	view.party_members.append(CharacterView.new(CharacterState.new("modular.hero", "Hero", 20, 20)))
	shell.present(view)
	shell.settings.hud.modular = true
	shell.refresh_layout()
	var running_style := (shell.hud.get_node("World/Surface") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(shell.hud.active and is_equal_approx((shell.hud.get_node("World") as Control).position.x, authored_position.x + 12.0) and running_style != null and running_style.bg_color == local_style.bg_color, "the saved Modular edit drives the running production layout and local surface")
	host.free()
	await tree.process_frame


func _test_theme_inheritance_through_authored_scene() -> void:
	var scene := load("res://src/ui/setup/party_setup_workspace.tscn") as PackedScene
	var workspace := scene.instantiate() as PartySetupWorkspace
	(Engine.get_main_loop() as SceneTree).root.add_child(workspace)
	assert_true(PREVIEW_FIXTURES.bind(workspace, "party-assembly", "Wide"), "the inherited theme probe binds real campaign rows")
	var heading := workspace.find_child("ScenarioHeading", true, false) as Label
	var secondary := workspace.find_child("NoCampaignsState", true, false) as Label
	var row := workspace.find_child("Scenario_*", true, false) as PanelContainer
	var action := row.find_child("LaunchCampaign", true, false) as Button
	var classic_color := heading.get_theme_color(&"font_color")
	var contrast := (load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme).duplicate() as Theme
	var heading_color := Color(0.1, 0.9, 0.6)
	var secondary_color := Color(0.7, 0.3, 0.9)
	var action_color := Color(0.3, 0.8, 0.9)
	contrast.set_color(&"font_color", &"ClassicScenarioHeading", heading_color)
	contrast.set_color(&"font_color", &"ClassicSecondaryText", secondary_color)
	contrast.set_color(&"font_color", &"ClassicTheldrowButton", action_color)
	var selected_font := load("res://src/ui/shared/assets/fonts/AlegreyaSans-Regular.ttf") as Font
	contrast.set_font(&"font", &"Label", selected_font)
	var scaled := ClassicTypography.themed_copy(contrast, PresentationSettings.new(), 1.25)
	assert_true(scaled.get_font(&"font", &"Label") == selected_font and scaled.get_color(&"font_color", &"ClassicScenarioHeading") == heading_color, "runtime typography scales a selected theme without restoring hardcoded Classic role values")
	workspace.theme = contrast
	assert_true(heading.get_theme_color(&"font_color") == heading_color and secondary.get_theme_color(&"font_color") == secondary_color and action.get_theme_color(&"font_color") == action_color, "one temporary theme reaches an embedded scene, its grandchild, and a dynamic production row")
	heading.add_theme_color_override(&"font_color", Color.RED)
	assert_equal(heading.get_theme_color(&"font_color"), Color.RED, "a local visual exception wins over inherited role styling")
	heading.remove_theme_color_override(&"font_color")
	assert_equal(heading.get_theme_color(&"font_color"), heading_color, "removing the exception restores inherited role styling")
	workspace.theme = null
	assert_equal(heading.get_theme_color(&"font_color"), classic_color, "clearing the temporary theme restores the project default without mutating its resource")
	workspace.free()


func _test_modular_theme_inheritance() -> void:
	var hud := (load("res://src/ui/shell/modular_hud.tscn") as PackedScene).instantiate() as ModularHud
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	assert_true(PREVIEW_FIXTURES.bind(hud, "modular-hud", "Wide"), "the authored Modular HUD binds representative data")
	var clock := hud.get_node("Narration/Surface/Column/Body/Content/NarrativeWell/NarrativeColumn/Facts/Clock") as Label
	var original_color := clock.get_theme_color(&"font_color")
	var contrast := (load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme).duplicate() as Theme
	var accent := Color(0.8, 0.15, 0.75)
	contrast.set_color(&"font_color", &"Label", accent)
	hud.theme = contrast
	assert_equal(clock.get_theme_color(&"font_color"), accent, "a contrasting host theme reaches the Modular grandchild through its intentional subtree theme")
	clock.add_theme_color_override(&"font_color", Color.GREEN)
	assert_equal(clock.get_theme_color(&"font_color"), Color.GREEN, "a Modular local override remains local")
	clock.remove_theme_color_override(&"font_color")
	assert_equal(clock.get_theme_color(&"font_color"), accent, "removing the Modular override restores inherited color")
	hud.theme = null
	assert_equal(clock.get_theme_color(&"font_color"), original_color, "removing the contrasting host theme restores the default Modular color")
	hud.free()


func _test_character_facts_survive_rebinding() -> void:
	_load_registry()
	var surface := (_surfaces["character-sheet"] as PackedScene).instantiate() as Control
	var sheet := surface.find_child("ClassicCharacterSheet", true, false) as ClassicCharacterSheet
	var retained := _fixed_character_facts(sheet)
	assert_equal(retained.size(), 72, "the unbound character sheet authors its overview, saves, race/caste, age, scroll and lifetime facts")
	(Engine.get_main_loop() as SceneTree).root.add_child(surface)
	for profile: String in ["Compact", "Empty", "Long Content", "Wide"]:
		PREVIEW_FIXTURES.bind(surface, "character-sheet", profile)
		assert_equal(_fixed_character_facts(sheet), retained, "character facts retain their scene identity through %s rebinding" % profile)
	_free_surface(surface)


func _fixed_character_facts(sheet: ClassicCharacterSheet) -> Array[Node]:
	var result: Array[Node] = []
	for region: String in ["OverviewAttributes", "OverviewCombat", "OverviewStatus"]:
		result.append_array(sheet.find_child(region, true, false).get_node("Content/MetricRows").get_children())
	result.append_array(sheet.find_child("RecordCards", true, false).get_children())
	result.append_array(sheet.find_child("ScrollCards", true, false).get_children())
	result.append_array(sheet.find_child("AgeBands", true, false).get_children())
	for region: String in ["SavingThrowsRegion", "RaceRegion", "CasteRegion"]:
		result.append_array(sheet.find_child(region, true, false).get_node("Content/MetricRows").get_children())
	return result


func _test_fixed_slot_controls_survive_rebinding() -> void:
	_load_registry()
	for surface_id: String in ["spells", "system"]:
		var surface := (_surfaces[surface_id] as PackedScene).instantiate() as Control
		var patterns: Array[String] = []
		patterns.assign(["FastSpellSlot*", "ScrollCaseSlot*"] if surface_id == "spells" else ["SavePreview_?_primary"])
		var retained := _fixed_slot_controls(surface, patterns)
		assert_equal(retained.size(), 15 if surface_id == "spells" else 10, "%s authors every fixed slot before tree entry" % surface_id)
		(Engine.get_main_loop() as SceneTree).root.add_child(surface)
		for profile: String in ["Wide", "Compact", "Empty", "Long Content"]:
			PREVIEW_FIXTURES.bind(surface, surface_id, profile)
			assert_equal(_fixed_slot_controls(surface, patterns), retained, "%s retains fixed slot identities across %s binding" % [surface_id, profile])
		_free_surface(surface)


func _fixed_slot_controls(surface: Control, patterns: Array[String]) -> Array[Node]:
	var result: Array[Node] = []
	for pattern: String in patterns:
		result.append_array(surface.find_children(pattern, "Control", true, false))
	return result


func _test_all_profiles_bind_through_production_components() -> void:
	_load_registry()
	var scene_tree := Engine.get_main_loop() as SceneTree
	for surface_id: String in _surfaces:
		for profile: String in _profiles:
			var surface := (_surfaces[surface_id] as PackedScene).instantiate() as Control
			assert_true(_has_scene_nodes(surface, _contracts[surface_id].rawSceneNodes), "%s composes its raw-scene anchors before tree entry or preview binding" % surface_id)
			scene_tree.root.add_child(surface)
			assert_true(PREVIEW_FIXTURES.bind(surface, surface_id, profile), "%s binds the %s fixture through its production component" % [surface_id, profile])
			assert_true(_has_scene_nodes(surface, _contracts[surface_id].populatedPreviewNodes), "%s exposes populated-preview anchors after binding" % surface_id)
			assert_equal(String(surface.get_meta("realmz_builder_profile", "")), profile, "%s records the active detached preview profile" % surface_id)
			scene_tree.root.remove_child(surface)
			surface.free()


func _test_representative_collections_and_modes() -> void:
	var temple := _bound_surface("temple", "Wide")
	var bank := _bound_surface("bank", "Unavailable")
	var pick_lock := _bound_surface("pick-lock", "Long Content")
	var lifecycle := _bound_surface("lifecycle-prompts", "Wide")
	var scrolling_text := _bound_surface("scrolling-text", "Long Content")
	var level_up := _bound_surface("level-up", "Long Content")
	var encounter := _bound_surface("encounter", "Wide")
	var shop := _bound_surface("shop", "Wide")
	var treasure := _bound_surface("treasure", "Long Content")
	var combat := _bound_surface("combat-command-deck", "Wide")
	var character_sheet := _bound_surface("character-sheet", "Wide")
	var inventory := _bound_surface("inventory", "Long Content")
	var spells := _bound_surface("spells", "Wide")
	var services := _bound_surface("services", "Wide")
	var roster := _bound_surface("roster-spellbook", "Wide")
	var vault := _bound_surface("character-files", "Wide")
	var allies := _bound_surface("allies", "Wide")
	var bestiary := _bound_surface("bestiary", "Wide")
	var journal := _bound_surface("maps-journal", "Wide")
	var system := _bound_surface("system", "Wide")
	var shell := _bound_surface("application-shell", "Wide")
	var campaign_selection := _bound_surface("campaign-selection", "Wide")
	var party_assembly := _bound_surface("party-assembly", "Wide")
	var character_creation := _bound_surface("character-creation", "Wide")
	assert_equal((temple.find_child("TempleCharacterRows", true, false) as VBoxContainer).find_children("*", "Button", false, false).size(), 2, "Temple preview uses the production adventurer-row collection")
	assert_equal((temple.find_child("TempleServiceRows", true, false) as VBoxContainer).find_children("*", "Button", false, false).size(), 3, "Temple preview uses the production service-row collection")
	assert_true((bank.find_child("Pool", true, false) as Button).disabled and (bank.find_child("Share", true, false) as Button).disabled, "Bank unavailable preview binds request-owned disabled actions")
	assert_equal((pick_lock.find_child("TumblerRows", true, false) as VBoxContainer).get_child_count(), 6, "Pick Lock long-content preview uses the production tumbler rows")
	assert_equal((lifecycle.find_child("LifecycleVerticalActions", true, false) as VBoxContainer).get_child_count(), 3, "Lifecycle preview creates the production response choices")
	assert_not_null(scrolling_text.find_child("ClassicScrollingTextDone", true, false), "scrolling-text preview binds the production scrolling surface and fixed action")
	assert_true((level_up.find_child("LevelSpellColumns", true, false) as Control).visible, "Level Up preview binds the production spell-selection workspace")
	assert_false((encounter.find_child("EncounterCommandAction", true, false) as BaseButton).disabled, "Encounter preview binds authored actions to the production command deck")
	assert_true((shop.find_child("ShopStockRows", true, false) as VBoxContainer).get_child_count() > 0, "Shop preview binds production stock rows")
	assert_equal((treasure.find_child("TreasureItemGrid", true, false) as GridContainer).get_child_count(), 35, "Treasure long-content preview binds a full production loot field")
	assert_not_null(combat.find_child("CombatCommandAttack", true, false), "Combat preview binds the production command deck")
	assert_true((character_sheet.find_child("ClassicCharacterSheet", true, false) as Control).visible, "Character preview binds the production complete sheet")
	assert_equal(inventory.find_children("InventoryItem_*", "Button", true, false).size(), 14, "Inventory long-content preview binds production item rows")
	assert_true(spells.find_children("KnownSpell_*", "Button", true, false).size() > 0, "Spells preview binds production spell records")
	assert_equal((services.find_child("MoneyCharacterRows", true, false) as VBoxContainer).get_child_count(), 2, "Services preview binds production money rows")
	assert_true((roster as ClassicPartyRoster).combat_spellbook_active(), "Roster preview opens the production combat spellbook")
	assert_equal(vault.find_children("CharacterFile_*", "PanelContainer", true, false).size(), 2, "Character Files preview binds production vault cards")
	assert_equal(allies.find_children("AllyRow_*", "Button", true, false).size(), 3, "Allies preview binds production ally records")
	assert_equal(bestiary.find_children("BestiaryRow_*", "Button", true, false).size(), 3, "Bestiary preview binds production catalog records")
	assert_equal((journal.find_child("JournalEntryRows", true, false) as VBoxContainer).get_child_count(), 3, "Maps and Journal preview binds production journal records")
	assert_equal(system.find_children("SavePreview_*", "Button", true, false).size(), 12, "Save preview binds ten scenario slots plus two legacy records")
	assert_equal((shell.find_child("PackageStatus", true, false) as Label).text, "City of Bywater", "application-shell preview binds the detached campaign through GameShell")
	assert_equal(campaign_selection.find_children("Scenario_*", "PanelContainer", true, false).size(), 3, "campaign selection preview binds installed scenarios through CampaignLibraryController")
	assert_equal((party_assembly.find_child("PartySlots", true, false) as VBoxContainer).get_child_count(), 6, "party assembly preview binds the retained six-slot party through CampaignPartySetupController")
	assert_not_null(character_creation.find_child("CharacterName", true, false), "character creation preview enters the production identity step")
	for surface: Control in [temple, bank, pick_lock, lifecycle, scrolling_text, level_up, encounter, shop, treasure, combat, character_sheet, inventory, spells, services, roster, vault, allies, bestiary, journal, system, shell, campaign_selection, party_assembly, character_creation]:
		_free_surface(surface)


func _bound_surface(surface_id: String, profile: String) -> Control:
	var surface := (_surfaces[surface_id] as PackedScene).instantiate() as Control
	(Engine.get_main_loop() as SceneTree).root.add_child(surface)
	PREVIEW_FIXTURES.bind(surface, surface_id, profile)
	return surface


func _free_surface(surface: Control) -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(surface)
	surface.free()


func _load_registry() -> void:
	var file := FileAccess.open("res://addons/realmz_builder/scene_previews.json", FileAccess.READ)
	var registry: Dictionary = JSON.parse_string(file.get_as_text())
	_contracts = registry.sceneContracts
	_profiles.assign(registry.profiles)
	for scene: Dictionary in registry.scenes:
		_surfaces[scene.id] = load("res://" + scene.scene)


func _has_scene_nodes(surface: Control, patterns: Array) -> bool:
	for pattern: String in patterns:
		if surface.find_children(pattern, "Node", true, false).is_empty():
			return false
	return true
