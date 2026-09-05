## Carries an exact board or disembark movement choice.

class_name BoatContinuationBody
extends SessionContinuationBody

var action: StringName
var source_map_id: String
var source_coordinate: Vector2i
var target_map_id: String
var target_coordinate: Vector2i
var direction: Vector2i


func wire_payload(kind: StringName) -> Dictionary:
	return {"kind": String(kind), "action": String(action), "sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "targetMapId": target_map_id, "targetX": target_coordinate.x, "targetY": target_coordinate.y, "directionX": direction.x, "directionY": direction.y}
