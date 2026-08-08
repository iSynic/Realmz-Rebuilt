class_name BattleInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	add_hint("Round %d" % int(request.payload.get("round", 1)))
	var actor_id := String(request.payload.get("actorId", ""))
	var targets: Variant = request.payload.get("targets", [])
	if targets is Array:
		for target: Variant in targets:
			if target is Dictionary:
				add_response("Attack %s • HP %d/%d" % [target.get("name", "Enemy"), int(target.get("currentHealth", 0)), int(target.get("maximumHealth", 0))], {"actorId": actor_id, "action": "attack", "targetId": String(target.get("id", ""))})
	add_response("Defend", {"actorId": actor_id, "action": "defend", "targetId": ""})
	add_response("Retreat", {"actorId": actor_id, "action": "retreat", "targetId": ""})
	add_response("Tactical movement unavailable", {}, false, "Combat positions are not exposed by the session yet.")
