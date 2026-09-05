## Plans deterministic, legal action categories and spell use for party Auto.

class_name CombatPartyActionPlanner
extends CombatAiScoringSupport

func choose_party_action(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> Dictionary:
	var choices: Array[Dictionary] = []
	if _context.actions().probe_bandage(state, actor.id).allowed:
		var bandage: Dictionary = {}
		for target_id: String in _context.actions().bandage_candidate_ids(state):
			var target := state.party.character_by_id(target_id)
			bandage = _prefer(bandage, {"action": &"bandage", "targetId": target_id, "score": 1100 - (target.current_health if target != null else 0)})
		_append_positive_choice(choices, bandage)
	if _context.actions().probe_turn_undead(state, content, actor.id).allowed:
		choices.append({"action": &"turn_undead", "score": 760})
	_append_positive_choice(choices, _best_party_spell(state, content, actor))
	var adjacent_ids := _hostile_adjacent_ids(state, actor.id)
	if not adjacent_ids.is_empty():
		if state.combat.actor_statuses.character_weapon_mode(actor.id) == &"missile":
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


func _best_party_spell(state: GameState, content: RealmzContent, actor: CharacterState) -> Dictionary:
	var best: Dictionary = {}
	var actors_by_cell := _actors_by_cell(state.combat.battlefield)
	var area_placement_cache: Dictionary = {}
	var area_center_cache: Dictionary = {}
	var summon_coordinate_cache: Dictionary = {}
	var ray_actor_cache: Dictionary = {}
	for option: CombatSpellOptionView in _context.magic_flow().selection().character_spell_options(state, content, actor.id):
		var spell := content.magic.spell_by_id(option.spell_id)
		if spell == null or not _auto_group_target_is_safe(spell):
			continue
		if CombatFlowSummoning.is_summon_spell(spell):
			best = _prefer(best, _best_summon(state, content, actor, spell, option.power, summon_coordinate_cache))
		elif ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell):
			best = _prefer(best, _best_charm(state, content, actor, spell, option.power))
		elif ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell):
			best = _prefer(best, _best_polymorph(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache))
		elif ClassicSpellSpecialEffectRules.is_combat_destroy_turn_undead_spell(spell):
			best = _prefer(best, _best_destroy_turn_undead(state, content, actor, spell, option.power))
		elif ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
			best = _prefer(best, _best_destroy_magic(state, content, actor, spell, option.power))
		elif ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell):
			continue
		elif MagicRules.is_condition_cure_spell(spell):
			best = _prefer(best, _best_condition_cure(state, content, actor, spell, option.power))
		elif spell.target_type == 7 and state.party.conditions.value(absi(spell.special)) < _maximum_condition_duration(spell, option.power):
			best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "score": 520 + (_maximum_condition_duration(spell, option.power) - state.party.conditions.value(absi(spell.special))) * 8 - absi(spell.cost * option.power) * 3})
		elif ClassicSpellConditionRules.combat_condition_effect_index(spell) >= 0 and spell.target_type in [3, 4]:
			best = _prefer(best, _best_damage_spell(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache, ray_actor_cache))
		elif ClassicSpellConditionRules.combat_condition_effect_index(spell) >= 0 or spell.target_type == 5 and ClassicSpellConditionRules.combat_persistent_field_condition_index(spell) >= 0:
			best = _prefer(best, _best_condition_effect(state, content, actor, spell, option.power))
		elif _context.automation().is_source_backed_combat_healing_spell(spell):
			best = _prefer(best, _best_heal(state, content, actor, spell, option.power))
		elif ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell):
			best = _prefer(best, _best_spell_point_restore(state, content, actor, spell, option.power))
		elif ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell):
			best = _prefer(best, _best_spell_point_drain(state, content, actor, spell, option.power, ray_actor_cache))
		elif spell.target_type in [0, 1, 3, 4, 6, 9, 10, 12]:
			best = _prefer(best, _best_damage_spell(state, content, actor, spell, option, actors_by_cell, area_placement_cache, area_center_cache, ray_actor_cache))
	return best


