## Decodes the strict saved envelope for every feature-owned session continuation.

class_name SessionContinuationCodec
extends RefCounted


static func decode(value: Variant) -> SessionContinuation:
	if not value is Dictionary or value.size() != 3 or value.get("version") != SessionContinuation.VERSION or not value.get("kind") is String or value["kind"].is_empty() or not value.get("data") is Dictionary:
		return null
	return _decode_payload(StringName(value["kind"]), value["data"])


static func _decode_payload(kind: StringName, data: Dictionary) -> SessionContinuation:
	match kind:
		&"post-clock": return _decode_post_clock(data)
		&"post-move": return _decode_post_move(data)
		&"boat-choice": return _decode_boat(data)
		&"application-hook": return _decode_application_hook(data)
		&"character-spell-confirmation":
			var remaining := _integer(data.get("remaining"))
			return CharacterContinuations.spell_confirmation(data["characterId"], remaining) if _has_exact_fields(data, ["characterId", "remaining"]) and data.get("characterId") is String and not data["characterId"].is_empty() and remaining >= 1 else null
		&"character-vault-publication":
			return CharacterContinuations.vault_publication(data["characterId"]) if _has_exact_fields(data, ["characterId"]) and data.get("characterId") is String and not data["characterId"].is_empty() else null
		&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation", &"drop-item-confirmation":
			return _decode_targeting(kind, data)
		&"item-xap": return _decode_item_xap(data)
		&"service-interaction": return _decode_service(data)
		&"pooled-wealth-departure": return _decode_pooled_wealth(data)
		&"age-updates": return _decode_age(data)
		&"combat-retreat-confirmation", &"combat-friendly-collision", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery":
			return _decode_combat(kind, data)
		&"combat-reward": return _decode_reward(data)
	return null


static func _decode_service(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["serviceId", "runtimeContinuation"]) or not data.get("serviceId") is String or data["serviceId"].is_empty():
		return null
	var runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
	if runtime == null or runtime.kind not in [ScenarioRuntimeContinuation.CLASSIC_SHOP, ScenarioRuntimeContinuation.CLASSIC_TEMPLE, ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, ScenarioRuntimeContinuation.CLASSIC_BANKING]:
		return null
	return ServiceContinuations.interaction(data["serviceId"], runtime)


static func _decode_pooled_wealth(data: Dictionary) -> SessionContinuation:
	var direction_x := _signed_integer(data.get("directionX"))
	var direction_y := _signed_integer(data.get("directionY"))
	if not _has_exact_fields(data, ["stage", "directionX", "directionY"]) or data.get("stage") not in ["warning", "distribution"] or direction_x < -1 or direction_x > 1 or direction_y < -1 or direction_y > 1 or Vector2i(direction_x, direction_y) == Vector2i.ZERO:
		return null
	return ServiceContinuations.pooled_wealth_departure(StringName(data["stage"]), Vector2i(direction_x, direction_y))


static func _decode_reward(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["battleId", "runtimeContinuation"]) or not data.get("battleId") is String or data["battleId"].is_empty():
		return null
	var runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
	var state := runtime.body as ScenarioRewardContinuationBody if runtime != null and runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
	if state == null or state.state == null or state.state.origin != &"battle" or state.state.source_id != data["battleId"]:
		return null
	return CombatContinuations.reward(data["battleId"], runtime)


