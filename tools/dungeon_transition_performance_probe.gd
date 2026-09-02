extends SceneTree

const MapWindowViewScript := preload("res://src/core/view/map_window_view.gd")
const PresenterScript := preload("res://src/presentation/dungeon_map_3d_presenter.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var presenter := PresenterScript.new() as DungeonMap3DPresenter
	root.add_child(presenter)
	await process_frame
	presenter.set_enabled(true)
	var views: Array[GameView] = []
	var previous: GameView
	for x: int in range(20, 50):
		var next := _view_for(Vector2i(x, 35), 2, previous.map_view if previous != null else null)
		views.append(next)
		previous = next
	var turn_view := _view_for(Vector2i(35, 35), 1)
	var turn_view_right := _view_with_window(turn_view.map_view.map_window, Vector2i(35, 35), 2)
	var backtrack_a := _view_for(Vector2i(35, 35), 2)
	var backtrack_b := _view_for(Vector2i(36, 35), 2, backtrack_a.map_view)
	var backtrack_return := _view_with_window(backtrack_a.map_view.map_window, Vector2i(35, 35), 2, _delta(backtrack_b.map_view, backtrack_a.map_view))
	# Warm textures, shader compilation, and the retained viewport before measuring.
	presenter.present(views[0])
	await process_frame
	var cold: Array[int] = []
	for view: GameView in views.slice(1):
		cold.append(_measure_present(presenter, view))
	var turns: Array[int] = []
	for index: int in 40:
		turns.append(_measure_present(presenter, turn_view if index % 2 == 0 else turn_view_right))
	var backtracks: Array[int] = []
	for index: int in 40:
		backtracks.append(_measure_present(presenter, backtrack_b if index % 2 == 0 else backtrack_return))
	var unique_p95 := _percentile_ms(cold, 0.95)
	var turn_p95 := _percentile_ms(turns, 0.95)
	var backtrack_p95 := _percentile_ms(backtracks, 0.95)
	print(JSON.stringify({
		"coldUniqueP50Ms": _percentile_ms(cold, 0.50),
		"coldUniqueP95Ms": unique_p95,
		"turnP95Ms": turn_p95,
		"backtrackP95Ms": backtrack_p95,
		"geometryBuildCount": presenter.geometry_rebuild_count(),
		"geometryRetentionHitCount": presenter.geometry_cache_hit_count(),
		"samples": {"cold": cold.size(), "turn": turns.size(), "backtrack": backtracks.size()},
	}))
	presenter.queue_free()
	await process_frame
	if unique_p95 > 8.3 or turn_p95 > 1.0 or backtrack_p95 > 1.0:
		printerr("DUNGEON_TRANSITION_BUDGET_EXCEEDED uniqueP95=%.3f turnP95=%.3f backtrackP95=%.3f" % [unique_p95, turn_p95, backtrack_p95])
		quit(1)
		return
	quit()


func _measure_present(presenter: DungeonMap3DPresenter, view: GameView) -> int:
	var started := Time.get_ticks_usec()
	presenter.present(view)
	return Time.get_ticks_usec() - started


func _view_for(party: Vector2i, heading: int, previous: MapView = null) -> GameView:
	var cells: Array[MapCellView] = []
	var bounds := Rect2i(party - Vector2i(12, 12), Vector2i(25, 25))
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var coordinate := Vector2i(x, y)
			cells.append(_cell(coordinate))
	var window := MapWindowViewScript.new(bounds, {}, cells)
	return _view_with_window(window, party, heading, _delta(previous, null, party, bounds) if previous != null else null)


func _view_with_window(window: RefCounted, party: Vector2i, heading: int, delta: MapPresentationDelta = null) -> GameView:
	var map_view := MapView.new("dungeon:probe", "Dungeon Probe", &"dungeon", 90, 90, party, [], false, [], {}, Vector2i.ZERO, -1, heading, true, false, -1, false, true, -1, false, [], delta, window)
	var view := GameView.new(1, true, null, map_view.map_id, party, 1, 0, 0, map_view)
	view.party_map_id = map_view.map_id
	view.map_view = map_view
	return view


func _delta(previous: MapView, current: MapView = null, destination: Vector2i = Vector2i.ZERO, bounds: Rect2i = Rect2i()) -> MapPresentationDelta:
	var target := current.party_coordinate if current != null else destination
	var delta := MapPresentationDelta.new("dungeon:probe", previous.party_coordinate, target)
	var current_bounds: Rect2i = current.map_window.bounds if current != null else bounds
	var previous_bounds: Rect2i = previous.map_window.bounds
	for y: int in range(current_bounds.position.y, current_bounds.end.y):
		for x: int in range(current_bounds.position.x, current_bounds.end.x):
			var coordinate := Vector2i(x, y)
			if not previous_bounds.has_point(coordinate):
				delta.entered.append(coordinate)
	return delta


func _cell(coordinate: Vector2i) -> MapCellView:
	var edges := {&"north": &"open", &"east": &"open", &"south": &"open", &"west": &"open"}
	var passability := {&"north": true, &"east": true, &"south": true, &"west": true}
	var features: Array[StringName] = []
	if posmod(coordinate.x + coordinate.y, 17) == 0:
		features.append(&"column")
	return MapCellView.new(coordinate, "classic.terrain.probe", 1, "dungeon-top-down-302", true, false, true, true, false, false, features, {}, edges, passability)


func _percentile_ms(samples: Array[int], percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	var index := clampi(ceili(float(sorted.size()) * percentile) - 1, 0, sorted.size() - 1)
	return snappedf(float(sorted[index]) / 1000.0, 0.001)
