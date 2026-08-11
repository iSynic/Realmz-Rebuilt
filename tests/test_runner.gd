extends SceneTree

const SUITES: Array[Script] = [
	preload("res://tests/core/test_game_session.gd"),
	preload("res://tests/core/test_realmz_rng.gd"),
	preload("res://tests/core/test_map_topology.gd"),
	preload("res://tests/core/test_realmz_rules.gd"),
	preload("res://tests/core/test_battlefield_builder.gd"),
	preload("res://tests/core/test_combat_flow.gd"),
	preload("res://tests/infrastructure/test_package_repository.gd"),
	preload("res://tests/infrastructure/test_save_repository.gd"),
	preload("res://tests/infrastructure/test_character_vault_repository.gd"),
	preload("res://tests/presentation/test_dungeon_geometry_projection.gd"),
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
const USAGE: String = "Usage: godot --headless --path <project> --script res://tests/test_runner.gd [-- --suite <path-fragment> ...]"


func _initialize() -> void:
	var requested_fragments: Array[String] = []
	var arguments := OS.get_cmdline_user_args()
	var argument_index: int = 0
	while argument_index < arguments.size():
		var argument: String = arguments[argument_index]
		if argument != "--suite" or argument_index + 1 >= arguments.size():
			printerr(USAGE)
			quit(2)
			return
		var fragment: String = arguments[argument_index + 1]
		if fragment.is_empty() or fragment.begins_with("--"):
			printerr(USAGE)
			quit(2)
			return
		requested_fragments.append(fragment)
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
