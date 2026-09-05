## Aggregates one battle map's identity, terrain, and actor placement state.

class_name BattlefieldState
extends RefCounted


var map_id: String
var source_origin: Vector2i
var map_shift: Vector2i
var party_anchor: Vector2i
var direction_degrees: int = 0
var rolled_distance: int = 0
var terrain: BattlefieldTerrainState
var actors: BattlefieldActorState


func _init(source_map_id: String, terrain_tiles: Array[int], origin: Vector2i = Vector2i.ZERO, shift: Vector2i = Vector2i.ZERO) -> void:
	map_id = source_map_id
	source_origin = origin
	map_shift = shift
	party_anchor = Vector2i(45, 45) + shift
	terrain = BattlefieldTerrainState.new(terrain_tiles)
	actors = BattlefieldActorState.new()
