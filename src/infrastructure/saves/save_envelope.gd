class_name SaveEnvelope
extends SessionSnapshot

const FORMAT: String = "realmz2-save"
const FORMAT_VERSION: int = 4

func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, pending_continuation: SessionContinuation = null, pending_session_interaction: InteractionRequest = null) -> void:
	super(campaign, package_identity, rules, revision, state, random_state, vm_state, action_state, pending_continuation, pending_session_interaction)


func to_data() -> Dictionary:
	return {
		"format": FORMAT,
		"formatVersion": FORMAT_VERSION,
		"campaignId": campaign_id,
		"packageHash": package_hash,
		"rulesVersion": rules_version,
		"deviationIds": deviation_ids.duplicate(),
		"viewRevision": view_revision,
		"gameState": game_state.to_data(),
		"rng": rng_state.to_data(),
		"scenarioVm": scenario_vm.to_data(),
		"scenarioActionState": scenario_action_state.to_data(),
		"sessionContinuation": {} if continuation == null else continuation.to_data(),
		"sessionInteraction": {} if session_interaction == null else session_interaction.to_data(),
		"combatState": combat_state.duplicate(true),
		"metadata": metadata.duplicate(true),
	}


static func from_snapshot(snapshot: SessionSnapshot) -> SaveEnvelope:
	if snapshot == null:
		return null
	var envelope := SaveEnvelope.new(snapshot.campaign_id, snapshot.package_hash, snapshot.rules_version, snapshot.view_revision, snapshot.game_state, snapshot.rng_state, snapshot.scenario_vm, snapshot.scenario_action_state, snapshot.continuation, snapshot.session_interaction)
	envelope.deviation_ids = snapshot.deviation_ids.duplicate()
	envelope.combat_state = snapshot.combat_state.duplicate(true)
	envelope.metadata = snapshot.metadata.duplicate(true)
	return envelope


static func from_data(data: Variant) -> SaveEnvelope:
	if not data is Dictionary or data.get("format") != FORMAT or _integer(data.get("formatVersion")) != FORMAT_VERSION:
		return null
	var fields: Array[String] = ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "deviationIds", "viewRevision", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "sessionInteraction", "combatState", "metadata"]
	if data.size() != fields.size():
		return null
	for field: String in fields:
		if not data.has(field):
			return null
	if data["format"] != FORMAT or data["formatVersion"] != FORMAT_VERSION:
		return null
	if not data["campaignId"] is String or data["campaignId"].is_empty() or not data["packageHash"] is String or data["packageHash"].length() != 64:
		return null
	var revision := _integer(data["viewRevision"])
	if not data["rulesVersion"] is String or data["rulesVersion"].is_empty() or revision < 0:
		return null
	if not data["deviationIds"] is Array or not data["sessionContinuation"] is Dictionary or not data["sessionInteraction"] is Dictionary or not data["combatState"] is Dictionary or not data["metadata"] is Dictionary:
		return null
	var deviations: Array[String] = []
	for deviation: Variant in data["deviationIds"]:
		if not deviation is String or deviation.is_empty() or deviations.has(deviation):
			return null
		deviations.append(deviation)
	var state := GameState.from_data(data["gameState"])
	var random_state := RealmzRngState.from_data(data["rng"])
	var vm_state := ScenarioVmSnapshot.from_data(data["scenarioVm"])
	var action_state := ScenarioActionState.from_data(data["scenarioActionState"])
	if state == null or random_state == null or vm_state == null or action_state == null:
		return null
	var normalized_continuation: Variant = {}
	var typed_continuation: SessionContinuation = null
	if not data["sessionContinuation"].is_empty():
		var continuation_wire: Dictionary = data["sessionContinuation"]
		if continuation_wire.size() != 3 or not continuation_wire.get("kind") is String or continuation_wire.get("version") != SessionContinuation.VERSION or not continuation_wire.get("data") is Dictionary:
			return null
		var untrusted_continuation: Dictionary = continuation_wire["data"].duplicate(true)
		untrusted_continuation["kind"] = continuation_wire["kind"]
		normalized_continuation = _normalize_session_continuation(untrusted_continuation)
		if normalized_continuation is Dictionary:
			var normalized_payload: Dictionary = normalized_continuation.duplicate(true)
			var normalized_kind: String = normalized_payload["kind"]
			normalized_payload.erase("kind")
			typed_continuation = SessionContinuation.from_data({"kind": normalized_kind, "version": SessionContinuation.VERSION, "data": normalized_payload})
	var session_request: InteractionRequest = null
	if not data["sessionInteraction"].is_empty():
		session_request = InteractionRequest.from_data(data["sessionInteraction"])
		if session_request == null or not _json_safe(session_request.body.to_data(), 0):
			return null
	if normalized_continuation == null or not _json_safe(data["combatState"], 0) or not _json_safe(data["metadata"], 0):
		return null
	var envelope := SaveEnvelope.new(data["campaignId"], data["packageHash"], data["rulesVersion"], revision, state, random_state, vm_state, action_state, typed_continuation, session_request)
	envelope.deviation_ids = deviations
	envelope.combat_state = data["combatState"].duplicate(true)
	envelope.metadata = data["metadata"].duplicate(true)
	return envelope


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
	return -100_000


