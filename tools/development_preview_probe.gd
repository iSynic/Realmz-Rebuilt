## Exercises one isolated Providence preview request through public package/session boundaries.

extends SceneTree

const RESULT_KIND := "realmz2.preview-result"
const RESULT_VERSION := 1

var _request: DevelopmentPreviewRequest


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/development_preview_probe.gd -- <preview-request.json>")
		call_deferred("_quit_cleanly", 2)
		return
	_request = DevelopmentPreviewRequest.decode(_read_json(arguments[0]))
	if _request == null:
		printerr("PREVIEW_REQUEST_REJECTED invalid_request: The preview request is malformed or unsupported.")
		call_deferred("_quit_cleanly", 1)
		return
	var failure := _validate_package_file()
	if not failure.is_empty():
		_finish_failed(failure[0], failure[1])
		return
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		_finish_failed("application_package_rejected", application.error_message)
		return
	repository.set_application_content(application.content, application.media.assets())
	var loaded := repository.load_package(_request.package_path)
	if not loaded.is_ok():
		_finish_failed(String(loaded.error_code), loaded.error_message)
		return
	var session := GameSession.new()
	var step := session.start(loaded.content, _request.rng_seed)
	if step.state == SessionStep.State.FAILED:
		_finish_failed(String(step.error_code), step.error_message)
		return
	step = _create_party(session)
	if step.state == SessionStep.State.FAILED:
		_finish_failed(String(step.error_code), step.error_message)
		return
	var target_failure := _validate_target(loaded.content)
	if not target_failure.is_empty():
		_finish_failed(target_failure[0], target_failure[1])
		return
	step = _start_target(session)
	if step.state == SessionStep.State.FAILED:
		_finish_failed(String(step.error_code), step.error_message)
		return
	var view := session.view(step.events)
	_finish({
		"status": "ready",
		"campaignId": loaded.content.campaign_id,
		"packageHash": loaded.content.package_hash,
		"targetKind": String(_request.target_kind),
		"targetId": _request.target_id,
		"rngSeed": _request.rng_seed,
		"revision": view.revision,
		"pendingInteractionKind": "" if view.pending_interaction == null else String(view.pending_interaction.kind),
	})


func _create_party(session: GameSession) -> SessionStep:
	var view := session.view()
	if view.race_options.is_empty() or view.caste_options.is_empty():
		return SessionStep.failed(view.revision, &"preview_party_unavailable", "The effective application catalog has no Race or Caste for the preview party.")
	var names: Array[String] = ["Ari", "Brom", "Cerys", "Doran", "Elowen", "Fen"]
	var members: Array[CharacterCreationSpec] = []
	for name: String in names:
		members.append(CharacterCreationSpec.new(name, view.race_options[0].id, view.caste_options[0].id, 1))
	return session.submit_intent(PartyIntents.create(members))


func _validate_target(content: RealmzContent) -> Array[String]:
	if _request.target_kind == DevelopmentPreviewRequest.SIMPLE_ENCOUNTER:
		if content.scenario_records.simple_encounter_by_id(_request.target_id) == null:
			return ["preview_target_unknown", "Simple Encounter %d is unavailable." % _request.target_id]
		return []
	var trigger := content.scenario_records.trigger_by_id(_request.target_id)
	if trigger == null:
		return ["preview_target_unknown", "Action Point '%s' is unavailable." % _request.target_id]
	if trigger.map_id != _request.target_map_id or trigger.coordinate != _request.target_coordinate:
		return ["preview_target_mismatch", "The Action Point identity does not match the requested map coordinate."]
	return []


func _start_target(session: GameSession) -> SessionStep:
	if _request.target_kind == DevelopmentPreviewRequest.SIMPLE_ENCOUNTER:
		return session.apply_debug_command(SessionDebugCommand.start_encounter(&"simple", _request.target_id))
	return session.apply_debug_command(SessionDebugCommand.start_action_point(_request.target_id))


func _validate_package_file() -> Array[String]:
	if not FileAccess.file_exists(_request.package_path):
		return ["preview_package_missing", "The preview package does not exist."]
	var actual_hash := FileAccess.get_sha256(_request.package_path)
	if actual_hash.to_lower() != _request.package_sha256:
		return ["preview_package_hash_mismatch", "The preview package SHA-256 does not match the request."]
	return []


func _finish_failed(code: String, message: String) -> void:
	_finish({
		"status": "failed",
		"errorCode": code,
		"errorMessage": message,
		"targetKind": "" if _request == null else String(_request.target_kind),
		"targetId": "" if _request == null else _request.target_id,
	})


func _finish(fields: Dictionary) -> void:
	var result := {"kind": RESULT_KIND, "formatVersion": RESULT_VERSION}
	result.merge(fields, true)
	var encoded := CanonicalJson.encode(result)
	var file := FileAccess.open(_request.result_path, FileAccess.WRITE)
	if file == null:
		printerr("PREVIEW_RESULT_REJECTED write_failed: The preview result could not be written.")
		call_deferred("_quit_cleanly", 1)
		return
	file.store_string(encoded + "\n")
	file.close()
	print("PREVIEW_%s %s" % [String(result["status"]).to_upper(), encoded])
	call_deferred("_quit_cleanly", 0 if result["status"] == "ready" else 1)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
