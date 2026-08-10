extends RealmzTestCase

var _cached_battle_world: WorldDefinition


func run() -> void:
	_test_tactical_adjacency_movement_and_restore()
	_test_guard_and_withdrawal_reactions()
	_test_character_and_monster_retreat()
	_test_guard_followups()
	_test_guard_death_macro_revival_continuation()
	_test_guard_age_update_restore()
	_test_monster_los_targeting_and_movement()
	_test_character_half_attack_cadence_and_restore()
	_test_character_weapon_mode_toggle_and_restore()
	_test_monster_missile_does_not_impersonate_melee()
	_test_source_backed_projectile_fire()
	_test_source_backed_character_spell_casting()
	_test_source_backed_combat_spell_item_use()
	_test_source_backed_special_healing_and_actor_targeting()
	_test_character_automatic_group_spell()
	_test_character_fixed_area_spell()
	_test_character_and_monster_repeated_target_spells()
	_test_ordinary_spell_reflection_and_opposed_monster_targets()
	_test_spell_death_macro_queue_and_restore()
	_test_source_backed_monster_spell_casting()
	_test_charm_resistance_continues_after_failed_opposed_save()
	_test_monster_authored_attack_rows_and_target_retention()
	_test_monster_attack_cursor_restore()
	_test_battle_owned_fumble_and_exact_recovery()
	_test_monster_fumble_clears_only_active_weapon()


func _test_source_backed_combat_spell_item_use() -> void:
	var rules := RealmzRules.new()
	var character := _character("character.item-caster")
	character.normal_attacks = 4
	character.spell_points = 0
	character.maximum_spell_points = 0
	character.maximum_load = 100
	var monster_definition := _monster_definition("monster.item-target", [MonsterAttackDefinition.new(1, 1)])
	var monster := MonsterState.new("monster.item-target.instance", monster_definition.id, "Item Target", 10, 10, 1)
	var state := _state(character, monster, "battle.item-use")
	var category_mask := 1 << 5
	var empty_ranges: Array[Vector2i] = []
	var empty_age_changes: Array[PackedInt32Array] = []
	var race := RaceDefinition.new("race.test", 1, "Human", _ints(8), _ints(8), _ints(5), _ints(5), _ints(40), empty_ranges, empty_age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, category_mask, 0)
	var caste := CasteDefinition.new("caste.test", 1, "Fighter", _ints(8), _ints(5), _ints(5), _ints(40), Vector2i(1, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 1, 1, 0, 1, 0, 0, 0, 1, 0, true, false, 0, category_mask, 0)
	var spell := SpellDefinition.new("spell.item-bolt", 1101, "Item Bolt")
	spell.damage_min = 3
	spell.damage_max = 3
	spell.damage_type = 1
	spell.spell_class = 1
	spell.cannot = 3
	spell.target_type = 1
	spell.in_combat = true
	spell.range_min = 10
	var group_spell := SpellDefinition.new("spell.item-wave", 1102, "Item Wave")
	group_spell.damage_min = 2
	group_spell.damage_max = 2
	group_spell.damage_type = 1
	group_spell.spell_class = 1
	group_spell.cannot = 3
	group_spell.target_type = 10
	group_spell.in_combat = true
	var item := ItemDefinition.new("item.combat-wand", 41, "Combat Wand")
	item.item_type = 21
	item.item_category_mask_low = category_mask
	item.initial_charges = 2
	item.weight = 2
	item.weight_per_charge = 1
	item.special_1 = 1
	item.special_2 = spell.classic_id
	item.sound_id = 49
	var instance := rules.inventory.add_item(character, item, "item.combat-wand.instance", true)
	var group_item := ItemDefinition.new("item.combat-wave", 42, "Wave Wand")
	group_item.item_type = 21
	group_item.item_category_mask_low = category_mask
	group_item.initial_charges = 1
	group_item.special_1 = 1
	group_item.special_2 = group_spell.classic_id
	var group_instance := rules.inventory.add_item(character, group_item, "item.combat-wave.instance", true)
	var content := _content([monster_definition], [item, group_item], [race], [caste], [spell, group_spell])
	var options := rules.combat_flow.character_item_spell_options(state, content, character.id)
	assert_true(options.any(func(option: CombatItemOptionView) -> bool: return option.item_instance_id == instance.id and option.target_id == monster.id), "combat request options expose a legal charged item and exact target")
	assert_true(options.any(func(option: CombatItemOptionView) -> bool: return option.item_instance_id == group_instance.id and option.target_mode == &"automatic" and option.target_name == "All Enemies"), "combat request options expose source-backed automatic group targeting without inventing an actor selection")
	var request := RealmzRuntimeApi.new(content, state, ScriptedRng.new([]), ScenarioActionState.new())._combat_request("request.item-use")
	assert_true(request.payload.get("actions", []).has("use_item"), "the scenario host advertises item use only when a source-probed option exists")
	assert_true(request.payload.get("itemCasts", []).any(func(option: Dictionary) -> bool: return option.get("itemInstanceId") == instance.id and option.get("targetId") == monster.id and option.get("power") == 1), "the scenario interaction carries exact item, spell-power, and target identities")
	var host_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	var host_api := RealmzRuntimeApi.new(content, host_state, ScriptedRng.new([0, 0, 100]), ScenarioActionState.new())
	var host_result := host_api._resume_battle({"kind": "classic-combat", "battleId": state.combat.battle_id}, InteractionResponse.new("request.item-use", InteractionRequest.COMBAT, {"actorId": character.id, "action": "use_item", "targetId": monster.id, "itemInstanceId": instance.id}), "request.item-use")
	assert_equal(host_result.state, ScenarioRuntimeOperationResult.State.WAITING, "a typed combat item response returns to the ordinary battle interaction")
	assert_equal([host_state.combat.monster_by_id(monster.id).current_health, host_state.party.character_by_id(character.id).inventory()[0].charges], [7, 1], "the scenario host commits the same exact target and item instance carried by its request")
	var host_state_before_invalid := host_state.to_data()
	var invalid_host_result := host_api._resume_battle({"kind": "classic-combat", "battleId": state.combat.battle_id}, InteractionResponse.new("request.item-use", InteractionRequest.COMBAT, {"actorId": character.id, "action": "use_item", "targetId": monster.id}), "request.item-use")
	assert_equal(invalid_host_result.state, ScenarioRuntimeOperationResult.State.FAILED, "a malformed combat item response is rejected explicitly")
	assert_equal(host_state.to_data(), host_state_before_invalid, "a rejected combat item response cannot consume a second charge or mutate battle state")
	var spell_points_before := character.spell_points
	var used := rules.combat_flow.use_spell_item(state, content, character.id, monster.id, instance.id, ScriptedRng.new([0, 0, 100]))
	assert_true(used.ok, "active character can commit a source-backed combat spell item")
	assert_equal([monster.current_health, instance.charges, character.spell_points], [7, 1, spell_points_before], "combat item applies damage, spends one charge, and never spends spell points")
	assert_equal([character.movement, character.attacks_remaining], [0, 3], "successful combat item use pays Castle's twelve movement and two half-attack units without forcing an otherwise legal turn to end")
	assert_true(used.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 649), "combat item plays its source item sound")
	assert_true(used.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("source") == "classic-item" and event.payload.get("itemInstanceId") == instance.id), "combat spell result retains item provenance")
	var group_state := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	group_state.combat.active_turn = null
	group_state.party.character_by_id(character.id).movement = 12
	group_state.party.character_by_id(character.id).attacks_remaining = 2
	var group_used := rules.combat_flow.use_spell_item(group_state, content, character.id, "", group_instance.id, ScriptedRng.new([0, 0, 100]))
	assert_true(group_used.ok, "a fixed-power item can use Castle's automatic hostile-group target form")
	assert_equal(group_state.combat.monster_by_id(monster.id).current_health, 5, "automatic hostile-group item use applies once to each matching live combatant")
	instance.charges = 0
	var rng := ScriptedRng.new([])
	var depleted := rules.combat_flow.use_spell_item(state, content, character.id, monster.id, instance.id, rng)
	assert_equal(depleted.error_code, &"item_has_no_charges", "depleted combat item is rejected explicitly")
	assert_equal(rng.snapshot().draw_count, 0, "depleted combat item consumes no randomness")


func _test_tactical_adjacency_movement_and_restore() -> void:
	var rules := RealmzRules.new()
	var character := _character("character.tactical")
	var definition := _monster_definition("monster.tactical", [MonsterAttackDefinition.new(1, 1)])
	var monster := MonsterState.new("monster.tactical.instance", definition.id, definition.name, 10, 10, 1)
	var state := _state(character, monster, "battle.tactical")
	var content := _content([definition])
	var battlefield := state.combat.battlefield
	assert_true(rules.battlefield.are_adjacent(battlefield, character.id, monster.id), "one-cell hostile footprints are Classic melee adjacent in all eight directions")
	battlefield.move_actor(monster.id, Vector2i(50, 45))
	assert_false(rules.battlefield.are_adjacent(battlefield, character.id, monster.id), "a one-cell gap is outside Castle's footprint scan")
	var no_draws := ScriptedRng.new([])
	var rejected := rules.combat_flow.submit_action(state, content, character.id, &"attack", monster.id, no_draws)
	assert_false(rejected.ok, "melee cannot cross an unoccupied battlefield cell")
	assert_equal(rejected.error_code, &"combat_target_not_adjacent", "nonadjacent melee has a stable failure identity")
	assert_equal(no_draws.snapshot().draw_count, 0, "rejected nonadjacent melee consumes no combat randomness")
	assert_equal(state.combat.active_turn, null, "rejected melee does not initialize mutable turn state")
	var resources_before_invalid_move := [character.attacks_remaining, character.movement]
	var invalid_move := rules.combat_flow.move_character(state, content, character.id, Vector2i(48, 45), ScriptedRng.new([]))
	assert_false(invalid_move.ok, "a nonadjacent tactical step is rejected")
	assert_equal(state.combat.active_turn, null, "rejected movement does not initialize mutable turn state")
	assert_equal([character.attacks_remaining, character.movement], resources_before_invalid_move, "rejected movement preserves combat resources")

	var moved := rules.combat_flow.move_character(state, content, character.id, Vector2i(46, 45), ScriptedRng.new([]))
	assert_true(moved.ok, "a reaction-free cardinal battlefield step commits")
	assert_equal([battlefield.character_position(character.id), character.movement], [Vector2i(46, 45), 11], "Castle cardinal movement spends the destination tile base plus one changed axis")
	assert_true(moved.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("cost") == 1), "movement publishes its exact committed cost")
	var free_view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow)
	assert_true(free_view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.enabled), "the detached view exposes reaction-free movement before any hostile perimeter is involved")
	battlefield.move_actor(monster.id, Vector2i(47, 45))
	assert_true(rules.battlefield.are_adjacent(battlefield, character.id, monster.id), "explicit fixture placement establishes diagonal melee adjacency")
	var beside_enemy := rules.combat_flow.move_character(state, content, character.id, Vector2i(46, 44), ScriptedRng.new([]))
	assert_true(beside_enemy.ok, "movement beside a non-guarding enemy commits without fabricating a reaction")
	var withdrawal := rules.combat_flow.move_character(state, content, character.id, Vector2i(45, 44), ScriptedRng.new([0, 0, 0, 0]))
	assert_true(withdrawal.ok, "movement that leaves an adjacent enemy resolves Castle's withdrawal attack")
	assert_true(withdrawal.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("action") == "withdrawal" and event.payload.get("behind") == true), "withdrawal emits the source-owned plus-twenty reaction identity")
	assert_equal(battlefield.character_position(character.id), Vector2i(45, 44), "a surviving withdrawal commits the validated destination")

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-turn tactical position survives the central save aggregate")
	assert_equal(restored.combat.battlefield.character_position(character.id), Vector2i(45, 44), "restore retains the exact committed battlefield coordinate")
	assert_equal(restored.party.character_by_id(character.id).movement, 9, "restore retains remaining tactical movement")
	var view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow)
	assert_equal(view.targets.map(func(target: MonsterView) -> String: return target.id), [], "the detached view excludes a hostile left outside the melee perimeter")
	assert_equal(view.movement_options.size(), 8, "the detached view exposes all eight source-backed step probes")
	assert_true(view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.enabled), "the detached view advertises legal steps now that reactions are session-owned")

	var large_field := _blank_battlefield()
	large_field.place_character("character.large-target", Vector2i(40, 40))
	large_field.place_monster("monster.large", Vector2i(42, 41), 3)
	assert_true(rules.battlefield.are_adjacent(large_field, "character.large-target", "monster.large"), "adjacency measures the complete two-by-two monster footprint rather than its anchor")
	large_field.remove_monster("monster.large")
	large_field.place_monster("monster.large", Vector2i(43, 42), 3)
	assert_false(rules.battlefield.are_adjacent(large_field, "character.large-target", "monster.large"), "large footprints still require a one-cell Classic neighborhood")
	var cost_tiles: Array[BattleTerrainTileDefinition] = []
	for tile_id: int in 401:
		cost_tiles.append(BattleTerrainTileDefinition.new(tile_id, 0, 12 if tile_id == 3 else 8 if tile_id == 2 else 0, 0, false, 0, false, false, false, 0, [[tile_id, tile_id, tile_id], [tile_id, tile_id, tile_id], [tile_id, tile_id, tile_id]]))
	var cost_terrain := BattleTerrainSetDefinition.new("terrain.cost", 1, 1, cost_tiles)
	var cost_field := _blank_battlefield()
	cost_field.place_character("character.cost", Vector2i(30, 30))
	cost_field.set_terrain(Vector2i(31, 29), 2)
	var diagonal_probe := rules.battlefield.probe_step(cost_field, cost_terrain, "character.cost", Vector2i(1, -1), 12)
	assert_true(diagonal_probe.allowed, "an open diagonal destination passes the shared tactical query")
	assert_equal(diagonal_probe.movement_cost, 5, "Castle movement charges terrain time divided by two minus one plus both changed axes")
	cost_field.place_monster("monster.cost-large", Vector2i(35, 35), 3)
	cost_field.set_terrain(Vector2i(36, 35), 2)
	cost_field.set_terrain(Vector2i(35, 34), 3)
	var large_probe := rules.battlefield.probe_step(cost_field, cost_terrain, "monster.cost-large", Vector2i(1, 0), 12)
	assert_equal(large_probe.movement_cost, 6, "a multi-cell step uses the maximum destination-footprint terrain cost rather than Remake's minimum")

	var distant_character := _character("character.distant-monster")
	distant_character.current_health = 20
	distant_character.maximum_health = 20
	var distant_monster := MonsterState.new("monster.distant.instance", definition.id, definition.name, 10, 10, 1)
	var distant_state := _state(distant_character, distant_monster, "battle.distant")
	distant_state.combat.battlefield.move_actor(distant_monster.id, Vector2i(50, 50))
	definition.movement_max = 12
	var distant_values: Array[int] = []
	distant_values.resize(40)
	distant_values.fill(0)
	var advanced := rules.combat_flow.submit_action(distant_state, content, distant_character.id, &"finish", "", ScriptedRng.new(distant_values))
	assert_true(advanced.ok, "a nonadjacent monster activation follows its source-backed tactical path")
	assert_true(advanced.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("actorId") == distant_monster.id), "monster movement is committed as explicit battlefield events")
	assert_true(distant_character.current_health < 20, "the monster resolves melee only after reaching an adjacent footprint")
	assert_true(rules.battlefield.are_adjacent(distant_state.combat.battlefield, distant_character.id, distant_monster.id), "automatic movement ends in source-legal melee adjacency")


