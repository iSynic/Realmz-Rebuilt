class_name BattlefieldBuilder
extends RefCounted

const SOURCE_SIZE: int = 30
const SCALE: int = 3
const GOOD_MINIMUM: int = 7
const GOOD_MAXIMUM_EXCLUSIVE: int = 83
const MAX_SEARCH_RADIUS: int = 512
const DUNGEON_WALL_TILE: int = 234
const DUNGEON_FLOOR_TILE: int = 232


func build_terrain(map: MapDefinition, world_state: WorldState, terrain_set: BattleTerrainSetDefinition, party_coordinate: Vector2i, rng: RealmzRng) -> BattlefieldBuildResult:
	if map == null or world_state == null or terrain_set == null or rng == null:
		return BattlefieldBuildResult.failed(&"invalid_battlefield_input", "Battlefield generation requires a map, overlays, terrain catalog, and session randomness.")
	if map.topology.width < SOURCE_SIZE or map.topology.height < SOURCE_SIZE:
		return BattlefieldBuildResult.failed(&"battlefield_map_too_small", "Map '%s' cannot provide Castle's 30 by 30 battle source window." % map.id)
	if map.level_type == &"land" and terrain_set.landlook != world_state.map_landlook(map) or map.level_type == &"dungeon" and terrain_set.landlook != -1:
		return BattlefieldBuildResult.failed(&"battlefield_terrain_mismatch", "Map '%s' references a battle terrain catalog for a different Classic map type." % map.id)
	var requested_origin := party_coordinate - Vector2i(15, 15)
	var source_origin := Vector2i(
		clampi(requested_origin.x, 0, map.topology.width - SOURCE_SIZE),
		clampi(requested_origin.y, 0, map.topology.height - SOURCE_SIZE)
	)
	var map_shift := (requested_origin - source_origin) * SCALE
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(terrain_set.base_tile if map.level_type == &"land" else DUNGEON_FLOOR_TILE)
	var battlefield := BattlefieldState.new(map.id, tiles, source_origin, map_shift)
	for source_y: int in SOURCE_SIZE:
		for source_x: int in SOURCE_SIZE:
			var cell := map.topology.effective_cell_at(source_origin + Vector2i(source_x, source_y), world_state)
			if cell == null:
				return BattlefieldBuildResult.failed(&"battlefield_missing_cell", "Map '%s' is missing a cell inside Castle's battle source window." % map.id)
			var build: Array = _dungeon_build(cell) if map.level_type == &"dungeon" else _land_build(map.id, cell, world_state, terrain_set)
			if build.is_empty():
				return BattlefieldBuildResult.failed(&"battlefield_missing_build", "Map '%s' cannot resolve battle terrain for cell %s." % [map.id, cell.coordinate])
			for sub_y: int in SCALE:
				for sub_x: int in SCALE:
					battlefield.set_terrain(Vector2i(source_x * SCALE + sub_x, source_y * SCALE + sub_y), int(build[sub_y][sub_x]))
	var decoration_error := _decorate_dungeon(battlefield, terrain_set, rng) if map.level_type == &"dungeon" else _decorate_land(battlefield, terrain_set, rng)
	if not decoration_error.is_empty():
		return BattlefieldBuildResult.failed(&"battlefield_decoration_failed", decoration_error)
	return BattlefieldBuildResult.succeeded(battlefield)


func roll_formation(battlefield: BattlefieldState, battle: BattleDefinition, rng: RealmzRng) -> Dictionary:
	if battlefield == null or battle == null or rng == null:
		return {}
	var direction := rng.draw(360, &"battle.setup.direction")
	var distance := rng.draw_classic(battle.distance, &"battle.setup.distance")
	var degree := float(direction) / 57.3
	var monster_origin := Vector2i(int(cos(degree) * float(distance) - 5.0), int(sin(degree) * float(distance) - 5.0))
	var swap_axes := direction < 45 or direction > 315 or direction > 135 and direction < 225
	var vertical_sign := -1 if direction < 180 else 1
	var horizontal_sign := 1 if direction > 90 and direction < 270 else -1
	battlefield.direction_degrees = direction
	battlefield.rolled_distance = distance
	return {
		"monsterOrigin": monster_origin,
		"swapAxes": swap_axes,
		"verticalSign": vertical_sign,
		"horizontalSign": horizontal_sign,
	}


