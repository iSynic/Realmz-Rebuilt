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
				add_response("Attack %s • HP %d/%d" % [target.get("name", "Enemy"), int(target.get("currentHealth", 0)), int(target.get("maximumHealth", 0))], {"actorId": actor_id, "action": "attack", "targetId": String(target.get("id", ""))})
	if weapon_mode == "missile":
		var ranged: Variant = request.payload.get("rangedAttack", {})
		var ranged_reason := String(ranged.get("reason", "Missile attacks are unavailable.") if ranged is Dictionary else "Missile attacks are unavailable.")
		add_response("Fire missile unavailable", {}, false, ranged_reason)
	var weapon_switch: Variant = request.payload.get("weaponSwitch", {})
	if action_ids.has("switch_weapon") and weapon_switch is Dictionary:
		var target_mode := String(weapon_switch.get("targetMode", "melee"))
		add_response("Switch to %s" % target_mode, {"actorId": actor_id, "action": "switch_weapon", "targetId": ""})
	if action_ids.has("defend"):
		add_response("Defend", {"actorId": actor_id, "action": "defend", "targetId": ""})
	if action_ids.has("retreat"):
		add_response("Retreat", {"actorId": actor_id, "action": "retreat", "targetId": ""})
	add_response("Tactical movement unavailable", {}, false, "Combat positions are not exposed by the session yet.")
