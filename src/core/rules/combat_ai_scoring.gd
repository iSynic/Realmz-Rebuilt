class_name CombatAiScoring
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const MAX_WEIGHTED_DRAW: int = 32_767

var _flow_ref: WeakRef
var _rules: ContextType


func _init(flow: RefCounted, rules: ContextType) -> void:
	_flow_ref = weakref(flow)
	_rules = rules


func _flow() -> RefCounted:
	return _flow_ref.get_ref() if _flow_ref != null else null


func choose_party_action(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> Dictionary:
	var choices: Array[Dictionary] = []
	if _flow().probe_bandage(state, actor.id).allowed:
		var bandage: Dictionary = {}
		for target_id: String in _flow().bandage_candidate_ids(state):
			var target := state.party.character_by_id(target_id)
			bandage = _prefer(bandage, {"action": &"bandage", "targetId": target_id, "score": 1100 - (target.current_health if target != null else 0)})
		_append_positive_choice(choices, bandage)
	if _flow().probe_turn_undead(state, content, actor.id).allowed:
		choices.append({"action": &"turn_undead", "score": 760})
	_append_positive_choice(choices, _best_party_spell(state, content, actor))
	var adjacent_ids := _hostile_adjacent_ids(state, actor.id)
	if not adjacent_ids.is_empty():
		if state.combat.character_weapon_mode(actor.id) == &"missile":
			choices.append({"action": &"switch_weapon", "score": 640})
		else:
			var melee: Dictionary = {}
			for target_id: String in adjacent_ids:
				melee = _prefer(melee, {"action": &"attack", "targetId": target_id, "score": 520 + _lethal_pressure(state, target_id)})
			_append_positive_choice(choices, melee)
	else:
		_append_positive_choice(choices, _best_projectile(state, content, actor))
		if actor.movement > 0:
			choices.append({"action": &"move", "score": 100})
	var selected := _weighted_choice(choices, rng, StringName("combat.auto.%s.action-choice" % actor.id))
	return {"action": &"defend", "score": 0} if selected.is_empty() else selected


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
	if state.monster_spellcasting_blocked or state.combat.was_attacked(monster.id) or definition.magic_attack_count <= 0:
		return {}
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if monster.conditions.is_active(condition):
			return {}
	var best: Dictionary = {}
	var actors_by_cell := _actors_by_cell(state.combat.battlefield)
	var area_placement_cache: Dictionary = {}
	var area_center_cache: Dictionary = {}
	for slot: int in 10:
		var spell := content.spell_by_id(definition.spell_id_at(slot))
		if spell == null or not _flow()._monster_spell_unavailable_reason(spell).is_empty():
			continue
		if spell.target_type != 12 and not _auto_group_target_is_safe(spell):
			continue
		if ClassicSpellCapabilityCatalog.is_combat_persistent_field_spell(spell) and not state.combat.can_queue_persistent_field():
			continue
		var maximum_power := 1 if ClassicSpellCapabilityCatalog.is_combat_application_elemental_attack(spell) else 7 if spell.cost == 0 else mini(7, monster.spell_points / spell.cost)
		for power: int in range(1, maximum_power + 1):
			var plan := _monster_spell_power_plan(state, content, monster, definition, spell, slot, power, actors_by_cell, area_placement_cache, area_center_cache)
			best = _prefer(best, plan)
	return best


func _monster_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, slot: int, power: int, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary) -> Dictionary:
	if ClassicSpellCapabilityCatalog.is_inert_self_duration_effect(spell):
		return {}
	if _flow()._is_summon_spell(spell):
		return _monster_summon_spell_power_plan(state, content, monster, spell, slot, power)
	if ClassicSpellCapabilityCatalog.is_combat_destroy_magic_spell(spell):
		return _monster_destroy_magic_plan(state, content, monster, spell, slot, power)
	if ClassicSpellCapabilityCatalog.is_combat_magic_detection_spell(spell):
		return {}
	if ClassicSpellCapabilityCatalog.is_combat_polymorph_spell(spell) and spell.target_type == 1:
		return _monster_polymorph_plan(state, content, monster, spell, slot, power)
	if spell.target_type in [3, 4]:
		return _monster_area_spell_power_plan(state, content, monster, definition, spell, slot, power, actors_by_cell, area_placement_cache, area_center_cache)
	if spell.target_type == 6:
		return _monster_ray_spell_power_plan(state, content, monster, spell, slot, power)
	if spell.target_type in [9, 10, 12]:
		return _monster_group_spell_power_plan(state, content, monster, spell, slot, power, spell.target_type == 9)
	var cure_index := MagicRules.condition_cure_index(spell) if MagicRules.is_condition_cure_spell(spell) else -1
	var effect_index := ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell)
	if effect_index < 0:
		effect_index = ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell)
	var spell_point_restore := ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell)
	var spell_point_drain := ClassicSpellCapabilityCatalog.is_combat_spell_point_drain_spell(spell)
	var friendly := spell.target_type == 5 or spell.cannot == 4 or cure_index >= 0 or spell_point_restore
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and (character.traitor == monster.traitor) == friendly and (spell.target_type != 5 or character.id == monster.id) and (not spell_point_restore or _target_missing_spell_points(state, character.id) > 0) and (not spell_point_drain or _target_spell_points(state, character.id) > 0) and (cure_index < 0 or character.conditions.is_active(cure_index)) and (effect_index < 0 or character.conditions.value(effect_index) == 0) and (cure_index >= 0 or character.id == monster.id or not _target_reflects(state, character.id)) and (friendly or not _target_hard_immune(state, content, character.id, spell)) and state.combat.battlefield.has_actor(character.id) and _flow()._spell_actor_target_is_valid(state, content, monster.id, character.id, spell, power):
			candidates.append(character.id)
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health > 0 and (candidate.traitor == monster.traitor) == friendly and (spell.target_type != 5 or candidate.id == monster.id) and (not spell_point_restore or _target_missing_spell_points(state, candidate.id) > 0) and (not spell_point_drain or _target_spell_points(state, candidate.id) > 0) and (cure_index < 0 or candidate.conditions.is_active(cure_index)) and (effect_index < 0 or candidate.conditions.value(effect_index) == 0) and (cure_index >= 0 or candidate.id == monster.id or not _target_reflects(state, candidate.id)) and (friendly or not _target_hard_immune(state, content, candidate.id, spell)) and state.combat.battlefield.has_actor(candidate.id) and content.monster_by_id(candidate.definition_id) != null and _flow()._spell_actor_target_is_valid(state, content, monster.id, candidate.id, spell, power):
			candidates.append(candidate.id)
	if candidates.is_empty():
		return {}
	var healing: bool = _flow()._is_source_backed_combat_healing_spell(spell)
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
	var coordinate: Vector2i = _flow()._automatic_monster_summon_coordinate(state, content, monster, spell, power)
	if coordinate == INVALID_COORDINATE:
		return {}
	var friendly_count := 0
	var hostile_count := 0
	var allied_summon_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
			if character.traitor == monster.traitor: friendly_count += 1
			else: hostile_count += 1
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health <= 0 or not state.combat.battlefield.has_actor(candidate.id):
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
	for target: MonsterState in state.combat.monsters():
		if target.current_health <= 0 or target.traitor == monster.traitor or not state.combat.battlefield.has_actor(target.id) or _target_reflects(state, target.id) or _target_hard_immune(state, content, target.id, spell) or not _flow()._spell_actor_target_is_valid(state, content, monster.id, target.id, spell, power):
			continue
		best = _prefer(best, {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [target.id], "score": 440 + target.hit_dice * 20 + target.current_health - spell.cost * power * 3})
	return best


