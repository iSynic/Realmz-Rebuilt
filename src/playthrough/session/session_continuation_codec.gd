## Decodes the strict saved envelope for every feature-owned session continuation.

class_name SessionContinuationCodec
extends RefCounted


static func decode(value: Variant) -> SessionContinuation:
	if not value is Dictionary:
		return null
	var envelope: Dictionary = value
	if envelope.size() != 3 or envelope.get("version") != SessionContinuation.VERSION or not _is_nonempty_string(envelope.get("kind")) or not envelope.get("data") is Dictionary:
		return null
	var kind: String = envelope["kind"]
	var data: Dictionary = envelope["data"]
	return _decode_payload(StringName(kind), data)


static func _decode_payload(kind: StringName, data: Dictionary) -> SessionContinuation:
	match kind:
		&"post-clock": return _decode_post_clock(data)
		&"post-move": return _decode_post_move(data)
		&"boat-choice": return _decode_boat(data)
		&"application-hook": return _decode_application_hook(data)
		&"character-spell-confirmation":
			var remaining := _integer(data.get("remaining"))
			if not _has_exact_fields(data, ["characterId", "remaining"]) or not _is_nonempty_string(data.get("characterId")) or remaining < 1:
				return null
			var spell_character_id: String = data["characterId"]
			return CharacterContinuations.spell_confirmation(spell_character_id, remaining)
		&"character-vault-publication":
			if not _has_exact_fields(data, ["characterId"]) or not _is_nonempty_string(data.get("characterId")):
				return null
			var vault_character_id: String = data["characterId"]
			return CharacterContinuations.vault_publication(vault_character_id)
		&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation", &"drop-item-confirmation":
			return _decode_targeting(kind, data)
		&"item-xap": return _decode_item_xap(data)
		&"service-interaction": return _decode_service(data)
		&"pooled-wealth-departure": return _decode_pooled_wealth(data)
		&"age-updates": return _decode_age(data)
		&"combat-retreat-confirmation", &"combat-friendly-collision", &"combat-round-macro", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery":
			return _decode_combat(kind, data)
		&"combat-reward": return _decode_reward(data)
	return null


static func _decode_service(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["serviceId", "runtimeContinuation"]) or not _is_nonempty_string(data.get("serviceId")):
		return null
	var runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
	if runtime == null or runtime.kind not in [ScenarioRuntimeContinuation.CLASSIC_SHOP, ScenarioRuntimeContinuation.CLASSIC_TEMPLE, ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, ScenarioRuntimeContinuation.CLASSIC_BANKING]:
		return null
	var service_id: String = data["serviceId"]
	return ServiceContinuations.interaction(service_id, runtime)


static func _decode_pooled_wealth(data: Dictionary) -> SessionContinuation:
	var direction_x := _signed_integer(data.get("directionX"))
	var direction_y := _signed_integer(data.get("directionY"))
	if not _has_exact_fields(data, ["stage", "directionX", "directionY"]) or data.get("stage") not in ["warning", "distribution"] or direction_x < -1 or direction_x > 1 or direction_y < -1 or direction_y > 1 or Vector2i(direction_x, direction_y) == Vector2i.ZERO:
		return null
	var stage: String = data["stage"]
	return ServiceContinuations.pooled_wealth_departure(StringName(stage), Vector2i(direction_x, direction_y))


