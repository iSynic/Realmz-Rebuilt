## Owns pure physical-attack eligibility, modifiers, fumbles, and initiative order.
class_name CombatAttackPolicy
extends RefCounted


static func character_fumble(attacker: CharacterState, equipment: CharacterCombatEquipment, rng: RealmzRng, allow_fumbles: bool, can_queue_fumble: bool) -> Dictionary:
	if not allow_fumbles: return {}
	var roll := rng.draw(1000 + 100 * attacker.level, &"combat.attack.fumble")
	if roll <= 50 or roll >= 60 or not equipment.is_armed(): return {"roll": roll}
	if not equipment.melee_weapon.cursed_item_id.is_empty(): return {"roll": roll, "blockedReason": &"cursed_weapon"}
	if not can_queue_fumble: return {"roll": roll, "blockedReason": &"fumble_queue_full"}
	return {"roll": roll, "fumbled": true}


static func fumbled_attack(chance: int, roll: int, fumble_roll: int) -> AttackResolution:
	var resolution := AttackResolution.new(false, false, chance, roll, 0)
	resolution.fumbled = true
	resolution.fumble_roll = fumble_roll
	return resolution


static func with_fumble_observation(resolution: AttackResolution, fumble: Dictionary) -> AttackResolution:
	if resolution == null or fumble.is_empty(): return resolution
	resolution.fumble_roll = int(fumble.get("roll", 0))
	resolution.fumble_block_reason = StringName(fumble.get("blockedReason", &""))
	return resolution


static func magic_weapon_requirement_reason(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterDefinition, hit: bool) -> StringName:
	if defender.magic_to_hit <= 0: return &""
	if equipment.is_armed():
		if hit and defender.magic_to_hit > equipment.melee_weapon.damage_bonus: return &"classic_magic_weapon_required"
		return &""
	return &"classic_magic_weapon_required" if defender.magic_to_hit > attacker.level / 8 else &""


static func required_weapon_reason(equipment: CharacterCombatEquipment, defender: MonsterDefinition, hit: bool) -> StringName:
	if not hit or defender.required_weapon == 0: return &""
	if not equipment.is_armed():
		if defender.required_weapon == -1: return &"classic_blunt_weapon_required"
		if defender.required_weapon == -2: return &"classic_sharp_weapon_required"
		return &"classic_specific_weapon_required"
	if defender.required_weapon == -1: return &"" if equipment.melee_weapon.blunt == -1 else &"classic_blunt_weapon_required"
	if defender.required_weapon == -2: return &"" if equipment.melee_weapon.blunt == -2 else &"classic_sharp_weapon_required"
	# FD-COMBAT-003: the shipped data uses ordinary Item Numbers, not Castle's
	# ineffective item-minus-1024 comparison.
	var required_item_id := defender.required_weapon & 0xff
	return &"" if equipment.melee_weapon.classic_id == required_item_id else &"classic_specific_weapon_required"


static func invalid_weapon_reason(weapon: ItemDefinition) -> StringName:
	if weapon == null: return &""
	if weapon.vs_small < 0 or weapon.vs_large < 0 or weapon.heat < 0 or weapon.cold < 0 or weapon.electric < 0 or weapon.vs_undead < 0 or weapon.vs_demon_devil < 0 or weapon.vs_evil < 0:
		return &"unsupported_negative_weapon_range"
	if weapon.special_1 == -10:
		if weapon.special_3 < 20 or weapon.special_3 >= 60: return &"invalid_weapon_condition"
		if weapon.special_2 == 1 and (weapon.special_4 < 0 or weapon.special_4 >= 8): return &"invalid_weapon_condition_save"
	return &""


static func roll_weapon_physical(weapon: ItemDefinition, defender_definition: MonsterDefinition, rng: RealmzRng) -> int:
	var damage := 0
	if defender_definition != null:
		if weapon.vs_undead != 0 and defender_definition.type_flag(1): damage += rng.draw(maxi(1, weapon.vs_undead), &"combat.attack.weapon-versus-undead")
		if weapon.vs_demon_devil != 0 and defender_definition.type_flag(2): damage += rng.draw(maxi(1, weapon.vs_demon_devil), &"combat.attack.weapon-versus-demon-devil")
		if weapon.vs_evil != 0 and defender_definition.type_flag(4): damage += rng.draw(maxi(1, weapon.vs_evil), &"combat.attack.weapon-versus-evil")
	# Castle's player melee path always uses the small-target die, including Rand(0).
	damage += rng.draw(maxi(1, weapon.vs_small), &"combat.attack.weapon-physical")
	return damage


static func attacker_condition_modifier(conditions: ConditionSet) -> int:
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


static func defender_condition_modifier(conditions: ConditionSet, include_protection_from_evil: bool = true) -> int:
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
	modifier -= 10 if include_protection_from_evil and conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL) else 0
	return modifier


static func initiative_order(characters: Array[CharacterState], monsters: Array[MonsterState], surprise: int, rng: RealmzRng) -> Array[String]:
	var order: Array[String] = []
	for character: CharacterState in characters:
		if character.current_health > 0: order.append(character.id)
	for monster: MonsterState in monsters:
		if monster.current_health > 0: order.append(monster.id)
	if surprise > 0: return _party_first(order, characters)
	if surprise < 0: return _monsters_first(order, monsters)
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


static func _agility(id: String, characters: Array[CharacterState], monsters: Array[MonsterState]) -> int:
	for character: CharacterState in characters:
		if character.id == id: return character.agility
	for monster: MonsterState in monsters:
		if monster.id == id: return monster.agility
	return 0


static func _party_first(order: Array[String], characters: Array[CharacterState]) -> Array[String]:
	var party_ids: Dictionary = {}
	for character: CharacterState in characters: party_ids[character.id] = true
	return _allegiance_first(order, party_ids)


static func _monsters_first(order: Array[String], monsters: Array[MonsterState]) -> Array[String]:
	var monster_ids: Dictionary = {}
	for monster: MonsterState in monsters: monster_ids[monster.id] = true
	return _allegiance_first(order, monster_ids)


static func _allegiance_first(order: Array[String], first_ids: Dictionary) -> Array[String]:
	var first: Array[String] = []
	var last: Array[String] = []
	for id: String in order:
		(first if first_ids.has(id) else last).append(id)
	first.append_array(last)
	return first


static func signed_16(value: int) -> int:
	var wrapped := value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


static func signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped
