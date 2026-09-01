class_name SessionContinuation
extends RefCounted

const VERSION: int = 1


class Body:
	extends RefCounted

	func _payload_data(_kind: StringName) -> Dictionary:
		return {}


class ExplorationBody:
	extends Body
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

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"post-clock":
			return {"kind": String(kind), "mapId": map_id, "x": coordinate.x, "y": coordinate.y, "timedDay": timed_day, "timedEncounterIndex": timed_encounter_index, "activeTimedProgramId": active_timed_program_id, "midnightRecoveryPending": midnight_recovery_pending, "timedCheckX": timed_check_coordinate.x, "timedCheckY": timed_check_coordinate.y, "checkRandom": check_random, "randomRegionIds": random_region_ids.duplicate(), "randomRegionIndex": random_region_index, "activeRandomProgramId": active_random_program_id, "activeRandomRegionId": active_random_region_id, "randomBattleStage": String(random_battle_stage), "resumeKind": String(resume_kind), "directionX": direction.x, "directionY": direction.y}
		return {"kind": String(kind), "mapId": map_id, "x": coordinate.x, "y": coordinate.y, "triggerIds": trigger_ids.duplicate(), "triggerIndex": trigger_index, "activeTriggerId": active_trigger_id, "randomRegionIds": random_region_ids.duplicate(), "randomRegionIndex": random_region_index, "activeRandomProgramId": active_random_program_id, "activeRandomRegionId": active_random_region_id, "randomBattleStage": String(random_battle_stage), "actionPointDestinationDepth": action_point_destination_depth}


class ApplicationBody:
	extends Body
	var hook: StringName
	var program_id: String
	var resume_kind: StringName
	var service_id: String
	var party_revived: bool
	var suspended_vm: ScenarioVmSnapshot
	var suspended_owner: SessionContinuation
	var vm_handoff: ScenarioVmHandoff
	var character_id: String
	var remaining: int

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"character-spell-confirmation":
			return {"kind": String(kind), "characterId": character_id, "remaining": remaining}
		if kind == &"character-vault-publication":
			return {"kind": String(kind), "characterId": character_id}
		var data := {"kind": String(kind), "hook": String(hook), "programId": program_id, "resumeKind": String(resume_kind), "serviceId": service_id, "partyRevived": party_revived}
		if resume_kind == &"scenario-party-defeat":
			data["suspendedVm"] = {} if suspended_vm == null else suspended_vm.to_data()
			data["suspendedOwner"] = {} if suspended_owner == null else suspended_owner.to_data()
			data["vmHandoff"] = {} if vm_handoff == null else vm_handoff.to_data()
		return data


class TargetingBody:
	extends Body
	var character_id: String
	var instance_id: String
	var spell_id: String
	var power: int
	var target_count: int
	var starting_charges: int
	var starting_spell_points: int
	var scroll_slot: int

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"drop-item-confirmation":
			return {"kind": String(kind), "characterId": character_id, "instanceId": instance_id}
		if kind == &"scroll-discard-confirmation":
			return {"kind": String(kind), "characterId": character_id, "spellId": spell_id, "power": power, "scrollSlot": scroll_slot}
		var data := {"kind": String(kind), "characterId": character_id, "spellId": spell_id, "power": power, "targetCount": target_count}
		if kind == &"item-use-target-selection":
			data["instanceId"] = instance_id
			data["startingCharges"] = starting_charges
		elif kind == &"field-spell-target-selection":
			data["startingSpellPoints"] = starting_spell_points
		else:
			data["scrollSlot"] = scroll_slot
		return data


class ItemBody:
	extends Body
	var character_id: String
	var instance_id: String
	var item_id: String
	var program_id: String
	var source_battle_id: String

	func _payload_data(kind: StringName) -> Dictionary:
		return {"kind": String(kind), "characterId": character_id, "instanceId": instance_id, "itemId": item_id, "programId": program_id, "sourceBattleId": source_battle_id}


class ServiceBody:
	extends Body
	var service_id: String
	var runtime_continuation: ScenarioRuntimeContinuation
	var stage: StringName
	var direction: Vector2i

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"pooled-wealth-departure":
			return {"kind": String(kind), "stage": String(stage), "directionX": direction.x, "directionY": direction.y}
		return {"kind": String(kind), "serviceId": service_id, "runtimeContinuation": {} if runtime_continuation == null else runtime_continuation.to_data()}


class AgeBody:
	extends Body
	var updates: Array[InteractionRequest.AgeUpdateBody]
	var index: int
	var resume_kind: StringName
	var resume_continuation: SessionContinuation

	func _payload_data(kind: StringName) -> Dictionary:
		var serialized_updates: Array[Dictionary] = []
		for update: InteractionRequest.AgeUpdateBody in updates:
			serialized_updates.append(update.to_data())
		return {"kind": String(kind), "updates": serialized_updates, "index": index, "resumeKind": String(resume_kind), "resumeContinuation": {} if resume_continuation == null else resume_continuation.to_data()}


class CombatBody:
	extends Body
	var battle_id: String
	var actor_id: String
	var mode: StringName
	var destination: Vector2i
	var combatant_id: String
	var program_id: String
	var reset_traitor_on_complete: bool = true

	func _payload_data(kind: StringName) -> Dictionary:
		if kind in [&"combat-retreat-confirmation", &"combat-friendly-collision"]:
			return {"kind": String(kind), "battleId": battle_id, "actorId": actor_id, "mode": String(mode), "destination": [destination.x, destination.y]}
		if kind == &"combat-death-macro":
			return {"kind": String(kind), "battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "resetTraitorOnComplete": reset_traitor_on_complete}
		return {"kind": String(kind), "battleId": battle_id}


class RewardBody:
	extends Body
	var battle_id: String
	var runtime_continuation: ScenarioRuntimeContinuation

	func _payload_data(kind: StringName) -> Dictionary:
		return {"kind": String(kind), "battleId": battle_id, "runtimeContinuation": {} if runtime_continuation == null else runtime_continuation.to_data()}


class BoatBody:
	extends Body
	var action: StringName
	var source_map_id: String
	var source_coordinate: Vector2i
	var target_map_id: String
	var target_coordinate: Vector2i
	var direction: Vector2i

	func _payload_data(kind: StringName) -> Dictionary:
		return {"kind": String(kind), "action": String(action), "sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "targetMapId": target_map_id, "targetX": target_coordinate.x, "targetY": target_coordinate.y, "directionX": direction.x, "directionY": direction.y}


var kind: StringName
var body: Body


func _init(continuation_kind: StringName = &"", continuation_body: Body = null) -> void:
	kind = continuation_kind
	body = continuation_body


static func post_clock(exploration_body: ExplorationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-clock", exploration_body)


static func post_move(exploration_body: ExplorationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-move", exploration_body)


static func boat_choice(boat_body: BoatBody) -> SessionContinuation:
	return SessionContinuation.new(&"boat-choice", boat_body)


static func application_hook(application_body: ApplicationBody) -> SessionContinuation:
	return SessionContinuation.new(&"application-hook", application_body)


static func character_spell_confirmation(character_id: String, remaining: int) -> SessionContinuation:
	var application_body := ApplicationBody.new()
	application_body.character_id = character_id
	application_body.remaining = remaining
	return SessionContinuation.new(&"character-spell-confirmation", application_body)


static func character_vault_publication(character_id: String) -> SessionContinuation:
	var application_body := ApplicationBody.new()
	application_body.character_id = character_id
	return SessionContinuation.new(&"character-vault-publication", application_body)


static func targeting_selection(continuation_kind: StringName, targeting_body: TargetingBody) -> SessionContinuation:
	assert(continuation_kind in [&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation", &"drop-item-confirmation"])
	return SessionContinuation.new(continuation_kind, targeting_body)


static func item_xap(item_body: ItemBody) -> SessionContinuation:
	return SessionContinuation.new(&"item-xap", item_body)


static func service_interaction(service_id: String, runtime_continuation: ScenarioRuntimeContinuation) -> SessionContinuation:
	var service_body := ServiceBody.new()
	service_body.service_id = service_id
	service_body.runtime_continuation = runtime_continuation.copy() if runtime_continuation != null else null
	return SessionContinuation.new(&"service-interaction", service_body)


static func pooled_wealth_departure(stage: StringName, direction: Vector2i) -> SessionContinuation:
	var service_body := ServiceBody.new()
	service_body.stage = stage
	service_body.direction = direction
	return SessionContinuation.new(&"pooled-wealth-departure", service_body)


static func age_updates(age_body: AgeBody) -> SessionContinuation:
	return SessionContinuation.new(&"age-updates", age_body)


static func combat_state(continuation_kind: StringName, combat_body: CombatBody) -> SessionContinuation:
	assert(continuation_kind in [&"combat-retreat-confirmation", &"combat-friendly-collision", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery"])
	return SessionContinuation.new(continuation_kind, combat_body)


static func combat_reward(battle_id: String, runtime_continuation: ScenarioRuntimeContinuation) -> SessionContinuation:
	var reward_body := RewardBody.new()
	reward_body.battle_id = battle_id
	reward_body.runtime_continuation = runtime_continuation.copy() if runtime_continuation != null else null
	return SessionContinuation.new(&"combat-reward", reward_body)


func is_empty() -> bool:
	return kind.is_empty() or body == null


func clear() -> void:
	kind = &""
	body = null


func exploration() -> ExplorationBody:
	return body as ExplorationBody


func application() -> ApplicationBody:
	return body as ApplicationBody


func targeting() -> TargetingBody:
	return body as TargetingBody


func item_xap_body() -> ItemBody:
	return body as ItemBody


func service() -> ServiceBody:
	return body as ServiceBody


func age() -> AgeBody:
	return body as AgeBody


func combat() -> CombatBody:
	return body as CombatBody


func reward() -> RewardBody:
	return body as RewardBody


func boat() -> BoatBody:
	return body as BoatBody


func copy() -> SessionContinuation:
	if is_empty():
		return SessionContinuation.new()
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live typed continuation must round-trip through its wire codec")
	return duplicate


func _wire_payload() -> Dictionary:
	return body._payload_data(kind) if body != null else {}


func to_data() -> Dictionary:
	var payload := _wire_payload()
	payload.erase("kind")
	return {"kind": String(kind), "version": VERSION, "data": payload}


static func from_data(value: Variant) -> SessionContinuation:
	if not value is Dictionary or value.size() != 3 or value.get("version") != VERSION or not value.get("kind") is String or value["kind"].is_empty() or not value.get("data") is Dictionary:
		return null
	return _from_wire_payload(StringName(value["kind"]), value["data"])


static func _from_wire_payload(continuation_kind: StringName, data: Dictionary) -> SessionContinuation:
	match continuation_kind:
		&"post-clock":
			return _decode_post_clock(data)
		&"post-move":
			return _decode_post_move(data)
		&"boat-choice":
			return _decode_boat(data)
		&"application-hook":
			return _decode_application(data)
		&"character-spell-confirmation":
			var remaining := _integer(data.get("remaining"))
			return character_spell_confirmation(data["characterId"], remaining) if _has_exact_fields(data, ["characterId", "remaining"]) and data.get("characterId") is String and not data["characterId"].is_empty() and remaining >= 1 else null
		&"character-vault-publication":
			return character_vault_publication(data["characterId"]) if _has_exact_fields(data, ["characterId"]) and data.get("characterId") is String and not data["characterId"].is_empty() else null
		&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"scroll-discard-confirmation", &"drop-item-confirmation":
			return _decode_targeting(continuation_kind, data)
		&"item-xap":
			return _decode_item_xap(data)
		&"service-interaction":
			if not _has_exact_fields(data, ["serviceId", "runtimeContinuation"]) or not data.get("serviceId") is String or data["serviceId"].is_empty():
				return null
			var service_runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
			if service_runtime == null or service_runtime.kind not in [ScenarioRuntimeContinuation.CLASSIC_SHOP, ScenarioRuntimeContinuation.CLASSIC_TEMPLE, ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, ScenarioRuntimeContinuation.CLASSIC_BANKING]:
				return null
			return service_interaction(data["serviceId"], service_runtime)
		&"pooled-wealth-departure":
			var direction_x := _signed_integer(data.get("directionX"))
			var direction_y := _signed_integer(data.get("directionY"))
			if not _has_exact_fields(data, ["stage", "directionX", "directionY"]) or data.get("stage") not in ["warning", "distribution"] or direction_x < -1 or direction_x > 1 or direction_y < -1 or direction_y > 1 or Vector2i(direction_x, direction_y) == Vector2i.ZERO:
				return null
			return pooled_wealth_departure(StringName(data["stage"]), Vector2i(direction_x, direction_y))
		&"age-updates":
			return _decode_age(data)
		&"combat-retreat-confirmation", &"combat-friendly-collision", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery":
			return _decode_combat(continuation_kind, data)
		&"combat-reward":
			if not _has_exact_fields(data, ["battleId", "runtimeContinuation"]) or not data.get("battleId") is String or data["battleId"].is_empty():
				return null
			var reward_runtime := ScenarioRuntimeContinuation.from_data(data.get("runtimeContinuation"))
			var reward_state := reward_runtime.body as ScenarioRuntimeContinuation.RewardBody if reward_runtime != null and reward_runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
			if reward_state == null or reward_state.state == null or reward_state.state.origin != &"battle" or reward_state.state.source_id != data["battleId"]:
				return null
			return combat_reward(data["battleId"], reward_runtime)
	return null


static func _decode_item_xap(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["characterId", "instanceId", "itemId", "programId", "sourceBattleId"]
	if not _has_exact_fields(data, fields) or not _nonempty_strings(data, ["characterId", "instanceId", "itemId", "programId"]) or not data.get("sourceBattleId") is String:
		return null
	var body := ItemBody.new()
	body.character_id = data["characterId"]
	body.instance_id = data["instanceId"]
	body.item_id = data["itemId"]
	body.program_id = data["programId"]
	body.source_battle_id = data["sourceBattleId"]
	return item_xap(body)


static func _decode_boat(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["action", "sourceMapId", "sourceX", "sourceY", "targetMapId", "targetX", "targetY", "directionX", "directionY"]
	if not _has_exact_fields(data, fields) or data.get("action") not in ["board", "disembark"] or not data.get("sourceMapId") is String or data["sourceMapId"].is_empty() or not data.get("targetMapId") is String or data["targetMapId"].is_empty():
		return null
	var body := BoatBody.new()
	body.action = StringName(data["action"])
	body.source_map_id = data["sourceMapId"]
	body.source_coordinate = Vector2i(_integer(data["sourceX"]), _integer(data["sourceY"]))
	body.target_map_id = data["targetMapId"]
	body.target_coordinate = Vector2i(_integer(data["targetX"]), _integer(data["targetY"]))
	body.direction = Vector2i(_signed_integer(data["directionX"]), _signed_integer(data["directionY"]))
	if body.source_coordinate.x < 0 or body.source_coordinate.y < 0 or body.target_coordinate.x < 0 or body.target_coordinate.y < 0 or body.direction == Vector2i.ZERO or body.direction.x < -1 or body.direction.x > 1 or body.direction.y < -1 or body.direction.y > 1:
		return null
	return boat_choice(body)


static func _decode_application(data: Dictionary) -> SessionContinuation:
	var scenario_defeat: bool = data.get("resumeKind") == "scenario-party-defeat"
	var fields: Array[String] = ["hook", "programId", "resumeKind", "serviceId", "partyRevived"]
	if scenario_defeat:
		fields.append_array(["suspendedVm", "suspendedOwner", "vmHandoff"])
	if not _has_exact_fields(data, fields) or not data.get("hook") is String or not data.get("programId") is String or data["programId"].is_empty() or not data.get("resumeKind") is String or not data.get("serviceId") is String or not data.get("partyRevived") is bool:
		return null
	var body := ApplicationBody.new()
	body.hook = StringName(data["hook"])
	body.program_id = data["programId"]
	body.resume_kind = StringName(data["resumeKind"])
	body.service_id = data["serviceId"]
	body.party_revived = data["partyRevived"]
	match body.resume_kind:
		&"begin-adventure":
			if body.hook != ScenarioApplicationHooks.START_GAME or not body.service_id.is_empty():
				return null
		&"service":
			if body.hook not in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] or body.service_id.is_empty():
				return null
		&"end-adventure":
			if body.hook != ScenarioApplicationHooks.END_ADVENTURE or not body.service_id.is_empty():
				return null
		&"end-adventure-close", &"party-defeat", &"scenario-party-defeat":
			if body.hook != ScenarioApplicationHooks.PARTY_DEATH or not body.service_id.is_empty():
				return null
		_:
			return null
	if scenario_defeat:
		body.suspended_vm = ScenarioVmSnapshot.from_data(data["suspendedVm"])
		body.suspended_owner = from_data(data["suspendedOwner"])
		body.vm_handoff = ScenarioVmHandoff.from_data(data["vmHandoff"])
		if body.suspended_vm == null or body.suspended_owner == null or body.suspended_owner.kind not in [&"post-clock", &"post-move"] or body.vm_handoff == null:
			return null
	return application_hook(body)


static func _decode_targeting(continuation_kind: StringName, data: Dictionary) -> SessionContinuation:
	if continuation_kind == &"drop-item-confirmation":
		if not _has_exact_fields(data, ["characterId", "instanceId"]) or not _nonempty_strings(data, ["characterId", "instanceId"]):
			return null
		var drop := TargetingBody.new()
		drop.character_id = data["characterId"]
		drop.instance_id = data["instanceId"]
		return targeting_selection(continuation_kind, drop)
	if continuation_kind == &"scroll-discard-confirmation":
		var discard_power := _integer(data.get("power"))
		var discard_slot := _integer(data.get("scrollSlot"))
		if not _has_exact_fields(data, ["characterId", "spellId", "power", "scrollSlot"]) or not _nonempty_strings(data, ["characterId", "spellId"]) or discard_power < 1 or discard_power > 7 or discard_slot < 0 or discard_slot >= 5:
			return null
		var discard := TargetingBody.new()
		discard.character_id = data["characterId"]
		discard.spell_id = data["spellId"]
		discard.power = discard_power
		discard.scroll_slot = discard_slot
		return targeting_selection(continuation_kind, discard)
	var fields: Array[String] = ["characterId", "spellId", "power", "targetCount"]
	match continuation_kind:
		&"item-use-target-selection": fields.append_array(["instanceId", "startingCharges"])
		&"field-spell-target-selection": fields.append("startingSpellPoints")
		&"scroll-target-selection": fields.append("scrollSlot")
	if not _has_exact_fields(data, fields) or not _nonempty_strings(data, ["characterId", "spellId"]):
		return null
	var power := _integer(data.get("power"))
	var target_count := _integer(data.get("targetCount"))
	if power < 1 or power > 7 or target_count < 1 or target_count > 6:
		return null
	var body := TargetingBody.new()
	body.character_id = data["characterId"]
	body.spell_id = data["spellId"]
	body.power = power
	body.target_count = target_count
	if continuation_kind == &"item-use-target-selection":
		var charges := _integer(data.get("startingCharges"))
		if not data.get("instanceId") is String or data["instanceId"].is_empty() or charges < -1 or charges > 32767:
			return null
		body.instance_id = data["instanceId"]
		body.starting_charges = charges
	elif continuation_kind == &"field-spell-target-selection":
		var spell_points := _integer(data.get("startingSpellPoints"))
		if spell_points < 0 or spell_points > 32767:
			return null
		body.starting_spell_points = spell_points
	else:
		var slot := _integer(data.get("scrollSlot"))
		if slot < 0 or slot >= 5:
			return null
		body.scroll_slot = slot
	return targeting_selection(continuation_kind, body)


static func _decode_age(data: Dictionary) -> SessionContinuation:
	if not _has_exact_fields(data, ["updates", "index", "resumeKind", "resumeContinuation"]) or not data.get("updates") is Array or data["updates"].is_empty() or data["updates"].size() > 30 or not data.get("resumeKind") is String or not data.get("resumeContinuation") is Dictionary:
		return null
	var index := _integer(data.get("index"))
	if index < 1 or index > data["updates"].size():
		return null
	var body := AgeBody.new()
	for update: Variant in data["updates"]:
		var typed_update := _age_update_from_data(update)
		if typed_update == null:
			return null
		body.updates.append(typed_update)
	body.index = index
	body.resume_kind = StringName(data["resumeKind"])
	if body.resume_kind in [&"completed", &"combat-monster-turns"]:
		if not data["resumeContinuation"].is_empty():
			return null
	elif body.resume_kind in [&"post-clock", &"post-move"]:
		body.resume_continuation = from_data(data["resumeContinuation"])
		if body.resume_continuation == null or body.resume_continuation.kind != body.resume_kind:
			return null
	else:
		return null
	return age_updates(body)


static func _decode_combat(continuation_kind: StringName, data: Dictionary) -> SessionContinuation:
	if not data.get("battleId") is String or data["battleId"].is_empty():
		return null
	var body := CombatBody.new()
	body.battle_id = data["battleId"]
	match continuation_kind:
		&"combat-retreat-confirmation", &"combat-friendly-collision":
			var valid_modes: Array[String] = []
			valid_modes.assign(["explicit", "edge"] if continuation_kind == &"combat-retreat-confirmation" else ["friendly"])
			if not _has_exact_fields(data, ["battleId", "actorId", "mode", "destination"]) or not data.get("actorId") is String or data["actorId"].is_empty() or data.get("mode") not in valid_modes or not data.get("destination") is Array or data["destination"].size() != 2:
				return null
			var x_value: Variant = _signed_integer_or_null(data["destination"][0])
			var y_value: Variant = _signed_integer_or_null(data["destination"][1])
			if x_value == null or y_value == null:
				return null
			var destination := Vector2i(int(x_value), int(y_value))
			if (data["mode"] == "explicit" and destination != Vector2i(-100_000, -100_000)) or (data["mode"] in ["edge", "friendly"] and destination == Vector2i(-100_000, -100_000)):
				return null
			body.actor_id = data["actorId"]
			body.mode = StringName(data["mode"])
			body.destination = destination
		&"combat-death-macro":
			if not _has_exact_fields(data, ["battleId", "combatantId", "programId", "resetTraitorOnComplete"]) or not _nonempty_strings(data, ["combatantId", "programId"]) or not data.get("resetTraitorOnComplete") is bool:
				return null
			body.combatant_id = data["combatantId"]
			body.program_id = data["programId"]
			body.reset_traitor_on_complete = data["resetTraitorOnComplete"]
		&"combat-ally-selection", &"combat-fumble-recovery":
			if not _has_exact_fields(data, ["battleId"]):
				return null
	return combat_state(continuation_kind, body)


static func _decode_post_clock(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "timedDay", "timedEncounterIndex", "activeTimedProgramId", "midnightRecoveryPending", "timedCheckX", "timedCheckY", "checkRandom", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "resumeKind", "directionX", "directionY"]
	if not _has_exact_fields(data, fields) or not data.get("mapId") is String or data["mapId"].is_empty() or not data.get("activeTimedProgramId") is String or not data.get("midnightRecoveryPending") is bool or not data.get("checkRandom") is bool or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"] or data.get("resumeKind") not in ["completed", "move", "post-move", "attempt-search-completed", "attempt-search-post-move", "area-search-second", "camp-entry-second", "rest-second", "camp-departure-second", "heal"]:
		return null
	var body := ExplorationBody.new()
	body.map_id = data["mapId"]
	body.coordinate = Vector2i(_integer(data["x"]), _integer(data["y"]))
	body.timed_day = _integer(data["timedDay"])
	body.timed_encounter_index = _integer(data["timedEncounterIndex"])
	body.active_timed_program_id = data["activeTimedProgramId"]
	body.midnight_recovery_pending = data["midnightRecoveryPending"]
	body.timed_check_coordinate = Vector2i(_signed_integer(data["timedCheckX"]), _signed_integer(data["timedCheckY"]))
	body.check_random = data["checkRandom"]
	body.random_region_ids = _strings(data["randomRegionIds"])
	body.random_region_index = _integer(data["randomRegionIndex"])
	body.active_random_program_id = data["activeRandomProgramId"]
	body.active_random_region_id = data["activeRandomRegionId"]
	body.random_battle_stage = StringName(data["randomBattleStage"])
	body.resume_kind = StringName(data["resumeKind"])
	body.direction = Vector2i(_signed_integer(data["directionX"]), _signed_integer(data["directionY"]))
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.timed_day < 0 or body.timed_encounter_index < 0 or body.timed_check_coordinate.x < -1 or body.timed_check_coordinate.y < -1 or body.random_region_ids.size() != data["randomRegionIds"].size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.direction.x < -1 or body.direction.x > 1 or body.direction.y < -1 or body.direction.y > 1:
		return null
	if body.resume_kind in [&"completed", &"post-move", &"attempt-search-completed", &"attempt-search-post-move", &"area-search-second", &"camp-entry-second", &"rest-second", &"heal"] and body.direction != Vector2i.ZERO or body.resume_kind in [&"move", &"camp-departure-second"] and body.direction == Vector2i.ZERO or body.random_battle_stage == &"surprise-choice" and body.active_random_region_id.is_empty():
		return null
	return post_clock(body)


static func _decode_post_move(data: Dictionary) -> SessionContinuation:
	var fields: Array[String] = ["mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if not _has_exact_fields(data, fields) or not data.get("mapId") is String or data["mapId"].is_empty() or not data.get("triggerIds") is Array or not data.get("activeTriggerId") is String or not data.get("randomRegionIds") is Array or not data.get("activeRandomProgramId") is String or not data.get("activeRandomRegionId") is String or data.get("randomBattleStage") not in ["", "surprise-choice"]:
		return null
	var body := ExplorationBody.new()
	body.map_id = data["mapId"]
	body.coordinate = Vector2i(_integer(data["x"]), _integer(data["y"]))
	body.trigger_ids = _strings(data["triggerIds"])
	body.trigger_index = _integer(data["triggerIndex"])
	body.active_trigger_id = data["activeTriggerId"]
	body.random_region_ids = _strings(data["randomRegionIds"])
	body.random_region_index = _integer(data["randomRegionIndex"])
	body.active_random_program_id = data["activeRandomProgramId"]
	body.active_random_region_id = data["activeRandomRegionId"]
	body.random_battle_stage = StringName(data["randomBattleStage"])
	body.action_point_destination_depth = _integer(data["actionPointDestinationDepth"])
	if body.coordinate.x < 0 or body.coordinate.y < 0 or body.trigger_ids.size() != data["triggerIds"].size() or body.trigger_index < 0 or body.random_region_ids.size() != data["randomRegionIds"].size() or body.random_region_index < -1 or body.random_region_index >= body.random_region_ids.size() or body.action_point_destination_depth < 0 or body.action_point_destination_depth > 1 or body.random_battle_stage == &"surprise-choice" and body.active_random_region_id.is_empty():
		return null
	return post_move(body)


static func _has_exact_fields(data: Dictionary, fields: Array[String]) -> bool:
	if data.size() != fields.size():
		return false
	for field: String in fields:
		if not data.has(field):
			return false
	return true


static func _nonempty_strings(data: Dictionary, fields: Array[String]) -> bool:
	for field: String in fields:
		if not data.get(field) is String or data[field].is_empty():
			return false
	return true


static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			if not value is String or value.is_empty():
				return []
			result.append(value)
	return result


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100000


static func _signed_integer_or_null(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null


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
		for key: Variant in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false


static func _age_update_from_data(value: Variant) -> InteractionRequest.AgeUpdateBody:
	if not value is Dictionary:
		return null
	var request := InteractionRequest.age_update("continuation.age", value)
	return null if request == null else request.body as InteractionRequest.AgeUpdateBody