func place_character(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, party_index: int, formation: Dictionary) -> bool:
	if battlefield == null or terrain_set == null or actor_id.is_empty() or party_index < 0 or formation.is_empty():
		return false
	var quotient := int(float(party_index) / 3.0)
	var horizontal_sign := int(formation.get("horizontalSign", -1))
	var vertical_sign := int(formation.get("verticalSign", 1))
	var base := Vector2i.ZERO
	if bool(formation.get("swapAxes", false)):
		base = Vector2i(quotient * horizontal_sign, party_index - 3 * absi(quotient) + absi(quotient) * vertical_sign)
	else:
		base = Vector2i(party_index - 3 * absi(quotient) + absi(quotient) * horizontal_sign, quotient * vertical_sign)
	var coordinate := _find_character_cell(battlefield, terrain_set, base)
	return coordinate.x >= 0 and battlefield.place_character(actor_id, coordinate)


func find_monster_position(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, desired_local: Vector2i, size: int) -> Vector2i:
	if battlefield == null or terrain_set == null or size < 0 or size > 3:
		return Vector2i(-1, -1)
	var center := battlefield.party_anchor + desired_local
	for radius: int in range(1, _maximum_useful_radius(center) + 1):
		var start := -radius
		var stop := radius
		for vertical_offset: int in range(start, stop):
			for horizontal_offset: int in range(start, stop):
				# Earlier radii already proved the interior illegal. Skipping those
				# repeated probes preserves this radius's row-major first candidate.
				if not _is_new_radius_edge(horizontal_offset, vertical_offset, radius):
					continue
				var candidate := center + Vector2i(horizontal_offset, vertical_offset)
				if _monster_position_is_legal(battlefield, terrain_set, candidate, size):
					return candidate
	return Vector2i(-1, -1)


func place_monster(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, desired_local: Vector2i, size: int) -> bool:
	var coordinate := find_monster_position(battlefield, terrain_set, desired_local, size)
	return coordinate.x >= 0 and battlefield.place_monster(actor_id, coordinate, size)


func _find_character_cell(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, base_local: Vector2i) -> Vector2i:
	var center := battlefield.party_anchor + base_local
	for radius: int in range(1, _maximum_useful_radius(center) + 1):
		for vertical_offset: int in range(-radius, radius):
			for horizontal_offset: int in range(-radius, radius):
				if not _is_new_radius_edge(horizontal_offset, vertical_offset, radius):
					continue
				var candidate := center + Vector2i(horizontal_offset, vertical_offset)
				if not _inside_good_rect(candidate) or battlefield.is_occupied(candidate):
					continue
				var terrain := terrain_set.tile_by_id(battlefield.terrain_at(candidate))
				if terrain != null and terrain.solid == 0:
					return candidate
	return Vector2i(-1, -1)


func _monster_position_is_legal(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, anchor: Vector2i, size: int) -> bool:
	if not _inside_good_rect(anchor):
		return false
	var footprint := BattlefieldState.footprint_cells(anchor, size)
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate) or battlefield.is_occupied(coordinate):
			return false
		var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
		if terrain == null:
			return false
		if coordinate == anchor:
			if size == 0 and terrain.solid != 0 or terrain.solid == 2:
				return false
		elif terrain.solid > 1:
			return false
	return true


func _land_build(map_id: String, cell: MapCell, world_state: WorldState, terrain_set: BattleTerrainSetDefinition) -> Array:
	var tile := _effective_land_tile(map_id, cell, world_state, terrain_set.base_tile)
	if tile <= 0 or tile >= 201:
		tile = terrain_set.base_tile
	var definition := terrain_set.tile_by_id(tile)
	if definition == null:
		return []
	return definition.combat_build()


