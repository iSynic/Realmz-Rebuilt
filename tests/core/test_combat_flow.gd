extends RealmzTestCase


func run() -> void:
	_test_character_half_attack_cadence_and_restore()
	_test_monster_authored_attack_rows_and_target_retention()
	_test_monster_attack_cursor_restore()


func _test_character_half_attack_cadence_and_restore() -> void:
	var rules := RealmzRules.new()
	var character := _character("character.fractional")
	character.normal_attacks = 3
	character.attacks_remaining = 0
	var definition := _monster_definition("monster.passive", [])
	var monster := MonsterState.new("monster.passive.instance", definition.id, definition.name, 1_000, 1_000, 1)
	var state := _state(character, monster, "battle.fractional")
	var content := _content([definition])
	var rng := RealmzRng.new(731)

	var first := rules.combat_flow.submit_action(state, content, character.id, &"attack", monster.id, rng)
	assert_true(first.ok, "the first fractional attack resolves")
	assert_equal(state.combat.active_actor_id(), character.id, "automatic passive monster processing returns to the character")
	assert_equal(character.attacks_remaining, 4, "one carried half-unit combines with the next three-unit activation")
	assert_equal(state.combat.round_number, 2, "the first one-and-a-half attack activation advances the round")
	assert_not_null(state.combat.active_turn, "the next prepared character activation is explicit session state")

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "an active fractional attack boundary survives central state restoration")
	assert_equal(restored.combat.active_turn.actor_id, character.id, "restore retains the exact active actor")
	assert_equal(restored.party.character_by_id(character.id).attacks_remaining, 4, "restore retains the integer half-attack reserve")

	var restored_character := restored.party.character_by_id(character.id)
	var restored_monster := restored.combat.monster_by_id(monster.id)
	var second := rules.combat_flow.submit_action(restored, content, restored_character.id, &"attack", restored_monster.id, rng)
	assert_true(second.ok, "the restored character can spend the first full attack")
	assert_equal(restored.combat.active_actor_id(), restored_character.id, "two remaining half-units keep the same activation")
	assert_equal(restored_character.attacks_remaining, 2, "one full attack consumes exactly two half-units")
	assert_equal(restored.combat.round_number, 2, "a repeated attack does not advance the round")

	var third := rules.combat_flow.submit_action(restored, content, restored_character.id, &"attack", restored_monster.id, rng)
	assert_true(third.ok, "the second full attack resolves in the same activation")
	assert_equal(restored.combat.active_actor_id(), restored_character.id, "the passive monster returns control for the next activation")
	assert_equal(restored_character.attacks_remaining, 3, "an exhausted reserve receives the next three half-unit allowance without a carry")
	assert_equal(restored.combat.round_number, 3, "exhausting the reserve advances through the next round")


func _test_monster_authored_attack_rows_and_target_retention() -> void:
	var rules := RealmzRules.new()
	var character := _character("character.multi-target")
	character.current_health = 100
	character.maximum_health = 100
	var attacks: Array[MonsterAttackDefinition] = [
		MonsterAttackDefinition.new(1, 1),
		MonsterAttackDefinition.new(2, 2),
		MonsterAttackDefinition.new(3, 3),
	]
	var definition := _monster_definition("monster.multi", attacks)
	definition.hit_dice = 20
	var monster := MonsterState.new("monster.multi.instance", definition.id, definition.name, 100, 100, 20, 100)
	var state := _state(character, monster, "battle.multi")
	var rng_values: Array[int] = []
	rng_values.resize(32)
	rng_values.fill(0)
	var rng := ScriptedRng.new(rng_values)

	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"defend", "", rng)
	assert_true(result.ok, "a three-row monster activation resolves")
	var attacks_seen: Array[DomainEvent] = []
	for event: DomainEvent in result.events:
		if event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == monster.id:
			attacks_seen.append(event)
	assert_equal(attacks_seen.size(), 3, "the monster executes every authored physical attack row")
	assert_equal(attacks_seen.map(func(event: DomainEvent) -> int: return int(event.payload.get("attackIndex"))), [0, 1, 2], "monster attack events retain authored row order")
	assert_equal(attacks_seen.map(func(event: DomainEvent) -> int: return int(event.payload.get("damage"))), [1, 2, 3], "each attack row resolves its own damage fields")
	assert_true(attacks_seen.all(func(event: DomainEvent) -> bool: return event.payload.get("targetId") == character.id), "a surviving target remains selected for the whole activation")
	var target_draws := rng.trace().filter(func(entry: Dictionary) -> bool: return entry.get("tag") == "combat.monster-target")
	assert_equal(target_draws.size(), 1, "one Castle target draw owns the complete authored attack sequence")
	assert_equal(state.combat.active_actor_id(), character.id, "the monster advances only after its final authored row")


func _test_monster_attack_cursor_restore() -> void:
	var character := _character("character.cursor")
	character.current_health = 100
	character.maximum_health = 100
	var attacks: Array[MonsterAttackDefinition] = [
		MonsterAttackDefinition.new(1, 1),
		MonsterAttackDefinition.new(2, 2),
		MonsterAttackDefinition.new(3, 3),
	]
	var definition := _monster_definition("monster.cursor", attacks)
	definition.hit_dice = 20
	var monster := MonsterState.new("monster.cursor.instance", definition.id, definition.name, 100, 100, 20, 100)
	var state := _state(character, monster, "battle.cursor")
	state.combat.turn_index = 1
	var active_turn := state.combat.begin_active_turn()
	active_turn.action = &"advance"
	active_turn.attack_index = 1
	active_turn.target_id = character.id

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-sequence monster cursor survives central state restoration")
	assert_equal(restored.combat.active_turn.attack_index, 1, "restore does not repeat the committed first attack row")
	var rng_values: Array[int] = []
	rng_values.resize(20)
	rng_values.fill(0)
	var events: Array[DomainEvent] = []
	RealmzRules.new().combat_flow._process_monster_turns(restored, _content([definition]), ScriptedRng.new(rng_values), events)
	var attacks_seen := events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved")
	assert_equal(attacks_seen.size(), 2, "restore executes only the two remaining authored rows")
	assert_equal(attacks_seen.map(func(event: DomainEvent) -> int: return int(event.payload.get("attackIndex"))), [1, 2], "the restored cursor resumes at the exact next row")
	assert_equal(restored.combat.active_actor_id(), character.id, "the restored sequence advances after its final row")


func _character(character_id: String) -> CharacterState:
	var result := CharacterState.new(character_id, "Cadence Hero", 30, 30)
	result.race_id = "race.test"
	result.caste_id = "caste.test"
	result.luck = 1
	result.hand_to_hand = 1
	result.normal_attacks = 2
	result.maximum_movement = 12
	result.movement = 12
	return result


func _monster_definition(definition_id: String, attacks: Array[MonsterAttackDefinition]) -> MonsterDefinition:
	return MonsterDefinition.new(definition_id, 1, "Cadence Monster", 1, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), [], [], attacks)


func _state(character: CharacterState, monster: MonsterState, battle_id: String) -> GameState:
	var result := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [character]), RealmzClock.new())
	result.combat = CombatState.new(battle_id, [monster])
	result.combat.set_turn_order([character.id, monster.id])
	return result


func _content(monsters: Array[MonsterDefinition]) -> RealmzContent:
	return RealmzContent.new("campaign.cadence", "0".repeat(64), "cadence", "realmz-classic-1", "map.test", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [], [], [], [], monsters)


func _ints(count: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(0)
	return result
