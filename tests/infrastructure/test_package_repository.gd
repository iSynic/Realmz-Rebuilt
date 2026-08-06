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
	assert_equal(loaded.content.package_hash, "4a55d5762ff84fc0b82b2d4ce9fca9e1bc2a2d21151542f082f0951773a95102", "package identity is retained")
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
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").actions()[0].opcode, 1, "Classic opcode identity is typed")
	assert_equal(loaded.content.trigger_by_id("ap.fixture.message").replacement.target_coordinate, Vector2i(2, 2), "AP replacement data is typed")

	var rejected := repository.load_package(TAMPERED_FIXTURE_PATH)
	assert_false(rejected.is_ok(), "a content mutation without matching manifest hashes is rejected")
	assert_contains(rejected.error_message, "failed size or SHA-256", "hash rejection reports the violated boundary")