static func _decode_reward(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["battleId", "runtimeContinuation"]) or not _is_nonempty_string(data.get("battleId")):
		return null
	var runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
	var state := runtime.body as ScenarioRewardContinuationBody if runtime != null and runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
	if state == null or state.state == null or state.state.origin != &"battle" or state.state.source_id != data["battleId"]:
		return null
	var battle_id: String = data["battleId"]
	return CombatContinuations.reward(battle_id, runtime)


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
	if not _has_exact_fields(data, fields) or data.get("action") not in ["board", "disembark"] or not _is_nonempty_string(data.get("sourceMapId")) or not _is_nonempty_string(data.get("targetMapId")):
		return null
	var body := BoatContinuationBody.new()
	var action: String = data["action"]
	body.action = StringName(action)
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
	if not _has_exact_fields(data, fields) or not data.get("hook") is String or not _is_nonempty_string(data.get("programId")) or not data.get("resumeKind") is String or not data.get("serviceId") is String or not data.get("partyRevived") is bool:
		return null
	var body := ScenarioApplicationContinuationBody.new()
	var hook: String = data["hook"]
	var resume_kind: String = data["resumeKind"]
	body.hook = StringName(hook)
	body.program_id = data["programId"]
	body.resume_kind = StringName(resume_kind)
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
		if not _is_nonempty_string(data.get("instanceId")) or body.starting_charges < -1 or body.starting_charges > 32767:
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
	if not _has_exact_fields(data, ["updates", "index", "resumeKind", "resumeContinuation"]) or not data.get("updates") is Array:
		return null
	var updates: Array = data["updates"]
	if updates.is_empty() or updates.size() > 30 or not data.get("resumeKind") is String or not data.get("resumeContinuation") is Dictionary:
		return null
	var index := _integer(data.get("index"))
	if index < 1 or index > updates.size():
		return null
	var body := AgeContinuationBody.new()
	for update: Variant in updates:
		var typed_update := _age_update_from_data(update)
		if typed_update == null:
			return null
		body.updates.append(typed_update)
	body.index = index
	var resume_kind: String = data["resumeKind"]
	var resume_data: Dictionary = data["resumeContinuation"]
	body.resume_kind = StringName(resume_kind)
	if body.resume_kind in [&"completed", &"combat-monster-turns"]:
		if not resume_data.is_empty():
			return null
	elif body.resume_kind in [&"post-clock", &"post-move"]:
		body.resume_continuation = SessionContinuation.from_data(data["resumeContinuation"])
		if body.resume_continuation == null or body.resume_continuation.kind != body.resume_kind:
			return null
	else:
		return null
	return CharacterContinuations.age_updates(body)


static func _decode_combat(kind: StringName, data: Dictionary) -> SessionContinuation:
	if not _is_nonempty_string(data.get("battleId")):
		return null
	var body := CombatContinuationBody.new()
	body.battle_id = data["battleId"]
	match kind:
		&"combat-retreat-confirmation", &"combat-friendly-collision":
			if not _decode_combat_action(kind, data, body):
				return null
		&"combat-round-macro":
			if not _has_exact_fields(data, ["battleId", "programId"]) or not _is_nonempty_string(data.get("programId")):
				return null
			body.program_id = data["programId"]
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
	if not _has_exact_fields(data, ["battleId", "actorId", "mode", "destination"]) or not _is_nonempty_string(data.get("actorId")) or data.get("mode") not in valid_modes or not data.get("destination") is Array:
		return false
	var destination_data: Array = data["destination"]
	if destination_data.size() != 2:
		return false
	var x_value: Variant = _signed_integer_or_null(destination_data[0])
	var y_value: Variant = _signed_integer_or_null(destination_data[1])
	if x_value == null or y_value == null:
		return false
	var x: int = x_value
	var y: int = y_value
	var destination := Vector2i(x, y)
	if (data["mode"] == "explicit" and destination != Vector2i(-100_000, -100_000)) or (data["mode"] in ["edge", "friendly"] and destination == Vector2i(-100_000, -100_000)):
		return false
	var mode: String = data["mode"]
	body.actor_id = data["actorId"]
	body.mode = StringName(mode)
	body.destination = destination
	return true


static func _combat_continuation(kind: StringName, body: CombatContinuationBody) -> SessionContinuation:
	match kind:
		&"combat-retreat-confirmation": return CombatContinuations.retreat_confirmation(body)
		&"combat-friendly-collision": return CombatContinuations.friendly_collision(body)
		&"combat-round-macro": return CombatContinuations.round_macro(body)
		&"combat-death-macro": return CombatContinuations.death_macro(body)
		&"combat-ally-selection": return CombatContinuations.ally_selection(body)
		&"combat-fumble-recovery": return CombatContinuations.fumble_recovery(body)
	return null


