extends RealmzTestCase


func run() -> void:
	_test_weighted_complete_footprint_route()
	_test_static_profile_cache_and_invalidation()
	_test_dynamic_occupancy_forecast()
	_test_obstruction_and_unreachable_routes()
	_test_all_footprint_profiles()


func _test_weighted_complete_footprint_route() -> void:
	var field := _field(1)
	field.set_terrain(Vector2i(41, 44), 3)
	field.place_monster("mover", Vector2i(40, 45), 1)
	field.place_character("target", Vector2i(47, 45))
	var rules := BattlefieldRules.new()
	var step := rules.probe_path_step_toward_actors(field, _terrain_set(), "mover", ["target"], 20)
	assert_equal([step.allowed, step.destination, step.movement_cost], [true, Vector2i(41, 46), 2], "weighted routing uses the maximum terrain charge across the complete footprint and avoids the expensive upper cell")
	var charged := rules.probe_step(field, _terrain_set(), "mover", Vector2i(1, -1), 20)
	assert_equal(charged.movement_cost, 11, "the direct step and weighted planner share the exact complete-footprint movement formula")
	var low_movement := rules.probe_path_step_toward_actors(field, _terrain_set(), "mover", ["target"], 1)
	assert_equal([low_movement.allowed, low_movement.destination, low_movement.movement_cost], [true, Vector2i(40, 46), 1], "route selection excludes unaffordable immediate edges while retaining an executable weighted detour")


func _test_static_profile_cache_and_invalidation() -> void:
	var field := _field(1)
	field.place_character("mover", Vector2i(40, 45))
	field.place_character("target", Vector2i(47, 45))
	var terrain := _terrain_set()
	var rules := BattlefieldRules.new()
	var first := rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 20)
	field.move_actor("target", Vector2i(48, 45))
	var second := rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 20)
	var builds_before_change := rules.debug_navigation_profile_build_count()
	field.set_terrain(Vector2i(42, 45), 3)
	var third := rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 20)
	assert_equal([first.allowed, second.allowed, third.allowed, builds_before_change, rules.debug_navigation_profile_build_count(), rules.debug_route_workspace_generation()], [true, true, true, 1, 2, 3], "actor motion reuses four derived profiles and typed search storage while an authoritative terrain mutation invalidates the cache")
	assert_false(field.to_data().has("terrainRevision"), "the navigation invalidation revision never enters serialized battlefield state")


func _test_dynamic_occupancy_forecast() -> void:
	var forecast_field := _field(2)
	for x: int in range(40, 50):
		forecast_field.set_terrain(Vector2i(x, 45), 1)
	forecast_field.place_character("mover", Vector2i(40, 45))
	forecast_field.place_character("traffic", Vector2i(43, 45))
	forecast_field.place_character("target", Vector2i(49, 45))
	var terrain := _terrain_set()
	var forecast := BattlefieldRules.new().probe_path_step_toward_actors(forecast_field, terrain, "mover", ["target"], 20)
	assert_equal([forecast.allowed, forecast.destination], [true, Vector2i(41, 45)], "later mobile occupancy remains a route forecast rather than a permanent wall")
	var swap_forecast_field := _field(1); swap_forecast_field.place_character("mover", Vector2i(40, 45)); swap_forecast_field.place_character("traffic", Vector2i(42, 45)); swap_forecast_field.place_character("target", Vector2i(44, 45)); swap_forecast_field.set_terrain(Vector2i(42, 44), 2); swap_forecast_field.set_terrain(Vector2i(42, 46), 2); var swap_forecast := BattlefieldRules.new().probe_path_step_toward_actors(swap_forecast_field, terrain, "mover", ["target"], 20, ["traffic"]); assert_equal([swap_forecast.allowed, swap_forecast.destination], [true, Vector2i(41, 44)], "a later legal allied swap carries its real five-movement cost so repeated route-first decisions do not steer into and then away from the same occupied lane")
	var immediate_field := BattlefieldState.from_data(forecast_field.to_data()); immediate_field.move_actor("traffic", Vector2i(41, 45))
	var blocked := BattlefieldRules.new().probe_path_step_toward_actors(immediate_field, terrain, "mover", ["target"], 20)
	assert_equal([blocked.allowed, blocked.reason], [false, &"path_not_found"], "the same dynamic occupancy blocks the immediate move when the corridor has no legal alternative")


func _test_obstruction_and_unreachable_routes() -> void:
	var u_field := _field(1)
	u_field.place_character("mover", Vector2i(40, 45))
	u_field.place_character("target", Vector2i(47, 45))
	for coordinate: Vector2i in [Vector2i(41, 45), Vector2i(44, 44), Vector2i(44, 45), Vector2i(44, 46), Vector2i(45, 44), Vector2i(45, 46), Vector2i(46, 44), Vector2i(46, 46)]:
		u_field.set_terrain(coordinate, 2)
	var routed := BattlefieldRules.new().probe_path_step_toward_actors(u_field, _terrain_set(), "mover", ["target"], 20)
	assert_true(routed.allowed and routed.destination != Vector2i(41, 45), "a U-shaped obstruction is planned around before committing the first pursuit step")
	var sealed := _field(1)
	sealed.place_character("mover", Vector2i(40, 45))
	sealed.place_character("target", Vector2i(47, 45))
	for y: int in range(0, BattlefieldState.SIZE):
		sealed.set_terrain(Vector2i(44, y), 2)
	var unreachable := BattlefieldRules.new().probe_path_step_toward_actors(sealed, _terrain_set(), "mover", ["target"], 20)
	assert_equal([unreachable.allowed, unreachable.reason], [false, &"path_not_found"], "an unreachable target terminates with the stable no-route result")


func _test_all_footprint_profiles() -> void:
	var first_steps: Array[Vector2i] = []
	var rules := BattlefieldRules.new()
	var terrain := _terrain_set()
	for actor_size: int in 4:
		var field := _field(1)
		field.place_monster("mover", Vector2i(40, 45), actor_size)
		field.place_character("target", Vector2i(47, 45))
		var step := rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 20)
		assert_true(step.allowed, "footprint profile %d finds a legal contact route" % actor_size)
		first_steps.append(step.destination)
	assert_equal(first_steps, [Vector2i(41, 45), Vector2i(41, 45), Vector2i(41, 45), Vector2i(41, 45)], "all four footprint profiles retain the deterministic open-field first step")


func _field(fill_tile: int) -> BattlefieldState:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(fill_tile)
	return BattlefieldState.new("battlefield.navigation", tiles)


func _terrain_set() -> BattleTerrainSetDefinition:
	var tiles: Array[BattleTerrainTileDefinition] = [
		BattleTerrainTileDefinition.new(1, 0, 0, 0, false, 0, false, false, false, 0, []),
		BattleTerrainTileDefinition.new(2, 0, 0, 2, false, 0, false, false, false, 0, []),
		BattleTerrainTileDefinition.new(3, 0, 20, 0, false, 0, false, false, false, 0, []),
	]
	return BattleTerrainSetDefinition.new("battlefield.navigation.terrain", 1, 1, tiles)
