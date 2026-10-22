## Verifies native timer/AP ownership through ordinary movement and disposable saves.
extends RefCounted

var checks: Array[Dictionary] = []
var failures: Array[String] = []
var _base: RealmzContent
var _root: String


func run(base: RealmzContent, scratch: String) -> Dictionary:
	_base = base
	_root = scratch
	for mode: String in ["header", "admitted", "zero", "disabled", "chance-failed", "keep", "erase", "no-match", "ordinary", "early-return", "no-due", "wait", "start-hook", "post-header", "empty-return", "gosub-live", "gosub-wait", "item", "item-wait"]:
		_case(mode)
	_item_rollback()
	if checks.size() != 42: failures.append("Timer/AP evidence is incomplete: %d of 42 checks." % checks.size())
	return {"mode": "prepared-ordinary-movement-save-readback-and-direct-rollback", "checks": checks, "failures": failures}


func _item_rollback() -> void:
	var context := SessionContext.new()
	context.begin(_base, 17)
	context.classic_execution.begin_timer(_base.start_map_id, _base.start_coordinate)
	var native_checkpoint := context.classic_execution.to_data()
	var state_checkpoint := context.state.to_data()
	var rng_checkpoint := context.rng.checkpoint()
	var vm_checkpoint := context.scenario_vm.snapshot()
	var action_checkpoint := context.scenario_action_state.to_data()
	context.classic_execution.coordinate += Vector2i.RIGHT
	var coordinator := SessionScenarioCoordinator.new(context)
	var restored: bool = coordinator.call("_rollback_item_xap", state_checkpoint, rng_checkpoint, vm_checkpoint, action_checkpoint, native_checkpoint)
	_check(restored and context.classic_execution.to_data() == native_checkpoint and context.runtime_api.classic_execution() == context.classic_execution and CanonicalJson.encode(context.state.to_data()) == CanonicalJson.encode(state_checkpoint) and context.rng.checkpoint() == rng_checkpoint, "direct item-XAP rollback restores the native preimage and shared API owner")


func _case(mode: String) -> void:
	var content := _content(mode)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [_hero(content, mode.begins_with("item"))]), RealmzClock.new())
	if mode.begins_with("item"): state.party.characters()[0].set_inventory([ItemInstance.new("timer.door-instance", "timer.door", 2, true)])
	state.party_setup_completed = mode != "start-hook"
	state.random_encounters_enabled = false
	state.clock.set_components(7, 23, 0)
	if mode in ["ordinary", "post-header"]: state.clock.set_components(7, 23, 55)
	if mode == "disabled": state.world.triggers.disable_trigger("arrival")
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	var session := GameSession.new()
	var prepared := session.restore(content, SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, RealmzRng.new(1).snapshot(), vm.snapshot(), ScenarioActionState.new()))
	if prepared.state != SessionStep.State.COMPLETED:
		_check(false, mode + " fixture preparation: " + prepared.error_message)
		return
	var result := session.submit_intent(InventoryIntents.use("timer.door-instance", "timer.hero") if mode.begins_with("item") else PartyIntents.begin_adventure() if mode == "start-hook" else ExplorationIntents.move(Vector2i.RIGHT))
	if mode.begins_with("item"): _check(session.snapshot().game_state.party.characters()[0].inventory()[0].charges == 1, "ordinary " + mode + " spends exactly one door-item charge")
	if mode in ["wait", "item-wait"]:
		_saved_arrival(content, session, result, mode)
		return
	if mode == "gosub-wait":
		_saved_gosub(content, session, result)
		return
	var saved := session.snapshot()
	var expected_count := 0 if mode in ["header", "zero", "disabled", "chance-failed", "no-match", "early-return", "no-due", "post-header", "empty-return", "gosub-live"] else 1
	var expected_following := 2 if mode in ["admitted", "start-hook", "empty-return", "gosub-live", "item"] else 1 if mode in ["zero", "disabled", "chance-failed", "ordinary"] else 0
	var expected_coordinate := Vector2i(1, 1) if mode in ["header", "early-return", "empty-return", "gosub-live"] else Vector2i(2, 1) if mode in ["no-match", "ordinary"] else Vector2i(3, 1)
	var expected_draws := 1 if mode == "no-due" else 2 if mode in ["header", "zero", "disabled", "no-match", "early-return", "ordinary", "empty-return", "gosub-live"] else 3
	if mode == "ordinary": expected_draws = 3
	if mode in ["start-hook", "item"]: expected_draws = 2
	if mode == "post-header": expected_draws = 4
	var progress := saved.game_state.scenario_progress if saved != null else null
	var expected_source_removed := mode in ["header", "early-return", "no-due", "no-match", "post-header", "empty-return", "gosub-live"]
	var expected_arrival_removed := mode in ["admitted", "zero", "disabled", "chance-failed", "erase"]
	_check(result.state == SessionStep.State.COMPLETED and progress != null and saved.game_state.party.coordinate == expected_coordinate and progress.quest_value(50) == expected_count and progress.quest_value(51) == (2 if mode == "post-header" else 0) and progress.quest_value(91) == expected_following and saved.game_state.world.triggers.trigger_is_disabled("source") == expected_source_removed and saved.game_state.world.triggers.trigger_is_disabled("arrival") == expected_arrival_removed and saved.rng_state.draw_count == expected_draws and progress.quest_value(96) == (1 if mode == "no-match" else 0) and progress.quest_value(99) == (1 if mode == "ordinary" else 0), "timer native ownership " + mode)
	session.close()


