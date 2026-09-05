## Plans deterministic, legal spell use and action categories for monsters.

class_name CombatMonsterActionPlanner
extends CombatAiScoringSupport

func choose_monster_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, rng: RealmzRng, allow_missile: bool = true) -> StringName:
	if monster.conditions.is_active(ConditionRules.RUNS_AWAY):
		return &"retreat"
	var adjacent := not _hostile_adjacent_ids_for_monster(state, monster).is_empty()
	var choices: Array[Dictionary] = [{"action": &"advance", "score": 560 if adjacent else 100}]
	var spell_plan := best_monster_spell_plan(state, content, monster, definition)
	var cast_score := int(spell_plan.get("score", -1)) + definition.cast_percent
	if not spell_plan.is_empty() and cast_score > 0:
		choices.append({"action": &"cast", "score": cast_score})
	if allow_missile and not adjacent and definition.missile_percent > 0 and not definition.item_id_at(1).is_empty():
		var missile_score := 250 + definition.missile_percent * 2
		if missile_score > 0:
			choices.append({"action": &"missile", "score": missile_score})
	var selected := _weighted_choice(choices, rng, StringName("combat.monster.%s.action-choice" % monster.id))
	return StringName(selected.get("action", &"advance"))


func best_monster_spell_plan(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition) -> Dictionary:
	if state.monster_spellcasting_blocked or state.combat.actor_statuses.was_attacked(monster.id) or definition.magic_attack_count <= 0:
		return {}
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if monster.conditions.is_active(condition):
			return {}
	var best: Dictionary = {}
	var actors_by_cell := _actors_by_cell(state.combat.battlefield)
	var area_placement_cache: Dictionary = {}
	var area_center_cache: Dictionary = {}
	for slot: int in 10:
		var spell := content.magic.spell_by_id(definition.spell_id_at(slot))
		if spell == null or not _context.automation().monster_spell_unavailable_reason(spell).is_empty():
			continue
		if spell.target_type != 12 and not _auto_group_target_is_safe(spell):
			continue
		if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not state.combat.spell_runtime.can_queue_persistent_field():
			continue
		var maximum_power := 1 if ClassicSpellSourceRules.is_combat_application_elemental_attack(spell) else 7 if spell.cost == 0 else mini(7, monster.spell_points / spell.cost)
		for power: int in range(1, maximum_power + 1):
			var plan := _monster_spell_power_plan(state, content, monster, definition, spell, slot, power, actors_by_cell, area_placement_cache, area_center_cache)
			best = _prefer(best, plan)
	return best


