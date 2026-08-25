extends SceneTree

var _failures: Array[String] = []
var _stages: Array[Dictionary] = []
var _observed_battles: Array[int] = []
var _content: RealmzContent
var _session: GameSession

const MAX_NEARBY_TRAVERSAL_STEPS := 8


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 3:
		printerr("Usage: godot --headless --path <project> --script res://tools/route_acceptance.gd -- <package.realmz2> <route.json> <report.json>")
		call_deferred("_quit_cleanly", 2)
		return
	var package_path: String = arguments[0]
	var route_path: String = arguments[1]
	var report_path: String = arguments[2]
	var route: Variant = _read_json(route_path)
	if route == null:
		printerr("ROUTE_REJECTED invalid route document")
		call_deferred("_quit_cleanly", 1)
		return
	var loaded := PackageRepository.new().load_package(package_path)
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	_content = loaded.content
	_session = GameSession.new()
	var started := _session.start(_content, 1)
	if started.state == SessionStep.State.FAILED:
		printerr("SESSION_REJECTED %s: %s" % [started.error_code, started.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	_prepare_party()
	_validate_route_header(route)
	for entry: Variant in route.get("steps", []):
		if not entry is Dictionary:
			_fail("route contains a non-object step")
			continue
		_run_step(entry)
	for entry: Variant in route.get("travelProofs", []):
		if not entry is Dictionary:
			_fail("route contains a non-object travel proof")
			continue
		_run_travel_proof(entry)
	if route.has("completionAnchor"):
		_validate_completion(route["completionAnchor"])
	var report := {
		"schemaVersion": 1,
		"routeId": String(route.get("routeId", "")),
		"campaignId": _content.campaign_id,
		"packageHash": _content.package_hash,
		"routeSha256": FileAccess.get_sha256(route_path),
		"status": "passed" if _failures.is_empty() else "failed",
		"stages": _stages,
		"failures": _failures,
		"observedBattleIds": _observed_battles,
		"finalState": _final_state(),
	}
	if not _write_report(report_path, report):
		printerr("REPORT_REJECTED unable to write %s" % report_path)
		call_deferred("_quit_cleanly", 1)
		return
	print("ROUTE_%s %s" % ["PASSED" if _failures.is_empty() else "FAILED", CanonicalJson.encode(report)])
	call_deferred("_quit_cleanly", 0 if _failures.is_empty() else 1)


func _prepare_party() -> void:
	if _session._state.party.characters().is_empty():
		var races := _content.race_definitions()
		var castes := _content.caste_definitions()
		if races.is_empty() or castes.is_empty():
			_fail("route package has no application character definitions")
			return
		for index: int in 6:
			var character := CharacterState.new("route.hero.%d" % (index + 1), "Route Hero %d" % (index + 1), 1_000_000, 1_000_000)
			character.race_id = races[0].id
			character.caste_id = castes[0].id
			if not _session._state.party.add_character(character):
				_fail("route harness could not create its deterministic party")
				return
	for character: CharacterState in _session._state.party.characters():
		character.maximum_health = 1_000_000
		character.current_health = 1_000_000
		character.brawn = 32_767
		character.maximum_load = 1_000_000_000
		character.carried_load = 0
		character.agility = 32_767
		character.magic_resistance = 32_767
		for ability_index: int in range(5, 13):
			character.set_ability_value(ability_index, 32_767)
		for save_index: int in 8:
			character.set_save_value_raw(save_index, 32_767)
	_session._state.party_setup_completed = true


func _validate_route_header(route: Dictionary) -> void:
	if route.get("campaignId") != _content.campaign_id:
		_fail("route campaign does not match the loaded package")
	var has_steps: bool = route.get("steps") is Array and not route["steps"].is_empty()
	var has_travel_proofs: bool = route.get("travelProofs") is Array and not route["travelProofs"].is_empty()
	if not has_steps and not has_travel_proofs:
		_fail("route has no executable steps or travel proofs")
	if has_steps and not route.has("completionAnchor"):
		_fail("route with scenario steps has no completion anchor")
	var start: Variant = route.get("start", {})
	if not start is Dictionary:
		_fail("route start is missing")
		return
	var map := _content.world.map_by_type_and_index(StringName(start.get("levelType", "")), int(start.get("levelIndex", -1)))
	if map == null or map.id != _content.start_map_id or Vector2i(int(start.get("x", -1)), int(start.get("y", -1))) != _content.start_coordinate:
		_fail("route start does not match the package manifest")


func _run_step(step_definition: Dictionary) -> void:
	var failure_count := _failures.size()
	var step_id := String(step_definition.get("id", "unnamed-step"))
	var trigger_id := String(step_definition.get("triggerId", ""))
	var trigger := _content.trigger_by_id(trigger_id)
	var scripted_responses: Array = step_definition.get("responses", [])
	var response_cursor := {"index": 0}
	if trigger == null:
		_fail("%s references unavailable trigger %s" % [step_id, trigger_id])
		_stage(step_id, failure_count)
		return
	if trigger.map_id.is_empty() or _content.world.map_by_id(trigger.map_id) == null:
		_run_program_step(step_id, step_definition, trigger, failure_count, scripted_responses, response_cursor)
		return
	_validate_step_position(step_id, step_definition.get("position", {}), trigger)
	var nearby_path := _nearby_topology_path(trigger)
	if not nearby_path.is_empty():
		_run_topology_step(step_id, step_definition, trigger, nearby_path, failure_count, scripted_responses, response_cursor)
		return
	_session._state.party.map_id = trigger.map_id
	_session._state.party.coordinate = trigger.coordinate
	_session._state.world.mark_visited(trigger.map_id, trigger.coordinate)
	var continuation_body := SessionContinuation.ExplorationBody.new()
	continuation_body.map_id = trigger.map_id
	continuation_body.coordinate = trigger.coordinate
	continuation_body.trigger_ids = [trigger.id]
	continuation_body.trigger_index = 0
	continuation_body.active_trigger_id = ""
	continuation_body.random_region_index = -1
	continuation_body.random_battle_stage = &""
	continuation_body.action_point_destination_depth = 0
	_session._session_continuation = SessionContinuation.post_move(continuation_body)
	if _session._session_continuation == null:
		_fail("%s could not construct its typed post-move continuation" % step_id)
		_stage(step_id, failure_count)
		return
	var events: Array[DomainEvent] = []
	var result := _session._continue_post_move([])
	result = _drain_interactions(result, events, step_id, scripted_responses, response_cursor)
	if result.state == SessionStep.State.FAILED:
		_fail("%s failed with %s: %s" % [step_id, result.error_code, result.error_message])
	_validate_scripted_responses(step_id, scripted_responses, response_cursor)
	_validate_step_events(step_id, step_definition, events)
	_stage(step_id, failure_count, {"entryMode": "checkpoint"})


func _run_travel_proof(proof: Dictionary) -> void:
	var failure_count := _failures.size()
	var proof_id := String(proof.get("id", "unnamed-travel-proof"))
	var start: Variant = proof.get("start", {})
	if not start is Dictionary or not proof.get("moves") is Array:
		_fail("%s has no typed start or movement list" % proof_id)
		_stage(proof_id, failure_count, {"entryMode": "travel-checkpoint"})
		return
	var map := _content.world.map_by_type_and_index(StringName(start.get("levelType", "")), int(start.get("levelIndex", -1)))
	var coordinate := Vector2i(int(start.get("x", -1)), int(start.get("y", -1)))
	if map == null or map.topology.cell_at(coordinate) == null:
		_fail("%s starts outside authoritative topology" % proof_id)
		_stage(proof_id, failure_count, {"entryMode": "travel-checkpoint"})
		return
	_session._state.party.map_id = map.id
	_session._state.party.coordinate = coordinate
	_session._state.world.mark_visited(map.id, coordinate)
	var events: Array[DomainEvent] = []
	var movement_steps := 0
	for move: Variant in proof["moves"]:
		if not move is Array or move.size() != 2 or not _is_integer(move[0]) or not _is_integer(move[1]):
			_fail("%s contains a malformed movement vector" % proof_id)
			break
		var direction := Vector2i(int(move[0]), int(move[1]))
		var result := _session.submit_intent(PlayerIntent.move(direction))
		result = _drain_interactions(result, events, proof_id)
		movement_steps += 1
		if result.state == SessionStep.State.FAILED:
			_fail("%s movement failed with %s: %s" % [proof_id, result.error_code, result.error_message])
			break
	_validate_travel_expectations(proof_id, proof.get("expect", {}), events)
	_stage(proof_id, failure_count, {"entryMode": "travel-checkpoint", "movementSteps": movement_steps})


func _validate_travel_expectations(proof_id: String, expected: Variant, events: Array[DomainEvent]) -> void:
	if not expected is Dictionary:
		_fail("%s has no typed travel expectations" % proof_id)
		return
	var event_kinds: Variant = expected.get("eventKinds", [])
	if not event_kinds is Array:
		_fail("%s has a malformed expected-event list" % proof_id)
		return
	for kind: Variant in event_kinds:
		if not kind is String or not _contains_event(events, StringName(kind)):
			_fail("%s did not publish expected event %s" % [proof_id, kind])
	if expected.has("partyInBoat"):
		if not expected["partyInBoat"] is bool:
			_fail("%s has a malformed expected boat state" % proof_id)
		elif expected["partyInBoat"] != _session._state.party_in_boat:
			_fail("%s ended with the wrong boat state" % proof_id)
	var end: Variant = expected.get("position", {})
	if end is Dictionary and not end.is_empty():
		var map := _content.world.map_by_type_and_index(StringName(end.get("levelType", "")), int(end.get("levelIndex", -1)))
		var coordinate := Vector2i(int(end.get("x", -1)), int(end.get("y", -1)))
		if map == null or _session._state.party.map_id != map.id or _session._state.party.coordinate != coordinate:
			_fail("%s ended at an unexpected position" % proof_id)


func _contains_event(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


func _is_integer(value: Variant) -> bool:
	return value is int or value is float and value == floorf(value)


func _nearby_topology_path(trigger: TriggerDefinition) -> Array[Vector2i]:
	if _session._state.party_in_boat or _session._state.party.map_id != trigger.map_id or _session._state.party.coordinate == trigger.coordinate:
		return []
	var map := _content.world.map_by_id(trigger.map_id)
	if map == null:
		return []
	var path := map.topology.find_path(_session._state.party.coordinate, trigger.coordinate, _session._state.world, map.level_type)
	if path.is_empty() or path.size() > MAX_NEARBY_TRAVERSAL_STEPS:
		return []
	return path


func _run_topology_step(step_id: String, step_definition: Dictionary, trigger: TriggerDefinition, path: Array[Vector2i], failure_count: int, scripted_responses: Array, response_cursor: Dictionary) -> void:
	var events: Array[DomainEvent] = []
	for path_index: int in path.size():
		var origin := _session._state.party.coordinate
		var destination := path[path_index]
		var result := _session.submit_intent(PlayerIntent.move(destination - origin))
		result = _drain_interactions(result, events, step_id, scripted_responses, response_cursor)
		if result.state == SessionStep.State.FAILED:
			_fail("%s topology traversal failed with %s: %s" % [step_id, result.error_code, result.error_message])
			break
		if path_index + 1 < path.size() and (_session._state.party.map_id != trigger.map_id or _session._state.party.coordinate != destination):
			_fail("%s topology traversal left its expected path before the target trigger" % step_id)
			break
	if not _contains_trigger_event(events, trigger.id):
		_fail("%s topology traversal did not fire trigger %s" % [step_id, trigger.id])
	_validate_scripted_responses(step_id, scripted_responses, response_cursor)
	_validate_step_events(step_id, step_definition, events)
	_stage(step_id, failure_count, {"entryMode": "topology-traversal", "movementSteps": path.size()})


func _contains_trigger_event(events: Array[DomainEvent], trigger_id: String) -> bool:
	for event: DomainEvent in events:
		if event.kind == &"trigger_fired" and event.payload.get("triggerId") == trigger_id:
			return true
	return false


func _run_program_step(step_id: String, step_definition: Dictionary, trigger: TriggerDefinition, failure_count: int, scripted_responses: Array, response_cursor: Dictionary) -> void:
	var position: Variant = step_definition.get("position", {})
	if not position is Dictionary:
		_fail("%s has no source position" % step_id)
		_stage(step_id, failure_count)
		return
	var map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
	var coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
	if map == null or map.topology.cell_at(coordinate) == null:
		_fail("%s source position is outside authoritative topology" % step_id)
		_stage(step_id, failure_count)
		return
	_session._state.party.map_id = map.id
	_session._state.party.coordinate = coordinate
	_session._state.world.mark_visited(map.id, coordinate)
	var events: Array[DomainEvent] = [DomainEvent.new(&"trigger_fired", {"triggerId": trigger.id, "source": "route-program"})]
	var execution_context := ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, coordinate, true)
	var started := _session._scenario_vm.start_program(trigger.program_id, execution_context)
	var result: SessionStep
	if started.state == ScenarioVmResult.State.FAILED:
		result = SessionStep.failed(0, started.error_code, started.error_message, events)
	else:
		var vm_result := _session._scenario_vm.run(_session._runtime_api)
		events.append_array(vm_result.events)
		if vm_result.state == ScenarioVmResult.State.FAILED:
			result = SessionStep.failed(0, vm_result.error_code, vm_result.error_message, events)
		elif vm_result.state == ScenarioVmResult.State.WAITING:
			result = SessionStep.waiting(0, vm_result.interaction, events)
		else:
			result = SessionStep.completed(0, events)
	var observed_events: Array[DomainEvent] = []
	result = _drain_interactions(result, observed_events, step_id, scripted_responses, response_cursor)
	if result.state == SessionStep.State.FAILED:
		_fail("%s failed with %s: %s" % [step_id, result.error_code, result.error_message])
	_validate_scripted_responses(step_id, scripted_responses, response_cursor)
	_validate_step_events(step_id, step_definition, observed_events)
	_stage(step_id, failure_count, {"entryMode": "program-checkpoint"})


func _drain_interactions(step: SessionStep, events: Array[DomainEvent], step_id: String, scripted_responses: Array = [], response_cursor: Dictionary = {}) -> SessionStep:
	var guard := 2_048
	var current := step
	while guard > 0:
		events.append_array(current.events)
		if current.state != SessionStep.State.WAITING_FOR_INTERACTION:
			return current
		var answered_kind := current.interaction.kind
		var response := _scripted_response(current.interaction, scripted_responses, response_cursor)
		var used_scripted_response := response != null
		if response == null:
			response = _default_response(current.interaction, step_id)
		if response == null:
			return SessionStep.failed(current.view_revision, &"unsupported_route_interaction", "Route harness cannot answer %s." % current.interaction.kind)
		current = _session.respond(response)
		if current.state == SessionStep.State.FAILED:
			current.error_message += " after %s route response%s" % [answered_kind, " (scripted)" if used_scripted_response else ""]
		guard -= 1
	return SessionStep.failed(current.view_revision, &"route_step_limit", "Route step exceeded 2,048 typed interaction responses.")


func _scripted_response(request: InteractionRequest, responses: Array, cursor: Dictionary) -> InteractionResponse:
	var index := int(cursor.get("index", 0))
	if request == null or index >= responses.size() or not responses[index] is Dictionary:
		return null
	var definition: Dictionary = responses[index]
	if StringName(definition.get("kind", "")) != request.kind or not definition.get("data", {}) is Dictionary:
		return null
	var data: Dictionary = _normalize_route_response_data(definition["data"])
	if request.kind == InteractionRequest.PICK_LOCK and data.get("frameIndex") == "first-success":
		var body := request.body as InteractionRequest.PickLockRequestBody
		if body == null:
			return null
		data["frameIndex"] = _first_successful_pick_lock_frame(body)
	cursor["index"] = index + 1
	var response := InteractionResponse.from_data(request.request_id, request.kind, data)
	if response == null:
		printerr("ROUTE_SCRIPT_REJECTED %s %s" % [request.kind, CanonicalJson.encode(data)])
	return response


func _validate_scripted_responses(step_id: String, responses: Array, cursor: Dictionary) -> void:
	var consumed := int(cursor.get("index", 0))
	if consumed != responses.size():
		_fail("%s consumed %d of %d scripted responses" % [step_id, consumed, responses.size()])


func _normalize_route_response_data(value: Variant) -> Variant:
	if value is float and value == floorf(value):
		return int(value)
	if value is Array:
		var values: Array = []
		for entry: Variant in value:
			values.append(_normalize_route_response_data(entry))
		return values
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _normalize_route_response_data(value[key])
		return result
	return value


func _first_successful_pick_lock_frame(body: InteractionRequest.PickLockRequestBody) -> int:
	for frame_index: int in body.frames.size():
		var succeeded := true
		for position: int in body.frames[frame_index]:
			if position < body.yellow_threshold:
				succeeded = false
				break
		if succeeded:
			return frame_index
	return body.frames.size() - 1


func _default_response(request: InteractionRequest, step_id: String) -> InteractionResponse:
	if request == null:
		return null
	match request.kind:
		&"combat_action":
			_force_victory()
			var combat_body := request.body as InteractionRequest.CombatRequestBody
			if combat_body == null:
				return null
			return InteractionResponse.from_data(request.request_id, request.kind, {"actorId": combat_body.actor_id, "action": "defend", "targetId": ""})
		&"acknowledge":
			return InteractionResponse.acknowledge(request)
		&"encounter_choice", &"scenario_choice":
			return InteractionResponse.indexed_choice(request, 0)
		&"yes_no":
			return InteractionResponse.yes_no(request, true)
		&"complex_encounter":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "choice", "slot": 0})
		&"shop_action", &"temple_action":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "leave"})
		&"bank_action":
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "leave", "amount": 0})
		&"ally_selection":
			var ally_body := request.body as InteractionRequest.SelectionRequestBody
			if ally_body == null:
				return null
			return InteractionResponse.from_data(request.request_id, request.kind, {"selectedIds": ally_body.selected_ids.duplicate()})
		&"treasure_distribution":
			var treasure_body := request.body as InteractionRequest.TreasureRequestBody
			if treasure_body == null:
				return null
			if treasure_body.mode == &"completion-confirmation":
				return InteractionResponse.from_data(request.request_id, request.kind, {"action": "confirm-completion"})
			if treasure_body.mode == &"fumbled-item-recovery" and treasure_body.item != null:
				return InteractionResponse.from_data(request.request_id, request.kind, {"action": "discard", "instanceId": treasure_body.item.instance_id})
			return InteractionResponse.from_data(request.request_id, request.kind, {"action": "done"})
		&"level_up":
			var level_body := request.body as InteractionRequest.LevelUpRequestBody
			if level_body == null:
				return null
			return InteractionResponse.from_data(request.request_id, request.kind, {
				"action": "continue" if level_body.mode == &"result" else "confirm-spells",
				"characterId": level_body.character_id,
				"spellIds": [],
			})
	_fail("%s yielded unsupported interaction %s" % [step_id, request.kind])
	return null


