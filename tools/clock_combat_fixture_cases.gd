## Disposable, explicit VM fixtures for clock, fumble and combat transfer evidence.
extends RefCounted

var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var _base: RealmzContent
var _root: String


func run(base: RealmzContent, scratch: String, native_returns: Array) -> Dictionary:
	_base = base
	_root = scratch
	if not scratch.is_absolute_path() or DirAccess.dir_exists_absolute(scratch):
		return {"failures": ["Fixture scratch directory must be fresh and absolute."]}
	DirAccess.make_dir_recursive_absolute(scratch)
	_fumbles()
	_nested_timers()
	_nested_wire_bounds()
	_transfers()
	_clock_returns(native_returns)
	_clock_party_death()
	_macro_dispatch()
	_reservation_guards()
	var timers: Dictionary = preload("res://tools/clock_timer_fixture_cases.gd").new().run(_base, _root.path_join("timer-contracts"))
	failures.append_array(timers["failures"])
	if evidence.size() != 95:
		failures.append("Fixture coverage is incomplete: expected 95 completed checks, received %d." % evidence.size())
	return {"mode": "direct-public-vm-and-save-repository", "checks": evidence, "timers": timers, "failures": failures}


func _content(programs: Array[ScenarioProgramDefinition], timers: Array[TimedEncounterDefinition] = []) -> RealmzContent:
	return RealmzContent.new("clock-combat-fixture", "a".repeat(64), "clock-combat-fixture", _base.rules_version, _base.start_map_id, _base.start_coordinate, _base.world, ScenarioDefinition.new(programs, []), [MessageDefinition.new(1, "The weapon slips from your grasp.")], [], [], _base.characters.race_definitions(), _base.characters.caste_definitions(), _base.items.definitions(), _base.magic.definitions(), [], [BattleDefinition.new("fixture.battle", 1, [])], [], [], [], [], timers)


func _hero(content: RealmzContent) -> CharacterState:
	var hero := CharacterState.new("fixture.hero", "Fixture", 30, 30)
	hero.race_id = content.characters.race_definitions()[0].id
	hero.caste_id = content.characters.caste_definitions()[0].id
	hero.maximum_load = 100
	hero.maximum_movement = 12
	hero.movement = 12
	hero.normal_attacks = 4
	hero.age_days = 4000
	hero.age_group = RealmzRules.new().characters.infer_age_group(hero.age_days, content.characters.race_by_id(hero.race_id))
	return hero


func _battle(content: RealmzContent, hero: CharacterState) -> GameState:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldGrid.CELL_COUNT)
	tiles.fill(0)
	var field := BattlefieldState.new(content.start_map_id, tiles)
	field.actors.place_character(hero.id, Vector2i(45, 45))
	var monster := MonsterState.new("fixture.monster", "fixture.monster-definition", "Fixture", 30, 30, 1)
	field.actors.place_monster(monster.id, Vector2i(46, 45), 0)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
	state.combat = CombatState.new("fixture.battle", [monster], 0, field)
	state.combat.set_turn_order([hero.id, monster.id])
	return state


