## Coordinates the session map view builder workflow against committed session state.

class_name SessionMapViewBuilder
extends RefCounted

const LOCATION_NOTE_VIEW_SIZE := Vector2i(15, 13)

static func build_map_view(context: SessionWorkflowContext, projection_size: Vector2i, prepared_map_id: String, prepared_coordinate: Vector2i, prepared_visible: Dictionary, window_cache: Dictionary, cell_cache: Dictionary, previous_map_view: MapView = null, presentation_delta: RefCounted = null) -> MapView:
	var state := context.state
	var party := state.party
	var topology := state.world.topology
	var exploration := state.world.exploration
	var map := context.content.world.map_by_id(party.map_id)
	_ensure_cell_cache(context, map, cell_cache)
	var wizard_eye := party.conditions.is_active(ConditionRules.PARTY_WIZARDS_EYE)
	var visible: Dictionary = {}
	if map.uses_los:
		if prepared_map_id == map.id and prepared_coordinate == party.coordinate:
			visible = prepared_visible
		else:
			for coordinate: Vector2i in map.topology.exploration_visible_cells(party.coordinate, state.world, true, wizard_eye):
				visible[coordinate] = true
	var width := mini(map.topology.width, projection_size.x)
	var height := mini(map.topology.height, projection_size.y)
	var bounds := Rect2i(clampi(party.coordinate.x - width / 2, 0, map.topology.width - width), clampi(party.coordinate.y - height / 2, 0, map.topology.height - height), width, height)
	var cache_key := "%s:%d:%d:%d,%d:%d,%d,%d,%d:%d" % [map.id, topology.revision(), exploration.revision(), party.coordinate.x, party.coordinate.y, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y, int(wizard_eye)]
	var window := window_cache.get(cache_key) as MapWindowView
	if window == null:
		if previous_map_view != null and previous_map_view.map_window != null and presentation_delta != null:
			window = _patch_map_window(context, map, bounds, visible, cell_cache, previous_map_view, presentation_delta)
		else:
			window = MapWindowView.new(bounds, {}, _complete_window_cells(context, map, bounds, visible, cell_cache))
			if presentation_delta != null:
				presentation_delta.complete_window_rebuild = true
		if window_cache.size() >= 32:
			window_cache.clear()
		window_cache[cache_key] = window
	var movement_options: Dictionary = {}
	var directions := MapTopology.land_directions() if map.level_type == &"land" else MapTopology.cardinal_directions()
	for direction: Vector2i in directions:
		var probe := context.content.world.probe_movement(map.id, party.coordinate, direction, state.world, state.party_in_boat)
		movement_options[MapTopology.direction_name(direction)] = {"allowed": probe.allowed, "reason": String(probe.reason)}
	var dark := topology.map_is_dark(map)
	var darkness_level := SessionViewProjectionPolicy.classic_darkness_level(party.conditions.value(ConditionRules.PARTY_TORCH_LIT)) if dark else -1
	var visited: Array[Vector2i] = []
	var seen: Array[Vector2i] = []
	if presentation_delta == null:
		visited = exploration.visited_coordinates(map.id)
		seen = exploration.seen_coordinates(map.id)
	var legacy_cells: Array[MapCellView] = []
	var result := MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, party.coordinate, legacy_cells, dark, visited, movement_options, state.last_move_direction, topology.map_landlook(map), state.dungeon_heading, state.dungeon_multiview, wizard_eye, map.base_scale, state.xy_display_hidden, state.compass_enabled, darkness_level, map.uses_los, seen, presentation_delta, window, _effective_random_region_bounds(context, map))
	result.inherit_visibility(previous_map_view)
	return result


static func _patch_map_window(context: SessionWorkflowContext, map: MapDefinition, bounds: Rect2i, visible: Dictionary, cell_cache: Dictionary, previous_map_view: MapView, presentation_delta: RefCounted) -> MapWindowView:
	var exploration := context.state.world.exploration
	var previous_bounds: Rect2i = previous_map_view.map_window.bounds
	presentation_delta.entered = _entered_coordinates(previous_bounds, bounds)
	presentation_delta.exited = _entered_coordinates(bounds, previous_bounds)
	var changed_membership: Dictionary = {}
	for coordinate: Vector2i in presentation_delta.entered + presentation_delta.changed:
		if bounds.has_point(coordinate):
			changed_membership[coordinate] = true
	var replacements: Dictionary = {}
	for coordinate: Vector2i in changed_membership:
		var cell := map.topology.cell_at(coordinate)
		if cell == null:
			continue
		var reusable := previous_map_view.map_window.retained_cell_at(coordinate) as MapCellView
		var is_visible := not map.uses_los or visible.has(coordinate)
		var was_visited := exploration.was_visited(map.id, coordinate)
		if reusable != null and cell.is_path and reusable.visited != was_visited:
			reusable = null
		replacements[coordinate] = reusable.detached_with_visibility(is_visible, was_visited) if reusable != null else _cached_cell_view(context, map, cell, is_visible, cell_cache)
	return previous_map_view.map_window.patched(bounds, replacements)


