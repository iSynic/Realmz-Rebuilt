extends SceneTree

const SUITES: Array[Script] = [
	preload("res://tests/core/test_game_session.gd"),
	preload("res://tests/core/test_realmz_rng.gd"),
	preload("res://tests/core/test_map_topology.gd"),
	preload("res://tests/core/test_realmz_rules.gd"),
	preload("res://tests/core/test_battlefield_builder.gd"),
	preload("res://tests/core/test_combat_flow.gd"),
	preload("res://tests/infrastructure/test_package_repository.gd"),
	preload("res://tests/infrastructure/test_character_vault_repository.gd"),
	preload("res://tests/presentation/test_dungeon_geometry_projection.gd"),
	preload("res://tests/presentation/test_classic_ui_system.gd"),
	preload("res://tests/scenario/test_scenario_vm.gd"),
	preload("res://tests/integration/test_exploration_session.gd"),
	preload("res://tests/integration/test_session_persistence.gd"),
]


func _initialize() -> void:
	var requested_suite := ""
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() == 2 and arguments[0] == "--suite":
		requested_suite = arguments[1]
	elif not arguments.is_empty():
		printerr("Usage: godot --headless --path <project> --script res://tests/test_runner.gd [-- --suite <path-fragment>]")
		quit(2)
		return
	var selected_suites: Array[Script] = []
	for suite_script: Script in SUITES:
		if requested_suite.is_empty() or suite_script.resource_path.contains(requested_suite):
			selected_suites.append(suite_script)
	if selected_suites.is_empty():
		printerr("No test suite matches '%s'." % requested_suite)
		quit(2)
		return
	var assertion_count: int = 0
	var failure_count: int = 0
	for suite_script: Script in selected_suites:
		print("RUN: %s" % suite_script.resource_path)
		var suite: RealmzTestCase = suite_script.new()
		suite.run()
		print("DONE: %s (%d assertions)" % [suite_script.resource_path, suite.assertions])
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
