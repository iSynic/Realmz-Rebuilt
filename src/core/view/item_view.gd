class_name ItemView
extends RefCounted

var instance_id: String
var definition_id: String
var classic_id: int
var name: String
var charges: int
var equipped: bool
var identified: bool
var usable: bool
var weight: int
var description: String
var value: int
var restriction_reason: String = ""
var icon_id: int
var icon_resource_type: String = "cicn"
var item_type: int
var curse_revealed: bool = false
var facts: Array[ItemFactView] = []
var properties: Array[String] = []
var restrictions: Array[String] = []
var actions := InventoryItemActionsView.new()


func _init(instance: ItemInstance, definition: ItemDefinition, presentation_definition: ItemDefinition = null, content: RealmzContent = null) -> void:
	instance_id = instance.id
	charges = instance.charges
	equipped = instance.equipped
	identified = instance.identified
	if definition == null:
		classic_id = 0
		definition_id = ""
		name = "Unknown item"
		description = "Definition unavailable"
		return
	var visible_definition := presentation_definition if presentation_definition != null else definition
	icon_id = definition.visible_icon_id(identified)
	item_type = visible_definition.item_type
	name = visible_definition.name if identified else visible_definition.unidentified_name
	usable = visible_definition.initial_charges > 0
	weight = visible_definition.instance_weight(instance.charges)
	description = visible_definition.description if identified else "This item's properties are unknown until it is identified."
	value = visible_definition.cost if identified else 0
	definition_id = visible_definition.id if identified else ""
	classic_id = visible_definition.classic_id if identified else 0
	curse_revealed = equipped and not definition.cursed_item_id.is_empty()
	_populate_facts(visible_definition)
	_populate_properties(visible_definition, content)
	_populate_restrictions(visible_definition, content)


func _populate_facts(definition: ItemDefinition) -> void:
	facts.append(ItemFactView.new(&"weight", "Weight", str(weight)))
	if definition.hands != 0:
		facts.append(ItemFactView.new(&"hands", "Hands", str(definition.hands)))
	if definition.vs_small != 0:
		facts.append(ItemFactView.new(&"damage-range", "Damage", "%d–%d" % [1 + definition.damage_bonus, definition.damage_bonus + definition.vs_small]))
	if not identified:
		return
	_add_numeric_fact(&"damage-bonus", "Damage bonus", definition.damage_bonus)
	_add_numeric_fact(&"strength", "Strength", definition.strength_bonus)
	_add_numeric_fact(&"luck", "Luck", definition.luck_bonus)
	_add_numeric_fact(&"armor", "Armor", definition.armor_bonus)
	_add_numeric_fact(&"movement", "Movement", definition.movement_bonus)
	_add_numeric_fact(&"magic-resistance", "Magic resistance", definition.magic_resistance_bonus)
	_add_numeric_fact(&"spell-points", "Spell points", definition.spell_point_bonus)
	_add_numeric_fact(&"heat", "Heat damage", definition.heat)
	_add_numeric_fact(&"cold", "Cold damage", definition.cold)
	_add_numeric_fact(&"electric", "Electrical damage", definition.electric)
	_add_numeric_fact(&"undead", "Versus undead", definition.vs_undead)
	_add_numeric_fact(&"demon-devil", "Versus demons/devils", definition.vs_demon_devil)
	_add_numeric_fact(&"evil", "Versus evil", definition.vs_evil)


