extends SceneTree

const SUITES: Array[Script] = [
	preload("res://tests/core/test_game_session.gd"),
	preload("res://tests/core/test_realmz_rng.gd"),
	preload("res://tests/core/test_map_topology.gd"),
	preload("res://tests/infrastructure/test_package_repository.gd"),
	preload("res://tests/integration/test_exploration_session.gd"),
	preload("res://tests/integration/test_session_persistence.gd"),
]


func _initialize() -> void:
	var assertion_count: int = 0
	var failure_count: int = 0
	for suite_script: Script in SUITES:
		var suite: RealmzTestCase = suite_script.new()
		suite.run()
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
