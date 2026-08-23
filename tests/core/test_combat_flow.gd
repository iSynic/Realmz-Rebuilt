extends RealmzTestCase

var _cached_battle_world: WorldDefinition


func run() -> void:
	_test_public_tactical_reaction_matrix()
	_test_public_magic_matrix()
	_test_public_monster_turn_matrix()
	_test_public_continuation_fumble_terminal_matrix()
	_test_public_command_automation_matrix()


func _test_public_tactical_reaction_matrix() -> void:
	var rules := RealmzRules.new()
	var definition := _monster_definition("monster.reaction", [MonsterAttackDefinition.new(1, 1)])
	definition.hit_dice = 20
	var character := _character("character.reaction")
	var monster := MonsterState.new("monster.reaction.instance", definition.id, definition.name, 30, 30, 20)
	var state := _state(character, monster, "battle.reaction")
	state.combat.set_guarding(monster.id, true)
	var result := rules.combat_flow.move_character(state, _content([definition]), character.id, Vector2i(44, 45), _zeros(16))
	assert_true(result.ok, "a public movement submission resolves the guarded withdrawal transaction")
	var reactions := result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("reaction") == true)
	assert_equal(reactions.map(func(event: DomainEvent) -> String: return String(event.payload.get("action"))), ["guard", "withdrawal"], "guard and withdrawal reactions retain their source order")
	assert_equal(reactions.map(func(event: DomainEvent) -> bool: return bool(event.payload.get("behind"))), [false, true], "only withdrawal carries the temporary behind modifier")
	assert_equal([character.current_health, state.combat.battlefield.character_position(character.id), state.combat.is_guarding(monster.id)], [28, Vector2i(44, 45), false], "both reactions commit before the surviving mover reaches its destination")

	var first := MonsterState.new("monster.slot.first", definition.id, definition.name, 30, 30, 20)
	var second := MonsterState.new("monster.slot.second", definition.id, definition.name, 30, 30, 20)
	var ordered_character := _character("character.ordered-reactions")
	var ordered_field := _blank_battlefield()
	ordered_field.place_character(ordered_character.id, Vector2i(45, 45))
	ordered_field.place_monster(first.id, Vector2i(46, 45), 0)
	ordered_field.place_monster(second.id, Vector2i(45, 46), 0)
	var ordered_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [ordered_character]), RealmzClock.new())
	ordered_state.combat = CombatState.new("battle.ordered-reactions", [first, second], 0, ordered_field)
	ordered_state.combat.set_turn_order([ordered_character.id, first.id, second.id])
	ordered_state.combat.set_guarding(first.id, true)
	ordered_state.combat.set_guarding(second.id, true)
	var ordered := rules.combat_flow.move_character(ordered_state, _content([definition]), ordered_character.id, Vector2i(44, 45), _zeros(20))
	var ordered_attacks := ordered.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("reaction") == true)
	assert_equal(ordered_attacks.map(func(event: DomainEvent) -> String: return String(event.payload.get("actorId"))), [first.id, second.id, first.id], "multiple reactions follow combat-slot order rather than stable-ID order")


