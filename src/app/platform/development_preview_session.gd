## Prepares one isolated Providence preview through the ordinary package and session APIs.

class_name DevelopmentPreviewSession
extends RefCounted

const PARTY_NAMES: Array[String] = ["Ari", "Brom", "Cerys", "Doran", "Elowen", "Fen"]

var content: RealmzContent
var application_media: MediaSource
var package_media: MediaSource
var last_step: SessionStep
var error_code: StringName
var error_message: String

var _request: DevelopmentPreviewRequest
var _runtime: Variant
var _repository := PackageRepository.new()


func load_request(request: DevelopmentPreviewRequest) -> bool:
	_request = request
	if request == null:
		return _fail(&"invalid_request", "The preview request is malformed or unsupported.")
	if not FileAccess.file_exists(request.package_path):
		return _fail(&"preview_package_missing", "The preview package does not exist.")
	if FileAccess.get_sha256(request.package_path).to_lower() != request.package_sha256:
		return _fail(&"preview_package_hash_mismatch", "The preview package SHA-256 does not match the request.")
	var application := _repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		return _fail(&"application_package_rejected", application.error_message)
	_repository.set_application_content(application.content, application.media.assets())
	var package := _repository.load_package(request.package_path)
	if not package.is_ok():
		return _fail(package.error_code, package.error_message)
	var target_failure := _validate_target(package.content)
	if not target_failure.is_empty():
		return _fail(target_failure[0], target_failure[1])
	package.content.characters.install_application_catalog(application.content.characters)
	content = package.content
	application_media = application.media
	package_media = package.media
	return true


func start(runtime: Variant) -> bool:
	if content == null or runtime == null:
		return _fail(&"preview_runtime_unavailable", "The preview runtime is unavailable.")
	_runtime = runtime
	last_step = runtime.start(content, _request.rng_seed)
	if last_step.state == SessionStep.State.FAILED:
		return _fail(last_step.error_code, last_step.error_message)
	last_step = _create_party(runtime)
	if last_step.state == SessionStep.State.FAILED:
		return _fail(last_step.error_code, last_step.error_message)
	last_step = _start_target(runtime)
	if last_step.state == SessionStep.State.FAILED:
		return _fail(last_step.error_code, last_step.error_message)
	return true


func ready_fields() -> Dictionary:
	var view: GameView = _runtime.view()
	return {
		"status": "ready",
		"campaignId": content.campaign_id,
		"packageHash": content.package_hash,
		"targetKind": String(_request.target_kind),
		"targetId": _request.target_id,
		"rngSeed": _request.rng_seed,
		"revision": view.revision,
		"pendingInteractionKind": "" if view.pending_interaction == null else String(view.pending_interaction.kind),
	}


func failure_fields() -> Dictionary:
	return {
		"status": "failed",
		"errorCode": String(error_code),
		"errorMessage": error_message,
		"targetKind": "" if _request == null else String(_request.target_kind),
		"targetId": "" if _request == null else _request.target_id,
	}


func _create_party(runtime: Variant) -> SessionStep:
	var view: GameView = runtime.view()
	if view.race_options.is_empty() or view.caste_options.is_empty():
		return SessionStep.failed(view.revision, &"preview_party_unavailable", "The effective application catalog has no Race or Caste for the preview party.")
	var members: Array[CharacterCreationSpec] = []
	for member_name: String in PARTY_NAMES:
		members.append(CharacterCreationSpec.new(member_name, view.race_options[0].id, view.caste_options[0].id, 1))
	return runtime.submit_intent(PartyIntents.create(members))


func _validate_target(package_content: RealmzContent) -> Array[String]:
	if _request.target_kind == DevelopmentPreviewRequest.SIMPLE_ENCOUNTER:
		if package_content.scenario_records.simple_encounter_by_id(_request.target_id) == null:
			return ["preview_target_unknown", "Simple Encounter %d is unavailable." % _request.target_id]
		return []
	var trigger := package_content.scenario_records.trigger_by_id(_request.target_id)
	if trigger == null:
		return ["preview_target_unknown", "Action Point '%s' is unavailable." % _request.target_id]
	if trigger.map_id != _request.target_map_id or trigger.coordinate != _request.target_coordinate:
		return ["preview_target_mismatch", "The Action Point identity does not match the requested map coordinate."]
	return []


func _start_target(runtime: Variant) -> SessionStep:
	if _request.target_kind == DevelopmentPreviewRequest.SIMPLE_ENCOUNTER:
		return runtime.apply_debug_command(SessionDebugCommand.start_encounter(&"simple", _request.target_id))
	return runtime.apply_debug_command(SessionDebugCommand.start_action_point(_request.target_id))


func _fail(code: StringName, message: String) -> bool:
	error_code = code
	error_message = message
	return false
