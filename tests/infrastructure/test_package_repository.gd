extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TAMPERED_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-tampered.realmz2"
const CLASSIC_CHARACTER_LIBRARY_PATH: String = "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const CLASSIC_CHARACTER_LIBRARY_ID: String = "realmz-classic-character-library"
const CLASSIC_CHARACTER_LIBRARY_HASH: String = "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"
const INSTALL_TEST_ROOT: String = "user://realmz2-tests/package-install-schema-v3"
const SCHEMA_REJECTION_PATH: String = "user://realmz2-tests/realmz2-schema-v2.realmz2"


func run() -> void:
	var repository := PackageRepository.new(); var character_library := repository.load_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH)
	assert_true(character_library.is_ok(), "the pinned Providence-built Classic character library loads as trusted application content: %s" % character_library.error_message)
	var bundled_campaigns := PackageHostController.new(repository).discover_available_campaigns(PackageHostController.BUNDLED_CAMPAIGN_ROOT, "res://tests/fixtures/no-bundled-overrides"); assert_equal([bundled_campaigns.size(), bundled_campaigns.map(func(campaign: CampaignPackageView) -> String: return campaign.campaign_id)], [13, ["scenario-assault-on-giant-mountain", "scenario-castle-in-the-clouds", "scenario-city-of-bywater", "scenario-destroy-the-necronomicon", "scenario-grilochs-revenge", "scenario-half-truth", "scenario-mithril-vault", "scenario-prelude-to-pestilence", "scenario-trouble-in-the-sword-lands", "scenario-twin-sands-of-time", "scenario-war-in-the-sword-lands", "scenario-white-dragon", "scenario-wrath-of-the-mind-lords"]], "public application discovery exposes exactly the ready Castle-distributed campaign bundle in deterministic order")
	if character_library.is_ok():
		assert_equal([character_library.content.race_definitions().size(), character_library.content.caste_definitions().size()], [30, 30], "the application character library contains the complete stock Race and Caste tables"); assert_equal([character_library.content.race_by_id("classic.race.1").name, character_library.content.caste_by_id("classic.caste.1").name], ["Human", "Fighter"], "the stock library retains Realmz names without scenario overrides")
		assert_equal([character_library.content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).size(), character_library.content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON).size()], [120, 120], "the stock creator receives all built-in portraits and tactical icons")
		assert_true(repository.load_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH) == character_library, "the immutable built-in library reuses one typed in-memory result")
		assert_equal(repository.retained_package_count(), 1, "the package repository retains one trusted bundled graph")
		repository.set_application_content(character_library.content, character_library.media.assets())
	var wrong_library_identity := repository.load_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, "0".repeat(64)); assert_false(wrong_library_identity.is_ok(), "a bundled library whose pinned package identity drifts is rejected")
	var production_scenario := repository.load_package("res://src/infrastructure/campaigns/scenario-assault-on-giant-mountain.realmz2")
	assert_true(production_scenario.is_ok(), "a production scenario composes against the pinned application definition catalog: %s" % production_scenario.error_message)
	if production_scenario.is_ok():
		var portable_torch := ItemInstance.new("portable.item.torch", "classic.item.805")
		assert_equal([character_library.content.item_by_id(portable_torch.definition_id).name, production_scenario.content.item_by_id(portable_torch.definition_id).name], ["Unknown item", "Torch"], "a portable character item retains only its stable identity and resolves through the active scenario-over-application catalog")
		assert_equal([production_scenario.content.item_by_id("classic.item.1").name, production_scenario.content.spell_by_id("classic.spell.1101").id, production_scenario.content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT).size()], [character_library.content.item_by_id("classic.item.1").name, "classic.spell.1101", 120], "application-owned definitions and appearance media remain available when the scenario provides no exact-key override")
	var loaded := repository.load_package(FIXTURE_PATH); assert_true(loaded.is_ok(), "the Providence-authored fixture passes package validation: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var fixture_archive := ZIPReader.new()
	assert_equal(fixture_archive.open(FIXTURE_PATH), OK, "the public package proof can open the validated synthetic archive")
	if fixture_archive.file_exists("manifest.json"):
		var manifest: Dictionary = JSON.parse_string(fixture_archive.read_file("manifest.json").get_string_from_utf8()); var malformed_content: Dictionary = JSON.parse_string(fixture_archive.read_file("content.json").get_string_from_utf8()); var world: Dictionary = JSON.parse_string(fixture_archive.read_file("world.json").get_string_from_utf8()); var scenario: Dictionary = JSON.parse_string(fixture_archive.read_file("scenario.json").get_string_from_utf8()); var boundary_content := malformed_content.duplicate(true); boundary_content["messages"].append({"id": 0, "text": ""}); boundary_content["messages"].append({"id": 2999, "text": "A".repeat(255)}); var boundary := PackageDomainAssembler.new().assemble(manifest, boundary_content, world, scenario, loaded.media.assets(), false, character_library.content); var malformed_encounter: Dictionary = malformed_content["complexEncounters"][0]; malformed_encounter["promptMessageId"] = 628; var sentinel_item: Dictionary = malformed_content["items"][0]; sentinel_item["specificCasteId"] = "classic.caste.-32768"; var normalized := PackageDomainAssembler.new().assemble(manifest, malformed_content, world, scenario, loaded.media.assets(), false, character_library.content); var reversed_world: Dictionary = world.duplicate(true); reversed_world["maps"][0]["randomRectangles"][1]["battleRange"] = [1, -1]; var reversed_range := PackageDomainAssembler.new().assemble(manifest, malformed_content, reversed_world, scenario, loaded.media.assets(), false, character_library.content); var invalid_branch_scenario: Dictionary = scenario.duplicate(true); invalid_branch_scenario["programs"].append({"id": "xap:9876", "ownerKind": "extra-action-point", "ownerId": "9876", "instructions": [{"kind": "classicAction", "slot": 0, "rawOpcode": 85, "opcode": 85, "id": 0, "gosub": false, "extraCode": [1, 0, 1, 0, 0]}]}); var invalid_branch := PackageDomainAssembler.new().assemble(manifest, malformed_content, world, invalid_branch_scenario, loaded.media.assets(), false, character_library.content); assert_equal([boundary.message_by_id(0).text if boundary != null else "assembly-failed", boundary.message_by_id(2999).text.length() if boundary != null else -1, loaded.content.message_by_id(628), normalized.message_by_id(628).text if normalized != null else "assembly-failed", normalized.item_by_id(String(sentinel_item["id"])).specific_caste_id if normalized != null else "assembly-failed", reversed_range.world.map_by_id("land:0").random_region_by_index(1).battle_maximum if reversed_range != null else 0, invalid_branch], ["", 255, null, "", "classic.caste.-32768", -1, null], "empty and maximum Data SD2 records cross public package assembly, missing prompt and item sentinels normalize, an inverted battle range survives, and every opcode 85 random destination must resolve during strict validation")
		var empty_race_content := malformed_content.duplicate(true); empty_race_content["races"].map(func(race: Dictionary) -> Variant: race["eligibleCasteIds"] = []; race["maximumAge"] = 0; race["baseMovement"] = 0; race["baseAttacks"] = 0; race["maximumAttacks"] = 0; race["attributeLimits"].fill(0); return null); var empty_race_result := PackageDomainAssembler.new().assemble(manifest, empty_race_content, world, scenario, loaded.media.assets(), false, character_library.content); var empty_caste_content := malformed_content.duplicate(true); empty_caste_content["castes"].map(func(caste: Dictionary) -> Variant: caste["eligibleRaceIds"] = []; caste["casteClass"] = 0; caste["movementBonus"] = 0; caste["maximumAttacks"] = 0; caste["startMoney"] = 0; caste["victoryThresholds"].fill(0); caste["attributeLimits"].fill(0); caste["staminaDice"].fill(0); caste["attackLevels"].fill(0); return null); var empty_caste_result := PackageDomainAssembler.new().assemble(manifest, empty_caste_content, world, scenario, loaded.media.assets(), false, character_library.content); assert_equal([empty_race_result, empty_caste_result], [null, null], "strict package assembly independently rejects complete 30-record Race or Caste tables with no functional rules"); var world_opcode_scenario: Dictionary = scenario.duplicate(true); world_opcode_scenario["programs"].append({"id": "xap:9877", "ownerKind": "extra-action-point", "ownerId": "9877", "instructions": [{"kind": "classicAction", "slot": 0, "rawOpcode": 92, "opcode": 92, "id": 0, "gosub": false, "extraCode": [0, 1, 0, -500, -1, 0, 0, 0, 0, 0]}, {"kind": "classicAction", "slot": 1, "rawOpcode": 92, "opcode": 92, "id": 1, "gosub": false, "extraCode": [-1, -1, 0, 100, 0, 1, 0, 0, 0, 0]}]}); var world_opcode_content := PackageDomainAssembler.new().assemble(manifest, malformed_content, world, world_opcode_scenario, loaded.media.assets(), false, character_library.content); assert_true(world_opcode_content != null and world_opcode_content.scenario.program_by_id("xap:9877").instruction_count() == 2 and world_opcode_content.scenario.program_by_id("xap:9877").instruction_at(1).extra_code.size() == 10, "strict package assembly preserves opcode 92's consecutive second row and admits Castle's PC slot-zero fallback indices")
		var scrolling_scenario: Dictionary = scenario.duplicate(true); scrolling_scenario["programs"].append({"id": "xap:9878", "ownerKind": "extra-action-point", "ownerId": "9878", "instructions": [{"kind": "classicAction", "slot": 0, "rawOpcode": 62, "opcode": 62, "id": -200, "gosub": false, "extraCode": [0, 0, 0, 0, 0]}]}); var scrolling_assembler := PackageDomainAssembler.new(); var scrolling_content := scrolling_assembler.assemble(manifest, malformed_content, world, scrolling_scenario, loaded.media.assets(), false, character_library.content); assert_true(scrolling_content != null and scrolling_content.scenario.program_by_id("xap:9878") != null, "strict package assembly admits opcode 62 when its exact signed TEXT resource is present: %s" % scrolling_assembler.error_message()); var missing_scrolling_scenario: Dictionary = scenario.duplicate(true); missing_scrolling_scenario["programs"].append({"id": "xap:9879", "ownerKind": "extra-action-point", "ownerId": "9879", "instructions": [{"kind": "classicAction", "slot": 0, "rawOpcode": 62, "opcode": 62, "id": -201, "gosub": false, "extraCode": [0, 0, 0, 0, 0]}]}); var missing_scrolling_content := PackageDomainAssembler.new().assemble(manifest, malformed_content, world, missing_scrolling_scenario, loaded.media.assets(), false, character_library.content); assert_equal(missing_scrolling_content, null, "strict package assembly rejects opcode 62 when its exact signed TEXT resource is absent")
	fixture_archive.close(); var repeated_external_load := repository.load_package(FIXTURE_PATH); assert_true(repeated_external_load.is_ok(), "an unchanged external package can be validated repeatedly"); assert_true(repeated_external_load != loaded, "external package validation never inherits trusted cache status")
	assert_equal(loaded.content.campaign_id, "realmz2-synthetic-fixture", "manifest campaign identity becomes typed content")
	assert_equal(loaded.content.package_hash, "9ab36f7b609628d76bbdfdb3ba6e4971de3cb4d83b5fe0048c45f04a9fd46dec", "package identity is retained")
	assert_equal(loaded.content.campaign_definition().title, "Realmz2 Synthetic Fixture", "campaign title metadata becomes a typed display contract")
	assert_equal(loaded.content.campaign_definition().version, "", "campaign version metadata preserves an authored empty value")
	assert_equal(loaded.content.campaign_definition().restrictions.maximum_party_size, 6, "campaign party-size restrictions are typed")
	assert_equal([loaded.content.campaign_definition().recommended_party_levels, loaded.content.campaign_definition().maximum_party_levels, loaded.content.campaign_definition().guidance_authored], [6, 12, true], "Data SC aggregate party guidance remains distinct from per-character restrictions")
	assert_equal(loaded.content.available_monster_sets(), [0, -1, 1], "packaged Classic monster sets retain the player-facing Normal, Mega, Monster order"); var menu_monster := loaded.content.monster_by_id_for_set("classic.monster.1", 0); var bestiary := loaded.content.bestiary_definitions_for_set(0); assert_equal([menu_monster.classic_name_id, menu_monster.description, menu_monster.not_on_menu], [42, "A deterministic synthetic bestiary entry.", false], "the package preserves independent Classic monster name identity and complete bestiary metadata"); assert_true(bestiary.has(menu_monster) and bestiary.all(func(definition: MonsterDefinition) -> bool: return definition.hit_dice > 0 and definition.hit_dice != 255 and not definition.not_on_menu), "the active package catalog exposes only Castle menu-visible Bestiary definitions in stable typed form")
	assert_equal(loaded.content.monster_by_id_for_set("classic.monster.1", 1).id, "classic.monster-set.1.1", "Monster Monsters resolves to a stable alternate definition identity")
	assert_equal(loaded.content.monster_by_id_for_set("classic.monster.1", -1).hit_dice, 12, "Mega Monsters preserves its alternate combat record")
	assert_true(loaded.content.campaign_definition().contact.has("email"), "campaign contact metadata is validated as a fixed shape")
	var map := loaded.content.world.map_by_id("land:0")
	assert_not_null(map, "the authoritative start map is constructed")
	assert_equal([map.battle_terrain_set_id, map.base_scale, map.topology.cell_at(Vector2i.ZERO).is_forest], ["classic.battle-terrain.landlook.0", 1, true], "land maps retain their battle terrain, base scale, and forest semantics")
	var player_map := loaded.content.world.player_map_by_classic_id(1)
	assert_not_null(player_map, "Data MD2 player-map records become immutable typed content")
	assert_equal([player_map.id, player_map.mode, player_map.map_id, player_map.icon_size], ["classic.player-map.1", PlayerMapDefinition.LAND_CROP, "land:0", 32], "player-map identity, mode, topology source, and divisor preserve the compiler contract")
	assert_equal([player_map.party_marker_asset_id, loaded.media.asset_by_id(player_map.party_marker_asset_id).resource_type, loaded.media.asset_by_id(player_map.party_marker_asset_id).resource_id], ["realmz-player-map-cicn-138", "cicn", 138], "the current-party marker resolves through exact Classic type-plus-ID media"); var custom_music := loaded.media.assets_of_kind("music")[0]; assert_equal([custom_music.scenario_music_slot, custom_music.label], [1, "Fixture Custom 1"], "scenario-owned music retains its independent Custom playlist slot")
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
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.map_id, "land:0", "AP post-action map identity is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.coordinate, Vector2i(1, 0), "AP post-action coordinate is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").classic_record_index, 0, "Classic trigger record identity crosses the compiler boundary")
	assert_equal(loaded.content.simple_encounter_by_id(0).response_at(0).result_program_id, "simple:0:result:0", "Encounter choices reference ordinary result programs")
	assert_equal(loaded.content.complex_encounter_by_id(0).expected_word(), "open", "Complex Encounter words become typed runtime data")
	assert_equal(loaded.content.thief_encounter_by_id(0).type_flags().size(), 10, "Thief Encounter mutable flags have a fixed source-backed shape")
	assert_equal([loaded.content.timed_encounter_by_id(0).classic_macro_id, loaded.content.timed_encounter_by_id(0).program_id], [0, "xap:0"], "Timed Encounter schedules retain their Classic XAP identity")
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
		assert_false(battle_atlas.region_for(0).has_area(), "Classic combat-build tile zero remains empty instead of aliasing battle tile one")
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
	assert_equal(loaded.content.monster_by_id("classic.monster.1").starting_conditions()[ConditionRules.REFLECTING_SPELLS], -1, "all forty authored monster starting conditions cross the validating package boundary")
	assert_equal(loaded.content.battle_by_id("classic.battle.0").monster_slots()[0].monster_id, "classic.monster.1", "battle placements reference stable monster IDs")
	assert_equal([loaded.content.shop_by_id("classic.shop.0").quantity(0), loaded.content.shop_by_id("classic.shop.0").stock_slot(0)], [2, 817], "shop stock compiles to stable item references, quantities, and sparse native slots")
	assert_equal(loaded.content.treasure_by_id("classic.treasure.0").item_ids()[0], "classic.item.901", "treasures use the same item identity as inventory")
	assert_equal(loaded.content.spell_by_id("classic.spell.5101").damage_max, 4, "custom spells use packed Realmz class/level/slot identity")
	assert_not_null(loaded.content.spell_by_id("classic.spell.1101"), "Providence compiles standard Data S spells into normalized runtime definitions")
	assert_equal(loaded.content.spell_by_id("classic.spell.1108").name, "Magic Darts", "standard spell names follow Castle's positive Custom Names STR# lookup")
	assert_equal(loaded.content.spell_by_id("classic.spell.2302").name, "Destroy Magic", "standard spell labels preserve their packed Classic identity")
	assert_equal(loaded.content.spell_by_id("classic.spell.3106").description, "Limited Phase:  Will allow the caster to teleport during combat.  The caster's turn will be over after phasing.", "stock spell descriptions resolve from Rebuilt's pinned Family Jewels application catalog rather than campaign-owned text")
	assert_not_null(loaded.media, "validated package media receives a typed catalog")
	assert_equal(loaded.media.assets().size(), 255, "the synthetic fixture carries authored map/scenario media, player-map media and markers, the battle atlas, both monster facings, both 120-entry character-appearance catalogs, and its explicit scenario sound and Custom music")
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
		var receipt_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(installed.installed_path + ".receipt.json"))
		assert_true(receipt_data is Dictionary, "the installation receipt is parseable JSON")
		if receipt_data is Dictionary:
			assert_equal([int(receipt_data["formatVersion"]), int(receipt_data["decoderVersion"]), receipt_data["schemaHash"]], [2, 6, PackageRepository.EXPECTED_SCHEMA_HASH], "the receipt records the v3 package and composed-catalog decoder contract")
		assert_contains(installed.installed_path, loaded.content.package_hash, "the installation path carries the package identity")
		repository.promote_installed_package(installed.installed_path)
		assert_equal(repository.retained_package_count(), 1, "promoting an installed package replaces the candidate without retaining an unbounded graph")
		var repeated := repository.install_package(FIXTURE_PATH, install_root)
		assert_true(repeated.is_ok(), "reinstalling identical immutable content is idempotent")
		assert_equal(repeated.installed_path, installed.installed_path, "idempotent installation resolves to the same package"); var overlaid_campaigns := PackageHostController.new(repository).discover_available_campaigns("res://tests/fixtures/packages", install_root); assert_true(overlaid_campaigns.any(func(campaign: CampaignPackageView) -> bool: return campaign.campaign_id == loaded.content.campaign_id and campaign.path == installed.installed_path), "a valid user-installed revision deterministically replaces its matching bundled baseline")
		var installed_phases: Array[StringName] = []
		var reopened := PackageRepository.new().install_package(installed.installed_path, install_root, func(phase: StringName, _completed: int, _total: int) -> void:
			if not installed_phases.has(phase):
				installed_phases.append(phase)
		)
		assert_true(reopened.is_ok(), "a fresh application process opens the app-owned installed package from its validation receipt")
		assert_true(installed_phases.has(&"checking-install"), "installed startup checks the durable receipt and immutable file identity")
		assert_true(installed_phases.has(&"checking-install-integrity"), "installed startup verifies the whole archive SHA-256 before trusting decoded content")
		assert_false(installed_phases.has(&"validating-integrity"), "installed startup does not repeat Providence payload validation"); var document_cache_path := installed.installed_path + ".documents.cache"; assert_true(FileAccess.file_exists(document_cache_path), "the first trusted reopen writes a compressed parsed-document cache beside the immutable archive"); var cached_phases: Array[StringName] = []; var cache_reopened := PackageRepository.new().install_package(installed.installed_path, install_root, func(phase: StringName, _completed: int, _total: int) -> void: if not cached_phases.has(phase): cached_phases.append(phase)); assert_true(cache_reopened.is_ok() and cached_phases.has(&"restoring-runtime-image") and not cached_phases.has(&"checking-install-integrity") and not cached_phases.has(&"reading-documents"), "a later process restores its verified primitive-only runtime image without rehashing the archive or reparsing JSON"); var damaged := FileAccess.open(document_cache_path, FileAccess.WRITE); damaged.store_buffer(var_to_bytes({"kind": "invalid"})); damaged.close(); var fallback_phases: Array[StringName] = []; var fallback_reopened := PackageRepository.new().install_package(installed.installed_path, install_root, func(phase: StringName, _completed: int, _total: int) -> void: if not fallback_phases.has(phase): fallback_phases.append(phase)); assert_true(fallback_reopened.is_ok() and fallback_phases.has(&"checking-install-integrity") and fallback_phases.has(&"reading-documents"), "an invalid sidecar rehashes and reparses the verified immutable archive instead of becoming a package failure")
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
		var altered_bytes := FileAccess.get_file_as_bytes(installed.installed_path); DirAccess.remove_absolute(ProjectSettings.globalize_path(document_cache_path))
		assert_true(not altered_bytes.is_empty(), "the receipt test can read its isolated installed fixture")
		if not altered_bytes.is_empty():
			altered_bytes[altered_bytes.size() - 1] = altered_bytes[altered_bytes.size() - 1] ^ 1
			var altered_install := FileAccess.open(installed.installed_path, FileAccess.WRITE)
			assert_not_null(altered_install, "the receipt test can replace the installed fixture without changing its byte count")
			if altered_install != null:
				altered_install.store_buffer(altered_bytes)
				altered_install.close()
				var receipt_path := installed.installed_path + ".receipt.json"
				var altered_receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
				assert_true(altered_receipt is Dictionary, "the same-size mutation retains a parseable receipt fixture")
				if altered_receipt is Dictionary:
					altered_receipt["archiveModifiedTime"] = FileAccess.get_modified_time(installed.installed_path)
					var receipt_file := FileAccess.open(receipt_path, FileAccess.WRITE)
					assert_not_null(receipt_file, "the fixture can align cheap modification metadata while retaining the validated archive hash")
					if receipt_file != null:
						receipt_file.store_string(CanonicalJson.encode(altered_receipt))
						receipt_file.close()
				var changed_install := PackageRepository.new().install_package(installed.installed_path, install_root)
				assert_false(changed_install.is_ok(), "a same-size installed archive mutation invalidates its receipt before cache reuse")
				assert_contains(changed_install.error_message, "SHA-256", "changed installed bytes report the strong immutable-file identity")

	var picture := MediaAsset.new("fixture.picture", "Fixture", "picture", "image/png", "PICT", 128, 0, "0000000000000000000000000000000000000000000000000000000000000000", "assets/media/0000000000000000000000000000000000000000000000000000000000000000.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	assert_true(picture.is_picture(), "package media classifies pictures by typed MIME and resource identity")
	assert_false(picture.is_sound(), "picture media cannot be selected by the sound presenter")
	var icon := MediaAsset.new("fixture.icon", "Fixture Icon", "icon", "image/png", "cicn", 128, 0, "1111111111111111111111111111111111111111111111111111111111111111", "assets/media/1111111111111111111111111111111111111111111111111111111111111111.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	var colliding_assets: Array[MediaAsset] = [picture, icon]
	var colliding_catalog := PackageMediaCatalog.new("", "", colliding_assets)
	assert_equal(colliding_catalog.asset_by_resource("PICT", 128), picture, "exact PICT lookup cannot collide with CICN identity")
	assert_equal(colliding_catalog.asset_by_resource("cicn", 128), icon, "exact cicn lookup is collision-free")
	assert_true(colliding_catalog.asset_by_resource("CICN", 128) == null, "Classic resource type bytes are not case-normalized")
	assert_true(colliding_catalog.asset_by_resource("ICON", 128) == null, "unavailable resource types do not fall back by numeric ID")
	var duplicate_picture := MediaAsset.new("fixture.picture.duplicate", "Duplicate Fixture", "picture", "image/png", "PICT", 128, 0, "2222222222222222222222222222222222222222222222222222222222222222", "assets/media/2222222222222222222222222222222222222222222222222222222222222222.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	var ambiguous_catalog := PackageMediaCatalog.new("", "", [picture, duplicate_picture])
	assert_true(ambiguous_catalog.asset_by_resource("PICT", 128) == null, "an ambiguous exact resource key never degrades to first-match lookup")
	assert_equal(ambiguous_catalog.resolution_diagnostic("PICT", 128, "test-picture")["status"], "ambiguous", "developer media diagnostics expose an ambiguous resource key")

	var rejected := repository.load_package(TAMPERED_FIXTURE_PATH)
	assert_false(rejected.is_ok(), "a content mutation without matching manifest hashes is rejected")
	assert_contains(rejected.error_message, "failed size or SHA-256", "hash rejection reports the violated boundary")
	var schema_v2_path := _write_schema_v2_fixture()
	var rejected_schema_v2 := repository.load_package(schema_v2_path)
	assert_false(rejected_schema_v2.is_ok(), "a schema-v2 package is rejected at the public package boundary")
	assert_contains(rejected_schema_v2.error_message, "Unsupported Realmz 2.0 package or schema version", "schema-v2 rejection is explicit before content construction")
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
	_cleanup_schema_rejection()
	var cancellation_calls: Array[int] = [0]
	var cancelled := repository.install_package(FIXTURE_PATH, INSTALL_TEST_ROOT, Callable(), func() -> bool:
		cancellation_calls[0] += 1
		return true
	)
	assert_true(cancellation_calls[0] > 0, "the repository cancellation seam is consulted before package work")
	assert_equal(cancelled.error_code, &"package_cancelled", "the repository exposes typed cancellation")
	assert_true(cancelled.installed_path.is_empty(), "a cancelled package operation has no installation path")
	repository.close()
	assert_equal(repository.retained_package_count(), 0, "closing the repository releases both bounded package graph slots")
	_cleanup_install_test_root()


func _cleanup_install_test_root() -> void:
	var expected := ProjectSettings.globalize_path("user://").simplify_path().path_join("realmz2-tests").path_join("package-install-schema-v3")
	var actual := ProjectSettings.globalize_path(INSTALL_TEST_ROOT).simplify_path()
	if actual != expected or not DirAccess.dir_exists_absolute(actual):
		return
	_remove_install_tree(actual, actual)


func _write_schema_v2_fixture() -> String:
	_cleanup_schema_rejection()
	var source := ZIPReader.new()
	if source.open(FIXTURE_PATH) != OK:
		return ""
	var absolute_path := ProjectSettings.globalize_path(SCHEMA_REJECTION_PATH)
	var writer := ZIPPacker.new()
	if writer.open(absolute_path) != OK:
		source.close()
		return ""
	for entry: String in source.get_files():
		var bytes := source.read_file(entry)
		if entry == "manifest.json":
			var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			if manifest is Dictionary:
				manifest["formatVersion"] = 1
				manifest["schemaVersion"] = 2
				bytes = CanonicalJson.encode(manifest).to_utf8_buffer()
		writer.start_file(entry)
		writer.write_file(bytes)
		writer.close_file()
	writer.close()
	source.close()
	return SCHEMA_REJECTION_PATH


func _cleanup_schema_rejection() -> void:
	var absolute_path := ProjectSettings.globalize_path(SCHEMA_REJECTION_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


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
