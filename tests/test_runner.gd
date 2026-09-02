extends SceneTree

const SUITES: Array[Script] = [
	preload("res://tests/core/test_game_session.gd"),
	preload("res://tests/core/test_realmz_rng.gd"),
	preload("res://tests/core/test_map_topology.gd"),
	preload("res://tests/core/test_realmz_rules.gd"),
	preload("res://tests/core/test_battlefield_builder.gd"),
	preload("res://tests/core/test_battlefield_navigation.gd"),
	preload("res://tests/core/test_combat_flow.gd"),
	preload("res://tests/core/test_character_creation_session.gd"),
	preload("res://tests/infrastructure/test_package_repository.gd"),
	preload("res://tests/infrastructure/test_package_install_task.gd"),
	preload("res://tests/infrastructure/test_save_repository.gd"),
	preload("res://tests/infrastructure/test_character_vault_repository.gd"),
	preload("res://tests/presentation/test_dungeon_geometry_projection.gd"),
	preload("res://tests/presentation/test_allies_workspace.gd"),
	preload("res://tests/presentation/test_music_system.gd"),
	preload("res://tests/presentation/test_classic_ui_shell.gd"),
	preload("res://tests/presentation/test_classic_ui_system.gd"),
	preload("res://tests/scenario/test_reward_workflow.gd"),
	preload("res://tests/scenario/test_scenario_vm.gd"),
	preload("res://tests/integration/test_exploration_session.gd"),
	preload("res://tests/integration/test_session_persistence.gd"),
	preload("res://tests/integration/test_inventory_session.gd"),
	preload("res://tests/integration/test_field_spell_workflow.gd"),
	preload("res://tests/integration/test_scroll_camp_workflow.gd"),
	preload("res://tests/integration/test_money_workflow.gd"),
	preload("res://tests/integration/test_party_order_workflow.gd"),
	preload("res://tests/integration/test_character_appearance_workflow.gd"),
]
const USAGE: String = "Usage: godot --headless --path <project> --script res://tests/test_runner.gd [-- --suite <path-fragment> ...] [--case <test-name-fragment> ...]"


func _initialize() -> void: _run()


func _run() -> void:
	var requested_fragments: Array[String] = []; var requested_cases: Array[String] = []
	var arguments := OS.get_cmdline_user_args(); var argument_index: int = 0
	while argument_index < arguments.size():
		var argument: String = arguments[argument_index]
		if argument_index + 1 >= arguments.size() or argument not in ["--suite", "--case"]:
			printerr(USAGE)
			quit(2)
			return
		var fragment: String = arguments[argument_index + 1]
		if fragment.is_empty() or fragment.begins_with("--"):
			printerr(USAGE)
			quit(2)
			return
		if argument == "--suite":
			requested_fragments.append(fragment)
		else:
			requested_cases.append(fragment)
		argument_index += 2
	for fragment: String in requested_fragments:
		var fragment_matches_suite: bool = false
		for suite_script: Script in SUITES:
			if suite_script.resource_path.contains(fragment):
				fragment_matches_suite = true
				break
		if not fragment_matches_suite:
			printerr("No test suite matches filter '%s'." % fragment)
			quit(2)
			return
	if not requested_cases.is_empty() and requested_fragments.is_empty():
		printerr("Named case filters require at least one --suite filter so unrelated suites are never instantiated.")
		quit(2)
		return
	var selected_suites: Array[Script] = []
	for suite_script: Script in SUITES:
		if requested_fragments.is_empty():
			selected_suites.append(suite_script)
			continue
		for fragment: String in requested_fragments:
			if suite_script.resource_path.contains(fragment):
				selected_suites.append(suite_script)
				break
	if selected_suites.is_empty():
		printerr("No test suite matches the requested filters.")
		quit(2)
		return
	for case_fragment: String in requested_cases:
		var fragment_matches_case: bool = false
		for suite_script: Script in selected_suites:
			var suite: RealmzTestCase = suite_script.new()
			for method: Dictionary in _test_methods(suite):
				if String(method["name"]).contains(case_fragment):
					fragment_matches_case = true
					break
			if fragment_matches_case:
				break
		if not fragment_matches_case:
			printerr("No test case in the selected suites matches filter '%s'." % case_fragment)
			quit(2)
			return
	var assertion_count: int = 0
	var failure_count: int = 0
	for suite_script: Script in selected_suites:
		var suite_started: int = Time.get_ticks_msec()
		print("RUN SUITE: %s" % suite_script.resource_path)
		var suite: RealmzTestCase = suite_script.new()
		if requested_cases.is_empty():
			suite.run()
			if suite_script.resource_path.ends_with("test_classic_ui_system.gd"): await suite.call("_test_application_quit_composition")
		else:
			var selected_methods := _selected_test_methods(suite, requested_cases)
			var shared_arguments: Array = []
			if selected_methods.any(func(method: Dictionary) -> bool: return not (method.get("args", []) as Array).is_empty()):
				shared_arguments = suite.selected_case_arguments()
			for method: Dictionary in selected_methods:
				var method_name := String(method["name"])
				var method_arguments: Array = method.get("args", []) as Array
				if not method_arguments.is_empty() and method_arguments.size() != shared_arguments.size():
					printerr("Test case '%s' needs %d shared argument(s), but its suite prepared %d." % [method_name, method_arguments.size(), shared_arguments.size()])
					quit(2)
					return
				var case_started: int = Time.get_ticks_msec()
				var assertions_before: int = suite.assertions
				print("RUN CASE: %s::%s" % [suite_script.resource_path, method_name])
				if method_arguments.is_empty():
					await suite.call(method_name)
				else:
					await suite.callv(method_name, shared_arguments)
				print("DONE CASE: %s::%s (%d assertions, %d ms)" % [suite_script.resource_path, method_name, suite.assertions - assertions_before, Time.get_ticks_msec() - case_started])
		print("DONE SUITE: %s (%d assertions, %d ms)" % [suite_script.resource_path, suite.assertions, Time.get_ticks_msec() - suite_started])
		assertion_count += suite.assertions
		for failure: String in suite.failures:
			failure_count += 1
			printerr("FAIL %s: %s" % [suite_script.resource_path, failure])
	if failure_count == 0:
		print("PASS: %d assertions across %d suites" % [assertion_count, selected_suites.size()])
		quit(0)
	else:
		printerr("FAILED: %d failures across %d assertions" % [failure_count, assertion_count])
		quit(1)


func _test_methods(suite: RealmzTestCase) -> Array[Dictionary]:
	var methods: Array[Dictionary] = []
	for method: Dictionary in suite.get_method_list():
		if String(method.get("name", "")).begins_with("_test_"):
			methods.append(method)
	return methods


func _selected_test_methods(suite: RealmzTestCase, fragments: Array[String]) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var methods := _test_methods(suite)
	for fragment: String in fragments:
		for method: Dictionary in methods:
			if String(method["name"]).contains(fragment) and not selected.has(method):
				selected.append(method)
	return selected
