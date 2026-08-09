extends RealmzTestCase


func run() -> void:
	_test_character_half_attack_cadence_and_restore()
	_test_monster_authored_attack_rows_and_target_retention()
	_test_monster_attack_cursor_restore()
	_test_battle_owned_fumble_and_exact_recovery()
	_test_monster_fumble_clears_only_active_weapon()


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
	active_turn.physical_action_committed = true

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-sequence monster cursor survives central state restoration")
	assert_equal(restored.combat.active_turn.attack_index, 1, "restore does not repeat the committed first attack row")
	assert_true(restored.combat.active_turn.physical_action_committed, "restore retains that the active monster turn already issued a physical row")
	var legacy_turn_data := restored.combat.active_turn.to_data()
	legacy_turn_data.erase("physicalActionCommitted")
	var legacy_turn := CombatTurnState.from_data(legacy_turn_data)
	assert_not_null(legacy_turn, "pre-fumble save-v3 active turns remain readable")
	assert_false(legacy_turn.physical_action_committed, "a legacy active turn does not fabricate a prior physical action")
	var rng_values: Array[int] = []
	rng_values.resize(20)
	rng_values.fill(0)
	var events: Array[DomainEvent] = []
	RealmzRules.new().combat_flow._process_monster_turns(restored, _content([definition]), ScriptedRng.new(rng_values), events)
	var attacks_seen := events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved")
	assert_equal(attacks_seen.size(), 2, "restore executes only the two remaining authored rows")
	assert_equal(attacks_seen.map(func(event: DomainEvent) -> int: return int(event.payload.get("attackIndex"))), [1, 2], "the restored cursor resumes at the exact next row")
	assert_equal(restored.combat.active_actor_id(), character.id, "the restored sequence advances after its final row")


func _test_battle_owned_fumble_and_exact_recovery() -> void:
	var rules := RealmzRules.new()
	var weapon := ItemDefinition.new("item.fumble-recovery", 77, "Charged Blade")
	weapon.item_type = 2
	weapon.vs_small = 1
	weapon.initial_charges = 30
	weapon.weight = 2
	weapon.weight_per_charge = 1
	var character := _character("character.fumble-recovery")
	character.maximum_load = 100
	character.normal_attacks = 4
	var instance := rules.inventory.add_item(character, weapon, "instance.fumble-recovery", false)
	assert_not_null(instance, "fumble flow fixture grants its charged melee weapon")
	if instance == null:
		return
	instance.charges = 7
	character.carried_load = weapon.instance_weight(instance.charges)
	assert_true(rules.inventory.equip(character, instance.id, weapon), "fumble flow fixture equips its melee weapon")
	var definition := _monster_definition("monster.fumble-passive", [])
	var monster := MonsterState.new("monster.fumble-passive.instance", definition.id, definition.name, 100, 100, 1)
	var state := _state(character, monster, "battle.fumble-recovery")
	var result := rules.combat_flow.submit_action(state, _content([definition], [weapon]), character.id, &"attack", monster.id, ScriptedRng.new([0, 0, 1609]))
	assert_true(result.ok, "a source-ranged fumble commits through the combat flow")
	assert_equal(character.inventory().size(), 0, "the fumbled weapon leaves the active inventory")
	assert_equal(state.party.storage().size(), 0, "the fumbled weapon does not enter unrelated party storage")
	assert_equal(state.combat.fumbled_items().size(), 1, "the completed mutation owns the weapon in battle state")
	assert_equal([state.combat.fumbled_items()[0].charges, state.combat.fumbled_items()[0].identified], [7, true], "FD-COMBAT-005 keeps remaining charges and applies Castle's recovery identification")
	var character_fumble_sounds := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("source") == "classic-combat-fumble")
	assert_equal(character_fumble_sounds.map(func(event: DomainEvent) -> Array: return [event.payload.get("soundId"), event.payload.get("waitForCompletion")]), [[10121, true], [10123, true], [655, false]], "character fumble preserves both synchronous sounds followed by dropitem's asynchronous sound 655")
	var correction_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/oracle/fumbled-item-charge-correction.json"))
	assert_true(correction_fixture is Dictionary, "the fumbled-item charge decision has a parseable source-observation fixture")
	if correction_fixture is Dictionary:
		assert_equal([int(correction_fixture["castleSourceObservation"]["recoveredCharges"]), int(correction_fixture["realmz2ChosenResult"]["recoveredCharges"])], [30, 7], "FD-COMBAT-005 separates Castle's reconstructed charge count from the chosen exact-instance result")
	var burdened := _character("character.fumble-burdened")
	burdened.maximum_load = 100
	burdened.carried_load = 92
	assert_false(rules.inventory.can_restore_item(burdened, state.combat.fumbled_items()[0], weapon), "FD-COMBAT-005 tests the exact remaining charge weight instead of Castle's base-weight-only recovery check")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "the battle-local fumble queue survives central state restoration")
	if restored == null:
		return
	assert_equal(restored.combat.fumbled_items()[0].to_data(), state.combat.fumbled_items()[0].to_data(), "save restoration preserves the exact queued item instance")
	restored.combat.completed = true
	restored.combat.outcome = &"defeat"
	var restored_character := restored.party.character_by_id(character.id)
	restored_character.current_health = 0
	var payload := rules.combat_flow.fumble_recovery_payload(restored, _content([definition], [weapon]))
	assert_equal([payload.get("mode"), payload.get("remaining")], ["fumbled-item-recovery", 1], "post-battle recovery exposes one typed assignment at a time")
	assert_true(payload["characters"][0]["enabled"], "Castle's fumble booty remains assignable after defeat and does not invent a survivor-only loss rule")
	var recovered := rules.combat_flow.apply_fumble_recovery(restored, _content([definition], [weapon]), {"action": "assign", "instanceId": instance.id, "characterId": character.id})
	assert_true(recovered.ok, "a legal post-battle recipient receives the fumbled weapon")
	assert_equal(restored_character.inventory()[0].to_data(), {"id": instance.id, "definitionId": weapon.id, "equipped": false, "identified": true, "charges": 7}, "recovery restores the exact item unequipped instead of reconstructing default charges")
	assert_true(restored.combat.fumbled_items().is_empty(), "assigned recovery removes the item from battle state")


