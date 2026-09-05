## Carries one deterministic Classic tumbler sequence for Pick Lock.

class_name PickLockRequestBody
extends InteractionRequestBody

var encounter_id: int
var action_index: int
var action_label: String
var character_id: String
var character_name: String
var portrait_id: String
var chance_percent: int
var yellow_threshold: int
var green_threshold: int
var frame_rate: int
var time_limit_frames: int
var frames: Array[Array] = []


func to_data() -> Dictionary:
	var serialized: Array[Array] = []
	for frame: Array in frames:
		serialized.append(frame.duplicate())
	return {"encounterId": encounter_id, "actionIndex": action_index, "actionLabel": action_label, "characterId": character_id, "characterName": character_name, "portraitId": portrait_id, "chancePercent": chance_percent, "yellowThreshold": yellow_threshold, "greenThreshold": green_threshold, "frameRate": frame_rate, "timeLimitFrames": time_limit_frames, "frames": serialized}


func prompt_text() -> String:
	return "Stop the tumblers when every marker reaches the gold zone."
