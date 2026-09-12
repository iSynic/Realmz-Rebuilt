## Coordinates session exploration coordinator responsibilities behind the public session boundary.

class_name SessionExplorationCoordinator
extends RefCounted

class ContextualEncounterSelection:
	extends RefCounted

	var program_id := ""
	var region_id := ""
	var used_default_program := false
	var error_code: StringName = &""
	var error_message := ""


class PostMoveContext:
	extends RefCounted

	var continuation: ExplorationContinuationBody
	var map: MapDefinition
	var coordinate := Vector2i.ZERO
	var terminal_result: SessionCoordinatorResult


var _context: SessionContext


func _init(context: SessionContext) -> void:
	_context = context


func begin_contextual_encounter() -> SessionCoordinatorResult:
	if _context.state.combat != null and not _context.state.combat.completed:
		return SessionCoordinatorResult.failed(&"encounter_during_battle", "The seamless Encounter command is unavailable during battle.")
	var map := _context.content.world.map_by_id(_context.state.party.map_id)
	if map == null:
		return SessionCoordinatorResult.failed(&"unknown_map", "The current map is unavailable for Encounter.")
	var encounter_coordinate := _context.state.party.coordinate
	if map.level_type == &"land" and _context.state.last_move_direction != Vector2i.ZERO:
		encounter_coordinate += _context.state.last_move_direction
	var cell: MapCell = map.topology.cell_at(encounter_coordinate)
	var events: Array[DomainEvent] = []
	var selection := _select_contextual_encounter(map, encounter_coordinate, cell, events)
	if not selection.error_code.is_empty():
		return SessionCoordinatorResult.failed(selection.error_code, selection.error_message, events)
	if _context.content.scenario.program_by_id(selection.program_id) == null:
		if selection.used_default_program:
			events.append(DomainEvent.new(&"contextual_encounter_unavailable", {"mapId": map.id, "coordinate": encounter_coordinate, "programId": selection.program_id}))
			return SessionCoordinatorResult.completed(events)
		return SessionCoordinatorResult.failed(&"unknown_random_door_program", "Encounter selected unavailable program '%s'." % selection.program_id, events)
	_context.set_continuation(ExplorationContinuationWorkflow.post_move(_context.workflow_context(), map, _context.state.party.coordinate))
	_context.session_continuation.exploration().active_random_program_id = selection.program_id
	events.append(DomainEvent.new(&"contextual_encounter_triggered", {"regionId": selection.region_id, "programId": selection.program_id, "coordinate": encounter_coordinate, "defaultProgram": selection.used_default_program}))
	return _start_contextual_encounter_program(map, encounter_coordinate, selection, events)