static func _complete_window_cells(context: SessionWorkflowContext, map: MapDefinition, bounds: Rect2i, visible: Dictionary, cell_cache: Dictionary) -> Array[MapCellView]:
	var cells: Array[MapCellView] = []
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var cell := map.topology.cell_at(Vector2i(x, y))
			if cell != null:
				cells.append(_cached_cell_view(context, map, cell, not map.uses_los or visible.has(cell.coordinate), cell_cache))
	return cells
static func _effective_random_region_bounds(context: SessionWorkflowContext, map: MapDefinition) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for region: RandomEncounterRegion in map.random_regions():
		var effective := context.state.world.triggers.random_region(region)
		if effective.bounds_overridden:
			var edges := effective.bounds_edges()
			result.append(Rect2i(edges[0], edges[2], edges[1] - edges[0] + 1, edges[3] - edges[2] + 1))
		else:
			result.append(region.bounds)
	return result


static func build_player_map_view(context: SessionWorkflowContext, definition: PlayerMapDefinition) -> PlayerMapView:
	var cells: Array[MapCellView] = []
	var source_map: MapDefinition = context.content.world.map_by_id(definition.map_id) if not definition.map_id.is_empty() else null
	if definition.mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP] and source_map != null:
		var cell_size := 16 if definition.mode == PlayerMapDefinition.DUNGEON_CROP else definition.icon_size
		var tile_count := ceili(320.0 / float(cell_size))
		for y: int in range(definition.start.y, definition.start.y + tile_count):
			for x: int in range(definition.start.x, definition.start.x + tile_count):
				var cell := source_map.topology.cell_at(Vector2i(x, y))
				if cell != null:
					cells.append(build_cell_view(context, source_map, cell, true))
	return PlayerMapView.new(definition, cells, player_map_shows_party(definition, source_map, context.state.party.map_id, context.state.party.coordinate), context.state.party.coordinate, true)


static func build_location_note_map_view(context: SessionWorkflowContext, map: MapDefinition, note: LocationNoteState) -> MapView:
	var view_size := Vector2i(mini(LOCATION_NOTE_VIEW_SIZE.x, map.topology.width), mini(LOCATION_NOTE_VIEW_SIZE.y, map.topology.height))
	var maximum := Vector2i(map.topology.width, map.topology.height) - view_size
	var origin := Vector2i(clampi(note.coordinate.x - 8, 0, maximum.x), clampi(note.coordinate.y - 6, 0, maximum.y))
	var cells: Array[MapCellView] = []
	for y: int in range(origin.y, origin.y + view_size.y):
		for x: int in range(origin.x, origin.x + view_size.x):
			var cell := map.topology.cell_at(Vector2i(x, y))
			if cell != null:
				cells.append(build_cell_view(context, map, cell, true))
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, note.coordinate, cells, note.darkness_value > 0, [note.coordinate], {}, Vector2i.ZERO, context.state.world.topology.map_landlook(map), 1, true, false, map.base_scale, false, true, clampi(note.darkness_value, 0, 6))


static func player_map_shows_party(definition: PlayerMapDefinition, source_map: MapDefinition, party_map_id: String, party_coordinate: Vector2i) -> bool:
	if source_map == null or source_map.id != party_map_id or definition.mode == PlayerMapDefinition.SCROLLING_TEXT:
		return false
	var visible_tiles := 320 / definition.icon_size
	return Rect2i(definition.start - Vector2i.ONE, Vector2i(visible_tiles + 1, visible_tiles + 1)).has_point(party_coordinate)