func _monster_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, slot: int, power: int, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary) -> Dictionary:
	if ClassicSpellSourceRules.is_inert_self_duration_effect(spell):
		return {}
	if CombatFlowSummoning.is_summon_spell(spell):
		return _monster_summon_spell_power_plan(state, content, monster, spell, slot, power)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
		return _monster_destroy_magic_plan(state, content, monster, spell, slot, power)
	if ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell):
		return {}
	if ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell) and spell.target_type == 1:
		return _monster_polymorph_plan(state, content, monster, spell, slot, power)
	if spell.target_type in [3, 4]:
		return _monster_area_spell_power_plan(state, content, monster, definition, spell, slot, power, actors_by_cell, area_placement_cache, area_center_cache)
	if spell.target_type == 6:
		return _monster_ray_spell_power_plan(state, content, monster, spell, slot, power)
	if spell.target_type in [9, 10, 12]:
		return _monster_group_spell_power_plan(state, content, monster, spell, slot, power, spell.target_type == 9)
	var cure_index := MagicRules.condition_cure_index(spell) if MagicRules.is_condition_cure_spell(spell) else -1
	var effect_index := ClassicSpellConditionRules.combat_condition_effect_index(spell)
	if effect_index < 0:
		effect_index = ClassicSpellConditionRules.combat_persistent_field_condition_index(spell)
	var spell_point_restore := ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell)
	var spell_point_drain := ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell)
	var friendly := spell.target_type == 5 or spell.cannot == 4 or cure_index >= 0 or spell_point_restore
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and (character.traitor == monster.traitor) == friendly and (spell.target_type != 5 or character.id == monster.id) and (not spell_point_restore or _target_missing_spell_points(state, character.id) > 0) and (not spell_point_drain or _target_spell_points(state, character.id) > 0) and (cure_index < 0 or character.conditions.is_active(cure_index)) and (effect_index < 0 or character.conditions.value(effect_index) == 0) and (cure_index >= 0 or character.id == monster.id or not _target_reflects(state, character.id)) and (friendly or not _target_hard_immune(state, content, character.id, spell)) and state.combat.battlefield.actors.has_actor(character.id) and _context.magic_flow().selection().spell_actor_target_is_valid(state, content, monster.id, character.id, spell, power):
			candidates.append(character.id)
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.current_health > 0 and (candidate.traitor == monster.traitor) == friendly and (spell.target_type != 5 or candidate.id == monster.id) and (not spell_point_restore or _target_missing_spell_points(state, candidate.id) > 0) and (not spell_point_drain or _target_spell_points(state, candidate.id) > 0) and (cure_index < 0 or candidate.conditions.is_active(cure_index)) and (effect_index < 0 or candidate.conditions.value(effect_index) == 0) and (cure_index >= 0 or candidate.id == monster.id or not _target_reflects(state, candidate.id)) and (friendly or not _target_hard_immune(state, content, candidate.id, spell)) and state.combat.battlefield.actors.has_actor(candidate.id) and content.combat.monster_by_id(candidate.definition_id) != null and _context.magic_flow().selection().spell_actor_target_is_valid(state, content, monster.id, candidate.id, spell, power):
			candidates.append(candidate.id)
	if candidates.is_empty():
		return {}
	var healing: bool = _context.automation().is_source_backed_combat_healing_spell(spell)
	var target_scores: Dictionary = {}
	for target_id: String in candidates:
		target_scores[target_id] = _monster_target_score(state, target_id, spell, power, healing, cure_index, effect_index)
	candidates.sort_custom(func(left: String, right: String) -> bool: return int(target_scores[left]) > int(target_scores[right]) or (target_scores[left] == target_scores[right] and left < right))
	var selected: Array[String] = []
	for target_id: String in candidates:
		if selected.size() >= (power if spell.target_type == 0 else 1):
			break
		if cure_index >= 0 or spell_point_restore or spell_point_drain or not healing or _target_missing_health(state, target_id) > 0:
			selected.append(target_id)
	if selected.is_empty():
		return {}
	var score := 0
	for target_id: String in selected:
		score += _monster_target_score(state, target_id, spell, power, healing, cure_index, effect_index)
	return {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": selected, "score": score - spell.cost * power * 3}


func _monster_summon_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int) -> Dictionary:
	var coordinate: Vector2i = _context.summoning().automatic_monster_coordinate(state, content, monster, spell, power)
	if coordinate == INVALID_COORDINATE:
		return {}
	var friendly_count := 0
	var hostile_count := 0
	var allied_summon_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id):
			if character.traitor == monster.traitor: friendly_count += 1
			else: hostile_count += 1
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.current_health <= 0 or not state.combat.battlefield.actors.has_actor(candidate.id):
			continue
		if candidate.traitor == monster.traitor:
			friendly_count += 1
			if candidate.summoned: allied_summon_count += 1
		else:
			hostile_count += 1
	if hostile_count <= 0 or friendly_count > hostile_count or allied_summon_count >= maxi(1, hostile_count - friendly_count + 1):
		return {}
	return {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [], "targetCoordinates": [coordinate], "score": 400 + (hostile_count - friendly_count) * 120 + hostile_count * 20 - spell.cost * power * 3}