func _select_contextual_encounter(map: MapDefinition, encounter_coordinate: Vector2i, cell: MapCell, events: Array[DomainEvent]) -> ContextualEncounterSelection:
	var selection := ContextualEncounterSelection.new()
	var region_ids: Array[String] = [] if cell == null else _context.state.world.triggers.random_region_ids_at(map, encounter_coordinate)
	for offset: int in region_ids.size():
		var region_id: String = region_ids[region_ids.size() - 1 - offset]
		var region := map.random_region_by_id(region_id)
		if region == null:
			selection.error_code = &"invalid_random_region"
			selection.error_message = "Encounter references an unavailable random rectangle."
			return selection
		var effective := _context.state.world.triggers.random_region(region)
		if effective.chance_ten_thousand >= 0:
			continue
		var door_ids := region.random_doors()
		var door_percents := effective.random_door_percents()
		for door_index: int in mini(door_ids.size(), door_percents.size()):
			var door_id := door_ids[door_index]
			var percent := door_percents[door_index]
			var roll := _context.rng.draw(100, StringName("contextual-encounter.%s.door.%d" % [region.id, door_index]))
			var fired := roll <= absi(percent)
			events.append(DomainEvent.new(&"contextual_encounter_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_id, "roll": roll, "chancePercent": percent, "triggered": fired}))
			if not fired:
				continue
			effective.consume_random_door(door_index)
			_context.state.world.triggers.set_random_region(effective)
			selection.program_id = "xap:%d" % door_id
			selection.region_id = region.id
	selection.used_default_program = selection.program_id.is_empty()
	if selection.used_default_program:
		selection.program_id = "xap:0"
	return selection


func _start_contextual_encounter_program(map: MapDefinition, encounter_coordinate: Vector2i, selection: ContextualEncounterSelection, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var execution_context := ScenarioExecutionContext.trigger(&"action", "", map.id, encounter_coordinate, true).set_random_region(selection.region_id)
	var started := _context.scenario_vm.start_program(selection.program_id, execution_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(started.error_code, started.error_message, events)
	var result := _context.scenario_vm.run(_context.runtime_api)
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _context.scenario().begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)

func set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	_context.set_continuation(ExplorationContinuationWorkflow.post_time(_context.workflow_context(), map, StringName(resume_kind), direction, check_random, timed_day, timed_coordinate))


func continue_post_time(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var active_timed_program_id = exploration.active_timed_program_id
	if not active_timed_program_id.is_empty() and not rebase_post_time_location():
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	if not exploration.active_random_program_id.is_empty():
		return complete_random_program(events)
	var map = _context.content.world.map_by_id(exploration.map_id)
	if map == null or _context.state.party.map_id != map.id or _context.state.party.coordinate != exploration.coordinate:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	if not active_timed_program_id.is_empty():
		exploration.active_timed_program_id = ""
	var timed_step = continue_timed_encounters(events)
	if timed_step != null:
		return timed_step
	map = _context.content.world.map_by_id(exploration.map_id)
	if map == null:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "Timed encounter continuation references an unavailable map.", events)
	if exploration.check_random:
		var random_step = continue_random_regions(map, events)
		if random_step != null:
			return random_step
	return complete_post_time(events)


func complete_post_time(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var resume_kind = exploration.resume_kind
	var direction = exploration.direction
	_context.session_continuation.clear()
	if resume_kind == &"move":
		return finish_exploration_movement(ExplorationMovementWorkflow.commit(_context.workflow_context(), direction, events))
	if resume_kind == &"camp-departure-second":
		return finish_exploration_movement(ExplorationMovementWorkflow.complete_land_camp_departure(_context.workflow_context(), direction, events))
	if resume_kind == &"post-move":
		var map = _context.content.world.map_by_id(_context.state.party.map_id)
		set_post_move_continuation(map, _context.state.party.coordinate)
		return continue_post_move(events)
	if resume_kind in [&"attempt-search-completed", &"attempt-search-post-move"]:
		var search_result := ExplorationSearchWorkflow.search_after_land_movement_attempt(_context.workflow_context(), events)
		if not search_result.ok:
			return SessionCoordinatorResult.failed(search_result.error_code, search_result.error_message, search_result.events)
		var final_resume_kind := &"post-move" if resume_kind == &"attempt-search-post-move" else &"completed"
		if search_result.check_random:
			set_post_time_continuation(search_result.map, final_resume_kind, Vector2i.ZERO, true, search_result.timed_day, _context.state.party.coordinate)
			return _context.responses().finish_with_age_updates(search_result.events, &"post-clock", _context.session_continuation.copy())
		if final_resume_kind == &"post-move":
			set_post_move_continuation(search_result.map, _context.state.party.coordinate)
			return continue_post_move(search_result.events)
		return SessionCoordinatorResult.completed(search_result.events)
	if resume_kind == &"area-search-second":
		var result := ExplorationSearchWorkflow.complete_area_search(_context.workflow_context(), events)
		if not result.ok:
			return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
		set_post_time_continuation(result.map, "completed", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
		return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())
	if resume_kind == &"camp-entry-second":
		var camp_result := ExplorationTimeWorkflow.complete_camp_entry(_context.workflow_context(), events)
		if not camp_result.ok:
			return SessionCoordinatorResult.failed(camp_result.error_code, camp_result.error_message, camp_result.events)
		set_post_time_continuation(camp_result.map, "completed", Vector2i.ZERO, camp_result.check_random, camp_result.timed_day, _context.state.party.coordinate)
		return _context.responses().finish_with_age_updates(camp_result.events, &"post-clock", _context.session_continuation.copy())
	if resume_kind == &"rest-second":
		var rest_result := ExplorationTimeWorkflow.complete_rest(_context.workflow_context(), events)
		if not rest_result.ok:
			return SessionCoordinatorResult.failed(rest_result.error_code, rest_result.error_message, rest_result.events)
		set_post_time_continuation(rest_result.map, "completed", Vector2i.ZERO, rest_result.check_random, rest_result.timed_day, _context.state.party.coordinate)
		return _context.responses().finish_with_age_updates(rest_result.events, &"post-clock", _context.session_continuation.copy())
	if resume_kind == &"heal":
		var heal_result := ExplorationTimeWorkflow.complete_heal(_context.workflow_context(), events)
		return SessionCoordinatorResult.completed(heal_result.events) if heal_result.ok else SessionCoordinatorResult.failed(heal_result.error_code, heal_result.error_message, heal_result.events)
	if resume_kind == &"completed":
		return SessionCoordinatorResult.completed(events)
	return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-clock exploration continuation has no valid completion path.", events)


func continue_timed_encounters(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-clock" or exploration == null:
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Timed encounters require a post-clock continuation.", events)
	var timed_day = exploration.timed_day
	if timed_day <= 0:
		return null
	var encounters = _context.content.scenario_records.timed_encounters()
	while exploration.timed_encounter_index < encounters.size():
		var index = exploration.timed_encounter_index
		var encounter = encounters[index]
		exploration.timed_encounter_index = index + 1
		var effective = _context.state.scenario_progress.encounters.timed_override(encounter.id)
		var effective_day = int(effective.get("day", encounter.day))
		if effective_day != timed_day:
			continue
		var increment = int(effective.get("increment", encounter.increment))
		effective["day"] = effective_day + increment
		_context.state.scenario_progress.encounters.set_timed_override(encounter.id, effective)
		events.append(DomainEvent.new(&"timed_encounter_advanced", {"encounterId": encounter.id, "day": effective_day, "nextDay": effective["day"], "source": "classic-midnight"}))
		var chance = int(effective.get("percent", encounter.chance_percent))
		var roll = _context.rng.draw(100, StringName("timed-encounter.%d" % encounter.id))
		var map = _context.content.world.map_by_id(_context.state.party.map_id)
		if map == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "Timed encounter eligibility references an unavailable map.", events)
		var eligible = roll <= chance and timed_encounter_requirements_met(encounter, map)
		events.append(DomainEvent.new(&"timed_encounter_checked", {"encounterId": encounter.id, "roll": roll, "chancePercent": chance, "eligible": eligible}))
		if not eligible:
			continue
		apply_pending_midnight_recovery(events)
		if _context.content.scenario.program_by_id(encounter.program_id) == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"unknown_timed_encounter_program", "Timed Encounter %d references unavailable XAP program '%s'." % [encounter.id, encounter.program_id], events)
		exploration.active_timed_program_id = encounter.program_id
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "classicMacroId": encounter.classic_macro_id, "programId": encounter.program_id}))
		var context = ScenarioExecutionContext.trigger(&"action", "", map.id, exploration.timed_check_coordinate, true).set_timed_encounter(encounter.id)
		var started = _context.scenario_vm.start_program(encounter.program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(started.error_code, started.error_message, events)
		var result = _context.scenario_vm.run(_context.runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _context.scenario().begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			if not rebase_post_time_location():
				_context.session_continuation.clear()
				return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
			return SessionCoordinatorResult.waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
		exploration.active_timed_program_id = ""
		if not rebase_post_time_location():
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	apply_pending_midnight_recovery(events)
	exploration.timed_day = 0
	return null


func apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	ExplorationContinuationWorkflow.apply_pending_midnight_recovery(_context.workflow_context(), _context.session_continuation.exploration(), events)


func rebase_post_time_location() -> bool:
	return ExplorationContinuationWorkflow.rebase_post_time_location(_context.workflow_context(), _context.session_continuation)


func timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	return ExplorationContinuationWorkflow.timed_encounter_requirements_met(_context.workflow_context(), encounter, map, _context.session_continuation.exploration())


func set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	_context.set_continuation(ExplorationContinuationWorkflow.post_move(_context.workflow_context(), map, coordinate, destination_depth))


func start_debug_action_point(trigger_id: String) -> SessionCoordinatorResult:
	return SessionActionPointCoordinator.new(_context, self).start_debug(trigger_id)


func continue_post_move(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var post_move := _prepare_post_move_context(events)
	if post_move.terminal_result != null:
		return post_move.terminal_result
	var resumed_trigger := _resume_completed_post_move_trigger(post_move, events)
	if resumed_trigger != null:
		return resumed_trigger
	var trigger_step := _run_next_post_move_trigger(post_move, events)
	if trigger_step != null:
		return trigger_step
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)


func _prepare_post_move_context(events: Array[DomainEvent]) -> PostMoveContext:
	var post_move := PostMoveContext.new()
	var exploration = _context.session_continuation.exploration()
	if _context.session_continuation.kind != &"post-move" or exploration == null:
		_context.session_continuation.clear()
		post_move.terminal_result = SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
		return post_move
	if _context.events_have(events, &"destination_trigger_recheck_requested") and exploration.action_point_destination_depth == 0:
		var requested_map = _context.content.world.map_by_id(_context.state.party.map_id)
		if requested_map == null:
			_context.session_continuation.clear()
			post_move.terminal_result = SessionCoordinatorResult.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
			return post_move
		set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
		exploration = _context.session_continuation.exploration()
	post_move.continuation = exploration
	post_move.map = _context.content.world.map_by_id(exploration.map_id)
	post_move.coordinate = exploration.coordinate
	var cell: MapCell = null if post_move.map == null else post_move.map.topology.cell_at(post_move.coordinate)
	if cell == null:
		_context.session_continuation.clear()
		post_move.terminal_result = SessionCoordinatorResult.failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
		return post_move
	if not exploration.active_random_program_id.is_empty():
		_context.session_continuation.clear()
		post_move.terminal_result = SessionCoordinatorResult.completed(events)
	return post_move


func _resume_completed_post_move_trigger(post_move: PostMoveContext, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration := post_move.continuation
	var active_trigger_id := exploration.active_trigger_id
	if not active_trigger_id.is_empty():
		var completed_trigger = _context.content.scenario_records.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		var backout_kind: StringName = &"choice" if _context.events_have(events, &"classic_choice_backout_requested") else &"encounter" if _context.events_have(events, &"encounter_cancelled") else &""
		if not backout_kind.is_empty():
			return _complete_classic_backout(post_move.map, post_move.coordinate, active_trigger_id, events, backout_kind)
		if _context.events_have(events, &"party_backed_up"):
			_context.session_continuation.clear()
			return SessionCoordinatorResult.completed(events)
		_context.scenario().finalize_completed_trigger(completed_trigger, events)
		if _context.scenario().apply_trigger_destination(completed_trigger, events, exploration.action_point_destination_depth == 0 and not _context.events_have(events, &"party_position_restored")):
			var destination_map = _context.content.world.map_by_id(_context.state.party.map_id)
			set_post_move_continuation(destination_map, _context.state.party.coordinate, 1)
			return continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = exploration.trigger_ids.size()
	return null


func _run_next_post_move_trigger(post_move: PostMoveContext, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var exploration := post_move.continuation
	var trigger_ids := exploration.trigger_ids
	while exploration.trigger_index < trigger_ids.size():
		var trigger_index = exploration.trigger_index
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger = _context.content.scenario_records.trigger_by_id(trigger_id)
		if trigger == null or _context.state.world.triggers.trigger_is_disabled(trigger_id):
			exploration.trigger_index = trigger_ids.size()
			break
		var trigger_chance = _context.state.world.triggers.trigger_chance(trigger.id, trigger.chance_percent)
		if (not trigger.active and not _context.state.world.triggers.trigger_chance_is_overridden(trigger_id)) or trigger_chance < 1:
			exploration.trigger_index = trigger_ids.size()
			break
		var chance_roll = _context.rng.draw(100, StringName("trigger.%s" % trigger.id))
		if chance_roll > trigger_chance:
			exploration.trigger_index = trigger_ids.size()
			break
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		var step = SessionActionPointCoordinator.new(_context, self).execute(post_move, trigger, events)
		if step != null:
			return step
	return null


func _complete_classic_backout(map: MapDefinition, coordinate: Vector2i, trigger_id: String, events: Array[DomainEvent], backout_kind: StringName) -> SessionCoordinatorResult:
	if _context.state.party.map_id != map.id or _context.state.party.coordinate != coordinate:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_choice_backout", "Classic backout lost its action-point location.", events)
	if map.level_type == &"land":
		var direction := _context.state.last_move_direction
		var destination := coordinate - direction
		if direction == Vector2i.ZERO or map.topology.cell_at(destination) == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_choice_backout", "Classic backout cannot reverse the preceding overland step.", events)
		_context.state.party.coordinate = destination
		events.append(DomainEvent.new(&"party_moved", {"fromMapId": map.id, "fromX": coordinate.x, "fromY": coordinate.y, "mapId": map.id, "x": destination.x, "y": destination.y, "source": "classic-%s-backout" % backout_kind, "triggerId": trigger_id}))
	events.append(DomainEvent.new(&"classic_%s_backout_completed" % backout_kind, {"triggerId": trigger_id, "mapId": map.id, "fromX": coordinate.x, "fromY": coordinate.y, "x": _context.state.party.coordinate.x, "y": _context.state.party.coordinate.y}))
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)

func continue_exploration_continuation(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.session_continuation.kind == &"application-hook":
		return _context.scenario().continue_application_hook(events)
	if _context.session_continuation.kind == &"post-clock":
		return continue_post_time(events)
	if _context.session_continuation.kind == &"post-move":
		return continue_post_move(events)
	return SessionCoordinatorResult.failed(&"invalid_session_continuation", "The completed scenario has no valid exploration continuation.", events)


func continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if not _context.state.random_encounters_enabled:
		return null
	var exploration = _context.session_continuation.exploration()
	if exploration == null:
		return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Random encounters require an exploration continuation.", events)
	var region_ids = exploration.random_region_ids
	while exploration.random_region_index >= 0:
		var region_index = exploration.random_region_index
		var region_id: String = String(region_ids[region_index])
		var region = map.random_region_by_id(region_id)
		if region == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_session_continuation", "Random-region continuation references unavailable content.", events)
		var effective = _context.state.world.triggers.random_region(region)
		var region_step := _check_random_region(map, exploration, region, effective, events)
		if region_step != null:
			return region_step
		exploration.random_region_index = region_index - 1
		if region.only:
			break
	return null


func _check_random_region(map: MapDefinition, exploration: ExplorationContinuationBody, region: RandomEncounterRegion, effective: RandomRegionState, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var roll = _context.rng.draw(10_000, StringName("random-region.%s" % region.id))
	var triggered = roll <= effective.chance_ten_thousand
	events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chanceTenThousand": effective.chance_ten_thousand, "triggered": triggered}))
	if not triggered:
		return null
	events.append(DomainEvent.new(&"random_region_triggered", {"regionId": region.id}))
	var door_step := _run_random_door(map, exploration, region, effective, events)
	if door_step != null:
		return door_step
	if effective.battle_minimum == 0 or _context.state.party.conditions.is_active(7):
		return null
	return _begin_random_battle_or_choice(exploration, region, events)


func _run_random_door(map: MapDefinition, exploration: ExplorationContinuationBody, region: RandomEncounterRegion, effective: RandomRegionState, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var door_ids = region.random_doors()
	var door_percents = effective.random_door_percents()
	for door_index: int in door_ids.size():
		var door_roll = _context.rng.draw(100, StringName("random-region.%s.door.%d" % [region.id, door_index]))
		var door_fired = door_roll <= absi(door_percents[door_index])
		events.append(DomainEvent.new(&"random_door_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_ids[door_index], "roll": door_roll, "chancePercent": door_percents[door_index], "triggered": door_fired}))
		if not door_fired:
			continue
		effective.consume_random_door(door_index)
		_context.state.world.triggers.set_random_region(effective)
		var program_id = "xap:%d" % door_ids[door_index]
		exploration.active_random_program_id = program_id
		events.append(DomainEvent.new(&"random_door_triggered", {"regionId": region.id, "programId": program_id, "oneShot": door_percents[door_index] > 0}))
		var context = ScenarioExecutionContext.trigger(&"action", "", map.id, _context.state.party.coordinate, true).set_random_region(region.id)
		var started = _context.scenario_vm.start_program(program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(started.error_code, started.error_message, events)
		var result = _context.scenario_vm.run(_context.runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _context.scenario().begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			return SessionCoordinatorResult.waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
		if _context.events_have(result.events, &"destination_trigger_recheck_requested"):
			return _recheck_random_door_destination(events)
		return complete_random_program(events)
	return null


func _recheck_random_door_destination(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var requested_map = _context.content.world.map_by_id(_context.state.party.map_id)
	if requested_map == null:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
	set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
	return continue_post_move(events)


func _begin_random_battle_or_choice(exploration: ExplorationContinuationBody, region: RandomEncounterRegion, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var good_surprise_roll = _context.rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
	if good_surprise_roll < region.option:
		var message = _context.content.scenario_records.message_by_id(absi(region.text_id))
		var prompt = message.text if message != null else "Take the advantage and enter battle?"
		exploration.active_random_region_id = region.id
		exploration.random_battle_stage = &"surprise-choice"
		var request_id = "random-surprise:%s:%d" % [region.id, _context.rng.snapshot().draw_count]
		_context.session_interaction = InteractionRequest.from_payload(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
		if region.sound_id > 0:
			events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
		return SessionCoordinatorResult.waiting(_context.session_interaction, events)
	var bad_surprise_roll = _context.rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
	var surprise = -1 if bad_surprise_roll < 10 else 0
	return start_random_battle(region, surprise, events)


func complete_random_program(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	if _context.session_continuation.kind == &"post-clock":
		_context.session_continuation.exploration().active_random_program_id = ""
		return complete_post_time(events)
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)


func move_after_pooled_wealth(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	var result := ExplorationMovementWorkflow.depart_camp(_context.workflow_context(), direction, preceding_events) if _context.state.party_camping else ExplorationMovementWorkflow.commit(_context.workflow_context(), direction, preceding_events)
	return finish_exploration_movement(result)


func finish_exploration_movement(result: ExplorationMovementWorkflow.MovementTransitionResult) -> SessionCoordinatorResult:
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	if not result.choice_kind.is_empty():
		return _begin_boat_choice(result)
	if not result.post_clock:
		return SessionCoordinatorResult.completed(result.events)
	set_post_time_continuation(result.map, result.resume_kind, result.direction, result.check_random, result.timed_day, result.timed_coordinate)
	return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _begin_boat_choice(result: ExplorationMovementWorkflow.MovementTransitionResult) -> SessionCoordinatorResult:
	var movement := result.choice_movement
	if movement == null or movement.source_map == null or movement.target_map == null or movement.topology_result == null or movement.topology_result.target_cell == null or result.choice_kind not in [&"board", &"disembark"]:
		return SessionCoordinatorResult.failed(&"invalid_boat_choice", "The Classic boat movement choice is unavailable.", result.events)
	var body := BoatContinuationBody.new()
	body.action = result.choice_kind
	body.source_map_id = movement.source_map.id
	body.source_coordinate = _context.state.party.coordinate
	body.target_map_id = movement.target_map.id
	body.target_coordinate = movement.target_coordinate
	body.direction = result.direction
	if body.direction == Vector2i.ZERO:
		return SessionCoordinatorResult.failed(&"invalid_boat_choice", "The Classic boat movement direction is unavailable.", result.events)
	_context.set_continuation(ExplorationContinuations.boat_choice(body))
	var prompt := "Board this boat?" if body.action == &"board" else "Leave the boat here and go ashore?"
	var yes_label := "Board" if body.action == &"board" else "Leave boat"
	var no_label := "Stay ashore" if body.action == &"board" else "Remain aboard"
	_context.session_interaction = InteractionRequest.from_payload("boat-choice:%s:%d" % [String(body.action), _context.next_revision()], &"yes_no", {"prompt": prompt, "yesLabel": yes_label, "noLabel": no_label})
	var events := result.events.duplicate()
	if body.action == &"disembark":
		events.append(ExplorationMovementWorkflow.sound_event(-148, "classic-boat-shore"))
	return SessionCoordinatorResult.waiting(_context.session_interaction, events)


func start_random_battle(region: RandomEncounterRegion, surprise: int, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var effective := _context.state.world.triggers.random_region(region)
	var battle_id := _context.rng.draw_between_classic(effective.battle_minimum, effective.battle_maximum, StringName("random-region.%s.battle" % region.id))
	var battle := _context.content.combat.battle_by_classic_id(absi(battle_id))
	if battle == null:
		_context.session_interaction = null
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(&"unknown_random_battle", "Random rectangle '%s' selected unavailable battle %d." % [region.id, battle_id], events)
	events.append(DomainEvent.new(&"random_encounter_triggered", {"regionId": region.id, "battleId": battle.id, "classicId": battle_id, "textId": region.text_id, "soundId": region.sound_id, "surprise": surprise}))
	var battle_result := _context.rules.combat_flow.start_battle(_context.state, _context.content, battle, _context.rng, surprise)
	if not battle_result.ok:
		_context.session_interaction = null
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(battle_result.error_code, battle_result.error_message, events)
	events.append_array(battle_result.events)
	if _context.state.combat != null and _context.session_continuation.kind == &"post-clock":
		var exploration := _context.session_continuation.exploration()
		exploration.random_region_index = -1 if region.only else exploration.random_region_index - 1
		_context.battle_return_continuation = _context.session_continuation.copy()
	if not CharacterAgingResult.update_payloads(battle_result.events).is_empty():
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.responses().finish_with_age_updates(events, &"combat-monster-turns")
	if not _context.event_payload(battle_result.events, &"monster_death_macro_requested").is_empty():
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.scenario().start_session_death_macro(events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	if battle_result.completed:
		return _context.scenario().finish_direct_battle(events)
	return SessionCoordinatorResult.completed(events)
