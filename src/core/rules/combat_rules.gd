class_name CombatRules
extends RefCounted

var _conditions: ConditionRules
var _characters: CharacterRules


func _init(condition_rules: ConditionRules, character_rules: CharacterRules) -> void:
	_conditions = condition_rules
	_characters = character_rules


func resolve_character_attack(attacker: CharacterState, defender: MonsterState, defender_definition: MonsterDefinition, equipped_damage_bonus: int, rng: RealmzRng, realmz_day: int = 0, behind: bool = false) -> AttackResolution:
	if attacker == null or defender == null or defender_definition == null or rng == null:
		return null
	var chance := 50 + attacker.to_hit + (20 if behind else 0) + 5 * equipped_damage_bonus
	chance += _attacker_condition_modifier(attacker.conditions)
	chance += rng.draw(maxi(1, attacker.luck), &"combat.attack.luck")
	for index: int in 8:
		if defender_definition.type_flag(index):
			chance += 5 * attacker.special_value(index)
	if defender_definition.type_flag(4) and attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance -= defender.armor
	chance += _defender_condition_modifier(defender.conditions)
	chance -= int(float(realmz_day) / 120.0)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	if not hit:
		return AttackResolution.new(false, false, chance, roll, 0)
	var reflected := false
	if defender.conditions.is_active(ConditionRules.REFLECTING_ATTACKS) and rng.draw(100, &"combat.attack.reflect") < 34:
		reflected = true
	var damage := equipped_damage_bonus + attacker.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	if equipped_damage_bonus == 0:
		damage += rng.draw(maxi(1, attacker.hand_to_hand), &"combat.attack.unarmed-damage")
	damage = maxi(0, damage)
	if defender.conditions.is_active(ConditionRules.HELPLESS):
		damage = defender.current_health
	if reflected:
		attacker.current_health -= damage
		return AttackResolution.new(true, attacker.current_health <= 0, chance, roll, damage, true)
	defender.current_health -= damage
	return AttackResolution.new(true, defender.current_health <= 0, chance, roll, damage)


