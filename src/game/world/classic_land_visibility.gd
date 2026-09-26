## Computes Castle's bounded land discovery sweep from authoritative terrain.
class_name ClassicLandVisibility
extends RefCounted


static func visible_cells(topology: MapTopology, origin: Vector2i, world: WorldState) -> Array[Vector2i]:
	var window := MapTopology.classic_exploration_window(origin, Vector2i(topology.width, topology.height))
	var local_origin := origin - window.position
	var seen: Dictionary = {}
	# Castle cansee2 uses ten turning rays per side, each including six cells.
	for major_axis: int in 2:
		var minor_axis := 1 - major_axis
		for direction: int in [-1, 1]:
			for target: int in 10:
				var position := local_origin
				var minor_step := -1 if target < 5 else (1 if target > 5 else 0)
				for _sample: int in 6:
					if position[minor_axis] == target:
						minor_step = 0
					var coordinate := window.position + position
					var cell := topology.effective_cell_at(coordinate, world)
					if cell != null:
						seen[coordinate] = true
						if cell.blocks_los and position[major_axis] != local_origin[major_axis]:
							break
					position[minor_axis] += minor_step
					position[major_axis] += direction
	var result: Array[Vector2i] = []
	result.assign(seen.keys())
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	return result
