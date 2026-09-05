## Strictly decodes thief encounter and pick-lock request bodies.
class_name InteractionThiefRequestDecoder
extends RefCounted


static func parse(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	if request_kind == &"thief_encounter":
		return _thief_encounter_from_data(payload)
	if request_kind == &"pick_lock":
		return _pick_lock_from_data(payload)
	return null


static func _thief_encounter_from_data(payload: Dictionary) -> ThiefEncounterRequestBody:
	var fields: Array = ["encounterId", "prompt", "soundId", "characters"]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.ints(payload, ["encounterId", "soundId"]):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["prompt"]) or not payload["characters"] is Array:
		return null
	var result := ThiefEncounterRequestBody.new()
	result.encounter_id = int(payload["encounterId"])
	result.prompt = payload["prompt"]
	result.sound_id = int(payload["soundId"])
	for entry: Variant in payload["characters"]:
		var character := InteractionSelectionValueDecoder.thief_character(entry)
		if character == null:
			return null
		result.characters.append(character)
	return result if result.encounter_id >= 0 and not result.characters.is_empty() else null


static func _pick_lock_from_data(payload: Dictionary) -> PickLockRequestBody:
	var fields: Array = [
		"encounterId", "actionIndex", "actionLabel", "characterId", "characterName",
		"portraitId", "chancePercent", "yellowThreshold", "greenThreshold", "frameRate",
		"timeLimitFrames", "frames",
	]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	var integer_fields: Array = [
		"encounterId", "actionIndex", "chancePercent", "yellowThreshold", "greenThreshold",
		"frameRate", "timeLimitFrames",
	]
	if not InteractionValueDecoderSupport.ints(payload, integer_fields):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["actionLabel", "characterId", "characterName", "portraitId"]):
		return null
	if not payload["frames"] is Array:
		return null
	var result := PickLockRequestBody.new()
	_populate_lock_identity(result, payload)
	if not _lock_bounds_are_valid(result, payload["frames"]):
		return null
	if not _populate_lock_frames(result, payload["frames"]):
		return null
	return result if result.time_limit_frames == result.frames.size() - 1 + result.frame_rate else null


static func _populate_lock_identity(result: PickLockRequestBody, payload: Dictionary) -> void:
	result.encounter_id = int(payload["encounterId"])
	result.action_index = int(payload["actionIndex"])
	result.action_label = payload["actionLabel"]
	result.character_id = payload["characterId"]
	result.character_name = payload["characterName"]
	result.portrait_id = payload["portraitId"]
	result.chance_percent = int(payload["chancePercent"])
	result.yellow_threshold = int(payload["yellowThreshold"])
	result.green_threshold = int(payload["greenThreshold"])
	result.frame_rate = int(payload["frameRate"])
	result.time_limit_frames = int(payload["timeLimitFrames"])


static func _lock_bounds_are_valid(result: PickLockRequestBody, frames: Array) -> bool:
	return (
		result.encounter_id >= 0
		and result.action_index in [2, 4, 6, 7]
		and result.chance_percent >= 1
		and result.chance_percent <= 90
		and result.yellow_threshold >= 20
		and result.green_threshold >= result.yellow_threshold
		and result.green_threshold <= 199
		and result.frame_rate >= 1
		and result.frame_rate <= 60
		and result.time_limit_frames >= result.frame_rate
		and not frames.is_empty()
		and frames.size() <= 421
	)


static func _populate_lock_frames(result: PickLockRequestBody, encoded_frames: Array) -> bool:
	var tumbler_count := -1
	for frame_value: Variant in encoded_frames:
		if not frame_value is Array or frame_value.size() > 6:
			return false
		if tumbler_count < 0:
			tumbler_count = frame_value.size()
		elif frame_value.size() != tumbler_count:
			return false
		var frame: Array[int] = []
		for position: Variant in frame_value:
			if not InteractionValueDecoderSupport.whole(position):
				return false
			if int(position) < 10 or int(position) > 208:
				return false
			frame.append(int(position))
		result.frames.append(frame)
	return true
