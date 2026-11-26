extends RealmzTestCase

## Limit Monster Reinforcements caps the rounds in which a battle's round script brings in
## monsters, and skips a reinforcement-only branch once the cap is reached.

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	_test_rules_round_trip()
	_test_spawn_waves(loaded.content)


func _test_rules_round_trip() -> void:
	var rules := AdventureRules.new()
	assert_false(rules.to_data().has("reinforcementLimit"), "Classic reinforcements leave the saved rules unchanged")
	rules.reinforcement_limit = 2
	var restored := AdventureRules.from_data(rules.to_data())
	assert_true(restored != null and restored.reinforcement_limit == 2, "a reinforcement limit round-trips")
	assert_equal(AdventureRules.from_data({"freeTargetingCancellation": false, "reinforcementLimit": 4}), null, "only the offered limits are accepted")
	assert_equal(AdventureRules.from_data({"freeTargetingCancellation": false, "reinforcementLimit": -1}), null, "Classic is written by leaving the limit out")


func _test_spawn_waves(content: RealmzContent) -> void:
	var summoned := MonsterDefinition.new("classic.monster.4", 4, "Minor Demon", 1, 4, 8, 0, 0, [], [], [], [], [], [], [])
	summoned.can_summon = -1
	var battle := BattleDefinition.new("battle.reinforcements", 1241, [])
	var only_reinforcements := ScenarioProgramDefinition.new("xap:77", &"extra-action-point", "77", [ClassicActionDefinition.new(0, 1, 1, 0, false, [0, 0, 0, 0, 0]), ClassicActionDefinition.new(1, 124, 124, 0, false, [0, 4, 1, 0, 0])])
	var with_story := ScenarioProgramDefinition.new("xap:78", &"extra-action-point", "78", [ClassicActionDefinition.new(0, 47, 47, 12, false, []), ClassicActionDefinition.new(1, 124, 124, 0, false, [0, 4, 1, 0, 0])])
	var scenario := ScenarioDefinition.new([only_reinforcements, with_story], [])
	var spawn_content := RealmzContent.new("reinforcements", "2".repeat(64), "reinforcements", content.rules_version, content.start_map_id, content.start_coordinate, content.world, scenario, [], [], [], [], [], [], [], [summoned], [battle])
	var hero := CharacterState.new("reinforcements.hero", "Hero", 20, 20)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, [hero]), RealmzClock.new())
	var map := content.world.map_by_id(content.start_map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null:
		assert_true(false, "the reinforcement fixture resolves the active map's battle terrain")
		return
	var tiles: Array[int] = []
	tiles.resize(BattlefieldGrid.CELL_COUNT)
	tiles.fill(terrain_set.base_tile)
	var field := BattlefieldState.new(content.start_map_id, tiles)
	field.actors.place_character(hero.id, Vector2i(45, 45))
	# Castle places a spawn beside the monster whose script runs; this one stands at (50,50).
	var source := MonsterState.new("reinforcements.source", summoned.id, summoned.name, 20, 20, 1, 8, 0, 0, 0, true)
	field.actors.place_monster(source.id, Vector2i(50, 50), summoned.size)
	state.combat = CombatState.new(battle.id, [source], -1, field)
	state.combat.set_turn_order([hero.id, source.id])
	state.combat.round_cursor = CombatRoundCursor.new()
	state.combat.round_cursor.phase = &"battle-macro"
	state.adventure_rules.reinforcement_limit = 1
	var api := RealmzRuntimeApi.new(spawn_content, state, RealmzRng.for_oracle(1241), ScenarioActionState.new(), RealmzRules.new())
	var spawn := ClassicActionDefinition.new(0, 124, 124, 0, false, [0, 4, 1, 0, 0])
	var context := ScenarioExecutionContext.calling(&"battle-macro").set_battle(battle.id)
	var counts: Array[int] = []
	for round_number: int in [1, 1, 2]:
		state.combat.turns.round_number = round_number
		api.execute_classic(spawn, "reinforcement.%d" % counts.size(), context)
		counts.append(state.combat.roster.monsters().size())
	assert_equal(counts, [2, 3, 3], "a one-wave limit lets every spawn of the first round's script through and stops the next round's")
	assert_true(ClassicReinforcementLimit.blocks_branch(state, only_reinforcements) and not ClassicReinforcementLimit.blocks_branch(state, with_story), "a spent limit skips a reinforcement-only branch but runs one that also changes the story")
	var round_macro := api.execute_classic(ClassicActionDefinition.new(0, 126, 126, 0, false, [0, 1, 1, 77, 0]), "reinforcement.branch", context)
	assert_true(_event_seen(round_macro.events, &"combat_reinforcements_limited") and not _event_seen(round_macro.events, &"battle_macro_tested"), "the round script's branch to a reinforcement-only script is skipped once the limit is spent")
	var restored := CombatState.from_data(state.combat.to_data())
	assert_true(restored != null and restored.reinforcement_waves == 1 and restored.reinforcement_wave_round == 1, "the waves used survive a save in the middle of a battle")
	state.combat.round_cursor.phase = &"party"
	api.execute_classic(spawn, "reinforcement.death", context)
	assert_equal(state.combat.roster.monsters().size(), 4, "a spawn outside the round script is never limited")
	state.combat.round_cursor.phase = &"battle-macro"
	state.combat.turns.round_number = 3
	state.adventure_rules.reinforcement_limit = AdventureRules.UNLIMITED_REINFORCEMENTS
	api.execute_classic(spawn, "reinforcement.classic", context)
	assert_equal(state.combat.roster.monsters().size(), 5, "Classic leaves reinforcements unlimited")


func _event_seen(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false