func _fumbles() -> void:
	for name: String in ["armed", "unarmed", "spell-active", "nonphysical", "queue-full", "cursed", "cursed-full-queue", "monster-active", "outside-combat", "authored-message"]:
		var program := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "extra-action-point:900", [ClassicActionDefinition.new(0, 122, 122, 0, false, [1 if name == "authored-message" else 0, -6000 if name == "authored-message" else 0, 0, 0, 0]), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
		var content := _content([program])
		var hero := _hero(content)
		var state := _battle(content, hero)
		var rules := RealmzRules.new()
		var weapon := ItemDefinition.new("fixture.weapon", 92, "Fixture weapon")
		weapon.item_type = 2
		weapon.vs_small = 1
		weapon.initial_charges = 7
		content.items = ItemCatalog.new([weapon])
		var instance := rules.inventory.add_item(hero, weapon, "fixture.exact-weapon", false)
		instance.charges = 7
		rules.equipment.equip(hero, instance.id, weapon)
		if name in ["cursed", "cursed-full-queue"]: weapon.cursed_item_id = "fixture.curse"
		if name == "unarmed": hero.set_inventory([])
		if name == "monster-active": state.combat.set_turn_order(["fixture.monster", hero.id])
		state.combat.turns.active_turn = CombatTurnState.new(state.combat.turns.active_actor_id())
		state.combat.turns.active_turn.classic_physical_active = name != "nonphysical"
		state.combat.turns.active_turn.classic_spell_active = name == "spell-active"
		if name in ["queue-full", "cursed-full-queue"]:
			for index: int in 20: state.combat.dropped_items.queue(ItemInstance.new("fixture.drop.%d" % index, weapon.id, 1, true))
		if name == "outside-combat": state.combat = null
		var rng := RealmzRng.new(1)
		var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
		var vm := ScenarioVm.new()
		vm.configure(content.scenario)
		vm.start_program(program.id)
		var result := vm.run(api)
		if name == "authored-message":
			_check(result.state == ScenarioVmResult.State.WAITING and hero.inventory().size() == 1 and state.combat.dropped_items.items().is_empty(), name + " pauses before removal")
			var restored := _write_read(content, state, rng, vm, name)
			if restored == null: continue
			state = restored.game_state
			hero = state.party.characters()[0]
			api = RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
			vm.restore(restored.scenario_vm)
			result = vm.resume(InteractionResponse.acknowledge(vm.pending_request()), api)
		var drops: Array[ItemInstance] = []
		if state.combat != null: drops.assign(state.combat.dropped_items.items())
		var changed := name in ["armed", "authored-message"]
		var should_return := name in ["unarmed", "cursed"]
		_check(result.state == ScenarioVmResult.State.COMPLETED and state.scenario_progress.quest_value(90) == (0 if should_return else 1) and (not changed or hero.inventory().is_empty() and drops.size() == 1 and drops[0].id == instance.id and drops[0].charges == 7) and (changed or name == "unarmed" or hero.inventory().size() == 1) and rng.snapshot().draw_count == 0, "scripted fumble " + name)


func _nested_timers() -> void:
	var caller := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "extra-action-point:900", [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0]), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
	var first := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "extra-action-point:901", [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0])])
	var second := ScenarioProgramDefinition.new("xap:902", &"extra-action-point", "extra-action-point:902", [ClassicActionDefinition.new(0, 1, 1, 1, false, []), ClassicActionDefinition.new(1, 76, 76, 0, false, [91, 1, 0, 0, 0])])
	var content := _content([caller, first, second], [TimedEncounterDefinition.new(0, 8, 2, 100, 901, first.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY), TimedEncounterDefinition.new(1, 9, 2, 100, 902, second.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)])
	var hero := _hero(content)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
	state.clock.set_components(7, 23, 0)
	var rng := RealmzRng.new(1)
	var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	vm.start_program(caller.id)
	var result := vm.run(api)
	_check(result.state == ScenarioVmResult.State.WAITING and state.clock.day() == 9 and hero.age_days == 4002 and rng.snapshot().draw_count == 2, "nested timers suspend after exactly two midnight scans")
	if result.state != ScenarioVmResult.State.WAITING: return
	var restored := _write_read(content, state, rng, vm, "nested-timers", api.classic_execution())
	if restored == null: return
	state = restored.game_state
	api = RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new(), null, restored.classic_execution)
	vm.restore(restored.scenario_vm)
	result = vm.resume(InteractionResponse.acknowledge(vm.pending_request()), api)
	_check(result.state == ScenarioVmResult.State.COMPLETED and state.clock.day() == 9 and state.scenario_progress.quest_value(90) == 0 and state.scenario_progress.quest_value(91) == 3 and rng.snapshot().draw_count == 2 and state.scenario_progress.encounters.timed_override(0).get("day") == 10 and state.scenario_progress.encounters.timed_override(1).get("day") == 11, "nested timer return uses the last loaded record without duplicate scans, aging or RNG")


