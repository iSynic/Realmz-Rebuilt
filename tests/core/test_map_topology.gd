extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "topology fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var world_state := WorldState.new()
	var land := loaded.content.world.map_by_id("land:0")
	var hidden_cell := land.topology.cell_at(Vector2i(0, 1))
	var hidden_feature := hidden_cell.feature_by_kind(&"secret")
	assert_not_null(hidden_feature, "land secret is an explicit feature")
	var hidden_probe := land.topology.probe_entry(hidden_cell.coordinate, Vector2i.LEFT, world_state)
	assert_equal(hidden_probe.reason, &"secret_hidden", "hidden land secret blocks movement through topology")
	assert_equal(hidden_probe.target_cell, hidden_cell, "a blocked destination retains its authoritative terrain facts for Classic attempt timing")
	world_state.discover_secret(hidden_feature.id)
	assert_true(land.topology.probe_entry(hidden_cell.coordinate, Vector2i.LEFT, world_state).allowed, "discovery overlay changes the same topology query")
	assert_true(land.topology.probe_land_entry(Vector2i.ZERO, world_state).allowed, "land entry checks the destination tile without inventing a diagonal edge")
	assert_equal(land.topology.probe_entry(Vector2i.ZERO, Vector2i(-1, -1), world_state).reason, &"invalid_direction", "edge-based topology entry remains cardinal for dungeons and pathfinding")
	assert_equal(land.topology.find_path(Vector2i(1, 1), Vector2i.ZERO, world_state, &"land"), [Vector2i.ZERO], "land pathfinding uses the same direct diagonal probe without corner blocking")
	assert_equal(land.topology.visible_cells(Vector2i(1, 1), 8, world_state, false).size(), 8100, "non-LOS land view derives every Classic map cell from topology")

	var dungeon := loaded.content.world.map_by_id("dungeon:0")
	assert_equal(dungeon.topology.probe_entry(Vector2i.ZERO, Vector2i.LEFT, world_state).reason, &"terrain_blocked", "dungeon wall blocks movement")
	var door_probe := dungeon.topology.probe_entry(Vector2i(1, 0), Vector2i.LEFT, world_state)
	assert_true(door_probe.allowed, "dungeon door permits the Classic movement attempt")
	assert_equal(door_probe.door_id, "dungeon:0:cell:1,0:door", "movement and rendering share the explicit door identity")
	assert_equal(dungeon.topology.find_path(Vector2i(2, 0), Vector2i(1, 0), world_state, &"dungeon"), [Vector2i(1, 0)], "pathfinding traverses the same explicit door edge")
	assert_true(dungeon.topology.find_path(Vector2i(2, 0), Vector2i.ZERO, world_state, &"dungeon").is_empty(), "pathfinding cannot route into blocked wall terrain")
	var diagonal_world := WorldDefinition.new([land, loaded.content.world.map_by_id("land:1")], [MapTransition.new("layout:land:0:northwest:land:1", "land:0", &"northwest", "land:1", &"southeast")])
	var diagonal_transition := diagonal_world.probe_movement("land:0", Vector2i.ZERO, Vector2i(-1, -1), world_state)
	assert_true(diagonal_transition.allowed, "a diagonal land boundary probe follows the authored Layout neighbor")
	assert_equal(diagonal_transition.target_map.id, "land:1", "diagonal Layout movement selects the diagonal map")
	assert_equal(diagonal_transition.target_coordinate, Vector2i(89, 89), "diagonal Layout movement wraps to the opposite target corner")
	var secret_probe := dungeon.topology.probe_entry(Vector2i(0, 1), Vector2i.RIGHT, world_state)
	assert_true(secret_probe.allowed, "matching directional secret passage permits entry")
	assert_equal(secret_probe.secret_id, "dungeon:0:cell:0,1:secret:east", "secret passage returns its stable overlay identity")
	assert_false(dungeon.topology.probe_entry(Vector2i(0, 1), Vector2i.UP, world_state).allowed, "nonmatching secret direction remains blocked")

	world_state.open_door(door_probe.door_id)
	world_state.mark_visited("dungeon:0", Vector2i(1, 0))
	var restored := WorldState.from_data(world_state.to_data())
	assert_not_null(restored, "world overlays serialize as typed state")
	assert_true(restored.door_is_open(door_probe.door_id), "door overlay survives serialization")
	assert_true(restored.secret_is_discovered(hidden_feature.id), "secret discovery survives serialization")
	assert_true(restored.was_visited("dungeon:0", Vector2i(1, 0)), "minimap visitation survives serialization")
