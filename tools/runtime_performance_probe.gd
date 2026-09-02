extends SceneTree

const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")
const CharacterVaultControllerScript := preload("res://src/app/controllers/character_vault_controller.gd")
const ShellScene := preload("res://src/presentation/classic_application_shell.tscn")
const VAULT_PATH := "user://realmz2-tests/runtime-performance-vault"


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or arguments.size() > 5:
		printerr("Usage: godot --path <project> --script res://tools/runtime_performance_probe.gd -- <package.realmz2> [seconds] [speed-percent] [map-id] [1280x720|native]")
		call_deferred("_quit_cleanly", 2); return
	var duration_seconds := clampf(float(arguments[1]) if arguments.size() >= 2 else 30.0, 0.25, 120.0)
	var speed_percent := clampi(snappedi(int(arguments[2]) if arguments.size() >= 3 else 400, 25), 25, 400)
	var requested_map_id := ""
	if arguments.size() >= 4:
		requested_map_id = String(arguments[3])
	var viewport_name := String(arguments[4]).to_lower() if arguments.size() == 5 else "1280x720"
	var viewport_size := DisplayServer.screen_get_size() if viewport_name == "native" else Vector2i(1280, 720)
	if viewport_size.x < 800 or viewport_size.y < 600:
		viewport_size = Vector2i(1280, 720)
	var package_started := Time.get_ticks_usec()
	var loaded := PackageRepositoryScript.new().load_package(arguments[0])
	var package_us := Time.get_ticks_usec() - package_started
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message]); call_deferred("_quit_cleanly", 1); return
	var session := GameSession.new()
	if session.start(loaded.content, 1).state == SessionStep.State.FAILED or not _assemble_party(session, loaded.content):
		printerr("SESSION_REJECTED"); call_deferred("_quit_cleanly", 1); return
	var state := session.snapshot().game_state; var map := loaded.content.world.map_by_id(requested_map_id if not requested_map_id.is_empty() else state.party.map_id)
	var route := _ordinary_route_pair(loaded.content, state, map)
	if route.is_empty() or not _place_party(session, loaded.content, map.id, route["coordinates"][0], 4096):
		printerr("MOVEMENT_ROUTE_REJECTED"); call_deferred("_quit_cleanly", 1); return
	var vault_result := _measure_vault_import(loaded.content)
	var shell := ShellScene.instantiate() as ClassicApplicationShell
	var map_presenter := ClassicMapPresenter.new()
	root.size = viewport_size; root.add_child(shell); root.add_child(map_presenter)
	var viewport_scale := Vector2(viewport_size) / Vector2(1280, 720)
	map_presenter.position = Vector2(2, 72) * viewport_scale; map_presenter.size = Vector2(926, 488) * viewport_scale
	session.set_map_projection_size(ClassicMapPresenter.projection_cells_for(map_presenter.size, map_presenter.map_origin.y, map_presenter.cell_size))
	var media := ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new())
	map_presenter.set_media_catalog(media)
	await process_frame
	var view := session.view(); map_presenter.present(view); shell.present(view)
	await _after_draw()
	var benchmark_start := session.snapshot()
	var directions: Array[Vector2i] = route["directions"]
	# Warm enough rendered movement frames to compile drivers, allocate retained
	# layer pages, and exercise several hourly status/magic refresh boundaries.
	for index: int in 80:
		var warm_step := session.submit_intent(PlayerIntent.move(directions[index % directions.size()])); view = session.view(warm_step.events); map_presenter.present(view); shell.present(view); await _after_draw()
	session.restore(loaded.content, benchmark_start); view = session.view(); map_presenter.present(view); shell.present(view); await _after_draw()
	var transaction_samples: Array[int] = []; var projection_samples: Array[int] = []; var shell_samples: Array[int] = []; var map_samples: Array[int] = []; var post_draw_samples: Array[int] = []; var frame_samples: Array[int] = []
	var ordinary_frames: Array[int] = []; var hourly_frames: Array[int] = []; var ordinary_domains: Dictionary = {}; var hourly_domains: Dictionary = {}
	var ordinary_combined: Array[int] = []; var hourly_combined: Array[int] = []
	var ordinary_map: Array[int] = []; var hourly_map: Array[int] = []; var ordinary_shell: Array[int] = []; var hourly_shell: Array[int] = []; var ordinary_post_draw: Array[int] = []; var hourly_post_draw: Array[int] = []
	var measured_started := Time.get_ticks_usec(); var movement_count := 0; var route_index := 0; var skipped_intervals := 0
	var segment_restarts := 0
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
		var step := session.submit_intent(PlayerIntent.move(direction)); var transaction_done := Time.get_ticks_usec()
		view = session.view(step.events); var projection_done := Time.get_ticks_usec()
		if step.state != SessionStep.State.COMPLETED or view.pending_interaction != null or view.map_view.presentation_delta == null:
			if step.state == SessionStep.State.FAILED or session.restore(loaded.content, benchmark_start).state == SessionStep.State.FAILED:
				printerr("MOVEMENT_INTERRUPTED step=%d state=%d events=%s" % [movement_count, step.state, step.events.map(func(event: DomainEvent) -> String: return String(event.kind))]); shell.free(); map_presenter.free(); _remove_tree(ProjectSettings.globalize_path(VAULT_PATH)); call_deferred("_quit_cleanly", 1); return
			segment_restarts += 1; route_index = 0; view = session.view(); map_presenter.present(view); shell.present(view); await _after_draw(); next_movement_at = Time.get_ticks_usec(); continue
		map_presenter.present(view); var map_done := Time.get_ticks_usec()
		shell.present(view); var shell_done := Time.get_ticks_usec()
		await _after_draw()
		var frame_done := Time.get_ticks_usec()
		transaction_samples.append(transaction_done - frame_started); projection_samples.append(projection_done - transaction_done); map_samples.append(map_done - projection_done); shell_samples.append(shell_done - map_done); post_draw_samples.append(frame_done - shell_done); frame_samples.append(frame_done - frame_started)
		var hourly := step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"fatigue_changed" and String(event.payload.get("reason", "")) == "hour-boundary")
		(hourly_frames if hourly else ordinary_frames).append(frame_done - frame_started)
		(hourly_combined if hourly else ordinary_combined).append(projection_done - frame_started)
		(hourly_map if hourly else ordinary_map).append(map_done - projection_done)
		(hourly_shell if hourly else ordinary_shell).append(shell_done - map_done)
		(hourly_post_draw if hourly else ordinary_post_draw).append(frame_done - shell_done)
		_append_domain_timings(hourly_domains if hourly else ordinary_domains, view.projection_timings_usec)
		movement_count += 1; route_index += 1; traversed[view.party_coordinate] = true
		var direction_name := String(MapTopology.direction_name(direction)); direction_counts[direction_name] = int(direction_counts.get(direction_name, 0)) + 1
		next_movement_at += interval_us
	var output := {
		"campaignId": loaded.content.campaign_id, "mapId": map.id, "mapName": map.name, "mapSize": [map.topology.width, map.topology.height], "mapCellCount": map.topology.cells().size(), "usesLos": map.uses_los, "renderingMethod": RenderingServer.get_current_rendering_method(), "renderingDriver": RenderingServer.get_current_rendering_driver_name(),
		"presentationMode": "ordinary-rules-movement", "vsyncDuringMeasurement": "disabled", "drawCompletion": "process-frame-plus-forced-render-without-buffer-swap", "mapProjectionMode": "los-visibility-delta" if map.uses_los else "incremental", "projectionGuardCellsPerEdge": ClassicMapPresenter.RETAINED_PROJECTION_MARGIN_CELLS.x, "routeLengthTiles": directions.size(), "routeUniqueCells": route["uniqueCells"], "routeBounds": route["bounds"], "uniqueCellsTraversed": traversed.size(), "distanceTiles": movement_count, "directionCounts": direction_counts, "tilesets": _tileset_evidence(map, media), "overlayAssetCount": route["overlayAssetCount"], "randomEncounterChanceDuringMeasurement": 0,
		"viewport": "%dx%d" % [viewport_size.x, viewport_size.y], "speedPercent": speed_percent, "scheduledStepsPerSecond": 20.0 * float(speed_percent) / 100.0, "actualStepsPerSecond": snappedf(float(movement_count) * 1_000_000.0 / float(Time.get_ticks_usec() - measured_started), 0.001), "durationSeconds": snappedf(float(Time.get_ticks_usec() - measured_started) / 1_000_000.0, 0.001), "movementFrames": movement_count, "ordinarySamples": ordinary_frames.size(), "hourlySamples": hourly_frames.size(), "segmentRestartsAtGameplayBoundaries": segment_restarts, "queuedCatchUpBursts": 0, "skippedIntervals": skipped_intervals,
		"packagePreparationMs": snappedf(float(package_us) / 1000.0, 0.001), "vaultCachedImportP95Ms": vault_result["p95Ms"], "vaultCacheSize": vault_result["cacheSize"],
		"transactionP95Ms": _percentile_ms(transaction_samples, 0.95), "sessionProjectionP95Ms": _percentile_ms(projection_samples, 0.95), "mapPresentationP95Ms": _percentile_ms(map_samples, 0.95), "shellPresentationP95Ms": _percentile_ms(shell_samples, 0.95), "postDrawP95Ms": _percentile_ms(post_draw_samples, 0.95),
		"frameP95Ms": _percentile_ms(frame_samples, 0.95), "frameP99Ms": _percentile_ms(frame_samples, 0.99), "frameMaxMs": _maximum_ms(frame_samples), "framesAbove8_3Ms": _above_ms(frame_samples, 8.3), "framesAbove12_5Ms": _above_ms(frame_samples, 12.5), "framesAbove16_7Ms": _above_ms(frame_samples, 16.7), "framesAbove20Ms": _above_ms(frame_samples, 20.0), "framesAbove33_3Ms": _above_ms(frame_samples, 33.3),
		"transactionPlusProjectionP95Ms": _combined_percentile_ms(transaction_samples, projection_samples, 0.95), "ordinaryTransactionPlusProjectionP95Ms": _percentile_ms(ordinary_combined, 0.95), "hourlyTransactionPlusProjectionP95Ms": _percentile_ms(hourly_combined, 0.95),
		"ordinaryFrameP95Ms": _percentile_ms(ordinary_frames, 0.95), "hourlyFrameP95Ms": _percentile_ms(hourly_frames, 0.95), "ordinaryRetainedMapP95Ms": _percentile_ms(ordinary_map, 0.95), "hourlyRetainedMapP95Ms": _percentile_ms(hourly_map, 0.95), "ordinaryShellP95Ms": _percentile_ms(ordinary_shell, 0.95), "hourlyShellP95Ms": _percentile_ms(hourly_shell, 0.95), "ordinaryPostDrawP95Ms": _percentile_ms(ordinary_post_draw, 0.95), "hourlyPostDrawP95Ms": _percentile_ms(hourly_post_draw, 0.95), "ordinaryProjectionDomainsP95Ms": _domain_p95_milliseconds(ordinary_domains), "hourlyProjectionDomainsP95Ms": _domain_p95_milliseconds(hourly_domains),
	}
	print(CanonicalJson.encode(output))
	var failed := float(output["transactionPlusProjectionP95Ms"]) > 3.0 or float(output["frameP95Ms"]) > 8.3 or float(output["frameP99Ms"]) > 12.5 or float(output["frameMaxMs"]) > 16.7 or skipped_intervals != 0
	if not ordinary_combined.is_empty(): failed = failed or float(output["ordinaryTransactionPlusProjectionP95Ms"]) > 3.0 or float(output["ordinaryFrameP95Ms"]) > 8.3
	if hourly_combined.size() >= 5: failed = failed or float(output["hourlyTransactionPlusProjectionP95Ms"]) > 3.0 or float(output["hourlyFrameP95Ms"]) > 8.3
	if failed: printerr("RUNTIME_MOVEMENT_BUDGET_EXCEEDED")
	shell.free(); map_presenter.free(); _remove_tree(ProjectSettings.globalize_path(VAULT_PATH)); call_deferred("_quit_cleanly", 1 if failed else 0)


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
	var race: RaceDefinition; var caste: CasteDefinition; var caster_type := 0
	for race_candidate: RaceDefinition in races:
		for caste_candidate: CasteDefinition in castes:
			if not race_candidate.eligible_caste_ids.is_empty() and not race_candidate.eligible_caste_ids.has(caste_candidate.id): continue
			var rows := caste_candidate.spellcaster_rows()
			for row_index: int in mini(3, rows.size()):
				if rows[row_index].y > 0:
					race = race_candidate; caste = caste_candidate; caster_type = row_index + 1; break
			if caste != null: break
		if caste != null: break
	if race == null or caste == null: return false
	var known_spells: Array[String] = []
	for spell: SpellDefinition in content.spell_definitions():
		if int(spell.classic_id / 1000) == caster_type and spell.classic_tier() >= 0:
			known_spells.append(spell.id)
			if known_spells.size() >= 4: break
	for index: int in 6:
		var character := CharacterState.new("runtime-performance-%d" % index, "Probe %d" % index, 20, 20); character.race_id = race.id; character.caste_id = caste.id; character.level = 10; character.spellcaster_type = caster_type; character.maximum_spell_points = 100; character.spell_points = 0; character.set_known_spells(known_spells)
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


