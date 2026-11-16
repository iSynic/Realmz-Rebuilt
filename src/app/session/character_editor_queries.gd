## Detached rows the Character Files editor binds: values, ranges, locks and reasons.

class_name CharacterEditorQueries
extends RefCounted

const _AGE_GROUPS: Array[String] = ["Young", "Adult", "Middle-aged", "Old", "Venerable"]

var _draft: CharacterEditDraft
var _content: RealmzContent


func _init(draft: CharacterEditDraft, content: RealmzContent) -> void:
	_draft = draft
	_content = content


func character_view() -> CharacterView:
	return CharacterView.new(_draft.state, _content)


## Why Items, Spells, age and Level Up are view-only, or "".
func rules_reason() -> String:
	return _draft.context.rules_unavailable_reason


## Value, legal range, base value and any Level Up lock for one numeric field.
func field(name: StringName) -> Dictionary:
	var state := _draft.state
	var magic := _draft.context.magical_strength(state)
	return {
		"value": CharacterEditLimits.field_value(state, name),
		"base": CharacterEditLimits.field_value(_draft.base, name),
		"range": CharacterEditLimits.field_range(name, state, magic),
		"lock": _draft.lock_reason(name),
		"magic": magic if name == &"brawn" else 0,
	}


## Value and base for one save (`kind` &"save") or skill (&"skill").
func indexed(kind: StringName, index: int) -> Dictionary:
	if kind == &"save":
		return {"value": _draft.state.save_value(index), "base": _draft.base.save_value(index), "range": CharacterEditLimits.SAVE_RANGE}
	return {"value": _draft.state.ability_value(index), "base": _draft.base.ability_value(index), "range": CharacterEditLimits.SKILL_RANGE}


## Name, level, experience still needed and appearance of the draft.
func identity() -> Dictionary:
	var state := _draft.state
	# Classic levels once experience rises above 0 (booty.c), so one more point is needed.
	var threshold := CharacterEditLimits.group_digits(1 - state.experience)
	return {"name": state.name, "baseName": _draft.base.name, "level": state.level, "gender": state.gender,
		"experienceText": "%s XP to level %d" % [threshold, state.level + 1] if state.experience <= 0 else "Ready to level",
		"portraitId": state.portrait_id, "iconId": state.combat_icon_id, "levelUp": _draft.has_level_up()}


func load_text() -> String:
	return "Load %s / %s" % [CharacterEditLimits.group_digits(_draft.state.carried_load), CharacterEditLimits.group_digits(_draft.state.maximum_load)]


## Age in years, the race's age table, the current age group and any lock.
func age() -> Dictionary:
	var limits := _draft.context.age_year_range()
	var group := clampi(_draft.state.age_group, 1, 5)
	var lock := _draft.lock_reason(&"age")
	if lock.is_empty() and _draft.context.race == null:
		lock = rules_reason()
	return {"years": floori(float(_draft.state.age_days) / 365.0), "baseYears": floori(float(_draft.base.age_days) / 365.0), "range": limits, "group": _AGE_GROUPS[group - 1],
		"race": _draft.context.race.name if _draft.context.race != null else "", "lock": lock}


## What setting the age to `years` would change: title, stat rows and any blocking reason.
func age_preview(years: int) -> Dictionary:
	var preview := CharacterStateCodec.copy(_draft.state)
	var error := CharacterEditOperations.new(_draft.context).apply(preview, {"kind": &"age", "value": years})
	var rows: Array[Dictionary] = []
	for field_name: StringName in CharacterEditLimits.ATTRIBUTES:
		_append_change(rows, CharacterEditLimits.LABELS[field_name], CharacterEditLimits.field_value(_draft.state, field_name), CharacterEditLimits.field_value(preview, field_name))
	_append_change(rows, "Movement", _draft.state.maximum_movement, preview.maximum_movement)
	_append_change(rows, "Magic resistance", _draft.state.magic_resistance, preview.magic_resistance)
	for index: int in 7:
		_append_change(rows, "%s save" % CharacterView.SAVE_NAMES[index], _draft.state.save_value(index), preview.save_value(index))
	_append_change(rows, "To-hit", _draft.state.to_hit, preview.to_hit)
	_append_change(rows, "Max load", _draft.state.maximum_load, preview.maximum_load)
	var group := clampi(preview.age_group, 1, 5)
	return {"crosses": preview.age_group != _draft.state.age_group, "group": _AGE_GROUPS[group - 1], "fromGroup": age().group, "rows": rows, "error": error}