func resolve_monster_attack(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or rng == null:
		return null
	var chance := 50 + 5 * attacker.hit_dice
	chance += _attacker_condition_modifier(attacker.conditions)
	chance -= defender.armor
	chance += _defender_condition_modifier(defender.conditions)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.monster-attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	if not hit:
		return AttackResolution.new(false, false, chance, roll, 0)
	var attacks := attacker_definition.attacks()
	var attack := MonsterAttackDefinition.new()
	if not attacks.is_empty():
		attack = attacks[clampi(attack_index, 0, attacks.size() - 1)]
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	if attack.damage_max >= attack.damage_min:
		damage += rng.draw_between(attack.damage_min, attack.damage_max, &"combat.monster-attack.damage")
	damage = maxi(0, damage)
	if defender.conditions.is_active(ConditionRules.HELPLESS):
		damage = defender.current_health
	var resolution := AttackResolution.new(true, defender.current_health - damage <= 0, chance, roll, damage)
	if attack.special != 0:
		resolution.special_code = attack.special
		var potency_low := int(float(attacker.hit_dice) / 2.0)
		resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
	if _is_status_special(attack.special):
		_apply_party_status_special(resolution, defender, rng)
	elif _is_resource_special(attack.special):
		_apply_party_resource_special(resolution, attacker, defender, rng)
	elif attack.special == 17:
		resolution.special_handled = true
		resolution.special_save_index = 7
		resolution.special_save_chance = defender.save_value(7)
		resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
		resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
		if not resolution.special_saved:
			resolution.special_applied = true
			var age_factor := _signed_16(attack.damage_max * attacker.hit_dice)
			resolution.special_age_days = int(float(race.max_age) * 0.01 * float(age_factor)) if race != null else 0
			if race != null and caste != null:
				resolution.aging = _characters.advance_age_days(defender, race, caste, resolution.special_age_days)
	resolution.damage_deferred = resolution.aging != null and resolution.aging.changed_group()
	if not resolution.damage_deferred:
		defender.current_health -= damage
		resolution.killed = defender.current_health <= 0
	return resolution


func resolve_monster_attack_monster(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or defender_definition == null or rng == null:
		return null
	var chance := 50 + 5 * attacker.hit_dice
	chance += _attacker_condition_modifier(attacker.conditions)
	chance -= defender.armor
	chance += _defender_condition_modifier(defender.conditions)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.monster-attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	if not hit:
		return AttackResolution.new(false, false, chance, roll, 0)
	var attacks := attacker_definition.attacks()
	var attack := MonsterAttackDefinition.new()
	if not attacks.is_empty():
		attack = attacks[clampi(attack_index, 0, attacks.size() - 1)]
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	if attack.damage_max >= attack.damage_min:
		damage += rng.draw_between(attack.damage_min, attack.damage_max, &"combat.monster-attack.damage")
	damage = maxi(0, damage)
	if defender.conditions.is_active(ConditionRules.HELPLESS):
		damage = defender.current_health
	var resolution := AttackResolution.new(true, defender.current_health - damage <= 0, chance, roll, damage)
	if attack.special != 0:
		resolution.special_code = attack.special
		var potency_low := int(float(attacker.hit_dice) / 2.0)
		resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
		if _is_status_special(attack.special):
			resolution.special_handled = true
			resolution.special_save_index = _status_save_index(attack.special)
			resolution.special_condition_index = _status_condition_index(attack.special)
			resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
			resolution.special_condition_after = resolution.special_condition_before
		elif _is_resource_special(attack.special):
			resolution.special_handled = true
			resolution.special_save_index = _resource_save_index(attack.special)
			resolution.special_resource = &"spell_points" if attack.special == 8 else &"experience"
		elif attack.special == 17:
			resolution.special_handled = true
		if defender.magic_resistance > 100:
			resolution.special_blocked = true
			resolution.special_block_reason = &"magic_resistance"
			resolution.hit = false
			resolution.damage = 0
			resolution.killed = false
			return resolution
	if _is_status_special(attack.special):
		_apply_monster_status_special(resolution, defender, defender_definition, rng)
	elif attack.special == 8:
		_apply_monster_spell_drain(resolution, attacker, defender, defender_definition, rng)
	elif attack.special == 9:
		resolution.special_blocked = true
		resolution.special_block_reason = &"party_target_only"
	elif attack.special == 17:
		resolution.special_handled = true
	defender.current_health -= damage
	resolution.killed = defender.current_health <= 0
	return resolution


func _apply_party_status_special(resolution: AttackResolution, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _status_save_index(resolution.special_code)
	resolution.special_condition_index = _status_condition_index(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_chance = defender.save_value(resolution.special_save_index)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	if resolution.special_saved:
		return
	if resolution.special_condition_before < 0:
		resolution.special_blocked = true
		resolution.special_block_reason = &"permanent_condition"
		return
	resolution.special_announced = true
	resolution.special_sound_id = 630
	if resolution.special_condition_before >= 30:
		resolution.special_blocked = true
		resolution.special_block_reason = &"party_condition_cap"
		return
	resolution.special_condition_after = _signed_16(resolution.special_condition_before + absi(resolution.special_potency))
	defender.conditions.set_value(resolution.special_condition_index, resolution.special_condition_after)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before


func _apply_monster_status_special(resolution: AttackResolution, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _status_save_index(resolution.special_code)
	resolution.special_condition_index = _status_condition_index(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender_definition, resolution.special_save_index)
	resolution.special_saved = _monster_saved(defender_definition, resolution.special_save_index, resolution.special_save_roll, resolution.special_save_chance)
	if resolution.special_saved:
		return
	if resolution.special_condition_before < 0:
		resolution.special_blocked = true
		resolution.special_block_reason = &"permanent_condition"
		return
	resolution.special_condition_after = _signed_16(resolution.special_condition_before + absi(resolution.special_potency))
	defender.conditions.set_value(resolution.special_condition_index, resolution.special_condition_after)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before
	resolution.special_announced = true
	resolution.special_sound_id = 684 if resolution.special_code == 16 else 630


func _apply_party_resource_special(resolution: AttackResolution, attacker: MonsterState, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _resource_save_index(resolution.special_code)
	resolution.special_resource = &"spell_points" if resolution.special_code == 8 else &"experience"
	resolution.special_save_chance = defender.save_value(resolution.special_save_index)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	if resolution.special_code == 8:
		resolution.special_target_before = defender.spell_points
		resolution.special_target_after = defender.spell_points
		resolution.special_actor_before = attacker.spell_points
		resolution.special_actor_after = attacker.spell_points
	else:
		resolution.special_target_before = defender.experience
		resolution.special_target_after = defender.experience
	if resolution.special_saved:
		return
	if resolution.special_code == 8:
		if defender.spell_points == 0:
			return
		var drained := attacker.hit_dice * 3
		if drained > defender.spell_points:
			drained = defender.spell_points
		defender.spell_points = _signed_16(defender.spell_points - drained)
		attacker.spell_points = _signed_16(attacker.spell_points + drained)
		resolution.special_amount = drained
		resolution.special_target_after = defender.spell_points
		resolution.special_actor_after = attacker.spell_points
		resolution.special_applied = drained != 0
		resolution.special_announced = resolution.special_applied
		return
	var removed := attacker.maximum_health * 20
	defender.experience = _signed_32(defender.experience - removed)
	resolution.special_amount = removed
	resolution.special_target_after = defender.experience
	resolution.special_applied = removed != 0
	resolution.special_announced = true
	resolution.special_sound_id = 630


func _apply_monster_spell_drain(resolution: AttackResolution, attacker: MonsterState, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 6
	resolution.special_resource = &"spell_points"
	resolution.special_target_before = defender.spell_points
	resolution.special_target_after = defender.spell_points
	resolution.special_actor_before = attacker.spell_points
	resolution.special_actor_after = attacker.spell_points
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender_definition, resolution.special_save_index)
	resolution.special_saved = _monster_saved(defender_definition, resolution.special_save_index, resolution.special_save_roll, resolution.special_save_chance)
	if resolution.special_saved or defender.spell_points == 0:
		return
	var drained := attacker.hit_dice * 3
	if drained > defender.spell_points:
		drained = defender.spell_points
	defender.spell_points = _signed_16(defender.spell_points - drained)
	attacker.spell_points = _signed_16(attacker.spell_points + drained)
	resolution.special_amount = drained
	resolution.special_target_after = defender.spell_points
	resolution.special_actor_after = attacker.spell_points
	resolution.special_applied = drained != 0
	resolution.special_announced = resolution.special_applied


static func _is_status_special(special_code: int) -> bool:
	return special_code in [1, 2, 3, 4, 5, 6, 7, 16]


static func _is_resource_special(special_code: int) -> bool:
	return special_code in [8, 9]


static func _resource_save_index(special_code: int) -> int:
	return 6 if special_code == 8 else 5


static func _status_condition_index(special_code: int) -> int:
	match special_code:
		1:
			return ConditionRules.RUNS_AWAY
		2:
			return ConditionRules.HELPLESS
		3:
			return ConditionRules.CURSED
		4:
			return ConditionRules.STUPID
		5:
			return ConditionRules.SLOW
		6:
			return ConditionRules.POISONED
		7:
			return ConditionRules.CONFUSED
		16:
			return ConditionRules.DISEASED
	return -1


static func _status_save_index(special_code: int) -> int:
	match special_code:
		3, 5:
			return 7
		6, 16:
			return 4
	return 5


static func _monster_save_chance(definition: MonsterDefinition, save_index: int) -> int:
	if save_index == 7:
		var total := 0
		for index: int in 6:
			total += definition.save_value(index)
		return int(float(total) / 6.0)
	return definition.save_value(save_index - 1) if save_index > 0 else 0


static func _monster_saved(definition: MonsterDefinition, save_index: int, roll: int, chance: int) -> bool:
	if save_index < 6 and definition.spell_immune(save_index):
		return true
	if save_index > 0 and roll <= chance:
		return true
	return definition.type_flag(1) and save_index in [0, 4, 5]


func initiative_order(characters: Array[CharacterState], monsters: Array[MonsterState], surprise: int, rng: RealmzRng) -> Array[String]:
	var order: Array[String] = []
	for character: CharacterState in characters:
		if character.current_health > 0:
			order.append(character.id)
	for monster: MonsterState in monsters:
		if monster.current_health > 0:
			order.append(monster.id)
	if surprise > 0:
		return _party_first(order, characters)
	if surprise < 0:
		return _monsters_first(order, monsters)
	for index: int in range(order.size() - 1, 0, -1):
		var swap_index := rng.draw_between(0, index, &"combat.initiative.slot")
		var held := order[index]
		order[index] = order[swap_index]
		order[swap_index] = held
	for left: int in order.size():
		for right: int in range(left, order.size() - 1):
			if _agility(order[right + 1], characters, monsters) > _agility(order[right], characters, monsters):
				var held := order[right]
				order[right] = order[right + 1]
				order[right + 1] = held
	return order


func _attacker_condition_modifier(conditions: ConditionSet) -> int:
	var modifier := 0
	modifier -= absi(conditions.value(ConditionRules.TANGLED))
	modifier += 15 if conditions.is_active(ConditionRules.STRONG) else 0
	modifier -= 15 if conditions.is_active(ConditionRules.SLOW) else 0
	modifier -= 10 if conditions.is_active(ConditionRules.CONFUSED) else 0
	modifier -= 15 if conditions.is_active(ConditionRules.BLIND) else 0
	modifier += 5 if conditions.is_active(ConditionRules.MAGIC_AURA) else 0
	modifier -= 5 if conditions.is_active(ConditionRules.CURSED) else 0
	modifier -= absi(conditions.value(ConditionRules.HINDERED_ATTACKS))
	return modifier


func _defender_condition_modifier(conditions: ConditionSet) -> int:
	var modifier := -2 * absi(conditions.value(ConditionRules.SHIELD_FROM_HITS))
	modifier += 10 if conditions.is_active(ConditionRules.CONFUSED) else 0
	modifier += 15 if conditions.is_active(ConditionRules.BLIND) else 0
	modifier += 15 if conditions.is_active(ConditionRules.SLOW) else 0
	modifier -= 5 if conditions.is_active(ConditionRules.MAGIC_AURA) else 0
	modifier += 5 if conditions.is_active(ConditionRules.CURSED) else 0
	modifier -= 10 if conditions.is_active(ConditionRules.INVISIBLE) else 0
	modifier += absi(conditions.value(ConditionRules.TANGLED))
	modifier += absi(conditions.value(ConditionRules.HINDERED_DEFENSE))
	modifier -= absi(conditions.value(ConditionRules.DEFENSE_BONUS))
	modifier -= 10 if conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL) else 0
	return modifier


func _agility(id: String, characters: Array[CharacterState], monsters: Array[MonsterState]) -> int:
	for character: CharacterState in characters:
		if character.id == id:
			return character.agility
	for monster: MonsterState in monsters:
		if monster.id == id:
			return monster.agility
	return 0


func _party_first(order: Array[String], characters: Array[CharacterState]) -> Array[String]:
	var party_ids: Dictionary = {}
	for character: CharacterState in characters:
		party_ids[character.id] = true
	var first: Array[String] = []
	var last: Array[String] = []
	for id: String in order:
		if party_ids.has(id):
			first.append(id)
		else:
			last.append(id)
	first.append_array(last)
	return first


func _monsters_first(order: Array[String], monsters: Array[MonsterState]) -> Array[String]:
	var monster_ids: Dictionary = {}
	for monster: MonsterState in monsters:
		monster_ids[monster.id] = true
	var first: Array[String] = []
	var last: Array[String] = []
	for id: String in order:
		if monster_ids.has(id):
			first.append(id)
		else:
			last.append(id)
	first.append_array(last)
	return first


static func _signed_16(value: int) -> int:
	var wrapped := value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


static func _signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped
