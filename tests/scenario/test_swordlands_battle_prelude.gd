extends RealmzTestCase


func run() -> void:
	var loaded := load_test_package("res://src/storage/packages/bundled_campaigns/scenario-trouble-in-the-sword-lands.realmz2")
	assert_true(loaded.is_ok(), "Trouble in the Sword Lands package loads for the reported AP")
	if not loaded.is_ok():
		return
	var content: RealmzContent = loaded.content
	var program := content.scenario.program_by_id("trigger:Data DD:18:7")
	var action: ClassicActionDefinition = program.instruction_at(3) if program != null else null
	assert_true(action != null and action.opcode == 2 and action.extra_code == [180, 180, 2221, 10136, 0], "land 18 AP 7 retains its authored battle row")
	if action == null:
		return
	assert_true(content.scenario_records.message_by_id(10136) == null and not content.has_media_resource("snd ", 2221), "the prelude message and sound really are absent")
	var party := PartyState.new("land:18", Vector2i(73, 22), [CharacterState.new("swordlands.hero", "Hero", 30, 30)])
	var state := GameState.new(party, RealmzClock.new())
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var result := api.execute_classic(action, "swordlands.land18.ap7.battle")
	assert_equal(result.state, ScenarioRuntimeOperationResult.State.WAITING, "missing optional prelude does not prevent battle 180 from starting")
	assert_true(state.combat != null and state.combat.battle_id == "classic.battle.180" and result.interaction != null and result.interaction.kind == &"combat_action", "reported AP enters an actionable battle")
	assert_true(not result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"message_shown" and event.payload.get("source") == "classic-battle"), "missing message is not fabricated")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 2221), "the authored sound identity reaches the nonblocking media resolver")
	var vm_party_members: Array[CharacterState] = []
	for index: int in range(6):
		vm_party_members.append(CharacterState.new("swordlands.vm.%d" % index, "Hero %d" % index, 1000, 1000))
	var vm_state := GameState.new(PartyState.new("land:18", Vector2i(73, 22), vm_party_members), RealmzClock.new())
	var vm_api := RealmzRuntimeApi.new(content, vm_state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
	var vm := ScenarioVm.new()
	vm.configure(content.scenario)
	vm.start_program(program.id, ScenarioExecutionContext.trigger(&"action-point", "Data DD:18:7", "land:18", Vector2i(73, 22), true))
	var ap_result := vm.run(vm_api)
	for step: int in range(4):
		if ap_result.state != ScenarioVmResult.State.WAITING or ap_result.interaction.kind != InteractionRequest.ACKNOWLEDGE:
			break
		ap_result = vm.resume(InteractionResponse.acknowledge(ap_result.interaction), vm_api)
	assert_true(ap_result.state == ScenarioVmResult.State.WAITING and ap_result.interaction != null and ap_result.interaction.kind == &"combat_action" and vm_state.combat != null and vm_state.combat.battle_id == "classic.battle.180", "the compiled AP itself reaches battle 180 after its authored narration (state %d, interaction %s, error %s)" % [ap_result.state, ap_result.interaction.kind if ap_result.interaction != null else "none", ap_result.error_message])