func _test_guard_and_withdrawal_reactions() -> void:
	var rules := RealmzRules.new()
	var definition := _monster_definition("monster.reaction", [MonsterAttackDefinition.new(1, 1)])
	definition.hit_dice = 20
	var character := _character("character.reaction")
	character.current_health = 30
	character.maximum_health = 30
	var monster := MonsterState.new("monster.reaction.instance", definition.id, definition.name, 30, 30, 20)
	var state := _state(character, monster, "battle.reaction")
	state.combat.set_guarding(monster.id, true)
	var reaction_values: Array[int] = []
	reaction_values.resize(8)
	reaction_values.fill(0)
	var moved := rules.combat_flow.move_character(state, _content([definition]), character.id, Vector2i(44, 45), ScriptedRng.new(reaction_values))
	assert_true(moved.ok, "a guarded withdrawal resolves through the deterministic movement boundary")
	var attacks := moved.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("reaction") == true)
	assert_equal(attacks.map(func(event: DomainEvent) -> String: return String(event.payload.get("action"))), ["guard", "withdrawal"], "Castle lets one guarding enemy strike before movement and again when the mover leaves its perimeter")
	assert_equal(attacks.map(func(event: DomainEvent) -> bool: return bool(event.payload.get("behind"))), [false, true], "only the withdrawal attack receives Castle's temporary plus-twenty modifier")
	assert_equal([character.current_health, state.combat.battlefield.character_position(character.id), state.combat.is_guarding(monster.id)], [28, Vector2i(44, 45), false], "both one-point reactions commit before the surviving mover reaches its destination and consume guard state")

	var ordered_character := _character("character.ordered-reactions")
	var first_monster := MonsterState.new("monster.z-first", definition.id, definition.name, 30, 30, 20)
	var second_monster := MonsterState.new("monster.a-second", definition.id, definition.name, 30, 30, 20)
	var ordered_field := _blank_battlefield()
	ordered_field.place_character(ordered_character.id, Vector2i(45, 45))
	ordered_field.place_monster(first_monster.id, Vector2i(46, 45), 0)
	ordered_field.place_monster(second_monster.id, Vector2i(45, 46), 0)
	var ordered_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [ordered_character]), RealmzClock.new())
	ordered_state.combat = CombatState.new("battle.ordered-reactions", [first_monster, second_monster], 0, ordered_field)
	ordered_state.combat.set_turn_order([ordered_character.id, first_monster.id, second_monster.id])
	ordered_state.combat.set_guarding(first_monster.id, true)
	ordered_state.combat.set_guarding(second_monster.id, true)
	var ordered_values: Array[int] = []
	ordered_values.resize(12)
	ordered_values.fill(0)
	var ordered_move := rules.combat_flow.move_character(ordered_state, _content([definition]), ordered_character.id, Vector2i(44, 45), ScriptedRng.new(ordered_values))
	var ordered_attacks := ordered_move.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("reaction") == true)
	assert_equal(ordered_attacks.map(func(event: DomainEvent) -> String: return String(event.payload.get("actorId"))), [first_monster.id, second_monster.id, first_monster.id], "guard and withdrawal queues use Castle combat-slot order rather than lexical stable-ID order")

	var charm_definition := _monster_definition("monster.reaction-charm", [MonsterAttackDefinition.new(1, 1, 0, 10)])
	var charmed_mover := _character("character.reaction-charmed-mover")
	charmed_mover.set_save_value_raw(0, 0)
	var charming_guard := MonsterState.new("monster.reaction-charming-guard", charm_definition.id, charm_definition.name, 30, 30, 20)
	var original_enemy := MonsterState.new("monster.reaction-original-enemy", charm_definition.id, charm_definition.name, 30, 30, 20)
	var charm_field := _blank_battlefield()
	charm_field.place_character(charmed_mover.id, Vector2i(45, 45))
	charm_field.place_monster(charming_guard.id, Vector2i(46, 45), 0)
	charm_field.place_monster(original_enemy.id, Vector2i(46, 46), 0)
	var charm_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [charmed_mover]), RealmzClock.new())
	charm_state.combat = CombatState.new("battle.reaction-charm", [charming_guard, original_enemy], 0, charm_field)
	charm_state.combat.set_turn_order([charmed_mover.id, charming_guard.id, original_enemy.id])
	charm_state.combat.set_guarding(charming_guard.id, true)
	var charm_values: Array[int] = []
	charm_values.resize(32)
	charm_values.fill(0)
	var charm_move := rules.combat_flow.move_character(charm_state, _content([charm_definition]), charmed_mover.id, Vector2i(44, 45), ScriptedRng.new(charm_values))
	assert_true(charmed_mover.traitor, "the first Guard reaction can change the mover's allegiance before withdrawal")
	assert_true(charm_move.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == original_enemy.id and event.payload.get("action") == "withdrawal"), "withdrawal uses the fixed original hostile perimeter even after an earlier Guard changes allegiance")

	var moving_target := _character("character.monster-move-guard")
	definition.movement_max = 12
	var moving_monster := MonsterState.new("monster.monster-move-guard.instance", definition.id, definition.name, 100, 100, 20)
	var moving_state := _state(moving_target, moving_monster, "battle.monster-move-guard")
	moving_state.combat.battlefield.move_actor(moving_monster.id, Vector2i(47, 45))
	moving_state.combat.turn_index = 1
	moving_state.combat.set_guarding(moving_target.id, true)
	var moving_events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(moving_state, _content([definition]), RealmzRng.new(73), moving_events)
	var moved_index := moving_events.find_custom(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("actorId") == moving_monster.id)
	var guard_index := moving_events.find_custom(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == moving_target.id and event.payload.get("action") == "guard")
	var own_attack_index := moving_events.find_custom(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == moving_monster.id and event.payload.get("action") == "advance")
	assert_true(moved_index >= 0 and guard_index > moved_index and own_attack_index > guard_index, "a party guard reacts after automatic movement reaches contact and before the active monster attacks")
	assert_false(moving_state.combat.is_guarding(moving_target.id), "the automatic contact reaction consumes the party guard")
	assert_false(moving_state.combat.is_guarding(moving_monster.id), "the active monster clears its freshly initialized guard when it makes a physical attack")


func _test_character_and_monster_retreat() -> void:
	var rules := RealmzRules.new()
	var definition := _monster_definition("monster.retreat", [MonsterAttackDefinition.new(1, 1)])
	definition.movement_max = 1
	var first := _character("character.retreat-first")
	var second := _character("character.retreat-second")
	var monster := MonsterState.new("monster.retreat.instance", definition.id, definition.name, 30, 30, 1)
	var battlefield := _blank_battlefield()
	battlefield.place_character(first.id, Vector2i(45, 45))
	battlefield.place_character(second.id, Vector2i(44, 45))
	battlefield.place_monster(monster.id, Vector2i(55, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [first, second]), RealmzClock.new())
	state.combat = CombatState.new("battle.character-retreat", [monster], 0, battlefield)
	state.combat.set_turn_order([first.id, second.id, monster.id])
	var content := _content([definition])

	var exact_ten: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), first.id)
	assert_true(exact_ten.allowed, "Castle allows explicit Escape at an integer-truncated enemy range of exactly ten")
	assert_equal(exact_ten.nearest_enemy_range, 10, "the retreat probe exposes Castle's exact nearest-enemy range")
	battlefield.move_actor(monster.id, Vector2i(54, 45))
	var too_close: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), first.id)
	assert_false(too_close.allowed, "explicit Escape is blocked below Castle's ten-cell threshold")
	assert_equal(too_close.reason, &"enemy_too_close", "close-enemy rejection has a stable typed reason")
	battlefield.move_actor(monster.id, Vector2i(55, 45))
	for condition: int in [ConditionRules.HELPLESS, ConditionRules.CONFUSED, ConditionRules.TANGLED, ConditionRules.SLOW]:
		first.conditions.set_value(condition, 1)
		var blocked: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), first.id)
		assert_equal([blocked.allowed, blocked.reason], [false, &"retreat_condition_blocked"], "Castle's explicit Escape condition gate remains source-owned")
		first.conditions.set_value(condition, 0)
	first.traitor = true
	assert_false(rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), first.id).allowed, "a traitor cannot use the party Escape command")
	first.traitor = false

	var escaped := rules.combat_flow.retreat_character(state, content, first.id, &"explicit", Vector2i(-100_000, -100_000), ScriptedRng.new([]))
	assert_true(escaped.ok and not escaped.completed, "one character can leave while another loyal party member remains in battle")
	assert_equal([battlefield.has_actor(first.id), battlefield.has_actor(second.id), first.current_health, first.prestige_penalty], [false, true, 30, 200], "Escape removes only the active character and applies Castle's exact prestige penalty")
	assert_equal(state.combat.active_actor_id(), second.id, "the battle continues at the next loyal character after a partial Escape")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a partially escaped party survives the central save aggregate")
	assert_equal([restored.combat.battlefield.has_actor(first.id), restored.party.character_by_id(first.id).prestige_penalty], [false, 200], "restore preserves the escaped identity and exact prestige penalty")
	assert_true(restored.combat.has_character_retreated(first.id), "restore preserves the explicit escaped-character identity rather than accepting arbitrary missing actors")
	var corrupt_retreat := state.to_data()
	corrupt_retreat["combat"]["retreatedCharacterIds"].append("character.not-in-party")
	corrupt_retreat["combat"]["turnOrder"].append("character.not-in-party")
	assert_equal(GameState.from_data(corrupt_retreat), null, "restore rejects an escaped identity that is not owned by the party")
	monster.conditions.set_value(ConditionRules.HELPLESS, 1)
	var wrapped := rules.combat_flow.submit_action(state, content, second.id, &"finish", "", ScriptedRng.new([]))
	assert_true(wrapped.ok and state.combat.active_actor_id() == second.id, "initiative skips an escaped living character when the round wraps")
	monster.conditions.set_value(ConditionRules.HELPLESS, 0)

	var session_character := _character("character.retreat-session")
	var session_monster := MonsterState.new("monster.retreat-session", definition.id, definition.name, 30, 30, 1)
	var session_state := _state(session_character, session_monster, "battle.retreat-session")
	session_state.combat.battlefield.move_actor(session_monster.id, Vector2i(55, 45))
	session_state.party_setup_completed = true
	var session := GameSession.new()
	assert_equal(session.start(content, 77).state, SessionStep.State.COMPLETED, "retreat confirmation fixture starts a validated session")
	session._state = session_state
	session._runtime_api = RealmzRuntimeApi.new(content, session_state, session._rng, session._scenario_action_state, session._rules)
	var confirmation := session.submit_intent(PlayerIntent.combat_action(&"retreat", session_character.id))
	assert_equal([confirmation.state, confirmation.interaction.kind, confirmation.interaction.payload.get("yesLabel"), confirmation.interaction.payload.get("noLabel")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO, "Embrace Cowardice", "Stay and Fight"], "explicit Escape yields Castle's typed confirmation without mutating combat")
	assert_true(session_state.combat.battlefield.has_actor(session_character.id), "the character remains in battle while confirmation is pending")
	var confirmation_save := SaveEnvelope.from_data(session.snapshot().to_data())
	assert_not_null(confirmation_save, "the explicit Escape confirmation is a committed central save boundary")
	var resumed_session := GameSession.new()
	assert_equal(resumed_session.restore(content, confirmation_save).state, SessionStep.State.COMPLETED, "the pending Escape confirmation restores transactionally")
	var accepted := resumed_session.respond(InteractionResponse.yes_no(resumed_session._session_interaction, true))
	assert_true(accepted.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_retreated" and event.payload.get("actorId") == session_character.id), "accepting the restored confirmation commits the same per-character Escape")
	assert_equal([resumed_session._state.last_battle_outcome, resumed_session._state.party.character_by_id(session_character.id).prestige_penalty], [&"retreated", 200], "restored confirmation resolves the exact battle outcome and penalty once")

	var forced_field := _blank_battlefield()
	forced_field.place_character(first.id, Vector2i(0, 45))
	forced_field.place_monster(monster.id, Vector2i(20, 45), 0)
	var forced_combat := CombatState.new("battle.edge-retreat", [monster], 0, forced_field)
	forced_combat.set_turn_order([first.id, monster.id])
	first.conditions.set_value(ConditionRules.SLOW, 1)
	var forced: Variant = rules.combat_flow.probe_edge_retreat(forced_combat, first.id, Vector2i(1, 45))
	assert_true(forced.allowed and forced.forced, "the outermost battlefield band forces movement Escape without the explicit condition gate")
	first.conditions.set_value(ConditionRules.SLOW, 0)
	forced_field.move_actor(first.id, Vector2i(2, 45))
	var prompted: Variant = rules.combat_flow.probe_edge_retreat(forced_combat, first.id, Vector2i(1, 45))
	assert_true(prompted.allowed and not prompted.forced, "entering Castle's edge band from the interior requires confirmation")

	var withdrawing_character := _character("character.retreat-guard")
	var withdrawing_monster := MonsterState.new("monster.retreat-withdrawal", definition.id, definition.name, 30, 30, 1)
	withdrawing_monster.target_id = withdrawing_character.id
	withdrawing_monster.conditions.set_value(ConditionRules.RUNS_AWAY, 1)
	var withdrawing_state := _state(withdrawing_character, withdrawing_monster, "battle.monster-retreat-withdrawal")
	withdrawing_state.combat.turn_index = 1
	withdrawing_state.combat.set_guarding(withdrawing_character.id, true)
	var withdrawal_events: Array[DomainEvent] = []
	var withdrawal_rolls: Array[int] = []
	withdrawal_rolls.resize(20)
	withdrawal_rolls.fill(0)
	rules.combat_flow._process_monster_turns(withdrawing_state, content, ScriptedRng.new(withdrawal_rolls), withdrawal_events)
	assert_true(withdrawal_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == withdrawing_character.id and event.payload.get("action") == "withdrawal" and event.payload.get("behind") == true), "a routed monster receives Castle's withdrawal attack before its committed step")
	assert_true(withdrawal_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("actorId") == withdrawing_monster.id and event.payload.get("automatic") == true), "routed-monster movement is identified as an automatic simulation action")
	assert_equal(withdrawing_state.combat.battlefield.monster_position(withdrawing_monster.id), Vector2i(47, 45), "the routed monster moves away from its retained target")

	var edge_character := _character("character.retreat-edge-target")
	var edge_monster := MonsterState.new("monster.retreat-edge", definition.id, definition.name, 30, 30, 1)
	edge_monster.target_id = edge_character.id
	edge_monster.conditions.set_value(ConditionRules.RUNS_AWAY, 1)
	var edge_state := _state(edge_character, edge_monster, "battle.monster-retreat-edge")
	edge_state.combat.battlefield.move_actor(edge_character.id, Vector2i(10, 45))
	edge_state.combat.battlefield.move_actor(edge_monster.id, Vector2i(2, 45))
	edge_state.combat.turn_index = 1
	var edge_events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(edge_state, content, ScriptedRng.new([]), edge_events)
	assert_true(edge_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_retreated" and event.payload.get("actorId") == edge_monster.id), "a routed hostile exits after its committed step enters Castle's edge band")
	assert_equal([edge_monster.current_health, edge_state.combat.battlefield.has_actor(edge_monster.id), edge_state.combat.outcome], [0, false, &"victory"], "hostile edge flight removes the monster and resolves the battle without a death macro")

	var unresolved_character := _character("character.retreat-unresolved-target")
	var unresolved_monster := MonsterState.new("monster.retreat-unresolved", definition.id, definition.name, 30, 30, 1)
	unresolved_monster.conditions.set_value(ConditionRules.RUNS_AWAY, 1)
	var unresolved_state := _state(unresolved_character, unresolved_monster, "battle.monster-retreat-unresolved")
	unresolved_state.combat.turn_index = 1
	var unresolved_events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(unresolved_state, content, ScriptedRng.new([]), unresolved_events)
	assert_true(unresolved_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("reason") == "retreat-target-unresolved"), "Castle's unsafe pos[-1] routed-monster branch remains explicit instead of selecting an invented target")
	assert_equal(unresolved_state.combat.battlefield.monster_position(unresolved_monster.id), Vector2i(46, 45), "the unresolved no-target branch leaves battlefield state unchanged")

	var mandatory_definition := _monster_definition("monster.retreat-mandatory-ally", [])
	mandatory_definition.movement_max = 1
	mandatory_definition.can_summon = -1
	var mandatory_character := _character("character.retreat-mandatory-observer")
	var mandatory_ally := MonsterState.new("monster.retreat-mandatory-ally", mandatory_definition.id, mandatory_definition.name, 30, 30, 1, 1, 0, 0, 0, false)
	var mandatory_enemy := MonsterState.new("monster.retreat-mandatory-enemy", definition.id, definition.name, 30, 30, 1)
	mandatory_ally.target_id = mandatory_enemy.id
	mandatory_ally.conditions.set_value(ConditionRules.RUNS_AWAY, 1)
	var mandatory_field := _blank_battlefield()
	mandatory_field.place_character(mandatory_character.id, Vector2i(40, 40))
	mandatory_field.place_monster(mandatory_ally.id, Vector2i(2, 45), 0)
	mandatory_field.place_monster(mandatory_enemy.id, Vector2i(10, 45), 0)
	var mandatory_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [mandatory_character]), RealmzClock.new())
	mandatory_state.combat = CombatState.new("battle.monster-retreat-mandatory", [mandatory_ally, mandatory_enemy], 0, mandatory_field)
	mandatory_state.combat.set_turn_order([mandatory_ally.id, mandatory_character.id, mandatory_enemy.id])
	var mandatory_events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(mandatory_state, _content([mandatory_definition, definition]), ScriptedRng.new([]), mandatory_events)
	assert_true(mandatory_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("reason") == "mandatory-ally-edge-retreat-unresolved"), "Castle's ineffective post-commit mandatory-ally reversal remains explicitly unresolved")
	assert_equal([mandatory_ally.current_health, mandatory_field.monster_position(mandatory_ally.id)], [30, Vector2i(1, 45)], "the mandatory ally stops alive at Castle's observed committed edge boundary")

