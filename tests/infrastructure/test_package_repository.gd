extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TAMPERED_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-tampered.realmz2"
const INSTALL_TEST_ROOT: String = "user://realmz2-tests/package-install-schema-v2"


func run() -> void:
	var repository := PackageRepository.new()
	var loaded := repository.load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "the Providence-authored fixture passes package validation: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	assert_true(repository.load_package(FIXTURE_PATH) == loaded, "an unchanged immutable package reuses its typed in-memory load result")
	assert_equal(loaded.content.campaign_id, "realmz2-synthetic-fixture", "manifest campaign identity becomes typed content")
	assert_equal(loaded.content.package_hash, "e15136a07d93c507b81fb7c9f56576199244dfc85f46da940f2f0e069aaaa63f", "package identity is retained")
	assert_equal(loaded.content.campaign_definition().title, "Realmz2 Synthetic Fixture", "campaign title metadata becomes a typed display contract")
	assert_equal(loaded.content.campaign_definition().version, "", "campaign version metadata preserves an authored empty value")
	assert_equal(loaded.content.campaign_definition().restrictions.maximum_party_size, 6, "campaign party-size restrictions are typed")
	assert_equal([loaded.content.campaign_definition().recommended_party_levels, loaded.content.campaign_definition().maximum_party_levels, loaded.content.campaign_definition().guidance_authored], [6, 12, true], "Data SC aggregate party guidance remains distinct from per-character restrictions")
	assert_equal(loaded.content.available_monster_sets(), [0, -1, 1], "packaged Classic monster sets retain the player-facing Normal, Mega, Monster order")
	assert_equal(loaded.content.monster_by_id_for_set("classic.monster.1", 1).id, "classic.monster-set.1.1", "Monster Monsters resolves to a stable alternate definition identity")
	assert_equal(loaded.content.monster_by_id_for_set("classic.monster.1", -1).hit_dice, 12, "Mega Monsters preserves its alternate combat record")
	assert_true(loaded.content.campaign_definition().contact.has("email"), "campaign contact metadata is validated as a fixed shape")
	var map := loaded.content.world.map_by_id("land:0")
	assert_not_null(map, "the authoritative start map is constructed")
	assert_equal(map.battle_terrain_set_id, "classic.battle-terrain.landlook.0", "land maps retain their effective Classic battle terrain identity")
	var player_map := loaded.content.world.player_map_by_classic_id(1)
	assert_not_null(player_map, "Data MD2 player-map records become immutable typed content")
	assert_equal([player_map.id, player_map.mode, player_map.map_id, player_map.icon_size], ["classic.player-map.1", PlayerMapDefinition.LAND_CROP, "land:0", 32], "player-map identity, mode, topology source, and divisor preserve the compiler contract")
	assert_equal([player_map.party_marker_asset_id, loaded.media.asset_by_id(player_map.party_marker_asset_id).resource_type, loaded.media.asset_by_id(player_map.party_marker_asset_id).resource_id], ["realmz-player-map-cicn-138", "cicn", 138], "the current-party marker resolves through exact Classic type-plus-ID media")
	assert_equal(player_map.markers().map(func(marker: PlayerMapMarkerDefinition) -> int: return marker.classic_icon_id), [137, 139, 140], "authored player-map markers retain their source order and exact CICN identities")
	for marker: PlayerMapMarkerDefinition in player_map.markers():
		assert_equal(loaded.media.asset_by_id(marker.icon_asset_id).resource_id, marker.classic_icon_id, "each player-map marker resolves to the matching Classic resource ID")
	assert_equal([loaded.content.world.player_map_by_classic_id(2).mode, loaded.content.world.player_map_by_classic_id(3).mode, loaded.content.world.player_map_by_classic_id(4).mode], [PlayerMapDefinition.DUNGEON_CROP, PlayerMapDefinition.PICTURE, PlayerMapDefinition.SCROLLING_TEXT], "the package covers all four Castle player-map display modes")
	var land_battle_terrain := loaded.content.world.battle_terrain_set_by_id(map.battle_terrain_set_id)
	assert_not_null(land_battle_terrain, "the map battle terrain identity resolves to immutable typed content")
	assert_equal(land_battle_terrain.tile_count(), 401, "land battle terrain contains the complete effective mapstats range")
	assert_equal(land_battle_terrain.tile_by_id(200).solid, 17, "active landlook tile 200 overwrites the earlier global Combat Data BD tile")
	assert_equal(land_battle_terrain.tile_by_id(201).combat_tile_at(2, 2), 201, "global combat tiles above the overlap retain their complete 3 x 3 build")
	assert_equal(map.topology.width, 90, "fixture topology preserves the Classic map width")
	assert_equal(map.topology.cells().size(), 8100, "every Classic topology cell is constructed exactly once")
	assert_equal(map.topology.cell_at(Vector2i(1, 0)).trigger_ids(), ["ap.fixture.message"], "cell trigger references come from authoritative topology")
	var special_land_cell := map.topology.cell_at(Vector2i(2, 2))
	assert_equal(special_land_cell.render_tile, 156, "Classic negative land cells render the landlook base terrain")
	assert_equal(special_land_cell.overlay_asset_id, "fixture.special-land.neg-99", "Classic negative land cells retain a separate overlay identity")
	assert_not_null(map.random_region_by_id("land:0:randlevel:rect:0"), "random rectangles become typed map regions")
	assert_equal(loaded.content.world.transition_from("land:0", &"east").target_map_id, "land:1", "Layout adjacency becomes an explicit transition")
	var dungeon := loaded.content.world.map_by_id("dungeon:0")
	assert_equal(dungeon.battle_terrain_set_id, "classic.battle-terrain.dungeon", "dungeon maps reference the shared Combat Data BD terrain set")
	var dungeon_battle_terrain := loaded.content.world.battle_terrain_set_by_id(dungeon.battle_terrain_set_id)
	assert_equal(dungeon_battle_terrain.tile_count(), 201, "dungeon battle terrain contains exactly Combat Data BD tiles 200 through 400")
	assert_equal(dungeon_battle_terrain.tile_by_id(200).solid, 23, "dungeon tile 200 retains the global Combat Data BD record")
	assert_equal(dungeon.topology.cell_at(Vector2i(1, 0)).edge(&"north").kind, &"door", "packed dungeon doors become explicit topology edges")
	assert_equal(dungeon.topology.cell_at(Vector2i(0, 1)).edge(&"east").kind, &"secret", "packed dungeon passage directions become explicit topology edges")
	assert_equal(loaded.content.message_by_id(1).text, "The Realmz 2.0 fixture is deterministic.", "runtime message text crosses the validating factory")
	assert_true(loaded.content.has_option_labels(), "Classic Data OD option labels cross the validating package boundary")
	assert_equal(loaded.content.option_label_by_id(1).text, "Proceed", "typed option labels remain distinct from ordinary scenario messages")
	var message_program := loaded.content.scenario.program_by_id(loaded.content.trigger_by_id("ap.fixture.message").program_id)
	assert_equal(message_program.instruction_at(0).opcode, 1, "Classic opcode identity is typed in the ordinary trigger program")
	assert_equal(loaded.content.scenario.application_hook_program_id(ScenarioApplicationHooks.START_GAME), "xap:40", "Start Game resolves from Global index zero to the emitted XAP program")
	assert_equal(loaded.content.scenario.application_hook_program_id(ScenarioApplicationHooks.PARTY_DEATH), "xap:41", "Party Death resolves from Global index one without off-by-one drift")
	assert_equal(loaded.content.scenario.application_hook_program_id(ScenarioApplicationHooks.END_ADVENTURE), "xap:42", "End Adventure resolves from Global index two")
	assert_equal(loaded.content.scenario.application_hook_program_id(ScenarioApplicationHooks.SHOP), "xap:43", "Shop resolves from Global index four")
	assert_equal(loaded.content.scenario.application_hook_program_id(ScenarioApplicationHooks.TEMPLE), "xap:44", "Temple resolves from Global index five")
	assert_true(PackageRepository.new()._construct_application_hooks({"startGame": null, "partyDeath": null, "endAdventure": null, "shop": null}) == null, "the loader rejects an incomplete application-hook contract")
	assert_true(PackageRepository.new()._construct_application_hooks({"startGame": -1, "partyDeath": null, "endAdventure": null, "shop": null, "temple": null}) == null, "the loader rejects native negative macro values instead of treating them as program IDs")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.map_id, "land:0", "AP post-action map identity is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.coordinate, Vector2i(1, 0), "AP post-action coordinate is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").classic_record_index, 0, "Classic trigger record identity crosses the compiler boundary")
	var duplicate_programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new("duplicate-program-a", &"trigger", "duplicate-trigger-a", []),
		ScenarioProgramDefinition.new("duplicate-program-b", &"trigger", "duplicate-trigger-b", []),
	]
	var duplicate_scenario := ScenarioDefinition.new(duplicate_programs, [])
	var duplicate_placed_records: Array = [
		{"id": "duplicate-trigger-a", "programId": "duplicate-program-a", "classicRecordIndex": 3, "mapId": "land:0", "coordinate": {"x": 0, "y": 0}, "active": true, "chancePercent": 100, "postActionLocation": null},
		{"id": "duplicate-trigger-b", "programId": "duplicate-program-b", "classicRecordIndex": 3, "mapId": "land:0", "coordinate": {"x": 1, "y": 0}, "active": true, "chancePercent": 100, "postActionLocation": null},
	]
	assert_true(PackageRepository.new()._construct_triggers(duplicate_placed_records, duplicate_scenario) == null, "the loader rejects ambiguous duplicate Classic placed-record identities")
	assert_equal(loaded.content.simple_encounter_by_id(0).response_at(0).result_program_id, "simple:0:result:0", "Encounter choices reference ordinary result programs")
	assert_equal(loaded.content.complex_encounter_by_id(0).expected_word(), "open", "Complex Encounter words become typed runtime data")
	assert_equal(loaded.content.thief_encounter_by_id(0).type_flags().size(), 10, "Thief Encounter mutable flags have a fixed source-backed shape")
	assert_equal(loaded.content.timed_encounter_by_id(0).trigger_record_index, 0, "Timed Encounter schedules retain their Classic AP identity")
	assert_not_null(loaded.content.scenario.action_by_id("scenario.realmz2-synthetic-fixture.after-encounter"), "compiled Scenario Actions become typed callable definitions")
	assert_equal(loaded.content.item_by_id("classic.item.901").name, "Fixture Wand", "Providence item records become immutable runtime definitions")
	assert_equal([loaded.content.item_by_classic_id(800).name, loaded.content.item_by_classic_id(800).item_type], ["Fixture Scroll Case", 13], "the Classic type-13 scroll case crosses the compiler boundary")
	assert_equal([loaded.content.item_by_classic_id(806).name, loaded.content.item_by_classic_id(806).initial_charges, loaded.content.item_by_classic_id(806).weight_per_charge], ["Fixture Parchment", 3, 1], "source-backed charged parchment crosses the compiler boundary at its Classic scenario item identity")
	assert_equal(loaded.content.spell_by_classic_id(1106).cost, -25, "Classic negative spell cost survives the package boundary as a fixed-power field spell")
	assert_equal(loaded.content.race_definitions().size(), 30, "the package contains Castle's complete 30-record race table")
	assert_equal(loaded.content.caste_definitions().size(), 30, "the package contains Castle's complete 30-record caste table")
	assert_equal(loaded.content.race_by_id("classic.race.1").classic_id, 1, "race package identity preserves Castle's one-based character value")
	assert_equal(loaded.content.race_by_id("classic.race.1").name, "Human", "race display names come from the imported Realmz name table")
	assert_equal(loaded.content.race_by_id("classic.race.1").base_movement, 10, "race rules cross the compiler boundary as direct Realmz data")
	assert_equal(loaded.content.race_by_id("classic.race.1").age_change(4).size(), 15, "the complete Castle race aging table crosses the validating package boundary")
	assert_true(loaded.content.race_by_id("classic.race.1").ability_bonus(13) is int, "the separate fourteen-entry racial ability table crosses the compiler boundary")
	assert_equal(loaded.content.caste_by_id("classic.caste.1").classic_id, 1, "caste package identity preserves Castle's one-based character value")
	assert_equal(loaded.content.caste_by_id("classic.caste.1").name, "Fighter", "caste display names come from the imported Realmz name table")
	assert_equal(loaded.content.caste_by_id("classic.caste.1").maximum_damage_bonus(), 5, "caste strength caps retain their source field meaning")
	assert_true(loaded.content.caste_by_id("classic.caste.1").initial_ability_value(13) is int and loaded.content.caste_by_id("classic.caste.1").level_ability_die(13) is int and loaded.content.caste_by_id("classic.caste.1").victory_threshold(29) is int, "caste abilities and all thirty victory thresholds cross the validating package boundary")
	var portraits := loaded.content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT)
	var combat_icons := loaded.content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)
	assert_equal([portraits.size(), combat_icons.size()], [120, 120], "the package exposes both complete browseable Classic character-appearance catalogs")
	assert_equal([portraits[0].classic_resource_id, portraits[-1].classic_resource_id], [257, 376], "portrait identities preserve the exact Portraits-fork CICN range")
	assert_equal([combat_icons[0].classic_resource_id, combat_icons[-1].classic_resource_id], [9000, 9119], "combat-icon identities preserve the exact Tacticals-fork CICN range")
	assert_true(portraits[0].is_recommended_for("classic.race.1"), "the Human zero-set inconsistency resolves to the proven browseable Human portrait set")
	assert_true(combat_icons[0].is_recommended_for("classic.race.1"), "Human tactical recommendations retain Castle's race-indexed 9000 set")
	var battle_atlas := loaded.media.battle_tileset()
	assert_not_null(battle_atlas, "reachable battles require the role-specific Classic PICT 302 atlas")
	if battle_atlas != null:
		assert_true(battle_atlas.is_battle_tileset(), "the battle atlas retains Castle's 20 by 20 grid of native 32-pixel cells")
		assert_equal(battle_atlas.region_for(1), Rect2i(0, 0, 32, 32), "Classic battle tile one maps to the first PICT 302 cell")
		assert_equal(battle_atlas.region_for(400), Rect2i(608, 608, 32, 32), "Classic battle tile 400 maps to the final PICT 302 cell")
		assert_false(battle_atlas.region_for(401).has_area(), "battle terrain cannot address beyond Castle's 400 artwork cells")
	var battle_tiles: Array[int] = []
	battle_tiles.resize(BattlefieldState.CELL_COUNT)
	battle_tiles.fill(232)
	var battle_view := CombatView.new(CombatState.new("classic.battle.presentation-contract", [], 0, BattlefieldState.new("land:0", battle_tiles)), [], loaded.content)
	assert_equal(battle_view.battlefield.upper_tileset_id, "landlook-0", "land combat identifies the active landlook atlas that Castle copies over PICT 302's upper half")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").attacks()[0].damage_max, 4, "monster attacks are typed instead of retained as native row dictionaries")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").item_ids(), ["classic.item.901", "", "", "", "", ""], "monster item slots preserve all six native positions")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").item_id_at(1), "", "an empty native missile slot does not collapse onto the melee item")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").spell_ids().size(), 10, "monster spell slots preserve all ten native positions")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").spell_id_at(1), "", "an empty native spell slot remains selectable as an empty Castle retry")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").required_weapon, 0, "monster weapon requirements remain distinct from battle placement distance")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").magic_to_hit, 0, "monster magical-plus thresholds remain an explicit field even when unrestricted")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").icon_id, 384, "monster display identity preserves Castle's exact base cicn")
	assert_not_null(loaded.media.asset_by_resource("cicn", 384), "the base facing of each reachable monster resolves through exact Classic media identity")
	assert_not_null(loaded.media.asset_by_resource("cicn", 692), "the alternate Castle facing resolves through the authored base cicn plus 308")
	var monster_media: Array[PackageMediaAsset] = loaded.media.assets()
	var fixture_monsters: Array[MonsterDefinition] = [loaded.content.monster_by_id("classic.monster.1")]
	assert_true(PackageRepository.new()._validate_monster_media(fixture_monsters, monster_media), "complete reachable monster media passes independent runtime readiness")
	monster_media = monster_media.filter(func(asset: PackageMediaAsset) -> bool: return not (asset.resource_type == "cicn" and asset.resource_id == 384))
	assert_false(PackageRepository.new()._validate_monster_media(fixture_monsters, monster_media), "missing required monster media fails readiness instead of degrading to letter placeholders")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").starting_conditions()[ConditionRules.REFLECTING_SPELLS], -1, "all forty authored monster starting conditions cross the validating package boundary")
	var random_weapon_monster := MonsterDefinition.new("monster.random-readiness", 999, "Random Readiness", 1, 0, 1, 0, 0, [], [], [], [], [], [], [MonsterAttackDefinition.new(1, 1)])
	random_weapon_monster.random_weapon_table = 6
	assert_false(PackageRepository.new()._validate_rule_references([], [], loaded.content.item_definitions(), [], [random_weapon_monster], [], [], [], {}), "package readiness rejects a random monster weapon table when any possible generated item is absent")
	var fixture_zip := ZIPReader.new()
	assert_equal(fixture_zip.open(FIXTURE_PATH), OK, "the package contract test can inspect detached fixture JSON")
	var fixture_content: Variant = JSON.parse_string(fixture_zip.read_file("content.json").get_string_from_utf8())
	var fixture_world: Variant = JSON.parse_string(fixture_zip.read_file("world.json").get_string_from_utf8())
	var fixture_assets: Variant = JSON.parse_string(fixture_zip.read_file("assets/index.json").get_string_from_utf8())
	fixture_zip.close()
	assert_true(fixture_content is Dictionary, "the detached fixture content parses for negative contract tests")
	if fixture_content is Dictionary:
		var invalid_races: Array = fixture_content["races"].duplicate(true)
		invalid_races.pop_back()
		assert_true(PackageRepository.new()._construct_races(invalid_races) == null, "the runtime rejects an incomplete Classic race table")
		invalid_races = fixture_content["races"].duplicate(true)
		invalid_races[1]["classicId"] = 1
		assert_true(PackageRepository.new()._construct_races(invalid_races) == null, "the runtime rejects duplicate Classic race identities")
		invalid_races = fixture_content["races"].duplicate(true)
		invalid_races[0]["abilityBonuses"].pop_back()
		assert_true(PackageRepository.new()._construct_races(invalid_races) == null, "the runtime rejects a race without all fourteen trained-ability bonuses")
		var invalid_castes: Array = fixture_content["castes"].duplicate(true)
		invalid_castes.pop_back()
		assert_true(PackageRepository.new()._construct_castes(invalid_castes) == null, "the runtime rejects an incomplete Classic caste table")
		invalid_castes = fixture_content["castes"].duplicate(true)
		invalid_castes[1]["classicId"] = 1
		assert_true(PackageRepository.new()._construct_castes(invalid_castes) == null, "the runtime rejects duplicate Classic caste identities")
		invalid_castes = fixture_content["castes"].duplicate(true)
		invalid_castes[0]["levelAbilityDice"].pop_back()
		assert_true(PackageRepository.new()._construct_castes(invalid_castes) == null, "the runtime rejects a caste without all fourteen level ability dice")
		invalid_castes = fixture_content["castes"].duplicate(true)
		invalid_castes[0]["victoryThresholds"].pop_back()
		assert_true(PackageRepository.new()._construct_castes(invalid_castes) == null, "the runtime rejects a caste without all thirty victory thresholds")
		var invalid_monsters: Array = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["magicToHit"] = -1
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime independently rejects a negative magical-plus threshold")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["requiredWeapon"] = 128
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime independently rejects a required-weapon value outside its signed byte")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["attackCount"] = 2
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime rejects a physical attack count beyond its supplied Classic rows")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["itemIds"] = ["classic.item.901"]
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime rejects legacy packed monster items because they erase native slot identity")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["conditions"].pop_back()
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime rejects a monster without all forty Classic starting conditions")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["conditions"][ConditionRules.REFLECTING_SPELLS] = -129
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime rejects a monster starting condition outside its signed byte")
		var spellless_monsters: Array = fixture_content["monsters"].duplicate(true)
		spellless_monsters[0]["spellIds"] = []
		var normalized_spellless: Variant = PackageRepository.new()._construct_monsters(spellless_monsters)
		assert_not_null(normalized_spellless, "an unambiguous legacy spellless monster remains loadable")
		if normalized_spellless != null:
			assert_equal(normalized_spellless[0].spell_ids(), ["", "", "", "", "", "", "", "", "", ""], "the loader normalizes a spellless monster to ten fixed empty slots")
		invalid_monsters = fixture_content["monsters"].duplicate(true)
		invalid_monsters[0]["spellIds"] = ["classic.spell.1101"]
		assert_true(PackageRepository.new()._construct_monsters(invalid_monsters) == null, "the runtime rejects legacy packed monster spells because they erase native slot identity")
	assert_true(fixture_assets is Dictionary, "the detached fixture asset index parses for appearance-catalog contract tests")
	if fixture_assets is Dictionary:
		var tracked_files: Dictionary = {}
		for asset: Dictionary in fixture_assets["assets"]:
			tracked_files[asset["path"]] = {"bytes": asset["bytes"], "sha256": asset["sha256"]}
		assert_true(PackageRepository.new()._validate_assets(fixture_assets, tracked_files), "the complete appearance catalogs pass independent runtime validation")
		var missing_portrait: Dictionary = fixture_assets.duplicate(true)
		missing_portrait["assets"] = missing_portrait["assets"].filter(func(asset: Dictionary) -> bool: return not (asset["kind"] == "portrait" and asset["resourceId"] == 257))
		assert_false(PackageRepository.new()._validate_assets(missing_portrait, tracked_files), "a package missing one Classic portrait fails readiness rather than degrading the creator")
		var malformed_portrait: Dictionary = fixture_assets.duplicate(true)
		for asset: Dictionary in malformed_portrait["assets"]:
			if asset["kind"] == "portrait":
				asset["mimeType"] = "application/octet-stream"
				break
		assert_false(PackageRepository.new()._validate_assets(malformed_portrait, tracked_files), "appearance assets must be decoded PNGs with usable dimensions")
		var battle_manifest := {"capabilities": ["realmz.presentation.battle-atlas-v1"]}
		assert_true(PackageRepository.new()._validate_presentation_capabilities(battle_manifest, fixture_assets), "the battle-atlas capability is backed by exactly one validated role-specific atlas")
		var missing_battle_atlas: Dictionary = fixture_assets.duplicate(true)
		missing_battle_atlas["assets"] = missing_battle_atlas["assets"].filter(func(asset: Dictionary) -> bool: return asset["kind"] != "battle-tileset")
		assert_false(PackageRepository.new()._validate_presentation_capabilities(battle_manifest, missing_battle_atlas), "a declared battle-atlas capability cannot silently omit its artwork")
	assert_true(fixture_world is Dictionary, "the detached fixture world parses for independent terrain contract tests")
	if fixture_world is Dictionary:
		var fixture_maps: Array[MapDefinition] = []
		for map_id: String in loaded.content.world.map_ids():
			fixture_maps.append(loaded.content.world.map_by_id(map_id))
		var fixture_player_maps: Variant = PackageRepository.new()._construct_player_maps(fixture_world["playerMaps"], fixture_maps, loaded.media.assets())
		assert_not_null(fixture_player_maps, "the detached player-map contract reconstructs through the independent validating factory")
		var invalid_player_maps: Array = fixture_world["playerMaps"].duplicate(true)
		invalid_player_maps[0]["classicId"] = 20
		assert_true(PackageRepository.new()._construct_player_maps(invalid_player_maps, fixture_maps, loaded.media.assets()) == null, "the runtime rejects Castle's unchecked twentieth player-map index before it can address beyond the save table")
		invalid_player_maps = fixture_world["playerMaps"].duplicate(true)
		invalid_player_maps[0]["iconSize"] = 0
		assert_true(PackageRepository.new()._construct_player_maps(invalid_player_maps, fixture_maps, loaded.media.assets()) == null, "the runtime rejects Castle's zero player-map divisor before presentation")
		invalid_player_maps = fixture_world["playerMaps"].duplicate(true)
		invalid_player_maps[0]["partyMarkerAssetId"] = "realmz-portrait-257"
		assert_true(PackageRepository.new()._construct_player_maps(invalid_player_maps, fixture_maps, loaded.media.assets()) == null, "the runtime rejects a player-map marker that is not exact cicn 138")
		invalid_player_maps = fixture_world["playerMaps"].duplicate(true)
		invalid_player_maps[0]["markers"] = [{"classicIconId": 137, "iconAssetId": "realmz-player-map-cicn-138", "x": 1, "y": 1}]
		assert_true(PackageRepository.new()._construct_player_maps(invalid_player_maps, fixture_maps, loaded.media.assets()) == null, "the runtime rejects a crop marker whose package asset does not match its authored cicn identity")
		var missing_map_program := ScenarioProgramDefinition.new("player-map.missing", &"trigger", "player-map.missing", [ClassicActionDefinition.new(0, 29, 29, 19, false, [])])
		var missing_map_scenario := ScenarioDefinition.new([missing_map_program], [])
		var fixture_world_definition := WorldDefinition.new(fixture_maps, [], [], fixture_player_maps)
		assert_false(PackageRepository.new()._validate_player_map_opcode_references(missing_map_scenario, fixture_world_definition), "package readiness rejects opcode 29 when its Data MD2 identity is unavailable")
		var invalid_terrain_sets: Array = fixture_world["battleTerrainSets"].duplicate(true)
		invalid_terrain_sets[1]["tiles"].pop_back()
		assert_true(PackageRepository.new()._construct_battle_terrain_sets(invalid_terrain_sets) == null, "the runtime rejects an incomplete effective land battle terrain range")
		invalid_terrain_sets = fixture_world["battleTerrainSets"].duplicate(true)
		invalid_terrain_sets[0]["tiles"][0]["combatBuild"] = [[200, 200, 200], [200, 200, 200]]
		assert_true(PackageRepository.new()._construct_battle_terrain_sets(invalid_terrain_sets) == null, "the runtime rejects a battle terrain tile without an exact 3 x 3 combat build")
		var terrain_sets: Array[BattleTerrainSetDefinition] = PackageRepository.new()._construct_battle_terrain_sets(fixture_world["battleTerrainSets"])
		var terrain_sets_by_id: Dictionary = {}
		for terrain_set: BattleTerrainSetDefinition in terrain_sets:
			terrain_sets_by_id[terrain_set.id] = terrain_set
		var trigger_ids: Dictionary = {}
		for trigger_record: Variant in fixture_world["triggers"]:
			trigger_ids[trigger_record["id"]] = true
		var invalid_maps: Array = fixture_world["maps"].duplicate(true)
		invalid_maps[0]["metadata"]["battleTerrainSetId"] = "classic.battle-terrain.missing"
		assert_true(PackageRepository.new()._construct_maps(invalid_maps, trigger_ids, terrain_sets_by_id, true) == null, "the runtime rejects an unknown map battle terrain reference")
		invalid_maps = fixture_world["maps"].duplicate(true)
		invalid_maps[0]["metadata"]["battleTerrainSetId"] = 7
		assert_true(PackageRepository.new()._construct_maps(invalid_maps, trigger_ids, terrain_sets_by_id, true) == null, "the runtime does not coerce a malformed battle terrain identity into a string")
	assert_equal(loaded.content.battle_by_id("classic.battle.0").monster_slots()[0].monster_id, "classic.monster.1", "battle placements reference stable monster IDs")
	assert_equal(loaded.content.shop_by_id("classic.shop.0").quantity(0), 2, "shop stock compiles to stable item references and quantities")
	assert_equal(loaded.content.treasure_by_id("classic.treasure.0").item_ids()[0], "classic.item.901", "treasures use the same item identity as inventory")
	assert_equal(loaded.content.spell_by_id("classic.spell.5101").damage_max, 4, "custom spells use packed Realmz class/level/slot identity")
	assert_not_null(loaded.content.spell_by_id("classic.spell.1101"), "Providence compiles standard Data S spells into normalized runtime definitions")
	assert_equal(loaded.content.spell_by_id("classic.spell.1108").name, "Magic Darts", "standard spell names follow Castle's positive Custom Names STR# lookup")
	assert_equal(loaded.content.spell_by_id("classic.spell.2302").name, "Destroy Magic", "standard spell labels preserve their packed Classic identity")
	assert_not_null(loaded.media, "validated package media receives a typed catalog")
	assert_equal(loaded.media.assets().size(), 254, "the synthetic fixture carries authored map/scenario media, player-map media and markers, the battle atlas, both monster facings, both 120-entry character-appearance catalogs, and only its explicit scenario sound")
	assert_equal([loaded.media.assets_of_kind("portrait").size(), loaded.media.assets_of_kind("combat-icon").size()], [120, 120], "the media catalog groups appearance roles without resource-ID-only lookup")
	var first_portrait_bytes := loaded.media.read_bytes_batch([loaded.media.assets_of_kind("portrait")[0]])
	assert_false((first_portrait_bytes.get("realmz-portrait-257", PackedByteArray()) as PackedByteArray).is_empty(), "batch media reads validate creator thumbnails through one archive boundary")
	var special_land_asset := loaded.media.asset_by_id("fixture.special-land.neg-99")
	assert_not_null(special_land_asset, "special land overlays resolve through the typed media index")
	assert_true(special_land_asset.is_picture(), "special land overlays are presentation images")
	assert_false(loaded.media.read_bytes(special_land_asset).is_empty(), "special land overlay bytes are hash-checked when read")
	var indexed_picture := loaded.media.asset_by_resource("PICT", 128)
	assert_not_null(indexed_picture, "Classic picture identity resolves through the typed media index")
	assert_false(loaded.media.read_bytes(indexed_picture).is_empty(), "content-addressed picture bytes are hash-checked when read")
	var indexed_sound := loaded.media.asset_by_resource("snd ", 30005)
	assert_not_null(indexed_sound, "Classic sound identity resolves through the typed media index")
	assert_false(loaded.media.read_bytes(indexed_sound).is_empty(), "content-addressed sound bytes are hash-checked when read")
	var picture_diagnostic := loaded.media.resolution_diagnostic("PICT", 128, "test-picture", "decoded")
	assert_equal(picture_diagnostic["packageAssetId"], indexed_picture.id, "media diagnostics report the exact resolved package identity")
	assert_equal(picture_diagnostic["sha256"], indexed_picture.sha256, "media diagnostics report the content hash")
	assert_equal(picture_diagnostic["decodeResult"], "decoded", "media diagnostics retain the presentation decoder result")
	var land_tileset := loaded.media.tileset_by_id("landlook-0")
	assert_not_null(land_tileset, "the authoritative land render identity resolves to a package tileset")
	assert_equal(land_tileset.region_for(156), Rect2i(480, 224, 32, 32), "Classic one-based land tile IDs resolve to the expected atlas region")
	assert_false(loaded.media.read_bytes(land_tileset).is_empty(), "content-addressed land atlas bytes are hash-checked when read")
	var dungeon_tileset := loaded.media.tileset_by_id("dungeon-top-down-302")
	assert_not_null(dungeon_tileset, "the authoritative dungeon render identity resolves to a package tileset")
	assert_equal(dungeon_tileset.region_for(1), Rect2i(0, 0, 16, 16), "the first Classic dungeon tile resolves without an off-by-one shift")

	_cleanup_install_test_root()
	var install_root := INSTALL_TEST_ROOT.path_join(loaded.content.package_hash)
	var installed := repository.install_package(FIXTURE_PATH, install_root)
	assert_true(installed.is_ok(), "a Providence-validated package installs through temporary byte readback: %s" % installed.error_message)
	if installed.is_ok():
		assert_true(FileAccess.file_exists(installed.installed_path), "the immutable installed package exists at its content-hash path")
		assert_true(FileAccess.file_exists(installed.installed_path + ".receipt.json"), "installation writes a durable validation receipt beside the immutable package")
		assert_contains(installed.installed_path, loaded.content.package_hash, "the installation path carries the package identity")
		var repeated := repository.install_package(FIXTURE_PATH, install_root)
		assert_true(repeated.is_ok(), "reinstalling identical immutable content is idempotent")
		assert_equal(repeated.installed_path, installed.installed_path, "idempotent installation resolves to the same package")
		var installed_phases: Array[StringName] = []
		var reopened := PackageRepository.new().install_package(installed.installed_path, install_root, func(phase: StringName, _completed: int, _total: int) -> void:
			if not installed_phases.has(phase):
				installed_phases.append(phase)
		)
		assert_true(reopened.is_ok(), "a fresh application process opens the app-owned installed package from its validation receipt")
		assert_true(installed_phases.has(&"checking-install"), "installed startup checks the durable receipt and immutable file identity")
		assert_false(installed_phases.has(&"validating-integrity"), "installed startup does not repeat Providence payload validation")
		var duplicate_path := installed.installed_path.get_base_dir().path_join("zz-duplicate.realmz2")
		if FileAccess.file_exists(duplicate_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(duplicate_path))
		var discovered := repository.discover_packages([install_root])
		var matching_installations: int = 0
		for candidate: PackageDiscoveryResult in discovered:
			if candidate.package_hash == loaded.content.package_hash:
				matching_installations += 1
				assert_true(candidate.ready, "discovery reports manifest/schema/capability availability without hashing or constructing the campaign")
				assert_equal(candidate.display_name, loaded.content.campaign.title, "discovery exposes the Providence-authored manifest name instead of inventing one from the campaign ID")
		assert_equal(matching_installations, 1, "discovery returns the immutable package identity exactly once")
		var duplicate := FileAccess.open(duplicate_path, FileAccess.WRITE)
		assert_not_null(duplicate, "the campaign-discovery fixture can create a second immutable revision path")
		if duplicate != null:
			duplicate.store_buffer(FileAccess.get_file_as_bytes(FIXTURE_PATH))
			duplicate.close()
		var campaign_listing := repository.discover_campaigns([install_root])
		var listed_campaigns: int = 0
		var listed_path: String = ""
		for candidate: PackageDiscoveryResult in campaign_listing:
			if candidate.ready and candidate.campaign_id == loaded.content.campaign_id:
				listed_campaigns += 1
				listed_path = candidate.path
		assert_equal(listed_campaigns, 1, "campaign discovery collapses immutable revisions to one current campaign entry")
		assert_equal(listed_path, duplicate_path, "campaign discovery selects the most recently installed valid revision")
		var altered_install := FileAccess.open(installed.installed_path, FileAccess.READ_WRITE)
		assert_not_null(altered_install, "the receipt test can alter its isolated installed fixture")
		if altered_install != null:
			altered_install.seek_end()
			altered_install.store_8(0)
			altered_install.close()
			var changed_install := PackageRepository.new().install_package(installed.installed_path, install_root)
			assert_false(changed_install.is_ok(), "an installed archive changed outside the installer invalidates its receipt")
			assert_contains(changed_install.error_message, "byte count", "changed installed bytes report the invalid immutable-file identity")

	var picture := PackageMediaAsset.new("fixture.picture", "Fixture", "picture", "image/png", "PICT", 128, 0, "0000000000000000000000000000000000000000000000000000000000000000", "assets/media/0000000000000000000000000000000000000000000000000000000000000000.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	assert_true(picture.is_picture(), "package media classifies pictures by typed MIME and resource identity")
	assert_false(picture.is_sound(), "picture media cannot be selected by the sound presenter")
	var icon := PackageMediaAsset.new("fixture.icon", "Fixture Icon", "icon", "image/png", "cicn", 128, 0, "1111111111111111111111111111111111111111111111111111111111111111", "assets/media/1111111111111111111111111111111111111111111111111111111111111111.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	var colliding_assets: Array[PackageMediaAsset] = [picture, icon]
	var colliding_catalog := PackageMediaCatalog.new("", "", colliding_assets)
	assert_equal(colliding_catalog.asset_by_resource("PICT", 128), picture, "exact PICT lookup cannot collide with CICN identity")
	assert_equal(colliding_catalog.asset_by_resource("cicn", 128), icon, "exact cicn lookup is collision-free")
	assert_true(colliding_catalog.asset_by_resource("CICN", 128) == null, "Classic resource type bytes are not case-normalized")
	assert_true(colliding_catalog.asset_by_resource("ICON", 128) == null, "unavailable resource types do not fall back by numeric ID")
	var duplicate_picture := PackageMediaAsset.new("fixture.picture.duplicate", "Duplicate Fixture", "picture", "image/png", "PICT", 128, 0, "2222222222222222222222222222222222222222222222222222222222222222", "assets/media/2222222222222222222222222222222222222222222222222222222222222222.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	var ambiguous_catalog := PackageMediaCatalog.new("", "", [picture, duplicate_picture])
	assert_true(ambiguous_catalog.asset_by_resource("PICT", 128) == null, "an ambiguous exact resource key never degrades to first-match lookup")
	assert_equal(ambiguous_catalog.resolution_diagnostic("PICT", 128, "test-picture")["status"], "ambiguous", "developer media diagnostics expose an ambiguous resource key")

	var settings_path := "user://realmz2-tests/presentation-settings.json"
	var settings_repository := SettingsRepository.new(settings_path)
	var settings := PresentationSettings.new()
	settings.master_volume = 0.35
	settings.topology_debug = true
	settings.text_scale = 1.2
	settings.reduced_motion = true
	settings.dungeon_3d = true
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_125
	settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.auto_switch_to_melee = false
	assert_true(settings.to_data()["dungeon3d"] is bool, "dungeon presentation setting serializes as a JSON-safe boolean")
	assert_not_null(PresentationSettings.from_data(settings.to_data()), "current presentation settings round-trip before filesystem persistence")
	var parsed_settings_data: Dictionary = JSON.parse_string(CanonicalJson.encode(settings.to_data()))
	assert_not_null(PresentationSettings.from_data(parsed_settings_data), "canonical JSON presentation settings round-trip (schema=%s dungeon=%s)" % [type_string(typeof(parsed_settings_data.get("schemaVersion"))), type_string(typeof(parsed_settings_data.get("dungeon3d")))])
	assert_true(settings_repository.save_settings(settings), "presentation settings commit through validated temporary replacement")
	var restored_settings := settings_repository.load_settings()
	assert_equal(restored_settings.master_volume, 0.35, "master volume persists outside gameplay state")
	assert_true(restored_settings.topology_debug, "topology display preference persists without altering rules")
	assert_equal(restored_settings.text_scale, 1.2, "accessibility text scale persists")
	assert_true(restored_settings.reduced_motion, "reduced cosmetic motion persists")
	assert_true(restored_settings.dungeon_3d, "topology-derived dungeon presentation preference persists")
	assert_equal(restored_settings.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists independently of text scale")
	assert_equal(restored_settings.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists outside gameplay state")
	assert_false(restored_settings.auto_switch_to_melee, "Auto Weapon Switch persists in the application settings repository")
	var legacy_settings := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 1, "masterVolume": 1.0, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false})
	assert_not_null(legacy_settings, "version-one presentation settings migrate without entering gameplay state")
	assert_false(legacy_settings.dungeon_3d, "migrated presentation settings default the optional 3D view off")
	assert_equal(legacy_settings.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "legacy settings migrate to automatic interface density")
	assert_equal(legacy_settings.window_mode, PresentationSettings.WINDOWED, "legacy settings migrate to windowed mode")
	assert_true(legacy_settings.auto_switch_to_melee, "legacy settings migrate to Castle's default-on Auto Weapon Switch preference")

	var rejected := repository.load_package(TAMPERED_FIXTURE_PATH)
	assert_false(rejected.is_ok(), "a content mutation without matching manifest hashes is rejected")
	assert_contains(rejected.error_message, "failed size or SHA-256", "hash rejection reports the violated boundary")
	var fixture_discovery := repository.discover_packages(["res://tests/fixtures/packages"])
	var discovered_valid := false
	var discovered_tampered_metadata := false
	for candidate: PackageDiscoveryResult in fixture_discovery:
		if candidate.path == FIXTURE_PATH:
			discovered_valid = candidate.ready
		elif candidate.path == TAMPERED_FIXTURE_PATH:
			discovered_tampered_metadata = candidate.ready
	assert_true(discovered_valid, "manifest-only discovery accepts the intact fixture without typed content construction")
	assert_true(discovered_tampered_metadata, "manifest-only discovery defers payload hashing until the package is selected for play")

	var sandbox_error := PackageRepository.package_capability_error("realmz.scenario.gdscript-actions-v1")
	assert_contains(sandbox_error, "no secure external host", "the manifest readiness path rejects deferred GDScript backends at the security boundary")
	assert_contains(PackageRepository.package_capability_error("realmz.scenario.unknown-v1"), "unknown capability", "the same readiness path rejects unrecognized package capabilities")
	_cleanup_install_test_root()


func _cleanup_install_test_root() -> void:
	var expected := ProjectSettings.globalize_path("user://").simplify_path().path_join("realmz2-tests").path_join("package-install-schema-v2")
	var actual := ProjectSettings.globalize_path(INSTALL_TEST_ROOT).simplify_path()
	if actual != expected or not DirAccess.dir_exists_absolute(actual):
		return
	_remove_install_tree(actual, actual)


func _remove_install_tree(path: String, verified_root: String) -> void:
	if path != verified_root and not path.begins_with(verified_root + "/"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories():
		_remove_install_tree(path.path_join(directory_name), verified_root)
	DirAccess.remove_absolute(path)
