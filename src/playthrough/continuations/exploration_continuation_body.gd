## Carries post-clock and post-movement exploration progress.

class_name ExplorationContinuationBody
extends SessionContinuationBody

var map_id: String
var coordinate: Vector2i
var timed_day: int
var timed_encounter_index: int
var active_timed_program_id: String
var midnight_recovery_pending: bool
var timed_check_coordinate: Vector2i
var check_random: bool
var random_region_ids: Array[String]
var random_region_index: int
var active_random_program_id: String
var active_random_region_id: String
var random_battle_stage: StringName
var resume_kind: StringName
var direction: Vector2i
var trigger_ids: Array[String]
var trigger_index: int
var active_trigger_id: String
var action_point_destination_depth: int


func wire_payload(kind: StringName) -> Dictionary:
	if kind == &"post-clock":
		return {"kind": String(kind), "mapId": map_id, "x": coordinate.x, "y": coordinate.y, "timedDay": timed_day, "timedEncounterIndex": timed_encounter_index, "activeTimedProgramId": active_timed_program_id, "midnightRecoveryPending": midnight_recovery_pending, "timedCheckX": timed_check_coordinate.x, "timedCheckY": timed_check_coordinate.y, "checkRandom": check_random, "randomRegionIds": random_region_ids.duplicate(), "randomRegionIndex": random_region_index, "activeRandomProgramId": active_random_program_id, "activeRandomRegionId": active_random_region_id, "randomBattleStage": String(random_battle_stage), "resumeKind": String(resume_kind), "directionX": direction.x, "directionY": direction.y}
	return {"kind": String(kind), "mapId": map_id, "x": coordinate.x, "y": coordinate.y, "triggerIds": trigger_ids.duplicate(), "triggerIndex": trigger_index, "activeTriggerId": active_trigger_id, "randomRegionIds": random_region_ids.duplicate(), "randomRegionIndex": random_region_index, "activeRandomProgramId": active_random_program_id, "activeRandomRegionId": active_random_region_id, "randomBattleStage": String(random_battle_stage), "actionPointDestinationDepth": action_point_destination_depth}
