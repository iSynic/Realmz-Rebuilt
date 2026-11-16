## Applies one Character Files editor operation to a draft character.
## Every operation reuses the in-play Classic rules and returns a reason when it can't apply.

class_name CharacterEditOperations
extends RefCounted

var _context: CharacterEditContext


func _init(context: CharacterEditContext) -> void:
	_context = context


## Applies `operation` to `character`; returns "" or the reason it was refused.
## Level Up writes its rolled gains into `operation["result"]`.
func apply(character: CharacterState, operation: Dictionary) -> String:
	match operation.get("kind", &"") as StringName:
		&"field": return _set_field(character, operation.field, int(operation.value))
		&"save": return _set_indexed(character, &"save", int(operation.index), int(operation.value))
		&"skill": return _set_indexed(character, &"skill", int(operation.index), int(operation.value))
		&"condition": return _set_condition(character, int(operation.index), int(operation.value))
		&"name": return _set_name(character, String(operation.value))
		&"gender": return _set_gender(character, int(operation.value))
		&"portrait", &"icon": return _set_appearance(character, operation.kind, String(operation.value))
		&"age": return _set_age(character, int(operation.value))
		&"level_up": return _level_up(character, operation)
		&"level_spells": return _choose_level_spells(character, operation.spell_ids)
		&"spell": return _set_spell(character, String(operation.spell_id), bool(operation.known))
	return CharacterEditItems.new(_context).apply(character, operation)


func _set_field(character: CharacterState, field: StringName, value: int) -> String:
	if not CharacterEditLimits.LABELS.has(field):
		return "This value can't be edited."
	var limits := CharacterEditLimits.field_range(field, character, _context.magical_strength(character))
	var label: String = CharacterEditLimits.LABELS[field]
	if value < limits.x or value > limits.y:
		return "%s must be %s to %s." % [label, CharacterEditLimits.group_digits(limits.x), CharacterEditLimits.group_digits(limits.y)]
	if field in CharacterEditLimits.MONEY:
		var change := (value - CharacterEditLimits.field_value(character, field)) * CharacterEditLimits.money_weight(field)
		# Spending money is always allowed, even for a character already over the limit.
		if change > 0 and character.carried_load + change > character.maximum_load:
			return "%s would bring the load to %s, over the %s limit." % [label, CharacterEditLimits.group_digits(character.carried_load + change), CharacterEditLimits.group_digits(character.maximum_load)]
		character.carried_load += change
		if _context.race != null:
			_context.rules.characters.recalculate_movement(character, _context.race, _equipped_movement_bonus(character))
	if field == &"brawn":
		return _set_brawn(character, value)
	CharacterEditLimits.set_field_value(character, field, value)
	if field == &"maximum_health":
		character.current_health = mini(character.current_health, value)
	elif field == &"maximum_spell_points":
		character.spell_points = mini(character.spell_points, value)
	return ""


## Brawn moves to-hit, damage and the load limit exactly as Classic aging does.
func _set_brawn(character: CharacterState, value: int) -> String:
	var maximum_bonus := _context.caste.attributes.maximum_damage_bonus() if _context.caste != null else 32_767
	var before := _context.rules.characters.strength_bonuses(character.brawn, maximum_bonus)
	var after := _context.rules.characters.strength_bonuses(value, maximum_bonus)
	var new_load := maxi(500, value * value * 20)
	# A character already over the limit may still raise Brawn part of the way.
	if new_load < character.carried_load and new_load < character.maximum_load:
		return "Max load would fall to %s, below the %s carried. Remove %s load first." % [CharacterEditLimits.group_digits(new_load), CharacterEditLimits.group_digits(character.carried_load), CharacterEditLimits.group_digits(character.carried_load - new_load)]
	character.to_hit += after.to_hit_bonus - before.to_hit_bonus
	character.damage_bonus += after.damage_bonus - before.damage_bonus
	character.brawn = value
	if _context.race != null:
		_context.rules.characters.recalculate_movement(character, _context.race, _equipped_movement_bonus(character))
	else:
		character.maximum_load = new_load
	return ""


func _set_indexed(character: CharacterState, kind: StringName, index: int, value: int) -> String:
	var limits := CharacterEditLimits.SAVE_RANGE if kind == &"save" else CharacterEditLimits.SKILL_RANGE
	var count := 8 if kind == &"save" else 15
	if index < 0 or index >= count:
		return "This value can't be edited."
	if value < limits.x or value > limits.y:
		return "Use a value from %d to %d." % [limits.x, limits.y]
	if kind == &"save":
		character.set_save_value(index, value, false)
	else:
		character.set_ability_value(index, value, false)
	return ""


## Permanent (negative) values come from race and class and stay locked.
func _set_condition(character: CharacterState, index: int, value: int) -> String:
	if index < 0 or index >= ConditionSet.CHARACTER_COUNT:
		return "This condition can't be edited."
	if character.conditions.value(index) < 0:
		return "This condition is permanent; it comes from race or class."
	if value < CharacterEditLimits.CONDITION_RANGE.x or value > CharacterEditLimits.CONDITION_RANGE.y:
		return "Conditions are 0 to 32,767."
	character.conditions.set_value(index, value)
	return ""


