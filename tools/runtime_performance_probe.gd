extends SceneTree

const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")
const CharacterVaultControllerScript := preload("res://src/app/controllers/character_vault_controller.gd")
const ShellScene := preload("res://src/presentation/classic_application_shell.tscn")
const VAULT_PATH := "user://realmz2-tests/runtime-performance-vault"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or arguments.size() > 3:
		printerr("Usage: godot --path <project> --script res://tools/runtime_performance_probe.gd -- <package.realmz2> [seconds] [speed-percent]")
		call_deferred("_quit_cleanly", 2); return
	var duration_seconds := clampf(float(arguments[1]) if arguments.size() == 2 else 30.0, 1.0, 120.0)
	if arguments.size() == 3: duration_seconds = clampf(float(arguments[1]), 1.0, 120.0)
	var speed_percent := clampi(snappedi(int(arguments[2]) if arguments.size() == 3 else 400, 25), 25, 400)
	var package_started := Time.get_ticks_usec()
	var loaded := PackageRepositoryScript.new().load_package(arguments[0])
	var package_us := Time.get_ticks_usec() - package_started
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message]); call_deferred("_quit_cleanly", 1); return
	var session := GameSession.new()
	if session.start(loaded.content, 1).state == SessionStep.State.FAILED or not _assemble_party(session, loaded.content):
		printerr("SESSION_REJECTED"); call_deferred("_quit_cleanly", 1); return
	var state := session.snapshot().game_state; var map := loaded.content.world.map_by_id(state.party.map_id)
	var route := _noclip_route(map)
	if route.is_empty() or map.uses_los or not _place_party(session, loaded.content, route["coordinates"][0]):
		printerr("MOVEMENT_ROUTE_REJECTED"); call_deferred("_quit_cleanly", 1); return
	var vault_result := _measure_vault_import(loaded.content)
	var shell := ShellScene.instantiate() as ClassicApplicationShell
	var map_presenter := ClassicMapPresenter.new()
	root.size = Vector2i(1280, 720); root.add_child(shell); root.add_child(map_presenter)
	map_presenter.position = Vector2(2, 72); map_presenter.size = Vector2(926, 488)
	var media := ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new())
	map_presenter.set_media_catalog(media)
	await process_frame
	var view := session.view(); map_presenter.present(view); shell.present(view)
	await _after_draw()
	var benchmark_start := session.snapshot()
	var directions: Array[Vector2i] = route["directions"]
	for index: int in mini(16, directions.size()):
		var warm_step := session.apply_debug_command(SessionDebugCommand.noclip_step(directions[index])); view = session.view(warm_step.events); map_presenter.present(view); shell.present(view); await _after_draw()
	session.restore(loaded.content, benchmark_start); view = session.view(); map_presenter.present(view); shell.present(view); await _after_draw()
	var transaction_samples: Array[int] = []; var projection_samples: Array[int] = []; var shell_samples: Array[int] = []; var map_samples: Array[int] = []; var post_draw_samples: Array[int] = []; var frame_samples: Array[int] = []
	var measured_started := Time.get_ticks_usec(); var movement_count := 0; var route_index := 0; var skipped_intervals := 0
	var interval_us := int(50_000.0 * 100.0 / float(speed_percent)); var next_movement_at := measured_started
	var traversed: Dictionary = {view.party_coordinate: true}; var direction_counts: Dictionary = {}
	while Time.get_ticks_usec() - measured_started < int(duration_seconds * 1_000_000.0):
		var now := Time.get_ticks_usec()
		if now < next_movement_at:
			await _after_draw(); continue
		if now - next_movement_at >= interval_us:
			skipped_intervals += int((now - next_movement_at) / interval_us); next_movement_at = now
		var frame_started := Time.get_ticks_usec()
		var direction: Vector2i = directions[route_index % directions.size()]
		var step := session.apply_debug_command(SessionDebugCommand.noclip_step(direction)); var transaction_done := Time.get_ticks_usec()
		view = session.view(step.events); var projection_done := Time.get_ticks_usec()
		if step.state != SessionStep.State.COMPLETED or view.pending_interaction != null or view.map_view.presentation_delta == null:
			printerr("MOVEMENT_INTERRUPTED step=%d state=%d" % [movement_count, step.state]); shell.free(); map_presenter.free(); _remove_tree(ProjectSettings.globalize_path(VAULT_PATH)); call_deferred("_quit_cleanly", 1); return
		map_presenter.present(view); var map_done := Time.get_ticks_usec()
		shell.present(view); var shell_done := Time.get_ticks_usec()
		await _after_draw()
		var frame_done := Time.get_ticks_usec()
		transaction_samples.append(transaction_done - frame_started); projection_samples.append(projection_done - transaction_done); map_samples.append(map_done - projection_done); shell_samples.append(shell_done - map_done); post_draw_samples.append(frame_done - shell_done); frame_samples.append(frame_done - frame_started)
		movement_count += 1; route_index += 1; traversed[view.party_coordinate] = true
		var direction_name := String(MapTopology.direction_name(direction)); direction_counts[direction_name] = int(direction_counts.get(direction_name, 0)) + 1
		next_movement_at += interval_us
	var output := {
		"campaignId": loaded.content.campaign_id, "mapId": map.id, "mapName": map.name, "mapSize": [map.topology.width, map.topology.height], "mapCellCount": map.topology.cells().size(), "usesLos": map.uses_los,
		"presentationMode": "debug-noclip-long-route", "routeLengthTiles": directions.size(), "routeUniqueCells": route["uniqueCells"], "routeBounds": route["bounds"], "uniqueCellsTraversed": traversed.size(), "distanceTiles": movement_count, "directionCounts": direction_counts, "tilesets": _tileset_evidence(map, media), "overlayAssetCount": route["overlayAssetCount"],
		"viewport": "1280x720", "speedPercent": speed_percent, "scheduledStepsPerSecond": 20.0 * float(speed_percent) / 100.0, "actualStepsPerSecond": snappedf(float(movement_count) * 1_000_000.0 / float(Time.get_ticks_usec() - measured_started), 0.001), "durationSeconds": snappedf(float(Time.get_ticks_usec() - measured_started) / 1_000_000.0, 0.001), "movementFrames": movement_count, "queuedCatchUpBursts": 0, "skippedIntervals": skipped_intervals,
		"packagePreparationMs": snappedf(float(package_us) / 1000.0, 0.001), "vaultCachedImportP95Ms": vault_result["p95Ms"], "vaultCacheSize": vault_result["cacheSize"],
		"transactionP95Ms": _percentile_ms(transaction_samples, 0.95), "sessionProjectionP95Ms": _percentile_ms(projection_samples, 0.95), "mapPresentationP95Ms": _percentile_ms(map_samples, 0.95), "shellPresentationP95Ms": _percentile_ms(shell_samples, 0.95), "postDrawP95Ms": _percentile_ms(post_draw_samples, 0.95),
		"frameP95Ms": _percentile_ms(frame_samples, 0.95), "frameP99Ms": _percentile_ms(frame_samples, 0.99), "frameMaxMs": _maximum_ms(frame_samples), "framesAbove8_3Ms": _above_ms(frame_samples, 8.3), "framesAbove12_5Ms": _above_ms(frame_samples, 12.5), "framesAbove16_7Ms": _above_ms(frame_samples, 16.7), "framesAbove20Ms": _above_ms(frame_samples, 20.0), "framesAbove33_3Ms": _above_ms(frame_samples, 33.3),
	}
	print(CanonicalJson.encode(output))
	shell.free(); map_presenter.free(); _remove_tree(ProjectSettings.globalize_path(VAULT_PATH)); call_deferred("_quit_cleanly", 0)