func _test_public_magic_matrix() -> void:
	var rules := RealmzRules.new()
	var spell := _combat_spell("spell.reflection", 1, 4)
	var caster := _character("character.reflection-caster")
	caster.set_known_spells([spell.id])
	caster.maximum_spell_attacks = 2
	caster.spell_points = 20
	var definition := _monster_definition("monster.reflection", [])
	var reflector := MonsterState.new("monster.reflector.instance", definition.id, "Reflector", 20, 20, 1)
	reflector.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1)
	var state := _state(caster, reflector, "battle.reflection")
	var content := _content([definition], [], [], [], [spell])
	var probe := rules.combat_flow.probe_character_spell_cast(state, content, caster.id, reflector.id, spell.id, 1)
	assert_true(probe.allowed, "the public spell probe exposes the legal reflected target")
	var reflected_rng := _zeros(24)
	var reflected := rules.combat_flow.cast_spell(state, content, caster.id, reflector.id, spell.id, 1, reflected_rng)
	assert_true(reflected.ok, "a selected reflecting monster resolves through the public spell boundary")
	var reflected_event: DomainEvent = reflected.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")[0]
	assert_equal([reflector.current_health, caster.current_health, caster.spell_points], [20, 26, 18], "reflection leaves the selected monster untouched and damages the original caster")
	assert_equal([reflected_event.payload.get("selectedTargetId"), reflected_event.payload.get("targetId"), reflected_event.payload.get("reflected")], [reflector.id, caster.id, true], "the event preserves authored and effective target identity")
	assert_equal(reflected_rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry["tag"]).begins_with("magic.")).map(func(entry: Dictionary) -> String: return String(entry["tag"])), ["magic.reflect", "magic.duration", "magic.damage", "magic.damage-save"], "reflection consumes its magic draws before duration, damage, and defenses")

	var repeated := _combat_spell("spell.repeated", 0, 2)
	repeated.spell_class = 3
	repeated.damage_type = 6
	var repeated_caster := _character("character.repeated-caster")
	repeated_caster.set_known_spells([repeated.id])
	repeated_caster.maximum_spell_attacks = 2
	repeated_caster.spell_points = 20
	var repeated_target := MonsterState.new("monster.repeated-target", definition.id, definition.name, 20, 20, 1)
	var repeated_state := _state(repeated_caster, repeated_target, "battle.repeated")
	var repeated_content := _content([definition], [], [], [], [repeated])
	var repeated_before := JSON.stringify(repeated_state.to_data())
	var repeated_rng := ScriptedRng.new([])
	var rejected := rules.combat_flow.cast_spell(repeated_state, repeated_content, repeated_caster.id, "", repeated.id, 2, repeated_rng, CombatFlow.INVALID_COORDINATE, 0, [repeated_target.id, repeated_target.id])
	assert_equal([rejected.error_code, repeated_rng.snapshot().draw_count, JSON.stringify(repeated_state.to_data())], [&"invalid_repeated_spell_targets", 0, repeated_before], "an invalid repeated selection rolls back state and RNG before execution")

	var area := _combat_spell("spell.area", 4, 2)
	var area_caster := _character("character.area-caster")
	area_caster.set_known_spells([area.id])
	area_caster.maximum_spell_attacks = 2
	area_caster.spell_points = 20
	var area_target := MonsterState.new("monster.area-target", definition.id, definition.name, 20, 20, 1)
	var area_state := _state(area_caster, area_target, "battle.area")
	var area_content := _content([definition], [], [], [], [area])
	var area_options := rules.combat_flow.character_spell_options(area_state, area_content, area_caster.id)
	assert_equal(area_options.size(), 7, "the public picker stages one choice per affordable spell power without expanding battlefield centers")
	assert_true(area_options.all(func(option: CombatSpellOptionView) -> bool: return option.target_mode == &"area" and not option.area_offsets.is_empty() and option.legal_target_coordinates.is_empty()), "area choices carry their exact mask but defer range and LOS until the selected center is submitted")
	assert_false(rules.combat_flow.probe_character_spell_cast(area_state, area_content, area_caster.id, "", area.id, 1).allowed, "an area cast still requires an explicit battlefield center")
	assert_true(rules.combat_flow.probe_character_spell_cast(area_state, area_content, area_caster.id, "", area.id, 1, Vector2i(45, 45)).allowed, "the submitted center is validated through the authoritative battlefield rules")

	var group := _combat_spell("spell.group", 12, 4)
	var group_caster := _character("character.group-caster")
	group_caster.set_known_spells([group.id])
	group_caster.maximum_spell_attacks = 2
	group_caster.spell_points = 20
	var group_ally := _character("character.group-ally")
	var group_first := MonsterState.new("monster.group-first", definition.id, definition.name, 20, 20, 1)
	var group_second := MonsterState.new("monster.group-second", definition.id, definition.name, 20, 20, 1)
	var group_field := _blank_battlefield(); group_field.place_character(group_caster.id, Vector2i(45, 45)); group_field.place_character(group_ally.id, Vector2i(44, 45)); group_field.place_monster(group_first.id, Vector2i(46, 45), 0); group_field.place_monster(group_second.id, Vector2i(47, 45), 0)
	var group_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [group_caster, group_ally]), RealmzClock.new()); group_state.combat = CombatState.new("battle.group", [group_first, group_second], 0, group_field); group_state.combat.set_turn_order([group_caster.id, group_ally.id, group_first.id, group_second.id]); var group_content := _content([definition], [], [], [], [group]); var host_state := GameState.from_data(JSON.parse_string(JSON.stringify(group_state.to_data())))
	var group_options := rules.combat_flow.character_spell_options(group_state, group_content, group_caster.id); assert_true(group_options.any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == group.id and option.target_name == "Everybody"), "the public picker exposes targetless automatic group casting")
	var group_cast := rules.combat_flow.cast_spell(group_state, group_content, group_caster.id, "", group.id, 1, _zeros(8)); var group_events := group_cast.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal(group_events.map(func(event: DomainEvent) -> String: return String(event.payload.get("targetId"))), [group_caster.id, group_ally.id, group_first.id, group_second.id], "automatic group targets preserve party-before-monster order"); assert_equal(group_caster.spell_points, 18, "an automatic group spell charges its caster once")
	var cure := _condition_cure_spell("spell.heal-poison", 2206, 110); var cure_caster := _character("character.cure-caster"); cure_caster.set_known_spells([cure.id]); cure_caster.maximum_spell_attacks = 2; cure_caster.spell_points = 60; var cure_ally := _character("character.cure-ally"); cure_ally.conditions.set_value(ConditionRules.POISONED, 6); cure_ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1); var cure_monster := MonsterState.new("monster.cure-target", definition.id, definition.name, 20, 20, 1); cure_monster.conditions.set_value(ConditionRules.POISONED, 4)
	var cure_field := _blank_battlefield(); cure_field.place_character(cure_caster.id, Vector2i(45, 45)); cure_field.place_character(cure_ally.id, Vector2i(44, 45)); cure_field.place_monster(cure_monster.id, Vector2i(46, 45), 0); var cure_state := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [cure_caster, cure_ally]), RealmzClock.new()); cure_state.combat = CombatState.new("battle.cure", [cure_monster], 0, cure_field); cure_state.combat.set_turn_order([cure_caster.id, cure_ally.id, cure_monster.id]); var cure_content := _content([definition], [], [], [], [cure])
	assert_true(rules.combat_flow.character_spell_options(cure_state, cure_content, cure_caster.id).any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == cure.id), "the public combat picker admits the strict Classic condition-cure signature"); var cure_rng := _zeros(8); var cure_result := rules.combat_flow.cast_spell(cure_state, cure_content, cure_caster.id, "", cure.id, 2, cure_rng, CombatFlow.INVALID_COORDINATE, 0, [cure_ally.id, cure_monster.id]); var cure_events := cure_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved")
	assert_equal([cure_result.ok, cure_ally.conditions.value(ConditionRules.POISONED), cure_monster.conditions.value(ConditionRules.POISONED), cure_caster.spell_points], [true, 0, 0, 20], "a repeated Heal Poison clears both selected actor kinds and pays once"); assert_true(cure_events.all(func(event: DomainEvent) -> bool: return event.payload.get("clearedCondition") == ConditionRules.POISONED and event.payload.get("reflected") == false), "condition-cure events identify the cleared slot and bypass spell reflection"); assert_false(cure_rng.trace().any(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).contains("reflect")), "condition curing consumes no reflection draw")
	var cured_save := GameState.from_data(JSON.parse_string(JSON.stringify(cure_state.to_data()))); assert_equal([cured_save.party.character_by_id(cure_ally.id).conditions.value(ConditionRules.POISONED), cured_save.combat.monster_by_id(cure_monster.id).conditions.value(ConditionRules.POISONED)], [0, 0], "cleared character and monster conditions survive combat save restoration")
	var ray := _combat_spell("spell.ray", 6, 2); var ray_caster := _character("character.ray-caster"); ray_caster.set_known_spells([ray.id]); ray_caster.maximum_spell_attacks = 2; ray_caster.spell_points = 20; var ray_ally := _character("character.ray-ally"); ray_ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1); var ray_target := MonsterState.new("monster.ray-target", definition.id, definition.name, 20, 20, 1); var ray_state := _state(ray_caster, ray_target, "battle.ray"); ray_state.party.add_character(ray_ally); ray_state.combat.battlefield.move_actor(ray_target.id, Vector2i(48, 45)); ray_state.combat.battlefield.place_character(ray_ally.id, Vector2i(46, 45)); ray_state.combat.set_turn_order([ray_caster.id, ray_ally.id, ray_target.id]); var ray_rng := _zeros(12); var ray_result := rules.combat_flow.cast_spell(ray_state, _content([definition], [], [], [], [ray]), ray_caster.id, ray_target.id, ray.id, 1, ray_rng); var ray_events := ray_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved"); assert_equal([ray_result.ok, ray_ally.current_health, ray_target.current_health, ray_caster.spell_points, ray_events.map(func(event: DomainEvent) -> String: return String(event.payload.get("targetId")))], [true, 28, 18, 18, [ray_ally.id, ray_target.id]], "a type-six ray pays once and resolves each distinct encountered actor in source order, including friendly fire"); assert_false(ray_rng.trace().any(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).contains("reflect")), "Classic rays bypass ordinary spell reflection while resolving their encountered actors")
	var ray_case := ItemDefinition.new("item.ray-scroll-case", 800, "Scroll Case"); ray_case.item_type = 13; var ray_scroll_caster := _character("character.ray-scroll"); ray_scroll_caster.spell_points = 7; ray_scroll_caster.set_inventory([ItemInstance.new("instance.ray-scroll-case", ray_case.id, 0, true, true)]); ray_scroll_caster.write_scroll(0, ray.id, 1); var ray_scroll_ally := _character("character.ray-scroll-ally"); var ray_scroll_target := MonsterState.new("monster.ray-scroll-target", definition.id, definition.name, 20, 20, 1); var ray_scroll_state := _state(ray_scroll_caster, ray_scroll_target, "battle.ray-scroll"); ray_scroll_state.party.add_character(ray_scroll_ally); ray_scroll_state.combat.battlefield.move_actor(ray_scroll_target.id, Vector2i(48, 45)); ray_scroll_state.combat.battlefield.place_character(ray_scroll_ally.id, Vector2i(46, 45)); ray_scroll_state.combat.set_turn_order([ray_scroll_caster.id, ray_scroll_ally.id, ray_scroll_target.id]); var ray_scroll_result := rules.combat_flow.use_combat_scroll(ray_scroll_state, _content([definition], [ray_case], [], [], [ray]), ray_scroll_caster.id, 0, ray_scroll_target.id, _zeros(12)); var ray_item := ItemDefinition.new("item.ray-wand", 801, "Ray Wand"); ray_item.item_type = 21; ray_item.initial_charges = 2; ray_item.item_category_mask_low = 1; ray_item.special_1 = 1; ray_item.special_2 = ray.classic_id; var ray_race := RaceDefinition.new("race.test", 1, "Ray Race", [], [], [], [], [], [], []); ray_race.item_category_mask_low = 1; var ray_caste := CasteDefinition.new("caste.test", 1, "Ray Caste", [], [], [], [], Vector2i.ONE, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO); ray_caste.caste_class = 1; ray_caste.item_category_mask_low = 1; var ray_item_caster := _character("character.ray-item"); ray_item_caster.set_inventory([ItemInstance.new("instance.ray-wand", ray_item.id, 2, false, true)]); var ray_item_ally := _character("character.ray-item-ally"); var ray_item_target := MonsterState.new("monster.ray-item-target", definition.id, definition.name, 20, 20, 1); var ray_item_state := _state(ray_item_caster, ray_item_target, "battle.ray-item"); ray_item_state.party.add_character(ray_item_ally); ray_item_state.combat.battlefield.move_actor(ray_item_target.id, Vector2i(48, 45)); ray_item_state.combat.battlefield.place_character(ray_item_ally.id, Vector2i(46, 45)); ray_item_state.combat.set_turn_order([ray_item_caster.id, ray_item_ally.id, ray_item_target.id]); var ray_item_result := rules.combat_flow.use_spell_item(ray_item_state, _content([definition], [ray_item], [ray_race], [ray_caste], [ray]), ray_item_caster.id, ray_item_target.id, "instance.ray-wand", _zeros(12)); assert_equal([ray_scroll_result.ok, ray_scroll_ally.current_health, ray_scroll_target.current_health, ray_scroll_caster.spell_points, ray_scroll_caster.scroll_at(0).is_empty(), ray_item_result.ok, ray_item_ally.current_health, ray_item_target.current_health, ray_item_caster.inventory()[0].charges], [true, 28, 18, 7, true, true, 28, 18, 1], "scroll and charged-item rays reuse the source traversal, spend no caster spell points, and commit their source resource once")
	var summon := SpellDefinition.new("spell.creature-summon", 3502, "Creature Summon 4"); summon.in_combat = true; summon.target_type = 0; summon.special = 58; summon.spell_class = 0; summon.size = 1; summon.cost = 2; summon.range_min = 15; var summon_definition := MonsterDefinition.new("monster.summonable", 0, "Summoned Guardian", 4, 2, 6, 1, 10, _ints(8), _ints(8), _ints(6), _ints(3), [], [], [], []); summon_definition.can_summon = 1; summon_definition.size = 3
	var summon_caster := _character("character.summoner"); summon_caster.normal_attacks = 4; summon_caster.set_known_spells([summon.id]); summon_caster.maximum_spell_attacks = 2; summon_caster.spell_points = 20; var summon_opponent_definition := _monster_definition("monster.summon-opponent", []); var summon_state := _state(summon_caster, MonsterState.new("monster.summon-opponent.instance", summon_opponent_definition.id, summon_opponent_definition.name, 30, 30, 1, 1, 0, 0, 0, true), "battle.summon"); var summon_content := _content([summon_definition, summon_opponent_definition], [], [], [], [summon]); var summon_options := rules.combat_flow.character_spell_options(summon_state, summon_content, summon_caster.id); assert_true(summon_options.any(func(option: CombatSpellOptionView) -> bool: return option.spell_id == summon.id and option.target_mode == &"coordinate_sequence" and option.maximum_targets == 1), "Creature Summon remains visible and exposes an ordered open-space target contract")
	var invalid_summon_state := GameState.from_data(summon_state.to_data()); var invalid_before := invalid_summon_state.to_data(); var invalid_summon_rng := _zeros(16); var invalid_summon := rules.combat_flow.cast_spell(invalid_summon_state, summon_content, summon_caster.id, "", summon.id, 1, invalid_summon_rng, CombatFlow.INVALID_COORDINATE, 0, [], [Vector2i(45, 46)]); assert_equal([invalid_summon.error_code, invalid_summon_state.to_data(), invalid_summon_rng.snapshot().draw_count], [&"summon_footprint_unavailable", invalid_before, 0], "a source-selected footprint collision restores the complete combat and RNG transaction")
	var summon_rng := _zeros(24); var summoned_result := rules.combat_flow.cast_spell(summon_state, summon_content, summon_caster.id, "", summon.id, 1, summon_rng, CombatFlow.INVALID_COORDINATE, 0, [], [Vector2i(44, 46)]); var summoned_rows := summon_state.combat.monsters().filter(func(monster: MonsterState) -> bool: return monster.summoned); assert_equal([summoned_result.ok, summoned_rows.size(), summon_caster.spell_points, summon_state.combat.battlefield.actor_position(summoned_rows[0].id), summon_state.combat.battlefield.actor_size(summoned_rows[0].id), summoned_rows[0].traitor], [true, 1, 18, Vector2i(44, 46), 3, false], "manual Creature Summon selects, constructs, and places a loyal Classic monster while charging once"); assert_equal(summon_rng.trace().slice(0, 3).map(func(entry: Dictionary) -> String: return String(entry["tag"])), ["combat.summon.%s.selection.0" % summon.id, "monster.%s.stamina.0" % summoned_rows[0].id, "monster.%s.stamina.1" % summoned_rows[0].id], "summoning preserves the source selection-before-construction RNG order"); assert_true(summoned_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_summoned" and event.payload.get("monsterId") == summoned_rows[0].id), "manual summoning publishes the created instance and placement"); var summoned_save := GameState.from_data(JSON.parse_string(JSON.stringify(summon_state.to_data()))); assert_true(summoned_save.combat.monsters().any(func(monster: MonsterState) -> bool: return monster.summoned and monster.definition_id == summon_definition.id), "summoned provenance survives deterministic save restoration")
	var scroll_case := ItemDefinition.new("item.cure-scroll-case", 800, "Scroll Case"); scroll_case.item_type = 13; var scroll_caster := _character("character.cure-scroll"); scroll_caster.spell_points = 7; scroll_caster.set_inventory([ItemInstance.new("instance.cure-scroll-case", scroll_case.id, 0, true, true)]); assert_true(scroll_caster.write_scroll(0, cure.id, 1), "the combat scroll fixture records Heal Poison"); var scroll_target := _character("character.cure-scroll-target"); scroll_target.conditions.set_value(ConditionRules.POISONED, 3); var scroll_state := _state(scroll_caster, MonsterState.new("monster.cure-scroll-opponent", definition.id, definition.name, 20, 20, 1), "battle.cure-scroll"); scroll_state.party.add_character(scroll_target); scroll_state.combat.battlefield.place_character(scroll_target.id, Vector2i(44, 45)); scroll_state.combat.set_turn_order([scroll_caster.id, scroll_target.id, scroll_state.combat.monsters()[0].id]); var scroll_used := rules.combat_flow.use_combat_scroll(scroll_state, _content([definition], [scroll_case], [], [], [cure]), scroll_caster.id, 0, "", _zeros(8), CombatFlow.INVALID_COORDINATE, 0, [scroll_target.id])
	assert_equal([scroll_used.ok, scroll_target.conditions.value(ConditionRules.POISONED), scroll_caster.spell_points, scroll_caster.scroll_at(0).is_empty()], [true, 0, 7, true], "a combat scroll cures its target, spends no spell points, and commits the slot once"); var summon_scroll_caster := _character("character.summon-scroll"); summon_scroll_caster.normal_attacks = 4; summon_scroll_caster.spell_points = 7; summon_scroll_caster.set_inventory([ItemInstance.new("instance.summon-scroll-case", scroll_case.id, 0, true, true)]); assert_true(summon_scroll_caster.write_scroll(0, summon.id, 1), "the combat scroll fixture records Creature Summon"); var summon_scroll_state := _state(summon_scroll_caster, MonsterState.new("monster.summon-scroll-opponent", summon_opponent_definition.id, summon_opponent_definition.name, 30, 30, 1, 1, 0, 0, 0, true), "battle.summon-scroll"); var summon_scroll := rules.combat_flow.use_combat_scroll(summon_scroll_state, _content([summon_definition, summon_opponent_definition], [scroll_case], [], [], [summon]), summon_scroll_caster.id, 0, "", _zeros(24), CombatFlow.INVALID_COORDINATE, 0, [], [Vector2i(44, 46)]); assert_equal([summon_scroll.ok, summon_scroll_caster.spell_points, summon_scroll_caster.scroll_at(0).is_empty(), summon_scroll_state.combat.monsters().filter(func(monster: MonsterState) -> bool: return monster.summoned).size()], [true, 7, true, 1], "a Creature Summon scroll uses the same typed placement transaction without spending caster spell points")
	var pending_spell := _combat_spell("spell.pending-special", 1, 0); pending_spell.special = 31; pending_spell.damage_min = 0; pending_spell.damage_max = 0; var pending_caster := _character("character.pending-special"); pending_caster.set_known_spells([pending_spell.id]); pending_caster.maximum_spell_attacks = 1; pending_caster.spell_points = 20; var pending_state := _state(pending_caster, MonsterState.new("monster.pending-special", definition.id, definition.name, 20, 20, 1), "battle.pending-special"); var pending_probe := rules.combat_flow.probe_character_spell_cast(pending_state, _content([definition], [], [], [], [pending_spell]), pending_caster.id, pending_state.combat.monsters()[0].id, pending_spell.id, 1)
	assert_equal([ClassicSpellCapabilityCatalog.mechanical_family(pending_spell), ClassicSpellCapabilityCatalog.combat_character_disposition(pending_spell), pending_probe.allowed], [ClassicSpellCapabilityCatalog.FAMILY_SPECIAL_EFFECT, ClassicSpellCapabilityCatalog.DISPOSITION_PENDING, false], "the application capability catalog owns the unresolved combat-special disposition used by the public probe"); assert_true(pending_probe.reason_text.contains("special 31, target type 1"), "an unresolved known spell reports its exact Classic family parameters instead of disappearing into a generic no-op")
	assert_not_null(host_state, "the public host-boundary fixture restores before a typed combat response")
	if host_state != null:
		var host_api := RealmzRuntimeApi.new(group_content, host_state, _zeros(8), ScenarioActionState.new())
		var request_id := "request.group"
		var host_result := host_api.resume_classic(_classic_battle_continuation(host_state.combat.battle_id), InteractionResponse.from_data(request_id, InteractionRequest.COMBAT, {"actorId": group_caster.id, "action": "cast_spell", "targetId": "", "spellId": group.id, "power": 1}), request_id)
		assert_equal(host_result.state, ScenarioRuntimeOperationResult.State.WAITING, "RealmzRuntimeApi returns a typed combat response to the same battle request")


func _test_public_monster_turn_matrix() -> void:
	var rules := RealmzRules.new(); var attack_definition := _monster_definition("monster.public-attack", [MonsterAttackDefinition.new(1, 1), MonsterAttackDefinition.new(2, 2)]); var target := _character("character.public-monster-target"); var attacker := MonsterState.new("monster.public-attacker", attack_definition.id, attack_definition.name, 30, 30, 4)
	var attack_state := _state(target, attacker, "battle.public-monster-attack"); var attack_result := rules.combat_flow.submit_action(attack_state, _content([attack_definition]), target.id, &"finish", "", _zeros(24)); assert_true(attack_result.ok, "a public character command dispatches the private monster turn internally")
	var attack_events := attack_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_attack_resolved" and event.payload.get("actorId") == attacker.id); assert_equal(attack_events.size(), 2, "the public monster turn executes every authored attack row"); assert_equal(attack_events.map(func(event: DomainEvent) -> String: return String(event.payload.get("targetId"))), [target.id, target.id], "monster attack rows retain their selected target")

	var spell := _combat_spell("spell.monster-public", 1, 4); var caster_definition := _monster_spell_definition("monster.public-caster", spell.id, 100); var spell_caster := MonsterState.new("monster.public-caster.instance", caster_definition.id, caster_definition.name, 30, 30, 4, 1, 0, 0, 10)
	var spell_target := _character("character.public-spell-target"); var spell_state := _state(spell_target, spell_caster, "battle.public-monster-spell"); var spell_content := _content([caster_definition], [], [], [], [spell])
	var spell_rng := _zeros(20); var spell_result := rules.combat_flow.submit_action(spell_state, spell_content, spell_target.id, &"finish", "", spell_rng)
	assert_true(spell_result.ok, "a public finish command reaches the source-backed monster cast branch")
	var cast_events := spell_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("source") == "classic-monster")
	assert_equal(cast_events.size(), 1, "public monster casting publishes one typed resolution")
	if not cast_events.is_empty():
		assert_equal([cast_events[0].payload.get("targetId"), cast_events[0].payload.get("power"), cast_events[0].payload.get("rangePower")], [spell_target.id, 1, 1], "public monster casting preserves target and affordability/range power")
	assert_equal([spell_target.current_health, spell_caster.spell_points], [26, 8], "the public monster cast spends lowered power cost and applies its damage"); assert_true(not spell_rng.trace().is_empty() and spell_rng.trace()[0].get("tag") == "combat.monster.%s.action-choice" % spell_caster.id, "monster AI spends its first draw on the weighted action categories")
	var monster_heal := _combat_spell("spell.monster-heal", 1, 6); monster_heal.special = 57; monster_heal.spell_class = 8; monster_heal.damage_type = 8; monster_heal.cannot = 4; monster_heal.duration_min = 0; monster_heal.duration_max = 0
	var healer_definition := _monster_spell_definition("monster.public-healer", monster_heal.id, 40); var monster_healer := MonsterState.new("monster.public-healer.instance", healer_definition.id, healer_definition.name, 30, 30, 4, 1, 0, 0, 10); var hurt_ally := MonsterState.new("monster.public-hurt-ally", healer_definition.id, "Hurt Ally", 5, 30, 4)
	var monster_heal_state := _state(_character("character.public-heal-opponent"), monster_healer, "battle.public-monster-heal"); monster_heal_state.combat.add_monster(hurt_ally); monster_heal_state.combat.battlefield.place_monster(hurt_ally.id, Vector2i(47, 45), 0); monster_heal_state.combat.set_turn_order([monster_heal_state.party.characters()[0].id, monster_healer.id, hurt_ally.id])
	var monster_healed := rules.combat_flow.submit_action(monster_heal_state, _content([healer_definition], [], [], [], [monster_heal]), monster_heal_state.party.characters()[0].id, &"finish", "", _zeros(24))
	assert_true(monster_healed.ok and monster_healed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("targetId") == hurt_ally.id and int(event.payload.get("healing", 0)) > 0), "scored monster AI heals its critically wounded ally instead of taking an adjacent physical action")
	var monster_cure := _condition_cure_spell("spell.monster-cure", 2206, 110); var cure_definition := _monster_spell_definition("monster.public-cure", monster_cure.id, 40); var monster_curer := MonsterState.new("monster.public-curer.instance", cure_definition.id, cure_definition.name, 30, 30, 4, 1, 0, 0, 40); var poisoned_ally := MonsterState.new("monster.public-poisoned-ally", cure_definition.id, "Poisoned Ally", 30, 30, 4); poisoned_ally.conditions.set_value(ConditionRules.POISONED, 6); poisoned_ally.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1)
	var monster_cure_state := _state(_character("character.public-cure-opponent"), monster_curer, "battle.public-monster-cure"); monster_cure_state.combat.add_monster(poisoned_ally); monster_cure_state.combat.battlefield.place_monster(poisoned_ally.id, Vector2i(47, 45), 0); monster_cure_state.combat.set_turn_order([monster_cure_state.party.characters()[0].id, monster_curer.id, poisoned_ally.id]); var monster_cured := rules.combat_flow.submit_action(monster_cure_state, _content([cure_definition], [], [], [], [monster_cure]), monster_cure_state.party.characters()[0].id, &"finish", "", _zeros(24))
	assert_true(monster_cured.ok and monster_cured.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("targetId") == poisoned_ally.id and event.payload.get("clearedCondition") == ConditionRules.POISONED), "scored monster AI cures an afflicted reflecting ally instead of treating it as a hostile damage target"); assert_equal(poisoned_ally.conditions.value(ConditionRules.POISONED), 0, "monster condition curing commits to authoritative combat state")
	var monster_ray := _combat_spell("spell.monster-ray", 6, 2); var monster_ray_definition := _monster_spell_definition("monster.public-ray", monster_ray.id, 100); var monster_ray_caster := MonsterState.new("monster.public-ray.instance", monster_ray_definition.id, monster_ray_definition.name, 30, 30, 4, 1, 0, 0, 10); var monster_ray_first := _character("character.monster-ray-first"); var monster_ray_second := _character("character.monster-ray-second"); var monster_ray_state := _state(monster_ray_first, monster_ray_caster, "battle.monster-ray"); monster_ray_state.combat.battlefield.move_actor(monster_ray_first.id, Vector2i(47, 45)); monster_ray_state.combat.battlefield.move_actor(monster_ray_caster.id, Vector2i(45, 45)); monster_ray_state.party.add_character(monster_ray_second); monster_ray_state.combat.battlefield.place_character(monster_ray_second.id, Vector2i(48, 45)); monster_ray_state.combat.set_turn_order([monster_ray_first.id, monster_ray_caster.id, monster_ray_second.id]); var monster_ray_result := rules.combat_flow.submit_action(monster_ray_state, _content([monster_ray_definition], [], [], [], [monster_ray]), monster_ray_first.id, &"finish", "", _zeros(64)); var unsafe_monster_ray_caster := MonsterState.new("monster.unsafe-ray.instance", monster_ray_definition.id, monster_ray_definition.name, 30, 30, 4, 1, 0, 0, 10); var unsafe_monster_ray_target := _character("character.unsafe-monster-ray"); var unsafe_monster_ray_ally := MonsterState.new("monster.unsafe-ray-ally", monster_ray_definition.id, monster_ray_definition.name, 20, 20, 4); var unsafe_monster_ray_state := _state(unsafe_monster_ray_target, unsafe_monster_ray_caster, "battle.unsafe-monster-ray"); unsafe_monster_ray_state.combat.battlefield.move_actor(unsafe_monster_ray_target.id, Vector2i(48, 45)); unsafe_monster_ray_state.combat.battlefield.move_actor(unsafe_monster_ray_caster.id, Vector2i(45, 45)); unsafe_monster_ray_state.combat.add_monster(unsafe_monster_ray_ally); unsafe_monster_ray_state.combat.battlefield.place_monster(unsafe_monster_ray_ally.id, Vector2i(46, 45), 0); unsafe_monster_ray_state.combat.set_turn_order([unsafe_monster_ray_target.id, unsafe_monster_ray_caster.id, unsafe_monster_ray_ally.id]); var unsafe_monster_ray_result := rules.combat_flow.submit_action(unsafe_monster_ray_state, _content([monster_ray_definition], [], [], [], [monster_ray]), unsafe_monster_ray_target.id, &"finish", "", _zeros(64)); assert_equal([monster_ray_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("actorId") == monster_ray_caster.id).size(), monster_ray_first.current_health, monster_ray_second.current_health, monster_ray_caster.spell_points, unsafe_monster_ray_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("actorId") == unsafe_monster_ray_caster.id).size(), unsafe_monster_ray_target.current_health, unsafe_monster_ray_ally.current_health], [2, 28, 28, 8, 0, 30, 20], "monster AI resolves an ally-safe ray across both opposed actors and rejects a line intersecting its ally")

	var retry_definition := _monster_spell_definition("monster.public-retry", spell.id, 50); retry_definition.movement_max = 12; var retry_caster := MonsterState.new("monster.public-retry.instance", retry_definition.id, retry_definition.name, 30, 30, 4, 1, 0, 0, 10); var retry_target := _character("character.public-retry-target")
	var retry_state := _state(retry_target, retry_caster, "battle.public-retry"); retry_state.combat.battlefield.move_actor(retry_caster.id, Vector2i(47, 45))
	var retry_rng := ScriptedRng.new([32_767, 32_767, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]); var retry_result := rules.combat_flow.submit_action(retry_state, _content([retry_definition], [], [], [], [spell]), retry_target.id, &"finish", "", retry_rng)
	assert_true(retry_result.ok, "the public monster movement boundary reaches its bounded post-movement cast retry"); var retry_action_trace := retry_rng.trace().filter(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")) == "combat.monster.%s.action-choice" % retry_caster.id); assert_equal(retry_action_trace.size(), 1, "monster action weighting consumes one choice draw and retains that action for the activation"); assert_true(not retry_action_trace.is_empty() and retry_action_trace[0].get("result") == retry_action_trace[0].get("range"), "the low-weight advance category remains possible instead of always choosing the higher cast score"); assert_true(retry_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("source") == "classic-monster"), "the public retry path commits the later ordinary cast")


func _test_public_continuation_fumble_terminal_matrix() -> void:
	var rules := RealmzRules.new()
	var spell := _combat_spell("spell.queued-death", 1, 4)
	var definition := _monster_definition("monster.queued-death", [])
	definition.death_macro = 321
	var monster := MonsterState.new("monster.queued-death.instance", definition.id, definition.name, 4, 4, 1)
	var character := _character("character.queued-death")
	character.set_known_spells([spell.id])
	character.maximum_spell_attacks = 2
	character.spell_points = 10
	var state := _state(character, monster, "battle.queued-death")
	var content := _content([definition], [], [], [], [spell])
	var lethal := rules.combat_flow.cast_spell(state, content, character.id, monster.id, spell.id, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_true(lethal.ok, "a lethal public spell commits before its death macro is resumed")
	assert_equal(state.combat.spell_death_macro_queue(), [monster.id], "the public spell boundary owns the exact death-macro queue head")
	assert_true(lethal.events.any(func(event: DomainEvent) -> bool: return event.kind == &"monster_death_macro_requested" and event.payload.get("combatantId") == monster.id), "the queue head is the only dispatched macro")
	var restored := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_not_null(restored, "the death-macro queue and active-caster cursor survive save restoration")
	if restored != null:
		restored.combat.monster_by_id(monster.id).current_health = 1
		var resumed := rules.combat_flow.continue_after_monster_death_macro(restored, content, _zeros(16), monster.id)
		assert_true(resumed.ok, "the public continuation completes the saved macro cursor")
		assert_equal([restored.combat.spell_death_macro_queue(), restored.combat.active_actor_id()], [[], character.id], "macro completion clears only the saved head and returns to the issuing caster")

	var weapon := ItemDefinition.new("item.exact-fumble", 77, "Charged Blade")
	weapon.item_type = 2
	weapon.vs_small = 1
	weapon.initial_charges = 30
	weapon.weight = 2
	weapon.weight_per_charge = 1
	var fumbler := _character("character.exact-fumble")
	fumbler.maximum_load = 100
	fumbler.normal_attacks = 4
	var instance := rules.inventory.add_item(fumbler, weapon, "instance.exact-fumble", false)
	assert_not_null(instance, "the public fumble fixture grants its charged weapon")
	if instance != null:
		instance.charges = 7
		fumbler.carried_load = weapon.instance_weight(instance.charges)
		assert_true(rules.inventory.equip(fumbler, instance.id, weapon), "the public fumble fixture equips the weapon")
		var fumble_definition := _monster_definition("monster.fumble", [])
		var fumble_state := _state(fumbler, MonsterState.new("monster.fumble.instance", fumble_definition.id, fumble_definition.name, 100, 100, 1), "battle.fumble")
		var fumble_content := _content([fumble_definition], [weapon])
		var fumble := rules.combat_flow.submit_action(fumble_state, fumble_content, fumbler.id, &"attack", fumble_state.combat.monsters()[0].id, ScriptedRng.new([0, 0, 1609]))
		assert_true(fumble.ok, "the public attack boundary commits a fumble")
		assert_equal([fumbler.inventory().size(), fumble_state.combat.fumbled_items().size(), fumble_state.combat.fumbled_items()[0].charges], [0, 1, 7], "battle owns the exact fumbled instance and remaining charges")
		var fumble_save := GameState.from_data(JSON.parse_string(JSON.stringify(fumble_state.to_data())))
		assert_not_null(fumble_save, "the exact fumble instance survives state restoration")
		if fumble_save != null:
			fumble_save.combat.completed = true
			fumble_save.combat.outcome = &"retreated"
			var payload := rules.combat_flow.fumble_recovery_payload(fumble_save, fumble_content)
			assert_equal(payload.get("remaining"), 1, "the public recovery payload exposes the queued item once")
			var recovered := rules.combat_flow.apply_fumble_recovery(fumble_save, fumble_content, &"assign", instance.id, fumbler.id)
			assert_true(recovered.ok, "the public recovery command assigns the saved instance")
			assert_equal([fumble_save.party.character_by_id(fumbler.id).inventory()[0].charges, fumble_save.combat.fumbled_items().size()], [7, 0], "recovery restores the exact charge count and removes only that queue entry")

	var terminal_spell := _combat_spell("spell.terminal", 1, 4)
	var terminal_caster := _character("character.terminal")
	terminal_caster.set_known_spells([terminal_spell.id])
	terminal_caster.maximum_spell_attacks = 2
	terminal_caster.spell_points = 10
	var terminal_definition := _monster_definition("monster.terminal", [])
	var terminal_monster := MonsterState.new("monster.terminal.instance", terminal_definition.id, terminal_definition.name, 4, 4, 1)
	var terminal_state := _state(terminal_caster, terminal_monster, "battle.terminal")
	var terminal_content := _content([terminal_definition], [], [], [], [terminal_spell])
	var terminal_result := rules.combat_flow.cast_spell(terminal_state, terminal_content, terminal_caster.id, terminal_monster.id, terminal_spell.id, 1, ScriptedRng.new([0, 0, 32_767, 32_767]))
	assert_true(terminal_result.completed, "a lethal public cast completes the battle")
	assert_equal(terminal_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"battle_completed").size(), 1, "terminal combat publishes exactly one completion event")
	var after_terminal := rules.combat_flow.submit_action(terminal_state, terminal_content, terminal_caster.id, &"finish", "", ScriptedRng.new([]))
	assert_equal(after_terminal.error_code, &"no_active_battle", "a second public command cannot re-enter terminal combat")


func _test_public_command_automation_matrix() -> void:
	var rules := RealmzRules.new()
	var definition := _monster_definition("monster.commands", [])
	var actor := _character("character.delay")
	actor.normal_attacks = 2
	actor.attack_bonus = 1
	var following := _character("character.following")
	var monster := MonsterState.new("monster.commands.instance", definition.id, definition.name, 50, 50, 1)
	var state := _state(actor, monster, "battle.commands")
	state.party.add_character(following)
	state.combat.battlefield.place_character(following.id, Vector2i(45, 46))
	state.combat.set_turn_order([actor.id, following.id, monster.id])
	var content := _content([definition])
	assert_true(rules.combat_flow.probe_delay(state, actor.id).allowed, "Delay is exposed by the public command probe")
	var delayed := rules.combat_flow.submit_action(state, content, actor.id, &"delay", "", _zeros(8)); assert_true(delayed.ok, "Delay commits through the public command boundary")
	assert_equal([state.combat.active_actor_id(), actor.attacks_remaining], [following.id, 1], "Delay preserves the current-round tail and the carried half-attack")
	var delayed_save := GameState.from_data(JSON.parse_string(JSON.stringify(state.to_data())))
	assert_equal([delayed_save.combat.active_actor_id(), delayed_save.combat.turn_order()], [following.id, [following.id, monster.id, actor.id]], "save restoration retains the delayed actor cursor")

	var healer := _character("character.bandage")
	var bleeding := _character("character.bleeding")
	bleeding.current_health = -1
	var bandage_state := _state(healer, MonsterState.new("monster.bandage.instance", definition.id, definition.name, 50, 50, 1), "battle.bandage")
	bandage_state.party.add_character(bleeding)
	bandage_state.combat.battlefield.remove_character(bleeding.id)
	bandage_state.combat.set_turn_order([healer.id, bleeding.id, bandage_state.combat.monsters()[0].id])
	bandage_state.combat.set_character_bleeding(bleeding.id, true)
	assert_equal(rules.combat_flow.bandage_candidate_ids(bandage_state), [bleeding.id], "the public Bandage probe exposes only the actual bleeding recipient")
	assert_true(rules.combat_flow.probe_bandage(bandage_state, healer.id, bleeding.id).allowed, "Bandage is available through its public probe")
	var bandaged := rules.combat_flow.submit_action(bandage_state, _content([definition]), healer.id, &"bandage", bleeding.id, _zeros(8))
	assert_true(bandaged.ok and not bandage_state.combat.is_character_bleeding(bleeding.id), "the public Bandage command clears its selected recipient")

	var turner := _character("character.turn-undead")
	turner.set_ability_value(13, 100)
	var flags := _ints(8)
	flags[1] = 1
	var undead_definition := MonsterDefinition.new("monster.undead", 230, "Undead", 1, 0, 1, 0, 0, flags, _ints(8), _ints(6), _ints(3), [], [], [], [])
	undead_definition.can_summon = 1
	var undead := MonsterState.new("monster.undead.instance", undead_definition.id, undead_definition.name, 20, 20, 1)
	var undead_state := _state(turner, undead, "battle.turn-undead")
	var undead_content := _content([undead_definition])
	assert_true(rules.combat_flow.probe_turn_undead(undead_state, undead_content, turner.id).allowed, "Turn Undead is admitted by its public probe")
	var turned := rules.combat_flow.submit_action(undead_state, undead_content, turner.id, &"turn_undead", "", ScriptedRng.new([8192]))
	assert_true(turned.ok, "Turn Undead resolves through the public command boundary")
	assert_true(turned.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_turn_undead_resolved"), "Turn Undead publishes its source-owned result event")
	assert_true(undead_state.combat.has_used_turn_undead(turner.id), "Turn Undead records its once-per-battle use")

	var healing_spell := _combat_spell("spell.auto-heal", 1, 4); healing_spell.special = 57; healing_spell.spell_class = 8; healing_spell.damage_type = 8; healing_spell.cannot = 4; healing_spell.duration_min = 0; healing_spell.duration_max = 0; var auto_area := _combat_spell("spell.auto-area", 4, 10)
	var auto_healer := _character("character.auto-healer"); auto_healer.set_known_spells([healing_spell.id, auto_area.id]); auto_healer.maximum_spell_attacks = 2; auto_healer.spell_points = 20
	var wounded := _character("character.auto-wounded"); wounded.current_health = 5
	var healing_state := _state(auto_healer, MonsterState.new("monster.auto-healing.instance", definition.id, definition.name, 100, 100, 1), "battle.auto-healing")
	healing_state.party.add_character(wounded); healing_state.combat.battlefield.place_character(wounded.id, Vector2i(44, 45)); healing_state.combat.set_turn_order([auto_healer.id, wounded.id, healing_state.combat.monsters()[0].id])
	var weighted_high_state := GameState.from_data(healing_state.to_data()); var healing_content := _content([definition], [], [], [], [healing_spell, auto_area]); var healed := rules.combat_flow.submit_action(healing_state, healing_content, auto_healer.id, &"auto", "", _zeros(96))
	assert_true(healed.ok and healed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("targetId") == wounded.id and int(event.payload.get("healing", 0)) > 0), "scored Auto heals a critically wounded ally before taking an adjacent attack")
	var high_values := _ints(96); high_values[0] = 32_767; var weighted_high := rules.combat_flow.submit_action(weighted_high_state, healing_content, auto_healer.id, &"auto", "", ScriptedRng.new(high_values)); var high_actions := weighted_high.events.filter(func(event: DomainEvent) -> bool: return event.payload.get("actorId") == auto_healer.id and event.kind in [&"combat_spell_resolved", &"combat_attack_resolved"]); assert_true(weighted_high.ok and not high_actions.is_empty() and high_actions[0].kind == &"combat_attack_resolved", "the lower-weight melee category remains possible instead of always choosing the stronger healing score")
	var auto_cure := _condition_cure_spell("spell.auto-cure", 2206, 110); var auto_curer := _character("character.auto-curer"); auto_curer.set_known_spells([auto_cure.id]); auto_curer.maximum_spell_attacks = 2; auto_curer.spell_points = 40; var auto_poisoned := _character("character.auto-poisoned"); auto_poisoned.conditions.set_value(ConditionRules.POISONED, 7); auto_poisoned.conditions.set_value(ConditionRules.REFLECTING_SPELLS, -1)
	var auto_cure_state := _state(auto_curer, MonsterState.new("monster.auto-cure-opponent", definition.id, definition.name, 100, 100, 1), "battle.auto-cure"); auto_cure_state.party.add_character(auto_poisoned); auto_cure_state.combat.battlefield.place_character(auto_poisoned.id, Vector2i(44, 45)); auto_cure_state.combat.set_turn_order([auto_curer.id, auto_poisoned.id, auto_cure_state.combat.monsters()[0].id]); var auto_cured := rules.combat_flow.submit_action(auto_cure_state, _content([definition], [], [], [], [auto_cure]), auto_curer.id, &"auto", "", _zeros(96))
	assert_true(auto_cured.ok and auto_cured.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("targetId") == auto_poisoned.id and event.payload.get("clearedCondition") == ConditionRules.POISONED), "Party Auto scores and casts a legal cure for an afflicted ally"); assert_equal(auto_poisoned.conditions.value(ConditionRules.POISONED), 0, "Party Auto condition curing commits to authoritative state")
	var auto_summon_spell := SpellDefinition.new("spell.auto-summon", 3502, "Creature Summon 4"); auto_summon_spell.in_combat = true; auto_summon_spell.target_type = 0; auto_summon_spell.special = 58; auto_summon_spell.spell_class = 17; auto_summon_spell.size = 1; auto_summon_spell.cost = 2; auto_summon_spell.range_min = 15; var auto_summon_definition := MonsterDefinition.new("monster.auto-summonable", 17, "Summoned Guardian", 4, 2, 6, 1, 10, _ints(8), _ints(8), _ints(6), _ints(3), [], [], [], []); auto_summon_definition.can_summon = 1; auto_summon_definition.size = 3
	var auto_summoner := _character("character.auto-summoner"); auto_summoner.normal_attacks = 4; auto_summoner.set_known_spells([auto_summon_spell.id]); auto_summoner.maximum_spell_attacks = 2; auto_summoner.spell_points = 20; var auto_summon_state := _state(auto_summoner, MonsterState.new("monster.auto-summon-opponent", definition.id, definition.name, 100, 100, 1), "battle.auto-summon"); auto_summon_state.combat.battlefield.move_actor("monster.auto-summon-opponent", Vector2i(50, 45)); var auto_summoned := rules.combat_flow.submit_action(auto_summon_state, _content([auto_summon_definition, definition], [], [], [], [auto_summon_spell]), auto_summoner.id, &"auto", "", _zeros(192))
	assert_true(auto_summoned.ok and auto_summoned.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_summoned" and event.payload.get("actorId") == auto_summoner.id) and auto_summon_state.combat.monsters().filter(func(monster: MonsterState) -> bool: return monster.summoned).size() == 1, "weighted Party Auto chooses one legal summon placement without repeatedly summoning after gaining the force advantage")
	var auto_ray := _combat_spell("spell.auto-ray", 6, 2); var auto_ray_caster := _character("character.auto-ray"); auto_ray_caster.set_known_spells([auto_ray.id]); auto_ray_caster.maximum_spell_attacks = 2; auto_ray_caster.spell_points = 20; var auto_ray_first := MonsterState.new("monster.auto-ray-first", definition.id, definition.name, 20, 20, 1); var auto_ray_second := MonsterState.new("monster.auto-ray-second", definition.id, definition.name, 20, 20, 1); var auto_ray_state := _state(auto_ray_caster, auto_ray_second, "battle.auto-ray"); auto_ray_state.combat.battlefield.move_actor(auto_ray_second.id, Vector2i(48, 45)); auto_ray_state.combat.add_monster(auto_ray_first); auto_ray_state.combat.battlefield.place_monster(auto_ray_first.id, Vector2i(47, 45), 0); auto_ray_state.combat.set_turn_order([auto_ray_caster.id, auto_ray_first.id, auto_ray_second.id]); var auto_ray_result := rules.combat_flow.submit_action(auto_ray_state, _content([definition], [], [], [], [auto_ray]), auto_ray_caster.id, &"auto", "", _zeros(64)); var unsafe_ray_caster := _character("character.unsafe-auto-ray"); unsafe_ray_caster.set_known_spells([auto_ray.id]); unsafe_ray_caster.maximum_spell_attacks = 2; unsafe_ray_caster.spell_points = 20; var unsafe_ray_ally := _character("character.unsafe-ray-ally"); var unsafe_ray_first := MonsterState.new("monster.unsafe-ray-first", definition.id, definition.name, 20, 20, 1); var unsafe_ray_second := MonsterState.new("monster.unsafe-ray-second", definition.id, definition.name, 20, 20, 1); var unsafe_ray_state := _state(unsafe_ray_caster, unsafe_ray_second, "battle.unsafe-auto-ray"); unsafe_ray_state.party.add_character(unsafe_ray_ally); unsafe_ray_state.combat.battlefield.move_actor(unsafe_ray_second.id, Vector2i(48, 45)); unsafe_ray_state.combat.battlefield.place_character(unsafe_ray_ally.id, Vector2i(46, 45)); unsafe_ray_state.combat.add_monster(unsafe_ray_first); unsafe_ray_state.combat.battlefield.place_monster(unsafe_ray_first.id, Vector2i(47, 45), 0); unsafe_ray_state.combat.set_turn_order([unsafe_ray_caster.id, unsafe_ray_ally.id, unsafe_ray_first.id, unsafe_ray_second.id]); var unsafe_ray_result := rules.combat_flow.submit_action(unsafe_ray_state, _content([definition], [], [], [], [auto_ray]), unsafe_ray_caster.id, &"auto", "", _zeros(128)); assert_equal([auto_ray_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("actorId") == auto_ray_caster.id).size(), auto_ray_first.current_health, auto_ray_second.current_health, unsafe_ray_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_spell_resolved" and event.payload.get("actorId") == unsafe_ray_caster.id).size(), unsafe_ray_ally.current_health], [2, 18, 18, 0, 30], "Party Auto scores an ally-safe multi-enemy ray but refuses the same endpoint when an ally intersects it")

	var auto_actor := _character("character.auto"); var auto_monster := MonsterState.new("monster.auto.instance", definition.id, definition.name, 1000, 1000, 1); var auto_state := _state(auto_actor, auto_monster, "battle.auto")
	var auto_traffic := _character("character.auto-traffic"); auto_state.party.add_character(auto_traffic); auto_state.combat.battlefield.place_character(auto_traffic.id, Vector2i(47, 44)); auto_state.combat.set_turn_order([auto_actor.id, auto_traffic.id, auto_monster.id]); auto_state.combat.battlefield.move_actor(auto_monster.id, Vector2i(49, 45)); auto_state.combat.battlefield.set_terrain(Vector2i(46, 45), 2); auto_state.combat.battlefield.set_terrain(Vector2i(44, 44), 2)
	var auto_rng := _zeros(256); var auto_result := rules.combat_flow.submit_action(auto_state, _content([definition]), auto_actor.id, &"auto", "", auto_rng); assert_true(auto_result.ok, "Auto Turn resolves through the public command boundary"); assert_equal(auto_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combat_auto_started").size(), 1, "Auto Turn starts exactly one bounded activation")
	var auto_moves := auto_result.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"combatant_moved"); assert_true(auto_moves.map(func(event: DomainEvent) -> Variant: return event.payload.get("to")).has([46, 44]) and not auto_rng.trace().any(func(entry: Dictionary) -> bool: return String(entry.get("tag", "")).contains(".shift.")), "Auto takes the deterministic legal detour before spending bounded shifted retries"); assert_true(auto_result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("source") == "classic-combat-auto-button"), "the public Auto command retains its button feedback")
	var bounded_actor := _character("character.auto-bounded"); bounded_actor.current_health = 32_767; bounded_actor.maximum_health = 32_767; var bounded_monster := MonsterState.new("monster.auto-bounded.instance", definition.id, definition.name, 32_767, 32_767, 1); var bounded_state := _state(bounded_actor, bounded_monster, "battle.auto-bounded"); assert_true(bounded_state.set_combat_auto(bounded_actor.id, true), "persistent Auto can be enabled through save-owned state")
	var bounded_rng := RealmzRng.new(17); var bounded_result := rules.combat_flow.submit_action(bounded_state, _content([definition]), bounded_actor.id, &"auto", "", bounded_rng); assert_true(bounded_result.ok, "persistent Auto commits one bounded activation")
	assert_equal([bounded_state.combat.round_number, bounded_state.combat.active_actor_id(), bounded_monster.current_health, bounded_rng.snapshot().draw_count], [2, bounded_actor.id, 32_766, 6], "persistent Auto yields after one activation so the host can interrupt before continuing")

	var undo_actor := _character("character.undo"); var undo_monster := MonsterState.new("monster.undo.instance", definition.id, definition.name, 100, 100, 1)
	var undo_state := _state(undo_actor, undo_monster, "battle.undo")
	undo_state.combat.battlefield.move_actor(undo_monster.id, Vector2i(50, 45))
	assert_true(rules.combat_flow.move_character(undo_state, _content([definition]), undo_actor.id, Vector2i(46, 45), ScriptedRng.new([])).ok, "movement establishes the public Undo boundary")
	assert_true(rules.combat_flow.probe_undo(undo_state, undo_actor.id).allowed, "Undo remains available after movement without a combat result")
	var undone := rules.combat_flow.submit_action(undo_state, _content([definition]), undo_actor.id, &"undo", "", ScriptedRng.new([]))
	assert_true(undone.ok, "Undo re-enters the activation through submit_action")
	assert_equal([undo_state.combat.battlefield.actor_position(undo_actor.id), rules.combat_flow.probe_undo(undo_state, undo_actor.id).allowed], [Vector2i(45, 45), false], "Undo restores the captured start cell and disables replay")


func _character(character_id: String) -> CharacterState:
	var result := CharacterState.new(character_id, "Combat Test Hero", 30, 30)
	result.race_id = "race.test"; result.caste_id = "caste.test"; result.luck = 1; result.hand_to_hand = 1
	result.normal_attacks = 2; result.maximum_movement = 12; result.movement = 12
	return result


func _monster_definition(definition_id: String, attacks: Array[MonsterAttackDefinition]) -> MonsterDefinition:
	return MonsterDefinition.new(definition_id, 1, "Combat Test Monster", 1, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), [], [], attacks)


