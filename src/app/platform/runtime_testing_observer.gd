## Exports bounded detached observations and validated adventure checkpoints.
class_name RuntimeTestingObserver
extends RefCounted

const RECENT_LIMIT := 128
var _session: GameSessionController
var _content: Callable
var _readiness: Callable
var _recent: Array[Dictionary] = []
var _step_count: int = 0
var revision: int = 0
var last_step: SessionStep
var _submitted: Dictionary = {}


func _init(session: GameSessionController, content: Callable, readiness: Callable) -> void:
	_session = session
	_content = content
	_readiness = readiness
	_session.step_committed.connect(record_step)
	_session.intent_submitted.connect(_record_intent)
	_session.response_submitted.connect(_record_response)


func record_step(step: SessionStep) -> void:
	revision += 1
	last_step = step
	_step_count += 1
	var events: Array[Dictionary] = []
	for event: DomainEvent in step.events.slice(maxi(0, step.events.size() - RECENT_LIMIT)):
		events.append(event.to_data())
	_recent.append({"sequence": _step_count, "revision": step.view_revision, "state": step.state, "submitted": _submitted.duplicate(true), "errorCode": String(step.error_code), "errorMessage": step.error_message, "events": events, "eventsTruncated": step.events.size() > RECENT_LIMIT})
	_submitted.clear()
	if _recent.size() > RECENT_LIMIT:
		_recent.pop_front()


func observe(params: Dictionary) -> Dictionary:
	if not params.is_empty() and params != {"diagnostics": "complete"}:
		return rejected("invalid_params", "Observation accepts an empty object or diagnostics: complete.")
	var view := _session.view()
	var content: RealmzContent = _content.call()
	var pending := view.active_interaction_request()
	var random_trace: Array = _session.session().rng_trace()
	var scenario_trace: Array = _session.session().scenario_trace()
	var limit := RECENT_LIMIT if params.is_empty() else 4096
	var state := {"campaignId": view.campaign_id, "packageHash": content.package_hash if content != null else "", "rulesVersion": view.rules_version, "sessionStarted": view.session_started, "partySetupAvailable": view.party_setup_available, "location": {"mapId": view.party_map_id, "x": view.party_coordinate.x, "y": view.party_coordinate.y}, "clock": {"day": view.realmz_day, "hour": view.realmz_hour, "minute": view.realmz_minute}, "fatigue": view.party_fatigue, "pooledGold": view.pooled_gold, "party": _party(view), "pendingInteraction": pending.to_data() if pending != null else null, "actions": _actions(view), "readiness": _readiness.call(), "recentSteps": _recent.duplicate(true), "recentStepsOmitted": maxi(0, _step_count - RECENT_LIMIT), "rngTrace": random_trace.slice(maxi(0, random_trace.size() - RECENT_LIMIT)), "scenarioTrace": scenario_trace.slice(maxi(0, scenario_trace.size() - RECENT_LIMIT)), "traceScope": "bounded-recent-diagnostics"}
	state["gameRevision"] = view.revision
	state["rngTrace"] = random_trace.slice(maxi(0, random_trace.size() - limit))
	state["scenarioTrace"] = scenario_trace.slice(maxi(0, scenario_trace.size() - limit))
	state["traceLimitReached"] = random_trace.size() >= 4096 or scenario_trace.size() >= 4096
	state["traceScope"] = "bounded-recent-diagnostics" if params.is_empty() else "complete-unless-trace-limit-reached"
	state["services"] = _services(view)
	state["nearbyTargets"] = _targets(view, content)
	if not params.is_empty():
		var snapshot := _session.session().snapshot()
		state["checkpointState"] = {"rng": snapshot.rng_state.to_data(), "gameState": snapshot.game_state.to_data()} if snapshot != null else null
	return accepted(state)