func _ordinary_route_pair(content: RealmzContent, state: GameState, map: MapDefinition) -> Dictionary:
	if map == null:
		return {}
	var seed := Vector2i(-1, -1)
	for cell: MapCell in map.topology.cells():
		if _safe_route_coordinate(state, map, cell):
			seed = cell.coordinate
			break
	if seed.x < 0:
		return {}
	var first_search := _ordinary_route_search(content, state, map, seed)
	var first_end: Vector2i = first_search["farthest"]
	var second_search := _ordinary_route_search(content, state, map, first_end)
	var second_end: Vector2i = second_search["farthest"]
	var parents: Dictionary = second_search["parents"]
	var coordinates: Array[Vector2i] = [second_end]
	while coordinates[-1] != first_end:
		if not parents.has(coordinates[-1]):
			return {}
		coordinates.append(parents[coordinates[-1]])
	coordinates.reverse()
	if coordinates.size() < 2:
		return {}
	var route_directions: Array[Vector2i] = []
	var minimum := coordinates[0]
	var maximum := coordinates[0]
	for index: int in range(1, coordinates.size()):
		var direction := coordinates[index] - coordinates[index - 1]
		route_directions.append(direction)
		minimum = Vector2i(mini(minimum.x, coordinates[index].x), mini(minimum.y, coordinates[index].y))
		maximum = Vector2i(maxi(maximum.x, coordinates[index].x), maxi(maximum.y, coordinates[index].y))
	for index: int in range(coordinates.size() - 1, 0, -1):
		route_directions.append(coordinates[index - 1] - coordinates[index])
	return {"coordinates": coordinates, "directions": route_directions, "uniqueCells": coordinates.size(), "bounds": [minimum.x, minimum.y, maximum.x, maximum.y], "overlayAssetCount": 0}


