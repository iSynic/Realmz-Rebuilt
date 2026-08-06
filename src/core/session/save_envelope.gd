class_name SaveEnvelope
extends RefCounted

const FORMAT: String = "realmz2-save"
const FORMAT_VERSION: int = 1

var campaign_id: String
var package_hash: String
var rules_version: String
var view_revision: int
var game_state: GameState
var rng_state: RealmzRngState
var scenario_vm: ScenarioVmSnapshot
var scenario_action_state: ScenarioActionState
var session_continuation: Dictionary = {}
var _deviation_ids: Array[String] = []
var _combat_state: Dictionary = {}
var _metadata: Dictionary = {}


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, continuation: Dictionary = {}) -> void:
	campaign_id = campaign
	package_hash = package_identity
	rules_version = rules
	view_revision = revision
	game_state = state
	rng_state = random_state
	scenario_vm = vm_state if vm_state != null else ScenarioVmSnapshot.new()
	scenario_action_state = action_state if action_state != null else ScenarioActionState.new()
	session_continuation = continuation.duplicate(true)


func pending_interaction() -> InteractionRequest:
	return scenario_vm.pending_request


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
		"combatState": _combat_state.duplicate(true),
		"metadata": _metadata.duplicate(true),
	}


static func from_data(data: Variant) -> SaveEnvelope:
	if not data is Dictionary:
		return null
	var fields: Array[String] = ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "deviationIds", "viewRevision", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "combatState", "metadata"]
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
	if not data["deviationIds"] is Array or not data["sessionContinuation"] is Dictionary or not data["combatState"] is Dictionary or not data["metadata"] is Dictionary:
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
	if normalized_continuation == null or not _json_safe(data["combatState"], 0) or not _json_safe(data["metadata"], 0):
		return null
	var envelope := SaveEnvelope.new(data["campaignId"], data["packageHash"], data["rulesVersion"], revision, state, random_state, vm_state, action_state, normalized_continuation)
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


static func _normalize_session_continuation(value: Dictionary) -> Variant:
	if value.is_empty():
		return {}
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId"]
	if value.size() != fields.size():
		return null
	for field: String in fields:
		if not value.has(field):
			return null
	var x := _integer(value["x"])
	var y := _integer(value["y"])
	var trigger_index := _integer(value["triggerIndex"])
	if value["kind"] != "post-move" or not value["mapId"] is String or x < 0 or y < 0 or not value["triggerIds"] is Array or trigger_index < 0 or not value["activeTriggerId"] is String:
		return null
	var trigger_ids: Array[String] = []
	for trigger_id: Variant in value["triggerIds"]:
		if not trigger_id is String or trigger_id.is_empty():
			return null
		trigger_ids.append(trigger_id)
	return {"kind": "post-move", "mapId": value["mapId"], "x": x, "y": y, "triggerIds": trigger_ids, "triggerIndex": trigger_index, "activeTriggerId": value["activeTriggerId"]}


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