static func build_cell_view(context: SessionWorkflowContext, map: MapDefinition, cell: MapCell, is_visible: bool) -> MapCellView:
	cell = map.topology.effective_cell_at(cell.coordinate, context.state.world)
	var feature_kinds: Array[StringName] = []
	var feature_orientations: Dictionary = {}
	var edge_kinds: Dictionary = {}
	var edge_passability: Dictionary = {}
	for direction: StringName in [&"north", &"east", &"south", &"west"]:
		var edge := cell.edge(direction)
		var concealed_secret := not edge.secret_id.is_empty() and not context.state.world.topology.secret_is_discovered(edge.secret_id, edge.initially_discovered)
		edge_kinds[direction] = &"wall" if concealed_secret else edge.kind
		edge_passability[direction] = false if concealed_secret else edge.passable
	for feature: MapFeature in cell.features():
		if feature.kind == &"secret" and not context.state.world.topology.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			continue
		if not feature_kinds.has(feature.kind):
			feature_kinds.append(feature.kind)
			feature_orientations[feature.kind] = feature.orientation
	if cell.is_path and context.state.world.exploration.was_visited(map.id, cell.coordinate):
		feature_kinds.append(&"discovered_path")
	var effective_landlook := context.state.world.topology.map_landlook(map)
	var tileset_id := "landlook-%d" % effective_landlook if map.level_type == &"land" and effective_landlook >= 0 else cell.tileset_id
	var render_tile := cell.render_tile
	var overlay_asset_id := cell.overlay_asset_id
	if map.level_type == &"land" and context.state.world.topology.has_terrain_override(map.id, cell.coordinate):
		var raw_tile := context.state.world.topology.classic_tile_for(map.id, cell)
		overlay_asset_id = ClassicLandTileRules.special_overlay(raw_tile)
		if not overlay_asset_id.is_empty():
			var terrain_set := context.content.world.battle_terrain_set_for_map(map, context.state.world)
			render_tile = cell.render_tile if terrain_set == null else terrain_set.base_tile
		else:
			render_tile = ClassicLandTileRules.normalized_tile(raw_tile)
	return MapCellView.new(cell.coordinate, context.state.world.topology.terrain_for(map.id, cell), render_tile, tileset_id, cell.passable, cell.blocks_los, is_visible, context.state.world.exploration.was_visited(map.id, cell.coordinate), not cell.trigger_ids().is_empty(), context.state.world.triggers.has_random_region_at(map, cell.coordinate), feature_kinds, feature_orientations, edge_kinds, edge_passability, overlay_asset_id)


static func _ensure_cell_cache(context: SessionWorkflowContext, map: MapDefinition, cell_cache: Dictionary) -> void:
	var signature := "%s:%d:%d:%d" % [map.id, context.state.world.topology.revision(), context.state.world.triggers.random_region_bounds_revision(), context.state.world.topology.map_landlook(map)]
	if String(cell_cache.get(&"signature", "")) == signature:
		return
	cell_cache.clear()
	cell_cache[&"signature"] = signature
	for cell: MapCell in map.topology.cells():
		cell_cache[cell.coordinate] = build_cell_view(context, map, cell, true)


static func _cached_cell_view(context: SessionWorkflowContext, map: MapDefinition, cell: MapCell, is_visible: bool, cell_cache: Dictionary) -> MapCellView:
	var was_visited := context.state.world.exploration.was_visited(map.id, cell.coordinate)
	var cached := cell_cache.get(cell.coordinate) as MapCellView
	if cached == null or cell.is_path and cached.visited != was_visited:
		cached = build_cell_view(context, map, cell, is_visible)
		cell_cache[cell.coordinate] = cached
	if cached.visible == is_visible and cached.visited == was_visited:
		return cached
	return cached.detached_with_visibility(is_visible, was_visited)


static func _entered_coordinates(previous: Rect2i, current: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var membership: Dictionary = {}
	if current.position.x < previous.position.x:
		_append_coordinates(result, membership, Rect2i(current.position.x, current.position.y, previous.position.x - current.position.x, current.size.y))
	elif current.end.x > previous.end.x:
		_append_coordinates(result, membership, Rect2i(previous.end.x, current.position.y, current.end.x - previous.end.x, current.size.y))
	if current.position.y < previous.position.y:
		_append_coordinates(result, membership, Rect2i(current.position.x, current.position.y, current.size.x, previous.position.y - current.position.y))
	elif current.end.y > previous.end.y:
		_append_coordinates(result, membership, Rect2i(current.position.x, previous.end.y, current.size.x, current.end.y - previous.end.y))
	return result


static func _append_coordinates(result: Array[Vector2i], membership: Dictionary, rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var coordinate := Vector2i(x, y)
			if not membership.has(coordinate):
				membership[coordinate] = true
				result.append(coordinate)
