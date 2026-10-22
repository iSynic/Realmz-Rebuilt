## Persists and validates save envelope data at the save boundary.

class_name SaveEnvelope
extends SessionSnapshot

const FORMAT: String = "realmz2-save"
const FORMAT_VERSION: int = 8
const MAX_MAP_PREVIEW_BYTES: int = 256 * 1024

var map_preview_jpeg: PackedByteArray = PackedByteArray()
var character_art := CharacterArtBundle.new()


func _init(campaign: String, package_identity: String, rules: String, revision: int, state: GameState, random_state: RealmzRngState, vm_state: ScenarioVmSnapshot = null, action_state: ScenarioActionState = null, pending_continuation: SessionContinuation = null, pending_battle_return: SessionContinuation = null, pending_session_interaction: InteractionRequest = null, native_execution: ClassicExecutionState = null) -> void:
	super(campaign, package_identity, rules, revision, state, random_state, vm_state, action_state, pending_continuation, pending_battle_return, pending_session_interaction, native_execution)


func to_data() -> Dictionary:
	var data := {
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
		"battleReturnContinuation": {} if battle_return_continuation == null else battle_return_continuation.to_data(),
		"sessionInteraction": {} if session_interaction == null else session_interaction.to_data(),
		"classicExecution": classic_execution.to_data(),
	}
	if not map_preview_jpeg.is_empty():
		data["mapPreviewJpeg"] = Marshalls.raw_to_base64(map_preview_jpeg)
	if not character_art.assets().is_empty():
		data["characterArt"] = character_art.to_data()
	return data


static func from_snapshot(snapshot: SessionSnapshot, preview_jpeg: PackedByteArray = PackedByteArray()) -> SaveEnvelope:
	if snapshot == null or not snapshot.is_complete:
		return null
	var envelope := SaveEnvelope.new(snapshot.campaign_id, snapshot.package_hash, snapshot.rules_version, snapshot.view_revision, snapshot.game_state, snapshot.rng_state, snapshot.scenario_vm, snapshot.scenario_action_state, snapshot.continuation, snapshot.battle_return_continuation, snapshot.session_interaction, snapshot.classic_execution)
	envelope.deviation_ids = snapshot.deviation_ids.duplicate()
	envelope.map_preview_jpeg = preview_jpeg.duplicate()
	if snapshot is SaveEnvelope:
		envelope.character_art = CharacterArtBundle.from_data((snapshot as SaveEnvelope).character_art.to_data())
	return envelope


