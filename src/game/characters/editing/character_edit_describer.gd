## Names Character Files editor operations for the Changes list.

class_name CharacterEditDescriber
extends RefCounted

var _context: CharacterEditContext


func _init(context: CharacterEditContext) -> void:
	_context = context


## The comparable value an operation changes, read before and after it applies.
func value(character: CharacterState, operation: Dictionary) -> Variant:
	var kind: StringName = operation.kind
	match kind:
		&"field": return CharacterEditLimits.field_value(character, _name(operation, &"field"))
		&"save": return character.save_value(_number(operation, &"index"))
		&"skill": return character.ability_value(_number(operation, &"index"))
		&"condition": return character.conditions.value(_number(operation, &"index"))
		&"name": return character.name
		&"gender": return character.gender
		&"portrait": return character.portrait_id
		&"icon": return character.combat_icon_id
		&"age": return floori(float(character.age_days) / 365.0)
		&"level_up": return {"level": character.level, "experience": character.experience}
		&"level_spells": return character.known_spells().size()
	return null


func effect(operation: Dictionary, before: Variant, after: Variant) -> Dictionary:
	var kind: StringName = operation.kind
	match kind:
		&"field": return _row(_text(CharacterEditLimits.LABELS, operation.field), "%s → %s" % [_grouped(before), _grouped(after)])
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
		&"spell": return _row(_spell_name(_text(operation, &"spell_id")), "learned" if operation.known else "forgotten")
		&"add_item": return _row(_item_name(operation), "added")
		&"remove_item": return _row(_item_name(operation), "removed")
		&"equip": return _row(_item_name(operation), "equipped" if operation.equipped else "unequipped")
		&"identify": return _row(_item_name(operation), "identified")
	return _row("Change", "")


static func _row(label: String, detail: String) -> Dictionary:
	return {"label": label, "detail": detail}


static func _gender(value: Variant) -> String:
	var gender: int = value
	return "Male" if gender == 1 else "Female"


static func _grouped(value: Variant) -> String:
	var amount: int = value
	return CharacterEditLimits.group_digits(amount)


static func _number(source: Dictionary, key: Variant) -> int:
	var value: int = source[key]
	return value


static func _text(source: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: String = source.get(key, fallback)
	return value


static func _name(source: Dictionary, key: Variant) -> StringName:
	var value: StringName = source[key]
	return value


static func _flag(source: Dictionary, key: Variant, fallback: bool) -> bool:
	var value: bool = source.get(key, fallback)
	return value


func _spell_name(spell_id: String) -> String:
	var spell := _context.spells.spell_by_id(spell_id) if _context.spells != null else null
	return spell.name if spell != null else "Spell"


## Identified names only, and a cursed item's decoy until it is worn, so the change
## list keeps the private facts play hides.
func _item_name(operation: Dictionary) -> String:
	var definition := _context.items.item_by_id(_text(operation, "definition_id")) if _context.items != null else null
	if definition == null:
		return "Item"
	var worn: bool = operation.kind == &"equip" and _flag(operation, "equipped", false)
	if not worn and not definition.cursed_item_id.is_empty():
		definition = InventoryRules.presentation_definition(null, definition, _context.items)
	return definition.name if operation.kind in [&"add_item", &"identify"] or _flag(operation, "identified", true) else definition.unidentified_name
