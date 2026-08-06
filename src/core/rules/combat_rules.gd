class_name CombatRules
extends RefCounted

var _conditions: ConditionRules


func _init(condition_rules: ConditionRules) -> void:
	_conditions = condition_rules


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


func resolve_monster_attack(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, rng: RealmzRng) -> AttackResolution:
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
	defender.current_health -= damage
	return AttackResolution.new(true, defender.current_health <= 0, chance, roll, damage)


func resolve_monster_attack_monster(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, rng: RealmzRng) -> AttackResolution:
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
	defender.current_health -= damage
	return AttackResolution.new(true, defender.current_health <= 0, chance, roll, damage)


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