static func _normalize_session_continuation(value: Dictionary) -> Variant:
	if value.is_empty():
		return {}
	if value.get("kind") == "application-hook":
		var hook_fields: Array[String] = ["kind", "hook", "programId", "resumeKind", "serviceId", "partyRevived"]
		var scenario_defeat: bool = value.get("resumeKind") == "scenario-party-defeat"
		if scenario_defeat:
			hook_fields.append_array(["suspendedVm", "suspendedOwner", "vmHandoff"])
		if value.size() != hook_fields.size():
			return null
		for field: String in hook_fields:
			if not value.has(field):
				return null
		if not value["hook"] is String or not value["programId"] is String or value["programId"].is_empty() or not value["resumeKind"] is String or not value["serviceId"] is String or not value["partyRevived"] is bool:
			return null
		var hook: String = value["hook"]
		var resume_kind: String = value["resumeKind"]
		var service_id: String = value["serviceId"]
		match resume_kind:
			"begin-adventure":
				if hook != String(ScenarioApplicationHooks.START_GAME) or not service_id.is_empty():
					return null
			"service":
				if hook not in [String(ScenarioApplicationHooks.SHOP), String(ScenarioApplicationHooks.TEMPLE)] or service_id.is_empty():
					return null
			"end-adventure":
				if hook != String(ScenarioApplicationHooks.END_ADVENTURE) or not service_id.is_empty():
					return null
			"end-adventure-close", "party-defeat":
				if hook != String(ScenarioApplicationHooks.PARTY_DEATH) or not service_id.is_empty():
					return null
			"scenario-party-defeat":
				if hook != String(ScenarioApplicationHooks.PARTY_DEATH) or not service_id.is_empty():
					return null
			_:
				return null
		var normalized := {"kind": "application-hook", "hook": hook, "programId": value["programId"], "resumeKind": resume_kind, "serviceId": service_id, "partyRevived": value["partyRevived"]}
		if scenario_defeat:
			var suspended_vm := ScenarioVmSnapshot.from_data(value["suspendedVm"])
			var suspended_owner: Variant = _normalize_session_continuation(value["suspendedOwner"]) if value["suspendedOwner"] is Dictionary else null
			var vm_handoff: Variant = _normalize_vm_handoff(value["vmHandoff"])
			if suspended_vm == null or not suspended_owner is Dictionary or suspended_owner.get("kind") not in ["post-clock", "post-move"] or not vm_handoff is Dictionary:
				return null
			normalized["suspendedVm"] = suspended_vm.to_data()
			normalized["suspendedOwner"] = suspended_owner
			normalized["vmHandoff"] = vm_handoff
		return normalized
	if value.get("kind") == "pooled-wealth-departure":
		var departure_fields: Array[String] = ["kind", "stage", "directionX", "directionY"]
		if value.size() != departure_fields.size():
			return null
		for field: String in departure_fields:
			if not value.has(field):
				return null
		var departure_x := _signed_integer(value["directionX"])
		var departure_y := _signed_integer(value["directionY"])
		if not value["stage"] is String or value["stage"] not in ["warning", "distribution"] or departure_x < -1 or departure_x > 1 or departure_y < -1 or departure_y > 1 or Vector2i(departure_x, departure_y) == Vector2i.ZERO:
			return null
		return {"kind": "pooled-wealth-departure", "stage": value["stage"], "directionX": departure_x, "directionY": departure_y}
	if value.get("kind") == "service-interaction":
		if value.size() != 3 or not value.get("serviceId") is String or value["serviceId"].is_empty() or not value.get("runtimeContinuation") is Dictionary:
			return null
		var runtime: Dictionary = value["runtimeContinuation"]
		var normalized_runtime: Dictionary = {}
		match String(runtime.get("kind", "")):
			"classic-shop":
				if runtime.size() != 3 or not runtime.get("shopId") is String or runtime["shopId"].is_empty() or not runtime.get("acceptRanges") is Array:
					return null
				var ranges: Array[int] = []
				for raw_range: Variant in runtime["acceptRanges"]:
					var accepted_range := _signed_integer(raw_range)
					if accepted_range < -32_768 or accepted_range > 32_767:
						return null
					ranges.append(accepted_range)
				if ranges.size() != 4:
					return null
				normalized_runtime = {"kind": "classic-shop", "shopId": runtime["shopId"], "acceptRanges": ranges}
			"classic-temple", "classic-temple-exit":
				var cost_percent := _signed_integer(runtime.get("costPercent"))
				if runtime.size() != 4 or cost_percent < -32_768 or cost_percent > 32_767 or not runtime.get("bankAvailable") is bool or not runtime.get("selectedCharacterId") is String or runtime["selectedCharacterId"].is_empty():
					return null
				normalized_runtime = {"kind": runtime["kind"], "costPercent": cost_percent, "bankAvailable": runtime["bankAvailable"], "selectedCharacterId": runtime["selectedCharacterId"]}
			"classic-banking":
				if runtime.size() != 1:
					return null
				normalized_runtime = {"kind": "classic-banking"}
			_:
				return null
		return {"kind": "service-interaction", "serviceId": value["serviceId"], "runtimeContinuation": normalized_runtime}
	if value.get("kind") == "drop-item-confirmation":
		var drop_fields: Array[String] = ["kind", "characterId", "instanceId"]
		if value.size() != drop_fields.size():
			return null
		for field: String in drop_fields:
			if not value.has(field) or not value[field] is String or value[field].is_empty():
				return null
		return {"kind": "drop-item-confirmation", "characterId": value["characterId"], "instanceId": value["instanceId"]}
	if value.get("kind") == "item-use-target-selection":
		var item_fields: Array[String] = ["kind", "characterId", "instanceId", "spellId", "power", "targetCount", "startingCharges"]
		if value.size() != item_fields.size():
			return null
		for field: String in item_fields:
			if not value.has(field):
				return null
		var power := _integer(value["power"])
		var target_count := _integer(value["targetCount"])
		var starting_charges := _integer(value["startingCharges"])
		if not value["characterId"] is String or value["characterId"].is_empty() or not value["instanceId"] is String or value["instanceId"].is_empty() or not value["spellId"] is String or value["spellId"].is_empty():
			return null
		if power < 1 or power > 7 or target_count < 1 or target_count > 6 or starting_charges < -1 or starting_charges > 32_767:
			return null
		return {"kind": "item-use-target-selection", "characterId": value["characterId"], "instanceId": value["instanceId"], "spellId": value["spellId"], "power": power, "targetCount": target_count, "startingCharges": starting_charges}
	if value.get("kind") == "field-spell-target-selection":
		var field_spell_fields: Array[String] = ["kind", "characterId", "spellId", "power", "targetCount", "startingSpellPoints"]
		if value.size() != field_spell_fields.size():
			return null
		for field: String in field_spell_fields:
			if not value.has(field):
				return null
		var field_power := _integer(value["power"])
		var field_target_count := _integer(value["targetCount"])
		var starting_spell_points := _integer(value["startingSpellPoints"])
		if not value["characterId"] is String or value["characterId"].is_empty() or not value["spellId"] is String or value["spellId"].is_empty():
			return null
		if field_power < 1 or field_power > 7 or field_target_count < 1 or field_target_count > 6 or starting_spell_points < 0 or starting_spell_points > 32_767:
			return null
		return {"kind": "field-spell-target-selection", "characterId": value["characterId"], "spellId": value["spellId"], "power": field_power, "targetCount": field_target_count, "startingSpellPoints": starting_spell_points}
	if value.get("kind") == "scroll-target-selection":
		var scroll_fields: Array[String] = ["kind", "characterId", "scrollSlot", "spellId", "power", "targetCount"]
		if value.size() != scroll_fields.size():
			return null
		for field: String in scroll_fields:
			if not value.has(field):
				return null
		var scroll_slot := _integer(value["scrollSlot"])
		var scroll_power := _integer(value["power"])
		var scroll_target_count := _integer(value["targetCount"])
		if not value["characterId"] is String or value["characterId"].is_empty() or not value["spellId"] is String or value["spellId"].is_empty():
			return null
		if scroll_slot < 0 or scroll_slot >= 5 or scroll_power < 1 or scroll_power > 7 or scroll_target_count < 1 or scroll_target_count > 6:
			return null
		return {"kind": "scroll-target-selection", "characterId": value["characterId"], "scrollSlot": scroll_slot, "spellId": value["spellId"], "power": scroll_power, "targetCount": scroll_target_count}
	if value.get("kind") == "character-spell-confirmation":
		var spell_fields: Array[String] = ["kind", "characterId", "remaining"]
		if value.size() != spell_fields.size():
			return null
		for field: String in spell_fields:
			if not value.has(field):
				return null
		var remaining := _integer(value["remaining"])
		if not value["characterId"] is String or value["characterId"].is_empty() or remaining < 1:
			return null
		return {"kind": "character-spell-confirmation", "characterId": value["characterId"], "remaining": remaining}
	if value.get("kind") == "character-vault-publication":
		if value.size() != 2 or not value.get("characterId") is String or value["characterId"].is_empty():
			return null
		return {"kind": "character-vault-publication", "characterId": value["characterId"]}
	if value.get("kind") == "age-updates":
		var age_fields: Array[String] = ["kind", "updates", "index", "resumeKind", "resumeContinuation"]
		if value.size() != age_fields.size():
			return null
		for field: String in age_fields:
			if not value.has(field):
				return null
		var index := _integer(value["index"])
		if not value["updates"] is Array or value["updates"].is_empty() or value["updates"].size() > 30 or index < 1 or index > value["updates"].size() or not _json_safe(value["updates"], 0):
			return null
		if not value["resumeKind"] is String or value["resumeKind"] not in ["completed", "post-move", "post-clock", "combat-monster-turns"] or not value["resumeContinuation"] is Dictionary:
			return null
		var resume_continuation: Dictionary = {}
		if value["resumeKind"] in ["completed", "combat-monster-turns"]:
			if not value["resumeContinuation"].is_empty():
				return null
		else:
			var normalized_resume: Variant = _normalize_session_continuation(value["resumeContinuation"])
			if not normalized_resume is Dictionary or normalized_resume.get("kind") != value["resumeKind"]:
				return null
			resume_continuation = normalized_resume
		return {"kind": "age-updates", "updates": value["updates"].duplicate(true), "index": index, "resumeKind": value["resumeKind"], "resumeContinuation": resume_continuation}
	if value.get("kind") == "combat-retreat-confirmation":
		var retreat_fields: Array[String] = ["kind", "battleId", "actorId", "mode", "destination"]
		if value.size() != retreat_fields.size():
			return null
		for field: String in retreat_fields:
			if not value.has(field):
				return null
		if not value["battleId"] is String or value["battleId"].is_empty() or not value["actorId"] is String or value["actorId"].is_empty() or not value["mode"] is String or value["mode"] not in ["explicit", "edge"]:
			return null
		if not value["destination"] is Array or value["destination"].size() != 2 or not value["destination"][0] is int or not value["destination"][1] is int:
			return null
		return {"kind": "combat-retreat-confirmation", "battleId": value["battleId"], "actorId": value["actorId"], "mode": value["mode"], "destination": value["destination"].duplicate()}
	if value.get("kind") == "combat-death-macro":
		var death_fields: Array[String] = ["kind", "battleId", "combatantId", "programId"]
		if value.size() not in [death_fields.size(), death_fields.size() + 1]:
			return null
		for field: String in death_fields:
			if not value.has(field) or not value[field] is String or value[field].is_empty():
				return null
		if value.has("resetTraitorOnComplete") and not value["resetTraitorOnComplete"] is bool:
			return null
		return {"kind": "combat-death-macro", "battleId": value["battleId"], "combatantId": value["combatantId"], "programId": value["programId"], "resetTraitorOnComplete": bool(value.get("resetTraitorOnComplete", true))}
	if value.get("kind") == "combat-ally-selection":
		if value.size() != 2 or not value.get("battleId") is String or value["battleId"].is_empty():
			return null
		return {"kind": "combat-ally-selection", "battleId": value["battleId"]}
	if value.get("kind") == "combat-fumble-recovery":
		if value.size() != 2 or not value.get("battleId") is String or value["battleId"].is_empty():
			return null
		return {"kind": "combat-fumble-recovery", "battleId": value["battleId"]}
	if value.get("kind") == "combat-reward":
		if value.size() != 3 or not value.get("battleId") is String or value["battleId"].is_empty() or not value.get("runtimeContinuation") is Dictionary:
			return null
		var runtime: Dictionary = value["runtimeContinuation"]
		if runtime.size() != 2 or runtime.get("kind") != "classic-reward":
			return null
		var reward := ClassicRewardState.from_data(runtime.get("state"))
		if reward == null or reward.origin != &"battle" or reward.source_id != value["battleId"]:
			return null
		return {"kind": "combat-reward", "battleId": value["battleId"], "runtimeContinuation": {"kind": "classic-reward", "state": reward.to_data()}}
	if value.get("kind") == "post-clock":
		var time_fields: Array[String] = ["kind", "mapId", "x", "y", "timedDay", "timedEncounterIndex", "activeTimedProgramId", "midnightRecoveryPending", "timedCheckX", "timedCheckY", "checkRandom", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "resumeKind", "directionX", "directionY"]
		if value.size() != time_fields.size():
			return null
		for field: String in time_fields:
			if not value.has(field):
				return null
		var time_x := _integer(value["x"])
		var time_y := _integer(value["y"])
		var timed_day := _integer(value["timedDay"])
		var timed_index := _integer(value["timedEncounterIndex"])
		var timed_x := _signed_integer(value["timedCheckX"])
		var timed_y := _signed_integer(value["timedCheckY"])
		var time_random_index := _integer(value["randomRegionIndex"])
		var direction_x := _signed_integer(value["directionX"])
		var direction_y := _signed_integer(value["directionY"])
		if not value["mapId"] is String or value["mapId"].is_empty() or time_x < 0 or time_y < 0 or timed_day < 0 or timed_index < 0 or not value["activeTimedProgramId"] is String or not value["midnightRecoveryPending"] is bool or timed_x < -1 or timed_y < -1 or not value["checkRandom"] is bool or not value["randomRegionIds"] is Array or time_random_index < -1 or not value["activeRandomProgramId"] is String or not value["activeRandomRegionId"] is String or not value["randomBattleStage"] is String or value["randomBattleStage"] not in ["", "surprise-choice"] or not value["resumeKind"] is String or value["resumeKind"] not in ["completed", "move", "post-move"] or direction_x < -1 or direction_x > 1 or direction_y < -1 or direction_y > 1:
			return null
		if value["resumeKind"] in ["completed", "post-move"] and (direction_x != 0 or direction_y != 0):
			return null
		if value["resumeKind"] == "move" and Vector2i(direction_x, direction_y) == Vector2i.ZERO:
			return null
		var time_region_ids: Array[String] = []
		for region_id: Variant in value["randomRegionIds"]:
			if not region_id is String or region_id.is_empty():
				return null
			time_region_ids.append(region_id)
		if time_random_index >= time_region_ids.size() or value["randomBattleStage"] == "surprise-choice" and value["activeRandomRegionId"].is_empty():
			return null
		return {"kind": "post-clock", "mapId": value["mapId"], "x": time_x, "y": time_y, "timedDay": timed_day, "timedEncounterIndex": timed_index, "activeTimedProgramId": value["activeTimedProgramId"], "midnightRecoveryPending": value["midnightRecoveryPending"], "timedCheckX": timed_x, "timedCheckY": timed_y, "checkRandom": value["checkRandom"], "randomRegionIds": time_region_ids, "randomRegionIndex": time_random_index, "activeRandomProgramId": value["activeRandomProgramId"], "activeRandomRegionId": value["activeRandomRegionId"], "randomBattleStage": value["randomBattleStage"], "resumeKind": value["resumeKind"], "directionX": direction_x, "directionY": direction_y}
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if value.size() != fields.size():
		return null
	for field: String in fields:
		if not value.has(field):
			return null
	var x := _integer(value["x"])
	var y := _integer(value["y"])
	var trigger_index := _integer(value["triggerIndex"])
	var random_region_index := _integer(value["randomRegionIndex"])
	var destination_depth := _integer(value["actionPointDestinationDepth"])
	if value["kind"] != "post-move" or not value["mapId"] is String or x < 0 or y < 0 or not value["triggerIds"] is Array or trigger_index < 0 or not value["activeTriggerId"] is String or not value["randomRegionIds"] is Array or random_region_index < -1 or not value["activeRandomProgramId"] is String or not value["activeRandomRegionId"] is String or not value["randomBattleStage"] is String or value["randomBattleStage"] not in ["", "surprise-choice"] or destination_depth < 0 or destination_depth > 1:
		return null
	var trigger_ids: Array[String] = []
	for trigger_id: Variant in value["triggerIds"]:
		if not trigger_id is String or trigger_id.is_empty():
			return null
		trigger_ids.append(trigger_id)
	var random_region_ids: Array[String] = []
	for region_id: Variant in value["randomRegionIds"]:
		if not region_id is String or region_id.is_empty():
			return null
		random_region_ids.append(region_id)
	if random_region_index >= random_region_ids.size():
		return null
	if value["randomBattleStage"] == "surprise-choice" and value["activeRandomRegionId"].is_empty():
		return null
	return {"kind": "post-move", "mapId": value["mapId"], "x": x, "y": y, "triggerIds": trigger_ids, "triggerIndex": trigger_index, "activeTriggerId": value["activeTriggerId"], "randomRegionIds": random_region_ids, "randomRegionIndex": random_region_index, "activeRandomProgramId": value["activeRandomProgramId"], "activeRandomRegionId": value["activeRandomRegionId"], "randomBattleStage": value["randomBattleStage"], "actionPointDestinationDepth": destination_depth}


