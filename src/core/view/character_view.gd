class_name CharacterView
extends RefCounted

const CONDITION_NAMES: Array[String] = [
	"In Retreat", "Is Helpless", "Entangled", "Cursed", "Magic Aura", "Stupid", "Moving Slowly", "Shielded from Hits", "Missile Shield", "Poisoned",
	"Regenerating", "Fire Protection", "Cold Protection", "Electrical Protection", "Chemical Protection", "Psi Protection", "Protection from First Level", "Protection from Second Level", "Protection from Third Level", "Protection from Fourth Level",
	"Protection from Fifth Level", "Strong", "Protection from Foe", "Speedy", "Invisible", "Animated", "Turned to Stone", "Blind", "Is Diseased", "Confused",
	"Reflecting Spells", "Reflecting Attacks", "Bonus Damage", "Absorbing Energy", "Losing Energy", "Absorbing Spell Energy", "Hindered Attacks", "Hindered Defense", "Increased Defense", "Silenced",
]
const SAVE_NAMES: Array[String] = ["Charm", "Heat", "Cold", "Electrical", "Chemical", "Mental", "Magic", "Special"]
const SPECIAL_NAMES: Array[String] = [
	"Magic-using", "Undead", "Demonic", "Reptilian", "Evil Creature", "Intelligent", "Large Creature", "Non-Humanoid",
	"Classic special slot 9", "Classic special slot 10", "Classic special slot 11", "Classic special slot 12",
]
const ABILITY_NAMES: Array[String] = [
	"Sneak Attack", "Classic ability 2", "Resurrection", "Major Wound", "Detect Secret", "Acrobatics", "Detect Trap", "Disable Trap",
	"Classic ability 9", "Force Lock", "Classic ability 11", "Pick Lock", "Classic ability 13", "Turn Undead", "Classic ability 15",
]
const AGE_CHANGE_NAMES: Array[String] = [
	"Brawn", "Knowledge", "Judgment", "Agility", "Vitality", "Luck", "Magic Resistance", "Movement",
	"Charm Save", "Heat Save", "Cold Save", "Electrical Save", "Chemical Save", "Mental Save", "Magic Save",
]

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
var race_description: String = ""
var caste_description: String = ""
var gender: int
var gender_name: String
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
var attack_bonus: int
var defense_bonus: int
var dodge: int
var missile: int
var two_hand: int
var hand_to_hand: int
var damage_bonus: int
var magic_resistance: int
var normal_attacks: int
var attacks_per_round: String
var spellcaster_type: int
var movement: int
var maximum_movement: int
var carried_load: int
var maximum_load: int
var traitor: bool
var gold: int
var gems: int
var jewelry: int
var condition_values: Array[int]
var save_values: Array[int]
var conditions: Array[CharacterMetricView] = []
var saving_throws: Array[CharacterMetricView] = []
var special_modifiers: Array[CharacterMetricView] = []
var abilities: Array[CharacterMetricView] = []
var race_traits: Array[CharacterMetricView] = []
var caste_traits: Array[CharacterMetricView] = []
var age_bands: Array[CharacterAgeBandView] = []
var record_available: bool = false
var record_unavailable_reason: String = "Lifetime combat history is not yet tracked, so Castle prestige cannot be calculated accurately."
var items: Array[ItemView] = []
var spells: Array[SpellView] = []
var scrolls: Array[SpellScrollView] = []


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
			race_description = race.description
			_populate_race_details(race)
		if caste != null:
			caste_name = caste.name
			caste_description = caste.description
			_populate_caste_details(caste)
	gender = character.gender
	gender_name = "Male" if gender == 1 else "Female"
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
	attacks_per_round = _attacks_per_round(character.normal_attacks + character.attack_bonus)
	spellcaster_type = character.spellcaster_type
	movement = character.movement
	maximum_movement = character.maximum_movement
	carried_load = character.carried_load
	maximum_load = character.maximum_load
	traitor = character.traitor
	gold = character.money.gold
	gems = character.money.gems
	jewelry = character.money.jewelry
	condition_values = character.conditions.values()
	_refresh_display_bonuses(0)
	for index: int in condition_values.size():
		var amount: int = condition_values[index]
		if amount != 0:
			conditions.append(CharacterMetricView.new(StringName("condition-%d" % index), index, _label_at(CONDITION_NAMES, index, "Classic condition %d" % (index + 1)), amount, "Permanent" if amount < 0 else "Value %d" % amount))
	for index: int in 8:
		var amount := character.save_value(index)
		save_values.append(amount)
		saving_throws.append(CharacterMetricView.new(StringName("save-%d" % index), index, SAVE_NAMES[index], amount))
	for index: int in 12:
		var amount := character.special_value(index)
		if amount != 0:
			special_modifiers.append(CharacterMetricView.new(StringName("special-%d" % index), index, SPECIAL_NAMES[index], amount))
	for index: int in 15:
		var amount := character.ability_value(index)
		if amount != 0:
			var detail := "The original label is not recoverable from the pinned source tree; the Classic slot and value are preserved." if ABILITY_NAMES[index].begins_with("Classic ability") else ""
			abilities.append(CharacterMetricView.new(StringName("ability-%d" % index), index, ABILITY_NAMES[index], amount, detail))
	for item: ItemInstance in character.inventory():
		items.append(ItemView.new(item, null if content == null else content.item_by_id(item.definition_id)))
	if content != null:
		for spell_id: String in character.known_spells():
			var definition := content.spell_by_id(spell_id)
			if definition != null:
				spells.append(SpellView.new(definition))
		for index: int in character.scroll_case().size():
			var scroll := character.scroll_at(index)
			scrolls.append(SpellScrollView.new(index, scroll, content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null))