func _monster_destroy_magic_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int) -> Dictionary:
	var candidates := _destroy_magic_candidates(state, content, monster.id, monster.traitor, spell, power)
	if candidates.is_empty():
		return {}
	var selected: Array[String] = []
	for target_id: String in candidates:
		if selected.size() >= power:
			break
		selected.append(target_id)
	var score := 0
	for target_id: String in selected:
		score += _destroy_magic_target_score(state, monster.traitor, target_id)
	return {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": selected, "score": score - spell.cost * power * 3}


func _monster_polymorph_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target: MonsterState in state.combat.roster.monsters():
		if target.current_health <= 0 or target.traitor == monster.traitor or not state.combat.battlefield.actors.has_actor(target.id) or _target_reflects(state, target.id) or _target_hard_immune(state, content, target.id, spell) or not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, monster.id, target.id, spell, power):
			continue
		best = _prefer(best, {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [target.id], "score": 440 + target.hit_dice * 20 + target.current_health - spell.cost * power * 3})
	return best


func _monster_group_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int, friendly: bool) -> Dictionary:
	var target_ids := _everybody_actor_ids(state) if spell.target_type == 12 else _friendly_actor_ids_for_monster(state, monster) if friendly else _opposed_actor_ids_for_monster(state, monster)
	var condition_index := ClassicSpellConditionRules.combat_condition_effect_index(spell)
	var effective_target_count := 0
	var effective_target_balance := 0
	for target_id: String in target_ids:
		if not _target_hard_immune(state, content, target_id, spell) and (condition_index < 0 or _target_condition_value(state, target_id, condition_index) == 0):
			effective_target_count += 1
			effective_target_balance += -1 if _actor_is_friendly_to_monster(state, monster, target_id) else 1
	if effective_target_count == 0 or spell.target_type == 12 and effective_target_balance <= 0:
		return {}
	var expected := expected_spell_effect(spell, power)
	if condition_index >= 0:
		expected = maxi(1, _maximum_condition_duration(spell, power))
	var score := 340 + (effective_target_balance if spell.target_type == 12 else effective_target_count) * expected * 5 - spell.cost * power * 3
	return {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": target_ids, "score": score}


func _monster_area_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, slot: int, power: int, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary) -> Dictionary:
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not state.combat.spell_runtime.can_queue_persistent_field():
		return {}
	var expected := expected_spell_effect(spell, power)
	var condition_index := ClassicSpellConditionRules.combat_persistent_field_condition_index(spell)
	var monster_targets_only := ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell)
	if monster_targets_only: expected = 10
	if expected <= 0 and condition_index < 0:
		return {}
	expected = maxi(expected, _maximum_condition_duration(spell, power)) if condition_index >= 0 else expected
	var maximum_range := absi(spell.range_min + spell.range_max * power) + (1 if definition.size != 0 else 0) + (1 if definition.size == 3 else 0)
	var rotations: Array = _context.spell_areas.rotation_patterns(spell, power)
	var best: Dictionary = {}
	for rotation: int in rotations.size():
		var offsets: Array[Vector2i] = []
		offsets.assign(rotations[rotation])
		var shape := _context.spell_areas.shape_for(spell, power, rotation)
		var cache_key := "%d:%d:%d:%d:%d:%d" % [shape, maximum_range, 1 if spell.range_min + spell.range_max > 0 else 0, spell.spell_class, condition_index, 1 if monster_targets_only else 0]
		if not area_placement_cache.has(cache_key):
			var placements: Array[Dictionary] = []
			var center_key := "%d:%d:%d" % [shape, maximum_range, 1 if spell.range_min + spell.range_max > 0 else 0]
			if not area_center_cache.has(center_key):
				area_center_cache[center_key] = _monster_area_candidate_centers(state, content, monster, shape, offsets, maximum_range, spell.range_min + spell.range_max > 0)
			for center: Vector2i in area_center_cache[center_key]:
				var hostile_ids: Dictionary = {}
				var harms_friend := false
				for offset: Vector2i in offsets:
					var target_id := String(actors_by_cell.get(center + offset, ""))
					if target_id.is_empty():
						continue
					if monster_targets_only and state.combat.roster.monster_by_id(target_id) == null:
						continue
					if _actor_is_friendly_to_monster(state, monster, target_id):
						harms_friend = true
					elif _target_reflects(state, target_id):
						harms_friend = true
					elif not _target_hard_immune(state, content, target_id, spell) and (condition_index < 0 or _target_condition_value(state, target_id, condition_index) == 0):
						hostile_ids[target_id] = true
				if not harms_friend and not hostile_ids.is_empty():
					placements.append({"center": center, "hostileCount": hostile_ids.size()})
			area_placement_cache[cache_key] = placements
		for placement: Dictionary in area_placement_cache[cache_key]:
			var score := 370 + int(placement["hostileCount"]) * maxi(1, expected) * 7 - spell.cost * power * 3
			best = _prefer(best, {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [], "coordinate": placement["center"], "rotation": rotation, "score": score})
	return best