func _monster_group_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int, friendly: bool) -> Dictionary:
	var target_ids := _everybody_actor_ids(state) if spell.target_type == 12 else _friendly_actor_ids_for_monster(state, monster) if friendly else _opposed_actor_ids_for_monster(state, monster)
	var condition_index := ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell)
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
	if ClassicSpellCapabilityCatalog.is_combat_persistent_field_spell(spell) and not state.combat.can_queue_persistent_field():
		return {}
	var expected := expected_spell_effect(spell, power)
	var condition_index := ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell)
	var monster_targets_only := ClassicSpellCapabilityCatalog.is_combat_polymorph_spell(spell)
	if monster_targets_only: expected = 10
	if expected <= 0 and condition_index < 0:
		return {}
	expected = maxi(expected, _maximum_condition_duration(spell, power)) if condition_index >= 0 else expected
	var maximum_range := absi(spell.range_min + spell.range_max * power) + (1 if definition.size != 0 else 0) + (1 if definition.size == 3 else 0)
	var rotations: Array = _rules.spell_areas.rotation_patterns(spell, power)
	var best: Dictionary = {}
	for rotation: int in rotations.size():
		var offsets: Array[Vector2i] = []
		offsets.assign(rotations[rotation])
		var shape := _rules.spell_areas.shape_for(spell, power, rotation)
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
					if monster_targets_only and state.combat.monster_by_id(target_id) == null:
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
		for target_cell: Vector2i in state.combat.battlefield.actor_footprint(target_id):
			for offset: Vector2i in offsets:
				unique[target_cell - offset] = true
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null:
		return []
	var result: Array[Vector2i] = []
	for value: Variant in unique:
		var center: Vector2i = value
		if _rules.spell_areas.pattern_fits(center, shape) and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, monster.id, center, maximum_range, require_line_of_sight):
			result.append(center)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or (left.y == right.y and left.x < right.x))
	return result


func _monster_ray_spell_power_plan(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, slot: int, power: int) -> Dictionary:
	var expected := expected_spell_effect(spell, power)
	if expected <= 0:
		return {}
	var best: Dictionary = {}
	for endpoint_id: String in _opposed_actor_ids_for_monster(state, monster):
		if not _flow()._spell_actor_target_is_valid(state, content, monster.id, endpoint_id, spell, power):
			continue
		var ray_ids: Array[String] = _flow().ray_spell_actor_ids(state, content, monster.id, endpoint_id, spell)
		if ray_ids.is_empty() or ray_ids.any(func(target_id: String) -> bool: return _actor_is_friendly_to_monster(state, monster, target_id) or _target_hard_immune(state, content, target_id, spell)):
			continue
		var drain := ClassicSpellCapabilityCatalog.is_combat_spell_point_drain_spell(spell)
		var score := 340 - spell.cost * power * 3
		for target_id: String in ray_ids:
			score += mini(_target_spell_points(state, target_id), expected) * 6 if drain else expected * 6 + _lethal_bonus(state, target_id, expected)
		if drain and ray_ids.all(func(target_id: String) -> bool: return _target_spell_points(state, target_id) <= 0):
			continue
		best = _prefer(best, {"spellId": spell.id, "spellSlot": slot, "power": power, "targetIds": [endpoint_id], "score": score})
	return best


