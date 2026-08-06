extends RealmzTestCase


func run() -> void:
	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i(48, 15), Vector2i(90, 90), Vector2i(11, 8)), Vector2i(43, 11), "exploration camera centers the AOGM start within the bounded map viewport")
	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i.ZERO, Vector2i(90, 90), Vector2i(11, 8)), Vector2i.ZERO, "exploration camera clamps at the north-west map boundary")
	assert_equal(ClassicMapPresenter.camera_top_left(Vector2i(89, 89), Vector2i(90, 90), Vector2i(11, 8)), Vector2i(79, 82), "exploration camera clamps at the south-east map boundary")
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