func _monster_area_candidate_centers(state: GameState, content: RealmzContent, monster: MonsterState, shape: int, offsets: Array[Vector2i], maximum_range: int, require_line_of_sight: bool) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for target_id: String in _opposed_actor_ids_for_monster(state, monster):
		for target_cell: Vector2i in state.combat.battlefield.actors.actor_footprint(target_id):
			for offset: Vector2i in offsets:
				unique[target_cell - offset] = true
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null:
		return []
	var result: Array[Vector2i] = []
	for value: Variant in unique:
		var center: Vector2i = value
		if _context.spell_areas.pattern_fits(center, shape) and _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, monster.id, center, maximum_range, require_line_of_sight):
			result.append(center)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or (left.y == right.y and left.x < right.x))
	return result


func _monster_ray_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int) -> Dictionary:
	var expected := expected_spell_effect(spell, power)
	if expected <= 0:
		return {}
	var best: Dictionary = {}
	for endpoint_id: String in _opposed_actor_ids_for_monster(state, monster):
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, monster.id, endpoint_id, spell, power):
			continue
		var ray_ids: Array[String] = _context.magic_flow().ray_spell_actor_ids(state, content, monster.id, endpoint_id, spell)
		if ray_ids.is_empty() or ray_ids.any(func(target_id: String) -> bool: return _actor_is_friendly_to_monster(state, monster, target_id) or _target_hard_immune(state, content, target_id, spell)):
			continue
		var drain := ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell)
		var score := 340 - spell.cost * power * 3
		for target_id: String in ray_ids:
			score += mini(_target_spell_points(state, target_id), expected) * 6 if drain else expected * 6 + _lethal_bonus(state, target_id, expected)
		if drain and ray_ids.all(func(target_id: String) -> bool: return _target_spell_points(state, target_id) <= 0):
			continue
		best = _prefer(best, {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [endpoint_id], "score": score})
	return best


func _monster_target_score(state: GameState, target_id: String, spell: SpellDefinition, power: int, healing: bool, cure_index: int = -1, effect_index: int = -1) -> int:
	var expected := expected_spell_effect(spell, power)
	if ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell):
		return 620 + mini(_target_missing_spell_points(state, target_id), expected) * 5 + _target_missing_spell_points(state, target_id)
	if ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell):
		return 540 + mini(_target_spell_points(state, target_id), expected) * 6 + _target_spell_points(state, target_id)
	if cure_index >= 0:
		return _condition_cure_score(state, target_id, cure_index)
	if effect_index >= 0:
		if spell.target_type == 5 or spell.cannot == 4:
			return 520 + _maximum_condition_duration(spell, power) * 8
		return 420 + expected * 5 + _lethal_bonus(state, target_id, expected) + _maximum_condition_duration(spell, power) * 4
	if healing:
		var missing := _target_missing_health(state, target_id)
		var health_percent := 100 * _target_health(state, target_id) / maxi(1, _target_maximum_health(state, target_id))
		return (950 if health_percent <= 35 else 650 if health_percent <= 65 else 180) + mini(missing, expected) * 5
	return 340 + expected * 5 + _lethal_bonus(state, target_id, expected)
