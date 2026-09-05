## Decodes choice, selection, encounter, thief, targeting, and lifecycle request values.

class_name InteractionSelectionValueDecoder
extends RefCounted


static func encounter_action(data: Variant) -> InteractionRequestValue.EncounterAction:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["id", "kind", "label", "slot", "actionIndex"], ["id", "kind", "label"]) or not InteractionValueDecoderSupport.strings(data, ["id", "kind", "label"]) or not InteractionValueDecoderSupport.optional_int(data, "slot") or not InteractionValueDecoderSupport.optional_int(data, "actionIndex"):
		return null
	var result := InteractionRequestValue.EncounterAction.new()
	result.id = data["id"]
	result.kind = StringName(data["kind"])
	result.label = data["label"]
	result.slot = int(data.get("slot", -1))
	result.action_index = int(data.get("actionIndex", -1))
	if result.kind not in [&"choice", &"word", &"spell", &"item", &"thief", &"back"]:
		return null
	if result.kind == &"choice" and result.slot < 0:
		return null
	return result


static func named_character(data: Variant) -> InteractionRequestValue.NamedCharacter:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["id", "name", "portraitId"], ["id", "name", "portraitId"]) or not InteractionValueDecoderSupport.strings(data, ["id", "name", "portraitId"]):
		return null
	var result := InteractionRequestValue.NamedCharacter.new()
	result.id = data["id"]
	result.name = data["name"]
	result.portrait_id = data["portraitId"]
	return result


static func thief_action(data: Variant) -> InteractionRequestValue.ThiefAction:
	var fields := ["index", "label", "value", "enabled", "reason"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.ints(data, ["index", "value"]) or not InteractionValueDecoderSupport.strings(data, ["label", "reason"]) or not data["enabled"] is bool:
		return null
	var result := InteractionRequestValue.ThiefAction.new()
	result.index = int(data["index"])
	result.label = data["label"]
	result.value = int(data["value"])
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	return result if result.index >= 0 and result.index < 8 else null


static func thief_character(data: Variant) -> InteractionRequestValue.ThiefCharacter:
	var fields := ["id", "name", "portraitId", "actions"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["id", "name", "portraitId"]) or not data["actions"] is Array:
		return null
	var result := InteractionRequestValue.ThiefCharacter.new()
	result.id = data["id"]
	result.name = data["name"]
	result.portrait_id = data["portraitId"]
	for entry: Variant in data["actions"]:
		var action := thief_action(entry)
		if action == null:
			return null
		result.actions.append(action)
	return result if not result.id.is_empty() else null


static func encounter_catalog_entry(data: Variant, kind: StringName) -> InteractionRequestValue.EncounterCatalogEntry:
	var id_field := "classicItemId" if kind == &"item" else "classicSpellId"
	var fields := [id_field, "name", "characterId"] if kind == &"spell" else [id_field, "name", "characterId", "instanceId", "iconResourceType", "iconId", "charges", "equipped"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.whole(data[id_field]) or not InteractionValueDecoderSupport.strings(data, ["name", "characterId"]):
		return null
	if kind == &"item" and (not InteractionValueDecoderSupport.strings(data, ["instanceId", "iconResourceType"]) or not InteractionValueDecoderSupport.ints(data, ["iconId", "charges"]) or not data["equipped"] is bool):
		return null
	var result := InteractionRequestValue.EncounterCatalogEntry.new()
	result.classic_id = int(data[id_field])
	result.name = data["name"]
	result.kind = kind
	result.character_id = data["characterId"]
	if kind == &"item":
		result.instance_id = data["instanceId"]
		result.icon_resource_type = data["iconResourceType"]
		result.icon_id = int(data["iconId"])
		result.charges = int(data["charges"])
		result.equipped = data["equipped"]
	return result if not result.character_id.is_empty() and (kind != &"item" or not result.instance_id.is_empty()) else null


static func choice_option(data: Variant) -> InteractionRequestValue.ChoiceOption:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["id", "label"], ["label"]) or not data["label"] is String or not InteractionValueDecoderSupport.optional_string(data, "id"):
		return null
	var result := InteractionRequestValue.ChoiceOption.new()
	result.id = String(data.get("id", ""))
	result.label = data["label"]
	result.has_id = data.has("id")
	return result


static func selection_candidate(data: Variant) -> InteractionRequestValue.SelectionCandidate:
	var allowed := ["id", "name", "currentHealth", "maximumHealth", "classicMonsterId", "required", "canSummon"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, allowed, ["id", "name"]) or not InteractionValueDecoderSupport.strings(data, ["id", "name"]) or not InteractionValueDecoderSupport.optional_int(data, "currentHealth") or not InteractionValueDecoderSupport.optional_int(data, "maximumHealth") or not InteractionValueDecoderSupport.optional_int(data, "classicMonsterId") or not InteractionValueDecoderSupport.optional_int(data, "canSummon") or data.has("required") and not data["required"] is bool:
		return null
	var result := InteractionRequestValue.SelectionCandidate.new()
	result.id = data["id"]
	result.name = data["name"]
	result.current_health = int(data.get("currentHealth", 0))
	result.maximum_health = int(data.get("maximumHealth", 0))
	result.has_current_health = data.has("currentHealth")
	result.has_maximum_health = data.has("maximumHealth")
	var ally_fields: bool = data.has("classicMonsterId") or data.has("required") or data.has("canSummon")
	if ally_fields and not (data.has("classicMonsterId") and data.has("required") and data.has("canSummon")):
		return null
	result.has_ally_facts = ally_fields
	result.classic_monster_id = int(data.get("classicMonsterId", 0))
	result.required = bool(data.get("required", false))
	result.can_summon = int(data.get("canSummon", 0))
	return result


static func spell_target_context(data: Variant) -> InteractionRequestValue.SpellTargetContext:
	var fields := ["actorId", "actorName", "spellId", "spellName", "description", "iconResourceType", "iconId", "power", "spellPointCost", "targetType", "targetSize", "targetCount", "sourceKind"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.strings(data, ["actorId", "actorName", "spellId", "spellName", "description", "iconResourceType", "sourceKind"]) or not InteractionValueDecoderSupport.ints(data, ["iconId", "power", "spellPointCost", "targetType", "targetSize", "targetCount"]):
		return null
	var result := InteractionRequestValue.SpellTargetContext.new()
	result.actor_id = data["actorId"]
	result.actor_name = data["actorName"]
	result.spell_id = data["spellId"]
	result.spell_name = data["spellName"]
	result.description = data["description"]
	result.icon_resource_type = data["iconResourceType"]
	result.icon_id = int(data["iconId"])
	result.power = int(data["power"])
	result.spell_point_cost = int(data["spellPointCost"])
	result.target_type = int(data["targetType"])
	result.target_size = int(data["targetSize"])
	result.target_count = int(data["targetCount"])
	result.source_kind = StringName(data["sourceKind"])
	if result.actor_id.is_empty() or result.spell_id.is_empty() or result.spell_name.is_empty() or result.power < 1 or result.power > 7 or result.spell_point_cost < 0 or result.target_count < 1 or result.source_kind not in [&"field-spell", &"scroll-use", &"item-use"]:
		return null
	return result


static func lifecycle_option(data: Variant) -> InteractionRequestValue.LifecycleOption:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["action", "label"], ["action", "label"]) or not InteractionValueDecoderSupport.strings(data, ["action", "label"]):
		return null
	var result := InteractionRequestValue.LifecycleOption.new()
	result.action = StringName(data["action"])
	result.label = data["label"]
	return result
