## Compares public VM clock execution with an explicit controlled-native receipt.
extends SceneTree

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []
var _content: RealmzContent


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or not args[2].is_absolute_path() or FileAccess.file_exists(args[2]):
		printerr("Expected native receipt, signed clock inputs and fresh absolute output JSON.")
		quit(2)
		return
	var native: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var inputs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not native is Dictionary or native.get("baseCommit") != "491816ad60037394f92c428e99c004494d3c28b3" or not inputs is Array:
		quit(2)
		return
	var repository := PackageRepository.new()
	var application := repository.load_package(ApplicationLibraryIdentity.PATH)
	if not application.is_ok():
		printerr(application.error_message)
		quit(2)
		return
	repository.set_application_content(application.content, application.media.assets())
	var loaded := repository.load_package("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2")
	if not loaded.is_ok():
		quit(2)
		return
	_content = loaded.content
	var words := {"day-zero": [1, 0, 0, 0, 99], "zero-midnight": [2, 0, 0, 60, 99], "keep-exact-minus-one": [1, -1, -1, -1, 99], "negative-offset": [2, -1, -2, -3, 99], "hour-before-minute-carry": [2, 0, 1, 60, 99], "minute-causes-midnight": [2, 0, 0, 60, 99], "unmatched-refresh": [77, -32768, 25, 61, -99], "noon-refresh": [0, 58, 13, 0, 0], "single-hour-carry": [2, 0, 49, 121, 0]}
	for input: Dictionary in inputs: words[input.name] = input.words
	if native.clock.size() != words.size():
		_failures.append("Native clock coverage does not match the complete input set.")
	for row: Dictionary in native.clock:
		if not words.has(row.case):
			_failures.append("Unknown native clock case: %s" % row.case)
			continue
		var values: Array[int] = []
		values.assign(words[row.case])
		words.erase(row.case)
		_probe_clock(row, values)
	if not words.is_empty(): _failures.append("Native clock cases missing: %s" % words.keys())
	var fixtures: Dictionary = preload("res://tools/clock_combat_fixture_cases.gd").new().run(_content, args[2].trim_suffix(".json") + "-fixtures", native.clockReturns)
	_failures.append_array(fixtures.failures)
	var output := {"format": "realmz.clock-combat-compatibility/1", "mode": "direct-public-vm", "nativeReceiptSha256": FileAccess.get_sha256(args[0]), "inputsSha256": FileAccess.get_sha256(args[1]), "packageHash": _content.package_hash, "applicationHash": _content.application_package_hash, "clockCases": _rows, "fixtures": fixtures, "failures": _failures}
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("CLOCK COMPARISON: %d cases; %d failures" % [_rows.size(), _failures.size()])
	for failure: String in _failures: printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _probe_clock(row: Dictionary, words: Array[int]) -> void:
	var caller := ScenarioProgramDefinition.new("clock.caller", &"action", "clock", [ClassicActionDefinition.new(0, 63, 63, 0, false, words), ClassicActionDefinition.new(1, 47, 47, 90, false, [])])
	var timer := ScenarioProgramDefinition.new("xap:900", &"extra-action-point", "extra-action-point:900", [ClassicActionDefinition.new(0, 47, 47, 91, false, [])])
	_content.scenario = ScenarioDefinition.new([caller, timer], [])
	_content.scenario_records = ScenarioContentCatalog.new(_content.campaign, [], [], [], [], [], [TimedEncounterDefinition.new(0, int(row.before.day) + 1, 1, 100, 900, timer.id, 0, -1, -1, -1, 0, -1, TimedEncounterDefinition.LocationKind.ANY), TimedEncounterDefinition.new(1, 0, 0, 0, 0, "xap:0", 0, 0, 0, 0, 0, 0, TimedEncounterDefinition.LocationKind.ANY)])
	var rules := RealmzRules.new()
	var hero := CharacterState.new("clock.hero", "Clock", int(row.before.stamina), int(row.before.stamina))
	hero.race_id = _content.characters.race_definitions()[0].id
	hero.caste_id = _content.characters.caste_definitions()[0].id
	hero.age_days = int(row.before.age)
	hero.age_group = rules.characters.infer_age_group(hero.age_days, _content.characters.race_by_id(hero.race_id))
	hero.maximum_spell_points = int(row.before.spellPoints)
	hero.spell_points = int(row.before.spellPoints)
	var state := GameState.new(PartyState.new(_content.start_map_id, _content.start_coordinate, [hero]), RealmzClock.new())
	state.party.fatigue = int(row.before.fatigue)
	state.clock.set_components(int(row.before.day), int(row.before.hour), int(row.before.minute))
	var rng := RealmzRng.new(1)
	var api := RealmzRuntimeApi.new(_content, state, rng, ScenarioActionState.new())
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	vm.start_program(caller.id)
	var result := vm.run(api)
	for ack: int in 6:
		if result.state != ScenarioVmResult.State.WAITING or result.interaction.kind != InteractionRequest.AGE_UPDATE: break
		result = vm.resume(InteractionResponse.acknowledge(result.interaction), api)
	var actual := {"day": state.clock.day(), "hour": state.clock.hour(), "minute": state.clock.minute(), "age": hero.age_days, "stamina": hero.current_health, "spellPoints": hero.spell_points, "fatigue": state.party.fatigue, "timerMarker": state.scenario_progress.quest_value(91), "followingSlot": state.scenario_progress.quest_value(90)}
	var expected: Dictionary = row.after.duplicate()
	if expected.has("rngDrawCount"):
		_check_rng(row.case, rng.snapshot().draw_count, int(expected.rngDrawCount) - int(row.before.rngDrawCount))
		expected.erase("rngDrawCount")
	for key: String in expected: expected[key] = int(expected[key])
	var mismatch: bool = result.state != ScenarioVmResult.State.COMPLETED or actual != expected
	_rows.append({"case": row.case, "words": words, "actual": actual, "expected": expected, "rngDraws": rng.snapshot().draw_count, "passed": not mismatch})
	if mismatch: _failures.append("%s: state %s, %s != %s" % [row.case, result.state, actual, row.after])


func _check_rng(label: String, actual: int, expected: int) -> void:
	if actual != expected: _failures.append("%s RNG: %d != %d" % [label, actual, expected])
