## Decodes detached combat targets, actors, movement, Fast Spells, and cast choices.

class_name InteractionCombatValueDecoder
extends RefCounted


static func combat_target(data: Variant) -> InteractionRequestValue.CombatTarget:
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, ["id", "kind", "name", "currentHealth", "maximumHealth", "hitDice", "magicResistance"], ["id", "name"]):
		return null
	if not InteractionValueDecoderSupport.strings(data, ["id", "name"]) or not InteractionValueDecoderSupport.optional_string(data, "kind") or not InteractionValueDecoderSupport.optional_int(data, "currentHealth") or not InteractionValueDecoderSupport.optional_int(data, "maximumHealth") or not InteractionValueDecoderSupport.optional_int(data, "hitDice") or not InteractionValueDecoderSupport.optional_int(data, "magicResistance"):
		return null
	var result := InteractionRequestValue.CombatTarget.new()
	result.id = data["id"]
	result.kind = StringName(data.get("kind", ""))
	result.name = data["name"]
	result.current_health = int(data.get("currentHealth", 0))
	result.maximum_health = int(data.get("maximumHealth", 0))
	result.hit_dice = int(data.get("hitDice", 0))
	result.magic_resistance = int(data.get("magicResistance", 0))
	result.has_hit_dice = data.has("hitDice")
	return result


