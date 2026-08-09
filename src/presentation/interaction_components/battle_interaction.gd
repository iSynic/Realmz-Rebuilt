class_name BattleInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	add_hint("Round %d" % int(request.payload.get("round", 1)))
	var actor_id := String(request.payload.get("actorId", ""))
	var actions: Variant = request.payload.get("actions", [])
	var action_ids: Array = actions if actions is Array else []
	var weapon_mode := String(request.payload.get("weaponMode", "melee"))
	add_hint("Weapon mode: %s" % weapon_mode.capitalize())
	var targets: Variant = request.payload.get("targets", [])
	if action_ids.has("attack") and targets is Array:
		for target: Variant in targets:
			if target is Dictionary:
				var verb := "Fire at" if weapon_mode == "missile" else "Attack"
				add_response("%s %s • HP %d/%d" % [verb, target.get("name", "Enemy"), int(target.get("currentHealth", 0)), int(target.get("maximumHealth", 0))], {"actorId": actor_id, "action": "attack", "targetId": String(target.get("id", ""))})
	elif weapon_mode == "melee":
		add_hint(String(request.payload.get("meleeAttackReason", "No adjacent melee target.")))
	var movement: Variant = request.payload.get("movement", [])
	if movement is Array:
		for option: Variant in movement:
			if option is Dictionary:
				var destination: Variant = option.get("destination", [])
				var direction: Variant = option.get("direction", [])
				var edge_retreat := bool(option.get("retreat", false))
				var label := "Leave battle %s" % _direction_label(direction) if edge_retreat else "Move %s • %d MP" % [_direction_label(direction), int(option.get("cost", 0))]
				var action := "retreat_edge" if edge_retreat else "move"
				var response := {"actorId": actor_id, "action": action, "targetId": "", "destination": destination}
				if edge_retreat:
					response["forced"] = bool(option.get("forcedRetreat", false))
				add_response(label, response, bool(option.get("enabled", false)), String(option.get("reason", "Movement unavailable.")))
	if weapon_mode == "missile" and not action_ids.has("attack"):
		var ranged: Variant = request.payload.get("rangedAttack", {})
		var ranged_reason := String(ranged.get("reason", "Missile attacks are unavailable.") if ranged is Dictionary else "Missile attacks are unavailable.")
		add_response("Fire missile unavailable", {}, false, ranged_reason)
	var weapon_switch: Variant = request.payload.get("weaponSwitch", {})
	if action_ids.has("switch_weapon") and weapon_switch is Dictionary:
		var target_mode := String(weapon_switch.get("targetMode", "melee"))
		add_response("Switch to %s" % target_mode, {"actorId": actor_id, "action": "switch_weapon", "targetId": ""})
	if action_ids.has("defend"):
		add_response("Defend", {"actorId": actor_id, "action": "defend", "targetId": ""})
	if action_ids.has("finish"):
		add_response("Finish turn", {"actorId": actor_id, "action": "finish", "targetId": ""})
	var retreat: Variant = request.payload.get("retreat", {})
	var retreat_enabled := action_ids.has("retreat") and retreat is Dictionary and bool(retreat.get("enabled", false))
	var retreat_reason := String(retreat.get("reason", "Retreat is unavailable.") if retreat is Dictionary else "Retreat is unavailable.")
	add_response("Escape", {"actorId": actor_id, "action": "retreat", "targetId": ""}, retreat_enabled, retreat_reason)


static func _direction_label(value: Variant) -> String:
	if not value is Array or value.size() != 2:
		return "?"
	var direction := Vector2i(int(value[0]), int(value[1]))
	return {
		Vector2i(-1, -1): "NW", Vector2i(0, -1): "N", Vector2i(1, -1): "NE",
		Vector2i(-1, 0): "W", Vector2i(1, 0): "E",
		Vector2i(-1, 1): "SW", Vector2i(0, 1): "S", Vector2i(1, 1): "SE",
	}.get(direction, "?")