func checkpoint(params: Dictionary) -> Dictionary:
	if not params.is_empty():
		return rejected("invalid_params", "Checkpoint export accepts an empty parameter object.")
	var snapshot := _session.session().snapshot()
	if snapshot == null:
		return rejected("snapshot_unavailable", "There is no safely snapshotable adventure at this boundary; observation remains available.")
	var envelope := SaveEnvelope.from_snapshot(snapshot).to_data()
	return accepted({"checkpoint": envelope, "sha256": JSON.stringify(envelope, "", true, true).sha256_text(), "mode": "observation"})


func accepted(result: Dictionary) -> Dictionary:
	return {"revision": revision, "result": result, "error": null}


func rejected(code: String, message: String) -> Dictionary:
	return {"revision": revision, "result": null, "error": {"code": code, "message": message}}


func _party(view: GameView) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for character: CharacterView in view.party_members:
		var items: Array[Dictionary] = []
		for item: ItemView in character.items:
			items.append({"instanceId": item.instance_id, "classicId": item.classic_id, "name": item.name, "charges": item.charges, "equipped": item.equipped, "identified": item.identified})
		members.append({"id": character.id, "name": character.name, "raceId": character.race_id, "casteId": character.caste_id, "level": character.level, "health": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points, "load": character.carried_load, "maximumLoad": character.maximum_load, "gold": character.gold, "gems": character.gems, "jewelry": character.jewelry, "conditions": character.condition_values.duplicate(), "items": items})
	return members


func _actions(view: GameView) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for key: Variant in view.action_availability:
		var action := view.availability(StringName(key))
		actions.append({"id": String(action.action_id), "enabled": action.enabled, "reason": action.reason})
	return actions


func _services(view: GameView) -> Array[Dictionary]:
	var services: Array[Dictionary] = []
	for service: ServiceView in view.services:
		services.append({"serviceId": service.service_id, "kind": String(service.service_kind), "title": service.title, "actions": service.actions.duplicate(), "disabledReasons": service.disabled_reasons.duplicate()})
	return services


func _targets(view: GameView, content: RealmzContent) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var map := content.world.map_by_id(view.party_map_id) if content != null else null
	if map == null:
		return targets
	for y: int in range(view.party_coordinate.y - 1, view.party_coordinate.y + 2):
		for x: int in range(view.party_coordinate.x - 1, view.party_coordinate.x + 2):
			var cell := map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			for trigger_id: String in cell.trigger_ids():
				var trigger := content.scenario_records.trigger_by_id(trigger_id)
				if trigger != null:
					targets.append({"kind": "action-point", "id": trigger.id, "programId": trigger.program_id, "mapId": trigger.map_id, "x": trigger.coordinate.x, "y": trigger.coordinate.y, "authoredActive": trigger.active, "chancePercent": trigger.chance_percent})
	return targets


func _record_intent(intent: PlayerIntent) -> void:
	_submitted = {"kind": "player-intent", "intent": PlayerIntent.Kind.keys()[intent.kind]} if intent != null else {"kind": "invalid-intent"}
	if intent == null:
		return
	if intent.payload is ExplorationIntentPayloads.Move:
		var movement := intent.payload as ExplorationIntentPayloads.Move
		_submitted["arguments"] = {"dx": movement.direction.x, "dy": movement.direction.y}
	elif intent.payload is EconomyIntentPayloads.Service:
		var service := intent.payload as EconomyIntentPayloads.Service
		_submitted["arguments"] = {"serviceId": service.service_id, "action": String(service.action), "actorId": service.actor_id, "amount": service.amount}
	elif intent.payload is EmptyIntentPayload:
		_submitted["arguments"] = {}
	else:
		_submitted["payloadScope"] = "typed payload details not exported for this intent"


func _record_response(response: InteractionResponse) -> void:
	_submitted = {"kind": "interaction-response", "requestId": response.request_id, "interactionKind": String(response.kind), "body": response.body.to_data() if response.body != null else null} if response != null else {"kind": "invalid-response"}