func _force_victory() -> void:
	var combat := _session._state.combat
	if combat == null:
		return
	for monster: MonsterState in combat.monsters():
		if monster.traitor:
			monster.current_health = 0


func _validate_step_position(step_id: String, position: Variant, trigger: TriggerDefinition) -> void:
	if not position is Dictionary:
		_fail("%s has no source position" % step_id)
		return
	var map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
	var coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
	if map == null or map.id != trigger.map_id or coordinate != trigger.coordinate:
		_fail("%s position does not match trigger %s" % [step_id, trigger.id])


func _validate_step_events(step_id: String, step_definition: Dictionary, events: Array[DomainEvent]) -> void:
	var observed_messages: Array[int] = []
	var observed_pictures: Array[int] = []
	var observed_step_battles: Array[int] = []
	for event: DomainEvent in events:
		if event.kind == &"message_shown":
			observed_messages.append(int(event.payload.get("messageId", -1)))
		elif event.kind == &"picture_requested":
			observed_pictures.append(int(event.payload.get("pictureId", -1)))
		elif event.kind == &"battle_started":
			var battle_id := int(event.payload.get("classicId", -1))
			observed_step_battles.append(battle_id)
			_observed_battles.append(battle_id)
		elif event.kind == &"battle_completed" and event.payload.get("outcome") != "victory":
			_fail("%s completed battle with outcome %s" % [step_id, event.payload.get("outcome")])
	var expected_messages := _expected_message_ids(step_definition)
	if not _contains_subsequence(observed_messages, expected_messages):
		_fail("%s message sequence differs: expected %s, observed %s" % [step_id, expected_messages, observed_messages])
	if step_definition.has("picture"):
		var picture: Variant = step_definition["picture"]
		if not picture is Dictionary or not observed_pictures.has(int(picture.get("id", -1))):
			_fail("%s did not publish its expected picture" % step_id)
	if step_definition.has("battleId") and not observed_step_battles.has(int(step_definition["battleId"])):
		_fail("%s did not start Classic battle %d" % [step_id, int(step_definition["battleId"])])


