extends RealmzTestCase


func run() -> void:
	_test_land_source_window_and_overlay()
	_test_dungeon_hole_normalization_and_rng()
	_test_formation_and_footprints()
	_test_battle_monster_construction_path()


func _test_land_source_window_and_overlay() -> void:
	var cells: Array[MapCell] = []
	for y: int in 30:
		for x: int in 30:
			var tile := 2 if x == 1 and y == 0 else 3 if x == 2 and y == 0 else -173 if x == 3 and y == 0 else 1
			cells.append(_cell(Vector2i(x, y), tile, &"land"))
	var map := MapDefinition.new("land.test", "Land", &"land", 0, MapTopology.new(30, 30, cells), false, false, 1, [], "terrain.land")
	var asymmetric_build := [[31, 32, 33], [34, 35, 36], [37, 38, 39]]
	var terrain := _terrain_set("terrain.land", 1, 1, {}, {3: asymmetric_build})
	var world := WorldState.new()
	world.replace_terrain(map.id, Vector2i.ZERO, "classic.terrain.2"); world.replace_terrain(map.id, Vector2i(1, 0), "classic.terrain.-1018")
	var rng := ScriptedRng.new([])
	var built := BattlefieldBuilder.new().build_terrain(map, world, terrain, Vector2i.ZERO, rng)
	assert_true(built.is_ok(), "a normalized land map builds Castle's 30 by 30 source window")
	if not built.is_ok():
		return
	assert_equal([built.battlefield.source_origin, built.battlefield.map_shift, built.battlefield.party_anchor], [Vector2i.ZERO, Vector2i(-45, -45), Vector2i.ZERO], "a corner battle preserves Castle's source clamp and negative map shift")
	assert_equal(built.battlefield.terrain_at(Vector2i.ZERO), 2, "battle terrain reads the live tile-replacement overlay")
	assert_equal(built.battlefield.terrain_at(Vector2i(3, 0)), 1, "a negative special-land replacement keeps the landlook base inside the next combat block")
	assert_equal(built.battlefield.terrain_at(Vector2i(9, 0)), 1, "an untouched negative special-land icon also becomes the active landlook base instead of leaking its absolute tile build into combat")
	var expanded_build: Array[int] = []
	for sub_y: int in 3:
		for sub_x: int in 3:
			expanded_build.append(built.battlefield.terrain_at(Vector2i(6 + sub_x, sub_y)))
	assert_equal(expanded_build, [31, 32, 33, 34, 35, 36, 37, 38, 39], "an asymmetric authored combat build preserves Castle's row and column order")
	assert_equal(rng.snapshot().draw_count, 0, "a non-rubble landlook with no forest consumes no decoration draws")
	var restored := BattlefieldState.from_data(JSON.parse_string(JSON.stringify(built.battlefield.to_data())))
	assert_not_null(restored, "the complete generated field is centrally serializable")
	if restored != null:
		assert_equal(restored.to_data(), built.battlefield.to_data(), "battlefield terrain, shifts, and placements round-trip exactly")
	var conflicting_data := built.battlefield.to_data()
	conflicting_data["characterPositions"] = {"shared.actor": [45, 45]}
	conflicting_data["monsterPositions"] = {"shared.actor": [50, 50]}
	conflicting_data["monsterSizes"] = {"shared.actor": 0}
	assert_equal(BattlefieldState.from_data(conflicting_data), null, "serialized battlefield rejects one actor identity crossing party and monster ownership")


func _test_dungeon_hole_normalization_and_rng() -> void:
	var cells: Array[MapCell] = []
	for y: int in 30:
		for x: int in 30:
			var features: Array[MapFeature] = []
			if x == 1 and y == 0:
				features.append(MapFeature.new("door", &"door", &"closed", &"horizontal"))
			elif x == 2 and y == 0:
				features.append(MapFeature.new("hole", &"no-wall-in-battle"))
			cells.append(_cell(Vector2i(x, y), 0, &"dungeon", "classic.dungeon.wall", features))
	var map := MapDefinition.new("dungeon.test", "Dungeon", &"dungeon", 0, MapTopology.new(30, 30, cells), false, false, -1, [], "terrain.dungeon")
	var terrain := _terrain_set("terrain.dungeon", -1, -1)
	var values: Array[int] = []
	values.resize(86 * 86)
	values.fill(32_767)
	var rng := ScriptedRng.new(values)
	var built := BattlefieldBuilder.new().build_terrain(map, WorldState.new(), terrain, Vector2i(15, 15), rng)
	assert_true(built.is_ok(), "dungeon packed semantics provide every fact required by combatmap")
	if not built.is_ok():
		return
	assert_equal([built.battlefield.terrain_at(Vector2i.ZERO), built.battlefield.terrain_at(Vector2i(3, 0)), built.battlefield.terrain_at(Vector2i(6, 0))], [234, 232, 232], "walls remain walls while doors and no-wall-in-battle cells become Castle floor blocks")
	assert_equal(rng.snapshot().draw_count, 86 * 86, "dungeon rubble consumes one chance draw for every interior field cell before testing solidity")