func _nested_wire_bounds() -> void:
	for mixed: bool in [false, true]:
		var wire := ScenarioVmSnapshot.new().to_data()
		wire["halted"] = false
		wire["frames"] = [ScenarioFrame.new(ScenarioFrame.PROGRAM, "xap:900").to_data()]
		wire["pendingRequest"] = InteractionRequest.acknowledge("nested-wire", "Continue").to_data()
		wire["pendingContinuation"] = {"kind": String(ScenarioVmPendingContinuation.CLASSIC_OPERATION), "version": 1, "data": {"runtime": ScenarioInteractionContinuations.acknowledge().to_data()}}
		for index: int in 33:
			var runtime: Dictionary
			if mixed and index % 2 == 1:
				runtime = {"kind": String(ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO), "version": 1, "data": {"sourceKind": String(ScenarioRuntimeContinuation.CLASSIC_COMBAT), "battleId": "fixture.battle", "battleCaller": ScenarioBattleCaller.classic(2, false, 0, 0).to_data(), "programId": "xap:900", "macroVm": wire}}
			else:
				var body := ScenarioClockContinuationBody.new().wire_payload()
				body["timerVm"] = wire
				body["scanPending"] = true
				body["programId"] = "xap:900"
				body["timerIndex"] = 1
				runtime = {"kind": String(ScenarioRuntimeContinuation.CLASSIC_CLOCK), "version": 1, "data": body}
			var parent := ScenarioVmSnapshot.new().to_data()
			parent["halted"] = false
			parent["frames"] = wire["frames"].duplicate(true)
			parent["pendingRequest"] = InteractionRequest.acknowledge("nested-wire", "Continue").to_data()
			parent["pendingContinuation"] = {"kind": String(ScenarioVmPendingContinuation.CLASSIC_OPERATION), "version": 1, "data": {"runtime": runtime}}
			wire = parent
			if index >= 31:
				var decoded := ScenarioVmSnapshot.from_data(wire)
				_check((decoded != null) == (index == 31), "nested %s wire depth %d is %s before recursive restore" % ["mixed-macro/clock" if mixed else "clock", index + 1, "accepted" if index == 31 else "rejected"])


func _transfers() -> void:
	for opcode: int in [20, 37, 45]:
		var map := _base.world.map_by_id(_base.start_map_id)
		var destination := _base.start_coordinate
		var words: Array[int] = []
		words.assign([1 if map.level_type == &"land" else 0, map.level_index, destination.x, destination.y, 1] if opcode == 37 else [map.level_index, destination.x, destination.y, 0, 0])
		var program := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "extra-action-point:900", [ClassicActionDefinition.new(0, opcode, opcode, 0, false, words), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
		var content := _content([program])
		var hero := _hero(content)
		var state := _battle(content, hero)
		var before := CanonicalJson.encode(state.combat.to_data())
		var rng := RealmzRng.new(1)
		var vm := ScenarioVm.new()
		vm.configure(content.scenario)
		vm.start_program(program.id)
		var result := vm.run(RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new()))
		_check(result.state == ScenarioVmResult.State.COMPLETED and state.scenario_progress.quest_value(90) == (0 if opcode == 37 else 1) and before == CanonicalJson.encode(state.combat.to_data()) and rng.snapshot().draw_count == 0, "combat transfer %d retains coherent actors, terrain, turn and native return" % opcode)
		_write_read(content, state, rng, vm, "transfer-%d" % opcode)