func _dungeon_build(cell: MapCell) -> Array:
	var floor_in_battle := cell.terrain_id != "classic.dungeon.wall"
	for feature: MapFeature in cell.features():
		if feature.kind in [&"door", &"stairs", &"secret", &"no-wall-in-battle"]:
			floor_in_battle = true
			break
	var tile := DUNGEON_FLOOR_TILE if floor_in_battle else DUNGEON_WALL_TILE
	return [[tile, tile, tile], [tile, tile, tile], [tile, tile, tile]]


func _decorate_dungeon(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, rng: RealmzRng) -> String:
	for y: int in range(2, 88):
		for x: int in range(2, 88):
			var coordinate := Vector2i(x, y)
			var roll := rng.draw(100, &"battle.terrain.dungeon-rubble-chance")
			var definition := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
			if definition == null:
				return "Dungeon battle terrain references an unavailable Combat Data BD tile."
			if roll < 10 and definition.solid == 0:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(141, 158, &"battle.terrain.dungeon-rubble-tile"))
	return ""


func _decorate_land(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, rng: RealmzRng) -> String:
	for y: int in range(2, 88):
		for x: int in range(2, 88):
			var coordinate := Vector2i(x, y)
			var bottom := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
			var top := terrain_set.tile_by_id(battlefield.terrain_at(coordinate + Vector2i.UP))
			if bottom == null or top == null:
				return "Land battle terrain references an unavailable effective mapstats tile."
			if bottom.forest != 0:
				# Castle combatmap.c uses bottom.ispath in both sums. Preserve that observable
				# draw branch until a named fidelity decision adjudicates the apparent typo.
				var bottom_blocked := bottom.solid + int(bottom.shore) + bottom.need_boat + int(bottom.blocks_los) + int(bottom.is_path)
				var top_blocked := top.solid + int(top.shore) + top.need_boat + int(top.blocks_los) + int(bottom.is_path)
				if bottom_blocked == 0 and top_blocked == 0:
					_decorate_forest_cell(battlefield, coordinate, bottom.forest, terrain_set.base_tile, rng)
				else:
					battlefield.set_terrain(coordinate, terrain_set.base_tile)
			elif battlefield.terrain_at(coordinate) == terrain_set.base_tile:
				_decorate_rubble_cell(battlefield, coordinate, terrain_set.landlook, rng)
	return ""


