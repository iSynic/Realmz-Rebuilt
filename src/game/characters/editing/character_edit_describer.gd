## Names Character Files editor operations for the Changes list.

class_name CharacterEditDescriber
extends RefCounted

var _context: CharacterEditContext


func _init(context: CharacterEditContext) -> void:
	_context = context


## The comparable value an operation changes, read before and after it applies.
func value(character: CharacterState, operation: Dictionary) -> Variant:
	match operation.kind as StringName:
		&"field": return CharacterEditLimits.field_value(character, operation.field)
		&"save": return character.save_value(int(operation.index))
		&"skill": return character.ability_value(int(operation.index))
		&"condition": return character.conditions.value(int(operation.index))
		&"name": return character.name
		&"gender": return character.gender
		&"portrait": return character.portrait_id
		&"icon": return character.combat_icon_id
		&"age": return floori(float(character.age_days) / 365.0)
		&"level_up": return {"level": character.level, "experience": character.experience}
		&"level_spells": return character.known_spells().size()
	return null


func effect(operation: Dictionary, before: Variant, after: Variant) -> Dictionary:
	match operation.kind as StringName:
		&"field": return _row(CharacterEditLimits.LABELS[operation.field], "%s → %s" % [CharacterEditLimits.group_digits(before), CharacterEditLimits.group_digits(after)])
		&"save": return _row("%s save" % CharacterView.SAVE_NAMES[operation.index], "%d → %d" % [before, after])
		&"skill": return _row(CharacterView.ABILITY_NAMES[operation.index], "%d → %d" % [before, after])
		&"condition": return _row(CharacterView.CONDITION_NAMES[operation.index], "%d → %d" % [before, after])
		&"name": return _row("Name", "%s → %s" % [before, after])
		&"gender": return _row("Gender", "%s → %s" % [_gender(before), _gender(after)])
		&"portrait": return _row("Portrait", "changed")
		&"icon": return _row("Combat icon", "changed")
		&"age": return _row("Age", "%d → %d years" % [before, after])
		&"level_up": return _row("Level", "%d → %d · XP reset" % [before.level, after.level])
		&"level_spells": return _row("Spells chosen", "%d known" % after)
		&"spell": return _row(_spell_name(String(operation.spell_id)), "learned" if operation.known else "forgotten")
		&"add_item": return _row(_item_name(operation), "added")
		&"remove_item": return _row(_item_name(operation), "removed")
		&"equip": return _row(_item_name(operation), "equipped" if operation.equipped else "unequipped")
		&"identify": return _row(_item_name(operation), "identified")
	return _row("Change", "")


static func _row(label: String, detail: String) -> Dictionary:
	return {"label": label, "detail": detail}


static func _gender(value: Variant) -> String:
	return "Male" if int(value) == 1 else "Female"


func _spell_name(spell_id: String) -> String:
	var spell := _context.spells.spell_by_id(spell_id) if _context.spells != null else null
	return spell.name if spell != null else "Spell"


## Identified names only, and a cursed item's decoy until it is worn, so the change
## list keeps the private facts play hides.
func _item_name(operation: Dictionary) -> String:
	var definition := _context.items.item_by_id(String(operation.get("definition_id", ""))) if _context.items != null else null
	if definition == null:
		return "Item"
	var worn: bool = operation.kind == &"equip" and bool(operation.get("equipped", false))
	if not worn and not definition.cursed_item_id.is_empty():
		definition = InventoryRules.presentation_definition(null, definition, _context.items)
	return definition.name if operation.kind in [&"add_item", &"identify"] or bool(operation.get("identified", true)) else definition.unidentified_name
