class_name CharacterRules
extends RefCounted

const ATTRIBUTE_COUNT: int = 6
const STARTING_LEVELS: Array[int] = [1, 3, 5, 7, 9, 11, 13, 15, 17, 20, 25, 30]
const ABILITY_ATTRIBUTE_VALUES: Array[int] = [3, 4, 5, 6, 7, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]
const STRENGTH_ABILITY_MODIFIERS := {
	0: [-5, -4, -3, -2, -1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4],
	3: [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
	5: [-75, -60, -45, -30, -15, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70],
	7: [-10, -8, -6, -4, -2, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28],
	9: [-75, -60, -45, -30, -15, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70],
}
const AGILITY_ABILITY_MODIFIERS := {
	0: [-5, -4, -3, -2, -1, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5, 5, 5],
	5: [-20, -15, -10, -5, -2, 5, 8, 11, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65],
	7: [-25, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70],
	11: [-25, -20, -15, -10, -5, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70],
}


func strength_bonuses(brawn: int, maximum_damage_bonus: int) -> StrengthResult:
	var hit := 0
	var damage := 0
	if brawn < 4:
		hit = -20
	else:
		match brawn:
			4: hit = -15; damage = -1
			5: hit = -10; damage = -1
			6: hit = -5
			16: hit = 5; damage = 1
			17: hit = 5; damage = 2
			18: hit = 10; damage = 2
			19: hit = 10; damage = 3
			20: hit = 15; damage = 3
			21: hit = 15; damage = 4
			22: hit = 20; damage = 4
			23: hit = 20; damage = 5
			24: hit = 25; damage = 5
			25: hit = 25; damage = 6
			26: hit = 30; damage = 6
			27: hit = 30; damage = 7
			28: hit = 35; damage = 7
			29: hit = 35; damage = 8
			30: hit = 40; damage = 8
	damage = mini(damage, maximum_damage_bonus)
	return StrengthResult.new(hit, damage)


func create_character(character_id: String, character_name: String, race: RaceDefinition, caste: CasteDefinition, gender: int, rng: RealmzRng, include_initial_items: bool = true, starting_level: int = 1) -> CharacterState:
	if race == null or caste == null or rng == null or not STARTING_LEVELS.has(starting_level):
		return null
	var attributes: Array[int] = []
	for index: int in ATTRIBUTE_COUNT:
		var rolled := rng.draw_between(1, 18, StringName("character.create.attribute.%d" % index)) + race.attribute_bonus(index) + caste.attribute_bonus(index)
		rolled = clampi(rolled, caste.attribute_minimum(index), caste.attribute_maximum(index))
		rolled = clampi(rolled, race.attribute_minimum(index), race.attribute_maximum(index))
		attributes.append(rolled)
	# Castle's seven-iteration loop aliases its final profile offset back to Luck,
	# consumes the roll, and never assigns the value. The draw is observable in
	# every later creation roll, so the deterministic session must retain it.
	rng.draw_between(1, 18, &"character.create.attribute.discarded")
	if gender == 2:
		attributes[0] -= 1
		attributes[3] += 1
		attributes[2] += 1
	else:
		attributes[0] += 1
		attributes[3] -= 1
	var save_values: Array[int] = []
	var special_values: Array[int] = []
	for index: int in 8:
		save_values.append(50 + race.save_bonus(index) + caste.save_bonus(index))
		special_values.append(race.hit_modifier(index))
	var age_group_count := clampi(caste.minimum_age_group, 1, 5)
	for age_index: int in age_group_count:
		var age_change := race.age_change(age_index)
		for attribute_index: int in ATTRIBUTE_COUNT:
			attributes[attribute_index] += age_change[attribute_index]
		for save_index: int in 7:
			save_values[save_index] += age_change[8 + save_index]
	for index: int in ATTRIBUTE_COUNT:
		attributes[index] = clampi(attributes[index], caste.attribute_minimum(index), caste.attribute_maximum(index))
		attributes[index] = clampi(attributes[index], race.attribute_minimum(index), race.attribute_maximum(index))
	for threshold: int in [80, 90, 95]:
		if rng.draw(100, StringName("character.create.special-bonus.%d.roll" % threshold)) > threshold:
			var special_index := rng.draw_between(0, 7, StringName("character.create.special-bonus.%d.index" % threshold))
			special_values[special_index] += 1
	var vitality_bonus := maxi(0, attributes[4] - 16)
	vitality_bonus = mini(vitality_bonus, caste.maximum_stamina_bonus)
	var maximum_health := rng.draw(maxi(1, caste.initial_stamina_die()), &"character.create.stamina") + vitality_bonus
	var result := CharacterState.new(character_id, character_name, maximum_health, maximum_health)
	result.race_id = race.id
	result.caste_id = caste.id
	result.gender = gender
	result.prestige_penalty = 10 * (starting_level - 1) * (starting_level - 1)
	result.experience = -caste.victory_threshold(starting_level - 1)
	result.age_group = age_group_count
	result.brawn = attributes[0]
	result.knowledge = attributes[1]
	result.judgment = attributes[2]
	result.agility = attributes[3]
	result.vitality = attributes[4]
	result.luck = attributes[5]
	var strength := strength_bonuses(result.brawn, caste.maximum_damage_bonus())
	result.to_hit = caste.initial_to_hit() + strength.to_hit_bonus
	result.damage_bonus = strength.damage_bonus
	result.dodge = 2 * result.agility + caste.initial_dodge()
	result.armor = 0
	if result.agility > 14:
		result.armor -= 2 * (14 - result.agility)
	result.magic_resistance = int(float(result.knowledge + result.judgment) / 10.0) * caste.magic_resistance_multiplier + race.magic_resistance
	result.two_hand = clampi(race.two_hand_bonus + caste.two_hand_bonus, 0, 100)
	result.missile = race.missile_bonus + caste.initial_missile() if caste.can_use_missile else 0
	result.hand_to_hand = caste.initial_hand_to_hand()
	result.maximum_movement = race.base_movement + caste.movement_bonus
	result.movement = result.maximum_movement
	result.normal_attacks = mini(race.base_attacks + caste.bonus_attacks, 2 * race.maximum_attacks)
	result.attacks_remaining = result.normal_attacks
	result.maximum_load = maxi(500, result.brawn * result.brawn * 20)
	result.money.gold = maxi(0, caste.start_money)
	var selected_age_range := race.age_range(clampi(caste.minimum_age_group - 1, 0, 4))
	if selected_age_range.y >= selected_age_range.x and selected_age_range.y > 0:
		result.age_days = rng.draw_between(selected_age_range.x, selected_age_range.y, &"character.create.age") * 365
	for index: int in 8:
		result.set_save_value(index, save_values[index])
		result.set_special_value(index, special_values[index])
	for index: int in ConditionSet.CHARACTER_COUNT:
		var starting_condition := race.condition_level(index)
		if caste.condition_level(index) == 1:
			starting_condition = -1
		result.conditions.set_value(index, starting_condition)
	_configure_spellcaster(result, caste, rng, starting_level)
	_initialize_abilities(result, race, caste)
	for _index: int in starting_level - 1:
		if level_up(result, race, caste, rng) == null:
			return null
	if include_initial_items:
		add_initial_items(result, caste)
	return result


func add_initial_items(character: CharacterState, caste: CasteDefinition) -> bool:
	if character == null or caste == null or not character.inventory().is_empty():
		return false
	var items: Array[ItemInstance] = []
	for index: int in caste.start_items().size():
		var item_id := caste.start_items()[index]
		items.append(ItemInstance.new("%s.item.%d" % [character.id, index], item_id))
	character.set_inventory(items)
	return true


func infer_age_group(age_days: int, race: RaceDefinition) -> int:
	if race == null:
		return 0
	var age_years := floori(float(age_days) / 365.0)
	for index: int in 5:
		var authored_range := race.age_range(index)
		if age_years >= authored_range.x and age_years <= authored_range.y:
			return index + 1
	return 0


func ensure_age_group(character: CharacterState, race: RaceDefinition, caste: CasteDefinition = null) -> int:
	if character == null or race == null:
		return 0
	if character.age_group >= 1 and character.age_group <= 5:
		return character.age_group
	character.age_group = infer_age_group(character.age_days, race)
	if character.age_group == 0:
		character.age_group = clampi(caste.minimum_age_group if caste != null else 1, 1, 5)
	return character.age_group


func advance_age_days(character: CharacterState, race: RaceDefinition, caste: CasteDefinition, day_change: int) -> CharacterAgingResult:
	if character == null or race == null or caste == null:
		return null
	var previous_days := character.age_days
	var previous_group := ensure_age_group(character, race, caste)
	character.age_days = _signed_32(character.age_days + day_change)
	var target_group := infer_age_group(character.age_days, race)
	if target_group > character.age_group and character.age_group < 5:
		character.age_group += 1
		_apply_age_change(character, race, caste, character.age_group, 1)
		return CharacterAgingResult.new(previous_days, character.age_days, previous_group, character.age_group, 1, character.age_group)
	if target_group > 0 and target_group < character.age_group and character.age_group > 1:
		var erased_group := character.age_group
		_apply_age_change(character, race, caste, erased_group, -1)
		character.age_group -= 1
		return CharacterAgingResult.new(previous_days, character.age_days, previous_group, character.age_group, -1, erased_group)
	return CharacterAgingResult.new(previous_days, character.age_days, previous_group, character.age_group)


func battle_experience(character: CharacterState, race: RaceDefinition, share: int) -> int:
	if character == null or race == null:
		return 0
	if floori(float(character.age_days) / 365.0) >= race.max_age:
		return int(float(share) * 0.6666666)
	return share


func level_up(character: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng) -> LevelUpResult:
	if character == null or race == null or caste == null or rng == null:
		return null
	character.level += 1
	# Castle consumes this registration-era roll even though the open-source
	# registration branch no longer changes the character.
	rng.draw(100, &"character.level.registration-check")
	character.normal_attacks = race.base_attacks + caste.bonus_attacks
	for required_level: int in caste.attack_levels():
		if required_level > 0 and required_level <= character.level:
			character.normal_attacks += 1
	character.normal_attacks = mini(character.normal_attacks, 2 * race.maximum_attacks)
	character.attacks_remaining = character.normal_attacks
	for index: int in ConditionSet.CHARACTER_COUNT:
		if caste.condition_level(index) == character.level:
			var current_condition := character.conditions.value(index)
			character.conditions.set_value(index, -1 if current_condition > -1 else current_condition - 1)
	character.to_hit += caste.level_to_hit()
	character.dodge += caste.level_dodge()
	character.hand_to_hand += caste.level_hand_to_hand()
	if caste.level_missile() > 0:
		character.missile += rng.draw(caste.level_missile(), &"character.level.missile")
	character.spellcaster_type = _level_spellcaster_type(caste)
	var spell_gain := _level_spell_points(character, caste, rng)
	character.spell_points += spell_gain
	character.maximum_spell_points += spell_gain
	var vitality_bonus := mini(maxi(0, character.vitality - 16), caste.maximum_stamina_bonus)
	var stamina_gain := rng.draw(maxi(1, caste.level_stamina_die()), &"character.level.stamina") + vitality_bonus
	character.current_health += stamina_gain
	character.maximum_health += stamina_gain
	var magic_gain := 1 if rng.draw(100, &"character.level.magic-resistance") <= character.judgment + character.knowledge + character.vitality else 0
	character.magic_resistance += magic_gain
	for index: int in 14:
		var ability_die := caste.level_ability_die(index)
		if ability_die > 0:
			character.set_ability_value(index, character.ability_value(index) + rng.draw(ability_die, StringName("character.level.ability.%d" % index)))
	for index: int in 12:
		character.set_ability_value(index, clampi(character.ability_value(index), 0, 100))
	character.dodge = clampi(character.dodge, 0, 100)
	character.missile = clampi(character.missile, 0, 100)
	character.magic_resistance = clampi(character.magic_resistance, 0, 100)
	character.two_hand = clampi(character.two_hand, 0, 100)
	character.damage_bonus = clampi(character.damage_bonus, 0, 200)
	character.hand_to_hand = clampi(character.hand_to_hand, 0, 200)
	return LevelUpResult.new(stamina_gain, spell_gain, caste.level_to_hit(), magic_gain)


func recalculate_movement(character: CharacterState, race: RaceDefinition, movement_bonus: int = 0) -> int:
	character.carried_load = maxi(0, character.carried_load)
	character.maximum_load = maxi(500, character.brawn * character.brawn * 20)
	var movement := 1.0 + (float(character.maximum_load - character.carried_load) / float(character.maximum_load)) * float(race.base_movement)
	if character.conditions.is_active(2):
		movement -= character.conditions.value(2)
	if character.conditions.is_active(6):
		movement /= 2.0
	if character.conditions.is_active(23):
		movement *= 2.0
	character.maximum_movement = maxi(2, int(movement)) + movement_bonus
	character.movement = mini(character.movement, character.maximum_movement)
	return character.maximum_movement


func spell_selection_total(character: CharacterState, caste: CasteDefinition) -> int:
	if character == null or caste == null or character.spellcaster_type < 1:
		return 0
	var start_level_sum := 0
	for row: Vector3i in caste.spellcaster_rows():
		start_level_sum += row.y
	var relative_level := character.level - (start_level_sum - 1)
	if relative_level < 1:
		return 0
	var bonus_attribute := character.judgment if character.spellcaster_type == 2 else character.knowledge
	var total := 3 * relative_level + int(relative_level * (relative_level - 1) / 2.0)
	if bonus_attribute > 15:
		total += relative_level * (bonus_attribute - 15)
	return total


func spell_selection_cost(spell: SpellDefinition) -> int:
	if spell == null:
		return 0
	var tier := spell.classic_tier()
	if tier < 0 or tier > 6:
		return 0
	var level := tier + 1
	return int(level * (level + 1) / 2.0)


func maximum_spell_selection_level(caste: CasteDefinition) -> int:
	if caste == null:
		return 0
	var result := 0
	for row: Vector3i in caste.spellcaster_rows():
		result += row.z
	return clampi(result, 0, 7)


func _configure_spellcaster(character: CharacterState, caste: CasteDefinition, rng: RealmzRng, effective_starting_level: int = 1) -> void:
	var rows := caste.spellcaster_rows()
	for index: int in mini(3, rows.size()):
		var row := rows[index]
		if row.y <= 0:
			continue
		character.spellcaster_type = index + 1
		character.maximum_spell_attacks = 1
		if effective_starting_level >= row.y:
			match character.spellcaster_type:
				1: character.maximum_spell_points = 4 + character.knowledge + rng.draw(maxi(1, character.judgment), &"character.create.spell-points")
				2: character.maximum_spell_points = 4 + character.judgment + rng.draw(maxi(1, character.knowledge), &"character.create.spell-points")
				3: character.maximum_spell_points = 10 + rng.draw(maxi(1, character.judgment + character.knowledge), &"character.create.spell-points")
	character.spell_points = character.maximum_spell_points


func _initialize_abilities(character: CharacterState, race: RaceDefinition, caste: CasteDefinition) -> void:
	for index: int in 14:
		var initial_value := caste.initial_ability_value(index)
		var ability := initial_value + race.ability_bonus(index) if initial_value != 0 else 0
		ability += _ability_attribute_modifier(STRENGTH_ABILITY_MODIFIERS, index, character.brawn) if initial_value != 0 else 0
		ability += _ability_attribute_modifier(AGILITY_ABILITY_MODIFIERS, index, character.agility) if initial_value != 0 else 0
		character.set_ability_value(index, ability)
	for index: int in 12:
		character.set_ability_value(index, clampi(character.ability_value(index), 0, 100))


func _ability_attribute_modifier(table: Dictionary, ability_index: int, attribute: int) -> int:
	if not table.has(ability_index):
		return 0
	var value_index := ABILITY_ATTRIBUTE_VALUES.find(attribute)
	if value_index < 0:
		return 0
	var values: Array = table[ability_index]
	return int(values[value_index])


func _level_spellcaster_type(caste: CasteDefinition) -> int:
	var rows := caste.spellcaster_rows()
	for index: int in mini(3, rows.size()):
		if rows[index].y > 0:
			return index + 1
	return 0


func _apply_age_change(character: CharacterState, race: RaceDefinition, caste: CasteDefinition, age_group: int, direction: int) -> void:
	var change := race.age_change(age_group - 1)
	if change.size() != 15:
		return
	var before_strength := strength_bonuses(character.brawn, caste.maximum_damage_bonus())
	character.to_hit = _signed_16(character.to_hit - before_strength.to_hit_bonus)
	character.damage_bonus = _signed_16(character.damage_bonus - before_strength.damage_bonus)
	character.brawn = _signed_16(character.brawn + direction * change[0])
	var after_strength := strength_bonuses(character.brawn, caste.maximum_damage_bonus())
	character.to_hit = _signed_16(character.to_hit + after_strength.to_hit_bonus)
	character.damage_bonus = _signed_16(character.damage_bonus + after_strength.damage_bonus)
	character.knowledge = _signed_16(character.knowledge + direction * change[1])
	character.judgment = _signed_16(character.judgment + direction * change[2])
	character.agility = _signed_16(character.agility + direction * change[3])
	character.vitality = _signed_16(character.vitality + direction * change[4])
	character.luck = _signed_16(character.luck + direction * change[5])
	character.magic_resistance = _signed_16(character.magic_resistance + direction * change[6])
	character.maximum_movement = maxi(2, _signed_16(character.maximum_movement + direction * change[7]))
	for save_index: int in 7:
		character.set_save_value_raw(save_index, _signed_16(character.save_value(save_index) + direction * change[8 + save_index]))


static func _signed_16(value: int) -> int:
	var wrapped := value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


static func _signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped


func _level_spell_points(character: CharacterState, caste: CasteDefinition, rng: RealmzRng) -> int:
	if character.level <= 1 or character.spellcaster_type < 1:
		return 0
	var rows := caste.spellcaster_rows()
	var row_index := character.spellcaster_type - 1
	if row_index >= rows.size() or rows[row_index].y <= 0 or rows[row_index].y > character.level:
		return 0
	if character.spellcaster_type == 1:
		return character.level + rng.draw(maxi(1, character.knowledge + int(float(character.judgment) / 2.0)), &"character.level.spell-points")
	return character.level + rng.draw(maxi(1, character.judgment + int(float(character.knowledge) / 2.0)), &"character.level.spell-points")
