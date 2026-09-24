## Detached, transient movement costs and predecessors from one battlefield query.
class_name BattlefieldReachability
extends RefCounted

var origin := Vector2i(-1, -1)
var costs: Dictionary[Vector2i, int] = {}
var predecessors: Dictionary[Vector2i, Vector2i] = {}


func route_to(destination: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if not costs.has(destination): return route
	var current := destination
	while current != origin:
		if not predecessors.has(current) or route.size() >= BattlefieldGrid.CELL_COUNT: return []
		route.append(current)
		current = predecessors[current]
	route.reverse()
	return route
