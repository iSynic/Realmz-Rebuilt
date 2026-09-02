extends SceneTree

const PACKAGE_REPOSITORY_SCRIPT := preload("res://src/infrastructure/packages/package_repository.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/movement_performance_probe.gd -- <package.realmz2>")
		call_deferred("_quit_cleanly", 2)
		return
	var loaded := PACKAGE_REPOSITORY_SCRIPT.new().load_package(arguments[0])
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var session := GameSession.new()
	var step := session.start(loaded.content, 1)
	if step.state == SessionStep.State.FAILED or not _assemble_six_character_party(session, loaded.content):
		printerr("SESSION_REJECTED: a six-character public setup could not be prepared")
		call_deferred("_quit_cleanly", 1)
		return
	var pair := _safe_movement_pair(session, loaded.content)
	if pair.is_empty() or not _place_party(session, loaded.content, pair["origin"], 4096):
		printerr("SESSION_REJECTED: no trigger-free movement pair is available")
		call_deferred("_quit_cleanly", 1)
		return
	var direction: Vector2i = pair["direction"]
	var transaction_samples: Array[int] = []
	var projection_samples: Array[int] = []
	var ordinary_transaction_samples: Array[int] = []
	var hourly_transaction_samples: Array[int] = []
	var ordinary_projection_samples: Array[int] = []
	var hourly_projection_samples: Array[int] = []
	var ordinary_domain_samples: Dictionary = {}
	var hourly_domain_samples: Dictionary = {}
	var event_kinds: Array[String] = []
	var event_sequences: Dictionary = {}
	var fatigue_payload: Dictionary = {}
	var ordinary_projection_count := 0
	for index: int in 60:
		var previous_view := session.view()
		var started_at := Time.get_ticks_usec()
		step = session.submit_intent(PlayerIntent.move(direction))
		var transaction_done := Time.get_ticks_usec()
		var view := session.view(step.events)
		var projection_done := Time.get_ticks_usec()
		if step.state != SessionStep.State.COMPLETED or view.pending_interaction != null:
			printerr("MOVEMENT_INTERRUPTED step=%d state=%d events=%s" % [index, step.state, step.events.map(func(event: DomainEvent) -> String: return String(event.kind))])
			call_deferred("_quit_cleanly", 1)
			return
		if index == 0:
			for event: DomainEvent in step.events:
				event_kinds.append(String(event.kind))
		var sequence := ",".join(step.events.map(func(event: DomainEvent) -> String: return String(event.kind)))
		event_sequences[sequence] = int(event_sequences.get(sequence, 0)) + 1
		for event: DomainEvent in step.events:
			if event.kind == &"fatigue_changed" and fatigue_payload.is_empty():
				fatigue_payload = event.payload.duplicate(true)
		if view.domain_revisions.is_ordinary_exploration_update_from(previous_view.domain_revisions):
			ordinary_projection_count += 1
		if index >= 10:
			transaction_samples.append(transaction_done - started_at)
			projection_samples.append(projection_done - transaction_done)
			var hourly := step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"fatigue_changed" and String(event.payload.get("reason", "")) == "hour-boundary")
			(hourly_transaction_samples if hourly else ordinary_transaction_samples).append(transaction_done - started_at)
			(hourly_projection_samples if hourly else ordinary_projection_samples).append(projection_done - transaction_done)
			_append_domain_timings(hourly_domain_samples if hourly else ordinary_domain_samples, view.projection_timings_usec)
		direction = -direction
	var total_samples: Array[int] = []
	for index: int in transaction_samples.size():
		total_samples.append(transaction_samples[index] + projection_samples[index])
	var output := {
		"campaignId": loaded.content.campaign_id,
		"partySize": session.view().party_members.size(),
		"sampleCount": total_samples.size(),
		"transactionP95Ms": _p95_milliseconds(transaction_samples),
		"projectionP95Ms": _p95_milliseconds(projection_samples),
		"transactionPlusProjectionP95Ms": _p95_milliseconds(total_samples),
		"ordinaryTransactionP95Ms": _p95_milliseconds(ordinary_transaction_samples),
		"ordinaryProjectionP95Ms": _p95_milliseconds(ordinary_projection_samples),
		"hourlyTransactionP95Ms": _p95_milliseconds(hourly_transaction_samples),
		"hourlyProjectionP95Ms": _p95_milliseconds(hourly_projection_samples),
		"ordinaryProjectionDomainsP95Ms": _domain_p95_milliseconds(ordinary_domain_samples),
		"hourlyProjectionDomainsP95Ms": _domain_p95_milliseconds(hourly_domain_samples),
		"scheduledStepsPerSecond100": 20,
		"scheduledStepsPerSecond400": 80,
		"ordinaryProjectionCount": ordinary_projection_count,
		"visitedHistorySize": session.view().map_view.visited_coordinates().size(),
		"eventKinds": event_kinds,
		"eventSequences": event_sequences,
		"fatiguePayload": fatigue_payload,
		"finalX": session.view().party_coordinate.x,
		"finalY": session.view().party_coordinate.y,
	}
	print(CanonicalJson.encode(output))
	if ordinary_projection_count != 60:
		printerr("MOVEMENT_INCREMENTAL_PROJECTION_MISSED expected=60 actual=%d sequences=%s" % [ordinary_projection_count, event_sequences])
		call_deferred("_quit_cleanly", 1)
		return
	if float(output["transactionPlusProjectionP95Ms"]) > 3.0:
		printerr("MOVEMENT_P95_EXCEEDED expectedAtMostMs=3 actualMs=%s" % output["transactionPlusProjectionP95Ms"])
		call_deferred("_quit_cleanly", 1)
		return
	call_deferred("_quit_cleanly", 0)


