## Translates a bounded testing vocabulary into ordinary or direct public commands.
class_name RuntimeTestingCommands
extends RefCounted

var _application: RealmzApplication
var _session: GameSessionController
var _observer: RuntimeTestingObserver
var _content: Callable


func _init(application: RealmzApplication, session: GameSessionController, observer: RuntimeTestingObserver, content: Callable) -> void:
	_application = application
	_session = session
	_observer = observer
	_content = content


func act(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["action", "arguments"]) or not params["action"] is String or not params["arguments"] is Dictionary:
		return _observer.rejected("invalid_params", "An action requires its exact name and argument object.")
	if not _application.accepts_exploration_input():
		return _observer.rejected("input_blocked", "The application is not accepting exploration commands.")
	var action: String = params["action"]
	var arguments: Dictionary = params["arguments"]
	if action == "move":
		return _move(arguments)
	var intent := _intent(action, arguments)
	if intent == null:
		return _observer.rejected("unsupported_action", "The action or its exact argument shape is unsupported.")
	return step_result(_application.submit_intent(intent), "ordinary-gameplay")


func respond(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["response"]) or not RuntimeTestingFixtureRequest.exact_fields(params["response"], ["requestId", "kind", "body"]):
		return _observer.rejected("invalid_params", "A response requires requestId, kind, and its typed body.")
	var value: Dictionary = params["response"]
	if not value["requestId"] is String or not value["kind"] is String or not value["body"] is Dictionary:
		return _observer.rejected("invalid_response", "The response envelope is invalid.")
	var pending := _session.view().active_interaction_request()
	if pending == null or pending.request_id != value["requestId"] or String(pending.kind) != value["kind"]:
		return _observer.rejected("interaction_mismatch", "Respond to the exact currently observed interaction.")
	var body: Dictionary = _typed_json(value["body"])
	var response := InteractionResponse.from_data(value["requestId"], StringName(value["kind"]), body)
	if not response.is_supported_kind() or response.body.to_data() != body:
		return _observer.rejected("invalid_response", "The typed interaction body is invalid.")
	var revision_before := _observer.revision
	_application.submit_response(response)
	if _observer.revision == revision_before:
		return _observer.rejected("input_not_committed", "The application did not commit a session response.")
	return step_result(_observer.last_step, "ordinary-gameplay")


func _typed_json(value: Variant, depth: int = 0) -> Variant:
	# Godot's JSON parser uses floats; typed interaction codecs require integers.
	if depth > 64:
		return null
	if value is float and RuntimeTestingFixtureRequest.integer(value, -9_007_199_254_740_991, 9_007_199_254_740_991):
		return int(value)
	if value is Array:
		var entries: Array = []
		for entry: Variant in value:
			entries.append(_typed_json(entry, depth + 1))
		return entries
	if value is Dictionary:
		var fields: Dictionary = {}
		for key: String in value:
			fields[key] = _typed_json(value[key], depth + 1)
		return fields
	return value


func invoke(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["target"]) or not params["target"] is Dictionary:
		return _observer.rejected("invalid_params", "Direct invocation requires one exact target object.")
	var target: Dictionary = params["target"]
	if target.get("kind") == "thief-encounter":
		return _invoke_thief(target)
	var command := _direct_command(target)
	if command == null:
		return _observer.rejected("unsupported_target", "The exact direct target is unsupported or invalid.")
	return step_result(_session.apply_debug_command(command), "direct-invocation")


func restore(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["checkpoint"]):
		return _observer.rejected("invalid_params", "Restore requires one validated checkpoint object.")
	var snapshot := SaveEnvelope.from_data(params["checkpoint"])
	if snapshot == null:
		return _observer.rejected("invalid_checkpoint", "The checkpoint failed save-envelope validation.")
	return step_result(_session.restore(_content.call(), snapshot), "fixture-restore")


func step_result(step: SessionStep, mode: String) -> Dictionary:
	if step == null:
		return _observer.rejected("adapter_failure", "The command returned no session result; inspect runtime diagnostics.")
	if step.state == SessionStep.State.FAILED:
		return _observer.rejected(String(step.error_code), step.error_message)
	var events: Array[Dictionary] = []
	for event: DomainEvent in step.events:
		events.append(event.to_data())
	return _observer.accepted({"mode": mode, "gameRevision": step.view_revision, "state": step.state, "events": events, "observation": _observer.observe({"diagnostics": "complete"})["result"]})