func _test_monster_fumble_clears_only_active_weapon() -> void:
	var rules := RealmzRules.new()
	var weapon := ItemDefinition.new("item.monster-fumble", 78, "Monster Blade")
	weapon.item_type = 2
	weapon.vs_small = 1
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(1, 1), MonsterAttackDefinition.new(2, 2)]
	var definition := _monster_definition("monster.armed-fumbler", attacks)
	definition.hit_dice = 4
	definition.weapon_id = weapon.id
	var character := _character("character.monster-fumble-target")
	character.current_health = 20
	character.maximum_health = 20
	var monster := MonsterState.new("monster.armed-fumbler.instance", definition.id, definition.name, 20, 20, 4)
	monster.weapon_id = weapon.id
	var state := _state(character, monster, "battle.monster-fumble")
	var values: Array[int] = [0, 0, 0, 0, 0, 942, 0, 0, 0, 0]
	var result := rules.combat_flow.submit_action(state, _content([definition], [weapon]), character.id, &"defend", "", ScriptedRng.new(values))
	assert_true(result.ok, "an armed monster fumble resolves through automatic combat flow")
	assert_equal(monster.weapon_id, "", "Castle clears the monster's active carried weapon after a fumble")
	var monster_attacks := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == monster.id)
	assert_equal(monster_attacks.size(), 2, "the monster continues its remaining authored attack rows after dropping the active weapon")
	assert_equal(monster_attacks.map(func(event: DomainEvent) -> int: return int(event.payload.get("damage"))), [0, 2], "the fumble misses and later rows use unarmed authored damage")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_fumbled" and event.payload.get("itemId") == weapon.id), "monster fumble feedback preserves the dropped active weapon identity")
	var monster_fumble_sounds := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("source") == "classic-combat-fumble")
	assert_equal(monster_fumble_sounds.map(func(event: DomainEvent) -> Array: return [event.payload.get("soundId"), event.payload.get("waitForCompletion")]), [[10121, true], [655, true]], "monster fumble preserves Castle's two synchronous sound calls")


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


func _content(monsters: Array[MonsterDefinition], items: Array[ItemDefinition] = []) -> RealmzContent:
	return RealmzContent.new("campaign.cadence", "0".repeat(64), "cadence", "realmz-classic-1", "map.test", Vector2i.ZERO, WorldDefinition.new([]), ScenarioDefinition.new([], []), [], [], [], [], [], items, [], monsters)


func _ints(count: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(0)
	return result
