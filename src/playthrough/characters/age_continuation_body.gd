## Carries source-ordered age acknowledgements and their resume point.

class_name AgeContinuationBody
extends SessionContinuationBody

var updates: Array[AgeUpdateRequestBody]
var index: int
var resume_kind: StringName
var resume_continuation: SessionContinuation


func wire_payload(kind: StringName) -> Dictionary:
	var serialized_updates: Array[Dictionary] = []
	for update: AgeUpdateRequestBody in updates:
		serialized_updates.append(update.to_data())
	return {"kind": String(kind), "updates": serialized_updates, "index": index, "resumeKind": String(resume_kind), "resumeContinuation": {} if resume_continuation == null else resume_continuation.to_data()}