func _set_name(character: CharacterState, value: String) -> String:
	var error := CharacterEditLimits.name_error(value)
	if error.is_empty():
		character.name = value.strip_edges()
	return error


func _set_gender(character: CharacterState, value: int) -> String:
	if value not in [1, 2]:
		return "Choose Male or Female."
	character.gender = value
	return ""


func _set_appearance(character: CharacterState, kind: StringName, value: String) -> String:
	var role := CharacterAppearanceDefinition.PORTRAIT if kind == &"portrait" else CharacterAppearanceDefinition.COMBAT_ICON
	if _context.appearance == null or not _context.appearance.appearance_is_available(value, role):
		return "That artwork isn't available."
	if kind == &"portrait":
		character.portrait_id = value
	else:
		character.combat_icon_id = value
	return ""


## Ages in whole years within the race's age table, applying each crossed age group.
func _set_age(character: CharacterState, years: int) -> String:
	if _context.race == null or _context.caste == null:
		return _context.rules_unavailable_reason
	var limits := _context.age_year_range()
	if years < limits.x or years > limits.y:
		return "%s ages are %d to %d." % [_context.race.name, limits.x, limits.y]
	var days := years * 365 + posmod(character.age_days, 365)
	if _context.rules.characters.infer_age_group(days, _context.race) == 0:
		return "No %s age group includes %d years." % [_context.race.name, years]
	var before := CharacterStateCodec.copy(character)
	_context.rules.characters.set_age_days(character, _context.race, _context.caste, days)
	_context.rules.characters.recalculate_movement(character, _context.race, _equipped_movement_bonus(character))
	return CharacterEditLimits.range_error(character, before)


## Runs the complete in-play level-up with the operation's dice, then resets
## experience to the next level's requirement as Classic opcode 102 does.
func _level_up(character: CharacterState, operation: Dictionary) -> String:
	if not _context.rules_available():
		return _context.rules_unavailable_reason
	if character.level >= CharacterEditLimits.SHORT_MAXIMUM:
		return "This character is at the highest level."
	var previous_level := character.level
	var result := _context.rules.characters.level_up(character, _context.race, _context.caste, RealmzRng.new(int(operation.seed)))
	if result == null or result.state == LevelUpResult.State.UNSAFE_CANDIDATE:
		return "This class's level-up data can't be applied safely."
	# A missing or non-positive authored threshold leaves the character ready to level
	# rather than storing positive experience outside Classic's range.
	character.experience = mini(0, 1 - _context.caste.progression.victory_threshold(clampi(previous_level, 1, 30) - 1))
	operation["result"] = {"stamina": result.stamina_gained, "spellPoints": result.spell_points_gained, "toHit": result.to_hit_gained, "magicResistance": result.magic_resistance_gained}
	return ""


## The post-Level Up spell choice. The editor sets spells directly, so any spell this
## caster can learn may be chosen without Classic's selection-point budget.
func _choose_level_spells(character: CharacterState, spell_ids: Array) -> String:
	var candidates := {}
	for spell: SpellDefinition in _context.spell_candidates(character):
		candidates[spell.id] = spell
	var selected: Array[String] = []
	for value: Variant in spell_ids:
		var spell_id := String(value)
		if selected.has(spell_id) or not candidates.has(spell_id):
			return "That spell isn't available to this caster."
		selected.append(spell_id)
	var others: Array[String] = []
	for spell_id: String in character.known_spells():
		if not candidates.has(spell_id):
			others.append(spell_id)
	# Spells outside this choice (another caster type, or above the caste's levels) stay known.
	_replace_known_spells(character, selected + others)
	return ""


func _set_spell(character: CharacterState, spell_id: String, known: bool) -> String:
	if not _context.rules_available():
		return _context.rules_unavailable_reason
	var spells := character.known_spells()
	if not known:
		if not spells.has(spell_id):
			return "This spell isn't known."
		spells.erase(spell_id)
		_replace_known_spells(character, spells)
		return ""
	if spells.has(spell_id):
		return "This spell is already known."
	if not _context.spell_candidates(character).any(func(spell: SpellDefinition) -> bool: return spell.id == spell_id):
		return "That spell isn't available to this caster."
	spells.append(spell_id)
	_replace_known_spells(character, spells)
	return ""


## Fast Spell bindings may only name known spells, so forgetting a spell clears its shortcut.
static func _replace_known_spells(character: CharacterState, spell_ids: Array[String]) -> void:
	character.set_known_spells(spell_ids)
	for index: int in character.fast_spells().size():
		var binding := character.fast_spell_at(index)
		if binding != null and not binding.is_empty() and not spell_ids.has(binding.spell_id):
			character.clear_fast_spell(index)


func _equipped_movement_bonus(character: CharacterState) -> int:
	var total := 0
	for instance: ItemInstance in character.inventory():
		var definition := _context.items.item_by_id(instance.definition_id) if _context.items != null and instance.equipped else null
		if definition != null:
			total += definition.movement_bonus
	return total