func _assemble_six_character_party(session: GameSession, content: RealmzContent) -> bool:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	if races.is_empty() or castes.is_empty():
		return false
	var race: RaceDefinition
	var caste: CasteDefinition
	var caster_type := 0
	for race_candidate: RaceDefinition in races:
		for caste_candidate: CasteDefinition in castes:
			if not race_candidate.eligible_caste_ids.is_empty() and not race_candidate.eligible_caste_ids.has(caste_candidate.id):
				continue
			var rows := caste_candidate.spellcaster_rows()
			for row_index: int in mini(3, rows.size()):
				if rows[row_index].y > 0:
					race = race_candidate; caste = caste_candidate; caster_type = row_index + 1
					break
			if caste != null: break
		if caste != null: break
	if race == null or caste == null:
		return false
	var known_spells: Array[String] = []
	for spell: SpellDefinition in content.spell_definitions():
		if int(spell.classic_id / 1000) == caster_type and spell.classic_tier() >= 0:
			known_spells.append(spell.id)
			if known_spells.size() >= 4: break
	for index: int in 6:
		var character := CharacterState.new("movement-probe-%d" % index, "Probe %d" % (index + 1), 20, 20)
		character.level = 10
		character.spellcaster_type = caster_type
		character.maximum_spell_points = 100
		character.spell_points = 0
		character.set_known_spells(known_spells)
		character.race_id = race.id
		character.caste_id = caste.id
		var imported := session.submit_intent(PlayerIntent.import_vault_character(character.id, "%064d" % (index + 1), character, "movement-probe", content.package_hash))
		if imported.state == SessionStep.State.FAILED:
			return false
	var started := session.submit_intent(PlayerIntent.begin_adventure())
	for ignored: int in 16:
		if started.state != SessionStep.State.WAITING_FOR_INTERACTION:
			break
		if started.interaction == null or started.interaction.kind != InteractionRequest.ACKNOWLEDGE:
			return false
		started = session.respond(InteractionResponse.acknowledge(started.interaction))
	return started.state == SessionStep.State.COMPLETED and session.view().party_members.size() == 6


func _safe_movement_pair(session: GameSession, content: RealmzContent) -> Dictionary:
	var state := session.snapshot().game_state
	var map := content.world.map_by_id(state.party.map_id)
	if map == null:
		return {}
	var directions := MapTopology.land_directions() if map.level_type == &"land" else MapTopology.cardinal_directions()
	for cell: MapCell in map.topology.cells():
		if not _safe_cell(cell):
			continue
		for direction: Vector2i in directions:
			var movement := content.world.probe_movement(map.id, cell.coordinate, direction, state.world)
			if movement.allowed and movement.target_map == map and _safe_cell(movement.topology_result.target_cell):
				return {"origin": cell.coordinate, "direction": direction}
	return {}


static func _safe_cell(cell: MapCell) -> bool:
	return cell != null and cell.passable and cell.trigger_ids().is_empty() and cell.random_rect_ids().is_empty() and cell.features().is_empty()


func _place_party(session: GameSession, content: RealmzContent, coordinate: Vector2i, visited_history_target: int = 0) -> bool:
	var snapshot := session.snapshot()
	snapshot.game_state.party.coordinate = coordinate
	var map := content.world.map_by_id(snapshot.game_state.party.map_id)
	if map != null:
		var seeded := 0
		for cell: MapCell in map.topology.cells():
			snapshot.game_state.world.mark_visited(map.id, cell.coordinate); seeded += 1
			if seeded >= visited_history_target: break
	snapshot.game_state.world.mark_visited(snapshot.game_state.party.map_id, coordinate)
	return session.restore(content, snapshot).state == SessionStep.State.COMPLETED


static func _p95_milliseconds(samples: Array[int]) -> float:
	if samples.is_empty():
		return 0.0
	var ordered := samples.duplicate()
	ordered.sort()
	var index := clampi(ceili(float(ordered.size()) * 0.95) - 1, 0, ordered.size() - 1)
	return snappedf(float(ordered[index]) / 1000.0, 0.001)


static func _append_domain_timings(samples: Dictionary, timings: Dictionary) -> void:
	for domain: String in timings:
		if not samples.has(domain): samples[domain] = [] as Array[int]
		(samples[domain] as Array[int]).append(int(timings[domain]))


static func _domain_p95_milliseconds(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for domain: String in samples:
		result[domain] = _p95_milliseconds(samples[domain] as Array[int])
	return result


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
