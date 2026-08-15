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
	var suspended_vm: Dictionary
	var suspended_owner: SessionContinuation
	var vm_handoff: Dictionary
	var character_id: String
	var remaining: int

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"character-spell-confirmation":
			return {"kind": String(kind), "characterId": character_id, "remaining": remaining}
		if kind == &"character-vault-publication":
			return {"kind": String(kind), "characterId": character_id}
		var data := {"kind": String(kind), "hook": String(hook), "programId": program_id, "resumeKind": String(resume_kind), "serviceId": service_id, "partyRevived": party_revived}
		if resume_kind == &"scenario-party-defeat":
			data["suspendedVm"] = suspended_vm.duplicate(true)
			data["suspendedOwner"] = {} if suspended_owner == null else suspended_owner._wire_payload()
			data["vmHandoff"] = vm_handoff.duplicate(true)
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
		var data := {"kind": String(kind), "characterId": character_id, "spellId": spell_id, "power": power, "targetCount": target_count}
		if kind == &"item-use-target-selection":
			data["instanceId"] = instance_id
			data["startingCharges"] = starting_charges
		elif kind == &"field-spell-target-selection":
			data["startingSpellPoints"] = starting_spell_points
		else:
			data["scrollSlot"] = scroll_slot
		return data


class ServiceBody:
	extends Body
	var service_id: String
	var runtime_continuation: Dictionary
	var stage: StringName
	var direction: Vector2i

	func _payload_data(kind: StringName) -> Dictionary:
		if kind == &"pooled-wealth-departure":
			return {"kind": String(kind), "stage": String(stage), "directionX": direction.x, "directionY": direction.y}
		return {"kind": String(kind), "serviceId": service_id, "runtimeContinuation": runtime_continuation.duplicate(true)}