func _best_charm(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target_id: String in _opposed_actor_ids(state, actor):
		if _target_reflects(state, target_id) or _target_hard_immune(state, content, target_id, spell) or not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			continue
		var score := 780 + _target_health(state, target_id) * 4 - absi(spell.cost * power) * 3
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": target_id, "score": score})
	return best


func _best_polymorph(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, option: CombatSpellOptionView, actors_by_cell: Dictionary, area_placement_cache: Dictionary, area_center_cache: Dictionary) -> Dictionary:
	if spell.target_type == 4:
		return _best_area(state, content, actor, spell, option, 10, actors_by_cell, area_placement_cache, area_center_cache, -1, true)
	var best: Dictionary = {}
	for target: MonsterState in state.combat.roster.monsters():
		if target.current_health <= 0 or target.traitor == actor.traitor or not state.combat.battlefield.actors.has_actor(target.id) or _target_reflects(state, target.id) or _target_hard_immune(state, content, target.id, spell) or not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target.id, spell, option.power):
			continue
		best = _prefer(best, {"action": &"cast_spell", "spellId": spell.id, "power": option.power, "targetId": target.id, "score": 440 + target.hit_dice * 20 + target.current_health - option.cost * 3})
	return best


func _best_destroy_turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var eligible := 0
	for target: MonsterState in state.combat.roster.monsters():
		var definition := content.combat.monster_by_id(target.definition_id)
		if target.current_health > 0 and target.traitor and state.combat.battlefield.actors.has_actor(target.id) and definition != null and definition.can_summon != -1 and (definition.type_flag(1) or definition.type_flag(2)):
			eligible += 1
	if eligible == 0 or not _context.magic_flow().selection().probe_character_spell_cast(state, content, actor.id, "", spell.id, power).allowed:
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
		coordinate_cache[cache_key] = _context.summoning().automatic_coordinate(state, content, actor, spell, power)
	var coordinate: Vector2i = coordinate_cache[cache_key]
	if coordinate == INVALID_COORDINATE:
		return {}
	var friendly_count := 0
	var hostile_count := 0
	var allied_summon_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id):
			if character.traitor == actor.traitor: friendly_count += 1
			else: hostile_count += 1
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id):
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
		if character.current_health > 0 and character.traitor == actor.traitor and character.conditions.is_active(condition_index) and state.combat.battlefield.actors.has_actor(character.id):
			candidates.append(character.id)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor == actor.traitor and monster.conditions.is_active(condition_index) and state.combat.battlefield.actors.has_actor(monster.id):
			candidates.append(monster.id)
	candidates.sort_custom(func(left: String, right: String) -> bool: return _condition_cure_score(state, left, condition_index) > _condition_cure_score(state, right, condition_index) or (_condition_cure_score(state, left, condition_index) == _condition_cure_score(state, right, condition_index) and left < right))
	if spell.target_type == 5:
		return {"action": &"cast_spell", "spellId": spell.id, "power": power, "targetId": actor.id, "score": _condition_cure_score(state, actor.id, condition_index) - absi(spell.cost * power) * 3} if candidates.has(actor.id) and _context.magic_flow().selection().probe_character_spell_cast(state, content, actor.id, actor.id, spell.id, power).allowed else {}
	var selected: Array[String] = []
	for target_id: String in candidates:
		if selected.size() >= (power if spell.target_type == 0 else 1):
			break
		var target_ids: Array[String] = []
		if spell.target_type == 0:
			target_ids.append(target_id)
		if _context.magic_flow().selection().probe_character_spell_cast(state, content, actor.id, target_id, spell.id, power, INVALID_COORDINATE, 0, target_ids).allowed:
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
	var condition_index := ClassicSpellConditionRules.combat_condition_effect_index(spell)
	if condition_index < 0:
		condition_index = ClassicSpellConditionRules.combat_persistent_field_condition_index(spell)
	var friendly := spell.target_type == 5 or spell.cannot == 4
	var candidate_ids: Array[String] = [actor.id]
	if spell.target_type != 5:
		candidate_ids = _friendly_actor_ids(state, actor) if friendly else _opposed_actor_ids(state, actor)
	var candidates: Array[String] = []
	for target_id: String in candidate_ids:
		var character := state.party.character_by_id(target_id)
		var monster := state.combat.roster.monster_by_id(target_id)
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
	if not _context.magic_flow().selection().probe_character_spell_cast(state, content, actor.id, probe_target, spell.id, power, INVALID_COORDINATE, 0, probe_targets).allowed:
		return {}
	var duration_score := _maximum_condition_duration(spell, power)
	var score := (520 if friendly else 420) + selected.size() * duration_score * (8 if friendly else 4) - absi(spell.cost * power) * 3
	var result := {"action": &"cast_spell", "spellId": spell.id, "power": power, "score": score}
	if spell.target_type == 0:
		result["targetIds"] = selected
	elif spell.target_type not in [9, 10, 12]:
		result["targetId"] = selected[0]
	return result


