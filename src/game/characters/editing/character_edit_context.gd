## Immutable rules, definitions and catalogs one character draft edits against.

class_name CharacterEditContext
extends RefCounted

var race: RaceDefinition
var caste: CasteDefinition
var rules: RealmzRules
var items: ItemCatalog
var spells: SpellCatalog
var appearance: CharacterCatalog
## Why Items, Spells and Level Up are view-only, or empty when they are editable.
var rules_unavailable_reason := ""


func _init(content: RealmzContent, character: CharacterState, custom_rules_reason: String = "") -> void:
	rules = RealmzRules.new(content != null and content.package_schema_version >= 7)
	if content == null or character == null:
		rules_unavailable_reason = "The Classic library isn't loaded yet."
		return
	items = content.items
	spells = content.magic
	appearance = content.characters
	if not custom_rules_reason.is_empty():
		rules_unavailable_reason = custom_rules_reason
		return
	race = content.characters.race_by_id(character.race_id)
	caste = content.characters.caste_by_id(character.caste_id)
	if race == null or caste == null:
		rules_unavailable_reason = "This character's race or class isn't in the Classic library."


func rules_available() -> bool:
	return rules_unavailable_reason.is_empty()


func item_definitions() -> Array[ItemDefinition]:
	return items.definitions() if items != null else [] as Array[ItemDefinition]


## Spells this character may know: its own caster type, up to its caste's highest
## level-up spell level, matching the in-play level-up candidates.
func spell_candidates(character: CharacterState) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	if not rules_available() or spells == null or character.spellcaster_type < 1:
		return result
	var maximum_level := rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in spells.definitions():
		if int(float(spell.classic_id) / 1000.0) == character.spellcaster_type and spell.classic_tier() >= 0 and spell.classic_tier() < maximum_level and spell.classic_slot() >= 1 and spell.classic_slot() <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


## Lowest and highest age in whole years across the race's five age groups.
func age_year_range() -> Vector2i:
	if race == null:
		return Vector2i.ZERO
	return Vector2i(race.age_range(0).x, race.age_range(4).y)


## Total strength granted by equipped items, which Rebuilt folds into brawn.
func magical_strength(character: CharacterState) -> int:
	var total := 0
	for instance: ItemInstance in character.inventory():
		var definition := items.item_by_id(instance.definition_id) if items != null and instance.equipped else null
		if definition != null:
			total += definition.strength_bonus
	return total
