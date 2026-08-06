class_name GameSession
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _scenario_vm: ScenarioVm
var _scenario_action_state: ScenarioActionState
var _runtime_api: RealmzRuntimeApi
var _session_continuation: Dictionary = {}
var _session_interaction: InteractionRequest
var _started: bool = false
var _view_revision: int = 0


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, &"session_already_started", "The session has already started.")
	if content == null or content.scenario == null:
		return SessionStep.failed(_view_revision, &"invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_start_location", "The package start location is unavailable.")
	var starting_characters: Array[CharacterState] = [CharacterState.new("party.starting.adventurer", "Adventurer", 10, 10)]
	var game_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	game_state.world.mark_visited(content.start_map_id, content.start_coordinate)
	var random_source := RealmzRng.new(initial_seed)
	var action_state := ScenarioActionState.new()
	var scenario_vm := ScenarioVm.new()
	scenario_vm.configure(content.scenario)
	_content = content
	_state = game_state
	_rng = random_source
	_rules = RealmzRules.new()
	_scenario_action_state = action_state
	_scenario_vm = scenario_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	_session_continuation.clear()
	_session_interaction = null
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SaveEnvelope) -> SessionStep:
	if content == null or content.scenario == null or save_envelope == null:
		return SessionStep.failed(_view_revision, &"invalid_restore", "Validated content and save data are required.")
	if save_envelope.campaign_id != content.campaign_id or save_envelope.package_hash != content.package_hash:
		return SessionStep.failed(_view_revision, &"package_mismatch", "The save belongs to a different package build.")
	if save_envelope.rules_version != content.rules_version:
		return SessionStep.failed(_view_revision, &"rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(save_envelope.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(save_envelope.game_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(save_envelope.rng_state):
		return SessionStep.failed(_view_revision, &"invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(save_envelope.game_state.to_data())
	var replacement_action_state := ScenarioActionState.from_data(save_envelope.scenario_action_state.to_data())
	if replacement_state == null or replacement_action_state == null:
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved game or Scenario Action state is invalid.")
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(save_envelope.scenario_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM state is invalid.")
	var replacement_continuation := save_envelope.session_continuation.duplicate(true)
	var replacement_session_interaction: InteractionRequest = null
	if save_envelope.session_interaction != null:
		replacement_session_interaction = InteractionRequest.from_data(save_envelope.session_interaction.to_data())
		if replacement_session_interaction == null:
			return SessionStep.failed(_view_revision, &"invalid_session_interaction", "The saved session interaction is invalid.")
	if not replacement_continuation.is_empty() and not _valid_session_continuation(content, replacement_state, replacement_continuation, replacement_vm.pending_request(), replacement_session_interaction):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The saved session continuation is invalid.")
	if replacement_continuation.is_empty() and replacement_session_interaction != null:
		return SessionStep.failed(_view_revision, &"invalid_session_interaction", "The saved session interaction has no owning continuation.")
	_content = content
	_state = replacement_state
	_rng = replacement_rng
	_rules = RealmzRules.new()
	_scenario_action_state = replacement_action_state
	_scenario_vm = replacement_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	_session_continuation = replacement_continuation
	_session_interaction = replacement_session_interaction
	_view_revision = save_envelope.view_revision
	_started = true
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_restored")])


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	if _pending_interaction() != null or _scenario_vm.is_active():
		return SessionStep.failed(_view_revision, &"interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, &"invalid_intent", "A typed player intent is required.")
	if _state.combat != null and not _state.combat.completed and intent.kind not in [PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.CHOOSE_COMBAT_ACTION]:
		return SessionStep.failed(_view_revision, &"battle_in_progress", "Resolve the active battle before returning to exploration.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			return _move(intent.direction)
		PlayerIntent.Kind.SEARCH:
			return _search()
		PlayerIntent.Kind.CAMP:
			return _camp()
		PlayerIntent.Kind.USE_ITEM:
			return _use_item(intent.target_id)
		PlayerIntent.Kind.CAST_SPELL:
			return _cast_spell(intent)
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			return _combat_action(intent)
		PlayerIntent.Kind.CREATE_PARTY:
			return _create_party(intent.party_members)
		_:
			return SessionStep.failed(_view_revision, &"intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func respond(response: InteractionResponse) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	var pending := _pending_interaction()
	if pending == null:
		return SessionStep.failed(_view_revision, &"no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != pending.request_id:
		return SessionStep.failed(_view_revision, &"interaction_mismatch", "The response does not match the pending request.")
	if _session_interaction != null:
		return _respond_session_interaction(response)
	var result := _scenario_vm.resume(response, _runtime_api)
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if not _session_continuation.is_empty():
		return _continue_post_move(events)
	return _finish_completed(events)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, null)
	var members: Array[CharacterView] = []
	for character: CharacterState in _state.party.characters():
		members.append(CharacterView.new(character, _content))
	var current_combat := CombatView.new(_state.combat) if _state.combat != null else null
	var result := GameView.new(_view_revision, true, _pending_interaction(), _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _build_map_view(), members, _state.party.fatigue, _state.party.pooled_wealth.gold, current_combat)
	result.campaign_id = _content.campaign_id
	result.rules_version = _content.rules_version
	result.party_setup_available = not _state.party_setup_completed and _view_revision == 1 and _pending_interaction() == null
	for race: RaceDefinition in _content.race_definitions():
		result.race_options.append(DefinitionOptionView.new(race.id, race.name))
	for caste: CasteDefinition in _content.caste_definitions():
		result.caste_options.append(DefinitionOptionView.new(caste.id, caste.name))
	return result


func snapshot() -> SaveEnvelope:
	if not _started or (_scenario_vm.is_active() and _scenario_vm.pending_request() == null):
		return null
	var envelope := SaveEnvelope.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, _state, _rng.snapshot(), _scenario_vm.snapshot(), _scenario_action_state, _session_continuation, _session_interaction)
	return SaveEnvelope.from_data(envelope.to_data())


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _scenario_vm == null else _scenario_vm.trace()


func _camp() -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"camp_during_battle", "The party cannot camp during battle.")
	if not _state.camping_allowed:
		return SessionStep.failed(_view_revision, &"camping_disabled", "Camping is not allowed at this location.")
	return _finish_completed(_rules.clock.camp(_state))


func _use_item(instance_id: String) -> SessionStep:
	if instance_id.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_item", "Use Item requires a stable item instance ID.")
	for character: CharacterState in _state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.id != instance_id:
				continue
			var definition := _content.item_by_id(instance.definition_id)
			if definition == null:
				return SessionStep.failed(_view_revision, &"unknown_item", "The item definition is unavailable.")
			if not _rules.inventory.use_charge(character, instance.id, definition):
				return SessionStep.failed(_view_revision, &"item_unusable", "The item has no usable charge.")
			return _finish_completed([DomainEvent.new(&"item_used", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "remainingCharges": maxi(0, instance.charges)})])
	return SessionStep.failed(_view_revision, &"unknown_item_instance", "The party does not possess item instance '%s'." % instance_id)


func _cast_spell(intent: PlayerIntent) -> SessionStep:
	var result := _rules.combat_flow.cast_spell(_state, _content, intent.actor_id, intent.secondary_target_id, intent.target_id, intent.power_level, _rng)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	return _finish_completed(result.events)


func _combat_action(intent: PlayerIntent) -> SessionStep:
	var result := _rules.combat_flow.submit_action(_state, _content, intent.actor_id, intent.action, intent.target_id, _rng)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	return _finish_completed(result.events)


func _create_party(specs: Array[CharacterCreationSpec]) -> SessionStep:
	if _state.party_setup_completed or _view_revision != 1 or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party creation is available only at a fresh campaign start.")
	if specs.is_empty() or specs.size() > 6:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "A Realmz party requires one through six characters.")
	var created: Array[CharacterState] = []
	var names: Dictionary = {}
	for index: int in specs.size():
		var spec: CharacterCreationSpec = specs[index]
		if spec == null or spec.name.is_empty() or spec.name.length() > 24 or spec.gender not in [1, 2]:
			return SessionStep.failed(_view_revision, &"invalid_character_spec", "Every party member requires a valid name and gender.")
		var name_key := spec.name.to_lower()
		if names.has(name_key):
			return SessionStep.failed(_view_revision, &"duplicate_character_name", "Party member names must be unique.")
		var race := _content.race_by_id(spec.race_id)
		var caste := _content.caste_by_id(spec.caste_id)
		if race == null or caste == null:
			return SessionStep.failed(_view_revision, &"unknown_character_definition", "Party creation references an unavailable race or caste.")
		names[name_key] = true
		var character := _rules.characters.create_character("party.character.%d" % (index + 1), spec.name, race, caste, spec.gender, _rng)
		if character == null:
			return SessionStep.failed(_view_revision, &"character_creation_failed", "Realmz rules rejected a party member.")
		created.append(character)
	var replacement := PartyState.new(_state.party.map_id, _state.party.coordinate, created)
	_state.party = replacement
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in created:
		character_ids.append(character.id)
	return _finish_completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _search() -> SessionStep:
	_state.mark_searched(_state.party.map_id, _state.party.coordinate)
	var current_map := _content.world.map_by_id(_state.party.map_id)
	var discovered: Array[String] = []
	var first_roll: int = 0
	for cell: MapCell in current_map.topology.cells():
		if absi(cell.coordinate.x - _state.party.coordinate.x) > 1 or absi(cell.coordinate.y - _state.party.coordinate.y) > 1:
			continue
		for feature: MapFeature in cell.features():
			if feature.kind != &"secret" or _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
				continue
			var roll := _rng.draw(100, StringName("exploration.search.%s" % feature.id))
			if first_roll == 0:
				first_roll = roll
			if roll <= 100:
				_state.world.discover_secret(feature.id)
				discovered.append(feature.id)
	_state.clock.advance_minutes(1)
	var events: Array[DomainEvent] = [DomainEvent.new("search_completed", {"mapId": _state.party.map_id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	for secret_id: String in discovered:
		events.append(DomainEvent.new("secret_discovered", {"secretId": secret_id}))
	return _finish_completed(events)


func _move(direction: Vector2i) -> SessionStep:
	if direction not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires one cardinal direction.")
	var source_map := _content.world.map_by_id(_state.party.map_id)
	var target_map := source_map
	var target_coordinate := _state.party.coordinate + direction
	var transition: MapTransition = null
	if not source_map.topology.contains(target_coordinate):
		transition = _content.world.transition_from(source_map.id, MapTopology.direction_name(direction))
		if transition == null:
			return _movement_blocked(&"map_boundary")
		target_map = _content.world.map_by_id(transition.target_map_id)
		target_coordinate = _content.world.transition_target_coordinate(transition, _state.party.coordinate)
	var probe := target_map.topology.probe_entry(target_coordinate, direction, _state.world)
	if not probe.allowed:
		return _movement_blocked(probe.reason)
	var events: Array[DomainEvent] = []
	if not probe.door_id.is_empty() and not _state.world.door_is_open(probe.door_id):
		_state.world.open_door(probe.door_id)
		events.append(DomainEvent.new("door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not _state.world.secret_is_discovered(probe.secret_id):
		_state.world.discover_secret(probe.secret_id)
		events.append(DomainEvent.new("secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := _state.party.map_id
	var source_coordinate := _state.party.coordinate
	_state.party.map_id = target_map.id
	_state.party.coordinate = target_coordinate
	_state.world.mark_visited(target_map.id, target_coordinate)
	_state.clock.advance_minutes(probe.target_cell.movement_cost)
	events.append(DomainEvent.new("party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	if transition != null:
		events.append(DomainEvent.new("map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	_session_continuation = {
		"kind": "post-move",
		"mapId": target_map.id,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"triggerIds": probe.target_cell.trigger_ids(),
		"triggerIndex": 0,
		"activeTriggerId": "",
		"randomRegionIds": probe.target_cell.random_rect_ids(),
		"randomRegionIndex": probe.target_cell.random_rect_ids().size() - 1,
		"activeRandomProgramId": "",
		"activeRandomRegionId": "",
		"randomBattleStage": "",
	}
	return _continue_post_move(events)


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	var coordinate := Vector2i(int(_session_continuation.get("x", -1)), int(_session_continuation.get("y", -1)))
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_random_program_id := String(_session_continuation.get("activeRandomProgramId", ""))
	if not active_random_program_id.is_empty():
		_session_continuation.clear()
		return _finish_completed(events)
	var active_trigger_id := String(_session_continuation.get("activeTriggerId", ""))
	if not active_trigger_id.is_empty():
		var completed_trigger := _content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_apply_trigger_replacement(map, completed_trigger, events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = int(_session_continuation["triggerIndex"]) + 1
	var trigger_ids: Array = _session_continuation["triggerIds"]
	while int(_session_continuation["triggerIndex"]) < trigger_ids.size():
		var trigger_index: int = int(_session_continuation["triggerIndex"])
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger := _content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _state.world.trigger_is_disabled(trigger_id):
			_session_continuation["triggerIndex"] = trigger_index + 1
			continue
		var trigger_chance := _state.world.trigger_chance(trigger.id, trigger.chance_percent)
		if trigger_chance < 0:
			_session_continuation["triggerIndex"] = trigger_index + 1
			continue
		if trigger_chance < 100:
			var chance_roll := _rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger_chance:
				_session_continuation["triggerIndex"] = trigger_index + 1
				continue
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		_session_continuation["activeTriggerId"] = trigger.id
		var started := _scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})
		if started.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(started.error_code, started.error_message, events)
		var result := _scenario_vm.run(_runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.WAITING:
			return _finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(result.error_code, result.error_message, events)
		_apply_trigger_replacement(map, trigger, events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = trigger_index + 1
	var random_step := _continue_random_regions(map, events)
	if random_step != null:
		return random_step
	_session_continuation.clear()
	return _finish_completed(events)


func _apply_trigger_replacement(map: MapDefinition, trigger: TriggerDefinition, events: Array[DomainEvent]) -> void:
	if trigger.replacement == null or not trigger.replacement.changes_terrain():
		return
	var replacement_cell := map.topology.cell_at(trigger.replacement.target_coordinate)
	if replacement_cell == null:
		return
	var terrain_id := "classic.terrain.%d" % trigger.replacement.terrain_id
	_state.world.replace_terrain(map.id, replacement_cell.coordinate, terrain_id)
	events.append(DomainEvent.new("tile_replaced", {"mapId": map.id, "x": replacement_cell.coordinate.x, "y": replacement_cell.coordinate.y, "terrainId": terrain_id}))


func _movement_blocked(reason: StringName) -> SessionStep:
	return _finish_completed([DomainEvent.new("movement_blocked", {"reason": String(reason)})])


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionStep:
	if not _state.random_encounters_enabled:
		return null
	var region_ids: Array = _session_continuation["randomRegionIds"]
	while int(_session_continuation["randomRegionIndex"]) >= 0:
		var region_index: int = int(_session_continuation["randomRegionIndex"])
		var region_id: String = String(region_ids[region_index])
		var region := map.random_region_by_id(region_id)
		if region == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Random-region continuation references unavailable content.", events)
		var effective := _state.world.random_region(region)
		var roll := _rng.draw(10_000, StringName("random-region.%s" % region.id))
		var triggered := roll <= effective.chance_ten_thousand
		events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chanceTenThousand": effective.chance_ten_thousand, "triggered": triggered}))
		if triggered:
			events.append(DomainEvent.new(&"random_region_triggered", {"regionId": region.id}))
			var door_ids := region.random_doors()
			var door_percents := effective.random_door_percents()
			for door_index: int in door_ids.size():
				var door_roll := _rng.draw(100, StringName("random-region.%s.door.%d" % [region.id, door_index]))
				var door_fired := door_roll <= absi(door_percents[door_index])
				events.append(DomainEvent.new(&"random_door_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_ids[door_index], "roll": door_roll, "chancePercent": door_percents[door_index], "triggered": door_fired}))
				if not door_fired:
					continue
				effective.consume_random_door(door_index)
				_state.world.set_random_region(effective)
				var program_id := "xap:%d" % door_ids[door_index]
				_session_continuation["activeRandomProgramId"] = program_id
				events.append(DomainEvent.new(&"random_door_triggered", {"regionId": region.id, "programId": program_id, "oneShot": door_percents[door_index] > 0}))
				var started := _scenario_vm.start_program(program_id, {"callingContext": "action", "mapId": map.id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "randomRegionId": region.id})
				if started.state == ScenarioVmResult.State.FAILED:
					_session_continuation.clear()
					return _finish_failed(started.error_code, started.error_message, events)
				var result := _scenario_vm.run(_runtime_api)
				events.append_array(result.events)
				if result.state == ScenarioVmResult.State.WAITING:
					return _finish_waiting(result.interaction, events)
				if result.state == ScenarioVmResult.State.FAILED:
					_session_continuation.clear()
					return _finish_failed(result.error_code, result.error_message, events)
				_session_continuation.clear()
				return _finish_completed(events)
			if effective.battle_minimum != 0 and not _state.party.conditions.is_active(7):
				var good_surprise_roll := _rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
				if good_surprise_roll < region.option:
					var message := _content.message_by_id(absi(region.text_id))
					var prompt := message.text if message != null else "Take the advantage and enter battle?"
					_session_continuation["activeRandomRegionId"] = region.id
					_session_continuation["randomBattleStage"] = "surprise-choice"
					var request_id := "random-surprise:%s:%d" % [region.id, _rng.snapshot().draw_count]
					_session_interaction = InteractionRequest.new(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
					if region.sound_id > 0:
						events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
					return _finish_waiting(_session_interaction, events)
				var bad_surprise_roll := _rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
				var surprise := -1 if bad_surprise_roll < 10 else 0
				return _start_random_battle(region, surprise, events)
		_session_continuation["randomRegionIndex"] = region_index - 1
		if region.only:
			break
	return null


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.completed(_view_revision, events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.waiting(_view_revision, request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.failed(_view_revision, code, message, events)


func _pending_interaction() -> InteractionRequest:
	return _session_interaction if _session_interaction != null else _scenario_vm.pending_request()


func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	if response.kind != &"yes_no" or not response.payload.has("accepted") or not response.payload["accepted"] is bool:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "The random encounter response must be a yes/no choice.")
	if _session_continuation.get("randomBattleStage", "") != "surprise-choice":
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice has no matching continuation.")
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	var region_id := String(_session_continuation.get("activeRandomRegionId", ""))
	var region: RandomEncounterRegion = null if map == null else map.random_region_by_id(region_id)
	if region == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice references unavailable content.")
	_session_interaction = null
	_session_continuation["activeRandomRegionId"] = ""
	_session_continuation["randomBattleStage"] = ""
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": response.payload["accepted"]})]
	if response.payload["accepted"]:
		return _start_random_battle(region, 1, events)
	_session_continuation["randomRegionIndex"] = int(_session_continuation["randomRegionIndex"]) - 1
	if region.only:
		_session_continuation.clear()
		return _finish_completed(events)
	var next_step := _continue_random_regions(map, events)
	if next_step != null:
		return next_step
	_session_continuation.clear()
	return _finish_completed(events)


func _start_random_battle(region: RandomEncounterRegion, surprise: int, events: Array[DomainEvent]) -> SessionStep:
	var effective := _state.world.random_region(region)
	if effective.battle_maximum < effective.battle_minimum:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(&"invalid_random_battle_range", "Random rectangle '%s' has an inverted battle range." % region.id, events)
	var battle_id := _rng.draw_between(effective.battle_minimum, effective.battle_maximum, StringName("random-region.%s.battle" % region.id))
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(&"unknown_random_battle", "Random rectangle '%s' selected unavailable battle %d." % [region.id, battle_id], events)
	events.append(DomainEvent.new(&"random_encounter_triggered", {"regionId": region.id, "battleId": battle.id, "classicId": battle_id, "textId": region.text_id, "soundId": region.sound_id, "surprise": surprise}))
	var battle_result := _rules.combat_flow.start_battle(_state, _content, battle, _rng, surprise)
	if not battle_result.ok:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(battle_result.error_code, battle_result.error_message, events)
	events.append_array(battle_result.events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_completed(events)


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: Dictionary, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage"]
	if continuation.size() != fields.size():
		return false
	for field: String in fields:
		if not continuation.has(field):
			return false
	if continuation["kind"] != "post-move" or not continuation["mapId"] is String or not continuation["x"] is int or not continuation["y"] is int or not continuation["triggerIds"] is Array or not continuation["triggerIndex"] is int or not continuation["activeTriggerId"] is String or not continuation["randomRegionIds"] is Array or not continuation["randomRegionIndex"] is int or not continuation["activeRandomProgramId"] is String or not continuation["activeRandomRegionId"] is String or not continuation["randomBattleStage"] is String:
		return false
	var map := content.world.map_by_id(continuation["mapId"])
	var coordinate := Vector2i(continuation["x"], continuation["y"])
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != coordinate or continuation["triggerIds"] != cell.trigger_ids() or continuation["randomRegionIds"] != cell.random_rect_ids():
		return false
	var random_index: int = continuation["randomRegionIndex"]
	if random_index < -1 or random_index >= continuation["randomRegionIds"].size():
		return false
	if session_interaction != null:
		if vm_interaction != null or continuation["activeTriggerId"] != "" or continuation["activeRandomProgramId"] != "" or continuation["randomBattleStage"] != "surprise-choice" or session_interaction.kind != &"yes_no":
			return false
		var active_region_id: String = continuation["activeRandomRegionId"]
		return random_index >= 0 and continuation["randomRegionIds"][random_index] == active_region_id and map.random_region_by_id(active_region_id) != null
	if vm_interaction == null or continuation["randomBattleStage"] != "" or continuation["activeRandomRegionId"] != "":
		return false
	if not continuation["activeRandomProgramId"].is_empty():
		return continuation["activeTriggerId"].is_empty() and content.scenario.program_by_id(continuation["activeRandomProgramId"]) != null
	var index: int = continuation["triggerIndex"]
	if index < 0 or index >= continuation["triggerIds"].size() or continuation["activeTriggerId"].is_empty() or continuation["triggerIds"][index] != continuation["activeTriggerId"]:
		return false
	return content.trigger_by_id(continuation["activeTriggerId"]) != null


func _build_map_view() -> MapView:
	var map := _content.world.map_by_id(_state.party.map_id)
	var visible_coordinates := map.topology.visible_cells(_state.party.coordinate, 8, _state.world, map.uses_los)
	var visible: Dictionary = {}
	for coordinate: Vector2i in visible_coordinates:
		visible[coordinate] = true
	var cells: Array[MapCellView] = []
	for cell: MapCell in map.topology.cells():
		var feature_kinds: Array[StringName] = []
		var edge_kinds: Dictionary = {}
		var edge_passability: Dictionary = {}
		for direction: StringName in [&"north", &"east", &"south", &"west"]:
			var edge := cell.edge(direction)
			edge_kinds[direction] = edge.kind
			edge_passability[direction] = edge.passable
		var hidden_secret := false
		for feature: MapFeature in cell.features():
			if feature.kind == &"secret" and not _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
				hidden_secret = true
				continue
			if not feature_kinds.has(feature.kind):
				feature_kinds.append(feature.kind)
		var can_enter := cell.passable and not hidden_secret
		cells.append(MapCellView.new(cell.coordinate, _state.world.terrain_for(map.id, cell), can_enter, cell.blocks_los, visible.has(cell.coordinate), _state.world.was_visited(map.id, cell.coordinate), not hidden_secret and not cell.trigger_ids().is_empty(), not cell.random_rect_ids().is_empty(), feature_kinds, edge_kinds, edge_passability))
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, _state.party.coordinate, cells)
