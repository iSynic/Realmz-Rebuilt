class_name ClassicMapPresenter
extends Control

@export var cell_size: float = 84.0
@export var map_origin: Vector2 = Vector2(24.0, 24.0)
@export var minimap_cell_size: float = 14.0
@export var show_debug_facts: bool = true

var _view: GameView


func present(game_view: GameView) -> void:
	_view = game_view
	visible = game_view != null and game_view.session_started and game_view.map_view != null
	queue_redraw()


func _draw() -> void:
	if _view == null or _view.map_view == null:
		return
	var map_view := _view.map_view
	var font := ThemeDB.fallback_font
	for cell: MapCellView in map_view.cells():
		var rect := Rect2(map_origin + Vector2(cell.coordinate) * cell_size, Vector2.ONE * cell_size)
		draw_rect(rect, _cell_color(cell, map_view.level_type), true)
		draw_rect(rect, Color(0.22, 0.25, 0.30), false, 1.0)
		_draw_edges(cell, rect)
		_draw_features(cell, rect)
		if cell.has_trigger:
			var center := rect.get_center()
			draw_colored_polygon(PackedVector2Array([center + Vector2(0, -8), center + Vector2(8, 0), center + Vector2(0, 8), center + Vector2(-8, 0)]), Color(0.95, 0.72, 0.26))
		if cell.in_random_region:
			draw_rect(rect.grow(-5.0), Color(0.48, 0.29, 0.58, 0.9), false, 2.0)
		if show_debug_facts:
			var facts := "%s%s%s" % ["M" if cell.passable else "X", "L" if cell.blocks_los else "", "R" if cell.in_random_region else ""]
			draw_string(font, rect.position + Vector2(7, 17), facts, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.78, 0.82, 0.88))
	var party_rect := Rect2(map_origin + Vector2(map_view.party_coordinate) * cell_size, Vector2.ONE * cell_size)
	draw_circle(party_rect.get_center(), 13.0, Color(0.92, 0.78, 0.34))
	draw_circle(party_rect.get_center(), 7.0, Color(0.17, 0.12, 0.06))
	draw_string(font, Vector2(map_origin.x, 16.0), "%s • %s" % [map_view.map_name, String(map_view.level_type)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.75, 0.42))
	_draw_minimap(map_view, font)


func _cell_color(cell: MapCellView, level_type: StringName) -> Color:
	if not cell.visible:
		return Color(0.025, 0.03, 0.04)
	if not cell.passable:
		return Color(0.16, 0.17, 0.20)
	if cell.terrain_id.ends_with(".2"):
		return Color(0.34, 0.50, 0.31)
	if level_type == &"dungeon":
		return Color(0.28, 0.27, 0.24)
	return Color(0.20, 0.38, 0.27)


func _draw_edges(cell: MapCellView, rect: Rect2) -> void:
	var edge_points := {
		&"north": [rect.position, rect.position + Vector2(rect.size.x, 0)],
		&"east": [rect.position + Vector2(rect.size.x, 0), rect.end],
		&"south": [rect.position + Vector2(0, rect.size.y), rect.end],
		&"west": [rect.position, rect.position + Vector2(0, rect.size.y)],
	}
	for direction: StringName in edge_points:
		var kind := cell.edge_kind(direction)
		if kind == &"open":
			continue
		var points: Array = edge_points[direction]
		var color := Color(0.84, 0.75, 0.52) if kind == &"door" else Color(0.64, 0.40, 0.72) if kind == &"secret" else Color(0.62, 0.65, 0.70)
		draw_line(points[0], points[1], color, 4.0 if cell.edge_is_passable(direction) else 7.0)


func _draw_features(cell: MapCellView, rect: Rect2) -> void:
	var center := rect.get_center()
	if cell.has_feature(&"door"):
		draw_line(center + Vector2(-13, 0), center + Vector2(13, 0), Color(0.84, 0.63, 0.30), 5.0)
	if cell.has_feature(&"secret"):
		draw_string(ThemeDB.fallback_font, center + Vector2(-5, 6), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.71, 0.46, 0.82))
	if cell.has_feature(&"stairs"):
		for offset: int in [-8, 0, 8]:
			draw_line(center + Vector2(-12, offset), center + Vector2(12, offset), Color(0.72, 0.72, 0.68), 2.0)
	if cell.has_feature(&"column"):
		draw_circle(center, 10.0, Color(0.64, 0.64, 0.62))


func _draw_minimap(map_view: MapView, font: Font) -> void:
	var origin := Vector2(map_origin.x + map_view.width * cell_size + 58.0, map_origin.y + 38.0)
	draw_string(font, origin - Vector2(0, 14), "Minimap", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.76, 0.82))
	for cell: MapCellView in map_view.cells():
		var rect := Rect2(origin + Vector2(cell.coordinate) * minimap_cell_size, Vector2.ONE * minimap_cell_size)
		var color := Color(0.28, 0.48, 0.32) if cell.visited else Color(0.09, 0.10, 0.12)
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0.20, 0.22, 0.25), false, 1.0)
	var party_center := origin + (Vector2(map_view.party_coordinate) + Vector2.ONE * 0.5) * minimap_cell_size
	draw_circle(party_center, 4.0, Color(0.94, 0.78, 0.28))
