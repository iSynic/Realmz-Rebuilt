class_name BattleTerrainTileDefinition
extends RefCounted

var tile: int
var sound: int
var movement_time: int
var solid: int
var shore: bool
var need_boat: int
var is_path: bool
var blocks_los: bool
var fly_float: bool
var forest: int
var _combat_build: Array = []
var _land_profile: LandTileProfile


func _init(tile_id: int, sound_id: int, time_cost: int, solid_class: int, is_shore: bool, boat_requirement: int, path: bool, los: bool, requires_fly_float: bool, forest_class: int, combat_build_rows: Array) -> void:
	tile = tile_id
	sound = sound_id
	movement_time = time_cost
	solid = solid_class
	shore = is_shore
	need_boat = boat_requirement
	is_path = path
	blocks_los = los
	fly_float = requires_fly_float
	forest = forest_class
	for row: Variant in combat_build_rows:
		_combat_build.append((row as Array).duplicate())


func combat_tile_at(row: int, column: int) -> int:
	if row < 0 or row >= _combat_build.size():
		return -1
	var values: Array = _combat_build[row]
	return -1 if column < 0 or column >= values.size() else int(values[column])


func combat_build() -> Array:
	return _combat_build.duplicate(true)


func land_profile() -> LandTileProfile:
	if _land_profile != null:
		return _land_profile
	if tile < 0 or tile > 200 or movement_time < 0 or need_boat < 0 or need_boat > 2:
		return null
	var flags := 4
	if solid == 0:
		flags |= 1
	if blocks_los:
		flags |= 2
	if need_boat == 2:
		flags |= 8
	if shore:
		flags |= 16
	if is_path:
		flags |= 32
	if need_boat != 0:
		flags |= 64
	if fly_float:
		flags |= 128
	if forest != 0:
		flags |= 256
	_land_profile = LandTileProfile.new(
		"classic.terrain.%d" % tile,
		movement_time,
		flags,
		sound,
		tile,
		need_boat,
		movement_time,
	)
	return _land_profile