func apply_equipment(equipment: CharacterCombatEquipment) -> void:
	if equipment == null or not equipment.valid:
		return
	damage_bonus = equipment.effective_damage_bonus
	luck = equipment.effective_luck
	armor = equipment.effective_armor
	_refresh_display_bonuses(equipment.equipped_damage_bonus)


func _refresh_display_bonuses(equipped_damage: int) -> void:
	attack_bonus = to_hit + 5 * equipped_damage
	attack_bonus += 15 if _condition(ConditionRules.STRONG) != 0 else 0
	attack_bonus -= 15 if _condition(ConditionRules.SLOW) != 0 else 0
	attack_bonus -= 10 if _condition(ConditionRules.CONFUSED) != 0 else 0
	attack_bonus -= 15 if _condition(ConditionRules.BLIND) != 0 else 0
	attack_bonus += 5 if _condition(ConditionRules.MAGIC_AURA) != 0 else 0
	attack_bonus -= 5 if _condition(ConditionRules.CURSED) != 0 else 0
	attack_bonus -= absi(_condition(ConditionRules.TANGLED))
	attack_bonus -= absi(_condition(ConditionRules.HINDERED_ATTACKS))
	defense_bonus = armor
	defense_bonus += 10 if _condition(ConditionRules.INVISIBLE) != 0 else 0
	defense_bonus -= 15 if _condition(ConditionRules.SLOW) != 0 else 0
	defense_bonus -= 10 if _condition(ConditionRules.CONFUSED) != 0 else 0
	defense_bonus -= 15 if _condition(ConditionRules.BLIND) != 0 else 0
	defense_bonus += 5 if _condition(ConditionRules.MAGIC_AURA) != 0 else 0
	defense_bonus -= 5 if _condition(ConditionRules.CURSED) != 0 else 0
	defense_bonus -= absi(_condition(ConditionRules.TANGLED))
	defense_bonus -= absi(_condition(ConditionRules.HINDERED_DEFENSE))
	defense_bonus += absi(_condition(ConditionRules.DEFENSE_BONUS))
	defense_bonus += 2 * absi(_condition(ConditionRules.SHIELD_FROM_HITS))


func _condition(index: int) -> int:
	return condition_values[index] if index >= 0 and index < condition_values.size() else 0


func _populate_race_details(race: RaceDefinition) -> void:
	race_traits = [
		CharacterMetricView.new(&"base-movement", 0, "Base Movement", race.base_movement),
		CharacterMetricView.new(&"magic-resistance", 1, "Magic Resistance", race.magic_resistance),
		CharacterMetricView.new(&"two-hand", 2, "Two-Hand Bonus", race.two_hand_bonus),
		CharacterMetricView.new(&"missile", 3, "Missile Bonus", race.missile_bonus),
		CharacterMetricView.new(&"base-attacks", 4, "Base Attacks", race.base_attacks),
		CharacterMetricView.new(&"maximum-attacks", 5, "Maximum Attacks", race.maximum_attacks),
		CharacterMetricView.new(&"maximum-age", 6, "Maximum Age", race.max_age, "Does not die of age" if race.does_not_die else ""),
		CharacterMetricView.new(&"regeneration", 7, "Regenerates", 1 if race.can_regenerate else 0, "Yes" if race.can_regenerate else "No"),
	]
	for band_index: int in 5:
		var age_range := race.age_range(band_index)
		var active := age_years >= age_range.x and age_years <= age_range.y
		age_bands.append(CharacterAgeBandView.new(band_index + 1, _age_group_name(band_index + 1), age_range, active, race.age_change(band_index), AGE_CHANGE_NAMES))


func _populate_caste_details(caste: CasteDefinition) -> void:
	caste_traits = [
		CharacterMetricView.new(&"minimum-age-group", 0, "Minimum Age Group", caste.minimum_age_group, _age_group_name(caste.minimum_age_group)),
		CharacterMetricView.new(&"movement-bonus", 1, "Movement Bonus", caste.movement_bonus),
		CharacterMetricView.new(&"magic-resistance-multiplier", 2, "Magic Resistance Multiplier", caste.magic_resistance_multiplier),
		CharacterMetricView.new(&"two-hand", 3, "Two-Hand Bonus", caste.two_hand_bonus),
		CharacterMetricView.new(&"maximum-stamina-bonus", 4, "Maximum Stamina Bonus", caste.maximum_stamina_bonus),
		CharacterMetricView.new(&"bonus-attacks", 5, "Bonus Attacks", caste.bonus_attacks),
		CharacterMetricView.new(&"maximum-attacks", 6, "Maximum Attacks", caste.maximum_attacks),
		CharacterMetricView.new(&"missile-use", 7, "Can Use Missile Weapons", 1 if caste.can_use_missile else 0, "Yes" if caste.can_use_missile else "No"),
		CharacterMetricView.new(&"missile-bonus", 8, "Receives Missile Bonus", 1 if caste.gets_missile_bonus else 0, "Yes" if caste.gets_missile_bonus else "No"),
	]


static func _attacks_per_round(total: int) -> String:
	if total >= 2 and total <= 19:
		return "%d/%d" % [floori(float(total) / 2.0) if total % 2 == 0 else total, 1 if total % 2 == 0 else 2]
	if total > 12:
		return ">/10"
	return "1/1"


static func _label_at(labels: Array[String], index: int, fallback: String) -> String:
	return fallback if index < 0 or index >= labels.size() else labels[index]


static func _age_group_name(group: int) -> String:
	return CharacterAgingResult.age_group_name(group)