func _populate_properties(definition: ItemDefinition, content: RealmzContent) -> void:
	if not identified:
		return
	if curse_revealed:
		properties.append("The curse has been revealed; this equipped item cannot be removed normally.")
	if definition.heat + definition.cold + definition.electric + definition.vs_undead + definition.vs_demon_devil + definition.vs_evil != 0:
		properties.append("This weapon does special damage.")
	if definition.item_type < 0 or definition.item_type == 23 or definition.item_type == 25:
		properties.append("This special item belongs to this campaign and does not transfer to another campaign.")
	if definition.special_1 == 120:
		properties.append("This weapon always hits in combat.")
	elif definition.special_1 == 121:
		properties.append("This weapon doubles its magical to-hit bonus without doubling its damage bonus.")
	elif definition.special_1 == 122 and definition.special_2 in [1, 2, 3, 4]:
		var attack_labels: Array[String] = ["one-half", "one", "one and one-half", "two"]
		var attacks: String = attack_labels[definition.special_2 - 1]
		properties.append("Gives the character %s extra attack%s per combat round." % [attacks, "" if definition.special_2 == 2 else "s"])
	if definition.special_2 > 1100:
		var spell := content.spell_by_classic_id(definition.special_2) if content != null else null
		properties.append("Stores the spell %s." % (spell.name if spell != null else "Classic spell %d" % definition.special_2))
	if definition.special_3 < 0:
		properties.append("%+d to hit Classic monster type %d." % [definition.special_5, absi(definition.special_3)])
	elif definition.special_3 > 0 and definition.special_3 < 16:
		properties.append("%+d to %s." % [definition.special_5, _ability_name(definition.special_3)])
	if definition.special_4 > 0 and definition.special_4 < 16:
		properties.append("%+d to %s." % [definition.special_5, _ability_name(definition.special_4)])


func _populate_restrictions(definition: ItemDefinition, content: RealmzContent) -> void:
	if not definition.specific_caste_id.is_empty():
		var caste := content.caste_by_id(definition.specific_caste_id) if content != null else null
		restrictions.append("Usable only by %s." % (caste.name if caste != null else _display_id(definition.specific_caste_id)))
	if not definition.specific_race_id.is_empty():
		var race := content.race_by_id(definition.specific_race_id) if content != null else null
		restrictions.append("Usable only by %s." % (race.name if race != null else _display_id(definition.specific_race_id)))
	if content == null:
		if definition.caste_restrictions != 0:
			restrictions.append("Classic class restrictions apply.")
		if definition.race_restrictions != 0:
			restrictions.append("Classic race restrictions apply.")
		if definition.caste_class_only != 0:
			restrictions.append("Only selected Classic class groups may use this item.")
		if definition.race_class_only != 0:
			restrictions.append("Only selected Classic race groups may use this item.")
		return
	var excluded_castes: Array[String] = []
	var allowed_castes: Array[String] = []
	for caste: CasteDefinition in content.caste_definitions():
		var bit := 1 << (caste.caste_class - 1) if caste.caste_class > 0 else 0
		if bit != 0 and (definition.caste_restrictions & bit) != 0:
			excluded_castes.append(caste.name)
		if bit != 0 and (definition.caste_class_only & bit) != 0:
			allowed_castes.append(caste.name)
	_add_name_restriction("Not usable by", excluded_castes)
	_add_name_restriction("Usable only by", allowed_castes)
	var excluded_races: Array[String] = []
	var allowed_races: Array[String] = []
	for race: RaceDefinition in content.race_definitions():
		if (definition.race_restrictions & race.descriptor_flags) != 0:
			excluded_races.append(race.name)
		if definition.race_class_only != 0 and (definition.race_class_only & race.descriptor_flags) == definition.race_class_only:
			allowed_races.append(race.name)
	_add_name_restriction("Not usable by", excluded_races)
	_add_name_restriction("Usable only by", allowed_races)


func _add_numeric_fact(id: StringName, label: String, amount: int) -> void:
	if amount != 0:
		facts.append(ItemFactView.new(id, label, "%+d" % amount))


func _add_name_restriction(prefix: String, names: Array[String]) -> void:
	if not names.is_empty():
		restrictions.append("%s %s." % [prefix, ", ".join(names)])


static func _ability_name(index: int) -> String:
	return CharacterView.ABILITY_NAMES[index - 1] if index > 0 and index <= CharacterView.ABILITY_NAMES.size() else "Classic ability %d" % index


static func _display_id(value: String) -> String:
	return value.get_file().replace("_", " ").replace("-", " ").capitalize()
