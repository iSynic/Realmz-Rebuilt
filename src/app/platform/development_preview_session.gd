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
	var target_failure := _validate_target(package.content, package.media)
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
	var readiness_error := _target_readiness_error(runtime.view())
	if not readiness_error.is_empty():
		return _fail(&"preview_target_not_ready", readiness_error)
	return true


func ready_fields() -> Dictionary:
	var view: GameView = _runtime.view()
	var interaction := view.active_interaction_request()
	return {
		"status": "ready",
		"campaignId": content.campaign_id,
		"packageHash": content.package_hash,
		"targetKind": String(_request.target_kind),
		"targetId": _request.target_id,
		"rngSeed": _request.rng_seed,
		"revision": view.revision,
		"pendingInteractionKind": "" if interaction == null else String(interaction.kind),
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


func _validate_target(package_content: RealmzContent, scenario_media: MediaSource) -> Array[String]:
	if _request.target_kind == DevelopmentPreviewRequest.SIMPLE_ENCOUNTER:
		if package_content.scenario_records.simple_encounter_by_id(_request.target_id) == null:
			return ["preview_target_unknown", "Simple Encounter %d is unavailable." % _request.target_id]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.COMPLEX_ENCOUNTER:
		if package_content.scenario_records.complex_encounter_by_id(_request.target_id) == null:
			return ["preview_target_unknown", "Complex Encounter %d is unavailable." % _request.target_id]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.THIEF_ENCOUNTER:
		var thief := package_content.scenario_records.thief_encounter_by_id(_request.target_id)
		var owner := package_content.scenario_records.complex_encounter_by_id(_request.target_complex_encounter_id)
		if thief == null:
			return ["preview_target_unknown", "Thief Encounter %d is unavailable." % _request.target_id]
		if owner == null:
			return ["preview_target_unknown", "Owning Complex Encounter %d is unavailable." % _request.target_complex_encounter_id]
		if not owner.thief or owner.thief_success != thief.id:
			return ["preview_target_mismatch", "Complex Encounter %d does not own Thief Encounter %d." % [_request.target_complex_encounter_id, _request.target_id]]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.EXTRA_ACTION_POINT_PROGRAM:
		var program := package_content.scenario.program_by_id("xap:%d" % _request.target_id)
		if program == null:
			return ["preview_target_unknown", "Extra Action Point program %d is unavailable." % _request.target_id]
		if not program.matches_extra_action_point(_request.target_id):
			return ["preview_target_mismatch", "Extra Action Point program %d has mismatched ownership." % _request.target_id]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.MAP_LOCATION:
		var map := package_content.world.map_by_id(_request.target_map_id)
		if map == null or map.topology.cell_at(_request.target_coordinate) == null:
			return ["preview_target_unknown", "Map location '%s' at %d,%d is unavailable." % [_request.target_map_id, _request.target_coordinate.x, _request.target_coordinate.y]]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.SCROLLING_TEXT:
		var status := scenario_media.resource_status("TEXT", _request.target_id) if scenario_media != null else &"missing"
		if status != &"resolved":
			return ["preview_target_unknown", "Scenario scrolling TEXT resource %d is %s." % [_request.target_id, String(status)]]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.BATTLE:
		if package_content.combat.battle_by_classic_id(_request.target_id) == null:
			return ["preview_target_unknown", "Battle %d is unavailable." % _request.target_id]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.TREASURE:
		if package_content.economy.treasure_by_classic_id(_request.target_id) == null:
			return ["preview_target_unknown", "Treasure %d is unavailable." % _request.target_id]
		return []
	if _request.target_kind == DevelopmentPreviewRequest.SHOP:
		if package_content.economy.shop_by_classic_id(_request.target_id) == null:
			return ["preview_target_unknown", "Shop %d is unavailable." % _request.target_id]
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
	if _request.target_kind == DevelopmentPreviewRequest.COMPLEX_ENCOUNTER:
		return runtime.apply_debug_command(SessionDebugCommand.start_encounter(&"complex", _request.target_id))
	if _request.target_kind == DevelopmentPreviewRequest.THIEF_ENCOUNTER:
		return _start_thief_target(runtime)
	if _request.target_kind == DevelopmentPreviewRequest.EXTRA_ACTION_POINT_PROGRAM:
		return runtime.apply_debug_command(SessionDebugCommand.start_extra_action_point_program(_request.target_id))
	if _request.target_kind == DevelopmentPreviewRequest.MAP_LOCATION:
		return runtime.apply_debug_command(SessionDebugCommand.warp(_request.target_map_id, _request.target_coordinate))
	if _request.target_kind == DevelopmentPreviewRequest.SCROLLING_TEXT:
		return runtime.apply_debug_command(SessionDebugCommand.start_scrolling_text(_request.target_id))
	if _request.target_kind == DevelopmentPreviewRequest.BATTLE:
		return runtime.apply_debug_command(SessionDebugCommand.start_battle(_request.target_id))
	if _request.target_kind == DevelopmentPreviewRequest.TREASURE:
		return runtime.apply_debug_command(SessionDebugCommand.start_treasure(_request.target_id))
	if _request.target_kind == DevelopmentPreviewRequest.SHOP:
		return runtime.apply_debug_command(SessionDebugCommand.start_shop(_request.target_id))
	return runtime.apply_debug_command(SessionDebugCommand.start_action_point(_request.target_id))


func _start_thief_target(runtime: Variant) -> SessionStep:
	var owner_step: SessionStep = runtime.apply_debug_command(SessionDebugCommand.start_encounter(&"complex", _request.target_complex_encounter_id))
	if owner_step.state == SessionStep.State.FAILED:
		return owner_step
	var interaction: InteractionRequest = runtime.view().active_interaction_request()
	if interaction == null or interaction.kind != InteractionRequest.WORD_AND_ACTION:
		return SessionStep.failed(runtime.view().revision, &"preview_target_not_ready", "Owning Complex Encounter %d did not enter its ordinary interaction surface." % _request.target_complex_encounter_id, owner_step.events)
	return runtime.respond(InteractionResponse.new(interaction.request_id, interaction.kind, InteractionResponse.ComplexEncounterBody.new(&"thief")))


func _target_readiness_error(view: GameView) -> String:
	if _request.target_kind not in [DevelopmentPreviewRequest.COMPLEX_ENCOUNTER, DevelopmentPreviewRequest.THIEF_ENCOUNTER, DevelopmentPreviewRequest.BATTLE, DevelopmentPreviewRequest.TREASURE, DevelopmentPreviewRequest.SHOP]:
		return ""
	var interaction := view.active_interaction_request()
	if _request.target_kind == DevelopmentPreviewRequest.BATTLE:
		if view.combat_view == null or view.combat_view.outcome != &"active" or interaction == null or interaction.kind != InteractionRequest.COMBAT:
			return "Battle %d did not enter an active combat command surface." % _request.target_id
	elif interaction == null or interaction.kind != _expected_interaction_kind():
		return "%s %d did not enter its ordinary interaction surface." % [String(_request.target_kind).capitalize(), _request.target_id]
	return ""


func _expected_interaction_kind() -> StringName:
	match _request.target_kind:
		DevelopmentPreviewRequest.COMPLEX_ENCOUNTER:
			return InteractionRequest.WORD_AND_ACTION
		DevelopmentPreviewRequest.THIEF_ENCOUNTER:
			return InteractionRequest.THIEF_ENCOUNTER
		DevelopmentPreviewRequest.TREASURE:
			return InteractionRequest.TREASURE_DISTRIBUTION
	return InteractionRequest.SHOP


func _fail(code: StringName, message: String) -> bool:
	error_code = code
	error_message = message
	return false
