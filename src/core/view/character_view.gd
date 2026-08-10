class_name CharacterView
extends RefCounted

var id: String
var name: String
var current_health: int
var maximum_health: int
var spell_points: int
var maximum_spell_points: int
var level: int
var experience: int
var age_days: int
var age_years: int
var age_group: int
var age_group_name: String
var race_id: String
var caste_id: String
var race_name: String
var caste_name: String
var gender: int
var portrait_id: String
var combat_icon_id: String
var brawn: int
var knowledge: int
var judgment: int
var agility: int
var vitality: int
var luck: int
var armor: int
var to_hit: int
var dodge: int
var missile: int
var two_hand: int
var hand_to_hand: int
var damage_bonus: int
var magic_resistance: int
var normal_attacks: int
var spellcaster_type: int
var movement: int
var maximum_movement: int
var carried_load: int
var maximum_load: int
var traitor: bool
var condition_values: Array[int]
var save_values: Array[int]
var items: Array[ItemView] = []
var spells: Array[SpellView] = []


func _init(character: CharacterState, content: RealmzContent = null) -> void:
	id = character.id
	name = character.name
	current_health = character.current_health
	maximum_health = character.maximum_health
	spell_points = character.spell_points
	maximum_spell_points = character.maximum_spell_points
	level = character.level
	experience = character.experience
	age_days = character.age_days
	age_years = floori(float(character.age_days) / 365.0)
	age_group = character.age_group
	age_group_name = _age_group_name(age_group)
	race_id = character.race_id
	caste_id = character.caste_id
	race_name = race_id.replace("_", " ").replace("-", " ").capitalize()
	caste_name = caste_id.replace("_", " ").replace("-", " ").capitalize()
	if content != null:
		var race := content.race_by_id(race_id)
		var caste := content.caste_by_id(caste_id)
		if race != null:
			race_name = race.name
		if caste != null:
			caste_name = caste.name
	gender = character.gender
	portrait_id = character.portrait_id
	combat_icon_id = character.combat_icon_id
	brawn = character.brawn
	knowledge = character.knowledge
	judgment = character.judgment
	agility = character.agility
	vitality = character.vitality
	luck = character.luck
	armor = character.armor
	to_hit = character.to_hit
	dodge = character.dodge
	missile = character.missile
	two_hand = character.two_hand
	hand_to_hand = character.hand_to_hand
	damage_bonus = character.damage_bonus
	magic_resistance = character.magic_resistance
	normal_attacks = character.normal_attacks
	spellcaster_type = character.spellcaster_type
	movement = character.movement
	maximum_movement = character.maximum_movement
	carried_load = character.carried_load
	maximum_load = character.maximum_load
	traitor = character.traitor
	condition_values = character.conditions.values()
	for index: int in 8:
		save_values.append(character.save_value(index))
	for item: ItemInstance in character.inventory():
		items.append(ItemView.new(item, null if content == null else content.item_by_id(item.definition_id)))
	if content != null:
		for spell_id: String in character.known_spells():
			var definition := content.spell_by_id(spell_id)
			if definition != null:
				spells.append(SpellView.new(definition))


static func _age_group_name(group: int) -> String:
	return CharacterAgingResult.age_group_name(group)
