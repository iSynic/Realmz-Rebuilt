class_name SessionExplorationCoordinator
extends RefCounted

var _session_ref: WeakRef


func _init(session: RefCounted) -> void:
	_session_ref = weakref(session)


func _session() -> RefCounted:
	return _session_ref.get_ref() if _session_ref != null else null

func _set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	_session()._set_continuation(ExplorationTimeWorkflow.post_time_continuation(_session()._workflow_context(), map, StringName(resume_kind), direction, check_random, timed_day, timed_coordinate))


func _continue_post_time(events: Array[DomainEvent]) -> SessionStep:
	var exploration = _session()._session_continuation.exploration()
	if _session()._session_continuation.kind != &"post-clock" or exploration == null:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var active_timed_program_id = exploration.active_timed_program_id
	if not active_timed_program_id.is_empty() and not _rebase_post_time_location():
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	var map = _session()._content.world.map_by_id(exploration.map_id)
	if map == null or _session()._state.party.map_id != map.id or _session()._state.party.coordinate != exploration.coordinate:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	if not active_timed_program_id.is_empty():
		exploration.active_timed_program_id = ""
	var timed_step = _continue_timed_encounters(events)
	if timed_step != null:
		return timed_step
	map = _session()._content.world.map_by_id(exploration.map_id)
	if map == null:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_timed_encounter_location", "Timed encounter continuation references an unavailable map.", events)
	var active_program_id = exploration.active_random_program_id
	if not active_program_id.is_empty():
		exploration.active_random_program_id = ""
		return _complete_post_time(events)
	if exploration.check_random and exploration.resume_kind != &"post-move":
		var random_step = _continue_random_regions(map, events)
		if random_step != null:
			return random_step
	return _complete_post_time(events)


func _complete_post_time(events: Array[DomainEvent]) -> SessionStep:
	var exploration = _session()._session_continuation.exploration()
	if _session()._session_continuation.kind != &"post-clock" or exploration == null:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var resume_kind = exploration.resume_kind
	var direction = exploration.direction
	_session()._session_continuation.clear()
	if resume_kind == &"move":
		return _session()._finish_exploration_movement(ExplorationTimeWorkflow.commit_move(_session()._workflow_context(), direction, events))
	if resume_kind == &"post-move":
		var map = _session()._content.world.map_by_id(_session()._state.party.map_id)
		_set_post_move_continuation(map, _session()._state.party.coordinate)
		return _continue_post_move(events)
	if resume_kind == &"completed":
		return _session()._finish_completed(events)
	return _session()._finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation has no valid completion path.", events)


