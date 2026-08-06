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
var race_id: String
var caste_id: String
var brawn: int
var knowledge: int
var judgment: int
var agility: int
var vitality: int
var luck: int
var armor: int
var movement: int
var maximum_movement: int
var carried_load: int
var maximum_load: int
var condition_values: Array[int]
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
	race_id = character.race_id
	caste_id = character.caste_id
	brawn = character.brawn
	knowledge = character.knowledge
	judgment = character.judgment
	agility = character.agility
	vitality = character.vitality
	luck = character.luck
	armor = character.armor
	movement = character.movement
	maximum_movement = character.maximum_movement
	carried_load = character.carried_load
	maximum_load = character.maximum_load
	condition_values = character.conditions.values()
	for item: ItemInstance in character.inventory():
		items.append(ItemView.new(item, null if content == null else content.item_by_id(item.definition_id)))
	if content != null:
		for spell_id: String in character.known_spells():
			var definition := content.spell_by_id(spell_id)
			if definition != null:
				spells.append(SpellView.new(definition))