static func from_data(data: Variant) -> SaveEnvelope:
	var version := _integer(data.get("formatVersion")) if data is Dictionary else -1
	var fields: Array[String] = ["format", "formatVersion", "campaignId", "packageHash", "rulesVersion", "deviationIds", "viewRevision", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "battleReturnContinuation", "sessionInteraction"]
	if version in [6, 7, 8]: fields.append("classicExecution")
	if not data is Dictionary or data.size() != fields.size() + (1 if data.has("mapPreviewJpeg") else 0) + (1 if data.has("characterArt") else 0):
		return null
	for field: String in fields:
		if not data.has(field):
			return null
	if data["format"] != FORMAT or version not in [5, 6, 7, FORMAT_VERSION]:
		return null
	if not _clock_shape_is_valid(data["gameState"], version) or not _rules_shape_is_valid(data["gameState"], version):
		return null
	var preview_jpeg := PackedByteArray()
	if data.has("mapPreviewJpeg"):
		if not data["mapPreviewJpeg"] is String or data["mapPreviewJpeg"].length() > MAX_MAP_PREVIEW_BYTES * 2:
			return null
		preview_jpeg = Marshalls.base64_to_raw(data["mapPreviewJpeg"])
		if not valid_map_preview(preview_jpeg):
			return null
	if not data["campaignId"] is String or data["campaignId"].is_empty() or not data["packageHash"] is String or data["packageHash"].length() != 64 or not data["rulesVersion"] is String or data["rulesVersion"].is_empty():
		return null
	var revision := _integer(data["viewRevision"])
	if revision < 0 or not data["deviationIds"] is Array or not data["sessionContinuation"] is Dictionary or not data["battleReturnContinuation"] is Dictionary or not data["sessionInteraction"] is Dictionary:
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
	var native_execution := ClassicExecutionState.from_data(data["classicExecution"]) if version >= 6 else ClassicExecutionState.new()
	if state == null or random_state == null or vm_state == null or action_state == null or native_execution == null:
		return null
	# ADR 0026: v5/v6 predate VM schema 4. v7 may still carry an unrestored
	# legacy VM copied from an older envelope; restore applies its coercion.
	if version < 7 and not vm_state.legacy_values:
		return null
	var typed_continuation := SessionContinuation.from_data(data["sessionContinuation"]) if not data["sessionContinuation"].is_empty() else null
	if not data["sessionContinuation"].is_empty() and typed_continuation == null:
		return null
	var typed_battle_return := SessionContinuation.from_data(data["battleReturnContinuation"]) if not data["battleReturnContinuation"].is_empty() else null
	if not data["battleReturnContinuation"].is_empty() and (typed_battle_return == null or typed_battle_return.kind != &"post-clock"):
		return null
	var session_request: InteractionRequest = null
	if not data["sessionInteraction"].is_empty():
		session_request = InteractionRequest.from_data(data["sessionInteraction"])
		if session_request == null or not _json_safe(session_request.body.to_data(), 0):
			return null
	var envelope := SaveEnvelope.new(data["campaignId"], data["packageHash"], data["rulesVersion"], revision, state, random_state, vm_state, action_state, typed_continuation, typed_battle_return, session_request, native_execution)
	envelope.deviation_ids = deviations
	envelope.map_preview_jpeg = preview_jpeg
	envelope.character_art = CharacterArtBundle.from_data(data.get("characterArt", []))
	if envelope.character_art == null or not envelope.character_art.matches_characters(CharacterArtBundle.snapshot_characters(envelope)):
		return null
	if version >= 6 and not _current_execution_facts_match(data, envelope):
		return null
	return envelope


static func _clock_shape_is_valid(state: Variant, version: int) -> bool:
	if not state is Dictionary or not state.get("clock") is Dictionary: return false
	var clock: Dictionary = state["clock"]
	return clock.size() == 1 and clock.has("totalMinutes") if version == 5 else clock.size() == 3 and clock.has_all(["day", "hour", "minute"])


static func _current_execution_facts_match(data: Dictionary, envelope: SaveEnvelope) -> bool:
	var expected := {"scenarioVm": envelope.scenario_vm.to_data(), "sessionContinuation": {} if envelope.continuation == null else envelope.continuation.to_data(), "battleReturnContinuation": {} if envelope.battle_return_continuation == null else envelope.battle_return_continuation.to_data()}
	for field: String in expected:
		if CanonicalJson.encode(data[field]) != CanonicalJson.encode(expected[field]): return false
	var combat := envelope.game_state.combat
	if combat != null and combat.turns.active_turn != null:
		return CanonicalJson.encode(data["gameState"]["combat"]["activeTurn"]) == CanonicalJson.encode(combat.turns.active_turn.to_data())
	return true


static func valid_map_preview(bytes: PackedByteArray) -> bool:
	if bytes.size() < 4 or bytes.size() > MAX_MAP_PREVIEW_BYTES or bytes[0] != 0xff or bytes[1] != 0xd8 or bytes[bytes.size() - 2] != 0xff or bytes[bytes.size() - 1] != 0xd9:
		return false
	var image := Image.new()
	return image.load_jpg_from_buffer(bytes) == OK and image.get_width() == 320 and image.get_height() == 320


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9_007_199_254_740_991.0:
		return int(value)
	return -1


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


static func _rules_shape_is_valid(value: Variant, version: int) -> bool:
	if not value is Dictionary: return false
	var state: Dictionary = value
	var rules := AdventureRules.from_data(state.get("adventureRules", {"freeTargetingCancellation": false}))
	if rules == null or version >= 8 and not state.has("adventureRules"): return false
	var combat: Variant = state.get("combat")
	if version < 8 and rules.free_targeting_cancellation: return false
	if combat == null: return true
	if not combat is Dictionary: return false
	var battle: Dictionary = combat
	if version < 8:
		return battle.get("roundCursor") == null and battle.get("retainedItemPowers", []) == []
	return battle.has("roundCursor") and battle.has("retainedItemPowers")