func _saved_gosub(content: RealmzContent, session: GameSession, step: SessionStep) -> void:
	var before := session.snapshot()
	var repository := SaveRepository.new(_root.path_join("gosub"))
	var written := before != null and step.state == SessionStep.State.WAITING_FOR_INTERACTION and repository.save(content.campaign_id, "A", before)
	var saved := repository.load(content.campaign_id, "A", content.package_hash) if written else null
	_check(saved != null and CanonicalJson.encode(saved.to_data()) == CanonicalJson.encode(SaveEnvelope.from_snapshot(before).to_data()), "GOSUB header survives actual v6 write/readback at the callee ACK")
	if saved == null: return
	for mutation: String in ["missing", "null", "map", "coordinate"]:
		var document := saved.to_data()
		var caller: Dictionary = document["scenarioVm"]["pendingContinuation"]["data"]["runtime"]["data"]["timerVm"]["frames"][0]
		match mutation:
			"missing": caller.erase("nativeReturnDestination")
			"null": caller["nativeReturnDestination"] = null
			"map": caller["nativeReturnDestination"]["mapId"] = "missing-map"
			"coordinate": caller["nativeReturnDestination"]["x"] = 2_147_483_647
		var bad := SaveEnvelope.from_data(document)
		var candidate := GameSession.new()
		_check(bad == null or candidate.restore(content, bad).state == SessionStep.State.FAILED, "GOSUB return header rejects " + mutation)
	var resumed := GameSession.new()
	var restored := resumed.restore(content, saved)
	_check(restored.state == SessionStep.State.COMPLETED, "GOSUB callee ACK restores the complete session")
	if restored.state != SessionStep.State.COMPLETED: return
	var result := resumed.respond(InteractionResponse.acknowledge(resumed.snapshot().pending_interaction()))
	var after := resumed.snapshot()
	_check(result.state == SessionStep.State.COMPLETED and after.game_state.party.coordinate == Vector2i(1, 1) and after.game_state.scenario_progress.quest_value(91) == 2 and after.game_state.scenario_progress.quest_value(50) == 0 and after.game_state.world.triggers.trigger_is_disabled("source") and not after.game_state.world.triggers.trigger_is_disabled("arrival") and after.rng_state.draw_count == 2, "GOSUB111 restores its captured header without restoring the global AP identity or replaying the timer")
	resumed.close()