func _monster_target_score(state: GameState, target_id: String, spell: SpellDefinition, power: int, healing: bool, cure_index: int = -1, effect_index: int = -1) -> int:
	var expected := expected_spell_effect(spell, power)
	if ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell):
		return 620 + mini(_target_missing_spell_points(state, target_id), expected) * 5 + _target_missing_spell_points(state, target_id)
	if ClassicSpellCapabilityCatalog.is_combat_spell_point_drain_spell(spell):
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


static func _prefer(current: Dictionary, candidate: Dictionary) -> Dictionary:
	return candidate if not candidate.is_empty() and int(candidate.get("score", -1)) > int(current.get("score", -1)) else current


static func _append_positive_choice(choices: Array[Dictionary], candidate: Dictionary) -> void:
	if not candidate.is_empty() and int(candidate.get("score", 0)) > 0:
		choices.append(candidate)


static func _weighted_choice(candidates: Array[Dictionary], rng: RealmzRng, semantic_tag: StringName) -> Dictionary:
	var choices: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if not candidate.is_empty() and int(candidate.get("score", 0)) > 0:
			choices.append(candidate)
	if choices.is_empty():
		return {}
	choices.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left.get("score", 0))
		var right_score := int(right.get("score", 0))
		return left_score > right_score or (left_score == right_score and _choice_key(left) < _choice_key(right))
	)
	if choices.size() == 1:
		return choices[0]
	var weights: Array[int] = []
	var total_weight := 0
	for choice: Dictionary in choices:
		var weight := maxi(1, int(choice.get("score", 0)))
		weights.append(weight)
		total_weight += weight
	while total_weight > MAX_WEIGHTED_DRAW:
		var divisor := (total_weight + MAX_WEIGHTED_DRAW - 1) / MAX_WEIGHTED_DRAW
		total_weight = 0
		for index: int in weights.size():
			weights[index] = maxi(1, weights[index] / divisor)
			total_weight += weights[index]
	var roll := rng.draw(total_weight, semantic_tag)
	var threshold := 0
	for index: int in choices.size():
		threshold += weights[index]
		if roll <= threshold:
			return choices[index]
	return choices.back()


static func _choice_key(choice: Dictionary) -> String:
	var target_ids: Array = choice.get("targetIds", [])
	var target_coordinates: Array = choice.get("targetCoordinates", [])
	return "%s|%s|%s|%s|%s|%s|%d" % [String(choice.get("action", "")), String(choice.get("spellId", "")), String(choice.get("targetId", "")), ",".join(target_ids), str(choice.get("coordinate", Vector2i(-1, -1))), str(target_coordinates), int(choice.get("rotation", 0))]


func _best_party_spell(state: GameState, content: RealmzContent, actor: CharacterState) -> Dictionary:
	var best: Dictionary = {}
	var actors_by_cell := _actors_by_cell(state.combat.battlefield)
	var area_placement_cache: Dictionary = {}
	var area_center_cache: Dictionary = {}
	var summon_coordinate_cache: Dictionary = {}
	var ray_actor_cache: Dictionary = {}
	for option: CombatSpellOptionView in _flow().character_spell_options(state, content, actor.id):
		var spell := content.spell_by_id(option.spell_id)
		if spell == null or not _auto_group_target_is_safe(spell):
			continue
		if _flow()._is_summon_spell(spell):
			best = _prefer(best, _best_summon(state, content, actor, spell, option.power, summon_coordinate_cache))
		elif ClassicSpellCapabilityCatalog.is_combat_charm_spell(spell):
			best = _prefer(best, _best_charm(state, content, actor, spell, option.power))
		elif ClassicSpellCapabilityCatalog.is_combat_polymorph_spell(spell):
			best = _prefer(best, _best_polymorph(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache))
		elif ClassicSpellCapabilityCatalog.is_combat_destroy_turn_undead_spell(spell):
			best = _prefer(best, _best_destroy_turn_undead(state, content, actor, spell, option.power))
		elif ClassicSpellCapabilityCatalog.is_combat_destroy_magic_spell(spell):
			best = _prefer(best, _best_destroy_magic(state, content, actor, spell, option.power))
		elif ClassicSpellCapabilityCatalog.is_combat_magic_detection_spell(spell):
			continue
		elif MagicRules.is_condition_cure_spell(spell):
			best = _prefer(best, _best_condition_cure(state, content, actor, spell, option.power))
		elif spell.target_type == 7 and state.party.conditions.value(absi(spell.special)) < _maximum_condition_duration(spell, option.power):
			best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "score": 520 + (_maximum_condition_duration(spell, option.power) - state.party.conditions.value(absi(spell.special))) * 8 - absi(spell.cost * option.power) * 3})
		elif ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell) >= 0 and spell.target_type in [3, 4]:
			best = _prefer(best, _best_damage_spell(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache, ray_actor_cache))
		elif ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell) >= 0 or spell.target_type == 5 and ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell) >= 0:
			best = _prefer(best, _best_condition_effect(state, content, actor, spell, option.power))
		elif _flow()._is_source_backed_combat_healing_spell(spell):
			best = _prefer(best, _best_heal(state, content, actor, spell, option.power))
		elif ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell):
			best = _prefer(best, _best_spell_point_restore(state, content, actor, spell, option.power))
		elif ClassicSpellCapabilityCatalog.is_combat_spell_point_drain_spell(spell):
			best = _prefer(best, _best_spell_point_drain(state, content, actor, spell, option.power, ray_actor_cache))
		elif spell.target_type in [0, 1, 3, 4, 6, 9, 10, 12]:
			best = _prefer(best, _best_damage_spell(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache, ray_actor_cache))
	return best