static func _normalize_vm_handoff(value: Variant) -> Variant:
	if not value is Dictionary or not value.get("runtime") is Dictionary:
		return null
	var runtime: Variant = _normalize_party_defeat_handoff(value["runtime"])
	if not runtime is Dictionary:
		return null
	match value.get("kind"):
		"classic-operation":
			if value.size() != 2:
				return null
			return {"kind": "classic-operation", "runtime": runtime}
		"safe-operation":
			if value.size() != 4 or not value.get("resultTarget") is String:
				return null
			var frame_index := _integer(value.get("frameIndex"))
			if frame_index < 0:
				return null
			return {"kind": "safe-operation", "runtime": runtime, "frameIndex": frame_index, "resultTarget": value["resultTarget"]}
	return null


static func _normalize_party_defeat_handoff(value: Variant) -> Variant:
	if not value is Dictionary or value.size() != 4 or value.get("kind") != "party-defeat" or not value.get("battleId") is String or value["battleId"].is_empty() or value.get("sourceKind") not in ["classic-combat", "safe-combat"]:
		return null
	var caller: Variant = _normalize_battle_caller(value.get("caller"))
	if not caller is Dictionary:
		return null
	if value["sourceKind"] == "safe-combat" and caller.get("kind") != "safe" or value["sourceKind"] == "classic-combat" and caller.get("kind") != "classic":
		return null
	return {"kind": "party-defeat", "battleId": value["battleId"], "sourceKind": value["sourceKind"], "caller": caller}


static func _normalize_battle_caller(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	match value.get("kind"):
		"safe":
			if value.size() != 2 or value.get("policy") != "continue":
				return null
			return {"kind": "safe", "policy": "continue"}
		"classic":
			if value.size() != 5 or not value.get("gosub") is bool:
				return null
			var opcode := _integer(value.get("opcode"))
			var mode := _signed_integer(value.get("mode"))
			var branch_target := _signed_integer(value.get("branchTarget"))
			if opcode not in [2, 48, 56, 107] or mode == -100_000 or branch_target == -100_000:
				return null
			return {"kind": "classic", "opcode": opcode, "gosub": value["gosub"], "mode": mode, "branchTarget": branch_target}
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
		for key: Variant in value.keys():
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false
