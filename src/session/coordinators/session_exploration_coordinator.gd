class_name SessionExplorationCoordinator
extends RefCounted

var _context: SessionCoordinatorContext


func _init(context: SessionCoordinatorContext) -> void:
	_context = context


func begin_contextual_encounter() -> SessionCoordinatorResult:
	if _context.state.combat != null and not _context.state.combat.completed:
		return _context.failed(&"encounter_during_battle", "The seamless Encounter command is unavailable during battle.")
	var map := _context.content.world.map_by_id(_context.state.party.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(_context.state.party.coordinate)
	if cell == null:
		return _context.failed(&"unknown_map", "The current map is unavailable for Encounter.")
	var selected_program_id := ""
	var selected_region_id := ""
	var events: Array[DomainEvent] = []
	var region_ids := cell.random_rect_ids()
	for offset: int in region_ids.size():
		var region_id: String = region_ids[region_ids.size() - 1 - offset]
		var region := map.random_region_by_id(region_id)
		if region == null:
			return _context.failed(&"invalid_random_region", "Encounter references an unavailable random rectangle.", events)
		var effective := _context.state.world.random_region(region)
		if effective.chance_ten_thousand >= 0:
			continue
		var door_ids := region.random_doors()
		var door_percents := effective.random_door_percents()
		for door_index: int in mini(door_ids.size(), door_percents.size()):
			var door_id := door_ids[door_index]
			var percent := door_percents[door_index]
			if door_id == 0 or percent == 0:
				continue
			var roll := _context.rng.draw(100, StringName("contextual-encounter.%s.door.%d" % [region.id, door_index]))
			var fired := roll <= absi(percent)
			events.append(DomainEvent.new(&"contextual_encounter_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_id, "roll": roll, "chancePercent": percent, "triggered": fired}))
			if not fired:
				continue
			effective.consume_random_door(door_index)
			_context.state.world.set_random_region(effective)
			selected_program_id = "xap:%d" % door_id
			selected_region_id = region.id
	if selected_program_id.is_empty():
		events.append(DomainEvent.new(&"contextual_encounter_unavailable", {"mapId": map.id, "coordinate": _context.state.party.coordinate}))
		return _context.completed(events)
	if _context.content.scenario.program_by_id(selected_program_id) == null:
		return _context.failed(&"unknown_random_door_program", "Encounter selected unavailable program '%s'." % selected_program_id, events)
	_context.set_continuation(ExplorationTimeWorkflow.post_move_continuation(_context.workflow_context(), map, _context.state.party.coordinate))
	_context.session_continuation.exploration().active_random_program_id = selected_program_id
	events.append(DomainEvent.new(&"contextual_encounter_triggered", {"regionId": selected_region_id, "programId": selected_program_id}))
	var execution_context := ScenarioExecutionContext.trigger(&"action", "", map.id, _context.state.party.coordinate, true).set_random_region(selected_region_id)
	var started := _context.scenario_vm.start_program(selected_program_id, execution_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(started.error_code, started.error_message, events)
	var result := _context.scenario_vm.run(_context.runtime_api)
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _context.scenario()._begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _context.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return _context.failed(result.error_code, result.error_message, events)
	_context.session_continuation.clear()
	return _context.completed(events)

func _set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	_context.set_continuation(ExplorationTimeWorkflow.post_time_continuation(_context.workflow_context(), map, StringName(resume_kind), direction, check_random, timed_day, timed_coordinate))


func _continue_post_time(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var active_timed_program_id = exploration.active_timed_program_id
	if not active_timed_program_id.is_empty() and not _rebase_post_time_location():
		_context.session_continuation.clear()
		return _context.failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	var map = _context.content.world.map_by_id(exploration.map_id)
	if map == null or _context.state.party.map_id != map.id or _context.state.party.coordinate != exploration.coordinate:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	if not active_timed_program_id.is_empty():
		exploration.active_timed_program_id = ""
	var timed_step = _continue_timed_encounters(events)
	if timed_step != null:
		return timed_step
	map = _context.content.world.map_by_id(exploration.map_id)
	if map == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_timed_encounter_location", "Timed encounter continuation references an unavailable map.", events)
	var active_program_id = exploration.active_random_program_id
	if not active_program_id.is_empty():
		exploration.active_random_program_id = ""
		return _complete_post_time(events)
	if exploration.check_random and exploration.resume_kind != &"post-move":
		var random_step = _continue_random_regions(map, events)
		if random_step != null:
			return random_step
	return _complete_post_time(events)


func _complete_post_time(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var resume_kind = exploration.resume_kind
	var direction = exploration.direction
	_context.session_continuation.clear()
	if resume_kind == &"move":
		return _finish_exploration_movement(ExplorationTimeWorkflow.commit_move(_context.workflow_context(), direction, events))
	if resume_kind == &"post-move":
		var map = _context.content.world.map_by_id(_context.state.party.map_id)
		_set_post_move_continuation(map, _context.state.party.coordinate)
		return _continue_post_move(events)
	if resume_kind == &"completed":
		return _context.completed(events)
	return _context.failed(&"invalid_session_continuation", "Post-clock exploration continuation has no valid completion path.", events)


func _continue_timed_encounters(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		return _context.failed(&"invalid_session_continuation", "Timed encounters require a post-clock continuation.", events)
	var timed_day = exploration.timed_day
	if timed_day <= 0:
		return null
	var encounters = _context.content.timed_encounters()
	while exploration.timed_encounter_index < encounters.size():
		var index = exploration.timed_encounter_index
		var encounter = encounters[index]
		exploration.timed_encounter_index = index + 1
		var effective = _context.state.timed_encounter_override(encounter.id)
		var effective_day = int(effective.get("day", encounter.day))
		if effective_day != timed_day:
			continue
		var increment = int(effective.get("increment", encounter.increment))
		effective["day"] = effective_day + increment
		_context.state.set_timed_encounter_override(encounter.id, effective)
		events.append(DomainEvent.new(&"timed_encounter_advanced", {"encounterId": encounter.id, "day": effective_day, "nextDay": effective["day"], "source": "classic-midnight"}))
		var chance = int(effective.get("percent", encounter.chance_percent))
		var roll = _context.rng.draw(100, StringName("timed-encounter.%d" % encounter.id))
		var map = _context.content.world.map_by_id(_context.state.party.map_id)
		if map == null:
			_context.session_continuation.clear()
			return _context.failed(&"invalid_timed_encounter_location", "Timed encounter eligibility references an unavailable map.", events)
		var eligible = roll <= chance and _timed_encounter_requirements_met(encounter, map)
		events.append(DomainEvent.new(&"timed_encounter_checked", {"encounterId": encounter.id, "roll": roll, "chancePercent": chance, "eligible": eligible}))
		if not eligible:
			continue
		_apply_pending_midnight_recovery(events)
		if _context.content.scenario.program_by_id(encounter.program_id) == null:
			_context.session_continuation.clear()
			return _context.failed(&"unknown_timed_encounter_program", "Timed Encounter %d references unavailable XAP program '%s'." % [encounter.id, encounter.program_id], events)
		exploration.active_timed_program_id = encounter.program_id
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "classicMacroId": encounter.classic_macro_id, "programId": encounter.program_id}))
		var context = ScenarioExecutionContext.trigger(&"action", "", map.id, exploration.timed_check_coordinate, true).set_timed_encounter(encounter.id)
		var started = _context.scenario_vm.start_program(encounter.program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return _context.failed(started.error_code, started.error_message, events)
		var result = _context.scenario_vm.run(_context.runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _context.scenario()._begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			if not _rebase_post_time_location():
				_context.session_continuation.clear()
				return _context.failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
			return _context.waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return _context.failed(result.error_code, result.error_message, events)
		exploration.active_timed_program_id = ""
		if not _rebase_post_time_location():
			_context.session_continuation.clear()
			return _context.failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	_apply_pending_midnight_recovery(events)
	exploration.timed_day = 0
	return null


func _apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	ExplorationTimeWorkflow.apply_pending_midnight_recovery(_context.workflow_context(), _context.session_continuation.exploration(), events)


func _rebase_post_time_location() -> bool:
	return ExplorationTimeWorkflow.rebase_post_time_location(_context.workflow_context(), _context.session_continuation)


func _timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	return ExplorationTimeWorkflow.timed_encounter_requirements_met(_context.workflow_context(), encounter, map, _context.session_continuation.exploration())


func _set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	_context.set_continuation(ExplorationTimeWorkflow.post_move_continuation(_context.workflow_context(), map, coordinate, destination_depth))


func _continue_post_move(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-move" or exploration == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	if _context.events_have(events, &"destination_trigger_recheck_requested") and exploration.action_point_destination_depth == 0:
		var requested_map = _context.content.world.map_by_id(_context.state.party.map_id)
		if requested_map == null:
			_context.session_continuation.clear()
			return _context.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
		_set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
		exploration = _context.session_continuation.exploration()
	var map = _context.content.world.map_by_id(exploration.map_id)
	var coordinate = exploration.coordinate
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_context.session_continuation.clear()
		return _context.failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_random_program_id = exploration.active_random_program_id
	if not active_random_program_id.is_empty():
		_context.session_continuation.clear()
		return _context.completed(events)
	var active_trigger_id = exploration.active_trigger_id
	if not active_trigger_id.is_empty():
		var completed_trigger = _context.content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_context.session_continuation.clear()
			return _context.failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_context.scenario()._finalize_completed_trigger(completed_trigger, events)
		if _context.scenario()._apply_trigger_destination(completed_trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map = _context.content.world.map_by_id(_context.state.party.map_id)
			_set_post_move_continuation(destination_map, _context.state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = exploration.trigger_ids.size()
	var trigger_ids = exploration.trigger_ids
	while exploration.trigger_index < trigger_ids.size():
		var trigger_index = exploration.trigger_index
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger = _context.content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _context.state.world.trigger_is_disabled(trigger_id):
			exploration.trigger_index = trigger_ids.size()
			break
		var trigger_chance = _context.state.world.trigger_chance(trigger.id, trigger.chance_percent)
		if trigger_chance < 1:
			exploration.trigger_index = trigger_ids.size()
			break
		if trigger_chance < 100:
			var chance_roll = _context.rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger_chance:
				exploration.trigger_index = trigger_ids.size()
				break
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		exploration.active_trigger_id = trigger.id
		var started = _context.scenario_vm.start_program(trigger.program_id, ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, coordinate, true))
		if started.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return _context.failed(started.error_code, started.error_message, events)
		var result = _context.scenario_vm.run(_context.runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _context.scenario()._begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			return _context.waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return _context.failed(result.error_code, result.error_message, events)
		_context.scenario()._finalize_completed_trigger(trigger, events)
		if _context.events_have(result.events, &"destination_trigger_recheck_requested"):
			var requested_map = _context.content.world.map_by_id(_context.state.party.map_id)
			if requested_map == null:
				_context.session_continuation.clear()
				return _context.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
			_set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
			return _continue_post_move(events)
		if _context.scenario()._apply_trigger_destination(trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map = _context.content.world.map_by_id(_context.state.party.map_id)
			_set_post_move_continuation(destination_map, _context.state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = trigger_ids.size()
	var random_step = _continue_random_regions(map, events)
	if random_step != null:
		return random_step
	_context.session_continuation.clear()
	return _context.completed(events)

func _continue_exploration_continuation(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.session_continuation.kind == &"application-hook":
		return _context.scenario()._continue_application_hook(events)
	if _context.session_continuation.kind == &"post-clock":
		return _continue_post_time(events)
	if _context.session_continuation.kind == &"post-move":
		return _continue_post_move(events)
	return _context.failed(&"invalid_session_continuation", "The completed scenario has no valid exploration continuation.", events)


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if not _context.state.random_encounters_enabled:
		return null
	var exploration = _context.session_continuation.exploration()
	if exploration == null:
		return _context.failed(&"invalid_session_continuation", "Random encounters require an exploration continuation.", events)
	var region_ids = exploration.random_region_ids
	while exploration.random_region_index >= 0:
		var region_index = exploration.random_region_index
		var region_id: String = String(region_ids[region_index])
		var region = map.random_region_by_id(region_id)
		if region == null:
			_context.session_continuation.clear()
			return _context.failed(&"invalid_session_continuation", "Random-region continuation references unavailable content.", events)
		var effective = _context.state.world.random_region(region)
		var roll = _context.rng.draw(10_000, StringName("random-region.%s" % region.id))
		var triggered = roll <= effective.chance_ten_thousand
		events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chanceTenThousand": effective.chance_ten_thousand, "triggered": triggered}))
		if triggered:
			events.append(DomainEvent.new(&"random_region_triggered", {"regionId": region.id}))
			var door_ids = region.random_doors()
			var door_percents = effective.random_door_percents()
			for door_index: int in door_ids.size():
				var door_roll = _context.rng.draw(100, StringName("random-region.%s.door.%d" % [region.id, door_index]))
				var door_fired = door_roll <= absi(door_percents[door_index])
				events.append(DomainEvent.new(&"random_door_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_ids[door_index], "roll": door_roll, "chancePercent": door_percents[door_index], "triggered": door_fired}))
				if not door_fired:
					continue
				effective.consume_random_door(door_index)
				_context.state.world.set_random_region(effective)
				var program_id = "xap:%d" % door_ids[door_index]
				exploration.active_random_program_id = program_id
				events.append(DomainEvent.new(&"random_door_triggered", {"regionId": region.id, "programId": program_id, "oneShot": door_percents[door_index] > 0}))
				var context = ScenarioExecutionContext.trigger(&"action", "", map.id, _context.state.party.coordinate, true).set_random_region(region.id)
				var started = _context.scenario_vm.start_program(program_id, context)
				if started.state == ScenarioVmResult.State.FAILED:
					_context.session_continuation.clear()
					return _context.failed(started.error_code, started.error_message, events)
				var result = _context.scenario_vm.run(_context.runtime_api)
				events.append_array(result.events)
				if result.state == ScenarioVmResult.State.SUSPENDED:
					return _context.scenario()._begin_scenario_handoff(result, events)
				if result.state == ScenarioVmResult.State.WAITING:
					return _context.waiting(result.interaction, events)
				if result.state == ScenarioVmResult.State.FAILED:
					_context.session_continuation.clear()
					return _context.failed(result.error_code, result.error_message, events)
				if _context.events_have(result.events, &"destination_trigger_recheck_requested"):
					var requested_map = _context.content.world.map_by_id(_context.state.party.map_id)
					if requested_map == null:
						_context.session_continuation.clear()
						return _context.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
					_set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
					return _continue_post_move(events)
				return _complete_random_program(events)
			if effective.battle_minimum != 0 and not _context.state.party.conditions.is_active(7):
				var good_surprise_roll = _context.rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
				if good_surprise_roll < region.option:
					var message = _context.content.message_by_id(absi(region.text_id))
					var prompt = message.text if message != null else "Take the advantage and enter battle?"
					exploration.active_random_region_id = region.id
					exploration.random_battle_stage = &"surprise-choice"
					var request_id = "random-surprise:%s:%d" % [region.id, _context.rng.snapshot().draw_count]
					_context.session_interaction = InteractionRequest.from_payload(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
					if region.sound_id > 0:
						events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
					return _context.waiting(_context.session_interaction, events)
				var bad_surprise_roll = _context.rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
				var surprise = -1 if bad_surprise_roll < 10 else 0
				return _start_random_battle(region, surprise, events)
		exploration.random_region_index = region_index - 1
		if region.only:
			break
	return null


func _complete_random_program(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.session_continuation.kind == &"post-clock":
		_context.session_continuation.exploration().active_random_program_id = ""
		return _complete_post_time(events)
	_context.session_continuation.clear()
	return _context.completed(events)


func _move_after_pooled_wealth(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	var result := ExplorationTimeWorkflow.depart_camp_for_movement(_context.workflow_context(), direction, preceding_events) if _context.state.party_camping else ExplorationTimeWorkflow.commit_move(_context.workflow_context(), direction, preceding_events)
	return _finish_exploration_movement(result)


func _finish_exploration_movement(result: ExplorationTimeWorkflow.MovementTransitionResult) -> SessionCoordinatorResult:
	if not result.ok:
		return _context.failed(result.error_code, result.error_message, result.events)
	if not result.choice_kind.is_empty():
		return _begin_boat_choice(result)
	if not result.post_clock:
		return _context.completed(result.events)
	_set_post_time_continuation(result.map, result.resume_kind, result.direction, result.check_random, result.timed_day, result.timed_coordinate)
	return _context.responses()._finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _begin_boat_choice(result: ExplorationTimeWorkflow.MovementTransitionResult) -> SessionCoordinatorResult:
	var movement := result.choice_movement
	if movement == null or movement.source_map == null or movement.target_map == null or movement.topology_result == null or movement.topology_result.target_cell == null or result.choice_kind not in [&"board", &"disembark"]:
		return _context.failed(&"invalid_boat_choice", "The Classic boat movement choice is unavailable.", result.events)
	var body := SessionContinuation.BoatBody.new()
	body.action = result.choice_kind
	body.source_map_id = movement.source_map.id
	body.source_coordinate = _context.state.party.coordinate
	body.target_map_id = movement.target_map.id
	body.target_coordinate = movement.target_coordinate
	body.direction = result.direction
	if body.direction == Vector2i.ZERO:
		return _context.failed(&"invalid_boat_choice", "The Classic boat movement direction is unavailable.", result.events)
	_context.set_continuation(SessionContinuation.boat_choice(body))
	var prompt := "Board this boat?" if body.action == &"board" else "Leave the boat here and go ashore?"
	var yes_label := "Board" if body.action == &"board" else "Leave boat"
	var no_label := "Stay ashore" if body.action == &"board" else "Remain aboard"
	_context.session_interaction = InteractionRequest.from_payload("boat-choice:%s:%d" % [String(body.action), _context.next_revision()], &"yes_no", {"prompt": prompt, "yesLabel": yes_label, "noLabel": no_label})
	var events := result.events.duplicate()
	if body.action == &"disembark":
		events.append(ExplorationTimeWorkflow._sound_event(-148, "classic-boat-shore"))
	return _context.waiting(_context.session_interaction, events)


func _start_random_battle(region: RandomEncounterRegion, surprise: int, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var effective := _context.state.world.random_region(region)
	if effective.battle_maximum < effective.battle_minimum:
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.failed(&"invalid_random_battle_range", "Random rectangle '%s' has an inverted battle range." % region.id, events)
	var battle_id := _context.rng.draw_between(effective.battle_minimum, effective.battle_maximum, StringName("random-region.%s.battle" % region.id))
	var battle := _context.content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.failed(&"unknown_random_battle", "Random rectangle '%s' selected unavailable battle %d." % [region.id, battle_id], events)
	events.append(DomainEvent.new(&"random_encounter_triggered", {"regionId": region.id, "battleId": battle.id, "classicId": battle_id, "textId": region.text_id, "soundId": region.sound_id, "surprise": surprise}))
	var battle_result := _context.rules.combat_flow.start_battle(_context.state, _context.content, battle, _context.rng, surprise)
	if not battle_result.ok:
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.failed(battle_result.error_code, battle_result.error_message, events)
	events.append_array(battle_result.events)
	if _context.state.combat != null and _context.session_continuation.kind == &"post-clock":
		var exploration := _context.session_continuation.exploration()
		exploration.random_region_index = -1 if region.only else exploration.random_region_index - 1
		_context.battle_return_continuation = _context.session_continuation.copy()
	if not CharacterAgingResult.update_payloads(battle_result.events).is_empty():
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.responses()._finish_with_age_updates(events, &"combat-monster-turns")
	if not _context.event_payload(battle_result.events, &"monster_death_macro_requested").is_empty():
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.scenario()._start_session_death_macro(events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	if battle_result.completed:
		return _context.scenario()._finish_direct_battle(events)
	return _context.completed(events)