func _test_guard_followups() -> void:
	var rules := RealmzRules.new()
	var definition := _monster_definition("monster.reaction-followup", [MonsterAttackDefinition.new(1, 1)])
	definition.hit_dice = 20
	var invisible_character := _character("character.invisible-withdrawal")
	invisible_character.conditions.set_value(ConditionRules.INVISIBLE, 1)
	var invisible_monster := MonsterState.new("monster.invisible-withdrawal.instance", definition.id, definition.name, 30, 30, 20)
	var invisible_state := _state(invisible_character, invisible_monster, "battle.invisible-withdrawal")
	var invisible_move := rules.combat_flow.move_character(invisible_state, _content([definition]), invisible_character.id, Vector2i(44, 45), ScriptedRng.new([]))
	assert_true(invisible_move.ok, "an invisible mover can leave a hostile perimeter")
	assert_false(invisible_move.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved"), "Castle suppresses withdrawal attacks, but not guarding attacks, for an invisible mover")

	var helpless_character := _character("character.helpless-guard")
	var helpless_monster := MonsterState.new("monster.helpless-guard.instance", definition.id, definition.name, 30, 30, 20)
	helpless_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless_state := _state(helpless_character, helpless_monster, "battle.helpless-guard")
	helpless_state.combat.set_guarding(helpless_monster.id, true)
	var helpless_move := rules.combat_flow.move_character(helpless_state, _content([definition]), helpless_character.id, Vector2i(45, 44), ScriptedRng.new([]))
	assert_true(helpless_move.ok, "movement beside a helpless guard still commits")
	assert_true(helpless_state.combat.is_guarding(helpless_monster.id), "Castle skips a helpless guard without consuming its guard flag")

	var guard_character := _character("character.guard-command")
	var passive_monster := MonsterState.new("monster.guard-command.instance", definition.id, definition.name, 30, 30, 20)
	passive_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var guard_state := _state(guard_character, passive_monster, "battle.guard-command")
	var guarded := rules.combat_flow.submit_action(guard_state, _content([definition]), guard_character.id, &"defend", "", ScriptedRng.new([0]))
	assert_true(guarded.ok and guard_state.combat.is_guarding(guard_character.id), "Defend establishes battle-owned guard state")
	assert_true(guarded.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_guarded" and event.payload.get("roll") == 1 and event.payload.get("soundId") == 10121), "Castle's one-based roll selects guard sound 10121 only below fifty")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(guard_state.to_data())))
	assert_not_null(restored, "guard state survives the central save aggregate")
	assert_true(restored.combat.is_guarding(guard_character.id), "restore retains the exact guarding actor identity")
	var finished := rules.combat_flow.submit_action(restored, _content([definition]), guard_character.id, &"finish", "", ScriptedRng.new([]))
	assert_true(finished.ok and not restored.combat.is_guarding(guard_character.id), "Finish clears guard and movement before ending the activation")
	assert_true(finished.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_turn_passed" and event.payload.get("action") == "finish"), "Finish publishes its source-owned command identity before the next round refreshes movement")

	var high_roll_character := _character("character.guard-high-roll")
	var high_roll_monster := MonsterState.new("monster.guard-high-roll.instance", definition.id, definition.name, 30, 30, 20)
	high_roll_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var high_roll_state := _state(high_roll_character, high_roll_monster, "battle.guard-high-roll")
	var high_guard := rules.combat_flow.submit_action(high_roll_state, _content([definition]), high_roll_character.id, &"defend", "", ScriptedRng.new([16_057]))
	assert_true(high_guard.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_guarded" and event.payload.get("roll") == 50 and event.payload.get("soundId") == 10123), "the exact source comparison makes roll fifty choose guard sound 10123")


func _test_guard_age_update_restore() -> void:
	var rules := RealmzRules.new()
	var age_ranges: Array[Vector2i] = [Vector2i(10, 19), Vector2i(20, 29), Vector2i(30, 39), Vector2i(40, 49), Vector2i(50, 59)]
	var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5:
		age_changes.append(PackedInt32Array(_ints(15)))
	var limits: Array[int] = []
	for _index: int in 6:
		limits.append_array([1, 30])
	var race := RaceDefinition.new("race.reaction-age", 31, "Reaction Age", _ints(8), _ints(8), _ints(6), limits, _ints(40), age_ranges, age_changes, 100)
	var caste := CasteDefinition.new("caste.reaction-age", 31, "Reaction Age", _ints(8), _ints(6), limits, _ints(40), Vector2i(1, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var character := _character("character.reaction-age")
	character.race_id = race.id
	character.caste_id = caste.id
	character.age_days = 19 * 365 + 364
	character.age_group = 1
	character.set_save_value_raw(7, 50)
	var definition := _monster_definition("monster.reaction-age", [MonsterAttackDefinition.new(1, 1, 0, 17)])
	definition.hit_dice = 1
	var monster := MonsterState.new("monster.reaction-age.instance", definition.id, definition.name, 30, 30, 1)
	var state := _state(character, monster, "battle.reaction-age")
	state.combat.set_guarding(monster.id, true)
	var content := _content([definition], [], [race], [caste])
	var rng := ScriptedRng.new([0, 0, 0, 0, 0, 32_767])
	var waiting := rules.combat_flow.move_character(state, content, character.id, Vector2i(45, 44), rng)
	assert_true(waiting.ok and waiting.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_age_changed"), "a guarding age attack reaches the typed age-update boundary before movement")
	assert_equal([character.current_health, state.combat.battlefield.character_position(character.id)], [30, Vector2i(45, 45)], "deferred physical damage and movement both wait behind the age acknowledgement")
	assert_not_null(state.combat.pending_reaction, "the battle owns the interrupted reaction cursor")
	assert_not_null(state.combat.pending_monster_attack, "the battle owns the deferred physical attack")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a guard reaction interrupted by aging survives whole-state restoration")
	if restored == null:
		return
	assert_equal([restored.combat.pending_reaction.mover_id, restored.combat.pending_reaction.next_attacker_index, restored.combat.pending_monster_attack.action], [character.id, 1, &"guard"], "restore resumes after the already-issued guard attack without replaying it")
	var restored_rng := RealmzRng.new()
	assert_true(restored_rng.restore(rng.snapshot()), "the reaction fixture restores its exact RNG boundary")
	var resumed := rules.combat_flow.continue_after_age_update(restored, content, restored_rng)
	assert_true(resumed.ok, "acknowledging the restored age update completes the pending reaction")
	assert_equal([restored.party.character_by_id(character.id).current_health, restored.combat.battlefield.character_position(character.id)], [29, Vector2i(45, 44)], "deferred damage commits once before the surviving mover reaches its destination")
	assert_equal([restored.combat.pending_reaction, restored.combat.pending_monster_attack], [null, null], "the completed reaction leaves no replayable continuation")
	assert_true(resumed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("reaction") == true and event.payload.get("action") == "guard"), "the resumed attack retains its guard identity for presentation")


func _test_guard_death_macro_revival_continuation() -> void:
	var rules := RealmzRules.new()
	var invalid_contact := CombatReactionState.new(CombatReactionState.MONSTER_CONTACT, "monster.invalid-contact", Vector2i(45, 45), Vector2i(45, 45), 0).to_data()
	invalid_contact["phase"] = "withdrawal"
	assert_equal(CombatReactionState.from_data(invalid_contact), null, "restore rejects a stationary monster-contact record with an impossible withdrawal phase")
	var first_guard := _character("character.revival-first-guard")
	var second_guard := _character("character.revival-second-guard")
	var definition := _monster_definition("monster.revival-mover", [MonsterAttackDefinition.new(1, 1)])
	definition.death_macro = 321
	var monster := MonsterState.new("monster.revival-mover.instance", definition.id, definition.name, 0, 30, 1)
	var battlefield := _blank_battlefield()
	battlefield.place_character(first_guard.id, Vector2i(44, 45))
	battlefield.place_character(second_guard.id, Vector2i(45, 44))
	battlefield.place_monster(monster.id, Vector2i(45, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [first_guard, second_guard]), RealmzClock.new())
	state.combat = CombatState.new("battle.revival-reaction", [monster], 0, battlefield)
	state.combat.set_turn_order([first_guard.id, second_guard.id, monster.id])
	state.combat.turn_index = 2
	state.combat.active_turn = CombatTurnState.new(monster.id)
	state.combat.active_turn.action = &"advance"
	state.combat.active_turn.movement_remaining = 0
	state.combat.set_guarding(first_guard.id, false)
	state.combat.set_guarding(second_guard.id, true)
	state.combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_CONTACT, monster.id, Vector2i(45, 45), Vector2i(45, 45), 0)
	state.combat.pending_reaction.set_phase(CombatReactionState.GUARD_AFTER, [first_guard.id, second_guard.id])
	state.combat.pending_reaction.take_next_attacker()
	state.combat.pending_reaction.mover_killed = true

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a death-macro interruption retains the defeated mover's footprint and exact reaction cursor")
	if restored == null:
		return
	# This is the state immediately after CODE 119 revives the reaction mover.
	var restored_monster := restored.combat.monster_by_id(monster.id)
	restored_monster.current_health = 30
	restored_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var resumed := rules.combat_flow.continue_after_monster_death_macro(restored, _content([definition]), ScriptedRng.new([0, 0, 0, 0, 0, 0, 0, 0]))
	assert_true(resumed.ok, "a death macro that revives the moving monster resumes its interrupted Guard cursor")
	assert_true(resumed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == second_guard.id and event.payload.get("action") == "guard"), "revival continues with the next source-ordered guard instead of discarding the pending reaction")
	assert_false(resumed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == first_guard.id and event.payload.get("action") == "guard"), "revival does not replay the guard that caused the death macro")


func _test_monster_los_targeting_and_movement() -> void:
	var rules := RealmzRules.new()
	var terrain_tiles: Array[BattleTerrainTileDefinition] = []
	for tile_id: int in 401:
		terrain_tiles.append(BattleTerrainTileDefinition.new(tile_id, 0, 0, 2 if tile_id == 2 else 0, false, 0, false, tile_id == 3, false, 0, [[tile_id, tile_id, tile_id], [tile_id, tile_id, tile_id], [tile_id, tile_id, tile_id]]))
	var terrain_set := BattleTerrainSetDefinition.new("terrain.monster-path", 1, 1, terrain_tiles)
	var battlefield := _blank_battlefield()
	battlefield.place_monster("monster.los", Vector2i(40, 40), 0)
	battlefield.place_character("character.los", Vector2i(50, 40))
	assert_true(rules.battlefield.has_line_of_sight(battlefield, terrain_set, "monster.los", "character.los"), "fixed 128-sample tactical LOS sees an unobstructed target")
	battlefield.set_terrain(Vector2i(48, 40), 3)
	assert_false(rules.battlefield.has_line_of_sight(battlefield, terrain_set, "monster.los", "character.los"), "FD-COMBAT-008 detects a blocker near the target independently of presentation delay")
	battlefield.set_terrain(Vector2i(48, 40), 1)
	var target_definition := _monster_definition("monster.los-target", [])
	var attacker := MonsterState.new("monster.los-attacker", target_definition.id, "LOS Attacker", 10, 10, 1)
	var ally_target := MonsterState.new("monster.los-ally", target_definition.id, "LOS Ally", 10, 10, 1, 1, 0, 0, 0, false)
	var target_character := _character("character.los-scan")
	var target_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [target_character]), RealmzClock.new())
	var target_field := _blank_battlefield()
	target_field.place_monster(attacker.id, Vector2i(40, 40), 0)
	target_field.place_monster(ally_target.id, Vector2i(40, 45), 0)
	target_field.place_character(target_character.id, Vector2i(50, 40))
	target_field.set_terrain(Vector2i(48, 40), 3)
	target_state.combat = CombatState.new("battle.los-scan", [attacker, ally_target], 0, target_field)
	target_state.combat.set_turn_order([attacker.id, ally_target.id, target_character.id])
	var fallback_rng := ScriptedRng.new([0])
	var fallback_target := rules.combat_flow._select_visible_monster_target(target_state, attacker, terrain_set, fallback_rng)
	assert_equal(fallback_target, ally_target.id, "an unseen random target switches to Castle's ascending combat-slot scan")
	assert_equal(fallback_rng.snapshot().draw_count, 1, "the deterministic fallback scan consumes no invented target draws")
	attacker.target_id = target_character.id
	assert_equal(rules.combat_flow._scan_visible_monster_target(target_state, attacker, terrain_set), ally_target.id, "an unseen retained target enters the ascending scan without a replacement random draw")
	var invalid_slot_rng := ScriptedRng.new([26811, 0])
	assert_equal(rules.combat_flow._select_visible_monster_target(target_state, attacker, terrain_set, invalid_slot_rng), ally_target.id, "invalid Classic gap slot nine rerolls before the LOS fallback scan")
	assert_equal(invalid_slot_rng.snapshot().draw_count, 2, "target-slot rejection preserves Castle's authored-slot draw order")

	battlefield.set_terrain(Vector2i(41, 40), 2)
	var shifted := rules.battlefield.probe_monster_step_toward(battlefield, terrain_set, "monster.los", Vector2i(50, 40), 10, ScriptedRng.new([0, 0, 0]))
	assert_true(shifted.allowed, "Castle's bounded shift retry can find an alternate monster step around a blocked direct path")
	assert_equal(shifted.destination, Vector2i(39, 41), "the retry preserves shift.c's exact randomized direction branch")
	battlefield.set_terrain(Vector2i(41, 40), 4)
	terrain_tiles[4].movement_time = 16
	var retained_cost_values: Array[int] = []
	retained_cost_values.resize(96)
	retained_cost_values.fill(0)
	var retained_cost := rules.battlefield.probe_monster_step_toward(battlefield, terrain_set, "monster.los", Vector2i(50, 40), 5, ScriptedRng.new(retained_cost_values))
	assert_false(retained_cost.allowed, "Castle retains an unaffordable direct terrain cost across shifted probes instead of finding a cheaper alternate step")
	assert_equal(retained_cost.movement_cost, 8, "the failed monster probe reports the source-retained maximum movement cost")
	battlefield.set_terrain(Vector2i(41, 40), 1)

	var character := _character("character.monster-path")
	character.current_health = 30
	character.maximum_health = 30
	var definition := _monster_definition("monster.path", [MonsterAttackDefinition.new(1, 1)])
	definition.movement_max = 12
	var monster := MonsterState.new("monster.path.instance", definition.id, definition.name, 20, 20, 1)
	var state := _state(character, monster, "battle.monster-path")
	state.combat.battlefield.move_actor(monster.id, Vector2i(50, 45))
	var values: Array[int] = []
	values.resize(40)
	values.fill(0)
	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"finish", "", ScriptedRng.new(values))
	var movement_events := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("actorId") == monster.id)
	assert_equal(movement_events.size(), 4, "a monster takes repeated legal steps until its footprint reaches adjacency")
	assert_equal(state.combat.battlefield.monster_position(monster.id), Vector2i(46, 45), "target-directed movement stops at the adjacent attack cell")
	assert_equal(monster.target_id, character.id, "Castle's selected monster target persists beyond the activation")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "persistent monster targeting survives the central save aggregate")
	assert_equal(restored.combat.monster_by_id(monster.id).target_id, character.id, "restore retains the exact persistent tactical target")
	var invalid_target_data := state.to_data()
	invalid_target_data["combat"]["monsters"][0]["targetId"] = "character.missing-target"
	assert_equal(GameState.from_data(JSON.parse_string(JSON.stringify(invalid_target_data))), null, "restore rejects a persistent monster target outside the complete combat aggregate")

	var tangled_character := _character("character.permanent-tangle")
	var tangled_monster := MonsterState.new("monster.permanent-tangle.instance", definition.id, definition.name, 20, 20, 1)
	tangled_monster.conditions.set_value(ConditionRules.TANGLED, -1)
	var tangled_state := _state(tangled_character, tangled_monster, "battle.permanent-tangle")
	tangled_state.combat.battlefield.move_actor(tangled_monster.id, Vector2i(50, 45))
	var tangled_result := rules.combat_flow.submit_action(tangled_state, _content([definition]), tangled_character.id, &"finish", "", ScriptedRng.new([0, 0]))
	assert_true(tangled_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("reason") == "permanent-tangle-movement-unresolved"), "Castle's apparent permanent-Tangle movement increase remains explicit instead of becoming gameplay")

	var helpless_character := _character("character.helpless-monster")
	var helpless_monster := MonsterState.new("monster.helpless.instance", definition.id, definition.name, 20, 20, 1)
	helpless_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless_state := _state(helpless_character, helpless_monster, "battle.helpless-monster")
	var helpless_rng := ScriptedRng.new([])
	var helpless_result := rules.combat_flow.submit_action(helpless_state, _content([definition]), helpless_character.id, &"finish", "", helpless_rng)
	assert_true(helpless_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action" and event.payload.get("action") == "incapacitated"), "Castle skips a helpless monster before its tactical decision")
	assert_equal(helpless_rng.snapshot().draw_count, 0, "an incapacitated monster consumes no AI or target randomness")

	var speedy_character := _character("character.speedy-monster")
	var speedy_monster := MonsterState.new("monster.speedy.instance", definition.id, definition.name, 20, 20, 1)
	speedy_monster.conditions.set_value(ConditionRules.SPEEDY, -1)
	var speedy_state := _state(speedy_character, speedy_monster, "battle.speedy-monster")
	var speedy_result := rules.combat_flow.submit_action(speedy_state, _content([definition]), speedy_character.id, &"finish", "", ScriptedRng.new([0, 0]))
	assert_true(speedy_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("reason") == "monster-speedy-cadence-unresolved"), "monster Speedy stays explicit until Castle's bonus-row overflow is adjudicated")