func _saved_arrival(content: RealmzContent, session: GameSession, step: SessionStep, mode: String) -> void:
	var before := session.snapshot()
	_check(step.state == SessionStep.State.WAITING_FOR_INTERACTION and before != null and before.pending_interaction() != null and before.pending_interaction().kind == InteractionRequest.ACKNOWLEDGE, "timer arrival waits inside the current native invocation")
	if before == null or before.pending_interaction() == null: return
	var repository := SaveRepository.new(_root.path_join(mode))
	var written := repository.save(content.campaign_id, "A", before)
	var restored := repository.load(content.campaign_id, "A", content.package_hash) if written else null
	_check(restored != null and CanonicalJson.encode(SaveEnvelope.from_snapshot(before).to_data()) == CanonicalJson.encode(restored.to_data()), "timer arrival complete v6 write/readback preserves shared and invocation facts")
	if restored == null: return
	for mutation: String in ["map", "trigger", "coordinate", "missing-shared"]:
		var document := restored.to_data()
		match mutation:
			"map": document["classicExecution"]["mapId"] = "missing-map"
			"trigger": document["classicExecution"]["triggerId"] = "missing-trigger"
			"coordinate": document["classicExecution"]["x"] = 2_147_483_647
			"missing-shared": document["classicExecution"] = ClassicExecutionState.new().to_data()
		var bad := SaveEnvelope.from_data(document)
		var candidate := GameSession.new()
		_check(bad != null and candidate.restore(content, bad).state == SessionStep.State.FAILED, "saved timer rejects " + mutation + " without guessing header history")
	var resumed := GameSession.new()
	var admitted := resumed.restore(content, restored)
	_check(admitted.state == SessionStep.State.COMPLETED and resumed.snapshot().classic_execution.to_data() == before.classic_execution.to_data(), "saved timer restores the one shared native header")
	if admitted.state != SessionStep.State.COMPLETED: return
	var completed := resumed.respond(InteractionResponse.acknowledge(resumed.snapshot().pending_interaction()))
	var after := resumed.snapshot()
	var item_mode := mode == "item-wait"
	_check(completed.state == SessionStep.State.COMPLETED and after.game_state.scenario_progress.quest_value(91) == 2 and after.game_state.scenario_progress.quest_value(96) == 0 and after.game_state.scenario_progress.quest_value(90) == 0 and not after.game_state.world.triggers.trigger_is_disabled("source") and after.game_state.world.triggers.trigger_is_disabled("arrival") == not item_mode and after.game_state.party.coordinate == Vector2i(3, 1) and after.rng_state.draw_count == (2 if item_mode else 3) and (not item_mode or after.game_state.party.characters()[0].inventory()[0].charges == 1), "saved " + mode + " returns to the selected AP's following slot exactly once")
	resumed.close()


func _content(mode: String) -> RealmzContent:
	var caller := ScenarioProgramDefinition.new("ap:source", &"trigger", "source", [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0]), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
	if mode == "post-header": caller = ScenarioProgramDefinition.new("ap:source", &"trigger", "source", [ClassicActionDefinition.new(0, 76, 76, 0, false, [51, 1, 0, 0, 0])])
	if mode.begins_with("item"): caller = ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "900", [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0]), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
	var timer := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "901", _timer_actions(mode))
	var arrival := ScenarioProgramDefinition.new("ap:arrival", &"trigger", "arrival", _arrival_actions(mode))
	var later := ScenarioProgramDefinition.new("xap:902", &"extra-action-point", "902", [ClassicActionDefinition.new(0, 47, 47, 99, false, [])])
	var callee_actions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(0, 45, 45, 0, false, [0, 2, 1, 0, 0])]
	if mode == "gosub-wait": callee_actions.append(ClassicActionDefinition.new(1, 1, 1, 1, false, []))
	callee_actions.append(ClassicActionDefinition.new(2, 111, 111, 0, false, []))
	var callee := ScenarioProgramDefinition.new("xap:903", &"extra-action-point", "903", callee_actions)
	var timers: Array[TimedEncounterDefinition] = [TimedEncounterDefinition.new(0, 9 if mode == "no-due" else 8, 1, 100, 901, timer.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)]
	if mode == "ordinary": timers.append(TimedEncounterDefinition.new(1, 8, 1, 100, 902, later.id, 0, -1, -1, -1, 0, 50, TimedEncounterDefinition.LocationKind.ANY))
	if mode == "post-header":
		timers[0] = TimedEncounterDefinition.new(0, 8, 2, 100, 901, timer.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)
		later = ScenarioProgramDefinition.new("xap:902", &"extra-action-point", "902", [ClassicActionDefinition.new(0, 37, 37, 0, false, [1, 0, 2, 1, 0])])
		timers.append(TimedEncounterDefinition.new(1, 9, 2, 100, 902, later.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY))
	var triggers: Array[TriggerDefinition] = [TriggerDefinition.new("source", caller.id, "timer-map", Vector2i(1, 1), true, 100, TriggerDestinationDefinition.new("timer-map", Vector2i(3, 1)), 0)]
	if mode != "no-match": triggers.append(TriggerDefinition.new("arrival", arrival.id, "timer-map", Vector2i(2, 1), true, 0 if mode == "zero" else 1 if mode == "chance-failed" else 100, TriggerDestinationDefinition.new("timer-map", Vector2i(3, 1)), 1))
	var scenario := ScenarioDefinition.new([caller, timer, arrival, later, callee], [], ScenarioApplicationHooks.new(caller.id) if mode == "start-hook" else null)
	var items := _base.items.definitions()
	if mode.begins_with("item"):
		var item := ItemDefinition.new("timer.door", 980, "Timer door item")
		item.item_type = 23; item.special_5 = 900; item.initial_charges = 2
		var hero := _hero(_base, true)
		item.item_category_mask_low = _base.characters.race_by_id(hero.race_id).item_category_mask_low & _base.characters.caste_by_id(hero.caste_id).item_category_mask_low
		items.append(item)
	return RealmzContent.new("timer-fixture", "b".repeat(64), "Timer fixture", _base.rules_version, "timer-map", Vector2i(0, 1), _world(mode), scenario, [MessageDefinition.new(1, "Timer arrival")], triggers, [], _base.characters.race_definitions(), _base.characters.caste_definitions(), items, _base.magic.definitions(), [], [], [], [], [], [], timers)


