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
	assert_equal(loaded.content.package_hash, "540d28daa48531e158da56d40e6ff10809c96695119cd02f7d8a46423ec3d1b8", "package identity is retained")
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
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").replacement.target_coordinate, Vector2i(2, 2), "AP replacement data is typed")
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
	assert_equal(loaded.content.battle_by_id("classic.battle.0").monster_ids()[0], "classic.monster.1", "battle slots reference stable monster IDs")
	assert_equal(loaded.content.shop_by_id("classic.shop.0").quantity(0), 2, "shop stock compiles to stable item references and quantities")
	assert_equal(loaded.content.treasure_by_id("classic.treasure.0").item_ids()[0], "classic.item.901", "treasures use the same item identity as inventory")
	assert_equal(loaded.content.spell_by_id("classic.spell.5101").damage_max, 4, "custom spells use packed Realmz class/level/slot identity")
	assert_not_null(loaded.content.spell_by_id("classic.spell.1101"), "Providence compiles standard Data S spells into normalized runtime definitions")

	var rejected := repository.load_package(TAMPERED_FIXTURE_PATH)
	assert_false(rejected.is_ok(), "a content mutation without matching manifest hashes is rejected")
	assert_contains(rejected.error_message, "failed size or SHA-256", "hash rejection reports the violated boundary")