func _measure_vault_import(content: RealmzContent) -> Dictionary:
	_remove_tree(ProjectSettings.globalize_path(VAULT_PATH))
	var repository := CharacterVaultRepositoryScript.new(VAULT_PATH)
	var race := content.race_definitions()[0]; var caste := content.caste_definitions()[0]
	var character := CharacterState.new("runtime-performance-character", "Performance", 20, 20); character.race_id = race.id; character.caste_id = caste.id
	var record := CharacterVaultRecord.new(character.id, content.rules_version, content.campaign_id, content.package_hash, character)
	if not repository.publish_revision(record): return {"p95Ms": -1.0, "cacheSize": 0}
	var controller := CharacterVaultControllerScript.new(repository); controller.revisions(content)
	var samples: Array[int] = []
	for ignored: int in 100:
		var started := Time.get_ticks_usec(); controller.import_intent(record.character_id, record.revision_hash); samples.append(Time.get_ticks_usec() - started)
	return {"p95Ms": _percentile_ms(samples, 0.95), "cacheSize": controller.cached_revision_count()}


func _assemble_party(session: GameSession, content: RealmzContent) -> bool:
	var races := content.race_definitions(); var castes := content.caste_definitions()
	if races.is_empty() or castes.is_empty(): return false
	var race := races[0]; var caste := castes[0]
	for candidate: CasteDefinition in castes:
		if race.eligible_caste_ids.is_empty() or race.eligible_caste_ids.has(candidate.id): caste = candidate; break
	for index: int in 6:
		var character := CharacterState.new("runtime-performance-%d" % index, "Probe %d" % index, 20, 20); character.race_id = race.id; character.caste_id = caste.id
		if session.submit_intent(PlayerIntent.import_vault_character(character.id, "%064d" % (index + 1), character, "runtime-performance", content.package_hash)).state == SessionStep.State.FAILED: return false
	var started := session.submit_intent(PlayerIntent.begin_adventure())
	while started.state == SessionStep.State.WAITING_FOR_INTERACTION and started.interaction != null and started.interaction.kind == InteractionRequest.ACKNOWLEDGE: started = session.respond(InteractionResponse.acknowledge(started.interaction))
	return started.state == SessionStep.State.COMPLETED