func _expected_message_ids(step_definition: Dictionary) -> Array[int]:
	var expected: Array[int] = []
	for field: String in ["messages", "sequence", "postVictory"]:
		for entry: Variant in step_definition.get(field, []):
			if entry is Dictionary and (field == "messages" or entry.get("kind") == "message"):
				var message_id := int(entry.get("id", -1))
				if message_id >= 0 and not expected.has(message_id):
					expected.append(message_id)
	return expected


func _contains_subsequence(observed: Array[int], expected: Array[int]) -> bool:
	var cursor := 0
	for value: int in observed:
		if cursor < expected.size() and value == expected[cursor]:
			cursor += 1
	return cursor == expected.size()


func _validate_completion(anchor: Variant) -> void:
	var failure_count := _failures.size()
	if not anchor is Dictionary or not anchor.get("runtime") is Dictionary:
		_fail("route has no completion runtime anchor")
		_stage("completion-runtime", failure_count)
		return
	var expected: Dictionary = anchor["runtime"]
	for quest_id: Variant in expected.get("questFlags", []):
		if not _session._state.quest_is_set(int(quest_id)):
			_fail("completion quest %d is not set" % int(quest_id))
	for override: Variant in expected.get("tileOverrides", []):
		if not override is Dictionary:
			_fail("completion tile override is malformed")
			continue
		var map := _content.world.map_by_type_and_index(StringName(override.get("levelType", "")), int(override.get("levelIndex", -1)))
		var coordinate := Vector2i(int(override.get("x", -1)), int(override.get("y", -1)))
		var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
		var terrain := "" if cell == null else _session._state.world.terrain_for(map.id, cell)
		if terrain != "classic.terrain.%d" % int(override.get("value", -1)):
			_fail("completion tile %s %s has terrain %s" % [map.id if map != null else "unknown", coordinate, terrain])
	var item_ids := _party_classic_item_ids()
	for item_id: Variant in expected.get("itemIds", []):
		if not item_ids.has(int(item_id)):
			_fail("completion reward item %d is absent" % int(item_id))
	var position: Variant = expected.get("position", {})
	if position is Dictionary:
		var expected_map := _content.world.map_by_type_and_index(StringName(position.get("levelType", "")), int(position.get("levelIndex", -1)))
		var expected_coordinate := Vector2i(int(position.get("x", -1)), int(position.get("y", -1)))
		if expected_map == null or _session._state.party.map_id != expected_map.id or _session._state.party.coordinate != expected_coordinate:
			_fail("completion position does not match the route anchor")
	_stage("completion-runtime", failure_count)


func _party_classic_item_ids() -> Array[int]:
	var result: Array[int] = []
	for character: CharacterState in _session._state.party.characters():
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null and not result.has(definition.classic_id):
				result.append(definition.classic_id)
	result.sort()
	return result


func _final_state() -> Dictionary:
	return {
		"mapId": _session._state.party.map_id,
		"x": _session._state.party.coordinate.x,
		"y": _session._state.party.coordinate.y,
		"questFlags": _set_quest_ids(),
		"itemIds": _party_classic_item_ids(),
		"world": _session._state.world.to_data(),
	}


func _set_quest_ids() -> Array[int]:
	var result: Array[int] = []
	for quest_id: int in 100:
		if _session._state.quest_is_set(quest_id):
			result.append(quest_id)
	return result


func _stage(stage_id: String, failure_count: int, evidence: Dictionary = {}) -> void:
	var stage := {"id": stage_id, "status": "passed" if _failures.size() == failure_count else "failed"}
	for key: Variant in evidence:
		stage[key] = evidence[key]
	_stages.append(stage)


func _fail(message: String) -> void:
	_failures.append(message)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else null


func _write_report(path: String, report: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(CanonicalJson.encode(report) + "\n")
	return true


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