static func _decode_post_clock(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "timedDay", "timedEncounterIndex", "activeTimedProgramId", "midnightRecoveryPending", "timedCheckX", "timedCheckY", "checkRandom", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "resumeKind", "directionX", "directionY"]
	if data.has("timedScanPending"): fields.append("timedScanPending")
	if data.has("timedScanPending") and not data["timedScanPending"] is bool: return null
	if data.has("movementMarkerPending"):
		fields.append("movementMarkerPending")
		if not data["movementMarkerPending"] is bool: return null
	if not _has_exact_fields(data, fields) or not _is_nonempty_string(data.get("mapId")) or not data.get("activeTimedProgramId") is String or not data.get("midnightRecoveryPending") is bool or not data.get("checkRandom") is bool or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"] or data.get("resumeKind") not in ["completed", "move", "post-move", "attempt-search-completed", "attempt-search-post-move", "area-search-second", "camp-entry-second", "rest-second", "camp-departure-second", "heal"]:
		return null
	var body := ExplorationContinuationBody.new()
	body.map_id = data["mapId"]
	body.coordinate = Vector2i(_integer(data["x"]), _integer(data["y"]))
	var day_value: Variant = _signed_integer_or_null(data["timedDay"])
	if day_value == null: return null
	var timed_day: int = day_value
	if not RealmzClock.valid_component(timed_day): return null
	body.timed_day = timed_day
	body.timed_scan_pending = data.get("timedScanPending", body.timed_day > 0)
	body.movement_marker_pending = data.get("movementMarkerPending", true)
	body.timed_encounter_index = _integer(data["timedEncounterIndex"])
	body.active_timed_program_id = data["activeTimedProgramId"]
	body.midnight_recovery_pending = data["midnightRecoveryPending"]
	body.timed_check_coordinate = Vector2i(_signed_integer(data["timedCheckX"]), _signed_integer(data["timedCheckY"]))
	body.check_random = data["checkRandom"]
	body.random_region_ids = _strings(data["randomRegionIds"])
	body.random_region_index = _integer(data["randomRegionIndex"])
	body.active_random_program_id = data["activeRandomProgramId"]
	body.active_random_region_id = data["activeRandomRegionId"]
	var random_battle_stage: String = data["randomBattleStage"]
	var resume_kind: String = data["resumeKind"]
	body.random_battle_stage = StringName(random_battle_stage)
	body.resume_kind = StringName(resume_kind)
	body.direction = Vector2i(_signed_integer(data["directionX"]), _signed_integer(data["directionY"]))
	if not _valid_post_clock(body, data):
		return null
	return ExplorationContinuations.post_clock(body)


static func _valid_post_clock(body: ExplorationContinuationBody, data: Dictionary) -> bool:
	var region_ids: Array = data["randomRegionIds"]
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.timed_encounter_index < 0 or body.timed_check_coordinate.x < -1 or body.timed_check_coordinate.y < -1 or body.random_region_ids.size() != region_ids.size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.direction.x < -1 or body.direction.x > 1 or body.direction.y < -1 or body.direction.y > 1:
		return false
	if body.resume_kind in [&"completed", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"heal"] and body.direction != Vector2i.ZERO:
		return false
	if body.resume_kind in [&"move", &"camp-departure-second"] and body.direction == Vector2i.ZERO:
		return false
	return body.random_battle_stage != &"surprise-choice" or not body.active_random_region_id.is_empty()


static func _decode_post_move(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if not _has_exact_fields(data, fields) or not _is_nonempty_string(data.get("mapId")) or not data.get("triggerIds") is Array or not data.get("activeTriggerId") is String or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"]:
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
	var random_battle_stage: String = data["randomBattleStage"]
	var trigger_ids: Array = data["triggerIds"]
	var region_ids: Array = data["randomRegionIds"]
	body.random_battle_stage = StringName(random_battle_stage)
	body.action_point_destination_depth = _integer(data["actionPointDestinationDepth"])
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.trigger_ids.size() != trigger_ids.size() or body.trigger_index < 0 or body.random_region_ids.size() != region_ids.size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.action_point_destination_depth < 0 or body.action_point_destination_depth > 1 or body.random_battle_stage == &"surprise-choice" and body.active_random_region_id.is_empty():
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
		if not _is_nonempty_string(data.get(field)):
			return false
	return true


static func _is_nonempty_string(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	return not text.is_empty()


static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			if not _is_nonempty_string(value):
				return []
			result.append(value)
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if _is_integral_float(value):
		var number: float = value
		return int(number)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if _is_integral_float(value):
		var number: float = value
		return int(number)
	return -100000


static func _signed_integer_or_null(value: Variant) -> Variant:
	if value is int:
		return value
	if _is_integral_float(value):
		var number: float = value
		return int(number)
	return null


static func _is_integral_float(value: Variant) -> bool:
	if not value is float:
		return false
	var number: float = value
	return is_equal_approx(number, roundf(number))


static func _age_update_from_data(value: Variant) -> AgeUpdateRequestBody:
	if not value is Dictionary:
		return null
	var payload: Dictionary = value
	var request := InteractionRequest.age_update("continuation.age", payload)
	return null if request == null else request.body as AgeUpdateRequestBody
