extends RealmzTestCase

var _cached_battle_world: WorldDefinition


func run() -> void:
	_test_tactical_adjacency_movement_and_restore()
	_test_monster_los_targeting_and_movement()
	_test_character_half_attack_cadence_and_restore()
	_test_character_weapon_mode_toggle_and_restore()
	_test_monster_missile_does_not_impersonate_melee()
	_test_monster_authored_attack_rows_and_target_retention()
	_test_monster_attack_cursor_restore()
	_test_battle_owned_fumble_and_exact_recovery()
	_test_monster_fumble_clears_only_active_weapon()


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
	var invalid_move := rules.combat_flow.move_character(state, content, character.id, Vector2i(48, 45))
	assert_false(invalid_move.ok, "a nonadjacent tactical step is rejected")
	assert_equal(state.combat.active_turn, null, "rejected movement does not initialize mutable turn state")
	assert_equal([character.attacks_remaining, character.movement], resources_before_invalid_move, "rejected movement preserves combat resources")

	var moved := rules.combat_flow.move_character(state, content, character.id, Vector2i(46, 45))
	assert_true(moved.ok, "a reaction-free cardinal battlefield step commits")
	assert_equal([battlefield.character_position(character.id), character.movement], [Vector2i(46, 45), 11], "Castle cardinal movement spends the destination tile base plus one changed axis")
	assert_true(moved.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("cost") == 1), "movement publishes its exact committed cost")
	var free_view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield)
	assert_true(free_view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.enabled), "the detached view exposes reaction-free movement before any hostile perimeter is involved")
	battlefield.move_actor(monster.id, Vector2i(47, 45))
	assert_true(rules.battlefield.are_adjacent(battlefield, character.id, monster.id), "explicit fixture placement establishes diagonal melee adjacency")
	var guard_reaction := rules.combat_flow.move_character(state, content, character.id, Vector2i(46, 44))
	assert_false(guard_reaction.ok, "movement that remains beside an enemy stays disabled until Castle guarding state is serializable")
	assert_equal(guard_reaction.error_code, &"guard_reaction_unavailable", "the missing guarding path is explicit rather than silently skipped")
	var withdrawal := rules.combat_flow.move_character(state, content, character.id, Vector2i(45, 44))
	assert_false(withdrawal.ok, "movement that leaves an adjacent enemy stays disabled until Castle withdrawal reactions are serializable")
	assert_equal(withdrawal.error_code, &"withdrawal_attack_unavailable", "the disabled reaction path is explicit instead of silently moving")
	assert_equal(battlefield.character_position(character.id), Vector2i(46, 45), "a rejected withdrawal leaves battlefield state unchanged")

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-turn tactical position survives the central save aggregate")
	assert_equal(restored.combat.battlefield.character_position(character.id), Vector2i(46, 45), "restore retains the exact committed battlefield coordinate")
	assert_equal(restored.party.character_by_id(character.id).movement, 11, "restore retains remaining tactical movement")
	var view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield)
	assert_equal(view.targets.map(func(target: MonsterView) -> String: return target.id), [monster.id], "the detached view exposes only adjacent hostile melee targets")
	assert_equal(view.movement_options.size(), 8, "the detached view exposes all eight source-backed step probes")
	assert_false(view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.enabled), "the detached view does not advertise a step that could skip guard or withdrawal reactions")
	assert_true(view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.reason == &"guard_reaction_unavailable" and not option.reason_text.is_empty()), "guard-disabled movement carries a player-facing typed reason")

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
	var advanced := rules.combat_flow.submit_action(distant_state, content, distant_character.id, &"defend", "", ScriptedRng.new(distant_values))
	assert_true(advanced.ok, "a nonadjacent monster activation follows its source-backed tactical path")
	assert_true(advanced.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved" and event.payload.get("actorId") == distant_monster.id), "monster movement is committed as explicit battlefield events")
	assert_true(distant_character.current_health < 20, "the monster resolves melee only after reaching an adjacent footprint")
	assert_true(rules.battlefield.are_adjacent(distant_state.combat.battlefield, distant_character.id, distant_monster.id), "automatic movement ends in source-legal melee adjacency")


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
	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"defend", "", ScriptedRng.new(values))
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
	var tangled_result := rules.combat_flow.submit_action(tangled_state, _content([definition]), tangled_character.id, &"defend", "", ScriptedRng.new([0, 0]))
	assert_true(tangled_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("reason") == "permanent-tangle-movement-unresolved"), "Castle's apparent permanent-Tangle movement increase remains explicit instead of becoming gameplay")

	var helpless_character := _character("character.helpless-monster")
	var helpless_monster := MonsterState.new("monster.helpless.instance", definition.id, definition.name, 20, 20, 1)
	helpless_monster.conditions.set_value(ConditionRules.HELPLESS, -1)
	var helpless_state := _state(helpless_character, helpless_monster, "battle.helpless-monster")
	var helpless_rng := ScriptedRng.new([])
	var helpless_result := rules.combat_flow.submit_action(helpless_state, _content([definition]), helpless_character.id, &"defend", "", helpless_rng)
	assert_true(helpless_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action" and event.payload.get("action") == "incapacitated"), "Castle skips a helpless monster before its tactical decision")
	assert_equal(helpless_rng.snapshot().draw_count, 0, "an incapacitated monster consumes no AI or target randomness")

	var speedy_character := _character("character.speedy-monster")
	var speedy_monster := MonsterState.new("monster.speedy.instance", definition.id, definition.name, 20, 20, 1)
	speedy_monster.conditions.set_value(ConditionRules.SPEEDY, -1)
	var speedy_state := _state(speedy_character, speedy_monster, "battle.speedy-monster")
	var speedy_result := rules.combat_flow.submit_action(speedy_state, _content([definition]), speedy_character.id, &"defend", "", ScriptedRng.new([0, 0]))
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
	var combat_view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield)
	assert_equal(combat_view.weapon_mode, &"missile", "the detached combat view exposes the battle-owned mode")
	assert_equal(combat_view.legal_actions, [&"switch_weapon", &"defend", &"retreat"], "the detached view cannot advertise melee attack while missile mode is active")
	assert_false(combat_view.ranged_attack_unavailable_reason.is_empty(), "the detached view carries the exact tactical ranged blocker")
	var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(94), ScenarioActionState.new())
	var request := api._combat_request("request.weapon-mode")
	assert_equal([request.payload.get("weaponMode"), request.payload.get("actions")], ["missile", ["switch_weapon", "defend", "retreat"]], "the typed interaction preserves the same legal actions as the detached view")
	assert_equal(request.payload.get("weaponSwitch", {}).get("targetMode"), "melee", "the typed switch response names its source-owned destination mode")
	assert_false(String(request.payload.get("rangedAttack", {}).get("reason", "")).is_empty(), "the typed interaction explains why Fire is disabled")
	var blocked := rules.combat_flow.submit_action(state, content, character.id, &"attack", monster.id, RealmzRng.new(92))
	assert_false(blocked.ok, "missile mode cannot fall through to the melee resolver while tactical ranged state is unavailable")
	assert_equal(blocked.error_code, &"missile_attack_unavailable", "the disabled ranged path fails with an explicit fidelity reason")
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
	var setup_view := CombatView.new(setup_state.combat, setup_state.party.characters(), content, rules.inventory, rules.battlefield)
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
	var result := rules.combat_flow.submit_action(state, _content([definition]), character.id, &"defend", "", ScriptedRng.new([0, 0, 0, 0]))
	assert_true(result.ok, "an unavailable tactical missile decision returns a committed combat step")
	assert_equal(character.current_health, 20, "the missile branch no longer applies an ordinary melee attack row")
	assert_false(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == monster.id), "no melee-resolution event is mislabeled as a missile")
	assert_true(result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_monster_action_unavailable" and event.payload.get("action") == "missile" and event.payload.get("reason") == "tactical-position-unavailable"), "the disabled missile branch reports its exact missing session fact")
	assert_equal(state.combat.active_actor_id(), character.id, "an unavailable monster missile spends exactly that monster activation without skipping the next character turn")


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
	active_turn.movement_remaining = 7

	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "a mid-sequence monster cursor survives central state restoration")
	assert_equal(restored.combat.active_turn.attack_index, 1, "restore does not repeat the committed first attack row")
	assert_true(restored.combat.active_turn.physical_action_committed, "restore retains that the active monster turn already issued a physical row")
	assert_equal(restored.combat.active_turn.movement_remaining, 7, "restore retains the source-owned monster movement remainder")
	var legacy_turn_data := restored.combat.active_turn.to_data()
	legacy_turn_data.erase("physicalActionCommitted")
	legacy_turn_data.erase("movementRemaining")
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


func _content(monsters: Array[MonsterDefinition], items: Array[ItemDefinition] = []) -> RealmzContent:
	return RealmzContent.new("campaign.cadence", "0".repeat(64), "cadence", "realmz-classic-1", "map.test", Vector2i(45, 45), _battle_world(), ScenarioDefinition.new([], []), [], [], [], [], [], items, [], monsters)


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
