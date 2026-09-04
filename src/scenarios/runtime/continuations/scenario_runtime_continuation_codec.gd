## Decodes every scenario runtime continuation from its strict saved envelope.

class_name ScenarioRuntimeContinuationCodec
extends RefCounted


static func decode(value: Variant) -> ScenarioRuntimeContinuation:
	if not value is Dictionary or value.size() != 3 or not value.get("kind") is String or value.get("version") != ScenarioRuntimeContinuation.VERSION or not value.get("data") is Dictionary:
		return null
	return _decode_payload(StringName(value["kind"]), value["data"])


static func _decode_payload(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	match kind:
		ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE:
			return ScenarioInteractionContinuations.acknowledge() if data.is_empty() else null
		ScenarioRuntimeContinuation.CLASSIC_BANKING:
			return ScenarioServiceContinuations.banking() if data.is_empty() else null
		ScenarioRuntimeContinuation.CLASSIC_TEXTBOX:
			var message_id := _integer(data.get("messageId"))
			return ScenarioInteractionContinuations.textbox(message_id) if data.size() == 1 and message_id > 0 else null
		ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP:
			return ScenarioInteractionContinuations.player_map(data["playerMapId"]) if data.size() == 1 and data.get("playerMapId") is String and not data["playerMapId"].is_empty() else null
		ScenarioRuntimeContinuation.SAFE_CHOICE:
			var option_count := _integer(data.get("optionCount"))
			return ScenarioInteractionContinuations.safe_choice(option_count) if data.size() == 1 and option_count >= 1 and option_count <= 256 else null
		ScenarioRuntimeContinuation.CLASSIC_CHOICE:
			var values := _integers(data.get("values"))
			return ScenarioInteractionContinuations.classic_choice(values, data["gosub"]) if data.size() == 2 and values.size() == 5 and data.get("gosub") is bool else null
		ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER:
			return _decode_encounter(kind, data)
		ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER, ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK, ScenarioRuntimeContinuation.CLASSIC_THIEF_RESOLUTION:
			return _decode_thief(kind, data)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_SELECTION:
			return _decode_character_selection(data)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_ABILITY:
			var ability_values := _integers(data.get("values"))
			return ScenarioInteractionContinuations.character_ability(ability_values, data["gosub"]) if data.size() == 2 and ability_values.size() == 5 and data.get("gosub") is bool else null
		ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES, ScenarioRuntimeContinuation.SAFE_AGE_UPDATES:
			return _decode_age(kind, data)
		ScenarioRuntimeContinuation.CLASSIC_SHOP:
			return _decode_shop(data)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE, ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT:
			return _decode_temple(kind, data)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE, ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE:
			return _decode_combat(kind, data)
		ScenarioRuntimeContinuation.CLASSIC_OPCODE_DEATH_MACRO:
			return _decode_opcode_death_macro(data)
		ScenarioRuntimeContinuation.CLASSIC_REWARD:
			var reward_state := ClassicRewardState.from_data(data.get("state"))
			return ScenarioRewardContinuations.reward(reward_state) if data.size() == 1 and reward_state != null else null
	return null


static func _decode_character_selection(data: Dictionary) -> ScenarioRuntimeContinuation:
	var count := _integer(data.get("count"))
	if data.size() != 3 or count < 1 or count > 6 or not data.get("allowDead") is bool or not data.get("invert") is bool:
		return null
	return ScenarioInteractionContinuations.character_selection(count, data["allowDead"], data["invert"])


static func _decode_shop(data: Dictionary) -> ScenarioRuntimeContinuation:
	var ranges := _integers(data.get("acceptRanges"))
	if data.size() != 2 or not data.get("shopId") is String or data["shopId"].is_empty() or ranges.size() not in [0, 4] or ranges.size() != data["acceptRanges"].size():
		return null
	return ScenarioServiceContinuations.shop(data["shopId"], ranges)


static func _decode_temple(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var cost_percent := _integer(data.get("costPercent"))
	if data.size() != 3 or cost_percent < -32768 or cost_percent > 32767 or not data.get("bankAvailable") is bool or not data.get("selectedCharacterId") is String or data["selectedCharacterId"].is_empty():
		return null
	return ScenarioServiceContinuations.temple(kind, cost_percent, data["bankAvailable"], data["selectedCharacterId"])


static func _decode_encounter(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var encounter_id := _integer(data.get("encounterId"))
	var encounter_attempt := _integer(data.get("encounterAttempt", 0))
	# Classic encounter tables are zero-based; encounter 0 is authored content.
	if encounter_id < 0 or encounter_attempt < 0 or not data.get("gosub") is bool:
		return null
	if kind == ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER:
		return ScenarioInteractionContinuations.encounter(kind, encounter_id, data["gosub"], [], encounter_attempt) if data.size() == (3 if data.has("encounterAttempt") else 2) else null
	var indexes := _integers(data.get("optionIndexes"))
	if data.size() != (4 if data.has("encounterAttempt") else 3) or indexes.is_empty() or indexes.size() > 10:
		return null
	for index: int in indexes:
		if index < 0:
			return null
	return ScenarioInteractionContinuations.encounter(kind, encounter_id, data["gosub"], indexes, encounter_attempt)


static func _decode_thief(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var encounter_id := _integer(data.get("encounterId"))
	var encounter_attempt := _integer(data.get("encounterAttempt", 0))
	var attempt_field_count := 1 if data.has("encounterAttempt") else 0
	if encounter_id < 0 or encounter_attempt < 0 or not data.get("gosub") is bool:
		return null
	if kind == ScenarioRuntimeContinuation.CLASSIC_THIEF_ENCOUNTER:
		return ScenarioInteractionContinuations.thief_encounter(encounter_id, data["gosub"], encounter_attempt) if data.size() == 2 + attempt_field_count else null
	var action_index := _integer(data.get("actionIndex"))
	if action_index < 0 or action_index > 7 or not data.get("characterId") is String or data["characterId"].is_empty():
		return null
	if kind == ScenarioRuntimeContinuation.CLASSIC_PICK_LOCK:
		return ScenarioInteractionContinuations.pick_lock(encounter_id, data["gosub"], action_index, data["characterId"], encounter_attempt) if data.size() == 4 + attempt_field_count and action_index in [2, 4, 6, 7] else null
	var phase := StringName(data.get("phase", ""))
	if data.size() != 7 + attempt_field_count or phase not in [&"action-message", &"trap-message"] or not data.get("succeeded") is bool or not data.get("trapPending") is bool:
		return null
	return ScenarioInteractionContinuations.thief_resolution(encounter_id, data["gosub"], action_index, data["characterId"], phase, data["succeeded"], data["trapPending"], encounter_attempt)


static func _decode_age(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	if data.size() != 4 or not data.has_all(["updates", "index", "value", "directive"]) or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30 or not data.get("directive") is Dictionary:
		return null
	var index := _integer(data.get("index"))
	if index < 1 or index > data["updates"].size() or not _json_safe(data.get("value"), 0):
		return null
	var updates: Array[AgeUpdateRequestBody] = []
	for update: Variant in data["updates"]:
		var typed_update := ScenarioAgeContinuations.update_from_data(update)
		if typed_update == null:
			return null
		updates.append(typed_update)
	var directive_data: Dictionary = data["directive"]
	var directive := ScenarioVmDirective.from_data(directive_data) if not directive_data.is_empty() else null
	if not directive_data.is_empty() and directive == null:
		return null
	return ScenarioAgeContinuations.updates(kind, updates, index, data["value"], directive)


static func _decode_combat(kind: StringName, data: Dictionary) -> ScenarioRuntimeContinuation:
	var expected_source := ScenarioRuntimeContinuation.SAFE_COMBAT if kind in _safe_combat_kinds() else ScenarioRuntimeContinuation.CLASSIC_COMBAT
	if not data.get("sourceKind") is String or StringName(data["sourceKind"]) != expected_source or not data.get("battleId") is String or data["battleId"].is_empty():
		return null
	var caller := ScenarioBattleCaller.from_data(data.get("battleCaller"))
	if caller == null or expected_source == ScenarioRuntimeContinuation.SAFE_COMBAT and caller.kind != ScenarioBattleCaller.SAFE or expected_source == ScenarioRuntimeContinuation.CLASSIC_COMBAT and caller.kind != ScenarioBattleCaller.CLASSIC:
		return null
	if kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT]:
		return ScenarioCombatContinuations.battle(kind, data["battleId"], caller) if data.size() == 3 else null
	if kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE]:
		return ScenarioCombatContinuations.terminal(kind, expected_source, data["battleId"], caller) if data.size() == 3 else null
	if kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT]:
		return _decode_combat_retreat(kind, expected_source, data, caller)
	if kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE]:
		return _decode_combat_age(kind, expected_source, data, caller)
	return _decode_combat_macro(kind, expected_source, data, caller)


static func _decode_combat_retreat(kind: StringName, source_kind: StringName, data: Dictionary, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	if data.size() != 6 or not data.get("actorId") is String or data["actorId"].is_empty() or data.get("mode") not in ["explicit", "edge"] or not data.get("destination") is Array or data["destination"].size() != 2:
		return null
	var x_value: Variant = _signed_integer_or_null(data["destination"][0])
	var y_value: Variant = _signed_integer_or_null(data["destination"][1])
	if x_value == null or y_value == null:
		return null
	var destination := Vector2i(int(x_value), int(y_value))
	if data["mode"] == "explicit" and destination != Vector2i(-100_000, -100_000) or data["mode"] == "edge" and destination == Vector2i(-100_000, -100_000):
		return null
	return ScenarioCombatContinuations.retreat(kind, source_kind, data["battleId"], caller, data["actorId"], StringName(data["mode"]), destination)


static func _decode_combat_age(kind: StringName, source_kind: StringName, data: Dictionary, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	if data.size() != 6 or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30:
		return null
	var index := _integer(data.get("index"))
	var round_before := _integer(data.get("roundBefore"))
	if index < 1 or index > data["updates"].size() or round_before < 1:
		return null
	var updates: Array[AgeUpdateRequestBody] = []
	for update: Variant in data["updates"]:
		var typed_update := ScenarioAgeContinuations.update_from_data(update)
		if typed_update == null:
			return null
		updates.append(typed_update)
	return ScenarioCombatContinuations.age_updates(kind, source_kind, data["battleId"], caller, updates, index, round_before)


static func _decode_combat_macro(kind: StringName, source_kind: StringName, data: Dictionary, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	if not data.get("programId") is String or data["programId"].is_empty():
		return null
	var macro_vm := ScenarioVmSnapshot.from_data(data.get("macroVm"))
	if macro_vm == null:
		return null
	if kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO]:
		return ScenarioCombatContinuations.macro(kind, source_kind, data["battleId"], caller, data["programId"], macro_vm) if data.size() == 5 else null
	if data.size() != 7 or not data.get("combatantId") is String or data["combatantId"].is_empty() or not data.get("resetTraitorOnComplete") is bool:
		return null
	return ScenarioCombatContinuations.macro(kind, source_kind, data["battleId"], caller, data["programId"], macro_vm, data["combatantId"], data["resetTraitorOnComplete"])


static func _decode_opcode_death_macro(data: Dictionary) -> ScenarioRuntimeContinuation:
	if data.size() != 5 or not data.get("battleId") is String or data["battleId"].is_empty() or not data.get("combatantId") is String or data["combatantId"].is_empty() or not data.get("programId") is String or data["programId"].is_empty():
		return null
	var remaining := _strings(data.get("remainingCombatantIds"))
	if remaining.size() != data["remainingCombatantIds"].size() or remaining.size() > 100:
		return null
	var macro_vm := ScenarioVmSnapshot.from_data(data.get("macroVm"))
	return ScenarioCombatContinuations.opcode_death_macro(data["battleId"], data["combatantId"], data["programId"], remaining, macro_vm) if macro_vm != null else null


static func _safe_combat_kinds() -> Array[StringName]:
	return [ScenarioRuntimeContinuation.SAFE_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE]


static func _integers(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		var normalized := _signed_integer(entry)
		if normalized == -100000:
			return []
		result.append(normalized)
	return result


static func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if not entry is String or entry.is_empty() or result.has(entry):
			return []
		result.append(entry)
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100000


static func _signed_integer_or_null(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null


static func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 32:
		return false
	if value == null or value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		if value.size() > 4096:
			return false
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 4096:
			return false
		for key: Variant in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false
