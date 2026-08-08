class_name CharacterRules
extends RefCounted

const ATTRIBUTE_COUNT: int = 6


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


func create_character(character_id: String, character_name: String, race: RaceDefinition, caste: CasteDefinition, gender: int, rng: RealmzRng) -> CharacterState:
	if race == null or caste == null or rng == null:
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
	_configure_spellcaster(result, caste, rng)
	var items: Array[ItemInstance] = []
	for index: int in caste.start_items().size():
		var item_id := caste.start_items()[index]
		items.append(ItemInstance.new("%s.item.%d" % [character_id, index], item_id))
	result.set_inventory(items)
	return result


func level_up(character: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng) -> LevelUpResult:
	if character == null or race == null or caste == null or rng == null:
		return null
	character.level += 1
	character.normal_attacks = race.base_attacks + caste.bonus_attacks
	for required_level: int in caste.attack_levels():
		if required_level > 0 and required_level <= character.level:
			character.normal_attacks += 1
	character.normal_attacks = mini(character.normal_attacks, 2 * race.maximum_attacks)
	character.attacks_remaining = character.normal_attacks
	for index: int in ConditionSet.CHARACTER_COUNT:
		if caste.condition_level(index) == character.level:
			character.conditions.add(index, -1)
	character.to_hit += caste.level_to_hit()
	character.dodge += caste.level_dodge()
	character.hand_to_hand += caste.level_hand_to_hand()
	if caste.level_missile() > 0:
		character.missile += rng.draw(caste.level_missile(), &"character.level.missile")
	var spell_gain := _level_spell_points(character, caste, rng)
	character.spell_points += spell_gain
	character.maximum_spell_points += spell_gain
	var vitality_bonus := mini(maxi(0, character.vitality - 16), caste.maximum_stamina_bonus)
	var stamina_gain := rng.draw(maxi(1, caste.level_stamina_die()), &"character.level.stamina") + vitality_bonus
	character.current_health += stamina_gain
	character.maximum_health += stamina_gain
	var magic_gain := 1 if rng.draw(100, &"character.level.magic-resistance") <= character.judgment + character.knowledge + character.vitality else 0
	character.magic_resistance += magic_gain
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


func _configure_spellcaster(character: CharacterState, caste: CasteDefinition, rng: RealmzRng) -> void:
	var rows := caste.spellcaster_rows()
	for index: int in mini(3, rows.size()):
		var row := rows[index]
		if row.y <= 0:
			continue
		character.spellcaster_type = index + 1
		character.maximum_spell_attacks = 1
		if character.level >= row.y:
			match character.spellcaster_type:
				1: character.maximum_spell_points = 4 + character.knowledge + rng.draw(maxi(1, character.judgment), &"character.create.spell-points")
				2: character.maximum_spell_points = 4 + character.judgment + rng.draw(maxi(1, character.knowledge), &"character.create.spell-points")
				3: character.maximum_spell_points = 10 + rng.draw(maxi(1, character.judgment + character.knowledge), &"character.create.spell-points")
	character.spell_points = character.maximum_spell_points


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
