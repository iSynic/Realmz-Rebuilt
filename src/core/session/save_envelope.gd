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
var pending_interaction: InteractionRequest
var _vm_frames: Array = []
var _scenario_action_state: Dictionary = {}
var _combat_state: Dictionary = {}
var _metadata: Dictionary = {}


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, pending: InteractionRequest = null) -> void:
	campaign_id = campaign
	package_hash = package_identity
	rules_version = rules
	view_revision = revision
	game_state = state
	rng_state = random_state
	pending_interaction = pending


func to_data() -> Dictionary:
	var pending_data: Variant = null
	if pending_interaction != null:
		pending_data = pending_interaction.to_data()
	return {
		"format": FORMAT,
		"formatVersion": FORMAT_VERSION,
		"campaignId": campaign_id,
		"packageHash": package_hash,
		"rulesVersion": rules_version,
		"deviationIds": [],
		"viewRevision": view_revision,
		"gameState": game_state.to_data(),
		"rng": rng_state.to_data(),
		"pendingInteraction": pending_data,
		"vmFrames": _vm_frames.duplicate(true),
		"scenarioActionState": _scenario_action_state.duplicate(true),
		"combatState": _combat_state.duplicate(true),
		"metadata": _metadata.duplicate(true),
	}


static func from_data(data: Variant) -> SaveEnvelope:
	if not data is Dictionary:
		return null
	for field: String in ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "viewRevision", "gameState", "rng", "pendingInteraction", "vmFrames", "scenarioActionState", "combatState", "metadata"]:
		if not data.has(field):
			return null
	if data["format"] != FORMAT or data["formatVersion"] != FORMAT_VERSION:
		return null
	if not data["campaignId"] is String or data["campaignId"].is_empty() or not data["packageHash"] is String or data["packageHash"].length() != 64:
		return null
	var revision := _integer(data["viewRevision"])
	if not data["rulesVersion"] is String or revision < 0:
		return null
	var state := GameState.from_data(data["gameState"])
	var random_state := RealmzRngState.from_data(data["rng"])
	if state == null or random_state == null:
		return null
	if not data["vmFrames"] is Array or not data["scenarioActionState"] is Dictionary or not data["combatState"] is Dictionary or not data["metadata"] is Dictionary:
		return null
	var pending: InteractionRequest = null
	if data["pendingInteraction"] != null:
		pending = InteractionRequest.from_data(data["pendingInteraction"])
		if pending == null:
			return null
	var envelope := SaveEnvelope.new(data["campaignId"], data["packageHash"], data["rulesVersion"], revision, state, random_state, pending)
	envelope._vm_frames = data["vmFrames"].duplicate(true)
	envelope._scenario_action_state = data["scenarioActionState"].duplicate(true)
	envelope._combat_state = data["combatState"].duplicate(true)
	envelope._metadata = data["metadata"].duplicate(true)
	return envelope


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