func _noclip_route(map: MapDefinition) -> Dictionary:
	if map == null or map.topology.width < 2 or map.topology.height < 2: return {}
	var coordinates: Array[Vector2i] = [Vector2i.ZERO]
	for target: Vector2i in [Vector2i(map.topology.width - 1, 0), Vector2i(0, map.topology.height - 1), Vector2i(map.topology.width - 1, map.topology.height - 1), Vector2i.ZERO]: _append_line(coordinates, target)
	for y: int in map.topology.height:
		_append_line(coordinates, Vector2i(map.topology.width - 1 if y % 2 == 0 else 0, y))
	var directions: Array[Vector2i] = []; var unique: Dictionary = {}; var overlay_assets: Dictionary = {}
	for index: int in coordinates.size():
		unique[coordinates[index]] = true
		if index > 0: directions.append(coordinates[index] - coordinates[index - 1])
		var cell := map.topology.cell_at(coordinates[index]);
		if cell != null and not cell.overlay_asset_id.is_empty(): overlay_assets[cell.overlay_asset_id] = true
	return {"coordinates": coordinates, "directions": directions, "uniqueCells": unique.size(), "bounds": [0, 0, map.topology.width - 1, map.topology.height - 1], "overlayAssetCount": overlay_assets.size()}


static func _append_line(coordinates: Array[Vector2i], target: Vector2i) -> void:
	var current := coordinates[-1]
	while current != target:
		current += Vector2i(signi(target.x - current.x), signi(target.y - current.y)); coordinates.append(current)


static func _tileset_evidence(map: MapDefinition, media: ClassicMediaCatalog) -> Array[Dictionary]:
	var ids: Dictionary = {}
	for cell: MapCell in map.topology.cells():
		if not cell.tileset_id.is_empty(): ids[cell.tileset_id] = true
	var result: Array[Dictionary] = []
	for id: String in ids:
		var asset := media.tileset_by_id(id)
		result.append({"id": id, "resolved": asset != null, "bytes": asset.byte_count if asset != null else 0, "width": asset.width if asset != null else 0, "height": asset.height if asset != null else 0, "tileWidth": asset.tile_width if asset != null else 0, "tileHeight": asset.tile_height if asset != null else 0})
	return result


func _place_party(session: GameSession, content: RealmzContent, coordinate: Vector2i) -> bool:
	var snapshot := session.snapshot(); snapshot.game_state.party.coordinate = coordinate; snapshot.game_state.world.mark_visited(snapshot.game_state.party.map_id, coordinate)
	return session.restore(content, snapshot).state == SessionStep.State.COMPLETED


static func _percentile_ms(samples: Array[int], percentile: float) -> float:
	if samples.is_empty(): return 0.0
	var ordered := samples.duplicate(); ordered.sort(); var index := clampi(ceili(float(ordered.size()) * percentile) - 1, 0, ordered.size() - 1)
	return snappedf(float(ordered[index]) / 1000.0, 0.001)


static func _maximum_ms(samples: Array[int]) -> float:
	return snappedf(float(samples.max() if not samples.is_empty() else 0) / 1000.0, 0.001)


static func _above_ms(samples: Array[int], threshold: float) -> int:
	return samples.filter(func(sample: int) -> bool: return float(sample) / 1000.0 > threshold).size()


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file_name: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories(): _remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _after_draw() -> void:
	if DisplayServer.get_name() == "headless": await process_frame
	else: await RenderingServer.frame_post_draw


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