func _test_character_weapon_mode_toggle_and_restore() -> void:
	var rules := RealmzRules.new()
	var melee := ItemDefinition.new("item.mode-melee", 81, "Mode Blade")
	melee.item_type = 2
	melee.vs_small = 1
	var missile := ItemDefinition.new("item.mode-missile", 82, "Mode Bow")
	missile.item_type = 15
	var duplicate_missile := ItemDefinition.new("item.mode-missile-duplicate", 83, "Second Bow")
	duplicate_missile.item_type = 15
	var character := _character("character.weapon-mode")
	for entry: Dictionary in [
		{"definition": melee, "instanceId": "instance.mode-melee"},
		{"definition": missile, "instanceId": "instance.mode-missile"},
	]:
		var instance := rules.inventory.add_item(character, entry["definition"], entry["instanceId"], true)
		assert_not_null(instance, "weapon-mode fixture grants each equipped weapon")
		assert_true(rules.inventory.equip(character, entry["instanceId"], entry["definition"]), "weapon-mode fixture equips each Classic slot")
	var equipment := rules.inventory.combat_equipment(character, [melee, missile])
	assert_true(equipment.valid, "one melee and one missile slot form a valid Classic equipment projection")
	assert_equal([equipment.melee_weapon.id, equipment.missile_weapon.id], [melee.id, missile.id], "combat projection distinguishes the two weapon slots")

	var definition := _monster_definition("monster.mode-passive", [])
	var monster := MonsterState.new("monster.mode-passive.instance", definition.id, definition.name, 100, 100, 1)
	var state := _state(character, monster, "battle.weapon-mode")
	state.combat.set_character_weapon_mode(character.id, &"melee")
	rules.combat_flow._prepare_character_turn(state.combat, character)
	var resources_before := [character.attacks_remaining, character.movement]
	var content := _content([definition], [melee, missile])
	var switched := rules.combat_flow.submit_action(state, content, character.id, &"switch_weapon", "", RealmzRng.new(91))
	assert_true(switched.ok, "the active character can switch from melee to an equipped missile weapon")
	assert_equal(state.combat.character_weapon_mode(character.id), &"missile", "the battle owns the active missile mode")
	assert_equal([character.attacks_remaining, character.movement, state.combat.active_actor_id()], [resources_before[0], resources_before[1], character.id], "switching mode spends no attacks, movement, or turn")
	assert_true(switched.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_weapon_mode_changed" and event.payload.get("mode") == "missile"), "the committed mode change publishes typed presentation feedback")
	var combat_view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow)
	assert_equal(combat_view.weapon_mode, &"missile", "the detached combat view exposes the battle-owned mode")
	assert_equal(combat_view.legal_actions, [&"switch_weapon", &"finish", &"defend"], "the detached view cannot advertise melee attack or illegal close-range Escape while missile mode is active")
	assert_false(combat_view.ranged_attack_unavailable_reason.is_empty(), "the detached view carries the exact tactical ranged blocker")
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(94), ScenarioActionState.new())
	var request := api._combat_request("request.weapon-mode")
	assert_equal([request.payload.get("weaponMode"), request.payload.get("actions")], ["missile", ["switch_weapon", "finish", "defend"]], "the typed interaction preserves the same legal actions as the detached view")
	assert_equal([request.payload.get("retreat", {}).get("enabled"), request.payload.get("retreat", {}).get("nearestEnemyRange")], [false, 1], "the typed interaction explains the source-backed close-range Escape blocker")
	assert_equal(request.payload.get("weaponSwitch", {}).get("targetMode"), "melee", "the typed switch response names its source-owned destination mode")
	assert_false(String(request.payload.get("rangedAttack", {}).get("reason", "")).is_empty(), "the typed interaction explains why Fire is disabled")
	var blocked := rules.combat_flow.submit_action(state, content, character.id, &"attack", monster.id, RealmzRng.new(92))
	assert_false(blocked.ok, "missile mode cannot fall through to the melee resolver while tactical ranged state is unavailable")
	assert_equal(blocked.error_code, &"projectile_charge_unavailable", "an empty missile slot fails with the exact unavailable authored fact")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "the active weapon mode survives whole-state restoration")
	assert_equal(restored.combat.character_weapon_mode(character.id), &"missile", "restore preserves the exact battle-owned toggle")
	var returned := rules.combat_flow.submit_action(restored, content, character.id, &"switch_weapon", "", RealmzRng.new(93))
	assert_true(returned.ok, "missile mode can always return to hand-to-hand or the melee slot")
	assert_equal(restored.combat.character_weapon_mode(character.id), &"melee", "the second toggle restores melee mode")

	var duplicate_instance := rules.inventory.add_item(character, duplicate_missile, "instance.mode-missile-duplicate", true)
	assert_not_null(duplicate_instance, "duplicate-slot fixture grants its second missile item")
	assert_true(rules.inventory.equip(character, duplicate_instance.id, duplicate_missile), "the generic inventory state can expose an impossible duplicate slot for validation")
	var rejected := rules.inventory.combat_equipment(character, [melee, missile, duplicate_missile])
	assert_false(rejected.valid, "two equipped missile weapons fail instead of selecting one by inventory order")
	assert_equal(rejected.error_code, &"multiple_missile_weapons", "the duplicate Classic slot has a stable failure identity")
	var invalid_character := _character("character.invalid-weapon-slots")
	for entry: Dictionary in [
		{"definition": missile, "instanceId": "instance.invalid-missile-a"},
		{"definition": duplicate_missile, "instanceId": "instance.invalid-missile-b"},
	]:
		var invalid_instance := rules.inventory.add_item(invalid_character, entry["definition"], entry["instanceId"], true)
		assert_not_null(invalid_instance, "invalid battle fixture grants each duplicate missile weapon")
		assert_true(rules.inventory.equip(invalid_character, entry["instanceId"], entry["definition"]), "invalid battle fixture equips each duplicate Classic slot")
	var invalid_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [invalid_character]), RealmzClock.new())
	var invalid_state_before: Dictionary = invalid_state.to_data()
	var invalid_content := _content([definition], [melee, missile, duplicate_missile])
	var invalid_battle := BattleDefinition.new("battle.invalid-weapon-slots", 2, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, definition.id, false)])
	var no_draws: Array[int] = []
	var invalid_start := rules.combat_flow.start_battle(invalid_state, invalid_content, invalid_battle, ScriptedRng.new(no_draws))
	assert_false(invalid_start.ok, "battle setup rejects duplicate Classic weapon slots before consuming setup randomness")
	assert_equal(invalid_start.error_code, &"multiple_missile_weapons", "battle setup preserves the equipment validation error")
	assert_equal(invalid_state.combat, null, "rejected battle setup does not install partial combat state")
	assert_equal(invalid_state.to_data(), invalid_state_before, "rejected battle setup leaves the complete game state unchanged")

	var missile_only := _character("character.missile-only")
	var missile_only_instance := rules.inventory.add_item(missile_only, missile, "instance.missile-only", true)
	assert_not_null(missile_only_instance, "initial-mode fixture grants its missile weapon")
	assert_true(rules.inventory.equip(missile_only, missile_only_instance.id, missile), "initial-mode fixture equips its type-15 slot")
	var setup_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [missile_only]), RealmzClock.new())
	var battle := BattleDefinition.new("battle.initial-mode", 1, [BattleMonsterSlotDefinition.new(Vector2i.ZERO, definition.id, false)])
	var started := rules.combat_flow.start_battle(setup_state, content, battle, RealmzRng.new(95))
	assert_true(started.ok, "battle setup accepts a character whose only weapon is missile")
	assert_equal(setup_state.combat.character_weapon_mode(missile_only.id), &"missile", "battle setup selects missile only when the melee slot is empty")
	assert_not_null(setup_state.combat.battlefield, "battle setup installs the topology-derived battlefield in central combat state")
	var setup_monster := setup_state.combat.monsters()[0]
	assert_true(setup_state.combat.battlefield.character_position(missile_only.id).x >= 0, "the live battlefield owns the party position")
	assert_true(setup_state.combat.battlefield.monster_position(setup_monster.id).x >= 0, "the live battlefield replaces its temporary placement key with the stable monster instance ID")
	var setup_view := CombatView.new(setup_state.combat, setup_state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow)
	assert_not_null(setup_view.battlefield, "the detached combat view exposes generated battlefield state without presenting the mutable aggregate")
	assert_equal(setup_view.battlefield.monster_footprint(setup_monster.id), BattlefieldState.footprint_cells(setup_state.combat.battlefield.monster_position(setup_monster.id), setup_state.combat.battlefield.monster_size(setup_monster.id)), "presentation receives the exact session-owned Classic footprint")
	var legacy_combat_data := setup_state.combat.to_data()
	var restored_battlefield_combat := CombatState.from_data(JSON.parse_string(JSON.stringify(legacy_combat_data)))
	assert_not_null(restored_battlefield_combat, "battle terrain and actor placements survive combat-state serialization")
	assert_equal(restored_battlefield_combat.battlefield.to_data(), setup_state.combat.battlefield.to_data(), "restored combat retains the exact generated field and footprints")
	var mismatched_battlefield_save := setup_state.to_data()
	mismatched_battlefield_save["combat"]["battlefield"]["mapId"] = "map.other"
	assert_equal(GameState.from_data(mismatched_battlefield_save), null, "whole-state restore rejects a battlefield detached from the party's authoritative map")
	legacy_combat_data.erase("characterWeaponModes")
	var legacy_combat := CombatState.from_data(legacy_combat_data)
	assert_not_null(legacy_combat, "pre-toggle save-v3 combat state remains readable")
	assert_equal(legacy_combat.character_weapon_mode(missile_only.id), &"melee", "legacy combat state receives the safe melee default instead of inventing a missile selection")

	var blocked_state := GameState.new(PartyState.new("map.test", Vector2i(45, 45), [_character("character.blocked-placement")]), RealmzClock.new())
	var blocked_content := RealmzContent.new("campaign.blocked", "0".repeat(64), "blocked", "realmz-classic-1", "map.test", Vector2i(45, 45), _blocked_battle_world(), ScenarioDefinition.new([], []), [], [], [], [], [], [], [], [definition])
	var blocked_before := blocked_state.to_data()
	var blocked_rng := ScriptedRng.new([0, 0, 0])
	blocked_rng.draw(10, &"battle.test.prior")
	var blocked_rng_before := blocked_rng.snapshot().to_data()
	var blocked_start := rules.combat_flow.start_battle(blocked_state, blocked_content, battle, blocked_rng)
	assert_false(blocked_start.ok, "an impossible source-backed battlefield fails instead of hanging Castle's unbounded placement loop")
	assert_equal(blocked_start.error_code, &"character_placement_failed", "bounded placement failure has an explicit stable identity")
	assert_equal(blocked_state.to_data(), blocked_before, "failed battlefield placement leaves the complete game state unchanged")
	assert_equal(blocked_rng.snapshot().to_data(), blocked_rng_before, "failed battlefield placement restores the exact RNG boundary")
	assert_equal(blocked_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["battle.test.prior"], "RNG rollback removes only speculative battle setup draws")

	var collision_character := _character("character.identity-collision")
	var collision_ally := MonsterState.new("combat.monster.1", definition.id, definition.name, 10, 10, 1, 1, 0, 0, 0, false)
	var collision_state := GameState.new(PartyState.new("map.test", Vector2i(45, 45), [collision_character]), RealmzClock.new())
	collision_state.party.set_allies([collision_ally])
	var collision_before := collision_state.to_data()
	var collision_rng := RealmzRng.new(96)
	var collision_rng_before := collision_rng.snapshot().to_data()
	var collision_start := rules.combat_flow.start_battle(collision_state, content, battle, collision_rng)
	assert_false(collision_start.ok, "a late stable-identity collision fails before combat is committed")
	assert_equal(collision_start.error_code, &"invalid_battlefield_identity", "late setup failure retains its stable identity")
	assert_equal(collision_state.to_data(), collision_before, "late setup failure rolls back the allocated instance ID and leaves ally state untouched")
	assert_equal(collision_rng.snapshot().to_data(), collision_rng_before, "late setup failure rolls back every terrain, formation, and monster-construction draw")


func _test_monster_missile_does_not_impersonate_melee() -> void:
	var rules := RealmzRules.new()
	var character := _character("character.missile-target")
	character.current_health = 20
	character.maximum_health = 20
	var attacks: Array[MonsterAttackDefinition] = [MonsterAttackDefinition.new(4, 4)]
	var definition := _monster_definition("monster.missile-only", attacks)
	definition.missile_percent = 100
	var monster := MonsterState.new("monster.missile-only.instance", definition.id, definition.name, 20, 20, 1)
	var state := _state(character, monster, "battle.monster-missile")
	state.combat.battlefield.move_actor(monster.id, Vector2i(50, 50))
	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"finish", "", ScriptedRng.new([0, 0, 0, 0]))
	assert_true(result.ok, "an unavailable tactical missile decision returns a committed combat step")
	assert_equal(character.current_health, 20, "the missile branch no longer applies an ordinary melee attack row")
	assert_false(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == monster.id), "no melee-resolution event is mislabeled as a missile")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("action") == "missile" and String(event.payload.get("reason")).contains("slot 1")), "the disabled missile branch reports its exact missing native slot")
	assert_equal(state.combat.active_actor_id(), character.id, "an unavailable monster missile spends exactly that monster activation without skipping the next character turn")