static func combatant(data: Variant) -> InteractionRequestValue.Combatant:
	var allowed := ["id", "kind", "name", "currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "hitDice", "attacks", "movement", "maximumMovement", "traitor", "helpless", "conditions", "items", "attackRows", "immunities", "vulnerabilities", "weapon", "weaponCharges", "range", "blocked"]
	var required := ["id", "kind", "name", "currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "attacks", "movement", "maximumMovement", "traitor", "helpless", "conditions"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, allowed, required) or not InteractionValueDecoderSupport.strings(data, ["id", "kind", "name"]) or not InteractionValueDecoderSupport.ints(data, ["currentHealth", "maximumHealth", "spellPoints", "maximumSpellPoints", "armor", "magicResistance", "movement", "maximumMovement"]) or not data["attacks"] is String or not InteractionValueDecoderSupport.bools(data, ["traitor", "helpless"]) or not InteractionValueDecoderSupport.string_array(data["conditions"]):
		return null
	if not InteractionValueDecoderSupport.optional_int(data, "hitDice") or not InteractionValueDecoderSupport.optional_string(data, "weapon") or not InteractionValueDecoderSupport.optional_int(data, "weaponCharges") or not InteractionValueDecoderSupport.optional_int(data, "range") or data.has("blocked") and not data["blocked"] is bool or data.has("items") and not InteractionValueDecoderSupport.string_array(data["items"]) or data.has("attackRows") and not InteractionValueDecoderSupport.string_array(data["attackRows"]) or data.has("immunities") and not InteractionValueDecoderSupport.string_array(data["immunities"]) or data.has("vulnerabilities") and not InteractionValueDecoderSupport.string_array(data["vulnerabilities"]):
		return null
	var result := InteractionRequestValue.Combatant.new()
	result.id = data["id"]
	result.kind = StringName(data["kind"])
	result.name = data["name"]
	result.current_health = int(data["currentHealth"])
	result.maximum_health = int(data["maximumHealth"])
	result.spell_points = int(data["spellPoints"])
	result.maximum_spell_points = int(data["maximumSpellPoints"])
	result.armor = int(data["armor"])
	result.magic_resistance = int(data["magicResistance"])
	result.attacks = data["attacks"]
	result.movement = int(data["movement"])
	result.maximum_movement = int(data["maximumMovement"])
	result.traitor = data["traitor"]
	result.helpless = data["helpless"]
	result.conditions = InteractionValueDecoderSupport.string_values(data["conditions"])
	result.items = InteractionValueDecoderSupport.string_values(data.get("items", []))
	result.attack_rows = InteractionValueDecoderSupport.string_values(data.get("attackRows", []))
	result.immunities = InteractionValueDecoderSupport.string_values(data.get("immunities", []))
	result.vulnerabilities = InteractionValueDecoderSupport.string_values(data.get("vulnerabilities", []))
	result.hit_dice = int(data.get("hitDice", 0))
	result.has_hit_dice = data.has("hitDice")
	result.weapon = String(data.get("weapon", ""))
	result.weapon_charges = int(data.get("weaponCharges", -1))
	result.has_weapon_charges = data.has("weaponCharges")
	result.range = int(data.get("range", -1))
	result.blocked = bool(data.get("blocked", false))
	result.has_position_facts = data.has("range")
	return result


static func movement_option(data: Variant) -> InteractionRequestValue.MovementOption:
	var fields := ["direction", "destination", "cost", "enabled", "reasonCode", "reason", "retreat", "forcedRetreat", "attackTargetId", "attackTargetName"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.coordinate(data["direction"]) or not InteractionValueDecoderSupport.coordinate(data["destination"]) or not InteractionValueDecoderSupport.ints(data, ["cost"]) or not InteractionValueDecoderSupport.bools(data, ["enabled", "retreat", "forcedRetreat"]) or not InteractionValueDecoderSupport.strings(data, ["reasonCode", "reason", "attackTargetId", "attackTargetName"]):
		return null
	var result := InteractionRequestValue.MovementOption.new()
	result.direction = InteractionValueDecoderSupport.vector(data["direction"])
	result.destination = InteractionValueDecoderSupport.vector(data["destination"])
	result.cost = int(data["cost"])
	result.enabled = data["enabled"]
	result.reason_code = StringName(data["reasonCode"])
	result.reason = data["reason"]
	result.retreat = data["retreat"]
	result.forced_retreat = data["forcedRetreat"]
	result.attack_target_id = data["attackTargetId"]
	result.attack_target_name = data["attackTargetName"]
	return result


static func fast_spell(data: Variant) -> InteractionRequestValue.FastSpell:
	var fields := ["slot", "spellId", "spellName", "power", "enabled", "reason"]
	if not data is Dictionary or not InteractionValueDecoderSupport.exact(data, fields, fields) or not InteractionValueDecoderSupport.ints(data, ["slot", "power"]) or not InteractionValueDecoderSupport.strings(data, ["spellId", "spellName", "reason"]) or not data["enabled"] is bool:
		return null
	var result := InteractionRequestValue.FastSpell.new()
	result.slot = int(data["slot"])
	result.spell_id = data["spellId"]
	result.spell_name = data["spellName"]
	result.power = int(data["power"])
	result.enabled = data["enabled"]
	result.reason = data["reason"]
	return result


static func cast_option(data: Variant, source_kind: StringName) -> InteractionRequestValue.CastOption:
	if not data is Dictionary:
		return null
	var common := ["spellId", "spellName", "power", "targetId", "targetName", "targetCurrentHealth", "targetMaximumHealth", "targetMode", "maximumTargets", "targetCandidates", "areaShape", "defaultTargetCoordinate", "areaOffsets", "areaRotationOffsets", "legalTargetCoordinates"]
	var allowed := common.duplicate()
	if source_kind == &"spell":
		allowed.append("cost")
	if source_kind == &"item":
		allowed.append_array(["itemInstanceId", "itemId", "itemName", "charges", "powerStaged"])
	if source_kind == &"scroll":
		allowed.append("scrollSlot")
	if not InteractionValueDecoderSupport.exact(data, allowed, ["spellId", "spellName", "power", "targetId", "targetName", "targetCurrentHealth", "targetMaximumHealth", "targetMode"]):
		return null
	if not InteractionValueDecoderSupport.strings(data, ["spellId", "spellName", "targetId", "targetName", "targetMode"]) or not InteractionValueDecoderSupport.ints(data, ["power", "targetCurrentHealth", "targetMaximumHealth"]):
		return null
	var result := InteractionRequestValue.CastOption.new()
	_populate_cast_identity(data, source_kind, result)
	if not _populate_cast_source(data, source_kind, result) or not _populate_cast_target(data, result):
		return null
	return result


static func _populate_cast_identity(data: Dictionary, source_kind: StringName, result: InteractionRequestValue.CastOption) -> void:
	result.source_kind = source_kind
	result.spell_id = data["spellId"]
	result.spell_name = data["spellName"]
	result.power = int(data["power"])
	result.target_id = data["targetId"]
	result.target_name = data["targetName"]
	result.target_current_health = int(data["targetCurrentHealth"])
	result.target_maximum_health = int(data["targetMaximumHealth"])
	result.target_mode = StringName(data["targetMode"])


static func _populate_cast_source(data: Dictionary, source_kind: StringName, result: InteractionRequestValue.CastOption) -> bool:
	if source_kind == &"spell":
		if not InteractionValueDecoderSupport.whole(data.get("cost")):
			return false
		result.cost = int(data["cost"])
	elif source_kind == &"item":
		if not InteractionValueDecoderSupport.strings(data, ["itemInstanceId", "itemId", "itemName"]) or not InteractionValueDecoderSupport.ints(data, ["charges"]) or not data.get("powerStaged", false) is bool:
			return false
		result.item_instance_id = data["itemInstanceId"]
		result.item_id = data["itemId"]
		result.item_name = data["itemName"]
		result.charges = int(data["charges"])
		result.power_staged = bool(data.get("powerStaged", false))
	elif source_kind == &"scroll":
		if not InteractionValueDecoderSupport.whole(data.get("scrollSlot")):
			return false
		result.scroll_slot = int(data["scrollSlot"])
	return true


static func _populate_cast_target(data: Dictionary, result: InteractionRequestValue.CastOption) -> bool:
	if result.target_mode in [&"sequence", &"coordinate_sequence"]:
		if not InteractionValueDecoderSupport.whole(data.get("maximumTargets")):
			return false
		result.maximum_targets = int(data["maximumTargets"])
	if result.target_mode == &"sequence":
		return _populate_cast_sequence(data, result)
	if result.target_mode == &"area":
		return _populate_cast_area(data, result)
	return true


static func _populate_cast_sequence(data: Dictionary, result: InteractionRequestValue.CastOption) -> bool:
	if not data.get("targetCandidates") is Array:
		return false
	for candidate: Variant in data["targetCandidates"]:
		var parsed := combat_target(candidate)
		if parsed == null:
			return false
		result.target_candidates.append(parsed)
	return true


static func _populate_cast_area(data: Dictionary, result: InteractionRequestValue.CastOption) -> bool:
	if not InteractionValueDecoderSupport.whole(data.get("areaShape")) or not InteractionValueDecoderSupport.coordinate(data.get("defaultTargetCoordinate")) or not data.get("areaOffsets") is Array or not data.get("legalTargetCoordinates") is Array:
		return false
	result.area_shape = int(data["areaShape"])
	result.default_target_coordinate = InteractionValueDecoderSupport.vector(data["defaultTargetCoordinate"])
	for coordinate: Variant in data["areaOffsets"]:
		if not InteractionValueDecoderSupport.coordinate(coordinate):
			return false
		result.area_offsets.append(InteractionValueDecoderSupport.vector(coordinate))
	if not _populate_cast_rotations(data, result):
		return false
	for coordinate: Variant in data["legalTargetCoordinates"]:
		if not InteractionValueDecoderSupport.coordinate(coordinate):
			return false
		result.legal_target_coordinates.append(InteractionValueDecoderSupport.vector(coordinate))
	return true


static func _populate_cast_rotations(data: Dictionary, result: InteractionRequestValue.CastOption) -> bool:
	if not data.has("areaRotationOffsets"):
		return true
	if not data["areaRotationOffsets"] is Array:
		return false
	for rotation_offsets: Variant in data["areaRotationOffsets"]:
		if not rotation_offsets is Array:
			return false
		var parsed_offsets: Array[Vector2i] = []
		for coordinate: Variant in rotation_offsets:
			if not InteractionValueDecoderSupport.coordinate(coordinate):
				return false
			parsed_offsets.append(InteractionValueDecoderSupport.vector(coordinate))
		result.area_rotation_offsets.append(parsed_offsets)
	return true