func _timer_actions(mode: String) -> Array[ClassicActionDefinition]:
	if mode == "empty-return": return [ClassicActionDefinition.new(0, 47, 47, 95, false, []), ClassicActionDefinition.new(1, 111, 111, 0, false, []), ClassicActionDefinition.new(2, 76, 76, 0, false, [91, 1, 0, 0, 0])]
	if mode in ["gosub-live", "gosub-wait"]: return [ClassicActionDefinition.new(0, -64, 64, 0, true, [-1, -1, 0, 903, 903]), ClassicActionDefinition.new(1, 76, 76, 0, false, [91, 1, 0, 0, 0])]
	if mode == "post-header": return [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0])]
	if mode == "header": return [ClassicActionDefinition.new(0, 47, 47, 95, false, [])]
	if mode == "early-return": return [ClassicActionDefinition.new(0, 37, 37, 0, false, [1, 0, 2, 1, 0])]
	return [ClassicActionDefinition.new(0, 20, 20, 0, false, [0, 2, 1, 0, 0]), ClassicActionDefinition.new(1, 76, 76, 0, false, [96, 1, 0, 0, 0])]


func _arrival_actions(mode: String) -> Array[ClassicActionDefinition]:
	var actions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(0, 1, 1, 1, false, []) if mode in ["wait", "item-wait"] else ClassicActionDefinition.new(0, 76, 76, 0, false, [50, 1, 0, 0, 0])]
	actions.append(ClassicActionDefinition.new(1, 24 if mode == "keep" else 25, 24 if mode == "keep" else 25, 0, false, []) if mode in ["keep", "erase"] else ClassicActionDefinition.new(1, 76, 76, 0, false, [91, 1, 0, 0, 0]))
	return actions


func _world(mode: String) -> WorldDefinition:
	var cells: Array[MapCell] = []
	for y: int in 16:
		for x: int in 16:
			var id := "source" if Vector2i(x, y) == Vector2i(1, 1) and mode != "ordinary" else "arrival" if Vector2i(x, y) == Vector2i(2, 1) else ""
			var ids: Array[String] = []
			var features: Array[MapFeature] = []
			if not id.is_empty():
				ids.append(id)
				features.append(MapFeature.new(id + ":marker", &"action-point", &"active"))
			cells.append(MapCell.new("timer:%d,%d" % [x, y], Vector2i(x, y), "classic.terrain.1", true, 1, false, true, false, false, true, false, false, 0, 1, "fixture.tileset", ids, [], {}, features))
	return WorldDefinition.new([MapDefinition.new("timer-map", "Timer fixture", &"land", 0, MapTopology.new(16, 16, cells))])


func _hero(content: RealmzContent, needs_item: bool = false) -> CharacterState:
	var hero := CharacterState.new("timer.hero", "Timer", 30, 30)
	hero.race_id = content.characters.race_definitions()[0].id
	hero.caste_id = content.characters.caste_definitions()[0].id
	if needs_item:
		var selected := false
		for race: RaceDefinition in content.characters.race_definitions():
			for caste: CasteDefinition in content.characters.caste_definitions():
				if caste.caste_class in range(1, 8) and (race.item_category_mask_low & caste.item_category_mask_low) != 0:
					hero.race_id = race.id; hero.caste_id = caste.id
					selected = true
					break
			if selected: break
	hero.age_days = 4000
	hero.age_group = RealmzRules.new().characters.infer_age_group(hero.age_days, content.characters.race_by_id(hero.race_id))
	return hero


func _check(passed: bool, label: String) -> void:
	checks.append({"case": label, "passed": passed})
	if not passed: failures.append(label)