func _ordinary_route_search(content: RealmzContent, state: GameState, map: MapDefinition, origin: Vector2i) -> Dictionary:
	var directions := MapTopology.cardinal_directions()
	var queue: Array[Vector2i] = [origin]
	var head := 0
	var parents: Dictionary = {}
	var distances: Dictionary = {origin: 0}
	var farthest := origin
	while head < queue.size():
		var coordinate := queue[head]
		head += 1
		for direction: Vector2i in directions:
			var movement := content.world.probe_movement(map.id, coordinate, direction, state.world, state.party_in_boat)
			if not movement.allowed or movement.target_map != map or not _safe_route_coordinate(state, map, movement.topology_result.target_cell):
				continue
			var destination: Vector2i = movement.topology_result.target_cell.coordinate
			if distances.has(destination):
				continue
			parents[destination] = coordinate
			distances[destination] = int(distances[coordinate]) + 1
			queue.append(destination)
			if int(distances[destination]) > int(distances[farthest]):
				farthest = destination
	return {"farthest": farthest, "parents": parents}


static func _safe_route_coordinate(_state: GameState, _map: MapDefinition, cell: MapCell) -> bool:
	return _safe_ordinary_cell(cell)


static func _safe_ordinary_cell(cell: MapCell) -> bool:
	return cell != null and cell.passable and cell.trigger_ids().is_empty() and cell.features().is_empty()


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