func _decorate_forest_cell(battlefield: BattlefieldState, coordinate: Vector2i, forest: int, base_tile: int, rng: RealmzRng) -> void:
	var top_coordinate := coordinate + Vector2i.UP
	match forest:
		1:
			if rng.draw(100, &"battle.terrain.forest-primary") < 20:
				var bottom_tile := 200 + rng.draw_between(67, 71, &"battle.terrain.forest-tile")
				battlefield.set_terrain(coordinate, bottom_tile)
				battlefield.set_terrain(top_coordinate, bottom_tile - 6 if not _between(battlefield.terrain_at(top_coordinate), 267, 271) else 266)
			elif rng.draw(100, &"battle.terrain.forest-secondary") < 10:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(81, 91, &"battle.terrain.forest-rubble"))
			else:
				battlefield.set_terrain(coordinate, base_tile)
		2:
			if rng.draw(100, &"battle.terrain.forest-primary") < 20:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(107, 111, &"battle.terrain.forest-tile"))
				battlefield.set_terrain(top_coordinate, 200 + rng.draw_between(101, 105, &"battle.terrain.forest-top") if not _between(battlefield.terrain_at(top_coordinate), 307, 311) else 306)
			elif rng.draw(100, &"battle.terrain.forest-secondary") < 10:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(121, 131, &"battle.terrain.forest-rubble"))
			else:
				battlefield.set_terrain(coordinate, base_tile)
		3:
			if rng.draw(100, &"battle.terrain.forest-primary") < 20 and not _between(battlefield.terrain_at(top_coordinate), 273, 280):
				var bottom_tile := 200 + rng.draw_between(77, 80, &"battle.terrain.forest-tile")
				battlefield.set_terrain(coordinate, bottom_tile)
				battlefield.set_terrain(top_coordinate, bottom_tile - 4)
			elif rng.draw(100, &"battle.terrain.forest-secondary") < 10:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(92, 100, &"battle.terrain.forest-rubble"))
			else:
				battlefield.set_terrain(coordinate, base_tile)
		4:
			if rng.draw(100, &"battle.terrain.forest-primary") < 20 and not _between(battlefield.terrain_at(top_coordinate), 381, 391):
				var bottom_tile := 200 + rng.draw_between(186, 190, &"battle.terrain.forest-tile")
				battlefield.set_terrain(coordinate, bottom_tile)
				if not _between(battlefield.terrain_at(top_coordinate), 307, 311):
					battlefield.set_terrain(top_coordinate, bottom_tile - 5)
			elif rng.draw(100, &"battle.terrain.forest-secondary") < 10:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(159, 171, &"battle.terrain.forest-rubble"))
			else:
				battlefield.set_terrain(coordinate, base_tile)
		5:
			if rng.draw(100, &"battle.terrain.forest-primary") < 20 and not _between(battlefield.terrain_at(top_coordinate), 391, 400):
				var bottom_tile := 200 + rng.draw_between(196, 200, &"battle.terrain.forest-tile")
				battlefield.set_terrain(coordinate, bottom_tile)
				if not _between(battlefield.terrain_at(top_coordinate), 317, 321):
					battlefield.set_terrain(top_coordinate, bottom_tile - 5)
			elif rng.draw(100, &"battle.terrain.forest-secondary") < 10:
				battlefield.set_terrain(coordinate, 200 + rng.draw_between(172, 180, &"battle.terrain.forest-rubble"))
			else:
				battlefield.set_terrain(coordinate, base_tile)


func _decorate_rubble_cell(battlefield: BattlefieldState, coordinate: Vector2i, landlook: int, rng: RealmzRng) -> void:
	var range_limits: Vector2i
	match landlook:
		0:
			range_limits = Vector2i(81, 91)
		3:
			range_limits = Vector2i(92, 100)
		5:
			range_limits = Vector2i(121, 131)
		9:
			range_limits = Vector2i(159, 171)
		10:
			range_limits = Vector2i(172, 180)
		_:
			return
	if rng.draw(100, &"battle.terrain.rubble-chance") < 20:
		battlefield.set_terrain(coordinate, 200 + rng.draw_between(range_limits.x, range_limits.y, &"battle.terrain.rubble-tile"))


static func _effective_land_tile(map_id: String, cell: MapCell, world_state: WorldState, base_tile: int) -> int:
	var raw_tile := world_state.classic_tile_for(map_id, cell)
	return base_tile if raw_tile < 0 else WorldState.normalized_classic_land_tile(raw_tile)


static func _inside_good_rect(coordinate: Vector2i) -> bool:
	return coordinate.x >= GOOD_MINIMUM and coordinate.y >= GOOD_MINIMUM and coordinate.x < GOOD_MAXIMUM_EXCLUSIVE and coordinate.y < GOOD_MAXIMUM_EXCLUSIVE


static func _maximum_useful_radius(center: Vector2i) -> int:
	var required := maxi(
		maxi(absi(GOOD_MINIMUM - center.x), absi((GOOD_MAXIMUM_EXCLUSIVE - 1) - center.x)),
		maxi(absi(GOOD_MINIMUM - center.y), absi((GOOD_MAXIMUM_EXCLUSIVE - 1) - center.y))
	) + 2
	return mini(required, MAX_SEARCH_RADIUS)


static func _is_new_radius_edge(horizontal_offset: int, vertical_offset: int, radius: int) -> bool:
	return horizontal_offset == -radius or horizontal_offset == radius - 1 or vertical_offset == -radius or vertical_offset == radius - 1


static func _between(value: int, low: int, high: int) -> bool:
	return value >= low and value <= high
