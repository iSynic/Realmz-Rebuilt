## Checks native icon inventory against detached map projection and exact media.
extends SceneTree

const PACKAGE_LOADER := preload("res://tools/performance_package_loader.gd")

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or FileAccess.file_exists(args[1]):
		printerr("Expected native inventory and fresh absolute output JSON paths.")
		quit(2)
		return
	var inventory: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not inventory is Dictionary or inventory.get("format") != "realmz.map-icon-inventory/1":
		quit(2)
		return
	var application := PACKAGE_LOADER.load_application()
	if not application.is_ok():
		printerr(application.error_message)
		quit(1)
		return
	_probe_boundaries(application)
	for row: Dictionary in inventory.packages:
		_probe_package(row, application)
	var output := {"format": "realmz.map-icon-projection/1", "inventorySha256": FileAccess.get_sha256(args[0]), "packages": _rows, "failures": _failures, "proofMode": "Validated package to detached cells and exact image lookup; direct projection, not ordinary gameplay"}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("MAP ICON PROJECTION: %d packages, %d failures" % [_rows.size(), _failures.size()])
	for failure: String in _failures.slice(0, 10): printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _probe_boundaries(application: PackageLoadResult) -> void:
	var rows := [[200, ""], [201, "realmz-land-cicn-201"], [1417, "realmz-land-cicn-417"], [4400, "realmz-land-cicn-1400"], [24993, "realmz-land-cicn-417"], [-18, "realmz-special-land-neg-18"], [-1018, "realmz-special-land-neg-18"], [-1000, "realmz-special-land-neg-0"], [-2000, "realmz-special-land-neg-0"], [-3001, "realmz-special-land-neg-1001"], [-3999, "realmz-special-land-neg-1999"], [-32768, "realmz-special-land-neg-30768"]]
	for row: Array in rows:
		if ClassicLandTileRules.special_overlay(row[0]) != row[1]:
			_failures.append("Signed/marker presentation mismatch for %d" % row[0])
	var zero := MediaAsset.new("fixture.zero", "Zero", "icon", "image/png", "cicn", 0, 1, "0".repeat(64), "missing.png", 32, 32, 0, 0, 0, 0, 0, 0, 0, -1, -1)
	var media := ClassicMediaCatalog.new(PackageMediaCatalog.new("", "", [zero]), ApplicationMediaCatalog.new(), application.media)
	if media.asset_by_id("realmz-special-land-neg-0") != zero:
		_failures.append("CICN zero is not an exact scenario resource lookup")


func _probe_package(row: Dictionary, application: PackageLoadResult) -> void:
	if FileAccess.get_sha256(row.path) != row.archiveSha256:
		_failures.append("Changed input archive: %s" % row.path)
		return
	var loaded := PACKAGE_LOADER.load_scenario(row.path, application)
	if not loaded.is_ok() or loaded.content.package_hash != row.packageHash:
		_failures.append("Package admission/identity: %s" % row.path)
		return
	var session := GameSession.new()
	if session.start(loaded.content, 1).state == SessionStep.State.FAILED:
		_failures.append("Session preparation: %s" % row.path)
		return
	var context := SessionWorkflowContext.new(loaded.content, session.snapshot().game_state, RealmzRules.new(), null, null, null)
	var media := ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new(), application.media)
	var missing: Array[Dictionary] = []
	for expected: Dictionary in row.cases:
		var map := loaded.content.world.map_by_id(expected.mapId)
		var cell := map.topology.cell_at(Vector2i(expected.x, expected.y))
		var projected := SessionMapViewBuilder.build_cell_view(context, map, cell, true)
		var alias := "realmz-special-land-neg-%d" % absi(expected.resourceId) if expected.raw < 0 else "realmz-land-cicn-%d" % expected.resourceId
		var exact := media.asset_by_resource("cicn", expected.resourceId)
		if not cell.native_tile_supplied or cell.native_tile_value != expected.raw or projected.overlay_asset_id != alias or media.asset_by_id(alias) != exact:
			_failures.append("%s %s %d,%d raw%d/%d alias%s/%s resource%s/%s" % [row.campaignId, map.id, expected.x, expected.y, expected.raw, cell.native_tile_value, projected.overlay_asset_id, alias, media.asset_by_id(alias).id if media.asset_by_id(alias) != null else "missing", exact.id if exact != null else "missing"])
		if exact == null:
			missing.append(expected)
		elif media.image_texture(exact) == null:
			_failures.append("Undecodable existing CICN %d in %s" % [expected.resourceId, row.campaignId])
		else:
			_probe_geometry(exact)
	_rows.append({"campaignId": row.campaignId, "packageHash": row.packageHash, "icons": row.cases.size(), "unavailableAuthoredResources": missing, "missingCompiledAliases": row.missingCompiledAliases})
	_probe_acquired_maps(context, row.cases)
	session.close()


func _probe_acquired_maps(context: SessionWorkflowContext, cases: Array) -> void:
	var by_cell: Dictionary = {}
	for expected: Dictionary in cases:
		by_cell["%s:%d,%d" % [expected.mapId, expected.x, expected.y]] = expected
	for definition: PlayerMapDefinition in context.content.world.player_maps():
		if definition.mode != PlayerMapDefinition.LAND_CROP:
			continue
		var view := SessionMapViewBuilder.build_player_map_view(context, definition)
		for cell: MapCellView in view.cells:
			var key := "%s:%d,%d" % [definition.map_id, cell.coordinate.x, cell.coordinate.y]
			if not by_cell.has(key):
				continue
			var resource: Variant = by_cell[key].playerMapResourceId
			var alias := "" if resource == null else "realmz-special-land-neg-%d" % absi(resource)
			if cell.overlay_asset_id != alias:
				_failures.append("Acquired map %s has wrong caller-specific icon at %s" % [definition.id, key])


func _probe_geometry(asset: MediaAsset) -> void:
	var extent := Vector2(64 if asset.resource_id > 200 and asset.width == 64 else 32, 64 if asset.resource_id > 200 and asset.height == 64 else 32)
	var expected := Rect2(Vector2(96, 96) - extent, extent)
	if MapTextureCache.land_overlay_rect(Rect2(64, 64, 32, 32), asset) != expected:
		_failures.append("Wrong lower-right anchored geometry for CICN %d" % asset.resource_id)