func _test_formation_and_footprints() -> void:
	var terrain := _terrain_set("terrain.flat", 1, 1)
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	var field := BattlefieldState.new("land.flat", tiles)
	var formation_rng := ScriptedRng.new([0, 0])
	var formation := BattlefieldBuilder.new().roll_formation(field, BattleDefinition.new("battle.formation", 1, [], 0), formation_rng)
	assert_equal([field.direction_degrees, field.rolled_distance, formation_rng.snapshot().draw_count], [1, 1, 2], "Castle Rand zero still consumes the distance draw and returns one")
	assert_equal(formation["monsterOrigin"], Vector2i(-4, -4), "direction and distance use Castle's degree conversion and C truncation")
	var builder := BattlefieldBuilder.new()
	assert_true(builder.place_character(field, terrain, "character.0", 0, formation), "the first party member receives a legal non-solid cell")
	assert_equal(field.character_position("character.0"), Vector2i(44, 44), "character search begins at Castle's negative-one offsets")
	field.remove_character("character.0")
	assert_true(builder.place_monster(field, terrain, "monster.large", Vector2i.ZERO, 3), "a two-by-two Classic monster footprint is placed around its lower-right anchor")
	assert_equal(BattlefieldState.footprint_cells(field.monster_position("monster.large"), 3), [Vector2i(44, 44), Vector2i(44, 43), Vector2i(43, 44), Vector2i(43, 43)], "size three uses Castle's first negative-offset anchor, top, left, and top-left cells")
	var blocked_tiles: Array[int] = []
	blocked_tiles.resize(BattlefieldState.CELL_COUNT)
	blocked_tiles.fill(2)
	var blocked := BattlefieldState.new("land.blocked", blocked_tiles)
	assert_equal(builder.find_monster_position(blocked, _terrain_set("terrain.blocked", 1, 1, {2: 2}), Vector2i.ZERO, 0), Vector2i(-1, -1), "an impossible placement fails explicitly instead of reproducing Castle's unbounded search")


func _test_battle_monster_construction_path() -> void:
	var saves: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8]
	var conditions := _ints(40)
	conditions[ConditionRules.REFLECTING_SPELLS] = -1
	var definition := MonsterDefinition.new("classic.monster.77", 77, "Battle Monster", 2, 1, 10, 10, 20, _ints(8), saves, _ints(6), _ints(3), [], [], [MonsterAttackDefinition.new(1, 1)], conditions)
	definition.spell_points = 10
	definition.random_weapon_table = 2
	definition.icon_id = 435
	var rng := ScriptedRng.new([0, 32_767, 0, 0, 0, 27_526])
	var monster := MonsterRules.new().build_battle_monster(definition, "monster.battle.1", false, 1, 1, rng)
	assert_not_null(monster, "authored battle monsters use their own combatsetup construction path")
	if monster == null:
		return
	assert_equal([monster.armor, monster.agility, monster.spell_points, monster.maximum_health, monster.magic_resistance], [6, 12, 12, 4, 23], "battle difficulty uses Castle's minus-three AC, forty-percent resources, and single resistance adjustment")
	assert_equal(monster.save_values(), [11, 12, 13, 14, 15, 16, 7, 8], "battle setup adds ten difficulty points only to Castle's first six monster saves")
	assert_equal(monster.conditions.value(ConditionRules.REFLECTING_SPELLS), -1, "battle construction copies every authored monster starting condition before play")
	assert_equal(monster.icon_id, 435, "battle construction preserves the authored Classic combat icon identity")
	assert_equal(monster.weapon_id, "classic.item.137", "authored battle table 2 gives overlapping roll 85 to its later row")
	assert_equal(rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["battle.monster.monster.battle.1.armor", "battle.monster.monster.battle.1.agility", "battle.monster.monster.battle.1.spell-points", "battle.monster.monster.battle.1.stamina.0", "battle.monster.monster.battle.1.stamina.1", "battle.monster.monster.battle.1.random-weapon"], "battle construction preserves AC, agility, spell points, health dice, and weapon draw order")


func _terrain_set(id: String, landlook: int, base_tile: int, solid_overrides: Dictionary = {}, build_overrides: Dictionary = {}) -> BattleTerrainSetDefinition:
	var tiles: Array[BattleTerrainTileDefinition] = []
	for tile: int in 401:
		var solid := int(solid_overrides.get(tile, 0))
		var build: Array = build_overrides.get(tile, [[tile, tile, tile], [tile, tile, tile], [tile, tile, tile]])
		tiles.append(BattleTerrainTileDefinition.new(tile, 0, 0, solid, false, 0, false, false, false, 0, build))
	return BattleTerrainSetDefinition.new(id, landlook, base_tile, tiles)


func _cell(coordinate: Vector2i, tile: int, level_type: StringName, terrain_id: String = "", features: Array[MapFeature] = []) -> MapCell:
	var terrain := terrain_id if not terrain_id.is_empty() else "classic.terrain.%d" % tile
	return MapCell.new("cell:%d,%d" % [coordinate.x, coordinate.y], coordinate, terrain, true, 1, false, level_type == &"land", false, false, false, false, false, 0, tile, "", [], [], {}, features)


func _ints(count: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(0)
	return result