func _test_source_backed_projectile_fire() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.projectile", 4101, "Test Arrow")
	spell.spell_class = 9
	spell.damage_type = 9
	spell.target_type = 1
	spell.range_min = 20
	spell.range_max = 0
	spell.damage_min = 4
	spell.damage_max = 4
	spell.fixed_target_count = 1
	var bow := ItemDefinition.new("item.projectile-bow", 104, "Test Bow")
	bow.item_type = 15
	bow.special_1 = -1
	bow.special_2 = spell.classic_id
	bow.initial_charges = 2
	bow.damage_bonus = 1
	var caste := CasteDefinition.new("caste.test", 1, "Projectile Caste", _ints(8), _ints(6), _ints(12), _ints(40), Vector2i(1, 1), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO)
	var character := _character("character.projectile")
	character.missile = 20
	var bow_instance := rules.inventory.add_item(character, bow, "instance.projectile-bow", true)
	assert_not_null(bow_instance, "projectile fixture grants the charged type-15 weapon")
	assert_true(rules.inventory.equip(character, bow_instance.id, bow), "projectile fixture equips the Classic missile slot")
	var definition := _monster_definition("monster.projectile-target", [])
	var monster := MonsterState.new("monster.projectile-target.instance", definition.id, definition.name, 5, 5, 1, 1)
	var state := _state(character, monster, "battle.character-projectile")
	state.combat.battlefield.move_actor(monster.id, Vector2i(50, 45))
	state.combat.set_character_weapon_mode(character.id, &"missile")
	var content := _content([definition], [bow], [], [caste], [spell])
	var view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow)
	assert_true(view.legal_actions.has(&"attack"), "a hostile monster in the source-backed 20-cell range exposes Fire")
	assert_equal(view.targets.map(func(target: MonsterView) -> String: return target.id), [monster.id], "the detached target list uses the same range and LOS query as execution")
	var result := rules.combat_flow.submit_action(state, content, character.id, &"attack", monster.id, ScriptedRng.new([0, 0, 0]))
	assert_true(result.ok, "a committed ordinary class-9 projectile resolves")
	assert_equal([bow_instance.charges, character.attacks_remaining, character.movement], [1, 1, 0], "manual fire spends one charge, two half-attacks, and twelve movement while preserving Castle's carried half-attack")
	assert_equal(monster.current_health, 0, "projectile damage includes the missile item's magic damage bonus")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_projectile_resolved" and event.payload.get("hitCount") == 1 and event.payload.get("damage") == 5), "projectile resolution publishes its source-backed hit and damage facts")

	var missile_item := ItemDefinition.new("item.monster-missile", 157, "Monster Crossbow")
	missile_item.item_type = 15
	missile_item.special_2 = spell.classic_id
	var melee_item := ItemDefinition.new("item.monster-melee", 81, "Monster Blade")
	melee_item.item_type = 2
	var monster_definition := MonsterDefinition.new("monster.projectile-shooter", 2, "Projectile Shooter", 1, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), [], [melee_item.id, missile_item.id, "", "", "", ""], [MonsterAttackDefinition.new(1, 1)])
	monster_definition.missile_percent = 100
	monster_definition.movement_max = 12
	var monster_shooter := MonsterState.new("monster.projectile-shooter.instance", monster_definition.id, monster_definition.name, 10, 10, 1)
	monster_shooter.weapon_id = melee_item.id
	monster_shooter.spell_points = 2
	spell.cost = 2
	var monster_target := _character("character.monster-projectile-target")
	monster_target.current_health = 20
	monster_target.maximum_health = 20
	monster_target.dodge = 0
	var monster_state := _state(monster_target, monster_shooter, "battle.monster-projectile")
	monster_state.combat.battlefield.move_actor(monster_shooter.id, Vector2i(50, 45))
	var monster_content := _content([monster_definition], [melee_item, missile_item], [], [], [spell])
	var monster_result := rules.combat_flow.submit_action(monster_state, monster_content, monster_target.id, &"finish", "", ScriptedRng.new([0, 5000, 0, 0, 0, 0]))
	assert_true(monster_result.ok, "a hostile monster fires from exact native item slot 1")
	assert_equal([monster_shooter.weapon_id, monster_target.current_health, monster_state.combat.is_guarding(monster_shooter.id)], [missile_item.id, 16, false], "monster fire equips slot 1, damages the character, and clears guard")
	assert_true(monster_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_projectile_resolved" and event.payload.get("source") == "classic-monster" and event.payload.get("rangePower") == 2 and event.payload.get("costPower") == 1), "monster fire retains initial range power while lowering only unaffordable cost power")
	assert_equal(monster_shooter.spell_points, 0, "monster fire spends the lowered affordable power cost")
	spell.range_min = 0
	var skipped_events: Array[DomainEvent] = []
	var skipped := rules.combat_flow._process_monster_projectile(monster_state, monster_content, monster_shooter, monster_definition, CombatTurnState.new(monster_shooter.id), ScriptedRng.new([0]), skipped_events)
	assert_equal(skipped, CombatFlow.MONSTER_ATTACK_FALLBACK, "an out-of-range missile resumes Castle's post-missile action decision")
	assert_true(skipped_events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_projectile_skipped" and event.payload.get("reason") == "no-character-target-in-range"), "the fallback retains a diagnostic trace without pretending the activation ended")
	var unrelated := MonsterState.new("monster.unrelated", monster_definition.id, "Unrelated", 10, 10)
	unrelated.weapon_id = "item.unrelated"
	rules.combat_flow._prepare_monster_melee_weapon(monster_shooter, monster_definition, monster_content)
	assert_equal([monster_shooter.weapon_id, unrelated.weapon_id], [melee_item.id, "item.unrelated"], "melee replacement updates the actual attacker instead of Castle's stale global monsterup")


func _test_source_backed_character_spell_casting() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.combat-fire", 1306, "Combat Fire")
	spell.in_combat = true
	spell.target_type = 1
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cost = 2
	spell.range_min = 10
	spell.damage_min = 4
	spell.damage_max = 4
	spell.duration_min = 1
	spell.duration_max = 1
	assert_equal(spell.classic_tier(), 2, "Classic spell 1306 encodes zero-based tier two rather than caster level")
	var character := _character("character.spell-caster")
	character.level = 10
	character.normal_attacks = 6
	character.maximum_spell_attacks = 2
	character.maximum_spell_points = 10
	character.spell_points = 10
	character.set_known_spells([spell.id])
	var definition := _monster_definition("monster.spell-target", [])
	var monster := MonsterState.new("monster.spell-target.instance", definition.id, definition.name, 30, 30, 1, 1)
	monster.conditions.set_value(18, 1)
	var state := _state(character, monster, "battle.character-spell")
	state.combat.battlefield.move_actor(monster.id, Vector2i(50, 45))
	var content := _content([definition], [], [], [], [spell])
	var options := rules.combat_flow.character_spell_options(state, content, character.id)
	assert_equal(options.size(), 10, "the typed battle picker exposes funded powers for every live Classic actor target")
	assert_equal([options[0].spell_id, options[0].power, options[0].cost, options[0].target_id], [spell.id, 1, 2, character.id], "the first detached cast option preserves party-slot-first Classic actor ordering")
	assert_true(options.any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == spell.id and option.power == 1 and option.target_id == monster.id), "the detached cast options retain the hostile monster after legal party targets")
	var screened := rules.combat_flow.cast_spell(state, content, character.id, monster.id, spell.id, 1, ScriptedRng.new([0, 0]))
	assert_true(screened.ok, "a funded ordinary single-target combat spell commits")
	assert_true(screened.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("classicTier") == 2 and event.payload.get("resisted") == true), "spell resistance uses the spell ID's tier even when caster level is ten")
	assert_equal([character.spell_points, character.attacks_remaining, character.movement, monster.current_health], [8, 5, 0, 30], "a resisted spell still spends energy, two half-attacks, and twelve movement while retaining Castle's carried half-attack")
	assert_equal(state.combat.active_turn.spell_cast_count, 1, "the active turn owns the committed per-activation spell count")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-activation spell count and round hit history survive save restoration")
	assert_equal(restored.combat.active_turn.spell_cast_count, 1, "restore cannot repeat the first spell slot in the activation")

	monster.conditions.set_value(18, 0)
	var second := rules.combat_flow.cast_spell(state, content, character.id, monster.id, spell.id, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_true(second.ok, "the caster can use its second authored spell attack in the same activation")
	assert_equal([character.spell_points, character.attacks_remaining, monster.current_health], [6, 3, 26], "the second cast commits ordinary damage and retains a final physical half-attack pair plus the carried half-unit")
	assert_true(state.combat.was_attacked(monster.id), "positive spell damage marks the target attacked for Castle's same-round casting gate")
	var capped_rng := ScriptedRng.new([])
	var capped := rules.combat_flow.cast_spell(state, content, character.id, monster.id, spell.id, 1, capped_rng)
	assert_false(capped.ok, "a third spell in the same activation is rejected")
	assert_equal(capped.error_code, &"spell_attack_limit_reached", "the per-activation spell cap has a stable failure identity")
	assert_equal(capped_rng.snapshot().draw_count, 0, "a rejected over-limit cast consumes no gameplay randomness")

	var blocked_character := _character("character.spell-blocked")
	blocked_character.maximum_spell_attacks = 1
	blocked_character.maximum_spell_points = 10
	blocked_character.spell_points = 10
	blocked_character.set_known_spells([spell.id])
	var blocked_monster := MonsterState.new("monster.spell-blocked.instance", definition.id, definition.name, 30, 30, 1, 1)
	var blocked_state := _state(blocked_character, blocked_monster, "battle.character-spell-blocked")
	blocked_state.combat.mark_attacked(blocked_character.id)
	var blocked := rules.combat_flow.cast_spell(blocked_state, content, blocked_character.id, blocked_monster.id, spell.id, 1, ScriptedRng.new([]))
	assert_equal(blocked.error_code, &"caster_attacked_this_round", "a character damaged earlier in the round cannot cast")
	blocked_state.combat.advance_turn()
	blocked_state.combat.advance_turn()
	assert_false(blocked_state.combat.was_attacked(blocked_character.id), "Castle's been-attacked gate clears only when combat advances to a new round")
	blocked_state.character_spellcasting_blocked = true
	var scenario_blocked := rules.combat_flow.cast_spell(blocked_state, content, blocked_character.id, blocked_monster.id, spell.id, 1, ScriptedRng.new([]))
	assert_equal(scenario_blocked.error_code, &"character_spellcasting_blocked", "a nonzero Classic spellcasting flag blocks rather than enables character casting")


func _test_source_backed_special_healing_and_actor_targeting() -> void:
	var rules := RealmzRules.new()
	var healing := SpellDefinition.new("spell.heal-small-wounds", 2105, "Heal Small Wounds")
	healing.in_combat = true
	healing.in_camp = true
	healing.target_type = 1
	healing.spell_class = 8
	healing.damage_type = 8
	healing.cannot = 4
	healing.special = 57
	healing.cost = 2
	healing.range_min = 1
	healing.power_damage_min = 4
	healing.power_damage_max = 4

	var caster := _character("character.healing-caster")
	caster.set_known_spells([healing.id])
	caster.maximum_spell_attacks = 2
	caster.maximum_spell_points = 20
	caster.spell_points = 20
	caster.normal_attacks = 4
	var ally := _character("character.healing-ally")
	ally.name = "Wounded Ally"
	ally.current_health = 10
	ally.maximum_health = 30
	var hostile_definition := _monster_definition("monster.healing-hostile", [])
	var hostile := MonsterState.new("monster.healing-hostile.instance", hostile_definition.id, "Hostile", 20, 20, 1)
	var battlefield := _blank_battlefield()
	battlefield.place_character(caster.id, Vector2i(45, 45))
	battlefield.place_character(ally.id, Vector2i(44, 45))
	battlefield.place_monster(hostile.id, Vector2i(46, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [caster, ally]), RealmzClock.new())
	state.combat = CombatState.new("battle.healing", [hostile], 0, battlefield)
	state.combat.set_turn_order([caster.id, ally.id, hostile.id])
	var content := _content([hostile_definition], [], [], [], [healing])

	var options := rules.combat_flow.character_spell_options(state, content, caster.id).filter(func(option: CombatSpellOptionView) -> bool: return option.spell_id == healing.id and option.power == 2)
	assert_equal(options.map(func(option: CombatSpellOptionView) -> String: return option.target_id), [caster.id, ally.id, hostile.id], "single-target player spells preserve Castle party-then-monster selection without imposing allegiance")
	assert_equal(options.map(func(option: CombatSpellOptionView) -> String: return option.target_name), [caster.name, ally.name, hostile.name], "typed spell options expose detached names for character and monster targets")

	var cast := rules.combat_flow.cast_spell(state, content, caster.id, ally.id, healing.id, 2, ScriptedRng.new([0, 0, 0, 0]))
	assert_true(cast.ok, "special 57 commits through the ordinary typed actor-target cast boundary")
	assert_equal([caster.spell_points, ally.current_health], [16, 18], "special 57 negates the shared damage roll into capped character healing")
	assert_false(state.combat.was_attacked(ally.id), "healing does not set Castle's been-attacked casting gate")
	var healing_event: DomainEvent = cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([healing_event.payload.get("targetId"), healing_event.payload.get("targetKind"), healing_event.payload.get("damage"), healing_event.payload.get("healing")], [ally.id, "character", -8, 8], "the typed result distinguishes healing from positive committed damage")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a committed healing cast restores through the central save aggregate")
	assert_equal([restored.party.character_by_id(ally.id).current_health, restored.party.character_by_id(caster.id).spell_points, restored.combat.active_turn.spell_cast_count], [18, 16, 1], "restore preserves healing, cost, and the per-activation cast cursor")

	var monster_slots: Array[String] = [healing.id, "", "", "", "", "", "", "", "", ""]
	var healer_definition := MonsterDefinition.new("monster.healing-caster", 9, "Monster Healer", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), monster_slots, [], [])
	healer_definition.magic_attack_count = 1
	var friend_definition := _monster_definition("monster.healing-friend", [])
	var monster_healer := MonsterState.new("monster.healing-caster.instance", healer_definition.id, healer_definition.name, 10, 10, 4, 1, 0, 0, 10)
	var monster_friend := MonsterState.new("monster.healing-friend.instance", friend_definition.id, "Monster Friend", 8, 20, 1)
	var party_target := _character("character.healing-opponent")
	var monster_field := _blank_battlefield()
	monster_field.place_character(party_target.id, Vector2i(45, 45))
	monster_field.place_monster(monster_healer.id, Vector2i(46, 45), 0)
	monster_field.place_monster(monster_friend.id, Vector2i(47, 45), 0)
	var monster_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	monster_state.combat = CombatState.new("battle.monster-healing", [monster_healer, monster_friend], 0, monster_field)
	monster_state.combat.set_turn_order([party_target.id, monster_healer.id, monster_friend.id])
	monster_state.combat.turn_index = 1
	var monster_content := _content([healer_definition, friend_definition], [], [], [], [healing])
	var monster_events: Array[DomainEvent] = []
	var monster_turn := monster_state.combat.begin_active_turn()
	var monster_result := rules.combat_flow._process_monster_cast(monster_state, monster_content, monster_healer, healer_definition, monster_turn, ScriptedRng.new([0, 0, 30_000, 0, 0, 0]), monster_events)
	assert_equal(monster_result, CombatFlow.MONSTER_ATTACK_COMPLETED, "a cannot-four monster spell uses the source-backed friendly target branch")
	assert_equal([monster_healer.current_health, monster_healer.maximum_health, monster_friend.current_health, party_target.current_health], [14, 10, 8, 30], "Castle monster healing can select self, exceed maximum stamina, and cannot target an opposed party actor")
	assert_true(monster_state.combat.was_attacked(monster_healer.id), "Castle marks a healed monster as attacked even though its negative damage increases stamina")
	var monster_event: DomainEvent = monster_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([monster_event.payload.get("targetId"), monster_event.payload.get("healing"), monster_healer.spell_points], [monster_healer.id, 4, 8], "monster healing publishes its effective ally target, actual gain, and paid power")
	var restored_monster := GameState.from_data(JSON.parse_string(JSON.stringify(monster_state.to_data())))
	assert_not_null(restored_monster, "monster special healing state restores")
	assert_equal([restored_monster.combat.monster_by_id(monster_healer.id).current_health, restored_monster.combat.active_turn.spell_cast_count], [14, 1], "restore preserves monster overheal and the authored magic-attack cursor")


func _test_spell_death_macro_queue_and_restore() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.queued-death", 1306, "Queued Death")
	spell.in_combat = true
	spell.target_type = 1
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cost = 2
	spell.range_min = 10
	spell.damage_min = 4
	spell.damage_max = 4
	spell.duration_min = 1
	spell.duration_max = 1
	var definition := _monster_definition("monster.queued-death", [])
	definition.death_macro = 321
	var monster := MonsterState.new("monster.queued-death.instance", definition.id, definition.name, 4, 4, 1)
	var character := _character("character.queued-death")
	character.set_known_spells([spell.id])
	character.maximum_spell_attacks = 2
	character.maximum_spell_points = 10
	character.spell_points = 10
	character.normal_attacks = 4
	character.attacks_remaining = 0
	var state := _state(character, monster, "battle.queued-death")
	var content := _content([definition], [], [], [], [spell])
	var cast := rules.combat_flow.cast_spell(state, content, character.id, monster.id, spell.id, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_true(cast.ok, "a lethal spell commits before its Castle death-macro queue is drained")
	var request_events := cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"monster_death_macro_requested")
	assert_equal(request_events.size(), 1, "the completed spell emits only its queue head")
	assert_equal([request_events[0].payload.get("combatantId"), request_events[0].payload.get("queuedBySpell"), request_events[0].payload.get("resetTraitorOnComplete")], [monster.id, true, false], "spell deaths identify Castle's deferred macro and allegiance-preserving completion path")
	assert_equal([state.combat.active_actor_id(), state.combat.spell_death_macro_queue(), state.combat.battlefield.has_actor(monster.id)], [character.id, [monster.id], true], "the active caster and corrected revival footprint survive until the queued macro completes")

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "the spell death-macro queue and active-caster continuation survive whole-state restoration")
	if restored == null:
		return
	var restored_monster := restored.combat.monster_by_id(monster.id)
	restored_monster.current_health = 1
	var resumed := rules.combat_flow.continue_after_monster_death_macro(restored, content, ScriptedRng.new([]), monster.id)
	assert_true(resumed.ok, "the restored queued spell macro completes against its exact saved combatant")
	assert_equal([restored.combat.spell_death_macro_queue(), restored.combat.active_actor_id(), restored.combat.battlefield.has_actor(monster.id), restored_monster.traitor], [[], character.id, true, true], "a revived queued-spell target retains its position, enemy allegiance, and the caster's remaining activation")

	var second_definition := _monster_definition("monster.queued-death.second", [])
	second_definition.death_macro = 322
	var first := MonsterState.new("monster.queue.first", definition.id, "First", 0, 4, 1)
	var second := MonsterState.new("monster.queue.second", second_definition.id, "Second", 0, 4, 1)
	var queue_field := _blank_battlefield()
	queue_field.place_character(character.id, Vector2i(45, 45))
	queue_field.place_monster(first.id, Vector2i(46, 45), 0)
	queue_field.place_monster(second.id, Vector2i(47, 45), 0)
	var queue_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [character]), RealmzClock.new())
	queue_state.combat = CombatState.new("battle.queued-order", [first, second], 0, queue_field)
	queue_state.combat.set_turn_order([character.id, first.id, second.id])
	queue_state.combat.begin_active_turn()
	assert_true(queue_state.combat.queue_spell_death_macro(first.id) and queue_state.combat.queue_spell_death_macro(second.id), "multiple spell deaths retain source target order")
	assert_true(queue_state.combat.begin_spell_death_macro_sequence(character.id, false), "the queue owns its issuing spell activation")
	var queue_content := _content([definition, second_definition])
	var first_completed := rules.combat_flow.continue_after_monster_death_macro(queue_state, queue_content, ScriptedRng.new([]), first.id)
	assert_true(first_completed.ok, "the first queued death macro advances only the queue cursor")
	assert_equal([queue_state.combat.spell_death_macro_queue(), queue_state.combat.battlefield.has_actor(first.id), queue_state.combat.battlefield.has_actor(second.id)], [[second.id], false, true], "a completed dead subject is removed while the next corrected revival footprint remains")
	assert_true(first_completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"monster_death_macro_requested" and event.payload.get("combatantId") == second.id), "the next source-ordered macro is requested before battle or turn continuation")
	var wrong_cursor := rules.combat_flow.continue_after_monster_death_macro(queue_state, queue_content, ScriptedRng.new([]), first.id)
	assert_equal(wrong_cursor.error_code, &"invalid_spell_death_macro_queue", "a stale response cannot skip or replay the saved queue head")
	var limit_field := _blank_battlefield()
	limit_field.place_character(character.id, Vector2i(45, 45))
	limit_field.place_monster(first.id, Vector2i(46, 45), 0)
	var limit_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [character]), RealmzClock.new())
	limit_state.combat = CombatState.new("battle.queued-limit", [first], 0, limit_field)
	limit_state.combat.set_turn_order([character.id, first.id])
	limit_state.combat.begin_active_turn()
	var filled_record_queue := true
	for _index: int in CombatState.MAX_SPELL_DEATH_MACROS:
		filled_record_queue = filled_record_queue and limit_state.combat.queue_spell_death_macro(first.id)
	assert_true(filled_record_queue, "Castle's fixed todoque permits one hundred ordered records including duplicate subjects")
	assert_false(limit_state.combat.queue_spell_death_macro(first.id), "the safe runtime rejects a record beyond Castle's fixed queue instead of overflowing memory")
	assert_true(limit_state.combat.begin_spell_death_macro_sequence(character.id, false), "the full record queue retains its issuing actor")
	var restored_limit := GameState.from_data(JSON.parse_string(JSON.stringify(limit_state.to_data())))
	assert_equal(restored_limit.combat.spell_death_macro_queue().size(), CombatState.MAX_SPELL_DEATH_MACROS, "save restoration preserves the complete bounded record queue")


