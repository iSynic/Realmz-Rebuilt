## Legal ranges and labels for every value the Character Files editor can change.

class_name CharacterEditLimits
extends RefCounted

const ATTRIBUTES: Array[StringName] = [&"brawn", &"knowledge", &"judgment", &"agility", &"vitality", &"luck"]
const MONEY: Array[StringName] = [&"gold", &"gems", &"jewelry"]
## Level Up rolls read these, so a pending Level Up locks them until it is undone.
const LEVEL_UP_INPUTS: Array[StringName] = [&"vitality", &"knowledge", &"judgment"]
const LABELS := {
	&"brawn": "Brawn", &"knowledge": "Knowledge", &"judgment": "Judgment", &"agility": "Agility",
	&"vitality": "Vitality", &"luck": "Luck", &"current_health": "Stamina", &"maximum_health": "Max stamina",
	&"spell_points": "Spell points", &"maximum_spell_points": "Max SP", &"armor": "Base armor",
	&"gold": "Gold", &"gems": "Gems", &"jewelry": "Jewelry", &"experience": "Experience",
	&"prestige_penalty": "Prestige penalty",
}
## Classic 16-bit load stays in range while brawn (including magical strength) is at most 57.
const BRAWN_MAXIMUM := 57
const ATTRIBUTE_RANGE := Vector2i(1, 127)
const SHORT_MAXIMUM := 32_767
const MONEY_RANGE := Vector2i(0, 65_535)
const SAVE_RANGE := Vector2i(-99, 120)
const SKILL_RANGE := Vector2i(0, 100)
const CONDITION_RANGE := Vector2i(0, 32_767)
const EXPERIENCE_RANGE := Vector2i(-2_147_483_648, 0)
const PRESTIGE_RANGE := Vector2i(0, 2_147_483_647)
const NAME_LENGTH := 20


## The legal range for one field given the character's current draft.
static func field_range(field: StringName, character: CharacterState, magical_strength: int) -> Vector2i:
	match field:
		&"brawn": return Vector2i(maxi(1, 1 + magical_strength), BRAWN_MAXIMUM)
		&"maximum_health": return Vector2i(1, SHORT_MAXIMUM)
		&"current_health": return Vector2i(0, maxi(0, character.maximum_health))
		&"maximum_spell_points": return Vector2i(0, SHORT_MAXIMUM)
		&"spell_points": return Vector2i(0, maxi(0, character.maximum_spell_points))
		&"armor": return Vector2i(-SHORT_MAXIMUM - 1, SHORT_MAXIMUM)
		&"experience": return EXPERIENCE_RANGE
		&"prestige_penalty": return PRESTIGE_RANGE
	if field in MONEY:
		return MONEY_RANGE
	return ATTRIBUTE_RANGE


static func field_value(character: CharacterState, field: StringName) -> int:
	var value: int = character.money.get(field) if field in MONEY else character.get(field)
	return value


static func set_field_value(character: CharacterState, field: StringName, value: int) -> void:
	if field in MONEY:
		character.money.set(field, value)
	else:
		character.set(field, value)


## Load per coin, gem or jewelry piece, from the economy's single owner.
static func money_weight(field: StringName) -> int:
	return EconomyRules.wealth_weight(WealthState.Kind.JEWELRY if field == &"jewelry" else (WealthState.Kind.GEMS if field == &"gems" else WealthState.Kind.GOLD))


## The first value a change pushed outside its Classic range, or "". A value `before`
## already held out of range blocks only when it moves further out.
static func range_error(character: CharacterState, before: CharacterState = null) -> String:
	var existing := range_errors(before) if before != null else {}
	var errors := range_errors(character)
	for key: String in errors:
		var entry: Array = errors[key]
		var severity: int = entry[0]
		var known: Array = existing.get(key, [0])
		var known_severity: int = known[0]
		if not existing.has(key) or severity > known_severity:
			var reason: String = entry[1]
			return reason
	return ""


## Every value outside its Classic range, keyed by value, as [distance outside, message].
static func range_errors(character: CharacterState) -> Dictionary:
	var errors := {}
	for field: StringName in ATTRIBUTES:
		var high := BRAWN_MAXIMUM if field == &"brawn" else ATTRIBUTE_RANGE.y
		_check(errors, String(field), field_value(character, field), Vector2i(ATTRIBUTE_RANGE.x, high), "%s would become %%d, outside %d–%d." % [LABELS[field], ATTRIBUTE_RANGE.x, high])
	for index: int in 8:
		_check(errors, "save%d" % index, character.save_value(index), SAVE_RANGE, "%s save would become %%d, outside −99 to 120." % CharacterView.SAVE_NAMES[index])
	for index: int in 15:
		_check(errors, "skill%d" % index, character.ability_value(index), SKILL_RANGE, "Skill %d would become %%d, outside 0 to 100." % (index + 1))
	var over := maxi(character.current_health - character.maximum_health, character.spell_points - character.maximum_spell_points)
	if over > 0:
		errors["current"] = [over, "Current stamina or spell points would exceed their maximum."]
	if character.maximum_load < character.carried_load:
		errors["load"] = [character.carried_load - character.maximum_load, "Max load would fall to %s, below the %s carried. Remove %s load first." % [group_digits(character.maximum_load), group_digits(character.carried_load), group_digits(character.carried_load - character.maximum_load)]]
	return errors


static func _check(errors: Dictionary, key: String, value: int, limits: Vector2i, message: String) -> void:
	var distance := maxi(limits.x - value, value - limits.y)
	if distance > 0:
		errors[key] = [distance, message % value]


## Validates a typed name: 1–20 printable characters after trimming.
static func name_error(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return "Enter a name."
	if trimmed.length() > NAME_LENGTH:
		return "Names are at most %d characters." % NAME_LENGTH
	for index: int in trimmed.length():
		var code := trimmed.unicode_at(index)
		if code < 32 or code > 126:
			return "Use letters, digits, spaces and simple punctuation."
	return ""


static func group_digits(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("−" if value < 0 else "") + digits + grouped
