## Replays isolated session continuations from an explicitly supplied combat checkpoint.
extends SceneTree

var _failures: Array[String] = []
var _checks: Array[Dictionary] = []
var _content: RealmzContent
var _root: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or not args[2].is_absolute_path() or DirAccess.dir_exists_absolute(args[2]):
		quit(2)
		return
	_root = args[2]
	DirAccess.make_dir_recursive_absolute(_root)
	var repository := PackageRepository.new()
	var app := repository.load_package(ApplicationLibraryIdentity.PATH)
	if not app.is_ok():
		quit(2)
		return
	repository.set_application_content(app.content, app.media.assets())
	var loaded := repository.load_package(args[0])
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var saved := SaveEnvelope.from_data(document.get("result", {}).get("checkpoint", document))
	if not loaded.is_ok() or saved == null or saved.game_state.combat == null:
		quit(2)
		return
	_content = loaded.content
	_random_return(saved)
	_transfer_matrix(saved)
	_repeated_transfers(saved)
	_retreat_exit(saved)
	_defeat_exit(saved)
	if _checks.size() != 59: _failures.append("Incomplete session evidence: %d of 59 checks." % _checks.size())
	var file := FileAccess.open(_root.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": "realmz.clock-combat-session/1", "checkpointSha256": FileAccess.get_sha256(args[1]), "archiveSha256": FileAccess.get_sha256(args[0]), "packageHash": _content.package_hash, "applicationHash": _content.application_package_hash, "checks": _checks, "failures": _failures}, "\t"))
	file.close()
	for failure: String in _failures: printerr(failure)
	print("SESSION COMPATIBILITY: %d checks, %d failures" % [_checks.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _random_return(saved: SessionSnapshot) -> void:
	# Preparation represents a random battle's recorded origin, separately from its relocation.
	var field := saved.game_state.combat.battlefield
	var origin := field.source_origin + field.map_shift / BattlefieldBuilder.SCALE + Vector2i(15, 15)
	var body := ExplorationContinuationBody.new()
	body.map_id = field.map_id
	body.coordinate = origin
	body.resume_kind = &"move"
	body.direction = Vector2i.RIGHT
	body.random_region_ids.assign(saved.game_state.world.triggers.random_region_ids_at(_content.world.map_by_id(field.map_id), origin))
	body.random_region_index = -1
	var candidate := SessionSnapshot.new(saved.campaign_id, saved.package_hash, saved.rules_version, saved.view_revision, saved.game_state, saved.rng_state, saved.scenario_vm, saved.scenario_action_state, saved.continuation, ExplorationContinuations.post_clock(body), saved.session_interaction)
	var session := _restore_readback(candidate, "relocated-random-battle")
	if session == null: return
	var invalid := SaveEnvelope.from_snapshot(candidate).to_data()
	invalid["battleReturnContinuation"]["data"]["x"] += 1
	var bad := SaveEnvelope.from_data(invalid)
	_check(bad != null and GameSession.new().restore(_content, bad).state == SessionStep.State.FAILED, "wrong random-battle origin is rejected")
	# Revive only the known relocation-macro enemy for an ordinary final attack.
	var prepared := session.snapshot()
	var state := prepared.game_state
	var hero := state.party.character_by_id("classic.starter.silver-leaf")
	state.combat.turns.turn_index = state.combat.turns.turn_order().find(hero.id)
	state.combat.turns.active_turn = CombatTurnState.new(hero.id)
	state.combat.turns.undo_state = null
	var survivor: MonsterState
	for monster: MonsterState in state.combat.roster.monsters():
		state.combat.battlefield.actors.remove_monster(monster.id)
		if survivor == null and _content.combat.monster_by_id(monster.definition_id).classic_id == 41: survivor = monster
		monster.current_health = 0
	if hero == null or survivor == null:
		_check(false, "ordinary victory fixture has the active actor and alternate monster 41")
		return
	hero.to_hit = 200
	hero.hand_to_hand = 100
	hero.damage_bonus = 200
	survivor.current_health = 1
	survivor.traitor = true
	if not state.combat.battlefield.actors.place_monster(survivor.id, state.combat.battlefield.actors.character_position(hero.id) + Vector2i(1, 1), _content.combat.monster_by_id(survivor.definition_id).size):
		_check(false, "ordinary victory target placement fits its complete footprint")
		return
	var restored := GameSession.new()
	var accepted := restored.restore(_content, prepared)
	_check(accepted.state == SessionStep.State.COMPLETED, "prepared ordinary victory validates: " + accepted.error_message)
	if accepted.state != SessionStep.State.COMPLETED: return
	var destination := state.party.coordinate
	var step := restored.submit_intent(CombatIntents.choose_action(&"attack", hero.id, survivor.id))
	for boundary: int in 8:
		if step.state != SessionStep.State.WAITING_FOR_INTERACTION: break
		var request := step.interaction
		if request.kind != InteractionRequest.TREASURE_DISTRIBUTION: break
		step = restored.respond(InteractionResponse.new(request.request_id, request.kind, InteractionResponse.TreasureBody.new(&"done")))
	_check(step.state == SessionStep.State.COMPLETED and restored.snapshot() != null and restored.snapshot().game_state.combat == null and restored.snapshot().game_state.party.coordinate == destination and restored.snapshot().game_state.party.map_id == state.party.map_id and restored.snapshot().battle_return_continuation == null, "ordinary victory preserves relocation and cancels the source travel step")
	_restore_readback(restored.snapshot(), "after-ordinary-victory")


func _transfer_matrix(saved: SessionSnapshot) -> void:
	var source := _content.world.map_by_id(saved.game_state.combat.battlefield.map_id)
	var sources: Array[MapDefinition] = [source]
	for map_id: String in _content.world.map_ids():
		var map := _content.world.map_by_id(map_id)
		if map.level_type == &"dungeon":
			sources.append(map)
			break
	for origin: MapDefinition in sources:
		_transfer_from(saved, origin)


func _transfer_from(saved: SessionSnapshot, source: MapDefinition) -> void:
	var destinations: Array[MapDefinition] = [source]
	for kind: StringName in [&"land", &"dungeon"]:
		for map_id: String in _content.world.map_ids():
			var map := _content.world.map_by_id(map_id)
			if map.level_type == kind and map.id != source.id:
				destinations.append(map)
				break
	for opcode: int in [20, 37, 45]:
		for map: MapDefinition in destinations:
			if opcode != 37 and map.level_type != source.level_type: continue
			var state := GameState.from_data(saved.game_state.to_data())
			state.party.map_id = source.id
			var coordinate := Vector2i(10, 10)
			var words: Array[int] = []
			words.assign([int(map.level_type == &"land"), map.level_index, coordinate.x, coordinate.y, 1] if opcode == 37 else [map.level_index, coordinate.x, coordinate.y, 0, 0])
			var before := CanonicalJson.encode(state.combat.to_data())
			var rng := RealmzRng.new()
			rng.restore(saved.rng_state)
			var api := RealmzRuntimeApi.new(_content, state, rng, ScenarioActionState.new())
			var result := api.execute_classic(ClassicActionDefinition.new(0, opcode, opcode, 0, false, words), "transfer", ScenarioExecutionContext.calling(&"monster-death-macro"))
			var label := "%s %d -> %s" % [source.id, opcode, map.id]
			_check(result.state == ScenarioRuntimeOperationResult.State.COMPLETED and state.party.map_id == map.id and state.party.coordinate == coordinate and CanonicalJson.encode(state.combat.to_data()) == before and rng.snapshot().to_data() == saved.rng_state.to_data(), label + " commits relocation without altering battlefield, actors, fields, turn or RNG")
			var candidate := SessionSnapshot.new(saved.campaign_id, saved.package_hash, saved.rules_version, saved.view_revision, state, rng.snapshot(), saved.scenario_vm, saved.scenario_action_state)
			var session := _restore_readback(candidate, "transfer-%s-%d-%s" % [source.id.replace(":", "-"), opcode, map.id.replace(":", "-")])
			if session == null: continue
			var hero := session.snapshot().game_state.combat.turns.active_actor_id()
			var step := session.submit_intent(CombatIntents.choose_action(&"defend", hero))
			_check(step.state != SessionStep.State.FAILED and session.snapshot() != null, label + " Guard remains executable after full restore")


func _repeated_transfers(saved: SessionSnapshot) -> void:
	var state := GameState.from_data(saved.game_state.to_data())
	var actor := state.combat.turns.active_actor_id()
	var spell := _content.magic.spell_by_classic_id(3209)
	var field := state.combat.spell_runtime.queue_persistent_field(spell.id, actor, Vector2i(20, 20), 0, 18, spell.queue_icon, 1, 1, 20)
	_check(field != null, "repeated transfer fixture has a live typed persistent field")
	var before := CanonicalJson.encode(state.combat.to_data())
	var rng := RealmzRng.new()
	rng.restore(saved.rng_state)
	var api := RealmzRuntimeApi.new(_content, state, rng, ScenarioActionState.new())
	for words: Array in [[0, 1, 10, 10, 1], [1, 5, 62, 10, 1], [0, 2, 20, 20, 1]]:
		var operands: Array[int] = []
		operands.assign(words)
		var result := api.execute_classic(ClassicActionDefinition.new(0, 37, 37, 0, false, operands), "repeated-transfer")
		_check(result.state == ScenarioRuntimeOperationResult.State.COMPLETED and CanonicalJson.encode(state.combat.to_data()) == before and rng.snapshot().to_data() == saved.rng_state.to_data(), "repeated transfer %s preserves terrain, field, occupancy and turn" % [words])
	_restore_readback(SessionSnapshot.new(saved.campaign_id, saved.package_hash, saved.rules_version, saved.view_revision, state, rng.snapshot(), saved.scenario_vm, saved.scenario_action_state), "repeated-transfers")


func _retreat_exit(saved: SessionSnapshot) -> void:
	var state := GameState.from_data(saved.game_state.to_data())
	var hero := state.party.character_by_id(state.combat.turns.active_actor_id())
	state.combat.turns.undo_state = null
	for other: CharacterState in state.party.characters():
		if other.id != hero.id:
			if other.current_health > 0: state.combat.actor_statuses.mark_character_retreated(other.id)
			state.combat.battlefield.actors.remove_character(other.id)
	state.combat.battlefield.actors.place_character(hero.id, Vector2i(3, 3))
	if CombatStateCodec.decode(state.combat.to_data()) == null:
		_check(false, "retreat fixture combat codec is valid")
		return
	var snapshot := SessionSnapshot.new(saved.campaign_id, saved.package_hash, saved.rules_version, saved.view_revision, state, saved.rng_state, saved.scenario_vm, saved.scenario_action_state)
	var session := _restore_readback(snapshot, "before-retreat")
	if session == null: return
	var step := session.submit_intent(CombatIntents.choose_action(&"retreat", hero.id))
	if step.state == SessionStep.State.WAITING_FOR_INTERACTION and step.interaction.kind == InteractionRequest.YES_NO:
		session = _restore_readback(session.snapshot(), "pending-retreat")
		if session == null: return
		step = session.respond(InteractionResponse.yes_no(session.snapshot().pending_interaction(), true))
	var after := session.snapshot()
	_check(step.state == SessionStep.State.COMPLETED and after != null and after.game_state.combat == null and after.game_state.last_battle_outcome == &"retreated" and after.game_state.party.map_id == state.party.map_id and after.game_state.party.coordinate == state.party.coordinate, "ordinary retreat keeps the committed relocation without victory or rewards")
	if after != null: _restore_readback(after, "after-retreat")


func _defeat_exit(saved: SessionSnapshot) -> void:
	var state := GameState.from_data(saved.game_state.to_data())
	var hero := state.party.character_by_id(state.combat.turns.active_actor_id())
	var enemy: MonsterState
	for monster: MonsterState in state.combat.roster.monsters():
		state.combat.battlefield.actors.remove_monster(monster.id)
		monster.current_health = 0
		if enemy == null and _content.combat.monster_by_id(monster.definition_id).size == 0: enemy = monster
	for character: CharacterState in state.party.characters():
		character.current_health = 1 if character.id == hero.id else -10
		character.armor = -100
		character.conditions = ConditionSet.new()
		state.combat.actor_statuses.set_character_bleeding(character.id, false)
		state.combat.battlefield.actors.remove_character(character.id)
	if enemy == null:
		_check(false, "defeat fixture has a source-defined single-cell enemy")
		return
	enemy.current_health = enemy.maximum_health
	enemy.hit_dice = 100
	enemy.traitor = true
	enemy.spell_points = 0
	enemy.conditions = ConditionSet.new()
	state.combat.battlefield.actors.place_character(hero.id, Vector2i(45, 45))
	state.combat.battlefield.actors.place_monster(enemy.id, Vector2i(46, 45), 0)
	state.combat.turns.undo_state = null
	state.combat.turns.active_turn = CombatTurnState.new(hero.id)
	var candidate := SessionSnapshot.new(saved.campaign_id, saved.package_hash, saved.rules_version, saved.view_revision, state, saved.rng_state, saved.scenario_vm, saved.scenario_action_state)
	var session := _restore_readback(candidate, "before-defeat")
	if session == null: return
	var step := session.submit_intent(CombatIntents.choose_action(&"finish", hero.id))
	var defeated := step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_completed" and event.payload.get("outcome") == "defeat")
	_check(step.state != SessionStep.State.FAILED and defeated and not step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_reward_constructed"), "ordinary Finish permits the surviving enemy to defeat the relocated party without rewards: " + step.error_message)
	var after := session.snapshot()
	if after != null:
		_check(after.game_state.party.map_id == state.party.map_id and after.game_state.party.coordinate == state.party.coordinate and after.game_state.last_battle_outcome == &"defeat", "defeat retains the authored exploration destination")
	else:
		_check(defeated and step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended"), "terminal defeat closes through its ordinary lifecycle")


func _restore_readback(snapshot: SessionSnapshot, label: String) -> GameSession:
	if snapshot == null:
		_check(false, label + " has a snapshot")
		return null
	var repository := SaveRepository.new(_root.path_join(label))
	var ok := repository.save(snapshot.campaign_id, "A", snapshot)
	var loaded := repository.load(snapshot.campaign_id, "A", snapshot.package_hash) if ok else null
	var session := GameSession.new()
	var result := session.restore(_content, loaded) if loaded != null else null
	_check(result != null and result.state == SessionStep.State.COMPLETED, label + " v6 write/readback and detached session restore" + (": " + result.error_message if result != null and result.state == SessionStep.State.FAILED else ""))
	return session if result != null and result.state == SessionStep.State.COMPLETED else null


func _check(passed: bool, label: String) -> void:
	_checks.append({"case": label, "passed": passed})
	if not passed: _failures.append(label)