func _monster_spell_definition(definition_id: String, spell_id: String, cast_percent: int) -> MonsterDefinition:
	var slots: Array[String] = [spell_id, "", "", "", "", "", "", "", "", ""]
	var result := MonsterDefinition.new(definition_id, 9, "Combat Test Caster", 4, 0, 1, 0, 0, _ints(8), _ints(8), _ints(6), _ints(3), slots, [], [])
	result.magic_attack_count = 1; result.cast_percent = cast_percent; result.missile_percent = 0; result.movement_max = 0
	return result


func _combat_spell(spell_id: String, target_type: int, damage: int) -> SpellDefinition:
	var result := SpellDefinition.new(spell_id, 1306, "Combat Test Spell")
	result.in_combat = true
	result.target_type = target_type
	result.spell_class = 1
	result.damage_type = 1
	result.cannot = 3
	result.cost = 2
	result.range_min = 15
	result.duration_min = 1
	result.duration_max = 1
	result.damage_min = damage
	result.damage_max = damage
	return result


func _condition_cure_spell(spell_id: String, classic_id: int, special: int) -> SpellDefinition:
	var result := SpellDefinition.new(spell_id, classic_id, "Condition Cure")
	result.in_combat = true; result.target_type = 0; result.spell_class = 8; result.damage_type = 8; result.cannot = 3; result.cost = 20; result.range_min = 15; result.special = special
	return result