func _move(arguments: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(arguments, ["dx", "dy"]) or not RuntimeTestingFixtureRequest.integer(arguments["dx"], -1, 1) or not RuntimeTestingFixtureRequest.integer(arguments["dy"], -1, 1):
		return _observer.rejected("invalid_params", "Move requires adjacent integer dx and dy.")
	var direction := Vector2i(int(arguments["dx"]), int(arguments["dy"]))
	if direction == Vector2i.ZERO:
		return _observer.rejected("invalid_params", "Move requires a nonzero adjacent direction.")
	var revision_before := _observer.revision
	_application.submit_movement(direction)
	if _observer.revision == revision_before:
		return _observer.rejected("input_blocked", "The ordinary host movement boundary rejected this direction.")
	return step_result(_observer.last_step, "ordinary-gameplay")


func _intent(action: String, arguments: Dictionary) -> PlayerIntent:
	if action == "service":
		if RuntimeTestingFixtureRequest.exact_fields(arguments, ["serviceId", "action"]) and arguments["serviceId"] is String and arguments["action"] is String:
			return EconomyIntents.service(arguments["serviceId"], StringName(arguments["action"]))
		return null
	if action == "dungeon-turn":
		if RuntimeTestingFixtureRequest.exact_fields(arguments, ["delta"]) and RuntimeTestingFixtureRequest.integer(arguments["delta"], -1, 1) and arguments["delta"] != 0:
			return ExplorationIntents.dungeon_turn(int(arguments["delta"]))
		return null
	if not arguments.is_empty():
		return null
	match action:
		"search": return ExplorationIntents.search()
		"toggle-search": return ExplorationIntents.toggle_search()
		"torch": return ExplorationIntents.use_torch()
		"contextual-encounter": return ExplorationIntents.contextual_encounter()
		"camp": return ExplorationIntents.camp()
		"rest": return ExplorationIntents.rest()
		"heal": return ExplorationIntents.heal()
	return null


func _direct_command(target: Dictionary) -> SessionDebugCommand:
	if not RuntimeTestingFixtureRequest.exact_fields(target, ["kind", "id"]) or not target["kind"] is String:
		return null
	if target["kind"] == "action-point":
		return SessionDebugCommand.start_action_point(target["id"]) if target["id"] is String and target["id"].length() <= 128 else null
	if not RuntimeTestingFixtureRequest.integer(target["id"], 0, 32767):
		return null
	var native_id := int(target["id"])
	match target["kind"]:
		"extra-action-point-program": return SessionDebugCommand.start_extra_action_point_program(native_id)
		"simple-encounter": return SessionDebugCommand.start_encounter(&"simple", native_id)
		"complex-encounter": return SessionDebugCommand.start_encounter(&"complex", native_id)
		"shop": return SessionDebugCommand.start_shop(native_id)
	return null


func _invoke_thief(target: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(target, ["kind", "id", "ownerId"]) or not RuntimeTestingFixtureRequest.integer(target["id"], 0, 32767) or not RuntimeTestingFixtureRequest.integer(target["ownerId"], 0, 32767):
		return _observer.rejected("invalid_target", "Thief invocation requires its exact ID and owning Complex Encounter ID.")
	var content: RealmzContent = _content.call()
	var owner := content.scenario_records.complex_encounter_by_id(int(target["ownerId"]))
	if owner == null or not owner.thief or owner.thief_success != int(target["id"]) or content.scenario_records.thief_encounter_by_id(int(target["id"])) == null:
		return _observer.rejected("target_owner_mismatch", "The requested Complex Encounter does not own this Thief Encounter.")
	var step := _session.apply_debug_command(SessionDebugCommand.start_encounter(&"complex", owner.id))
	if step.state == SessionStep.State.FAILED:
		return step_result(step, "direct-invocation")
	var pending := _session.view().active_interaction_request()
	if pending == null or pending.kind != InteractionRequest.WORD_AND_ACTION:
		return _observer.rejected("target_not_ready", "The owning encounter did not expose its ordinary action surface.")
	return step_result(_session.respond(InteractionResponse.new(pending.request_id, pending.kind, InteractionResponse.ComplexEncounterBody.new(&"thief"))), "direct-invocation")
