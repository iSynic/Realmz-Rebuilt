extends SceneTree

const PACKAGE_REPOSITORY_SCRIPT := preload("res://src/infrastructure/packages/package_repository.gd")
const GAME_SESSION_SCRIPT := preload("res://src/session/game_session.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 and arguments.size() != 3:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_probe.gd -- <package.realmz2> [--install-root <directory>]")
		call_deferred("_quit_cleanly", 2)
		return
	var package_path: String = arguments[0]
	var install_root := ""
	if arguments.size() == 3:
		if arguments[1] != "--install-root":
			printerr("PACKAGE_REJECTED arguments: expected --install-root")
			call_deferred("_quit_cleanly", 2)
			return
		install_root = arguments[2]
	var repository := PACKAGE_REPOSITORY_SCRIPT.new()
	var started_at := Time.get_ticks_msec()
	var timing := {"active": &"" as StringName, "startedAt": started_at, "phaseMs": {}}
	var record_progress := func(phase: StringName, _completed: int, _total: int) -> void:
		var now := Time.get_ticks_msec()
		var active: StringName = timing["active"]
		if phase != active:
			if not active.is_empty():
				var phase_ms: Dictionary = timing["phaseMs"]
				phase_ms[String(active)] = int(phase_ms.get(String(active), 0)) + now - int(timing["startedAt"])
			timing["active"] = phase
			timing["startedAt"] = now
	var package_result: PackageLoadResult
	if install_root.is_empty():
		package_result = repository.load_package(package_path, record_progress)
	else:
		var install_result := repository.install_package(package_path, install_root, record_progress)
		if not install_result.is_ok():
			printerr("PACKAGE_REJECTED %s: %s" % [install_result.error_code, install_result.error_message])
			call_deferred("_quit_cleanly", 1)
			return
		package_path = install_result.installed_path
		package_result = install_result.package
	var active_phase: StringName = timing["active"]
	var phase_ms: Dictionary = timing["phaseMs"]
	if not active_phase.is_empty():
		phase_ms[String(active_phase)] = int(phase_ms.get(String(active_phase), 0)) + Time.get_ticks_msec() - int(timing["startedAt"])
	var package_load_ms := Time.get_ticks_msec() - started_at
	if not package_result.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [package_result.error_code, package_result.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var content: RealmzContent = package_result.content
	var media: PackageMediaCatalog = package_result.media
	var session := GAME_SESSION_SCRIPT.new()
	var session_started_at := Time.get_ticks_msec()
	var step: Variant = session.call("start", content, 1)
	var session_start_ms := Time.get_ticks_msec() - session_started_at
	if step.state == SessionStep.State.FAILED:
		printerr("SESSION_REJECTED %s: %s" % [step.error_code, step.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var view_started_at := Time.get_ticks_msec()
	var view: GameView = session.call("view")
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
		"packagePath": package_path,
		"rulesVersion": content.rules_version,
		"startMapId": view.party_map_id,
		"startX": view.party_coordinate.x,
		"startY": view.party_coordinate.y,
		"partySetupAvailable": view.party_setup_available,
		"pendingInteraction": step.interaction != null,
		"mediaAssets": media.assets().size(),
		"packageLoadMs": package_load_ms,
		"phaseMs": phase_ms,
		"postMoveViewMs": post_move_view_ms,
		"sessionStartMs": session_start_ms,
		"tenRepeatViewsMs": ten_repeat_views_ms,
		"totalMs": Time.get_ticks_msec() - started_at,
	}))
	call_deferred("_quit_cleanly", 0)


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
