extends RealmzTestCase


func run() -> void:
	assert_equal(ClassicOpcodeCatalog.normalize(-32768), -32768, "native signed-short minimum agrees with Providence's preserved normalization")
	var document := {
		"applicationHooks": {"startGame": null, "partyDeath": null, "endAdventure": null, "shop": null, "temple": null},
		"programs": [
			{"id": "xap:1", "ownerKind": "extra-action-point", "ownerId": "1", "instructions": []},
			{"id": "xap:2", "ownerKind": "extra-action-point", "ownerId": "2", "instructions": [
				{"kind": "classicAction", "slot": 3, "rawOpcode": -2823, "opcode": 2823, "id": -4, "gosub": true, "extraCode": [1, -2, 3, 4, 5]},
				{"kind": "classicAction", "slot": 4, "rawOpcode": 111, "opcode": 111, "id": 0, "gosub": false, "extraCode": null},
			]},
		],
		"scenarioActions": [], "stateDefinitions": [], "migrations": [],
	}
	var strict := PackageScenarioDecoder.new()
	assert_equal(strict.decode_scenario(document, "fixture"), null, "fresh packages retain strict opcode validation")
	var imported := PackageScenarioDecoder.new().decode_scenario(document, "fixture", true)
	assert_not_null(imported, "deferred imported instructions survive typed decoding")
	if imported == null:
		return
	var action: ClassicActionDefinition = imported.program_by_id("xap:2").instruction_at(0)
	assert_equal([action.raw_opcode, action.opcode, action.operand_id, action.slot, action.gosub, action.extra_code], [-2823, 2823, -4, 3, true, [1, -2, 3, 4, 5]], "native opcode, sign, slot and operands remain exact")
	var vm := ScenarioVm.new()
	var loaded := load_test_package("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2")
	if not loaded.is_ok():
		return
	var state := GameState.new(PartyState.new(loaded.content.start_map_id, loaded.content.start_coordinate, []), RealmzClock.new())
	var api := RealmzRuntimeApi.new(loaded.content, state, RealmzRng.for_oracle(1), ScenarioActionState.new())
	vm.configure(imported)
	vm.start_program("xap:1")
	assert_equal(vm.run(api).state, ScenarioVmResult.State.COMPLETED, "an unrelated program remains executable")
	vm.start_program("xap:2")
	assert_equal(vm.run(api).state, ScenarioVmResult.State.COMPLETED, "Castle newland.c unmatched opcode falls through to the following slot")
	var skipped: Dictionary = {}
	var continued := false
	for entry: Dictionary in vm.trace():
		if entry.get("event") == "classic-unrecognized-skipped":
			skipped = entry
		continued = continued or entry.get("event") == "classic-return"
	assert_equal([skipped.get("programId"), skipped.get("slot"), skipped.get("rawOpcode"), skipped.get("opcode"), skipped.get("id"), skipped.get("extraCode")], ["xap:2", 3, -2823, 2823, -4, [1, -2, 3, 4, 5]], "skip trace retains exact native instruction for repair")
	assert_true(continued, "the following Classic instruction executes")
	vm.configure(ScenarioDefinition.new([imported.program_by_id("xap:2")], []))
	vm.start_program("xap:2")
	var failed := vm.run(api)
	assert_equal(failed.error_code, &"unsupported_classic_opcode", "fresh typed definitions do not gain imported fallthrough")
	var context := vm.diagnostics.failure_context()
	assert_equal([context.get("programId"), context.get("slot"), context.get("rawOpcode"), context.get("opcode"), context.get("operands")], ["xap:2", 3, -2823, 2823, [-4, 1, -2, 3, 4, 5]], "failure diagnostics retain exact native instruction for repair")
	_test_extra_code_tail_guard(document, api, state)
	var encounter := loaded.content.scenario_records.simple_encounter_by_id(0)
	var eliminated := encounter.response_at(0)
	var original_target := eliminated.result_program_id
	eliminated.result_program_id = "simple:0:result:-1"
	var choice := api.request_classic_encounter(&"simple", 0, "eliminated-native-choice", ScenarioExecutionContext.empty())
	assert_equal(choice.error_code, &"encounter_has_no_options", "a native-zero result eliminates the fixture's sole choice")
	eliminated.result_program_id = original_target
	assert_equal(api.request_classic_encounter(&"simple", 0, "restored-native-choice", ScenarioExecutionContext.empty()).state, ScenarioRuntimeOperationResult.State.WAITING, "a valid result leaves the choice usable")


func _test_extra_code_tail_guard(document: Dictionary, api: RealmzRuntimeApi, state: GameState) -> void:
	var guarded := document.duplicate(true)
	guarded["schemaVersion"] = 5
	guarded["extraCodeTail"] = {"rowId": 2463, "availableBytes": 6}
	var instruction: Dictionary = guarded["programs"][1]["instructions"][0]
	instruction.merge({"rawOpcode": 12, "opcode": 12, "id": 2463, "gosub": false, "extraCode": null}, true)
	var imported := PackageScenarioDecoder.new().decode_scenario(guarded, "fixture", true)
	assert_not_null(imported, "a partial source tail installs as an explicit fault")
	if imported == null: return
	var vm := ScenarioVm.new()
	vm.configure(imported)
	vm.start_program("xap:1")
	assert_equal(vm.run(api).state, ScenarioVmResult.State.COMPLETED, "unrequested incomplete row does not block another program")
	var revision := state.world.topology.revision()
	vm.start_program("xap:2")
	var failed := vm.run(api)
	assert_equal(failed.error_code, &"malformed_classic_extra_code", "selected malformed row reaches the prepared guard")
	assert_true(failed.error_message.contains("row 2463") and failed.error_message.contains("6 of 10"), "error identifies row and byte counts")
	assert_equal(state.world.topology.revision(), revision, "guard runs before tile mutation")
	var fault := vm.diagnostics.failure_context()
	assert_equal([fault.get("nativePath"), fault.get("extraCodeRow"), fault.get("availableBytes"), fault.get("requiredBytes"), fault.get("programId"), fault.get("slot")], ["Data EDCD", 2463, 6, 10, "xap:2", 3], "failure log retains exact repair context")
	assert_false(vm.trace().any(func(entry: Dictionary) -> bool: return entry.get("event") == "classic-return"), "guard stops the following instruction")
	instruction.merge({"rawOpcode": 92, "opcode": 92, "id": 2462, "extraCode": [0, 0, 0, 0, 0]}, true)
	imported = PackageScenarioDecoder.new().decode_scenario(guarded, "fixture", true)
	vm.configure(imported)
	vm.start_program("xap:2")
	assert_equal(vm.run(api).error_code, &"malformed_classic_extra_code", "opcode 92 companion row uses the same guard")
	instruction.merge({"rawOpcode": 111, "opcode": 111, "id": 2463, "extraCode": null}, true)
	imported = PackageScenarioDecoder.new().decode_scenario(guarded, "fixture", true)
	assert_equal(imported.program_by_id("xap:2").instruction_at(0).extra_code_fault, null, "non-EDCD operands are not mistaken for row references")
	guarded["schemaVersion"] = 3
	assert_equal(PackageScenarioDecoder.new().decode_scenario(guarded, "fixture", true), null, "older schemas cannot silently acquire tail metadata")
