## Exports bounded detached observations and validated adventure checkpoints.
class_name RuntimeTestingObserver
extends RefCounted

const RECENT_LIMIT := 128
var _session: GameSessionController
var _content: Callable
var _readiness: Callable
var _recent: Array[Dictionary] = []
var _step_count: int = 0


func _init(session: GameSessionController, content: Callable, readiness: Callable) -> void:
	_session = session
	_content = content
	_readiness = readiness
	_session.step_committed.connect(record_step)


func record_step(step: SessionStep) -> void:
	_step_count += 1
	var events: Array[Dictionary] = []
	for event: DomainEvent in step.events.slice(maxi(0, step.events.size() - RECENT_LIMIT)):
		events.append(event.to_data())
	_recent.append({"sequence": _step_count, "revision": step.view_revision, "state": step.state, "errorCode": String(step.error_code), "errorMessage": step.error_message, "events": events, "eventsTruncated": step.events.size() > RECENT_LIMIT})
	if _recent.size() > RECENT_LIMIT:
		_recent.pop_front()


func observe(params: Dictionary) -> Dictionary:
	if not params.is_empty():
		return rejected("invalid_params", "Observation currently accepts an empty parameter object.")
	var view := _session.view()
	var content: RealmzContent = _content.call()
	var pending := view.active_interaction_request()
	var random_trace: Array = _session.session().rng_trace()
	var scenario_trace: Array = _session.session().scenario_trace()
	var state := {"campaignId": view.campaign_id, "packageHash": content.package_hash if content != null else "", "rulesVersion": view.rules_version, "sessionStarted": view.session_started, "partySetupAvailable": view.party_setup_available, "location": {"mapId": view.party_map_id, "x": view.party_coordinate.x, "y": view.party_coordinate.y}, "clock": {"day": view.realmz_day, "hour": view.realmz_hour, "minute": view.realmz_minute}, "fatigue": view.party_fatigue, "pooledGold": view.pooled_gold, "party": _party(view), "pendingInteraction": pending.to_data() if pending != null else null, "actions": _actions(view), "readiness": _readiness.call(), "recentSteps": _recent.duplicate(true), "recentStepsOmitted": maxi(0, _step_count - RECENT_LIMIT), "rngTrace": random_trace.slice(maxi(0, random_trace.size() - RECENT_LIMIT)), "scenarioTrace": scenario_trace.slice(maxi(0, scenario_trace.size() - RECENT_LIMIT)), "traceScope": "bounded-recent-diagnostics"}
	return accepted(state)


func checkpoint(params: Dictionary) -> Dictionary:
	if not params.is_empty():
		return rejected("invalid_params", "Checkpoint export accepts an empty parameter object.")
	var snapshot := _session.session().snapshot()
	if snapshot == null:
		return rejected("snapshot_unavailable", "There is no safely snapshotable adventure at this boundary; observation remains available.")
	var envelope := SaveEnvelope.from_snapshot(snapshot).to_data()
	return accepted({"checkpoint": envelope, "sha256": JSON.stringify(envelope, "", true).sha256_text(), "mode": "observation"})


func accepted(result: Dictionary) -> Dictionary:
	return {"revision": _session.view().revision, "result": result, "error": null}


func rejected(code: String, message: String) -> Dictionary:
	return {"revision": _session.view().revision, "result": null, "error": {"code": code, "message": message}}


func _party(view: GameView) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for character: CharacterView in view.party_members:
		members.append({"id": character.id, "name": character.name, "raceId": character.race_id, "casteId": character.caste_id, "level": character.level, "health": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "gold": character.gold, "gems": character.gems, "jewelry": character.jewelry, "conditions": character.condition_values.duplicate()})
	return members


func _actions(view: GameView) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for key: Variant in view.action_availability:
		var action := view.availability(StringName(key))
		actions.append({"id": String(action.action_id), "enabled": action.enabled, "reason": action.reason})
	return actions