func _best_charm(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target_id: String in _opposed_actor_ids(state, actor):
		if _target_reflects(state, target_id) or _target_hard_immune(state, content, target_id, spell) or not _flow()._spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			continue
		var score := 780 + _target_health(state, target_id) * 4 - absi(spell.cost * power) * 3
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": target_id, "score": score})
	return best


func _best_polymorph(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, option: CombatSpellOptionView, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary) -> Dictionary:
	if spell.target_type == 4:
		return _best_area(state, content, actor, spell, option, 10, actors_by_cell, area_placement_cache, area_center_cache, -1, true)
	var best: Dictionary = {}
	for target: MonsterState in state.combat.monsters():
		if target.current_health <= 0 or target.traitor == actor.traitor or not state.combat.battlefield.has_actor(target.id) or _target_reflects(state, target.id) or _target_hard_immune(state, content, target.id, spell) or not _flow()._spell_actor_target_is_valid(state, content, actor.id, target.id, spell, option.power):
			continue
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "targetId": target.id, "score": 440 + target.hit_dice * 20 + target.current_health - option.cost * 3})
	return best


func _best_destroy_turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var eligible := 0
	for target: MonsterState in state.combat.monsters():
		var definition := content.monster_by_id(target.definition_id)
		if target.current_health > 0 and target.traitor and state.combat.battlefield.has_actor(target.id) and definition != null and definition.can_summon != -1 and (definition.type_flag(1) or definition.type_flag(2)):
			eligible += 1
	if eligible == 0 or not _flow().probe_character_spell_cast(state, content, actor.id, "", spell.id, power).allowed:
		return {}
	return {"action": &"cast_spell", "spellId": spell.id, "power": power, "score": 520 + eligible * 180 - absi(spell.cost * power) * 3}