func _best_heal(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Dictionary:
	var best: Dictionary = {}
	for target: CharacterState in state.party.characters():
		if target.current_health <= 0 or target.traitor != actor.traitor or target.current_health >= target.maximum_health:
			continue
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target.id, spell, power):
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
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
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
		if _target_spell_points(state, target_id) > 0 and not _target_reflects(state, target_id) and not _target_hard_immune(state, content, target_id, spell) and _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
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
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, endpoint_id, spell, power):
			continue
		var cache_key := "%s:%d" % [endpoint_id, 1 if spell.range_min + spell.range_max > 0 else 0]
		if not ray_actor_cache.has(cache_key):
			ray_actor_cache[cache_key] = _context.magic_flow().ray_spell_actor_ids(state, content, actor.id, endpoint_id, spell)
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
	var condition_index := ClassicSpellConditionRules.combat_persistent_field_condition_index(spell)
	if absi(spell.special) == 28:
		condition_index = ClassicSpellConditionRules.combat_condition_effect_index(spell)
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
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, endpoint_id, spell, power):
			continue
		var cache_key := "%s:%d" % [endpoint_id, 1 if spell.range_min + spell.range_max > 0 else 0]
		if not ray_actor_cache.has(cache_key):
			ray_actor_cache[cache_key] = _context.magic_flow().ray_spell_actor_ids(state, content, actor.id, endpoint_id, spell)
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
		var shape := _context.spell_areas.shape_for(spell, option.power, rotation)
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
					if monster_targets_only and state.combat.roster.monster_by_id(target_id) == null:
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
		if _context.spell_areas.pattern_fits(center, shape) and _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, actor.id, center, maximum_range, require_line_of_sight):
			result.append(center)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or (left.y == right.y and left.x < right.x))
	return result


func _hostile_spell_targets(state: GameState, content: RealmzContent, actor: CharacterState, spell: SpellDefinition, power: int) -> Array[String]:
	var result: Array[String] = []
	for target_id: String in _opposed_actor_ids(state, actor):
		var target_character := state.party.character_by_id(target_id)
		var target_monster := state.combat.roster.monster_by_id(target_id)
		if _target_hard_immune(state, content, target_id, spell) or (target_character != null and target_character.conditions.is_active(ConditionRules.REFLECTING_SPELLS)) or (target_monster != null and target_monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS)):
			continue
		if _context.magic_flow().selection().spell_actor_target_is_valid(state, content, actor.id, target_id, spell, power):
			result.append(target_id)
	result.sort_custom(func(left: String, right: String) -> bool: return _target_health(state, left) < _target_health(state, right) or (_target_health(state, left) == _target_health(state, right) and left < right))
	return result


func _best_projectile(state: GameState, content: RealmzContent, actor: CharacterState) -> Dictionary:
	if state.combat.actor_statuses.character_weapon_mode(actor.id) != &"missile":
		return {}
	var profile = _context.reactions().character_projectile_profile(actor, content, _context.equipment.combat_equipment(actor, content.items.definitions()))
	if profile == null or not profile.available:
		return {"action": &"switch_weapon", "score": 110}
	var best: Dictionary = {}
	for target_id: String in _opposed_actor_ids(state, actor):
		if _context.reactions().projectile_target_is_valid(state.combat, content, actor.id, target_id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
			best = _prefer(best, {"action": &"attack", "targetId": target_id, "score": 330 + _lethal_pressure(state, target_id)})
	return best if not best.is_empty() else {"action": &"switch_weapon", "score": 110}