static func _decode_item_xap(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["characterId", "instanceId", "itemId", "programId", "sourceBattleId"]
	if not _has_exact_fields(data, fields) or not _nonempty_strings(data, ["characterId", "instanceId", "itemId", "programId"]) or not data.get("sourceBattleId") is String:
		return null
	var body := ItemXapContinuationBody.new()
	body.character_id = data["characterId"]
	body.instance_id = data["instanceId"]
	body.item_id = data["itemId"]
	body.program_id = data["programId"]
	body.source_battle_id = data["sourceBattleId"]
	return InventoryContinuations.item_xap(body)


static func _decode_boat(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["action", "sourceMapId", "sourceX", "sourceY", "targetMapId", "targetX", "targetY", "directionX", "directionY"]
	if not _has_exact_fields(data, fields) or data.get("action") not in ["board", "disembark"] or not data.get("sourceMapId") is String or data["sourceMapId"].is_empty() or not data.get("targetMapId") is String or data["targetMapId"].is_empty():
		return null
	var body := BoatContinuationBody.new()
	body.action = StringName(data["action"])
	body.source_map_id = data["sourceMapId"]
	body.source_coordinate = Vector2i(_integer(data["sourceX"]), _integer(data["sourceY"]))
	body.target_map_id = data["targetMapId"]
	body.target_coordinate = Vector2i(_integer(data["targetX"]), _integer(data["targetY"]))
	body.direction = Vector2i(_signed_integer(data["directionX"]), _signed_integer(data["directionY"]))
	if body.source_coordinate.x < 0 or body.source_coordinate.y < 0 or body.target_coordinate.x < 0 or body.target_coordinate.y < 0 or body.direction == Vector2i.ZERO or body.direction.x < -1 or body.direction.x > 1 or body.direction.y < -1 or body.direction.y > 1:
		return null
	return ExplorationContinuations.boat_choice(body)


static func _decode_application_hook(data: Dictionary) -> SessionContinuation:
	var scenario_defeat: bool = data.get("resumeKind") == "scenario-party-defeat"
	var fields: Array[String] = ["hook", "programId", "resumeKind", "serviceId", "partyRevived"]
	if scenario_defeat:
		fields.append_array(["suspendedVm", "suspendedOwner", "vmHandoff"])
	if not _has_exact_fields(data, fields) or not data.get("hook") is String or not data.get("programId") is String or data["programId"].is_empty() or not data.get("resumeKind") is String or not data.get("serviceId") is String or not data.get("partyRevived") is bool:
		return null
	var body := ScenarioApplicationContinuationBody.new()
	body.hook = StringName(data["hook"])
	body.program_id = data["programId"]
	body.resume_kind = StringName(data["resumeKind"])
	body.service_id = data["serviceId"]
	body.party_revived = data["partyRevived"]
	if not _valid_application_hook(body):
		return null
	if scenario_defeat:
		body.suspended_vm = ScenarioVmSnapshot.from_data(data["suspendedVm"])
		body.suspended_owner = SessionContinuation.from_data(data["suspendedOwner"])
		body.vm_handoff = ScenarioVmHandoff.from_data(data["vmHandoff"])
		if body.suspended_vm == null or body.suspended_owner == null or body.suspended_owner.kind not in [&"post-clock", &"post-move"] or body.vm_handoff == null:
			return null
	return ScenarioContinuations.application_hook(body)


static func _valid_application_hook(body: ScenarioApplicationContinuationBody) -> bool:
	match body.resume_kind:
		&"begin-adventure": return body.hook == ScenarioApplicationHooks.START_GAME and body.service_id.is_empty()
		&"service": return body.hook in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] and not body.service_id.is_empty()
		&"end-adventure": return body.hook == ScenarioApplicationHooks.END_ADVENTURE and body.service_id.is_empty()
		&"end-adventure-close", &"party-defeat", &"scenario-party-defeat": return body.hook == ScenarioApplicationHooks.PARTY_DEATH and body.service_id.is_empty()
	return false


static func _decode_targeting(kind: StringName, data: Dictionary) -> SessionContinuation:
	if kind == &"drop-item-confirmation":
		if not _has_exact_fields(data, ["characterId", "instanceId"]) or not _nonempty_strings(data, ["characterId", "instanceId"]):
			return null
		var drop := TargetingContinuationBody.new()
		drop.character_id = data["characterId"]
		drop.instance_id = data["instanceId"]
		return InventoryContinuations.drop_confirmation(drop)
	if kind == &"scroll-discard-confirmation":
		return _decode_scroll_discard(data)
	var fields: Array[String] = ["characterId", "spellId", "power", "targetCount"]
	match kind:
		&"item-use-target-selection": fields.append_array(["instanceId", "startingCharges"])
		&"field-spell-target-selection": fields.append("startingSpellPoints")
		&"scroll-target-selection": fields.append("scrollSlot")
	if not _has_exact_fields(data, fields) or not _nonempty_strings(data, ["characterId", "spellId"]):
		return null
	var body := TargetingContinuationBody.new()
	body.character_id = data["characterId"]
	body.spell_id = data["spellId"]
	body.power = _integer(data.get("power"))
	body.target_count = _integer(data.get("targetCount"))
	if body.power < 1 or body.power > 7 or body.target_count < 1 or body.target_count > 6 or not _read_target_source(kind, data, body):
		return null
	return _targeting_continuation(kind, body)


static func _decode_scroll_discard(data: Dictionary) -> SessionContinuation:
	var body := TargetingContinuationBody.new()
	body.power = _integer(data.get("power"))
	body.scroll_slot = _integer(data.get("scrollSlot"))
	if not _has_exact_fields(data, ["characterId", "spellId", "power", "scrollSlot"]) or not _nonempty_strings(data, ["characterId", "spellId"]) or body.power < 1 or body.power > 7 or body.scroll_slot < 0 or body.scroll_slot >= 5:
		return null
	body.character_id = data["characterId"]
	body.spell_id = data["spellId"]
	return MagicContinuations.scroll_discard(body)


static func _read_target_source(kind: StringName, data: Dictionary, body: TargetingContinuationBody) -> bool:
	if kind == &"item-use-target-selection":
		body.starting_charges = _integer(data.get("startingCharges"))
		if not data.get("instanceId") is String or data["instanceId"].is_empty() or body.starting_charges < -1 or body.starting_charges > 32767:
			return false
		body.instance_id = data["instanceId"]
	elif kind == &"field-spell-target-selection":
		body.starting_spell_points = _integer(data.get("startingSpellPoints"))
		if body.starting_spell_points < 0 or body.starting_spell_points > 32767:
			return false
	else:
		body.scroll_slot = _integer(data.get("scrollSlot"))
		if body.scroll_slot < 0 or body.scroll_slot >= 5:
			return false
	return true


static func _targeting_continuation(kind: StringName, body: TargetingContinuationBody) -> SessionContinuation:
	match kind:
		&"item-use-target-selection": return InventoryContinuations.item_target(body)
		&"field-spell-target-selection": return MagicContinuations.field_spell_target(body)
		&"scroll-target-selection": return MagicContinuations.scroll_target(body)
	return null


static func _decode_age(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["updates", "index", "resumeKind", "resumeContinuation"]) or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30 or not data.get("resumeKind") is String or not data.get("resumeContinuation") is Dictionary:
		return null
	var index := _integer(data.get("index"))
	if index < 1 or index > data["updates"].size():
		return null
	var body := AgeContinuationBody.new()
	for update: Variant in data["updates"]:
		var typed_update := _age_update_from_data(update)
		if typed_update == null:
			return null
		body.updates.append(typed_update)
	body.index = index
	body.resume_kind = StringName(data["resumeKind"])
	if body.resume_kind in [&"completed", &"combat-monster-turns"]:
		if not data["resumeContinuation"].is_empty():
			return null
	elif body.resume_kind in [&"post-clock", &"post-move"]:
		body.resume_continuation = SessionContinuation.from_data(data["resumeContinuation"])
		if body.resume_continuation == null or body.resume_continuation.kind != body.resume_kind:
			return null
	else:
		return null
	return CharacterContinuations.age_updates(body)


static func _decode_combat(kind: StringName, data: Dictionary) -> SessionContinuation:
	if not data.get("battleId") is String or data["battleId"].is_empty():
		return null
	var body := CombatContinuationBody.new()
	body.battle_id = data["battleId"]
	match kind:
		&"combat-retreat-confirmation", &"combat-friendly-collision":
			if not _decode_combat_action(kind, data, body):
				return null
		&"combat-death-macro":
			if not _has_exact_fields(data, ["battleId", "combatantId", "programId", "resetTraitorOnComplete"]) or not _nonempty_strings(data, ["combatantId", "programId"]) or not data.get("resetTraitorOnComplete") is bool:
				return null
			body.combatant_id = data["combatantId"]
			body.program_id = data["programId"]
			body.reset_traitor_on_complete = data["resetTraitorOnComplete"]
		&"combat-ally-selection", &"combat-fumble-recovery":
			if not _has_exact_fields(data, ["battleId"]):
				return null
	return _combat_continuation(kind, body)


static func _decode_combat_action(kind: StringName, data: Dictionary, body: CombatContinuationBody) -> bool:
	var valid_modes: Array[String] = []
	valid_modes.assign(["explicit", "edge"] if kind == &"combat-retreat-confirmation" else ["friendly"])
	if not _has_exact_fields(data, ["battleId", "actorId", "mode", "destination"]) or not data.get("actorId") is String or data["actorId"].is_empty() or data.get("mode") not in valid_modes or not data.get("destination") is Array or data["destination"].size() != 2:
		return false
	var x_value: Variant = _signed_integer_or_null(data["destination"][0])
	var y_value: Variant = _signed_integer_or_null(data["destination"][1])
	if x_value == null or y_value == null:
		return false
	var destination := Vector2i(int(x_value), int(y_value))
	if (data["mode"] == "explicit" and destination != Vector2i(-100_000, -100_000)) or (data["mode"] in ["edge", "friendly"] and destination == Vector2i(-100_000, -100_000)):
		return false
	body.actor_id = data["actorId"]
	body.mode = StringName(data["mode"])
	body.destination = destination
	return true


static func _combat_continuation(kind: StringName, body: CombatContinuationBody) -> SessionContinuation:
	match kind:
		&"combat-retreat-confirmation": return CombatContinuations.retreat_confirmation(body)
		&"combat-friendly-collision": return CombatContinuations.friendly_collision(body)
		&"combat-death-macro": return CombatContinuations.death_macro(body)
		&"combat-ally-selection": return CombatContinuations.ally_selection(body)
		&"combat-fumble-recovery": return CombatContinuations.fumble_recovery(body)
	return null


static func _decode_post_clock(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "timedDay", "timedEncounterIndex", "activeTimedProgramId", "midnightRecoveryPending", "timedCheckX", "timedCheckY", "checkRandom", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "resumeKind", "directionX", "directionY"]
	if not _has_exact_fields(data, fields) or not data.get("mapId") is String or data["mapId"].is_empty() or not data.get("activeTimedProgramId") is String or not data.get("midnightRecoveryPending") is bool or not data.get("checkRandom") is bool or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"] or data.get("resumeKind") not in ["completed", "move", "post-move", "attempt-search-completed", "attempt-search-post-move", "area-search-second", "camp-entry-second", "rest-second", "camp-departure-second", "heal"]:
		return null
	var body := ExplorationContinuationBody.new()
	body.map_id = data["mapId"]
	body.coordinate = Vector2i(_integer(data["x"]), _integer(data["y"]))
	body.timed_day = _integer(data["timedDay"])
	body.timed_encounter_index = _integer(data["timedEncounterIndex"])
	body.active_timed_program_id = data["activeTimedProgramId"]
	body.midnight_recovery_pending = data["midnightRecoveryPending"]
	body.timed_check_coordinate = Vector2i(_signed_integer(data["timedCheckX"]), _signed_integer(data["timedCheckY"]))
	body.check_random = data["checkRandom"]
	body.random_region_ids = _strings(data["randomRegionIds"])
	body.random_region_index = _integer(data["randomRegionIndex"])
	body.active_random_program_id = data["activeRandomProgramId"]
	body.active_random_region_id = data["activeRandomRegionId"]
	body.random_battle_stage = StringName(data["randomBattleStage"])
	body.resume_kind = StringName(data["resumeKind"])
	body.direction = Vector2i(_signed_integer(data["directionX"]), _signed_integer(data["directionY"]))
	if not _valid_post_clock(body, data):
		return null
	return ExplorationContinuations.post_clock(body)


static func _valid_post_clock(body: ExplorationContinuationBody, data: Dictionary) -> bool:
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.timed_day < 0 or body.timed_encounter_index < 0 or body.timed_check_coordinate.x < -1 or body.timed_check_coordinate.y < -1 or body.random_region_ids.size() != data["randomRegionIds"].size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.direction.x < -1 or body.direction.x > 1 or body.direction.y < -1 or body.direction.y > 1:
		return false
	if body.resume_kind in [&"completed", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"heal"] and body.direction != Vector2i.ZERO:
		return false
	if body.resume_kind in [&"move", &"camp-departure-second"] and body.direction == Vector2i.ZERO:
		return false
	return body.random_battle_stage != &"surprise-choice" or not body.active_random_region_id.is_empty()


static func _decode_post_move(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if not _has_exact_fields(data, fields) or not data.get("mapId") is String or data["mapId"].is_empty() or not data.get("triggerIds") is Array or not data.get("activeTriggerId") is String or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"]:
		return null
	var body := ExplorationContinuationBody.new()
	body.map_id = data["mapId"]
	body.coordinate = Vector2i(_integer(data["x"]), _integer(data["y"]))
	body.trigger_ids = _strings(data["triggerIds"])
	body.trigger_index = _integer(data["triggerIndex"])
	body.active_trigger_id = data["activeTriggerId"]
	body.random_region_ids = _strings(data["randomRegionIds"])
	body.random_region_index = _integer(data["randomRegionIndex"])
	body.active_random_program_id = data["activeRandomProgramId"]
	body.active_random_region_id = data["activeRandomRegionId"]
	body.random_battle_stage = StringName(data["randomBattleStage"])
	body.action_point_destination_depth = _integer(data["actionPointDestinationDepth"])
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.trigger_ids.size() != data["triggerIds"].size() or body.trigger_index < 0 or body.random_region_ids.size() != data["randomRegionIds"].size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.action_point_destination_depth < 0 or body.action_point_destination_depth > 1 or body.random_battle_stage == &"surprise-choice" and body.active_random_region_id.is_empty():
		return null
	return ExplorationContinuations.post_move(body)


static func _has_exact_fields(data: Dictionary, fields: Array[String]) -> bool:
	if data.size() != fields.size():
		return false
	for field: String in fields:
		if not data.has(field):
			return false
	return true


static func _nonempty_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not data.get(field) is String or data[field].is_empty():
			return false
	return true


static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			if not value is String or value.is_empty():
				return []
			result.append(value)
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


static func _age_update_from_data(value: Variant) -> AgeUpdateRequestBody:
	if not value is Dictionary:
		return null
	var request := InteractionRequest.age_update("continuation.age", value)
	return null if request == null else request.body as AgeUpdateRequestBody