func _test_character_automatic_group_spell() -> void:
	var rules := RealmzRules.new()
	assert_true(rules.combat_flow._group_target_matches(9, false, false), "target type 9 includes a loyal participant for a loyal caster")
	assert_false(rules.combat_flow._group_target_matches(9, true, false), "target type 9 excludes an opposed participant")
	assert_false(rules.combat_flow._group_target_matches(10, false, false), "target type 10 excludes a friendly participant")
	assert_true(rules.combat_flow._group_target_matches(10, true, false), "target type 10 includes an opposed participant")
	var spell := SpellDefinition.new("spell.everybody", 1306, "Everybody")
	spell.in_combat = true
	spell.target_type = 12
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cannot = 1
	spell.cost = 2
	spell.damage_min = 4
	spell.damage_max = 4
	spell.power_damage_min = 2
	spell.power_damage_max = 2
	spell.duration_min = 1
	spell.duration_max = 1
	var caster := _character("character.group.caster")
	caster.set_known_spells([spell.id])
	caster.maximum_spell_attacks = 2
	caster.maximum_spell_points = 20
	caster.spell_points = 20
	caster.normal_attacks = 4
	var ally := _character("character.group.ally")
	ally.current_health = 20
	ally.maximum_health = 20
	var first_definition := _monster_definition("monster.group.first", [])
	first_definition.death_macro = 321
	var second_definition := _monster_definition("monster.group.second", [])
	second_definition.death_macro = 322
	var first := MonsterState.new("monster.group.first.instance", first_definition.id, "First", 6, 6, 1)
	var second := MonsterState.new("monster.group.second.instance", second_definition.id, "Second", 6, 6, 1)
	var battlefield := _blank_battlefield()
	battlefield.place_character(caster.id, Vector2i(45, 45))
	battlefield.place_character(ally.id, Vector2i(44, 45))
	battlefield.place_monster(first.id, Vector2i(46, 45), 0)
	battlefield.place_monster(second.id, Vector2i(47, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [caster, ally]), RealmzClock.new())
	state.combat = CombatState.new("battle.group", [first, second], 0, battlefield)
	state.combat.set_turn_order([caster.id, ally.id, first.id, second.id])
	var content := _content([first_definition, second_definition], [], [], [], [spell])
	var options := rules.combat_flow.character_spell_options(state, content, caster.id)
	assert_true(options.any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == spell.id and option.power == 1 and option.target_id.is_empty() and option.target_name == "Everybody"), "automatic group spells expose one typed picker option without fabricating a combatant target")
	var cast := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 1, ScriptedRng.new([0, 0, 0, 32_767, 32_767, 32_767, 32_767]))
	assert_true(cast.ok, "a player everybody spell resolves as one committed Classic cast")
	assert_equal(caster.spell_points, 18, "the group spell charges its caster once rather than once per target")
	var resolved := cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("targetId")), [caster.id, ally.id, first.id, second.id], "group targets resolve in Castle party-slot then monster-slot order")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("damage")), [6, 6, 6, 6], "one shared base and power damage roll feeds each target's independent defenses")
	assert_equal([caster.current_health, ally.current_health, first.current_health, second.current_health], [caster.maximum_health - 6, 14, 0, 0], "everybody affects both sides without repeating the shared damage roll")
	assert_equal(state.combat.spell_death_macro_queue(), [first.id, second.id], "spell-killed monsters enter the death-macro queue in source target order")
	var macro_requests := cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"monster_death_macro_requested")
	assert_equal(macro_requests.size(), 1, "only the first queued group-spell death macro is dispatched")
	assert_equal(macro_requests[0].payload.get("combatantId"), first.id, "the queue head is the first defeated native monster slot")
	assert_equal(rules.combat_flow._monster_spell_unavailable_reason(spell), "monster-group-spell-power-resource-anomaly", "monster group casting stays explicitly disabled instead of reproducing Castle's stale power and missing resource accounting")


func _test_character_fixed_area_spell() -> void:
	var rules := RealmzRules.new()
	var pattern_counts: Array[int] = []
	for shape: int in range(1, 19):
		pattern_counts.append(rules.spell_areas.pattern(shape).size())
	assert_equal(pattern_counts, [1, 2, 5, 9, 13, 25, 37, 8, 21, 14, 13, 14, 13, 28, 1, 2, 2, 4], "the fixed rules preserve all eighteen source-ordered Data AD mask sizes")
	assert_equal(rules.spell_areas.pattern(3), [Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1)], "Data AD shape three preserves its row-major cross orientation")
	assert_equal(rules.spell_areas.pattern(11), [Vector2i(3, -3), Vector2i(2, -2), Vector2i(3, -2), Vector2i(1, -1), Vector2i(2, -1), Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(-2, 2), Vector2i(-1, 2), Vector2i(-3, 3), Vector2i(-2, 3)], "Data AD shape eleven preserves its asymmetric diagonal rather than inventing a geometric primitive")
	assert_false(rules.spell_areas.pattern(14).has(Vector2i.ZERO), "Data AD shape fourteen preserves its hollow center")
	assert_equal(rules.spell_areas.pattern(18), [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO], "Data AD shape eighteen preserves its source-oriented two-by-two footprint")
	var spell := SpellDefinition.new("spell.fixed-area", 1306, "Fixed Area")
	spell.in_combat = true
	spell.target_type = 3
	spell.size = 3
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cannot = 1
	spell.cost = 2
	spell.range_min = 10
	spell.damage_min = 4
	spell.damage_max = 4
	spell.power_damage_min = 2
	spell.power_damage_max = 2
	spell.duration_min = 1
	spell.duration_max = 1
	var caster := _character("character.area.caster")
	caster.set_known_spells([spell.id])
	caster.maximum_spell_attacks = 2
	caster.maximum_spell_points = 20
	caster.spell_points = 20
	caster.normal_attacks = 4
	var ally := _character("character.area.ally")
	ally.current_health = 20
	ally.maximum_health = 20
	var first_definition := _monster_definition("monster.area.first", [])
	first_definition.death_macro = 323
	var immune_definition := _monster_definition("monster.area.immune", [])
	var first := MonsterState.new("monster.area.first.instance", first_definition.id, "First", 6, 6, 1)
	var immune := MonsterState.new("monster.area.immune.instance", immune_definition.id, "Immune", 12, 12, 1, 1, 0, 101)
	var battlefield := _blank_battlefield()
	battlefield.place_character(caster.id, Vector2i(40, 45))
	battlefield.place_character(ally.id, Vector2i(45, 44))
	battlefield.place_monster(first.id, Vector2i(44, 45), 0)
	battlefield.place_monster(immune.id, Vector2i(46, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [caster, ally]), RealmzClock.new())
	state.combat = CombatState.new("battle.area", [first, immune], 0, battlefield)
	state.combat.set_turn_order([caster.id, ally.id, first.id, immune.id])
	var content := _content([first_definition, immune_definition], [], [], [], [spell])
	var options := rules.combat_flow.character_spell_options(state, content, caster.id)
	assert_true(options.any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == spell.id and option.target_mode == &"area" and option.area_shape == 3 and option.area_offsets == rules.spell_areas.pattern(3)), "fixed area spells expose one typed center-selection descriptor instead of fabricating a combatant target")
	var empty_caster := _character("character.area.empty-caster")
	empty_caster.set_known_spells([spell.id])
	empty_caster.maximum_spell_attacks = 2
	empty_caster.maximum_spell_points = 20
	empty_caster.spell_points = 20
	empty_caster.normal_attacks = 4
	var far_definition := _monster_definition("monster.area.far", [])
	var far_monster := MonsterState.new("monster.area.far.instance", far_definition.id, "Far", 12, 12, 1)
	var empty_battlefield := _blank_battlefield()
	empty_battlefield.place_character(empty_caster.id, Vector2i(40, 45))
	empty_battlefield.place_monster(far_monster.id, Vector2i(80, 80), 0)
	var empty_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [empty_caster]), RealmzClock.new())
	empty_state.combat = CombatState.new("battle.area.empty", [far_monster], 0, empty_battlefield)
	empty_state.combat.set_turn_order([empty_caster.id, far_monster.id])
	var empty_rng := ScriptedRng.new([0, 0, 0])
	var empty_cast := rules.combat_flow.cast_spell(empty_state, _content([far_definition], [], [], [], [spell]), empty_caster.id, "", spell.id, 1, empty_rng, Vector2i(40, 40))
	assert_true(empty_cast.ok, "a legal empty-space center still commits the one Classic area transaction")
	assert_equal([empty_caster.spell_points, empty_rng.snapshot().draw_count], [18, 3], "an empty area still spends once and rolls shared duration plus base and power damage")
	assert_equal(empty_cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved").size(), 0, "an empty area does not fabricate a target event")
	var missing_center := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 1, ScriptedRng.new([]))
	assert_false(missing_center.ok, "area execution requires an explicit battlefield center")
	assert_equal([missing_center.error_code, caster.spell_points], [&"area_target_required", 20], "missing area coordinates fail before resource mutation")
	var edge_probe := rules.combat_flow.probe_character_spell_cast(state, content, caster.id, "", spell.id, 1, Vector2i.ZERO)
	assert_equal(edge_probe.reason, &"spell_area_outside_battlefield", "an unsafe Castle edge mask is rejected rather than indexing outside the battlefield")
	spell.target_type = 0
	var multi_probe := rules.combat_flow.probe_character_spell_cast(state, content, caster.id, "", spell.id, 1)
	assert_equal(multi_probe.reason, &"repeated_open_space_spell_unresolved", "nonzero-size target type zero remains separate because Castle selects open-space footprints instead of ordinary actors")
	spell.target_type = 3
	spell.queue_icon = 1
	assert_equal(rules.combat_flow.probe_character_spell_cast(state, content, caster.id, "", spell.id, 1).reason, &"queued_spell_field_unresolved", "a persistent area field stays disabled instead of resolving damage while silently omitting its queued collision state")
	assert_equal(rules.combat_flow._monster_spell_unavailable_reason(spell), "monster-queued-spell-field-unresolved", "monster casting cannot silently omit the same queued field state")
	spell.queue_icon = 0
	spell.can_rotate = true
	assert_equal(rules.combat_flow.probe_character_spell_cast(state, content, caster.id, "", spell.id, 1).reason, &"rotatable_area_spell_unresolved", "rotatable spells stay disabled until their authored adjacent-mask orientation contract is implemented")
	spell.can_rotate = false
	ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 1)
	var reflection_rng := ScriptedRng.new([])
	var reflected := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 1, reflection_rng, Vector2i(45, 45))
	assert_equal([reflected.error_code, reflection_rng.snapshot().draw_count, caster.spell_points], [&"area_spell_reflection_unresolved", 0, 20], "unimplemented reflection fails transactionally before Castle's targeting draw or cast cost")
	ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 0)
	var cast := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 1, ScriptedRng.new([0, 0, 0, 32_767, 32_767, 32_767, 32_767]), Vector2i(45, 45))
	assert_true(cast.ok, "a fixed area resolves as one committed Classic cast")
	assert_equal(caster.spell_points, 18, "the fixed area charges its caster once")
	var resolved := cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("targetId")), [ally.id, first.id], "area occupants resolve in party-slot then monster-slot order while over-100 monster resistance is removed during targeting")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("damage")), [6, 6], "one area duration/base-damage roll feeds each selected target's independent defenses")
	assert_equal([ally.current_health, first.current_health, immune.current_health], [14, 0, 12], "the Data AD mask affects intersecting footprints and skips source-immune monsters")
	assert_equal(resolved[0].payload.get("areaCenter"), [45, 45], "area events retain the selected battlefield center")
	assert_equal(resolved[0].payload.get("areaShape"), 3, "area events retain the resolved Data AD shape")
	assert_equal(state.combat.spell_death_macro_queue(), [first.id], "area deaths enter the existing source-ordered spell macro queue")
	spell.target_type = 4
	assert_equal(rules.spell_areas.shape_for(spell, 5), 5, "target type four derives its Data AD shape from cast power rather than the fixed size field")


func _test_source_backed_monster_spell_casting() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.monster-fire", 1306, "Monster Fire")
	spell.target_type = 1
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cost = 2
	spell.range_min = 10
	spell.damage_min = 4
	spell.damage_max = 4
	spell.duration_min = 1
	spell.duration_max = 1
	var slots: Array[String] = ["", spell.id, "", "", "", "", "", "", "", ""]
	var definition := MonsterDefinition.new("monster.spell-caster", 9, "Spell Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), slots, [], [])
	definition.magic_attack_count = 1
	definition.cast_percent = 100
	definition.missile_percent = 0
	definition.movement_max = 0
	var monster := MonsterState.new("monster.spell-caster.instance", definition.id, definition.name, 30, 30, 4, 1, 0, 0, 10)
	var character := _character("character.monster-spell-target")
	var state := _state(character, monster, "battle.monster-spell")
	state.combat.turn_index = 1
	var content := _content([definition], [], [], [], [spell])
	var values: Array[int] = [0, 0, 0, 4000, 0, 0, 0, 0, 0, 32_767]
	var rng := ScriptedRng.new(values)
	var events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(state, content, rng, events)
	assert_equal([character.current_health, monster.spell_points], [26, 8], "an ordinary monster spell spends lowered power cost and commits damage to its selected party target")
	assert_false(state.combat.is_guarding(monster.id), "Castle's ordinary targeted monster cast clears Guard")
	assert_equal(state.combat.active_actor_id(), character.id, "a successful monster spell ends the monster activation")
	var cast_events := events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("source") == "classic-monster")
	assert_equal(cast_events.size(), 1, "monster casting publishes one typed source-owned resolution event")
	assert_equal([cast_events[0].payload.get("spellId"), cast_events[0].payload.get("power"), cast_events[0].payload.get("rangePower")], [spell.id, 1, 1], "the event distinguishes affordability power from Castle's preserved range power")
	assert_equal(rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).begins_with("monster.spell.slot")).map(func(entry: Dictionary) -> int: return int(entry.get("result"))), [0, 1], "fixed monster spell slots consume empty-position draws before selecting the authored spell")

	definition.magic_attack_count = 2
	var multi_monster := MonsterState.new("monster.multi-spell.instance", definition.id, definition.name, 30, 30, 4, 1, 0, 0, 10)
	var multi_target := _character("character.multi-spell-target")
	var multi_state := _state(multi_target, multi_monster, "battle.monster-multi-spell")
	multi_state.combat.turn_index = 1
	var multi_turn := multi_state.combat.begin_active_turn()
	var one_cast_values: Array[int] = [0, 4000, 0, 0, 0, 0, 0, 32_767]
	var multi_values: Array[int] = []
	multi_values.append_array(one_cast_values)
	multi_values.append_array(one_cast_values)
	var multi_events: Array[DomainEvent] = []
	assert_equal(rules.combat_flow._process_monster_cast(multi_state, content, multi_monster, definition, multi_turn, ScriptedRng.new(multi_values), multi_events), 0, "the bounded caster completes every authored magical attack")
	assert_equal([multi_target.current_health, multi_monster.spell_points, multi_turn.spell_cast_count, multi_turn.monster_cast_attempt_count], [22, 6, 2, 1], "two magical attacks share one attempt while committing independent slot, power, target, and resolution draws")
	var restored_multi := GameState.from_data(JSON.parse_string(JSON.stringify(multi_state.to_data())))
	assert_not_null(restored_multi, "monster cast and retry cursors survive central save restoration")
	assert_equal([restored_multi.combat.active_turn.spell_cast_count, restored_multi.combat.active_turn.monster_cast_attempt_count], [2, 1], "restore cannot repeat a committed magical attack or first tryspell attempt")

	definition.magic_attack_count = 1
	definition.cast_percent = 50
	var retry_monster := MonsterState.new("monster.retry-spell.instance", definition.id, definition.name, 30, 30, 4, 1, 0, 0, 10)
	var retry_target := _character("character.retry-spell-target")
	var retry_state := _state(retry_target, retry_monster, "battle.monster-retry-spell")
	retry_state.combat.turn_index = 1
	var retry_values: Array[int] = [0, 32_767, 0, 4000, 0, 0, 0, 0, 0, 32_767]
	var retry_rng := ScriptedRng.new(retry_values)
	var retry_events: Array[DomainEvent] = []
	rules.combat_flow._process_monster_turns(retry_state, content, retry_rng, retry_events)
	assert_equal(retry_target.current_health, 26, "a monster that initially chooses movement may retry casting after its zero-movement advance")
	assert_equal(retry_rng.trace().filter(func(entry: Dictionary) -> bool: return entry.get("tag") == "monster.ai.cast").size(), 1, "Castle's post-movement tryspell jump does not repeat the cast-percent roll")