func _best_destroy_magic(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var candidates := _destroy_magic_candidates(state, content, actor.id, actor.traitor, spell, power)
	if candidates.is_empty():
		return {}
	var selected: Array[String] = []
	for target_id: String in candidates:
		if selected.size() >= power:
			break
		selected.append(target_id)
	var score := 0
	for target_id: String in selected:
		score += _destroy_magic_target_score(state, actor.traitor, target_id)
	return {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetIds": selected, "score": score - absi(spell.cost * power) * 3}


func _best_summon(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int, coordinate_cache: Dictionary) -> Dictionary:
	var maximum_range := absi(spell.range_min + spell.range_max * power)
	var cache_key := "%d:%d" % [maximum_range, 1 if spell.range_min + spell.range_max > 0 else 0]
	if not coordinate_cache.has(cache_key):
		coordinate_cache[cache_key] = _flow()._automatic_summon_coordinate(state, content, actor, spell, power)
	var coordinate: Vector2i = coordinate_cache[cache_key]
	if coordinate == INVALID_COORDINATE:
		return {}
	var friendly_count := 0
	var hostile_count := 0
	var allied_summon_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
			if character.traitor == actor.traitor: friendly_count += 1
			else: hostile_count += 1
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
			continue
		if monster.traitor == actor.traitor:
			friendly_count += 1
			if monster.summoned: allied_summon_count += 1
		else:
			hostile_count += 1
	if hostile_count <= 0 or friendly_count > hostile_count or allied_summon_count >= maxi(1, hostile_count - friendly_count + 1):
		return {}
	return {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetCoordinates": [coordinate], "score": 400 + (hostile_count - friendly_count) * 120 + hostile_count * 20 - absi(spell.cost * power) * 3}


func _best_condition_cure(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var condition_index := MagicRules.condition_cure_index(spell)
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor == actor.traitor and character.conditions.is_active(condition_index) and state.combat.battlefield.has_actor(character.id):
			candidates.append(character.id)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and monster.traitor == actor.traitor and monster.conditions.is_active(condition_index) and state.combat.battlefield.has_actor(monster.id):
			candidates.append(monster.id)
	candidates.sort_custom(func(left: String, right: String) -> bool: return _condition_cure_score(state, left, condition_index) > _condition_cure_score(state, right, condition_index) or (_condition_cure_score(state, left, condition_index) == _condition_cure_score(state, right, condition_index) and left < right))
	if spell.target_type == 5:
		return {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": actor.id, "score": _condition_cure_score(state, actor.id, condition_index) - absi(spell.cost * power) * 3} if candidates.has(actor.id) and _flow().probe_character_spell_cast(state, content, actor.id, actor.id, spell.id, power).allowed else {}
	var selected: Array[String] = []
	for target_id: String in candidates:
		if selected.size() >= (power if spell.target_type == 0 else 1):
			break
		var target_ids: Array[String] = []
		if spell.target_type == 0:
			target_ids.append(target_id)
		if _flow().probe_character_spell_cast(state, content, actor.id, target_id, spell.id, power, INVALID_COORDINATE, 0, target_ids).allowed:
			selected.append(target_id)
	if selected.is_empty():
		return {}
	var score := 0
	for target_id: String in selected:
		score += _condition_cure_score(state, target_id, condition_index)
	var result := {"action": &"cast_spell", "spellId": spell.id, "power": power, "score": score - absi(spell.cost * power) * 3}
	if spell.target_type == 0:
		result["targetIds"] = selected
	else:
		result["targetId"] = selected[0]
	return result


func _best_condition_effect(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var condition_index := ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell)
	if condition_index < 0:
		condition_index = ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell)
	var friendly := spell.target_type == 5 or spell.cannot == 4
	var candidate_ids: Array[String] = [actor.id]
	if spell.target_type != 5:
		candidate_ids = _friendly_actor_ids(state, actor) if friendly else _opposed_actor_ids(state, actor)
	var candidates: Array[String] = []
	for target_id: String in candidate_ids:
		var character := state.party.character_by_id(target_id)
		var monster := state.combat.monster_by_id(target_id)
		var conditions := character.conditions if character != null else monster.conditions if monster != null else null
		if conditions == null or conditions.value(condition_index) != 0 or target_id != actor.id and _target_reflects(state, target_id):
			continue
		candidates.append(target_id)
	if candidates.is_empty():
		return {}
	var selected: Array[String] = []
	for target_id: String in candidates:
		if spell.target_type == 0 and selected.size() >= power:
			break
		selected.append(target_id)
	var probe_target := "" if spell.target_type in [9, 10, 12] else selected[0]
	var probe_targets: Array[String] = []
	if spell.target_type == 0:
		probe_targets.assign(selected)
	if not _flow().probe_character_spell_cast(state, content, actor.id, probe_target, spell.id, power, INVALID_COORDINATE, 0, probe_targets).allowed:
		return {}
	var duration_score := _maximum_condition_duration(spell, power)
	var score := (520 if friendly else 420) + selected.size() * duration_score * (8 if friendly else 4) - absi(spell.cost * power) * 3
	var result := {"action": &"cast_spell", "spellId": spell.id, "power": power, "score": score}
	if spell.target_type == 0:
		result["targetIds"] = selected
	elif spell.target_type not in [9, 10, 12]:
		result["targetId"] = selected[0]
	return result


static func _condition_cure_score(state: GameState, target_id: String, condition_index: int) -> int:
	var character := state.party.character_by_id(target_id)
	var condition_value := character.conditions.value(condition_index) if character != null else state.combat.monster_by_id(target_id).conditions.value(condition_index)
	var urgency := 900 if condition_index in [ConditionRules.POISONED, ConditionRules.DISEASED] else 720
	return urgency + mini(200, absi(condition_value) * 10)


static func _maximum_condition_duration(spell: SpellDefinition, power: int) -> int:
	return maxi(spell.duration_min, spell.duration_max) + power * maxi(spell.power_duration_min, spell.power_duration_max)


func _best_heal(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target: CharacterState in state.party.characters():
		if target.current_health <= 0 or target.traitor != actor.traitor or target.current_health >= target.maximum_health:
			continue
		if not _flow()._spell_actor_target_is_valid(state, content, actor.id, target.id, spell, power):
			continue
		var health_percent := 100 * target.current_health / maxi(1, target.maximum_health)
		if health_percent > 65:
			continue
		var urgency := 980 if health_percent <= 35 else 680
		var score := urgency + 100 - health_percent - absi(spell.cost * power) * 3
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": target.id, "score": score})
	return best


func _best_spell_point_restore(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target_id: String in _friendly_actor_ids(state, actor):
		if spell.target_type == 5 and target_id != actor.id or _target_missing_spell_points(state, target_id) <= 0 or target_id != actor.id and _target_reflects(state, target_id):
			continue
		if not _flow()._spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			continue
		var score := 620 + mini(_target_missing_spell_points(state, target_id), expected_spell_effect(spell, power)) * 5 + _target_missing_spell_points(state, target_id) - absi(spell.cost * power) * 3
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": target_id, "score": score})
	return best


func _best_spell_point_drain(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int, ray_actor_cache: Dictionary) -> Dictionary:
	var expected := expected_spell_effect(spell, power)
	if expected <= 0:
		return {}
	if spell.target_type == 6:
		return _best_party_spell_point_drain_ray(state, content, actor, spell, power, expected, ray_actor_cache)
	var candidates: Array[String] = []
	for target_id: String in _opposed_actor_ids(state, actor):
		if _target_spell_points(state, target_id) > 0 and not _target_reflects(state, target_id) and not _target_hard_immune(state, content, target_id, spell) and _flow()._spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			candidates.append(target_id)
	candidates.sort_custom(func(left: String, right: String) -> bool: return _target_spell_points(state, left) > _target_spell_points(state, right) or (_target_spell_points(state, left) == _target_spell_points(state, right) and left < right))
	if candidates.is_empty():
		return {}
	var selected: Array[String] = candidates.slice(0, mini(power if spell.target_type == 0 else 1, candidates.size()))
	var score := 540 - absi(spell.cost * power) * 3
	for target_id: String in selected:
		score += mini(_target_spell_points(state, target_id), expected) * 6 + _target_spell_points(state, target_id)
	return {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetIds": selected, "targetId": selected[0], "score": score}


func _best_party_spell_point_drain_ray(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int, expected: int, ray_actor_cache: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for endpoint_id: String in _opposed_actor_ids(state, actor):
		if not _flow()._spell_actor_target_is_valid(state, content, actor.id, endpoint_id, spell, power):
			continue
		var cache_key := "%s:%d" % [endpoint_id, 1 if spell.range_min + spell.range_max > 0 else 0]
		if not ray_actor_cache.has(cache_key):
			ray_actor_cache[cache_key] = _flow().ray_spell_actor_ids(state, content, actor.id, endpoint_id, spell)
		var ray_ids: Array[String] = ray_actor_cache[cache_key]
		if ray_ids.is_empty() or ray_ids.any(func(target_id: String) -> bool: return _actor_is_friendly(state, actor, target_id) or _target_hard_immune(state, content, target_id, spell)) or ray_ids.all(func(target_id: String) -> bool: return _target_spell_points(state, target_id) <= 0):
			continue
		var score := 540 - absi(spell.cost * power) * 3
		for target_id: String in ray_ids:
			score += mini(_target_spell_points(state, target_id), expected) * 6 + _target_spell_points(state, target_id)
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": endpoint_id, "score": score})
	return best


func _best_damage_spell(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, option: CombatSpellOptionView, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary, ray_actor_cache: Dictionary) -> Dictionary:
	var expected := expected_spell_effect(spell, option.power)
	var condition_index := ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell)
	if absi(spell.special) == 28:
		condition_index = ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell)
		expected = absi(_maximum_condition_duration(spell, option.power))
	if expected <= 0 and condition_index < 0:
		return {}
	expected = maxi(expected, _maximum_condition_duration(spell, option.power)) if condition_index >= 0 else expected
	if spell.target_type in [3, 4]:
		return _best_area(state, content, actor, spell, option, expected, actors_by_cell, area_placement_cache, area_center_cache, condition_index)
	if spell.target_type == 6:
		return _best_party_ray(state, content, actor, spell, option.power, expected, ray_actor_cache)
	var targets := _hostile_spell_targets(state, content, actor, spell, option.power)
	if targets.is_empty():
		return {}
	var cost_penalty := absi(spell.cost * option.power) * 3
	if spell.target_type == 10:
		return {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "score": 360 + targets.size() * expected * 6 - cost_penalty}
	if spell.target_type == 0:
		var selected: Array[String] = []
		for target_id: String in targets:
			if selected.size() >= option.power:
				break
			selected.append(target_id)
		return {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "targetIds": selected, "score": 350 + selected.size() * expected * 5 - cost_penalty}
	var best: Dictionary = {}
	for target_id: String in targets:
		var score := 350 + expected * 5 + _lethal_bonus(state, target_id, expected) - cost_penalty
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "targetId": target_id, "score": score})
	return best


func _best_party_ray(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int, expected: int, ray_actor_cache: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for endpoint_id: String in _opposed_actor_ids(state, actor):
		if not _flow()._spell_actor_target_is_valid(state, content, actor.id, endpoint_id, spell, power):
			continue
		var cache_key := "%s:%d" % [endpoint_id, 1 if spell.range_min + spell.range_max > 0 else 0]
		if not ray_actor_cache.has(cache_key):
			ray_actor_cache[cache_key] = _flow().ray_spell_actor_ids(state, content, actor.id, endpoint_id, spell)
		var ray_ids: Array[String] = ray_actor_cache[cache_key]
		if ray_ids.is_empty() or ray_ids.any(func(target_id: String) -> bool: return _actor_is_friendly(state, actor, target_id) or _target_hard_immune(state, content, target_id, spell)):
			continue
		var score := 350 + ray_ids.size() * expected * 6 - absi(spell.cost * power) * 3
		for target_id: String in ray_ids:
			score += _lethal_bonus(state, target_id, expected)
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": endpoint_id, "score": score})
	return best


func _best_area(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, option: CombatSpellOptionView, expected: int, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary, condition_index: int = -1, monster_targets_only: bool = false) -> Dictionary:
	var maximum_range := absi(spell.range_min + spell.range_max * option.power)
	var best: Dictionary = {}
	var rotations: Array = option.area_rotation_offsets if not option.area_rotation_offsets.is_empty() else [option.area_offsets]
	for rotation: int in rotations.size():
		var offsets: Array[Vector2i] = []
		offsets.assign(rotations[rotation])
		var shape := _rules.spell_areas.shape_for(spell, option.power, rotation)
		var cache_key := "%d:%d:%d:%d:%d:%d" % [shape, maximum_range, 1 if spell.range_min + spell.range_max > 0 else 0, spell.spell_class, condition_index, 1 if monster_targets_only else 0]
		if not area_placement_cache.has(cache_key):
			var placements: Array[Dictionary] = []
			var center_key := "%d:%d:%d" % [shape, maximum_range, 1 if spell.range_min + spell.range_max > 0 else 0]
			if not area_center_cache.has(center_key):
				area_center_cache[center_key] = _area_candidate_centers(state, content, actor, shape, offsets, maximum_range, spell.range_min + spell.range_max > 0)
			for center: Vector2i in area_center_cache[center_key]:
				var hostile_ids: Dictionary = {}
				var harms_friend := false
				for offset: Vector2i in offsets:
					var target_id := String(actors_by_cell.get(center + offset, ""))
					if target_id.is_empty():
						continue
					if monster_targets_only and state.combat.monster_by_id(target_id) == null:
						continue
					if _actor_is_friendly(state, actor, target_id):
						harms_friend = true
					elif _target_reflects(state, target_id):
						harms_friend = true
					elif not _target_hard_immune(state, content, target_id, spell) and (condition_index < 0 or _target_condition_value(state, target_id, condition_index) == 0):
						hostile_ids[target_id] = true
				if not harms_friend and not hostile_ids.is_empty():
					placements.append({"center": center, "hostileCount": hostile_ids.size()})
			area_placement_cache[cache_key] = placements
		for placement: Dictionary in area_placement_cache[cache_key]:
			var score := 370 + int(placement["hostileCount"]) * expected * 7 - option.cost * 3
			best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "coordinate": placement["center"], "rotation": rotation, "score": score})
	return best


func _area_candidate_centers(state: GameState, content: RealmzContent, actor: CharacterState, shape: int, offsets: Array[Vector2i], maximum_range: int, require_line_of_sight: bool) -> Array[Vector2i]:
	var unique: Dictionary = {}
	for target_id: String in _opposed_actor_ids(state, actor):
		for target_cell: Vector2i in state.combat.battlefield.actor_footprint(target_id):
			for offset: Vector2i in offsets:
				unique[target_cell - offset] = true
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null:
		return []
	var result: Array[Vector2i] = []
	for value: Variant in unique:
		var center: Vector2i = value
		if _rules.spell_areas.pattern_fits(center, shape) and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, actor.id, center, maximum_range, require_line_of_sight):
			result.append(center)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or (left.y == right.y and left.x < right.x))
	return result


static func _actors_by_cell(battlefield: BattlefieldState) -> Dictionary:
	var result: Dictionary = {}
	for actor_id: String in battlefield.actor_ids():
		for coordinate: Vector2i in battlefield.actor_footprint(actor_id):
			result[coordinate] = actor_id
	return result


func _hostile_spell_targets(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Array[String]:
	var result: Array[String] = []
	for target_id: String in _opposed_actor_ids(state, actor):
		var target_character := state.party.character_by_id(target_id)
		var target_monster := state.combat.monster_by_id(target_id)
		if _target_hard_immune(state, content, target_id, spell) or (target_character != null and target_character.conditions.is_active(ConditionRules.REFLECTING_SPELLS)) or (target_monster != null and target_monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS)):
			continue
		if _flow()._spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			result.append(target_id)
	result.sort_custom(func(left: String, right: String) -> bool: return _target_health(state, left) < _target_health(state, right) or (_target_health(state, left) == _target_health(state, right) and left < right))
	return result


func _auto_group_target_is_safe(spell: SpellDefinition) -> bool:
	if spell.target_type not in [9, 10, 12]:
		return true
	if spell.target_type == 12:
		return false
	var condition_effect := ClassicSpellCapabilityCatalog.combat_condition_effect_index(spell) >= 0 or ClassicSpellCapabilityCatalog.combat_persistent_field_condition_index(spell) >= 0
	var friendly_effect: bool = MagicRules.is_condition_cure_spell(spell) or _flow()._is_source_backed_combat_healing_spell(spell) or ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell) or condition_effect and (spell.cannot == 4 or spell.target_type == 9)
	return spell.target_type == 9 if friendly_effect else spell.target_type == 10