func _clock_returns(rows: Array) -> void:
	if rows.size() != 8:
		_check(false, "Native return matrix contains all eight cases")
		return
	for row: Dictionary in rows:
		var clock_actions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(row.clockSlot, 63, 63, 0, false, [2, 0, 0, 60, 0]), ClassicActionDefinition.new(row.clockSlot + 1, 76, 76, 0, false, [90, 1, 0, 0, 0]), ClassicActionDefinition.new(7, 24, 24, 0, false, [])]
		var timer_actions: Array[ClassicActionDefinition] = []
		for slot: int in [0, 1, 3]: timer_actions.append(ClassicActionDefinition.new(slot, 76, 76, 0, false, [91 + slot, 1, 0, 0, 0]))
		timer_actions.append(ClassicActionDefinition.new(7, 24, 24, 0, false, []))
		var timer := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "extra-action-point:901", timer_actions)
		var clock := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "extra-action-point:900", clock_actions)
		var root := ScenarioProgramDefinition.new("xap:904", &"extra-action-point", "extra-action-point:904", [ClassicActionDefinition.new(0, -39, 39, 900, true, []), ClassicActionDefinition.new(1, 47, 47, 95, false, [])])
		var branch := ScenarioProgramDefinition.new("xap:903", &"extra-action-point", "extra-action-point:903", [ClassicActionDefinition.new(0, 39, 39, 901, false, [])])
		var timer_id := branch.id if row.branch else timer.id
		var content := _content([root, clock, timer, branch], [TimedEncounterDefinition.new(0, 8, 1, 100, 903 if row.branch else 901, timer_id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)])
		var hero := _hero(content)
		var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
		state.clock.set_components(7, 23, 0)
		var vm := ScenarioVm.new()
		vm.configure(content.scenario)
		vm.start_program(root.id if row.nestedGosub else clock.id)
		var result := vm.run(RealmzRuntimeApi.new(content, state, RealmzRng.new(1), ScenarioActionState.new()))
		var actual := {"rootFollowing": state.scenario_progress.quest_value(95), "originalFollowing": state.scenario_progress.quest_value(90), "timer0": state.scenario_progress.quest_value(91), "timer1": state.scenario_progress.quest_value(92), "timer3": state.scenario_progress.quest_value(94)}
		var matches := result.state == ScenarioVmResult.State.COMPLETED
		for key: String in actual: matches = matches and actual[key] == int(row[key])
		_check(matches, "native clock return slot %d branch %s GOSUB %s: %s" % [row.clockSlot, row.branch, row.nestedGosub, actual])