func _place_party(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i, visited_history_target: int = 0) -> bool:
	var snapshot := session.snapshot(); snapshot.game_state.party.map_id = map_id; snapshot.game_state.party.coordinate = coordinate
	# Keep campaign-authored timed encounters out of the instrumentation route.
	# The benchmark still advances the real five-minute clock, hour recovery,
	# conditions, fatigue, search, and movement transactions; this preparation
	# prevents an unrelated modal timeline from replacing a measured travel step.
	for encounter: TimedEncounterDefinition in content.timed_encounters():
		snapshot.game_state.set_timed_encounter_override(encounter.id, {"day": snapshot.game_state.clock.day() + 10_000, "percent": encounter.chance_percent})
	var map := content.world.map_by_id(map_id); var seeded := 0
	if map != null:
		for region: RandomEncounterRegion in map.random_regions():
			var effective := snapshot.game_state.world.random_region(region)
			effective.chance_ten_thousand = 0
			snapshot.game_state.world.set_random_region(effective)
		for cell: MapCell in map.topology.cells():
			snapshot.game_state.world.mark_visited(map_id, cell.coordinate); seeded += 1
			if seeded >= visited_history_target: break
	snapshot.game_state.world.mark_visited(map_id, coordinate)
	return session.restore(content, snapshot).state == SessionStep.State.COMPLETED