func _best_projectile(state: GameState, content: RealmzContent, actor: CharacterState) -> Dictionary:
	if state.combat.character_weapon_mode(actor.id) != &"missile":
		return {}
	var profile = _flow().character_projectile_profile(actor, content, _rules.inventory.combat_equipment(actor, content.item_definitions()))
	if profile == null or not profile.available:
		return {"action": &"switch_weapon", "score": 110}
	var best: Dictionary = {}
	for target_id: String in _opposed_actor_ids(state, actor):
		if _flow().projectile_target_is_valid(state.combat, content, actor.id, target_id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
			best = _prefer(best, {"action": &"attack", "targetId": target_id, "score": 330 + _lethal_pressure(state, target_id)})
	return best if not best.is_empty() else {"action": &"switch_weapon", "score": 110}


func _opposed_actor_ids(state: GameState, actor: CharacterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and state.combat.battlefield.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and state.combat.battlefield.has_actor(monster.id):
			result.append(monster.id)
	return result


func _friendly_actor_ids(state: GameState, actor: CharacterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor == actor.traitor and state.combat.battlefield.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and monster.traitor == actor.traitor and state.combat.battlefield.has_actor(monster.id):
			result.append(monster.id)
	return result


func _hostile_adjacent_ids(state: GameState, actor_id: String) -> Array[String]:
	var actor := state.party.character_by_id(actor_id)
	var result: Array[String] = []
	if actor == null:
		return result
	for target_id: String in _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, actor_id):
		if not _actor_is_friendly(state, actor, target_id):
			result.append(target_id)
	return result


func _hostile_adjacent_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for target_id: String in _rules.battlefield.adjacent_actor_ids(state.combat.battlefield, monster.id):
		var character := state.party.character_by_id(target_id)
		var target_monster := state.combat.monster_by_id(target_id)
		if (character != null and character.current_health > 0 and character.traitor != monster.traitor) or (target_monster != null and target_monster.current_health > 0 and target_monster.traitor != monster.traitor):
			result.append(target_id)
	return result


func _opposed_actor_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor != monster.traitor and state.combat.battlefield.has_actor(character.id):
			result.append(character.id)
	for candidate: MonsterState in state.combat.monsters():
		if candidate.id != monster.id and candidate.current_health > 0 and candidate.traitor != monster.traitor and state.combat.battlefield.has_actor(candidate.id):
			result.append(candidate.id)
	return result


func _friendly_actor_ids_for_monster(state: GameState, monster: MonsterState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and character.traitor == monster.traitor and state.combat.battlefield.has_actor(character.id): result.append(character.id)
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health > 0 and candidate.traitor == monster.traitor and state.combat.battlefield.has_actor(candidate.id): result.append(candidate.id)
	return result


func _everybody_actor_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.has_actor(character.id): result.append(character.id)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and state.combat.battlefield.has_actor(monster.id): result.append(monster.id)
	return result


static func expected_spell_effect(spell: SpellDefinition, power: int) -> int:
	if ClassicSpellCapabilityCatalog.is_combat_death_spell(spell):
		return 128
	if absi(spell.special) == 28:
		return absi(_maximum_condition_duration(spell, power))
	return int((spell.damage_min + spell.damage_max) / 2.0 + (spell.power_damage_min + spell.power_damage_max) * power / 2.0)


static func _actor_is_friendly(state: GameState, actor: CharacterState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.traitor == actor.traitor
	var monster := state.combat.monster_by_id(target_id)
	return monster != null and monster.traitor == actor.traitor


static func _actor_is_friendly_to_monster(state: GameState, actor: MonsterState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.traitor == actor.traitor
	var monster := state.combat.monster_by_id(target_id)
	return monster != null and monster.traitor == actor.traitor


static func _target_health(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.current_health
	var monster := state.combat.monster_by_id(target_id)
	return monster.current_health if monster != null else 0x7fff_ffff


static func _target_maximum_health(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.maximum_health
	var monster := state.combat.monster_by_id(target_id)
	return monster.maximum_health if monster != null else 1


static func _target_missing_health(state: GameState, target_id: String) -> int:
	return maxi(0, _target_maximum_health(state, target_id) - _target_health(state, target_id))


static func _target_missing_spell_points(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return maxi(0, character.maximum_spell_points - character.spell_points)
	var monster := state.combat.monster_by_id(target_id)
	return maxi(0, monster.maximum_spell_points - monster.spell_points) if monster != null else 0


static func _target_spell_points(state: GameState, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return maxi(0, character.spell_points)
	var monster := state.combat.monster_by_id(target_id)
	return maxi(0, monster.spell_points) if monster != null else 0


static func _target_condition_value(state: GameState, target_id: String, condition_index: int) -> int:
	var character := state.party.character_by_id(target_id)
	var monster := state.combat.monster_by_id(target_id) if character == null else null
	return character.conditions.value(condition_index) if character != null else monster.conditions.value(condition_index) if monster != null else 0


func _destroy_magic_candidates(state: GameState, content: RealmzContent, caster_id: String, caster_traitor: bool, spell: SpellDefinition, power: int) -> Array[String]:
	var candidates: Array[String] = []
	for target_id: String in _all_actor_ids(state):
		if (target_id != caster_id and _target_reflects(state, target_id)) or _destroy_magic_target_score(state, caster_traitor, target_id) <= 0 or not _flow()._spell_actor_target_is_valid(state, content, caster_id, target_id, spell, power):
			continue
		candidates.append(target_id)
	candidates.sort_custom(func(left: String, right: String) -> bool: return _destroy_magic_target_score(state, caster_traitor, left) > _destroy_magic_target_score(state, caster_traitor, right) or (_destroy_magic_target_score(state, caster_traitor, left) == _destroy_magic_target_score(state, caster_traitor, right) and left < right))
	return candidates


static func _destroy_magic_target_score(state: GameState, caster_traitor: bool, target_id: String) -> int:
	var character := state.party.character_by_id(target_id)
	var monster := state.combat.monster_by_id(target_id) if character == null else null
	var conditions: ConditionSet = character.conditions if character != null else monster.conditions if monster != null else null
	if conditions == null:
		return 0
	var target_traitor_before := character.traitor if character != null else monster.traitor
	var target_traitor_after := false if character != null else target_traitor_before
	var allied_before := target_traitor_before == caster_traitor
	var allied_after := target_traitor_after == caster_traitor
	var score := 0
	var harmful := [ConditionRules.RUNS_AWAY, ConditionRules.HELPLESS, ConditionRules.TANGLED, ConditionRules.CURSED, ConditionRules.STUPID, ConditionRules.SLOW, ConditionRules.POISONED, ConditionRules.TURNED_TO_STONE, ConditionRules.BLIND, ConditionRules.DISEASED, ConditionRules.CONFUSED, ConditionRules.ENERGY_DRAIN, ConditionRules.HINDERED_ATTACKS, ConditionRules.HINDERED_DEFENSE, ConditionRules.SILENCED]
	for index: int in conditions.size():
		if conditions.value(index) <= 0:
			continue
		var harmful_effect := index in harmful
		score += (300 if harmful_effect else -180) if allied_after else (-240 if harmful_effect else 240)
	if character != null and character.traitor:
		score += 1_200 if allied_after and not allied_before else -1_400 if allied_before and not allied_after else 0
	return score


static func _all_actor_ids(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
			result.append(character.id)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and state.combat.battlefield.has_actor(monster.id):
			result.append(monster.id)
	return result


static func _target_hard_immune(state: GameState, content: RealmzContent, target_id: String, spell: SpellDefinition) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.magic_resistance > 100
	var monster := state.combat.monster_by_id(target_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	return monster != null and (monster.magic_resistance > 100 or definition != null and definition.spell_immune(spell.spell_class))


static func _target_reflects(state: GameState, target_id: String) -> bool:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return character.conditions.is_active(ConditionRules.REFLECTING_SPELLS)
	var monster := state.combat.monster_by_id(target_id)
	return monster != null and monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS)


static func _lethal_bonus(state: GameState, target_id: String, expected: int) -> int:
	return 180 if _target_health(state, target_id) <= expected else 0


static func _lethal_pressure(state: GameState, target_id: String) -> int:
	return maxi(0, 100 - mini(100, _target_health(state, target_id)))