func _continue_timed_encounters(events: Array[DomainEvent]) -> SessionStep:
	var exploration = _session()._session_continuation.exploration()
	if _session()._session_continuation.kind != &"post-clock" or exploration == null:
		return _session()._finish_failed(&"invalid_session_continuation", "Timed encounters require a post-clock continuation.", events)
	var timed_day = exploration.timed_day
	if timed_day <= 0:
		return null
	var encounters = _session()._content.timed_encounters()
	while exploration.timed_encounter_index < encounters.size():
		var index = exploration.timed_encounter_index
		var encounter = encounters[index]
		exploration.timed_encounter_index = index + 1
		var effective = _session()._state.timed_encounter_override(encounter.id)
		var effective_day = int(effective.get("day", encounter.day))
		if effective_day != timed_day:
			continue
		var increment = int(effective.get("increment", encounter.increment))
		effective["day"] = effective_day + increment
		_session()._state.set_timed_encounter_override(encounter.id, effective)
		events.append(DomainEvent.new(&"timed_encounter_advanced", {"encounterId": encounter.id, "day": effective_day, "nextDay": effective["day"], "source": "classic-midnight"}))
		var chance = int(effective.get("percent", encounter.chance_percent))
		var roll = _session()._rng.draw(100, StringName("timed-encounter.%d" % encounter.id))
		var map = _session()._content.world.map_by_id(_session()._state.party.map_id)
		if map == null:
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"invalid_timed_encounter_location", "Timed encounter eligibility references an unavailable map.", events)
		var eligible = roll <= chance and _timed_encounter_requirements_met(encounter, map)
		events.append(DomainEvent.new(&"timed_encounter_checked", {"encounterId": encounter.id, "roll": roll, "chancePercent": chance, "eligible": eligible}))
		if not eligible:
			continue
		_apply_pending_midnight_recovery(events)
		var trigger = _session()._content.trigger_by_map_record(map.id, encounter.trigger_record_index)
		if trigger == null:
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"unknown_timed_encounter_trigger", "Timed Encounter %d references unavailable Action Point record %d on map '%s'." % [encounter.id, encounter.trigger_record_index, map.id], events)
		exploration.active_timed_program_id = trigger.program_id
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "triggerId": trigger.id, "programId": trigger.program_id}))
		var context = ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, exploration.timed_check_coordinate, true).set_timed_encounter(encounter.id)
		var started = _session()._scenario_vm.start_program(trigger.program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			_session()._session_continuation.clear()
			return _session()._finish_failed(started.error_code, started.error_message, events)
		var result = _session()._scenario_vm.run(_session()._runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _session()._begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			if not _rebase_post_time_location():
				_session()._session_continuation.clear()
				return _session()._finish_failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
			return _session()._finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session()._session_continuation.clear()
			return _session()._finish_failed(result.error_code, result.error_message, events)
		exploration.active_timed_program_id = ""
		if not _rebase_post_time_location():
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	_apply_pending_midnight_recovery(events)
	exploration.timed_day = 0
	return null


func _apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	ExplorationTimeWorkflow.apply_pending_midnight_recovery(_session()._workflow_context(), _session()._session_continuation.exploration(), events)


func _rebase_post_time_location() -> bool:
	return ExplorationTimeWorkflow.rebase_post_time_location(_session()._workflow_context(), _session()._session_continuation)


func _timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	return ExplorationTimeWorkflow.timed_encounter_requirements_met(_session()._workflow_context(), encounter, map, _session()._session_continuation.exploration())


func _set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	_session()._set_continuation(ExplorationTimeWorkflow.post_move_continuation(_session()._workflow_context(), map, coordinate, destination_depth))


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	var exploration = _session()._session_continuation.exploration()
	if _session()._session_continuation.kind != &"post-move" or exploration == null:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	if _session()._events_have(events, &"destination_trigger_recheck_requested") and exploration.action_point_destination_depth == 0:
		var requested_map = _session()._content.world.map_by_id(_session()._state.party.map_id)
		if requested_map == null:
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
		_set_post_move_continuation(requested_map, _session()._state.party.coordinate, 1)
		exploration = _session()._session_continuation.exploration()
	var map = _session()._content.world.map_by_id(exploration.map_id)
	var coordinate = exploration.coordinate
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_session()._session_continuation.clear()
		return _session()._finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_random_program_id = exploration.active_random_program_id
	if not active_random_program_id.is_empty():
		_session()._session_continuation.clear()
		return _session()._finish_completed(events)
	var active_trigger_id = exploration.active_trigger_id
	if not active_trigger_id.is_empty():
		var completed_trigger = _session()._content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_session()._finalize_completed_trigger(completed_trigger, events)
		if _session()._apply_trigger_destination(completed_trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map = _session()._content.world.map_by_id(_session()._state.party.map_id)
			_set_post_move_continuation(destination_map, _session()._state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = exploration.trigger_ids.size()
	var trigger_ids = exploration.trigger_ids
	while exploration.trigger_index < trigger_ids.size():
		var trigger_index = exploration.trigger_index
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger = _session()._content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _session()._state.world.trigger_is_disabled(trigger_id):
			exploration.trigger_index = trigger_ids.size()
			break
		var trigger_chance = _session()._state.world.trigger_chance(trigger.id, trigger.chance_percent)
		if trigger_chance < 1:
			exploration.trigger_index = trigger_ids.size()
			break
		if trigger_chance < 100:
			var chance_roll = _session()._rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger_chance:
				exploration.trigger_index = trigger_ids.size()
				break
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		exploration.active_trigger_id = trigger.id
		var started = _session()._scenario_vm.start_program(trigger.program_id, ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, coordinate, true))
		if started.state == ScenarioVmResult.State.FAILED:
			_session()._session_continuation.clear()
			return _session()._finish_failed(started.error_code, started.error_message, events)
		var result = _session()._scenario_vm.run(_session()._runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _session()._begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			return _session()._finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session()._session_continuation.clear()
			return _session()._finish_failed(result.error_code, result.error_message, events)
		_session()._finalize_completed_trigger(trigger, events)
		if _session()._events_have(result.events, &"destination_trigger_recheck_requested"):
			var requested_map = _session()._content.world.map_by_id(_session()._state.party.map_id)
			if requested_map == null:
				_session()._session_continuation.clear()
				return _session()._finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
			_set_post_move_continuation(requested_map, _session()._state.party.coordinate, 1)
			return _continue_post_move(events)
		if _session()._apply_trigger_destination(trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map = _session()._content.world.map_by_id(_session()._state.party.map_id)
			_set_post_move_continuation(destination_map, _session()._state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = trigger_ids.size()
	var random_step = _continue_random_regions(map, events)
	if random_step != null:
		return random_step
	_session()._session_continuation.clear()
	return _session()._finish_completed(events)

func _continue_exploration_continuation(events: Array[DomainEvent]) -> SessionStep:
	if _session()._session_continuation.kind == &"application-hook":
		return _session()._continue_application_hook(events)
	if _session()._session_continuation.kind == &"post-clock":
		return _continue_post_time(events)
	if _session()._session_continuation.kind == &"post-move":
		return _continue_post_move(events)
	return _session()._finish_failed(&"invalid_session_continuation", "The completed scenario has no valid exploration continuation.", events)


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionStep:
	if not _session()._state.random_encounters_enabled:
		return null
	var exploration = _session()._session_continuation.exploration()
	if exploration == null:
		return _session()._finish_failed(&"invalid_session_continuation", "Random encounters require an exploration continuation.", events)
	var region_ids = exploration.random_region_ids
	while exploration.random_region_index >= 0:
		var region_index = exploration.random_region_index
		var region_id: String = String(region_ids[region_index])
		var region = map.random_region_by_id(region_id)
		if region == null:
			_session()._session_continuation.clear()
			return _session()._finish_failed(&"invalid_session_continuation", "Random-region continuation references unavailable content.", events)
		var effective = _session()._state.world.random_region(region)
		var roll = _session()._rng.draw(10_000, StringName("random-region.%s" % region.id))
		var triggered = roll <= effective.chance_ten_thousand
		events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chanceTenThousand": effective.chance_ten_thousand, "triggered": triggered}))
		if triggered:
			events.append(DomainEvent.new(&"random_region_triggered", {"regionId": region.id}))
			var door_ids = region.random_doors()
			var door_percents = effective.random_door_percents()
			for door_index: int in door_ids.size():
				var door_roll = _session()._rng.draw(100, StringName("random-region.%s.door.%d" % [region.id, door_index]))
				var door_fired = door_roll <= absi(door_percents[door_index])
				events.append(DomainEvent.new(&"random_door_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_ids[door_index], "roll": door_roll, "chancePercent": door_percents[door_index], "triggered": door_fired}))
				if not door_fired:
					continue
				effective.consume_random_door(door_index)
				_session()._state.world.set_random_region(effective)
				var program_id = "xap:%d" % door_ids[door_index]
				exploration.active_random_program_id = program_id
				events.append(DomainEvent.new(&"random_door_triggered", {"regionId": region.id, "programId": program_id, "oneShot": door_percents[door_index] > 0}))
				var context = ScenarioExecutionContext.trigger(&"action", "", map.id, _session()._state.party.coordinate, true).set_random_region(region.id)
				var started = _session()._scenario_vm.start_program(program_id, context)
				if started.state == ScenarioVmResult.State.FAILED:
					_session()._session_continuation.clear()
					return _session()._finish_failed(started.error_code, started.error_message, events)
				var result = _session()._scenario_vm.run(_session()._runtime_api)
				events.append_array(result.events)
				if result.state == ScenarioVmResult.State.SUSPENDED:
					return _session()._begin_scenario_handoff(result, events)
				if result.state == ScenarioVmResult.State.WAITING:
					return _session()._finish_waiting(result.interaction, events)
				if result.state == ScenarioVmResult.State.FAILED:
					_session()._session_continuation.clear()
					return _session()._finish_failed(result.error_code, result.error_message, events)
				if _session()._events_have(result.events, &"destination_trigger_recheck_requested"):
					var requested_map = _session()._content.world.map_by_id(_session()._state.party.map_id)
					if requested_map == null:
						_session()._session_continuation.clear()
						return _session()._finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
					_set_post_move_continuation(requested_map, _session()._state.party.coordinate, 1)
					return _continue_post_move(events)
				return _complete_random_program(events)
			if effective.battle_minimum != 0 and not _session()._state.party.conditions.is_active(7):
				var good_surprise_roll = _session()._rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
				if good_surprise_roll < region.option:
					var message = _session()._content.message_by_id(absi(region.text_id))
					var prompt = message.text if message != null else "Take the advantage and enter battle?"
					exploration.active_random_region_id = region.id
					exploration.random_battle_stage = &"surprise-choice"
					var request_id = "random-surprise:%s:%d" % [region.id, _session()._rng.snapshot().draw_count]
					_session()._session_interaction = InteractionRequest.from_payload(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
					if region.sound_id > 0:
						events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
					return _session()._finish_waiting(_session()._session_interaction, events)
				var bad_surprise_roll = _session()._rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
				var surprise = -1 if bad_surprise_roll < 10 else 0
				return _session()._start_random_battle(region, surprise, events)
		exploration.random_region_index = region_index - 1
		if region.only:
			break
	return null


func _complete_random_program(events: Array[DomainEvent]) -> SessionStep:
	if _session()._session_continuation.kind == &"post-clock":
		_session()._session_continuation.exploration().active_random_program_id = ""
		return _complete_post_time(events)
	_session()._session_continuation.clear()
	return _session()._finish_completed(events)
