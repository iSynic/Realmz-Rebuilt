extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TAMPERED_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-tampered.realmz2"


func run() -> void:
	var repository := PackageRepository.new()
	var loaded := repository.load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "the Providence-authored fixture passes package validation: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	assert_equal(loaded.content.campaign_id, "realmz2-synthetic-fixture", "manifest campaign identity becomes typed content")
	assert_equal(loaded.content.package_hash, "53b6ab7cec5e3aa63d86360bbe016b63c415c64d24b472cc951986db4317f1c9", "package identity is retained")
	var map := loaded.content.world.map_by_id("land:0")
	assert_not_null(map, "the authoritative start map is constructed")
	assert_equal(map.topology.width, 3, "fixture topology width is preserved")
	assert_equal(map.topology.cells().size(), 9, "every topology cell is constructed exactly once")
	assert_equal(map.topology.cell_at(Vector2i(1, 0)).trigger_ids(), ["ap.fixture.message"], "cell trigger references come from authoritative topology")
	assert_not_null(map.random_region_by_id("land:0:randlevel:rect:0"), "random rectangles become typed map regions")
	assert_equal(loaded.content.world.transition_from("land:0", &"east").target_map_id, "land:1", "Layout adjacency becomes an explicit transition")
	var dungeon := loaded.content.world.map_by_id("dungeon:0")
	assert_equal(dungeon.topology.cell_at(Vector2i(1, 0)).edge(&"north").kind, &"door", "packed dungeon doors become explicit topology edges")
	assert_equal(dungeon.topology.cell_at(Vector2i(0, 1)).edge(&"east").kind, &"secret", "packed dungeon passage directions become explicit topology edges")
	assert_equal(loaded.content.message_by_id(1).text, "The Realmz 2.0 fixture is deterministic.", "runtime message text crosses the validating factory")
	var message_program := loaded.content.scenario.program_by_id(loaded.content.trigger_by_id("ap.fixture.message").program_id)
	assert_equal(message_program.instruction_at(0).opcode, 1, "Classic opcode identity is typed in the ordinary trigger program")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.map_id, "land:0", "AP post-action map identity is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").post_action_location.coordinate, Vector2i(1, 0), "AP post-action coordinate is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").classic_record_index, 0, "Classic trigger record identity crosses the compiler boundary")
	assert_equal(loaded.content.simple_encounter_by_id(0).response_at(0).result_program_id, "simple:0:result:0", "Encounter choices reference ordinary result programs")
	assert_equal(loaded.content.complex_encounter_by_id(0).expected_word(), "open", "Complex Encounter words become typed runtime data")
	assert_equal(loaded.content.thief_encounter_by_id(0).type_flags().size(), 10, "Thief Encounter mutable flags have a fixed source-backed shape")
	assert_equal(loaded.content.timed_encounter_by_id(0).trigger_record_index, 0, "Timed Encounter schedules retain their Classic AP identity")
	assert_not_null(loaded.content.scenario.action_by_id("scenario.realmz2-synthetic-fixture.after-encounter"), "compiled Scenario Actions become typed callable definitions")
	assert_equal(loaded.content.item_by_id("classic.item.901").name, "Fixture Wand", "Providence item records become immutable runtime definitions")
	assert_equal(loaded.content.race_by_id("classic.race.0").base_movement, 10, "race rules cross the compiler boundary as direct Realmz data")
	assert_equal(loaded.content.caste_by_id("classic.caste.0").maximum_damage_bonus(), 5, "caste strength caps retain their source field meaning")
	assert_equal(loaded.content.monster_by_id("classic.monster.1").attacks()[0].damage_max, 4, "monster attacks are typed instead of retained as native row dictionaries")
	assert_equal(loaded.content.battle_by_id("classic.battle.0").monster_slots()[0].monster_id, "classic.monster.1", "battle placements reference stable monster IDs")
	assert_equal(loaded.content.shop_by_id("classic.shop.0").quantity(0), 2, "shop stock compiles to stable item references and quantities")
	assert_equal(loaded.content.treasure_by_id("classic.treasure.0").item_ids()[0], "classic.item.901", "treasures use the same item identity as inventory")
	assert_equal(loaded.content.spell_by_id("classic.spell.5101").damage_max, 4, "custom spells use packed Realmz class/level/slot identity")
	assert_not_null(loaded.content.spell_by_id("classic.spell.1101"), "Providence compiles standard Data S spells into normalized runtime definitions")
	assert_not_null(loaded.media, "validated package media receives a typed catalog")
	assert_equal(loaded.media.assets().size(), 4, "the synthetic fixture carries authored picture/sound media and both referenced map atlases")
	var indexed_picture := loaded.media.picture_by_resource_id(128)
	assert_not_null(indexed_picture, "Classic picture identity resolves through the typed media index")
	assert_false(loaded.media.read_bytes(indexed_picture).is_empty(), "content-addressed picture bytes are hash-checked when read")
	var indexed_sound := loaded.media.sound_by_resource_id(30005)
	assert_not_null(indexed_sound, "Classic sound identity resolves through the typed media index")
	assert_false(loaded.media.read_bytes(indexed_sound).is_empty(), "content-addressed sound bytes are hash-checked when read")
	var land_tileset := loaded.media.tileset_by_id("landlook-0")
	assert_not_null(land_tileset, "the authoritative land render identity resolves to a package tileset")
	assert_equal(land_tileset.region_for(156), Rect2i(480, 224, 32, 32), "Classic one-based land tile IDs resolve to the expected atlas region")
	assert_false(loaded.media.read_bytes(land_tileset).is_empty(), "content-addressed land atlas bytes are hash-checked when read")
	var dungeon_tileset := loaded.media.tileset_by_id("dungeon-top-down-302")
	assert_not_null(dungeon_tileset, "the authoritative dungeon render identity resolves to a package tileset")
	assert_equal(dungeon_tileset.region_for(1), Rect2i(0, 0, 16, 16), "the first Classic dungeon tile resolves without an off-by-one shift")

	var install_root := "user://realmz2-tests/package-install"
	var installed := repository.install_package(FIXTURE_PATH, install_root)
	assert_true(installed.is_ok(), "a validated package installs through temporary typed readback: %s" % installed.error_message)
	if installed.is_ok():
		assert_true(FileAccess.file_exists(installed.installed_path), "the immutable installed package exists at its content-hash path")
		assert_contains(installed.installed_path, loaded.content.package_hash, "the installation path carries the package identity")
		var repeated := repository.install_package(FIXTURE_PATH, install_root)
		assert_true(repeated.is_ok(), "reinstalling identical immutable content is idempotent")
		assert_equal(repeated.installed_path, installed.installed_path, "idempotent installation resolves to the same package")
		var discovered := repository.discover_packages([install_root])
		var matching_installations: int = 0
		for candidate: PackageDiscoveryResult in discovered:
			if candidate.package_hash == loaded.content.package_hash:
				matching_installations += 1
				assert_true(candidate.ready, "discovery reports independently validated readiness")
		assert_equal(matching_installations, 1, "discovery returns the immutable package identity exactly once")

	var picture := PackageMediaAsset.new("fixture.picture", "Fixture", "picture", "image/png", "PICT", 128, 0, "0000000000000000000000000000000000000000000000000000000000000000", "assets/media/0000000000000000000000000000000000000000000000000000000000000000.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	assert_true(picture.is_picture(), "package media classifies pictures by typed MIME and resource identity")
	assert_false(picture.is_sound(), "picture media cannot be selected by the sound presenter")

	var settings_path := "user://realmz2-tests/presentation-settings.json"
	var settings_repository := SettingsRepository.new(settings_path)
	var settings := PresentationSettings.new()
	settings.master_volume = 0.35
	settings.topology_debug = true
	settings.text_scale = 1.2
	settings.reduced_motion = true
	settings.dungeon_3d = true
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
	var legacy_settings := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 1, "masterVolume": 1.0, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false})
	assert_not_null(legacy_settings, "version-one presentation settings migrate without entering gameplay state")
	assert_false(legacy_settings.dungeon_3d, "migrated presentation settings default the optional 3D view off")

	var rejected := repository.load_package(TAMPERED_FIXTURE_PATH)
	assert_false(rejected.is_ok(), "a content mutation without matching manifest hashes is rejected")
	assert_contains(rejected.error_message, "failed size or SHA-256", "hash rejection reports the violated boundary")

	var sandbox_error := PackageRepository.package_capability_error("realmz.scenario.gdscript-actions-v1")
	assert_contains(sandbox_error, "no secure external host", "the manifest readiness path rejects deferred GDScript backends at the security boundary")
	assert_contains(PackageRepository.package_capability_error("realmz.scenario.unknown-v1"), "unknown capability", "the same readiness path rejects unrecognized package capabilities")
