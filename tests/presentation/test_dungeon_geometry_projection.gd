extends RealmzTestCase


func run() -> void:
	var map_presenter := ClassicMapPresenter.new()
	assert_equal(map_presenter.cell_size, 32.0, "Classic land atlases render at their native 32-pixel cell size")
	map_presenter._party_rect = Rect2(64, 64, 32, 32)
	map_presenter._minimap_rect = Rect2(400, 300, 90, 90)
	assert_equal(map_presenter._movement_direction_at(Vector2(130, 80)), Vector2i.RIGHT, "map clicks to the right of the party request eastward movement")
	assert_equal(map_presenter._movement_direction_at(Vector2(80, 20)), Vector2i.UP, "map clicks above the party request northward movement")
	assert_equal(map_presenter._movement_direction_at(Vector2(80, 80)), Vector2i.ZERO, "clicking the party marker does not move")
	assert_equal(ClassicMapPresenter.land_direction_at(Vector2(130, 20), map_presenter._party_rect), Vector2i(1, -1), "land clicks beyond both party-cell axes request northeast movement")
	assert_equal(ClassicMapPresenter.land_direction_at(Vector2(20, 130), map_presenter._party_rect), Vector2i(-1, 1), "land clicks beyond both party-cell axes request southwest movement")
	assert_equal(ClassicMapPresenter.land_direction_at(Vector2(80, 20), map_presenter._party_rect), Vector2i.UP, "land clicks aligned with the party column remain cardinal")
	map_presenter.free()

	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i(48, 15), Vector2i(90, 90), Vector2i(16, 13)), Vector2i(40, 9), "native Classic cells center the AOGM start within the bounded map viewport")
	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i.ZERO, Vector2i(90, 90), Vector2i(16, 13)), Vector2i.ZERO, "exploration camera clamps at the north-west map boundary")
	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i(89, 89), Vector2i(90, 90), Vector2i(16, 13)), Vector2i(74, 77), "exploration camera clamps at the south-east map boundary")
	var maximized_cells := ClassicMapPresenter.viewport_cells_for(Vector2(1780, 610), 24.0, 32.0)
	assert_equal(maximized_cells, Vector2i(25, 18), "maximized layouts cap the camera to the detached 25-cell map window")
	var maximized_origin := ClassicMapPresenter.map_draw_origin_for(Vector2(1780, 610), Vector2(0, 24), 32.0, maximized_cells)
	assert_equal(maximized_origin, Vector2(490, 29), "the capped map viewport is centered in the maximized stage")
	var first_coordinate := Vector2i(50, 15)
	var later_coordinate := Vector2i(72, 15)
	var first_camera := ClassicMapPresenter.camera_top_left(first_coordinate, Vector2i(90, 90), maximized_cells)
	var later_camera := ClassicMapPresenter.camera_top_left(later_coordinate, Vector2i(90, 90), maximized_cells)
	var first_party_rect := Rect2(maximized_origin + Vector2(first_coordinate - first_camera) * 32.0, Vector2.ONE * 32.0)
	var later_party_rect := Rect2(maximized_origin + Vector2(later_coordinate - later_camera) * 32.0, Vector2.ONE * 32.0)
	assert_equal(later_party_rect, first_party_rect, "overworld movement scrolls map contents without moving the maximized viewport")
	var cells: Array[MapCellView] = [
		_cell(Vector2i.ZERO, true, true, [&"stairs"], {&"north": &"wall", &"east": &"door", &"south": &"open", &"west": &"map-boundary"}, {&"north": false, &"east": true, &"south": true, &"west": false}),
		_cell(Vector2i.RIGHT, true, true, [&"column"], {&"north": &"secret", &"east": &"map-boundary", &"south": &"open", &"west": &"door"}, {&"north": false, &"east": false, &"south": true, &"west": true}),
		_cell(Vector2i.DOWN, true, false, [], {&"north": &"open", &"east": &"wall", &"south": &"wall", &"west": &"wall"}, {&"north": true, &"east": false, &"south": false, &"west": false}),
	]
	var dungeon_view := MapView.new("dungeon:test", "Projection Test", &"dungeon", 2, 2, Vector2i.ZERO, cells)
	var projection := DungeonGeometryProjection.from_map_view(dungeon_view)
	assert_not_null(projection, "dungeon MapView produces a disposable 3D projection")
	assert_equal(projection.map_id, dungeon_view.map_id, "projection retains only detached view identity")
	assert_equal(projection.cells().size(), 2, "only topology-visible cells become presentation geometry")
	assert_equal(projection.edges().size(), 8, "every visible directed topology edge is preserved for equivalence checks")
	for source: MapCellView in dungeon_view.cells():
		assert_equal(source.render_tile, 1, "detached presentation cells retain their immutable render tile")
		assert_equal(source.tileset_id, "dungeon-top-down-302", "detached presentation cells retain their immutable tileset identity")
		if not source.visible:
			assert_equal(projection.cell_at(source.coordinate), null, "hidden cells cannot leak into dungeon geometry")
			continue
		var projected_cell := projection.cell_at(source.coordinate)
		assert_not_null(projected_cell, "visible topology cell has one 3D projection cell")
		assert_equal(projected_cell.passable, source.passable, "2D and 3D consume the same cell passability fact")
		assert_equal(projected_cell.blocks_los, source.blocks_los, "2D and 3D consume the same LOS fact")
		assert_equal(projected_cell.features, source.features(), "2D and 3D consume the same feature facts")
		for direction: StringName in DungeonGeometryProjection.DIRECTIONS:
			var edge := projection.edge_at(source.coordinate, direction)
			assert_not_null(edge, "visible directed edge has one projection fact")
			assert_equal(edge.kind, source.edge_kind(direction), "3D edge kind equals the authoritative detached view")
			assert_equal(edge.passable, source.edge_is_passable(direction), "3D edge passability equals the authoritative detached view")
	var east := projection.edge_at(Vector2i.ZERO, &"east")
	var west := projection.edge_at(Vector2i.RIGHT, &"west")
	assert_equal(east.canonical_key, west.canonical_key, "opposite directed facts share one render-cache edge identity")
	var land_view := MapView.new("land:test", "Land", &"land", 1, 1, Vector2i.ZERO, [_cell(Vector2i.ZERO, true, true, [], {}, {})])
	assert_equal(DungeonGeometryProjection.from_map_view(land_view), null, "the optional 3D presenter cannot create a second land-map model")


func _cell(coordinate: Vector2i, passable: bool, visible: bool, features: Array[StringName], edge_kinds: Dictionary, edge_passability: Dictionary) -> MapCellView:
	return MapCellView.new(coordinate, "classic.terrain.test", 1, "dungeon-top-down-302", passable, false, visible, visible, false, false, features, {}, edge_kinds, edge_passability)