func _write_read(content: RealmzContent, state: GameState, rng: RealmzRng, vm: ScenarioVm, name: String, native_execution: ClassicExecutionState = null) -> SaveEnvelope:
	var snapshot := SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, rng.snapshot(), vm.snapshot(), ScenarioActionState.new(), null, null, null, native_execution)
	var repository := SaveRepository.new(_root.path_join(name))
	if not repository.save(content.campaign_id, "A", snapshot):
		_check(false, name + " save: " + repository.last_error)
		return null
	var path := _root.path_join(name).path_join(content.campaign_id).path_join("A.r2save")
	var restored := SaveEnvelope.from_data(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_check(restored != null and CanonicalJson.encode(restored.game_state.to_data()) == CanonicalJson.encode(state.to_data()) and CanonicalJson.encode(restored.scenario_vm.to_data()) == CanonicalJson.encode(vm.snapshot().to_data()) and restored.classic_execution.to_data() == snapshot.classic_execution.to_data(), name + " v6 verified write and exact readback")
	return restored


func _clock_party_death() -> void:
	var caller := ScenarioProgramDefinition.new("ap:clock-death", &"trigger", "clock-death", [ClassicActionDefinition.new(0, 63, 63, 0, false, [1, -1, 24, -1, 0]), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
	var timer := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "extra-action-point:901", [ClassicActionDefinition.new(0, 16, 16, 0, false, [-40, 1, 1, 0, 0]), ClassicActionDefinition.new(1, 76, 76, 0, false, [91, 1, 0, 0, 0])])
	var death := ScenarioProgramDefinition.new("hook:death", &"application-hook", "party-death", [ClassicActionDefinition.new(0, 1, 1, 1, false, []), ClassicActionDefinition.new(1, 119, 119, 0, false, [])])
	var content := _content([caller, timer, death], [TimedEncounterDefinition.new(0, 8, 1, 100, 901, timer.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY)])
	content.scenario = ScenarioDefinition.new([caller, timer, death], [], ScenarioApplicationHooks.new("", death.id))
	var cells: Array[MapCell] = []
	for y: int in 3:
		for x: int in 3:
			var coordinate := Vector2i(x, y)
			var is_ap := coordinate == Vector2i(2, 1)
			var trigger_ids: Array[String] = []
			var features: Array[MapFeature] = []
			if is_ap:
				trigger_ids.append("clock-death")
				features.append(MapFeature.new("clock:ap", &"action-point", &"active"))
			cells.append(MapCell.new("clock:cell:%d,%d" % [x, y], coordinate, "classic.terrain.1", true, 1, false, true, false, false, true, false, false, 0, 1, "fixture.tileset", trigger_ids, [], {}, features))
	content.start_map_id = "clock-map"
	content.start_coordinate = Vector2i(1, 1)
	content.world = WorldDefinition.new([MapDefinition.new(content.start_map_id, "Clock fixture", &"land", 0, MapTopology.new(3, 3, cells))])
	var trigger := TriggerDefinition.new("clock-death", caller.id, content.start_map_id, Vector2i(2, 1), true, 100)
	content.scenario_records = ScenarioContentCatalog.new(content.campaign, [MessageDefinition.new(1, "The timer interrupts at Party Death.")], [trigger], [], [], [], content.scenario_records.timed_encounters())
	var hero := _hero(content)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
	state.party_setup_completed = true
	state.clock.set_components(7, 23, 0)
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	var session := GameSession.new()
	var prepared := session.restore(content, SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, RealmzRng.new(1).snapshot(), vm.snapshot(), ScenarioActionState.new()))
	_check(prepared.state == SessionStep.State.COMPLETED, "clock Party Death session preparation validates")
	if prepared.state != SessionStep.State.COMPLETED: return
	var waiting := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	_check(waiting.state == SessionStep.State.WAITING_FOR_INTERACTION and waiting.interaction.kind == InteractionRequest.ACKNOWLEDGE and session.snapshot() != null and session.snapshot().game_state.clock.day() == 8, "clock timer hands off to the real Party Death hook at its committed scan cursor")
	if waiting.state != SessionStep.State.WAITING_FOR_INTERACTION: return
	var resumed := _session_readback(content, session.snapshot(), "clock-death-pending")
	if resumed == null: return
	var result := resumed.respond(InteractionResponse.acknowledge(resumed.snapshot().pending_interaction()))
	var saved := resumed.snapshot()
	_check(result.state == SessionStep.State.COMPLETED and saved != null and saved.game_state.party.characters()[0].current_health == 1 and saved.game_state.clock.day() == 8 and saved.game_state.scenario_progress.quest_value(90) == 0 and saved.game_state.scenario_progress.quest_value(91) == 2 and saved.rng_state.draw_count == 3, "FD-SCENARIO-026 revival retains the typed timer continuation without duplicate damage, time, aging or RNG")
	if saved != null: _session_readback(content, saved, "clock-death-completed")


func _session_readback(content: RealmzContent, snapshot: SessionSnapshot, name: String) -> GameSession:
	var repository := SaveRepository.new(_root.path_join(name))
	var saved := repository.save(content.campaign_id, "A", snapshot)
	var loaded := repository.load(content.campaign_id, "A", content.package_hash) if saved else null
	var session := GameSession.new()
	var result := session.restore(content, loaded) if loaded != null else null
	_check(result != null and result.state == SessionStep.State.COMPLETED, name + " actual v9 write/readback and detached session restore" + (": " + result.error_message if result != null else ""))
	return session if result != null and result.state == SessionStep.State.COMPLETED else null


func _macro_dispatch() -> void:
	var aura: SpellDefinition
	for definition: SpellDefinition in _base.magic.definitions():
		if definition.name == "Magic Aura": aura = definition
	if aura == null:
		_check(false, "Macro fixtures have the application Magic Aura definition")
		return
	for target_type: int in [1, 6]:
		for mode: String in ["live", "resisted", "dead-cell", "queued-live", "queued-fumble", "queued-scroll", "queued-item"]:
			var spell := aura.with_scenario_adjustments(0, false)
			spell.target_type = target_type
			spell.cannot = 0 if mode == "resisted" else 4
			var nested_actions: Array[ClassicActionDefinition] = [ClassicActionDefinition.new(0, 1, 1, 1, false, [])]
			if mode in ["queued-fumble", "queued-scroll", "queued-item"]: nested_actions.append(ClassicActionDefinition.new(1, 122, 122, 0, false, [0, 0, 0, 0, 0]))
			nested_actions.append(ClassicActionDefinition.new(2, 17, 17, 0, false, [spell.classic_id, 1, 0, 0 if mode == "resisted" else 1, 0]))
			if mode in ["queued-fumble", "queued-scroll", "queued-item"]: nested_actions.append(ClassicActionDefinition.new(3, 122, 122, 0, false, [0, 0, 0, 0, 0]))
			var nested := ScenarioProgramDefinition.new("xap:902", &"extra-action-point", "extra-action-point:902", nested_actions)
			var actions: Array[ClassicActionDefinition] = []
			if mode != "dead-cell": actions.append(ClassicActionDefinition.new(0, 119, 119, 0, false, []))
			actions.append(ClassicActionDefinition.new(1, -39, 39, 902, true, []))
			var macro := ScenarioProgramDefinition.new("xap:901", &"extra-action-point", "extra-action-point:901", actions)
			var content := _content([macro, nested])
			var lethal := SpellDefinition.new("fixture.lethal", 1306, "Lethal fixture spell")
			lethal.in_combat = true
			lethal.target_type = 0
			lethal.spell_class = 1
			lethal.damage_type = 1
			lethal.cannot = 3
			lethal.cost = 2
			lethal.range_min = 15
			lethal.damage_min = 500
			lethal.damage_max = 500
			content.magic = SpellCatalog.new([spell, lethal])
			var definition := MonsterDefinition.new("fixture.monster-definition", 1, "Macro source", 1, 0, 10, 0, 0, [], [], [], [], [], [], [])
			definition.death_macro = 901
			content.combat = CombatCatalog.new([definition], [BattleDefinition.new("fixture.battle", 1, [])])
			var hero := _hero(content)
			hero.to_hit = 200
			hero.damage_bonus = 200
			hero.set_known_spells([lethal.id])
			hero.spell_points = 100
			hero.maximum_spell_points = 100
			hero.maximum_spell_attacks = 2
			hero.maximum_movement = 30
			hero.movement = 30
			if mode in ["queued-fumble", "queued-scroll", "queued-item"]: _arm_macro_caster(content, hero, lethal)
			var state := _battle(content, hero)
			state.party_setup_completed = true
			var source := state.combat.roster.monsters()[0]
			source.magic_resistance = 100 if mode == "resisted" else 0
			var vm := ScenarioVm.new()
			vm.configure(content.scenario)
			var session := GameSession.new()
			var prepared := session.restore(content, SessionSnapshot.new(content.campaign_id, content.package_hash, content.rules_version, 1, state, RealmzRng.new(17).snapshot(), vm.snapshot(), ScenarioActionState.new()))
			if prepared.state != SessionStep.State.COMPLETED:
				_check(false, "Macro session preparation: " + prepared.error_message)
				continue
			var label := "macro type %d %s" % [target_type, mode]
			var waiting: SessionStep
			if mode.begins_with("queued-"):
				waiting = _attack_then_cast(content, session, hero.id, source.id, lethal.id, mode)
			else:
				waiting = session.submit_intent(CombatIntents.choose_action(&"attack", hero.id, source.id))
			_check(waiting.state == SessionStep.State.WAITING_FOR_INTERACTION and waiting.interaction.kind == InteractionRequest.ACKNOWLEDGE and session.snapshot() != null, label + " enters a nested death-macro acknowledgement from an ordinary attack: " + waiting.error_message)
			if waiting.state != SessionStep.State.WAITING_FOR_INTERACTION: continue
			var restored := _session_readback(content, session.snapshot(), label.replace(" ", "-"))
			if restored == null: continue
			var result := restored.respond(InteractionResponse.acknowledge(restored.snapshot().pending_interaction()))
			var resolutions := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
			var matches := result.state != SessionStep.State.FAILED and resolutions.size() == (0 if mode == "dead-cell" else 1)
			if mode != "dead-cell" and not resolutions.is_empty():
				matches = matches and resolutions[0].payload.get("targetId") == source.id and resolutions[0].payload.get("resisted") == (mode == "resisted") and resolutions[0].payload.get("areaShape") == 1
			_check(matches, label + " preserves source-cell targeting, resistance and dead-cell no-effect without projecting a ray: " + result.error_message + " resolutions=" + str(resolutions.size()))
			if mode in ["queued-fumble", "queued-scroll", "queued-item"]:
				var saved := restored.snapshot()
				_check(saved != null and saved.game_state.party.character_by_id(hero.id).inventory().any(func(item: ItemInstance) -> bool: return item.id == "fixture.cast-weapon" and item.equipped) and not result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_fumbled") and result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_fumble_skipped" and event.payload.get("reason") == "spell-in-progress"), label + " queued opcode 122 retains the spell guard through saved nested acknowledgement after an earlier physical attack")


