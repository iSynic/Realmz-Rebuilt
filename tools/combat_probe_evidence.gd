## Captures exact combat outcomes and isolated decision costs outside simulation.
extends RefCounted


class CountedBattlefield:
	extends BattlefieldRules

	var route_queries := 0
	var repeated_routes := 0
	var los_queries := 0
	var route_keys: Dictionary = {}

	func probe_path_step_toward_actors(field: BattlefieldState, terrain: BattleTerrainSetDefinition, actor_id: String, target_ids: Array[String], movement: int, swappable: Array[String] = [], forbidden: Array[Vector2i] = [], anchors: Array[Vector2i] = [], contact: bool = true) -> BattlefieldStepResult:
		route_queries += 1
		var excluded := forbidden.duplicate()
		excluded.erase(field.actors.actor_position(actor_id))
		var key := str([field.terrain.revision(), field.actors.revision(), actor_id, target_ids, movement, swappable, excluded, anchors, contact])
		if route_keys.has(key): repeated_routes += 1
		route_keys[key] = true
		return super.probe_path_step_toward_actors(field, terrain, actor_id, target_ids, movement, swappable, forbidden, anchors, contact)

	func has_line_of_sight_to_coordinate(field: BattlefieldState, terrain: BattleTerrainSetDefinition, actor_id: String, destination: Vector2i, origin: Vector2i = Vector2i(-1, -1), occupied: Dictionary = {}) -> bool:
		los_queries += 1
		return super.has_line_of_sight_to_coordinate(field, terrain, actor_id, destination, origin, occupied)


static func outcome(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> Dictionary:
	var recorded: Array[Dictionary] = []
	for event: DomainEvent in events: recorded.append(event.to_data())
	return {"state": state.to_data(), "rng": rng.snapshot().to_data(), "rngTrace": rng.trace(), "events": recorded}


static func write_evidence(directory: String, evidence: Dictionary) -> bool:
	if not directory.is_absolute_path() or DirAccess.dir_exists_absolute(directory):
		printerr("EVIDENCE_REJECTED: use a new absolute evidence directory.")
		return false
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	for name: String in evidence:
		var file := FileAccess.open(directory.path_join(name + ".json"), FileAccess.WRITE)
		if file == null: return false
		file.store_string(CanonicalJson.encode(evidence[name]) + "\n")
	return true


static func decision_phases(initial: Dictionary, content: RealmzContent, random_state: RealmzRngState) -> Dictionary:
	var state := GameState.from_data(initial)
	var rules := RealmzRules.new()
	var context := CombatContext.new(rules)
	var flow := rules.combat_flow
	context.bind_collaborators(flow.rounds, flow.actions, flow.reactions, flow.magic, flow.fields, flow.summoning, flow.phase, flow.automation)
	var actor := state.party.character_by_id(state.combat.turns.active_actor_id())
	flow.actions.prepare_character_turn(state.combat, actor)
	var selection := flow.magic.selection()
	var admitted := 0
	var started := Time.get_ticks_usec()
	for spell_id: String in actor.known_spells():
		for power: int in range(1, 8):
			if selection.probe_character_spell_choice(state, content, actor.id, spell_id, power).allowed: admitted += 1
	var admission_us := Time.get_ticks_usec() - started
	var pursuit := CombatPartyAutomation.new(context)
	started = Time.get_ticks_usec()
	var move := pursuit.plan_pursuit_step(state, content, actor, [state.combat.battlefield.actors.actor_position(actor.id)])
	var pursuit_us := Time.get_ticks_usec() - started
	var rng := RealmzRng.for_oracle()
	rng.restore(random_state)
	started = Time.get_ticks_usec()
	var choice := CombatPartyActionPlanner.new(context).choose_party_action(state, content, actor, rng, move)
	var scoring_us := Time.get_ticks_usec() - started
	return {"spellAdmissionMs": admission_us / 1000.0, "pursuitMs": pursuit_us / 1000.0, "scoringMs": scoring_us / 1000.0, "knownSpellCount": actor.known_spells().size(), "spellPowerCandidates": actor.known_spells().size() * 7, "admittedSpellPowers": admitted, "selectedAction": String(choice.get("action", ""))}


static func query_counts(initial: Dictionary, content: RealmzContent, random_state: RealmzRngState, actor_ids: Array[String], auto: bool, expected: Dictionary) -> Dictionary:
	var state := GameState.from_data(initial)
	var rng := RealmzRng.for_oracle()
	rng.restore(random_state)
	var rules := RealmzRules.new()
	var counted := CountedBattlefield.new()
	rules.battlefield = counted
	rules.combat_flow = CombatFlow.new(rules)
	var events: Array[DomainEvent] = []
	for actor_id: String in actor_ids:
		var result := rules.combat_flow.submit_action(state, content, actor_id, &"auto" if auto else &"finish", "", rng)
		if not result.ok: return {"error": String(result.error_code)}
		events.append_array(result.events)
	var actual := outcome(state, rng, events)
	# The Auto timing run retains setup draws; compare only this command's draws.
	var expected_draws: Array = expected["rngTrace"].filter(func(entry: Dictionary) -> bool: return int(entry["drawIndex"]) >= random_state.draw_count)
	var matches: bool = CanonicalJson.encode(actual["state"]) == CanonicalJson.encode(expected["state"]) and CanonicalJson.encode(actual["events"]) == CanonicalJson.encode(expected["events"]) and CanonicalJson.encode(actual["rngTrace"]) == CanonicalJson.encode(expected_draws) and actual["rng"] == expected["rng"]
	return {"routeQueries": counted.route_queries, "repeatedRouteQueries": counted.repeated_routes, "losQueries": counted.los_queries, "exactOutcomeMatches": matches}