class AgeBody:
	extends Body
	var updates: Array[Dictionary]
	var index: int
	var resume_kind: StringName
	var resume_continuation: SessionContinuation

	func _payload_data(kind: StringName) -> Dictionary:
		var serialized_updates: Array[Dictionary] = []
		for update: Dictionary in updates:
			serialized_updates.append(update.duplicate(true))
		return {"kind": String(kind), "updates": serialized_updates, "index": index, "resumeKind": String(resume_kind), "resumeContinuation": {} if resume_continuation == null else resume_continuation._wire_payload()}


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
		if kind == &"combat-retreat-confirmation":
			return {"kind": String(kind), "battleId": battle_id, "actorId": actor_id, "mode": String(mode), "destination": [destination.x, destination.y]}
		if kind == &"combat-death-macro":
			return {"kind": String(kind), "battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "resetTraitorOnComplete": reset_traitor_on_complete}
		return {"kind": String(kind), "battleId": battle_id}


class RewardBody:
	extends Body
	var battle_id: String
	var runtime_continuation: Dictionary

	func _payload_data(kind: StringName) -> Dictionary:
		return {"kind": String(kind), "battleId": battle_id, "runtimeContinuation": runtime_continuation.duplicate(true)}


var kind: StringName
var body: Body


func _init(continuation_kind: StringName = &"", continuation_body: Body = null) -> void:
	kind = continuation_kind
	body = continuation_body


static func post_clock(exploration_body: ExplorationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-clock", exploration_body)


static func post_move(exploration_body: ExplorationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-move", exploration_body)


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
	assert(continuation_kind in [&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"drop-item-confirmation"])
	return SessionContinuation.new(continuation_kind, targeting_body)


static func service_interaction(service_id: String, runtime_continuation: Dictionary) -> SessionContinuation:
	var service_body := ServiceBody.new()
	service_body.service_id = service_id
	service_body.runtime_continuation = runtime_continuation.duplicate(true)
	return SessionContinuation.new(&"service-interaction", service_body)


static func pooled_wealth_departure(stage: StringName, direction: Vector2i) -> SessionContinuation:
	var service_body := ServiceBody.new()
	service_body.stage = stage
	service_body.direction = direction
	return SessionContinuation.new(&"pooled-wealth-departure", service_body)


static func age_updates(age_body: AgeBody) -> SessionContinuation:
	return SessionContinuation.new(&"age-updates", age_body)


static func combat_state(continuation_kind: StringName, combat_body: CombatBody) -> SessionContinuation:
	assert(continuation_kind in [&"combat-retreat-confirmation", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery"])
	return SessionContinuation.new(continuation_kind, combat_body)


static func combat_reward(battle_id: String, runtime_continuation: Dictionary) -> SessionContinuation:
	var reward_body := RewardBody.new()
	reward_body.battle_id = battle_id
	reward_body.runtime_continuation = runtime_continuation.duplicate(true)
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


func service() -> ServiceBody:
	return body as ServiceBody


func age() -> AgeBody:
	return body as AgeBody


func combat() -> CombatBody:
	return body as CombatBody


func reward() -> RewardBody:
	return body as RewardBody


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
	if not value is Dictionary or value.size() != 3 or value.get("version") != VERSION or not value.get("kind") is String or not value.get("data") is Dictionary:
		return null
	var payload: Dictionary = value["data"].duplicate(true)
	payload["kind"] = value["kind"]
	return _from_wire_payload(payload)


static func _from_wire_payload(data: Dictionary) -> SessionContinuation:
	if data.is_empty():
		return null
	var continuation_kind := StringName(data.get("kind", ""))
	match continuation_kind:
		&"post-clock", &"post-move":
			var exploration := ExplorationBody.new()
			exploration.map_id = String(data.get("mapId", ""))
			exploration.coordinate = Vector2i(int(data.get("x", 0)), int(data.get("y", 0)))
			exploration.random_region_ids.assign(_strings(data.get("randomRegionIds", [])))
			exploration.random_region_index = int(data.get("randomRegionIndex", -1))
			exploration.active_random_program_id = String(data.get("activeRandomProgramId", ""))
			exploration.active_random_region_id = String(data.get("activeRandomRegionId", ""))
			exploration.random_battle_stage = StringName(data.get("randomBattleStage", ""))
			if continuation_kind == &"post-clock":
				exploration.timed_day = int(data.get("timedDay", 0))
				exploration.timed_encounter_index = int(data.get("timedEncounterIndex", 0))
				exploration.active_timed_program_id = String(data.get("activeTimedProgramId", ""))
				exploration.midnight_recovery_pending = bool(data.get("midnightRecoveryPending", false))
				exploration.timed_check_coordinate = Vector2i(int(data.get("timedCheckX", -1)), int(data.get("timedCheckY", -1)))
				exploration.check_random = bool(data.get("checkRandom", false))
				exploration.resume_kind = StringName(data.get("resumeKind", ""))
				exploration.direction = Vector2i(int(data.get("directionX", 0)), int(data.get("directionY", 0)))
			else:
				exploration.trigger_ids.assign(_strings(data.get("triggerIds", [])))
				exploration.trigger_index = int(data.get("triggerIndex", 0))
				exploration.active_trigger_id = String(data.get("activeTriggerId", ""))
				exploration.action_point_destination_depth = int(data.get("actionPointDestinationDepth", 0))
			return SessionContinuation.new(continuation_kind, exploration)
		&"application-hook", &"character-spell-confirmation", &"character-vault-publication":
			var application := ApplicationBody.new()
			application.hook = StringName(data.get("hook", ""))
			application.program_id = String(data.get("programId", ""))
			application.resume_kind = StringName(data.get("resumeKind", ""))
			application.service_id = String(data.get("serviceId", ""))
			application.party_revived = bool(data.get("partyRevived", false))
			application.suspended_vm = data.get("suspendedVm", {}).duplicate(true)
			application.suspended_owner = _from_wire_payload(data.get("suspendedOwner", {}))
			application.vm_handoff = data.get("vmHandoff", {}).duplicate(true)
			application.character_id = String(data.get("characterId", ""))
			application.remaining = int(data.get("remaining", 0))
			return SessionContinuation.new(continuation_kind, application)
		&"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection", &"drop-item-confirmation":
			var targeting := TargetingBody.new()
			targeting.character_id = String(data.get("characterId", ""))
			targeting.instance_id = String(data.get("instanceId", ""))
			targeting.spell_id = String(data.get("spellId", ""))
			targeting.power = int(data.get("power", 0))
			targeting.target_count = int(data.get("targetCount", 0))
			targeting.starting_charges = int(data.get("startingCharges", 0))
			targeting.starting_spell_points = int(data.get("startingSpellPoints", 0))
			targeting.scroll_slot = int(data.get("scrollSlot", -1))
			return SessionContinuation.new(continuation_kind, targeting)
		&"service-interaction", &"pooled-wealth-departure":
			var service := ServiceBody.new()
			service.service_id = String(data.get("serviceId", ""))
			service.runtime_continuation = data.get("runtimeContinuation", {}).duplicate(true)
			service.stage = StringName(data.get("stage", ""))
			service.direction = Vector2i(int(data.get("directionX", 0)), int(data.get("directionY", 0)))
			return SessionContinuation.new(continuation_kind, service)
		&"age-updates":
			var age := AgeBody.new()
			age.updates = []
			for update: Variant in data.get("updates", []):
				age.updates.append(update.duplicate(true))
			age.index = int(data.get("index", 0))
			age.resume_kind = StringName(data.get("resumeKind", ""))
			age.resume_continuation = _from_wire_payload(data.get("resumeContinuation", {}))
			return SessionContinuation.new(continuation_kind, age)
		&"combat-retreat-confirmation", &"combat-death-macro", &"combat-ally-selection", &"combat-fumble-recovery":
			var combat := CombatBody.new()
			combat.battle_id = String(data.get("battleId", ""))
			combat.actor_id = String(data.get("actorId", ""))
			combat.mode = StringName(data.get("mode", ""))
			var destination: Variant = data.get("destination", [0, 0])
			combat.destination = Vector2i(int(destination[0]), int(destination[1])) if destination is Array and destination.size() == 2 else Vector2i.ZERO
			combat.combatant_id = String(data.get("combatantId", ""))
			combat.program_id = String(data.get("programId", ""))
			combat.reset_traitor_on_complete = bool(data.get("resetTraitorOnComplete", true))
			return SessionContinuation.new(continuation_kind, combat)
		&"combat-reward":
			var reward := RewardBody.new()
			reward.battle_id = String(data.get("battleId", ""))
			reward.runtime_continuation = data.get("runtimeContinuation", {}).duplicate(true)
			return SessionContinuation.new(continuation_kind, reward)
	return null


static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			result.append(String(value))
	return result
