extends SceneTree

const PACKAGE_REPOSITORY_SCRIPT := preload("res://src/storage/packages/package_repository.gd")
const GAME_SESSION_SCRIPT := preload("res://src/playthrough/session/game_session.gd")
const USAGE := "Usage: godot --headless --path <project> --script res://tools/package_probe.gd -- <package.realmz2> [--install-root <directory>] [--application-package <package.realmz2> --application-id <id> --application-hash <sha256>]"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var options := _parse_arguments(arguments)
	if options.is_empty():
		printerr(USAGE)
		call_deferred("_quit_cleanly", 2)
		return
	var package_path: String = options["packagePath"]
	var install_root: String = options["installRoot"]
	var repository := PACKAGE_REPOSITORY_SCRIPT.new()
	var application := repository.load_bundled_package(options["applicationPath"], options["applicationId"], options["applicationHash"])
	if not application.is_ok():
		printerr("APPLICATION_PACKAGE_REJECTED %s: %s" % [application.error_code, application.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	repository.set_application_content(application.content, application.media.assets())
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
	var blocked_move := session.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	var blocked_move_ms := Time.get_ticks_msec() - blocked_move_started_at
	var post_move_view_started_at := Time.get_ticks_msec()
	session.view()
	var post_move_view_ms := Time.get_ticks_msec() - post_move_view_started_at
	print(CanonicalJson.encode({
		"applicationCampaignId": application.content.campaign_id,
		"applicationPackageHash": application.content.package_hash,
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


func _parse_arguments(arguments: Array[String]) -> Dictionary:
	if arguments.is_empty() or (arguments.size() - 1) % 2 != 0:
		return {}
	var result := {
		"applicationHash": ApplicationLibraryIdentity.PACKAGE_HASH,
		"applicationId": ApplicationLibraryIdentity.CAMPAIGN_ID,
		"applicationPath": ApplicationLibraryIdentity.PATH,
		"installRoot": "",
		"packagePath": arguments[0],
	}
	var allowed := {
		"--application-hash": "applicationHash",
		"--application-id": "applicationId",
		"--application-package": "applicationPath",
		"--install-root": "installRoot",
	}
	for index: int in range(1, arguments.size(), 2):
		var option: String = arguments[index]
		if not allowed.has(option) or arguments[index + 1].is_empty():
			return {}
		result[allowed[option]] = arguments[index + 1]
	return result


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
