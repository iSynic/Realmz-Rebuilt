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
	var assertion_count: int = 0
	var failure_count: int = 0
	for suite_script: Script in SUITES:
		print("RUN: %s" % suite_script.resource_path)
		var suite: RealmzTestCase = suite_script.new()
		suite.run()
		print("DONE: %s (%d assertions)" % [suite_script.resource_path, suite.assertions])
		assertion_count += suite.assertions
		for failure: String in suite.failures:
			failure_count += 1
			printerr("FAIL %s: %s" % [suite_script.resource_path, failure])
	if failure_count == 0:
		print("PASS: %d assertions across %d suites" % [assertion_count, SUITES.size()])
		quit(0)
	else:
		printerr("FAILED: %d failures across %d assertions" % [failure_count, assertion_count])
		quit(1)