static func _percentile_ms(samples: Array[int], percentile: float) -> float:
	if samples.is_empty(): return 0.0
	var ordered := samples.duplicate(); ordered.sort(); var index := clampi(ceili(float(ordered.size()) * percentile) - 1, 0, ordered.size() - 1)
	return snappedf(float(ordered[index]) / 1000.0, 0.001)


static func _combined_percentile_ms(first: Array[int], second: Array[int], percentile: float) -> float:
	var combined: Array[int] = []
	for index: int in mini(first.size(), second.size()):
		combined.append(first[index] + second[index])
	return _percentile_ms(combined, percentile)


static func _maximum_ms(samples: Array[int]) -> float:
	return snappedf(float(samples.max() if not samples.is_empty() else 0) / 1000.0, 0.001)


static func _above_ms(samples: Array[int], threshold: float) -> int:
	return samples.filter(func(sample: int) -> bool: return float(sample) / 1000.0 > threshold).size()


static func _append_domain_timings(samples: Dictionary, timings: Dictionary) -> void:
	for domain: String in timings:
		if not samples.has(domain): samples[domain] = [] as Array[int]
		(samples[domain] as Array[int]).append(int(timings[domain]))


static func _domain_p95_milliseconds(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for domain: String in samples: result[domain] = _percentile_ms(samples[domain] as Array[int], 0.95)
	return result


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file_name: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories(): _remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _after_draw() -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		# Complete real native-resolution rendering without coupling the 120 Hz
		# engine-work benchmark to the physical monitor's refresh interval.
		RenderingServer.force_draw(false)


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