func _arm_macro_caster(content: RealmzContent, hero: CharacterState, lethal: SpellDefinition) -> void:
	_select_item_user(content, hero)
	var weapon := ItemDefinition.new("fixture.cast-weapon", 92, "Fixture weapon")
	weapon.item_type = 2
	weapon.vs_small = 1
	var wand := ItemDefinition.new("fixture.cast-wand", 800, "Fixture wand")
	wand.item_type = 21
	wand.item_category_mask_low = content.characters.race_by_id(hero.race_id).item_category_mask_low & content.characters.caste_by_id(hero.caste_id).item_category_mask_low
	wand.item_category_mask_high = content.characters.race_by_id(hero.race_id).item_category_mask_high & content.characters.caste_by_id(hero.caste_id).item_category_mask_high
	wand.special_1 = 1
	wand.special_2 = lethal.classic_id
	wand.initial_charges = 3
	var scroll_case := ItemDefinition.new("fixture.scroll-case", 801, "Fixture scroll case")
	scroll_case.item_type = 13
	var items := content.items.definitions()
	items.append_array([weapon, wand, scroll_case])
	content.items = ItemCatalog.new(items)
	var rules := RealmzRules.new()
	var instance := rules.inventory.add_item(hero, weapon, "fixture.cast-weapon", false)
	rules.equipment.equip(hero, instance.id, weapon)
	rules.inventory.add_item(hero, wand, "fixture.cast-wand", false)
	var case_instance := rules.inventory.add_item(hero, scroll_case, "fixture.scroll-case", false)
	rules.equipment.equip(hero, case_instance.id, scroll_case)
	hero.write_scroll(0, lethal.id, 1)
	hero.luck = 100


