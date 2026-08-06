class_name GameState
extends RefCounted

var party: PartyState
var clock: RealmzClock
var _searched_cells: Dictionary = {}
var _world_overlays: Dictionary = {}


func _init(party_state: PartyState, realmz_clock: RealmzClock) -> void:
	party = party_state
	clock = realmz_clock


func mark_searched(map_id: String, coordinate: Vector2i) -> void:
	_searched_cells[_cell_key(map_id, coordinate)] = true


func was_searched(map_id: String, coordinate: Vector2i) -> bool:
	return _searched_cells.has(_cell_key(map_id, coordinate))


func to_data() -> Dictionary:
	var searched: Array[String] = []
	for key: Variant in _searched_cells.keys():
		searched.append(String(key))
	searched.sort()
	return {
		"party": party.to_data(),
		"clock": clock.to_data(),
		"searchedCells": searched,
		"worldOverlays": _world_overlays.duplicate(true),
	}


static func from_data(data: Variant) -> GameState:
	if not data is Dictionary:
		return null
	for field: String in ["party", "clock", "searchedCells", "worldOverlays"]:
		if not data.has(field):
			return null
	var party_state := PartyState.from_data(data["party"])
	var realmz_clock := RealmzClock.from_data(data["clock"])
	if party_state == null or realmz_clock == null or not data["searchedCells"] is Array or not data["worldOverlays"] is Dictionary:
		return null
	var state := GameState.new(party_state, realmz_clock)
	for key: Variant in data["searchedCells"]:
		if not key is String or key.is_empty():
			return null
		state._searched_cells[key] = true
	state._world_overlays = data["worldOverlays"].duplicate(true)
	return state


static func _cell_key(map_id: String, coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [map_id, coordinate.x, coordinate.y]
