class_name DefinitionOptionView
extends RefCounted

var id: String
var name: String
var description: String = ""
var related_ids: Array[String] = []
var facts: Array[String] = []


func _init(definition_id: String, display_name: String, display_description: String = "", related_definition_ids: Array[String] = [], display_facts: Array[String] = []) -> void:
	id = definition_id
	name = display_name
	description = display_description
	related_ids = related_definition_ids.duplicate()
	facts = display_facts.duplicate()


static func from_race(definition: RaceDefinition) -> DefinitionOptionView:
	var display_facts: Array[String] = [
		"Movement %d" % definition.base_movement,
	]
	var attack_fraction := _race_attack_fraction(definition.base_attacks)
	if not attack_fraction.is_empty():
		display_facts.append("Attacks %s • Maximum %d" % [attack_fraction, definition.maximum_attacks])
	_append_signed(display_facts, "Magic resistance", definition.magic_resistance)
	_append_signed(display_facts, "Missile adjustment", definition.missile_bonus)
	_append_signed(display_facts, "Two-hand adjustment", definition.two_hand_bonus)
	if definition.max_age > 0:
		display_facts.append("Maximum age %d" % definition.max_age)
	var attributes := _named_modifiers(definition.attribute_bonus, ["Brawn", "Knowledge", "Judgment", "Agility", "Vitality", "Luck"])
	if not attributes.is_empty():
		display_facts.append("Attributes • %s" % attributes)
	var saves := _named_modifiers(definition.save_bonus, ["Charm", "Fire", "Cold", "Shock", "Chemical", "Mental", "SP drain", "Special"])
	if not saves.is_empty():
		display_facts.append("Saves • %s" % saves)
	return DefinitionOptionView.new(definition.id, definition.name, definition.description, definition.eligible_caste_ids, display_facts)


static func from_caste(definition: CasteDefinition) -> DefinitionOptionView:
	var display_facts: Array[String] = [
		"Stamina d%d initially • d%d per level" % [definition.initial_stamina_die(), definition.level_stamina_die()],
		"To hit %+d initially • %+d per level" % [definition.initial_to_hit(), definition.level_to_hit()],
		"Dodge %+d initially • %+d per level" % [definition.initial_dodge(), definition.level_dodge()],
	]
	if definition.can_use_missile:
		display_facts.append("Missile %+d initially • %+d per level" % [definition.initial_missile(), definition.level_missile()])
	else:
		display_facts.append("Cannot use missile weapons")
	display_facts.append("Hand to hand %+d initially • %+d per level" % [definition.initial_hand_to_hand(), definition.level_hand_to_hand()])
	if definition.minimum_age_group > 0:
		display_facts.append("Minimum age %s" % _minimum_age_label(definition.minimum_age_group))
	_append_signed(display_facts, "Movement", definition.movement_bonus)
	var attack_bonus := _caste_attack_fraction(definition.bonus_attacks)
	if not attack_bonus.is_empty():
		display_facts.append("Bonus attacks %s" % attack_bonus)
	_append_signed(display_facts, "Two-hand adjustment", definition.two_hand_bonus)
	_append_signed(display_facts, "Maximum stamina bonus", definition.maximum_stamina_bonus)
	if definition.magic_resistance_multiplier != 1:
		display_facts.append("Magic resistance ×%d" % definition.magic_resistance_multiplier)
	if definition.spellcaster_rows().any(func(row: Vector3i) -> bool: return row.y > 0):
		display_facts.append("Spellcaster")
	if definition.gets_missile_bonus:
		display_facts.append("Receives missile bonus")
	if definition.start_money != 0:
		display_facts.append("Starting gold %d" % definition.start_money)
	var attributes := _named_modifiers(definition.attribute_bonus, ["Brawn", "Knowledge", "Judgment", "Agility", "Vitality", "Luck"])
	if not attributes.is_empty():
		display_facts.append("Attributes • %s" % attributes)
	var saves := _named_modifiers(definition.save_bonus, ["Charm", "Fire", "Cold", "Shock", "Chemical", "Mental", "SP drain", "Special"])
	if not saves.is_empty():
		display_facts.append("Saves • %s" % saves)
	return DefinitionOptionView.new(definition.id, definition.name, definition.description, definition.eligible_race_ids, display_facts)


static func _append_signed(target: Array[String], label: String, value: int) -> void:
	if value != 0:
		target.append("%s %s" % [label, "%+d" % value])


static func _named_modifiers(reader: Callable, labels: Array[String]) -> String:
	var values: Array[String] = []
	for index: int in labels.size():
		var value := int(reader.call(index))
		if value != 0:
			values.append("%s %+d" % [labels[index], value])
	return " • ".join(values)


static func _race_attack_fraction(value: int) -> String:
	match value:
		2: return "1"
		3: return "1 1/2"
		4: return "2"
		_: return ""


static func _caste_attack_fraction(value: int) -> String:
	match value:
		1: return "1/2"
		2: return "1"
		3: return "1 1/2"
		4: return "2"
		_: return ""


static func _minimum_age_label(value: int) -> String:
	match value:
		2: return "Young"
		3: return "Prime"
		4: return "Adult"
		5: return "Senior"
		_: return "Youth"