func _select_item_user(content: RealmzContent, hero: CharacterState) -> void:
	for race: RaceDefinition in content.characters.race_definitions():
		for caste: CasteDefinition in content.characters.caste_definitions():
			if caste.caste_class < 1 or caste.caste_class > 7: continue
			if (race.item_category_mask_low & caste.item_category_mask_low) == 0 and (race.item_category_mask_high & caste.item_category_mask_high) == 0: continue
			hero.race_id = race.id
			hero.caste_id = caste.id
			hero.age_group = RealmzRules.new().characters.infer_age_group(hero.age_days, race)
			return
	failures.append("The pinned application has no usable race/class item-category intersection.")


func _attack_then_cast(content: RealmzContent, session: GameSession, actor_id: String, target_id: String, spell_id: String, mode: String) -> SessionStep:
	var before := session.snapshot()
	before.game_state.party.character_by_id(actor_id).damage_bonus = 0
	session.restore(content, before)
	session.submit_intent(CombatIntents.choose_action(&"attack", actor_id, target_id))
	if mode == "queued-scroll": return session.submit_intent(MagicIntents.use_scroll_on_target(actor_id, 0, "", [target_id]))
	if mode == "queued-item": return session.submit_intent(InventoryIntents.use_on_target("fixture.cast-wand", actor_id, "", [target_id]))
	return session.submit_intent(MagicIntents.cast_at_targets(spell_id, actor_id, [target_id]))


