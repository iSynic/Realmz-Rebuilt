## Maps Castle's grouped roster conditions to exact application icon resources.
class_name RosterConditionIcons
extends RefCounted


static func icon_ids(character: CharacterView) -> Array[int]:
	var values := character.condition_values
	var result: Array[int] = []
	if _has_any_condition(values, [ConditionRules.RUNS_AWAY, ConditionRules.TANGLED, ConditionRules.SLOW]):
		result.append(180)
	if _has_any_condition(values, [ConditionRules.HELPLESS, ConditionRules.TURNED_TO_STONE, ConditionRules.BLIND]):
		result.append(183)
	if _has_any_condition(values, [ConditionRules.POISONED, ConditionRules.DISEASED, ConditionRules.TANGLED]):
		result.append(181)
	if character.traitor or values.size() > ConditionRules.ANIMATED and values[ConditionRules.ANIMATED] < 0:
		result.append(182)
	if _has_any_condition(values, [ConditionRules.HINDERED_ATTACKS, ConditionRules.HINDERED_DEFENSE, ConditionRules.CURSED]):
		result.append(185)
	if _has_any_condition(values, [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED]):
		result.append(184)
	return result


static func icon_texture(media: ClassicMediaCatalog, cache: Dictionary, resource_id: int) -> Texture2D:
	if media == null:
		return null
	if cache.has(resource_id):
		return cache[resource_id] as Texture2D
	var asset := media.asset_by_resource("cicn", resource_id)
	var texture := media.image_texture(asset) if asset != null and asset.is_picture() else null
	cache[resource_id] = texture
	return texture


static func icon_label(resource_id: int) -> String:
	match resource_id:
		180: return "Movement affected"
		181: return "Poisoned, diseased, or tangled"
		182: return "Charmed or hostile"
		183: return "Physical action affected"
		184: return "Magic affected"
		185: return "Attack or defense affected"
	return "Condition"


static func _has_any_condition(values: Array[int], indices: Array[int]) -> bool:
	for index: int in indices:
		if index < values.size() and values[index] != 0:
			return true
	return false
