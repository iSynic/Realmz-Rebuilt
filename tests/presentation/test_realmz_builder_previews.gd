## Verifies editor-only fixtures through the same production binders used at runtime.

extends RealmzTestCase

const PREVIEW_FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
var _surfaces: Dictionary = {}
var _contracts: Dictionary = {}
var _profiles: Array[String] = []


func run() -> void:
	_test_all_profiles_bind_through_production_components()
	_test_representative_collections_and_modes()
	_test_character_facts_survive_rebinding()
	_test_fixed_slot_controls_survive_rebinding()


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