func _reservation_guards() -> void:
	for source: StringName in [&"cast_spell", &"use_scroll", &"use_item"]:
		var content := _content([])
		var hero := _hero(content)
		hero.spell_points = 20
		hero.maximum_spell_points = 20
		var weapon := ItemDefinition.new("fixture.weapon", 92, "Charged weapon")
		weapon.item_type = 2
		weapon.vs_small = 1
		weapon.initial_charges = 7
		var wand := ItemDefinition.new("fixture.wand", 800, "Fixture wand")
		wand.item_type = 21
		wand.initial_charges = 3
		var spell := SpellDefinition.new("fixture.spell", 1306, "Fixture spell")
		spell.cost = 2
		content.items = ItemCatalog.new([weapon, wand])
		content.magic = SpellCatalog.new([spell])
		var rules := RealmzRules.new()
		var exact_weapon := rules.inventory.add_item(hero, weapon, "weapon.instance", false)
		rules.equipment.equip(hero, exact_weapon.id, weapon)
		var item := rules.inventory.add_item(hero, wand, "wand.instance", false)
		hero.write_scroll(0, spell.id, 1)
		var state := _battle(content, hero)
		state.combat.turns.begin_active_turn().classic_physical_active = true
		var selection := CombatCastSelection.new()
		selection.actor_id = hero.id
		selection.action = source
		selection.spell_id = spell.id
		selection.power = 1
		selection.scroll_slot = 0 if source == &"use_scroll" else -1
		selection.item_instance_id = item.id if source == &"use_item" else ""
		var reserved := CombatCastResources.reserve(state, content, selection)
		var rng := RealmzRng.new(1)
		var api := RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
		var skipped := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [0, 0, 0, 0, 0]), "reserved-fumble")
		_check(reserved and skipped.state == ScenarioRuntimeOperationResult.State.COMPLETED and state.combat.dropped_items.items().is_empty() and state.combat.turns.active_turn.classic_spell_active, String(source) + " payment owner retains the spell guard after an earlier physical action")
		var vm := ScenarioVm.new()
		vm.configure(content.scenario)
		var loaded := _write_read(content, state, rng, vm, "reservation-" + String(source))
		if loaded == null: continue
		state = loaded.game_state
		CombatCastResources.abort(state)
		api = RealmzRuntimeApi.new(content, state, rng, ScenarioActionState.new())
		var dropped := api.execute_classic(ClassicActionDefinition.new(0, 122, 122, 0, false, [0, 0, 0, 0, 0]), "after-abort-fumble")
		_check(dropped.state == ScenarioRuntimeOperationResult.State.COMPLETED and not state.combat.turns.active_turn.classic_spell_active and state.combat.dropped_items.items().size() == 1 and state.combat.dropped_items.items()[0].id == exact_weapon.id and state.combat.dropped_items.items()[0].charges == 7 and rng.snapshot().draw_count == 0, String(source) + " abort clears only the spell guard; subsequent scripted fumble retains exact weapon and consumes no natural-fumble RNG")


func _check(condition: bool, label: String) -> void:
	evidence.append({"case": label, "passed": condition})
	if not condition: failures.append(label)
