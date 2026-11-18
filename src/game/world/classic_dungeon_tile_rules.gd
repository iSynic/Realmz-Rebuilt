## Builds the dungeon cell a replaced Classic tile value describes, as the package compiler builds authored cells.

class_name ClassicDungeonTileRules
extends RefCounted

const WALL := 0x0001
const HORIZONTAL_DOOR := 0x0002
const VERTICAL_DOOR := 0x0004
const STAIRS := 0x0008
const COLUMN := 0x0010
const NOTE := 0x0020
const REVEALED_SECRET := 0x0040
const UNMAPPED := 0x0080
const SECRET_PASSAGES: Dictionary[StringName, int] = {&"north": 0x0100, &"east": 0x0200, &"south": 0x0400, &"west": 0x0800}
const ACTION_POINT := 0x1000
const ARCHWAY := 0x2000
const NO_WALL_IN_BATTLE := 0x4000
const PLAIN_FEATURES: Dictionary[StringName, int] = {&"stairs": STAIRS, &"column": COLUMN, &"unmapped": UNMAPPED, &"note": NOTE, &"action-point": ACTION_POINT, &"archway": ARCHWAY, &"no-wall-in-battle": NO_WALL_IN_BATTLE}


## Returns the authored cell as it stands once Castle has written this value over its dungeon tile.
static func replaced_cell(cell: MapCell, raw_tile: int) -> MapCell:
	var wall := raw_tile & WALL != 0
	var door := raw_tile & (HORIZONTAL_DOOR | VERTICAL_DOOR) != 0
	var any_secret := raw_tile & 0x0F00 != 0
	var revealed := raw_tile & REVEALED_SECRET != 0
	var base_open := not wall or door or raw_tile & (ACTION_POINT | NOTE) != 0
	var replaced := MapCell.new(
		cell.id,
		cell.coordinate,
		"classic.dungeon.wall" if wall else "classic.dungeon.floor",
		base_open or any_secret,
		cell.movement_cost,
		wall and not door and (not any_secret or not revealed),
		false,
		false,
		false,
		false,
		false,
		false,
		cell.movement_sound_id,
		cell.render_tile,
		cell.tileset_id,
		cell.trigger_ids(),
		cell.random_rect_ids(),
		_edges(cell.id, raw_tile, base_open),
		_features(cell.id, raw_tile),
		cell.overlay_asset_id,
		cell.boat_requirement,
		cell.blocked_attempt_timeclicks,
		false,
	)
	replaced.native_tile_supplied = cell.native_tile_supplied
	replaced.native_tile_value = cell.native_tile_value
	return replaced


static func _edges(cell_id: String, raw_tile: int, base_open: bool) -> Dictionary:
	var door_id := "%s:door" % cell_id if raw_tile & (HORIZONTAL_DOOR | VERTICAL_DOOR) != 0 else ""
	var revealed := raw_tile & REVEALED_SECRET != 0
	var edges: Dictionary = {}
	for direction: StringName in SECRET_PASSAGES:
		var secret_passage := raw_tile & SECRET_PASSAGES[direction] != 0
		var passable := base_open or secret_passage
		var kind := &"wall"
		if secret_passage:
			kind = &"secret"
		elif not door_id.is_empty():
			kind = &"door"
		elif raw_tile & ARCHWAY != 0:
			kind = &"archway"
		elif passable:
			kind = &"open"
		var secret_id := "%s:secret:%s" % [cell_id, direction] if secret_passage else ""
		edges[direction] = MapEdge.new(kind, passable, not revealed if secret_passage else not passable, door_id, secret_id, not secret_passage or revealed)
	return edges


static func _features(cell_id: String, raw_tile: int) -> Array[MapFeature]:
	var features: Array[MapFeature] = []
	var revealed := raw_tile & REVEALED_SECRET != 0
	for direction: StringName in SECRET_PASSAGES:
		if raw_tile & SECRET_PASSAGES[direction] != 0:
			features.append(MapFeature.new("%s:secret:%s" % [cell_id, direction], &"secret", &"revealed" if revealed else &"hidden", direction))
	if raw_tile & (HORIZONTAL_DOOR | VERTICAL_DOOR) != 0:
		features.append(MapFeature.new("%s:door" % cell_id, &"door", &"closed", &"horizontal" if raw_tile & HORIZONTAL_DOOR != 0 else &"vertical"))
	for kind: StringName in PLAIN_FEATURES:
		if raw_tile & PLAIN_FEATURES[kind] != 0:
			features.append(MapFeature.new("%s:%s" % [cell_id, kind], kind))
	return features
