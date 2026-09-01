extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "topology fixture loads: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var world_state := WorldState.new()
	var land := loaded.content.world.map_by_id("land:0")
	var hidden_cell := land.topology.cell_at(Vector2i(0, 1)); var hidden_feature := hidden_cell.feature_by_kind(&"secret")
	assert_not_null(hidden_feature, "land secret is an explicit feature")
	var hidden_probe := land.topology.probe_land_entry(hidden_cell.coordinate, world_state)
	assert_true(hidden_probe.allowed, "an undiscovered land secret preserves the underlying terrain's passability")
	assert_equal(hidden_probe.target_cell, hidden_cell, "a concealed destination retains its authoritative terrain facts")
	world_state.discover_secret(hidden_feature.id)
	var solid_secret := MapFeature.new("solid-secret", &"secret", &"hidden"); var solid_trigger_ids: Array[String] = ["solid-secret-ap"]; var solid_cell := MapCell.new("solid-secret-cell", Vector2i.ZERO, "classic.terrain.38", false, 1, true, true, false, false, false, false, false, 0, 38, "fixture.tileset", solid_trigger_ids, [], {}, [solid_secret]); var solid_topology := MapTopology.new(1, 1, [solid_cell]); assert_equal(solid_topology.probe_land_entry(Vector2i.ZERO, world_state).reason, &"terrain_blocked", "a concealed secret preserves solid underlying terrain even when an AP shares its cell"); world_state.discover_secret(solid_secret.id); assert_true(land.topology.probe_land_entry(hidden_cell.coordinate, world_state).allowed and solid_topology.probe_land_entry(Vector2i.ZERO, world_state).allowed, "discovery preserves walkable terrain and opens a formerly solid secret entrance")
	assert_true(land.topology.probe_land_entry(Vector2i.ZERO, world_state).allowed, "land entry checks the destination tile without inventing a diagonal edge")
	assert_equal(land.topology.probe_entry(Vector2i.ZERO, Vector2i(-1, -1), world_state).reason, &"invalid_direction", "edge-based topology entry remains cardinal for dungeons and pathfinding")
	assert_equal(land.topology.find_path(Vector2i(1, 1), Vector2i.ZERO, world_state, &"land"), [Vector2i.ZERO], "land pathfinding uses the same direct diagonal probe without corner blocking")
	assert_equal(land.topology.visible_cells(Vector2i(1, 1), 8, world_state, false).size(), 8100, "non-LOS land view derives every Classic map cell from topology")
	var bounded_visibility := land.topology.visible_cells(Vector2i(1, 1), 2, world_state, true); assert_true(bounded_visibility.all(func(coordinate: Vector2i) -> bool: return coordinate.x <= 3 and coordinate.y <= 3), "LOS visibility probes only the bounded radius neighborhood")
	assert_true(bounded_visibility.size() <= 16, "edge-clamped LOS visibility never traverses the complete map")
	var no_ids: Array[String] = []; var no_features: Array[MapFeature] = []; var no_edges := {&"north": MapEdge.new(&"open", true, false), &"east": MapEdge.new(&"open", true, false), &"south": MapEdge.new(&"open", true, false), &"west": MapEdge.new(&"open", true, false)}; var wall_edges := {&"north": MapEdge.new(&"wall", false, true), &"east": MapEdge.new(&"wall", false, true), &"south": MapEdge.new(&"wall", false, true), &"west": MapEdge.new(&"wall", false, true)}; var los_cells: Array[MapCell] = [MapCell.new("los:0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", no_ids, no_ids, no_edges, no_features), MapCell.new("los:1", Vector2i(1, 0), "classic.terrain.2", false, 1, true, true, false, false, false, false, false, 0, 2, "fixture.tileset", no_ids, no_ids, wall_edges, no_features), MapCell.new("los:2", Vector2i(2, 0), "classic.terrain.3", true, 1, false, true, false, false, false, false, false, 0, 3, "fixture.tileset", no_ids, no_ids, no_edges, no_features)]; var los_map := MapDefinition.new("los", "LOS", &"land", 0, MapTopology.new(3, 1, los_cells), false, true); var los_content := RealmzContent.new("los-fixture", "0".repeat(64), "los-content", "realmz-classic-1", los_map.id, Vector2i.ZERO, WorldDefinition.new([los_map]), ScenarioDefinition.new([], []), [], [], [], loaded.content.race_definitions(), loaded.content.caste_definitions()); var los_session := GameSession.new(); assert_equal(los_session.start(los_content, 17).state, SessionStep.State.COMPLETED, "the public session starts on the synthetic LOS map")
	var los_view := los_session.view().map_view; assert_equal([los_view.uses_los, los_view.cell_at(Vector2i(1, 0)).visible, los_view.cell_at(Vector2i(2, 0)).visible, los_view.seen_coordinates(), los_map.topology.exploration_visible_cells(Vector2i.ZERO, WorldState.new(), true, true)], [true, true, false, [Vector2i.ZERO, Vector2i(1, 0)], [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]], "the blocking tile enters exact saved sight memory, the sealed tile beyond stays black, and bounded Wizard's Eye ignores occluders")
	var sight_cells: Array[MapCell] = []
	for x: int in 33:
		sight_cells.append(MapCell.new("sight:%d" % x, Vector2i(x, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", no_ids, no_ids, no_edges, no_features))
	var sight_topology := MapTopology.new(33, 1, sight_cells); var sight_origin := Vector2i(16, 0); var ordinary_sight := sight_topology.exploration_visible_cells(sight_origin, WorldState.new(), true); var wizard_sight := sight_topology.exploration_visible_cells(sight_origin, WorldState.new(), true, true)
	assert_equal([MapTopology.EXPLORATION_VISIBILITY_RADIUS, ordinary_sight.front(), ordinary_sight.back(), ordinary_sight.size()], [8, Vector2i(8, 0), Vector2i(24, 0), 17], "ordinary LOS remains the bounded radius-eight exploration probe")
	assert_equal([MapTopology.WIZARDS_EYE_VISIBILITY_RADIUS, wizard_sight.front(), wizard_sight.back(), wizard_sight.size()], [16, Vector2i.ZERO, Vector2i(32, 0), 33], "Wizard's Eye doubles the exploration radius while remaining bounded to the current map")
	var edge_only_cells: Array[MapCell] = [los_cells[0], MapCell.new("edge:1", Vector2i(1, 0), "classic.terrain.3", true, 1, false, true, false, false, false, false, false, 0, 3, "fixture.tileset", no_ids, no_ids, wall_edges, no_features)]; assert_false(MapTopology.new(2, 1, edge_only_cells).has_line_of_sight(Vector2i.ZERO, Vector2i(1, 0), WorldState.new()), "a blocking edge still hides a passable destination cell")

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
	var blocked_target_cell := MapCell.new("layout-target:0", Vector2i.ZERO, "classic.terrain.38", false, 1, true, true, false, false, false, false, false, 0, 38, "fixture.tileset", no_ids, no_ids, no_edges, no_features)
	var blocked_target_map := MapDefinition.new("land:blocked-target", "Blocked target", &"land", 2, MapTopology.new(1, 1, [blocked_target_cell]), false, false)
	var layout_only_world := WorldDefinition.new([MapDefinition.new("land:source", "Source", &"land", 3, MapTopology.new(1, 1, [los_cells[0]]), false, false), blocked_target_map], [MapTransition.new("layout:source:south:target", "land:source", &"south", "land:blocked-target", &"north")])
	var layout_only_transition := layout_only_world.probe_movement("land:source", Vector2i.ZERO, Vector2i.DOWN, world_state)
	assert_true(layout_only_transition.allowed and layout_only_transition.target_coordinate == Vector2i.ZERO and layout_only_transition.topology_result.target_cell == blocked_target_cell, "a Castle Layout neighbor wraps onto its authored edge coordinate without rechecking the destination terrain")
	var secret_probe := dungeon.topology.probe_entry(Vector2i(0, 1), Vector2i.RIGHT, world_state)
	assert_true(secret_probe.allowed, "matching directional secret passage permits entry")
	assert_equal(secret_probe.secret_id, "dungeon:0:cell:0,1:secret:east", "secret passage returns its stable overlay identity")
	assert_false(dungeon.topology.probe_entry(Vector2i(0, 1), Vector2i.UP, world_state).allowed, "nonmatching secret direction remains blocked")

	world_state.open_door(door_probe.door_id); world_state.mark_visited("dungeon:0", Vector2i(1, 0)); world_state.mark_seen("dungeon:0", Vector2i(2, 0))
	var restored := WorldState.from_data(world_state.to_data())
	var prior_save_data := world_state.to_data(); prior_save_data.erase("seenCells"); var prior_save := WorldState.from_data(prior_save_data)
	assert_not_null(restored, "world overlays serialize as typed state")
	assert_true(restored.door_is_open(door_probe.door_id), "door overlay survives serialization")
	assert_true(restored.secret_is_discovered(hidden_feature.id), "secret discovery survives serialization")
	assert_true(restored.was_visited("dungeon:0", Vector2i(1, 0)) and restored.seen_coordinates("dungeon:0") == [Vector2i(1, 0), Vector2i(2, 0)] and prior_save.seen_coordinates("dungeon:0") == [Vector2i(1, 0)], "walked and exact sight-memory coordinates remain distinct, survive deterministic serialization, and safely seed current-schema saves that predate exact sight memory")
