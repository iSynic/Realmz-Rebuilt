## Connects opt-in testing transport to explicit application-owned collaborators.
class_name RuntimeTestingHost
extends Node

var _endpoint: RuntimeTestingEndpoint
var _observer: RuntimeTestingObserver
var _session: GameSessionController
var _readiness: Callable
var _fixture: RuntimeTestingFixtureRequest
var _prepared: RuntimeTestingFixtureSession
var _commands: RuntimeTestingCommands
var _ui: RuntimeTestingUi
var _fixture_ready := false
var _drawn_revision := -1
var _capture_bytes := 0
var _capture_count := 0


static func live_requested() -> bool:
	return OS.is_debug_build() and OS.get_cmdline_user_args().has("--realmz-testing-observe")


func bind(session: GameSessionController, content: Callable, readiness: Callable, application: RealmzApplication = null, fixture: RuntimeTestingFixtureRequest = null) -> Error:
	if not OS.is_debug_build() or (fixture == null and not live_requested()) or (fixture != null and application == null):
		return ERR_UNAUTHORIZED
	_session = session
	_readiness = readiness
	_fixture = fixture
	_observer = RuntimeTestingObserver.new(session, content, _readiness_fields)
	if application != null:
		_ui = RuntimeTestingUi.new(application, _observer)
	if fixture != null:
		_prepared = RuntimeTestingFixtureSession.new()
		_commands = RuntimeTestingCommands.new(application, session, _observer, content)
	_endpoint = RuntimeTestingEndpoint.new()
	add_child(_endpoint)
	RenderingServer.frame_post_draw.connect(_frame_drawn)
	return _endpoint.open(OS.get_environment("REALMZ_TESTING_HOME"), "observe" if fixture == null else "fixture", func() -> int: return _observer.revision, _dispatch, fixture)


func prepare_fixture(presentation: PresentationCoordinator, media: PresentationMediaController, shell: GameShell, content_ready: Callable) -> void:
	_prepare.call_deferred(presentation, media, shell, content_ready)


func _prepare(presentation: PresentationCoordinator, media: PresentationMediaController, shell: GameShell, content_ready: Callable) -> void:
	shell.status.set_status("Preparing isolated runtime fixture…")
	await get_tree().process_frame
	if not _prepared.load_request(_fixture):
		shell.status.set_status("Fixture failed: %s" % _prepared.error["message"], true)
		return
	content_ready.call(_prepared.content)
	media.set_application_character_media(_prepared.application_media)
	media.set_package_media(_prepared.package_media)
	if not _prepared.start(_fixture, _session):
		shell.status.set_status("Fixture failed: %s" % _prepared.error["message"], true)
		return
	presentation.refresh()
	shell.status.set_status("TEST FIXTURE %s • isolated data" % _fixture.fixture_id.left(8))
	_fixture_ready = true


func _dispatch(command: String, params: Dictionary) -> Dictionary:
	match command:
		"describe":
			return _observer.accepted(_endpoint.description()) if params.is_empty() else _observer.rejected("invalid_params", "Describe accepts an empty parameter object.")
		"observe":
			return _observe(params)
		"checkpoint":
			return _observer.checkpoint(params)
	if _fixture == null:
		return _observer.rejected("live_read_only", "Live adventures permit observation and checkpoint export only.")
	if command == "close":
		if not params.is_empty():
			return _observer.rejected("invalid_params", "Close accepts an empty parameter object.")
		_observer.revision += 1
		_endpoint.request_shutdown()
		return _observer.accepted({"mode": "fixture-lifecycle", "closing": true})
	if not _fixture_ready:
		return _observer.rejected("fixture_not_ready", "Fixture preparation has not completed successfully.")
	if command == "capture":
		return _capture(params)
	var readiness := _readiness_fields()
	if readiness["combatPlayback"] or readiness["hostInteraction"]:
		return _observer.rejected("input_blocked", "Presentation playback or a host interaction owns the application boundary.")
	match command:
		"act": return _commands.act(params)
		"respond": return _commands.respond(params)
		"invoke": return _commands.invoke(params)
		"restore": return _commands.restore(params)
		"ui": return _ui.execute(params)
	return _observer.rejected("unsupported_command", "This adapter does not support the requested command.")


func _observe(params: Dictionary) -> Dictionary:
	var result := _observer.observe(params)
	if result["error"] != null:
		return result
	if _ui != null:
		result["result"].merge(_ui.controls())
	if _prepared != null:
		result["result"]["identity"] = _prepared.identity.duplicate(true)
	return result


func _readiness_fields() -> Dictionary:
	var fields: Dictionary = _readiness.call()
	fields["fixtureReady"] = _fixture_ready
	fields["fixtureError"] = _prepared.error.duplicate() if _prepared != null and not _prepared.error.is_empty() else null
	fields["drawnRevision"] = _drawn_revision
	fields["visualReady"] = _observer != null and _drawn_revision == _observer.revision and not fields.get("combatPlayback", false)
	return fields


func _frame_drawn() -> void:
	if _observer != null:
		_drawn_revision = _observer.revision


func _capture(params: Dictionary) -> Dictionary:
	if not params.is_empty():
		return _observer.rejected("invalid_params", "Capture accepts no file path or other parameters.")
	if DisplayServer.get_name() == "headless":
		return _observer.rejected("capture_unavailable", "A rendered fixture viewport is required for screenshots.")
	if not _readiness_fields()["visualReady"]:
		return _observer.rejected("presentation_not_ready", "Wait for a rendered frame of the committed revision.")
	var screenshot := get_viewport().get_texture().get_image()
	var png := screenshot.save_png_to_buffer()
	if _capture_bytes + png.size() > RuntimeTestingProtocol.MAX_RECORD_BYTES:
		return _observer.rejected("recording_limit", "The fixture screenshot bound was reached; existing evidence is retained.")
	var directory := _fixture.scratch_root.path_join("captures")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _observer.rejected("capture_write_failed", "The fixture capture directory is unavailable.")
	_capture_count += 1
	var path := directory.path_join("frame-%06d.png" % _capture_count)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _observer.rejected("capture_write_failed", "The fixture screenshot could not be written.")
	file.store_buffer(png)
	file.close()
	_capture_bytes += png.size()
	return _observer.accepted({"mode": "rendered-observation", "path": path, "sha256": FileAccess.get_sha256(path), "bytes": png.size(), "width": screenshot.get_width(), "height": screenshot.get_height(), "readiness": _readiness_fields()})