func _classic_battle_continuation(battle_id: String) -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuation.combat(ScenarioRuntimeContinuation.CLASSIC_COMBAT, battle_id, ScenarioBattleCaller.classic(2, false, 0, 0))


func _state(character: CharacterState, monster: MonsterState, battle_id: String) -> GameState:
	var result := GameState.new(PartyState.new("map.test", Vector2i.ZERO, [character]), RealmzClock.new())
	var battlefield := _blank_battlefield()
	battlefield.place_character(character.id, Vector2i(45, 45))
	battlefield.place_monster(monster.id, Vector2i(46, 45), 0)
	result.combat = CombatState.new(battle_id, [monster], 0, battlefield)
	result.combat.set_turn_order([character.id, monster.id])
	return result


func _content(monsters: Array[MonsterDefinition], items: Array[ItemDefinition] = [], races: Array[RaceDefinition] = [], castes: Array[CasteDefinition] = [], spells: Array[SpellDefinition] = []) -> RealmzContent:
	return RealmzContent.new("campaign.combat-test", "0".repeat(64), "combat-test", "realmz-classic-1", "map.test", Vector2i(45, 45), _battle_world(), ScenarioDefinition.new([], []), [], [], [], races, castes, items, spells, monsters)


func _blank_battlefield() -> BattlefieldState:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	return BattlefieldState.new("map.test", tiles)


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
		terrain_tiles.append(BattleTerrainTileDefinition.new(tile, 0, 0, 1 if tile == 2 else 0, false, 0, false, false, false, 0, [[tile, tile, tile], [tile, tile, tile], [tile, tile, tile]]))
	var terrain_set := BattleTerrainSetDefinition.new("terrain.test", 1, 1, terrain_tiles)
	var map := MapDefinition.new("map.test", "Combat Test Map", &"land", 0, MapTopology.new(90, 90, cells), false, false, 1, [], terrain_set.id)
	_cached_battle_world = WorldDefinition.new([map], [], [terrain_set])
	return _cached_battle_world


func _ints(count: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(count)
	result.fill(0)
	return result


func _zeros(count: int) -> ScriptedRng:
	return ScriptedRng.new(_ints(count))