static func _append_change(rows: Array[Dictionary], label: String, before: int, after: int) -> void:
	if before != after:
		rows.append({"label": label, "before": before, "after": after})


func items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rules := CharacterEditItems.new(_draft.context)
	for instance: ItemInstance in _draft.state.inventory():
		var definition := _content.items.item_by_id(instance.definition_id) if _content != null else null
		var known := definition != null
		# As in play, an unequipped cursed item shows its decoy; the curse shows once worn.
		var shown := InventoryRules.presentation_definition(instance, definition, _content.items) if known else null
		var cursed := known and instance.equipped and instance.identified and not definition.cursed_item_id.is_empty()
		var reason := rules.equip_reason(_draft.state, instance) if _draft.context.rules_available() else rules_reason()
		result.append({"instanceId": instance.id, "definitionId": instance.definition_id, "equipped": instance.equipped, "identified": instance.identified, "cursed": cursed,
			"name": (shown.name if instance.identified else shown.unidentified_name) if known else "Scenario item %s" % instance.definition_id.get_slice(".", instance.definition_id.get_slice_count(".") - 1),
			"weight": definition.instance_weight(instance.charges) if known else 0, "charges": instance.charges,
			"equipReason": reason, "editable": known and _draft.context.rules_available()})
	return result


## Library items matching `filter`, each with the reason it can't be added now. One row
## past `limit` is returned so the list can say that more matches exist.
func catalog(filter: String, limit: int = 80) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _content == null:
		return result
	var rules := CharacterEditItems.new(_draft.context)
	var needle := filter.strip_edges().to_lower()
	for definition: ItemDefinition in _content.items.definitions():
		# A cursed item is listed under its decoy, as play shows it, keeping the curse private.
		var shown := InventoryRules.presentation_definition(null, definition, _content.items)
		if shown.name.is_empty() or (not needle.is_empty() and not shown.name.to_lower().contains(needle)):
			continue
		result.append({"definitionId": definition.id, "name": shown.name, "weight": definition.instance_weight(definition.initial_charges), "reason": rules.add_reason(_draft.state, definition)})
		if result.size() > limit:
			break
	return result


## Spells the character can know at `level` (1–7), marking which are known.
func spells(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known := _draft.state.known_spells()
	for spell: SpellDefinition in _listed_spells():
		if spell.classic_tier() + 1 == level:
			result.append({"id": spell.id, "name": spell.name, "known": known.has(spell.id), "cost": _draft.context.rules.characters.spell_selection_cost(spell), "description": spell.description, "view": SpellView.new(spell)})
	return result


## Spell levels this caster can reach, and the Classic level-up point budget.
func spell_summary() -> Dictionary:
	var levels: Array[int] = []
	var spent := 0
	var known := _draft.state.known_spells()
	for spell: SpellDefinition in _listed_spells():
		if not levels.has(spell.classic_tier() + 1):
			levels.append(spell.classic_tier() + 1)
		if known.has(spell.id):
			spent += _draft.context.rules.characters.spell_selection_cost(spell)
	var total := _draft.context.rules.characters.spell_selection_total(_draft.state, _draft.context.caste) if _draft.context.rules_available() else 0
	return {"levels": levels, "total": total, "spent": spent, "caster": _draft.state.spellcaster_type > 0, "known": known.size()}


## Learnable spells, or only the known ones when the character's rules are view-only.
func _listed_spells() -> Array[SpellDefinition]:
	if _draft.context.rules_available() or _draft.context.spells == null:
		return _draft.context.spell_candidates(_draft.state)
	var result: Array[SpellDefinition] = []
	for spell_id: String in _draft.state.known_spells():
		var spell := _draft.context.spells.spell_by_id(spell_id)
		if spell != null:
			result.append(spell)
	return result


func conditions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in ConditionSet.CHARACTER_COUNT:
		var value := _draft.state.conditions.value(index)
		result.append({"index": index, "name": CharacterView.CONDITION_NAMES[index], "value": value, "base": _draft.base.conditions.value(index), "locked": value < 0})
	return result


func level_result() -> Dictionary:
	return _draft.last_level_result()


func appearance_options(portrait: bool) -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	if _content == null:
		return result
	for definition: CharacterAppearanceDefinition in _content.characters.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT if portrait else CharacterAppearanceDefinition.COMBAT_ICON):
		result.append(CharacterAppearanceOptionView.new(definition))
	return result