func _test_character_and_monster_repeated_target_spells() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.magic-darts", 3208, "Magic Darts")
	spell.in_combat = true
	spell.target_type = 0
	spell.size = 0
	spell.spell_class = 3
	spell.damage_type = 6
	spell.cannot = 3
	spell.cost = 2
	spell.range_min = 15
	spell.duration_min = 1
	spell.duration_max = 1
	spell.damage_min = 1
	spell.damage_max = 4
	var caster := _character("character.darts.caster")
	caster.set_known_spells([spell.id])
	caster.maximum_spell_attacks = 2
	caster.maximum_spell_points = 20
	caster.spell_points = 20
	caster.normal_attacks = 4
	var ally := _character("character.darts.ally")
	ally.current_health = 20
	ally.maximum_health = 20
	var target_definition := _monster_definition("monster.darts.target", [])
	var immune_definition := _monster_definition("monster.darts.immune", [])
	var target := MonsterState.new("monster.darts.target.instance", target_definition.id, "Target", 20, 20, 1)
	var immune := MonsterState.new("monster.darts.immune.instance", immune_definition.id, "Immune", 20, 20, 1, 1, 0, 101)
	var battlefield := _blank_battlefield()
	battlefield.place_character(caster.id, Vector2i(45, 45))
	battlefield.place_character(ally.id, Vector2i(44, 45))
	battlefield.place_monster(target.id, Vector2i(46, 45), 0)
	battlefield.place_monster(immune.id, Vector2i(47, 45), 0)
	var state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [caster, ally]), RealmzClock.new())
	state.combat = CombatState.new("battle.darts", [target, immune], 0, battlefield)
	state.combat.set_turn_order([caster.id, ally.id, target.id, immune.id])
	var content := _content([target_definition, immune_definition], [], [], [], [spell])
	var options := rules.combat_flow.character_spell_options(state, content, caster.id)
	var sequence_options := options.filter(func(option: CombatSpellOptionView) -> bool: return option.spell_id == spell.id and option.power == 3 and option.target_mode == &"sequence")
	assert_equal(sequence_options.size(), 1, "target type zero exposes one ordered-selection option per spell and power")
	assert_equal(sequence_options[0].maximum_targets, 3, "the typed option carries Castle's one-target-per-power maximum")
	assert_equal(sequence_options[0].target_candidates.map(func(candidate: CombatSpellTargetView) -> String: return candidate.id), [caster.id, ally.id, target.id, immune.id], "the candidate list preserves party slots before monster slots without imposing allegiance")
	var duplicate_rng := ScriptedRng.new([])
	var duplicate := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 3, duplicate_rng, CombatFlow.INVALID_COORDINATE, 0, [target.id, target.id])
	assert_equal([duplicate.error_code, duplicate_rng.snapshot().draw_count, caster.spell_points], [&"invalid_repeated_spell_targets", 0, 20], "duplicate selections fail before cost, turn, or RNG mutation")
	ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 1)
	var reflecting_options := rules.combat_flow.character_spell_options(state, content, caster.id).filter(func(option: CombatSpellOptionView) -> bool: return option.spell_id == spell.id and option.power == 3 and option.target_mode == &"sequence")
	assert_true(reflecting_options[0].target_candidates.any(func(candidate: CombatSpellTargetView) -> bool: return candidate.id == ally.id), "a reflecting actor remains a legal Classic selection instead of disappearing from the picker")
	ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 0)
	var cast_rng := ScriptedRng.new([0, 0, 32_767, 0, 32_767, 32_767, 0, 0])
	var cast := rules.combat_flow.cast_spell(state, content, caster.id, "", spell.id, 3, cast_rng, CombatFlow.INVALID_COORDINATE, 0, [ally.id, target.id, immune.id])
	assert_true(cast.ok, "an ordered actor sequence commits as one Classic target-type-zero cast")
	assert_equal(caster.spell_points, 14, "the caster pays once for the chosen power rather than once per selected actor")
	assert_equal(cast_rng.snapshot().draw_count, 8, "each ordinary target rerolls duration and damage while the over-100 target still consumes its two pre-resolution rolls")
	var resolved := cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("targetId")), [ally.id, target.id], "resolution events preserve user selection order and omit Castle's over-100 immune target")
	assert_equal(resolved.map(func(event: DomainEvent) -> Variant: return event.payload.get("damage")), [1, 4], "target type zero rerolls base damage for each selected actor instead of sharing an area roll")
	assert_equal([ally.current_health, target.current_health, immune.current_health], [19, 16, 20], "the selected party member and monster receive their independent rolls while complete magic immunity remains unchanged")

	var early_caster := _character("character.darts.early-caster")
	early_caster.spell_points = 20
	var early_target := _character("character.darts.early-target")
	var early := rules.magic.resolve_character_repeated_spell(early_caster, [SpellTargetSelection.for_character(early_target)], spell, 3, spell.classic_tier(), ScriptedRng.new([0, 0, 32_767]))
	assert_true(early != null and early.cast, "Castle permits casting before all power-count target slots are filled")
	assert_equal(early_caster.spell_points, 14, "early casting does not refund unused target slots from the prepaid power")

	var monster_slots: Array[String] = [spell.id, "", "", "", "", "", "", "", "", ""]
	var caster_definition := MonsterDefinition.new("monster.darts.caster", 9, "Darts Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), monster_slots, [], [])
	caster_definition.magic_attack_count = 1
	var monster_caster := MonsterState.new("monster.darts.caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var first_party := _character("character.darts.first-party")
	var second_party := _character("character.darts.second-party")
	var monster_field := _blank_battlefield()
	monster_field.place_character(first_party.id, Vector2i(45, 45))
	monster_field.place_character(second_party.id, Vector2i(46, 45))
	monster_field.place_monster(monster_caster.id, Vector2i(47, 45), 0)
	var monster_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [first_party, second_party]), RealmzClock.new())
	monster_state.combat = CombatState.new("battle.monster-darts", [monster_caster], 0, monster_field)
	monster_state.combat.set_turn_order([first_party.id, second_party.id, monster_caster.id])
	monster_state.combat.turn_index = 2
	var monster_content := _content([caster_definition], [], [], [], [spell])
	var repeated_values: Array[int] = [0, 0, 32_767]
	repeated_values.append_array(_ints(100))
	repeated_values.append_array([0, 0, 32_767])
	var monster_rng := ScriptedRng.new(repeated_values)
	var monster_events: Array[DomainEvent] = []
	var monster_turn := monster_state.combat.begin_active_turn()
	assert_equal(rules.combat_flow._process_monster_cast(monster_state, monster_content, monster_caster, caster_definition, monster_turn, monster_rng, monster_events), 0, "a monster commits a partial repeated-target cast after Castle's shared hundred-attempt target budget")
	assert_equal([first_party.current_health, second_party.current_health, monster_caster.spell_points], [first_party.maximum_health - 1, second_party.maximum_health, 6], "the partial cast resolves one unique actor but spends the full randomly chosen power")
	assert_equal(monster_rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).begins_with("monster.spell.target.")).size(), 100, "the per-cast retry budget counts successful and rejected samples across one complete target sequence")
	assert_equal(monster_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved").size(), 1, "partial monster selection emits only the target actually resolved")

	var reset_target := _character("character.darts.reset-target")
	var reset_caster := MonsterState.new("monster.darts.reset-caster", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var reset_field := _blank_battlefield()
	reset_field.place_character(reset_target.id, Vector2i(45, 45))
	reset_field.place_monster(reset_caster.id, Vector2i(47, 45), 0)
	var reset_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [reset_target]), RealmzClock.new())
	reset_state.combat = CombatState.new("battle.monster-darts-reset", [reset_caster], 0, reset_field)
	reset_state.combat.set_turn_order([reset_target.id, reset_caster.id])
	reset_state.combat.turn_index = 1
	caster_definition.magic_attack_count = 2
	var reset_values: Array[int] = [0, 0, 0]
	for _sample: int in 99:
		reset_values.append(32_767)
	reset_values.append_array([0, 0, 0, 32_767])
	reset_values.append_array([0, 0, 0, 0, 0, 0, 32_767])
	var reset_rng := ScriptedRng.new(reset_values)
	var reset_events: Array[DomainEvent] = []
	var reset_turn := reset_state.combat.begin_active_turn()
	assert_equal(rules.combat_flow._process_monster_cast(reset_state, monster_content, reset_caster, caster_definition, reset_turn, reset_rng, reset_events), 0, "FD-COMBAT-011 gives every monster spell cast an independent hundred-attempt target budget")
	assert_equal([reset_turn.spell_cast_count, reset_target.current_health, reset_caster.spell_points], [2, reset_target.maximum_health - 2, 6], "a cast succeeding on its hundredth sample cannot suppress the next otherwise-valid cast")
	assert_equal(reset_rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).begins_with("monster.spell.target.")).size(), 101, "the corrected second cast performs its own first target draw instead of tripping Castle's leaked 101st-attempt cutoff")
	assert_false(reset_state.combat.to_data().has("monsterSpellTargetPass"), "the corrected per-cast retry guard is temporary execution state rather than save-owned battle state")
	var stale_counter_data := reset_state.combat.to_data()
	stale_counter_data["monsterSpellTargetPass"] = 77
	var stale_counter_restore := CombatState.from_data(stale_counter_data)
	assert_not_null(stale_counter_restore, "save-v3 battle data emitted by the brief battle-wide-counter implementation remains readable")
	assert_false(stale_counter_restore.to_data().has("monsterSpellTargetPass"), "restoring stale counter data discards the accidental implementation field")
	var correction_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/oracle/monster-spell-target-retry-scope-correction.json"))
	assert_true(correction_fixture is Dictionary, "the monster spell-target retry decision has a parseable source-observation fixture")
	if correction_fixture is Dictionary:
		assert_equal([int(correction_fixture["castleSourceObservation"]["nextAttemptNumber"]), bool(correction_fixture["castleSourceObservation"]["samplesRngBeforeCutoff"]), int(correction_fixture["realmz2ChosenResult"]["nextCastFirstAttemptNumber"])], [101, false, 1], "FD-COMBAT-011 separates Castle's battle-wide leaked cutoff from the chosen per-cast retry budget")

	spell.size = 1
	assert_equal(rules.combat_flow.probe_character_spell_cast(state, content, caster.id, "", spell.id, 1).reason, &"repeated_open_space_spell_unresolved", "nonzero-size target type zero remains the separate open-space or summoning contract")
	assert_equal(rules.combat_flow._monster_spell_unavailable_reason(spell), "monster-repeated-open-space-spell-unresolved", "monster open-space target type zero is not silently treated as actor damage")


