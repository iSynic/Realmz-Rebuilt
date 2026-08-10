extends SceneTree


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_probe.gd -- <package.realmz2>")
		call_deferred("_quit_cleanly", 2)
		return
	var package_path: String = arguments[0]
	var repository := PackageRepository.new()
	var archive := ZIPReader.new()
	var started_at := Time.get_ticks_msec()
	var open_error := archive.open(package_path)
	if open_error != OK:
		printerr("PACKAGE_REJECTED package_open_failed: ZIP error %d" % open_error)
		call_deferred("_quit_cleanly", 1)
		return
	var archive_entries: Array[String] = repository._zip_entries(archive)
	var manifest: Variant = repository._read_document(archive, "manifest.json")
	if manifest == null or not repository._validate_manifest(manifest, archive, archive_entries):
		printerr("PACKAGE_REJECTED manifest: %s" % repository._last_error)
		call_deferred("_quit_cleanly", 1)
		return
	print("PROBE manifest_ms=%d" % (Time.get_ticks_msec() - started_at))
	var documents_started := Time.get_ticks_msec()
	var content_document: Variant = repository._read_document(archive, "content.json")
	var world_document: Variant = repository._read_document(archive, "world.json")
	var scenario_document: Variant = repository._read_document(archive, "scenario.json")
	var asset_document: Variant = repository._read_document(archive, "assets/index.json")
	print("PROBE documents_ms=%d" % (Time.get_ticks_msec() - documents_started))
	if content_document == null or world_document == null or scenario_document == null or asset_document == null:
		printerr("PACKAGE_REJECTED documents: %s" % repository._last_error)
		call_deferred("_quit_cleanly", 1)
		return
	var construction_started := Time.get_ticks_msec()
	var runtime_assets := repository._construct_assets(asset_document)
	var content := repository._construct_content(manifest, content_document, world_document, scenario_document, runtime_assets)
	print("PROBE construction_ms=%d" % (Time.get_ticks_msec() - construction_started))
	if content == null:
		printerr("PACKAGE_REJECTED construction: %s" % repository._last_error)
		call_deferred("_quit_cleanly", 1)
		return
	var media := PackageMediaCatalog.new(package_path, manifest["packageHash"], runtime_assets)
	archive.close()
	var session := GameSession.new()
	var session_started_at := Time.get_ticks_msec()
	var step := session.start(content, 1)
	var session_start_ms := Time.get_ticks_msec() - session_started_at
	if step.state == SessionStep.State.FAILED:
		printerr("SESSION_REJECTED %s: %s" % [step.error_code, step.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var view_started_at := Time.get_ticks_msec()
	var view := session.view()
	var first_view_ms := Time.get_ticks_msec() - view_started_at
	var repeat_views_started_at := Time.get_ticks_msec()
	for index: int in 10:
		session.view()
	var ten_repeat_views_ms := Time.get_ticks_msec() - repeat_views_started_at
	var blocked_move_started_at := Time.get_ticks_msec()
	var blocked_move := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	var blocked_move_ms := Time.get_ticks_msec() - blocked_move_started_at
	var post_move_view_started_at := Time.get_ticks_msec()
	session.view()
	var post_move_view_ms := Time.get_ticks_msec() - post_move_view_started_at
	print(CanonicalJson.encode({
		"blockedMoveError": String(blocked_move.error_code),
		"blockedMoveMs": blocked_move_ms,
		"campaignId": content.campaign_id,
		"firstViewMs": first_view_ms,
		"packageHash": content.package_hash,
		"rulesVersion": content.rules_version,
		"startMapId": view.party_map_id,
		"startX": view.party_coordinate.x,
		"startY": view.party_coordinate.y,
		"partySetupAvailable": view.party_setup_available,
		"pendingInteraction": step.interaction != null,
		"mediaAssets": media.assets().size(),
		"postMoveViewMs": post_move_view_ms,
		"sessionStartMs": session_start_ms,
		"tenRepeatViewsMs": ten_repeat_views_ms,
		"totalMs": Time.get_ticks_msec() - started_at,
	}))
	call_deferred("_quit_cleanly", 0)


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
