class_name SaveEnvelope
extends RefCounted

const FORMAT: String = "realmz2-save"
const FORMAT_VERSION: int = 3

var campaign_id: String
var package_hash: String
var rules_version: String
var view_revision: int
var game_state: GameState
var rng_state: RealmzRngState
var scenario_vm: ScenarioVmSnapshot
var scenario_action_state: ScenarioActionState
var session_continuation: Dictionary = {}
var session_interaction: InteractionRequest
var _deviation_ids: Array[String] = []
var _combat_state: Dictionary = {}
var _metadata: Dictionary = {}


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, continuation: Dictionary = {}, pending_session_interaction: InteractionRequest = null) -> void:
	campaign_id = campaign
	package_hash = package_identity
	rules_version = rules
	view_revision = revision
	game_state = state
	rng_state = random_state
	scenario_vm = vm_state if vm_state != null else ScenarioVmSnapshot.new()
	scenario_action_state = action_state if action_state != null else ScenarioActionState.new()
	session_continuation = continuation.duplicate(true)
	session_interaction = pending_session_interaction


func pending_interaction() -> InteractionRequest:
	return session_interaction if session_interaction != null else scenario_vm.pending_request


func to_data() -> Dictionary:
	return {
		"format": FORMAT,
		"formatVersion": FORMAT_VERSION,
		"campaignId": campaign_id,
		"packageHash": package_hash,
		"rulesVersion": rules_version,
		"deviationIds": _deviation_ids.duplicate(),
		"viewRevision": view_revision,
		"gameState": game_state.to_data(),
		"rng": rng_state.to_data(),
		"scenarioVm": scenario_vm.to_data(),
		"scenarioActionState": scenario_action_state.to_data(),
		"sessionContinuation": session_continuation.duplicate(true),
		"sessionInteraction": {} if session_interaction == null else session_interaction.to_data(),
		"combatState": _combat_state.duplicate(true),
		"metadata": _metadata.duplicate(true),
	}


static func from_data(data: Variant) -> SaveEnvelope:
	var migrated: Variant = _migrate(data)
	if migrated == null:
		return null
	data = migrated
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
	var normalized_continuation: Variant = _normalize_session_continuation(data["sessionContinuation"])
	var session_request: InteractionRequest = null
	if not data["sessionInteraction"].is_empty():
		session_request = InteractionRequest.from_data(data["sessionInteraction"])
		if session_request == null or not _json_safe(session_request.payload, 0):
			return null
	if normalized_continuation == null or not _json_safe(data["combatState"], 0) or not _json_safe(data["metadata"], 0):
		return null
	var envelope := SaveEnvelope.new(data["campaignId"], data["packageHash"], data["rulesVersion"], revision, state, random_state, vm_state, action_state, normalized_continuation, session_request)
	envelope._deviation_ids = deviations
	envelope._combat_state = data["combatState"].duplicate(true)
	envelope._metadata = data["metadata"].duplicate(true)
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


static func _migrate(value: Variant) -> Variant:
	if not value is Dictionary or value.get("format", "") != FORMAT:
		return null
	var version := _integer(value.get("formatVersion", -1))
	if version == FORMAT_VERSION:
		return value.duplicate(true)
	var migrated: Dictionary = value.duplicate(true)
	if version == 1:
		var fields_v1: Array[String] = ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "deviationIds", "viewRevision", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "combatState", "metadata"]
		if migrated.size() != fields_v1.size():
			return null
		for field: String in fields_v1:
			if not migrated.has(field):
				return null
		migrated["formatVersion"] = 2
		migrated["sessionInteraction"] = {}
		if migrated["sessionContinuation"] is Dictionary and not migrated["sessionContinuation"].is_empty():
			var continuation_v1: Dictionary = migrated["sessionContinuation"]
			for field: String in ["randomRegionIds", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage"]:
				if not continuation_v1.has(field):
					if field == "randomRegionIds":
						continuation_v1[field] = []
					else:
						continuation_v1[field] = ""
			if not continuation_v1.has("randomRegionIndex"):
				continuation_v1["randomRegionIndex"] = -1
		version = 2
	if version != 2:
		return null
	var fields_v2: Array[String] = ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "deviationIds", "viewRevision", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "sessionInteraction", "combatState", "metadata"]
	if migrated.size() != fields_v2.size():
		return null
	for field: String in fields_v2:
		if not migrated.has(field):
			return null
	if migrated["sessionContinuation"] is Dictionary and not migrated["sessionContinuation"].is_empty():
		var continuation_v2: Dictionary = migrated["sessionContinuation"]
		if not continuation_v2.has("actionPointDestinationDepth"):
			continuation_v2["actionPointDestinationDepth"] = 0
	migrated["formatVersion"] = FORMAT_VERSION
	return migrated


static func _normalize_session_continuation(value: Dictionary) -> Variant:
	if value.is_empty():
		return {}
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
		if not value["resumeKind"] is String or value["resumeKind"] not in ["completed", "post-move", "combat-monster-turns"] or not value["resumeContinuation"] is Dictionary:
			return null
		var resume_continuation: Dictionary = {}
		if value["resumeKind"] in ["completed", "combat-monster-turns"]:
			if not value["resumeContinuation"].is_empty():
				return null
		else:
			var normalized_resume: Variant = _normalize_session_continuation(value["resumeContinuation"])
			if not normalized_resume is Dictionary or normalized_resume.get("kind") != "post-move":
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