func _test_ordinary_spell_reflection_and_opposed_monster_targets() -> void:
	var rules := RealmzRules.new()
	var spell := SpellDefinition.new("spell.reflection-bolt", 1306, "Reflection Bolt")
	spell.in_combat = true
	spell.target_type = 1
	spell.spell_class = 1
	spell.damage_type = 1
	spell.cannot = 3
	spell.cost = 2
	spell.range_min = 15
	spell.duration_min = 1
	spell.duration_max = 1
	spell.damage_min = 4
	spell.damage_max = 4

	var player_caster := _character("character.reflection-caster")
	player_caster.set_known_spells([spell.id])
	player_caster.maximum_spell_attacks = 2
	player_caster.maximum_spell_points = 20
	player_caster.spell_points = 20
	player_caster.normal_attacks = 4
	var reflecting_definition := _monster_definition("monster.reflecting-target", [])
	var reflecting_monster := MonsterState.new("monster.reflecting-target.instance", reflecting_definition.id, "Reflector", 20, 20, 1)
	reflecting_monster.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1)
	var player_state := _state(player_caster, reflecting_monster, "battle.player-spell-reflection")
	var player_content := _content([reflecting_definition], [], [], [], [spell])
	var reflected_rng := ScriptedRng.new([0, 0, 0, 0])
	var reflected := rules.combat_flow.cast_spell(player_state, player_content, player_caster.id, reflecting_monster.id, spell.id, 1, reflected_rng)
	assert_true(reflected.ok, "a selected reflecting monster resolves through the ordinary spell path")
	var reflected_event: DomainEvent = reflected.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([reflecting_monster.current_health, player_caster.current_health, player_caster.spell_points], [20, 26, 18], "a successful one-through-thirty-three reflection leaves the selected monster untouched and damages the original caster")
	assert_equal([reflected_event.payload.get("selectedTargetId"), reflected_event.payload.get("targetId"), reflected_event.payload.get("targetKind"), reflected_event.payload.get("reflected")], [reflecting_monster.id, player_caster.id, "character", true], "the typed event preserves both the authored selection and Castle's effective redirected target")
	assert_equal(reflected_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["magic.reflect", "magic.duration", "magic.damage", "magic.damage-save"], "single-target reflection precedes duration, damage, and target defenses")

	var failed_caster := _character("character.failed-reflection-caster")
	failed_caster.set_known_spells([spell.id])
	failed_caster.maximum_spell_attacks = 2
	failed_caster.spell_points = 20
	failed_caster.normal_attacks = 4
	var failed_monster := MonsterState.new("monster.failed-reflection-target", reflecting_definition.id, "Failed Reflector", 20, 20, 1)
	failed_monster.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 1)
	var failed_state := _state(failed_caster, failed_monster, "battle.failed-spell-reflection")
	var failed_rng := ScriptedRng.new([32_767, 0, 0, 0])
	var not_reflected := rules.combat_flow.cast_spell(failed_state, player_content, failed_caster.id, failed_monster.id, spell.id, 1, failed_rng)
	var direct_event: DomainEvent = not_reflected.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([failed_caster.current_health, failed_monster.current_health, direct_event.payload.get("targetId"), direct_event.payload.get("reflected")], [30, 16, failed_monster.id, false], "a roll of one hundred fails reflection and preserves the original target")

	var repeated_spell := SpellDefinition.new("spell.reflection-darts", 3208, "Reflection Darts")
	repeated_spell.in_combat = true
	repeated_spell.target_type = 0
	repeated_spell.size = 0
	repeated_spell.spell_class = 3
	repeated_spell.damage_type = 6
	repeated_spell.cannot = 3
	repeated_spell.cost = 2
	repeated_spell.range_min = 15
	repeated_spell.duration_min = 1
	repeated_spell.duration_max = 1
	repeated_spell.damage_min = 2
	repeated_spell.damage_max = 2
	var repeated_caster := _character("character.repeated-reflection-caster")
	repeated_caster.set_known_spells([repeated_spell.id])
	repeated_caster.maximum_spell_attacks = 2
	repeated_caster.spell_points = 20
	repeated_caster.normal_attacks = 4
	var repeated_ally := _character("character.repeated-reflector")
	repeated_ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 1)
	var repeated_target_definition := _monster_definition("monster.repeated-ordinary", [])
	var repeated_target := MonsterState.new("monster.repeated-ordinary.instance", repeated_target_definition.id, "Ordinary Target", 20, 20, 1)
	var repeated_field := _blank_battlefield()
	repeated_field.place_character(repeated_caster.id, Vector2i(45, 45))
	repeated_field.place_character(repeated_ally.id, Vector2i(44, 45))
	repeated_field.place_monster(repeated_target.id, Vector2i(46, 45), 0)
	var repeated_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [repeated_caster, repeated_ally]), RealmzClock.new())
	repeated_state.combat = CombatState.new("battle.repeated-reflection", [repeated_target], 0, repeated_field)
	repeated_state.combat.set_turn_order([repeated_caster.id, repeated_ally.id, repeated_target.id])
	var repeated_content := _content([repeated_target_definition], [], [], [], [repeated_spell])
	var repeated_rng := ScriptedRng.new([0, 0, 0, 0, 0, 0, 0])
	var repeated_result := rules.combat_flow.cast_spell(repeated_state, repeated_content, repeated_caster.id, "", repeated_spell.id, 2, repeated_rng, CombatFlow.INVALID_COORDINATE, 0, [repeated_ally.id, repeated_target.id])
	var repeated_events := repeated_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal(repeated_events.map(func(event: DomainEvent) -> Variant: return [event.payload.get("selectedTargetId"), event.payload.get("targetId"), event.payload.get("reflected")]), [[repeated_ally.id, repeated_caster.id, true], [repeated_target.id, repeated_target.id, false]], "each repeated selection independently records reflection without changing source order")
	assert_equal(repeated_rng.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["magic.repeated.reflect.0", "magic.repeated.duration.0", "magic.repeated.damage.0", "magic.damage-save", "magic.repeated.duration.1", "magic.repeated.damage.1", "magic.damage-save"], "each selected actor completes reflection and resolution before the next repeated target begins")

	var monster_slots: Array[String] = [spell.id, "", "", "", "", "", "", "", "", ""]
	var caster_definition := MonsterDefinition.new("monster.opposed-caster", 9, "Opposed Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), monster_slots, [], [])
	caster_definition.magic_attack_count = 1
	var opposed_definition := _monster_definition("monster.opposed-target", [])
	var monster_caster := MonsterState.new("monster.opposed-caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var party_target := _character("character.opposed-slot-zero")
	var opposed_monster := MonsterState.new("monster.opposed-target.instance", opposed_definition.id, "Opposed Monster", 20, 20, 1, 1, 0, 0, 0, false)
	var opposed_field := _blank_battlefield()
	opposed_field.place_character(party_target.id, Vector2i(45, 45))
	opposed_field.place_monster(monster_caster.id, Vector2i(47, 45), 0)
	opposed_field.place_monster(opposed_monster.id, Vector2i(46, 45), 0)
	var opposed_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	opposed_state.combat = CombatState.new("battle.opposed-monster-spell", [monster_caster, opposed_monster], 0, opposed_field)
	opposed_state.combat.set_turn_order([party_target.id, monster_caster.id, opposed_monster.id])
	opposed_state.combat.turn_index = 1
	var opposed_content := _content([caster_definition, opposed_definition], [], [], [], [spell])
	var opposed_events: Array[DomainEvent] = []
	var opposed_rng := ScriptedRng.new([0, 0, 32_767, 0, 0, 0])
	assert_equal(rules.combat_flow._process_monster_cast(opposed_state, opposed_content, monster_caster, caster_definition, opposed_state.combat.begin_active_turn(), opposed_rng, opposed_events), CombatFlow.MONSTER_ATTACK_COMPLETED, "a monster can select an opposed monster through Castle's native target space")
	var opposed_event: DomainEvent = opposed_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([party_target.current_health, opposed_monster.current_health, opposed_event.payload.get("targetId"), opposed_event.payload.get("targetKind")], [30, 16, opposed_monster.id, "monster"], "native slot eleven resolves against monster index one rather than falling through the party-slot gap")

	var reflecting_opponent := MonsterState.new("monster.opposed-reflector.instance", opposed_definition.id, "Opposed Reflector", 20, 20, 1, 1, 0, 0, 0, false)
	reflecting_opponent.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1)
	var reflecting_caster := MonsterState.new("monster.reflected-caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var reflection_field := _blank_battlefield()
	reflection_field.place_character(party_target.id, Vector2i(45, 45))
	reflection_field.place_monster(reflecting_caster.id, Vector2i(47, 45), 0)
	reflection_field.place_monster(reflecting_opponent.id, Vector2i(46, 45), 0)
	var monster_reflection_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	monster_reflection_state.combat = CombatState.new("battle.monster-spell-reflection", [reflecting_caster, reflecting_opponent], 0, reflection_field)
	monster_reflection_state.combat.set_turn_order([party_target.id, reflecting_caster.id, reflecting_opponent.id])
	monster_reflection_state.combat.turn_index = 1
	var monster_reflection_events: Array[DomainEvent] = []
	var monster_reflection_rng := ScriptedRng.new([0, 0, 32_767, 0, 0, 0, 0])
	rules.combat_flow._process_monster_cast(monster_reflection_state, opposed_content, reflecting_caster, caster_definition, monster_reflection_state.combat.begin_active_turn(), monster_reflection_rng, monster_reflection_events)
	var monster_reflection_event: DomainEvent = monster_reflection_events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([reflecting_opponent.current_health, reflecting_caster.current_health, monster_reflection_event.payload.get("selectedTargetId"), monster_reflection_event.payload.get("targetId"), monster_reflection_event.payload.get("reflected")], [20, 26, reflecting_opponent.id, reflecting_caster.id, true], "an opposed monster's reflection redirects once to the active monster caster")
	var immune_caster := MonsterState.new("monster.immune-reflected-caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 101, 10)
	var reflected_to_immune := rules.magic.resolve_monster_targeted_spell(immune_caster, caster_definition, SpellTargetSelection.for_monster(reflecting_opponent, opposed_definition), spell, 1, spell.classic_tier(), ScriptedRng.new([0, 0, 0]))
	assert_equal([reflected_to_immune.resolutions.size(), reflected_to_immune.target_ids[0], reflected_to_immune.reflected_targets[0], reflected_to_immune.resolutions[0].resisted, immune_caster.current_health], [1, immune_caster.id, true, true, 30], "reflection bypasses only the original target's above-100 targeting exclusion; the effective monster caster then resists during resolution")

	var macro_definition := _monster_definition("monster.spell-macro-target", [])
	macro_definition.death_macro = 77
	var macro_target := MonsterState.new("monster.spell-macro-target.instance", macro_definition.id, "Macro Target", 3, 3, 1, 1, 0, 0, 0, false)
	var macro_caster := MonsterState.new("monster.spell-macro-caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var macro_field := _blank_battlefield()
	macro_field.place_character(party_target.id, Vector2i(45, 45))
	macro_field.place_monster(macro_caster.id, Vector2i(47, 45), 0)
	macro_field.place_monster(macro_target.id, Vector2i(46, 45), 0)
	var macro_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	macro_state.combat = CombatState.new("battle.monster-spell-macro", [macro_caster, macro_target], 0, macro_field)
	macro_state.combat.set_turn_order([party_target.id, macro_caster.id, macro_target.id])
	macro_state.combat.turn_index = 1
	var macro_content := _content([caster_definition, macro_definition], [], [], [], [spell])
	var macro_events: Array[DomainEvent] = []
	var macro_result := rules.combat_flow._process_monster_cast(macro_state, macro_content, macro_caster, caster_definition, macro_state.combat.begin_active_turn(), ScriptedRng.new([0, 0, 32_767, 0, 0, 0]), macro_events)
	assert_equal(macro_result, CombatFlow.MONSTER_ATTACK_DEATH_MACRO, "a monster spell pauses for an opposed monster's death macro")
	assert_equal([macro_state.combat.pending_spell_death_macro_id(), macro_state.combat.spell_macro_actor_id(), macro_state.combat.spell_macro_advances_turn()], [macro_target.id, macro_caster.id, true], "the serialized spell queue retains the monster caster and completed activation")
	var restored_macro := GameState.from_data(JSON.parse_string(JSON.stringify(macro_state.to_data())))
	assert_equal([restored_macro.combat.pending_spell_death_macro_id(), restored_macro.combat.spell_macro_actor_id()], [macro_target.id, macro_caster.id], "save restoration preserves the opposed-monster spell death-macro boundary")
	var low_energy_slots: Array[String] = [spell.id, "", "", "", "", "", "", "", "", ""]
	var low_energy_definition := MonsterDefinition.new("monster.low-energy-macro-caster", 11, "Low-energy Macro Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), low_energy_slots, [], [])
	low_energy_definition.magic_attack_count = 2
	var low_energy_caster := MonsterState.new("monster.low-energy-macro-caster.instance", low_energy_definition.id, low_energy_definition.name, 30, 30, 4, 1, 0, 0, 2)
	var low_energy_target := MonsterState.new("monster.low-energy-macro-target.instance", macro_definition.id, "Low-energy Macro Target", 3, 3, 1, 1, 0, 0, 0, false)
	var low_energy_field := _blank_battlefield()
	low_energy_field.place_character(party_target.id, Vector2i(45, 45))
	low_energy_field.place_monster(low_energy_caster.id, Vector2i(47, 45), 0)
	low_energy_field.place_monster(low_energy_target.id, Vector2i(46, 45), 0)
	var low_energy_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	low_energy_state.combat = CombatState.new("battle.low-energy-macro", [low_energy_caster, low_energy_target], 0, low_energy_field)
	low_energy_state.combat.set_turn_order([party_target.id, low_energy_caster.id, low_energy_target.id])
	low_energy_state.combat.turn_index = 1
	var low_energy_events: Array[DomainEvent] = []
	var low_energy_result := rules.combat_flow._process_monster_cast(low_energy_state, _content([low_energy_definition, macro_definition], [], [], [], [spell]), low_energy_caster, low_energy_definition, low_energy_state.combat.begin_active_turn(), ScriptedRng.new([0, 0, 32_767, 0, 0, 0, 0, 0]), low_energy_events)
	assert_equal([low_energy_result, low_energy_state.combat.active_turn.spell_cast_count, low_energy_state.combat.pending_spell_death_macro_id()], [CombatFlow.MONSTER_ATTACK_DEATH_MACRO, 1, low_energy_target.id], "a later unaffordable magic attack cannot bypass a death macro queued by the committed first cast")

	var self_macro_slots: Array[String] = [spell.id, "", "", "", "", "", "", "", "", ""]
	var self_macro_definition := MonsterDefinition.new("monster.self-reflecting-caster", 12, "Self-reflecting Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), self_macro_slots, [], [])
	self_macro_definition.magic_attack_count = 2
	self_macro_definition.death_macro = 88
	var self_macro_caster := MonsterState.new("monster.self-reflecting-caster.instance", self_macro_definition.id, self_macro_definition.name, 3, 3, 4, 1, 0, 0, 20)
	var self_macro_target := MonsterState.new("monster.self-reflecting-target.instance", opposed_definition.id, "Self-reflecting Target", 20, 20, 1, 1, 0, 0, 0, false)
	self_macro_target.conditions.set_value(ConditionRules.REFLECTING_SPELLS, 1)
	var self_macro_field := _blank_battlefield()
	self_macro_field.place_character(party_target.id, Vector2i(45, 45))
	self_macro_field.place_monster(self_macro_caster.id, Vector2i(47, 45), 0)
	self_macro_field.place_monster(self_macro_target.id, Vector2i(46, 45), 0)
	var self_macro_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [party_target]), RealmzClock.new())
	self_macro_state.combat = CombatState.new("battle.self-reflection-macro", [self_macro_caster, self_macro_target], 0, self_macro_field)
	self_macro_state.combat.set_turn_order([party_target.id, self_macro_caster.id, self_macro_target.id])
	self_macro_state.combat.turn_index = 1
	var self_macro_events: Array[DomainEvent] = []
	var self_macro_rng := ScriptedRng.new([0, 0, 32_767, 0, 0, 0, 0, 0, 0, 32_767, 0, 0, 0, 0])
	var self_macro_result := rules.combat_flow._process_monster_cast(self_macro_state, _content([self_macro_definition, opposed_definition], [], [], [], [spell]), self_macro_caster, self_macro_definition, self_macro_state.combat.begin_active_turn(), self_macro_rng, self_macro_events)
	assert_equal([self_macro_result, self_macro_state.combat.active_turn.spell_cast_count, self_macro_caster.current_health, self_macro_target.current_health], [CombatFlow.MONSTER_ATTACK_DEATH_MACRO, 2, -5, 20], "Castle's noofmagattacks loop completes after the first reflected cast kills its monster caster")
	assert_equal([self_macro_state.combat.spell_death_macro_queue(), self_macro_state.combat.spell_macro_actor_id(), self_macro_state.combat.battlefield.has_actor(self_macro_caster.id)], [[self_macro_caster.id, self_macro_caster.id], self_macro_caster.id, true], "each post-death reflected hit queues another Castle macro record while retaining the dead caster's anchor")
	var restored_self_macro := GameState.from_data(JSON.parse_string(JSON.stringify(self_macro_state.to_data())))
	assert_equal([restored_self_macro.combat.active_turn.spell_cast_count, restored_self_macro.combat.spell_death_macro_queue(), restored_self_macro.combat.spell_macro_advances_turn()], [2, [self_macro_caster.id, self_macro_caster.id], true], "save restoration cannot repeat the post-death casts or deduplicate Castle's queued records")
	var first_self_macro := rules.combat_flow.continue_after_monster_death_macro(restored_self_macro, _content([self_macro_definition, opposed_definition], [], [], [], [spell]), ScriptedRng.new([]), self_macro_caster.id)
	assert_true(first_self_macro.ok, "the first duplicate caster macro completes through the ordinary continuation")
	assert_equal([restored_self_macro.combat.spell_death_macro_queue(), restored_self_macro.combat.battlefield.has_actor(self_macro_caster.id)], [[self_macro_caster.id], true], "a still-dead duplicate subject retains occupancy until its final queued macro record")


func _test_charm_resistance_continues_after_failed_opposed_save() -> void:
	var spell := SpellDefinition.new("spell.charm-resistance", 1101, "Charm")
	spell.spell_class = 0
	spell.damage_type = 0
	spell.cannot = 0
	var target := _character("character.charm-resistance")
	target.set_save_value(0, 0)
	target.magic_resistance = 100
	var rng := ScriptedRng.new([32_767, 0])
	assert_true(MagicRules.new().character_resists(4, target, spell, 1, 0, rng), "a failed charm save continues into Castle's ordinary magic-resistance check")
	assert_equal(rng.snapshot().draw_count, 2, "charm resistance consumes the opposed save before magic resistance")
	spell.cannot = 1
	var bypass_rng := ScriptedRng.new([32_767])
	assert_false(MagicRules.new().character_resists(4, target, spell, 1, 0, bypass_rng), "cannot one bypasses screens and magic resistance only after the initial charm save")
	assert_equal(bypass_rng.snapshot().draw_count, 1, "the cannot bypass does not erase the source-ordered charm draw")


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

	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"finish", "", rng)
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
	active_turn.movement_remaining = 7

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-sequence monster cursor survives central state restoration")
	assert_equal(restored.combat.active_turn.attack_index, 1, "restore does not repeat the committed first attack row")
	assert_true(restored.combat.active_turn.physical_action_committed, "restore retains that the active monster turn already issued a physical row")
	assert_equal(restored.combat.active_turn.movement_remaining, 7, "restore retains the source-owned monster movement remainder")
	var legacy_turn_data := restored.combat.active_turn.to_data()
	legacy_turn_data.erase("physicalActionCommitted")
	legacy_turn_data.erase("movementRemaining")
	legacy_turn_data.erase("spellCastCount")
	legacy_turn_data.erase("monsterCastAttemptCount")
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
	var result := rules.combat_flow.submit_action(state, _content([definition], [weapon]), character.id, &"finish", "", ScriptedRng.new(values))
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
	var battlefield := _blank_battlefield()
	battlefield.place_character(character.id, Vector2i(45, 45))
	battlefield.place_monster(monster.id, Vector2i(46, 45), 0)
	result.combat = CombatState.new(battle_id, [monster], 0, battlefield)
	result.combat.set_turn_order([character.id, monster.id])
	return result


func _blank_battlefield() -> BattlefieldState:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	return BattlefieldState.new("map.test", tiles)


func _content(monsters: Array[MonsterDefinition], items: Array[ItemDefinition] = [], races: Array[RaceDefinition] = [], castes: Array[CasteDefinition] = [], spells: Array[SpellDefinition] = []) -> RealmzContent:
	return RealmzContent.new("campaign.cadence", "0".repeat(64), "cadence", "realmz-classic-1", "map.test", Vector2i(45, 45), _battle_world(), ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells, monsters)


func _battle_world() -> WorldDefinition:
	if _cached_battle_world != null:
		return _cached_battle_world
	var cells: Array[MapCell] = []
	var empty_ids: Array[String] = []
	var empty_features: Array[MapFeature] = []
	for y: int in 90:
		for x: int in 90:
			var coordinate := Vector2i(x, y)
			cells.append(MapCell.new("map.test:cell:%d,%d" % [x, y], coordinate, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "", empty_ids, empty_ids, {}, empty_features))
	var terrain_tiles: Array[BattleTerrainTileDefinition] = []
	for tile: int in 401:
		terrain_tiles.append(BattleTerrainTileDefinition.new(tile, 0, 0, 0, false, 0, false, false, false, 0, [[tile, tile, tile], [tile, tile, tile], [tile, tile, tile]]))
	var terrain_set := BattleTerrainSetDefinition.new("terrain.test", 1, 1, terrain_tiles)
	var map := MapDefinition.new("map.test", "Battle Test Map", &"land", 0, MapTopology.new(90, 90, cells), false, false, 1, [], terrain_set.id)
	_cached_battle_world = WorldDefinition.new([map], [], [terrain_set])
	return _cached_battle_world


func _blocked_battle_world() -> WorldDefinition:
	var cells: Array[MapCell] = []
	var empty_ids: Array[String] = []
	var empty_features: Array[MapFeature] = []
	for y: int in 90:
		for x: int in 90:
			var coordinate := Vector2i(x, y)
			cells.append(MapCell.new("map.test:blocked:%d,%d" % [x, y], coordinate, "classic.terrain.2", false, 1, false, true, false, false, false, false, false, 0, 2, "", empty_ids, empty_ids, {}, empty_features))
	var terrain_tiles: Array[BattleTerrainTileDefinition] = []
	for tile: int in 401:
		terrain_tiles.append(BattleTerrainTileDefinition.new(tile, 0, 0, 2 if tile == 2 else 0, false, 0, false, false, false, 0, [[tile, tile, tile], [tile, tile, tile], [tile, tile, tile]]))
	var terrain_set := BattleTerrainSetDefinition.new("terrain.blocked", 1, 2, terrain_tiles)
	var map := MapDefinition.new("map.test", "Blocked Battle Test Map", &"land", 0, MapTopology.new(90, 90, cells), false, false, 1, [], terrain_set.id)
	return WorldDefinition.new([map], [], [terrain_set])


func _ints(count: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(0)
	return result
