## Projects eligible committed target sequences into one disposable visual resolution.
class_name CombatPlaybackCondense
extends RefCounted


static func project(events: Array[DomainEvent]) -> Array[DomainEvent]:
	var projected: Array[DomainEvent] = []
	var index := 0
	while index < events.size():
		var event := events[index]
		if event.kind == &"combat_spell_cast":
			var spell_group := _spell_group(events, index)
			if not spell_group.is_empty():
				projected.append(event)
				projected.append_array(spell_group["events"])
				index = int(spell_group["nextIndex"])
				continue
		elif event.kind == &"combat_attack_resolved":
			var attack_group := _attack_group(events, index)
			if not attack_group.is_empty():
				projected.append_array(attack_group["events"])
				index = int(attack_group["nextIndex"])
				continue
		projected.append(event)
		index += 1
	return projected


static func _spell_group(events: Array[DomainEvent], cast_index: int) -> Dictionary:
	var cast := events[cast_index]
	var actor_id := String(cast.payload.get("actorId", ""))
	var spell_id := String(cast.payload.get("spellId", ""))
	if actor_id.is_empty() or spell_id.is_empty(): return {}
	var results: Array[Dictionary] = []
	var distinct_targets := {}
	var first_sound: DomainEvent
	var count := -1
	var index := cast_index + 1
	while index < events.size():
		var event := events[index]
		if event.kind == &"sound_requested":
			if String(event.payload.get("source", "")) not in ["classic-combat-spell-result", "classic-monster-spell-result", "classic-monster-macro"]:
				break
			if first_sound == null: first_sound = event
		elif event.kind == &"combat_spell_projectile":
			if String(event.payload.get("actorId", "")) != actor_id or String(event.payload.get("spellId", "")) != spell_id:
				break
		elif event.kind == &"combat_spell_resolved":
			var payload := event.payload
			if String(payload.get("actorId", "")) != actor_id or String(payload.get("spellId", "")) != spell_id:
				break
			var sequence_count := int(payload.get("castSequenceCount", 0))
			if sequence_count < 2 or (count >= 0 and sequence_count != count) or int(payload.get("castSequenceIndex", -1)) != results.size():
				break
			count = sequence_count
			results.append(payload.duplicate(true))
			distinct_targets[String(payload.get("targetId", ""))] = true
			if results.size() == count:
				if distinct_targets.size() < 2: break
				var condensed: Array[DomainEvent] = []
				if first_sound != null: condensed.append(first_sound)
				condensed.append(DomainEvent.new(&"combat_multi_spell_resolved", {"actorId": actor_id, "results": results}))
				return {"events": condensed, "nextIndex": index + 1}
		else:
			break
		index += 1
	return {}


static func _attack_group(events: Array[DomainEvent], first_index: int) -> Dictionary:
	var first := events[first_index]
	if int(first.payload.get("attackIndex", -1)) != 0 or bool(first.payload.get("reaction", false)):
		return {}
	var actor_id := String(first.payload.get("actorId", ""))
	var action := String(first.payload.get("action", ""))
	if actor_id.is_empty() or String(first.payload.get("targetId", "")).is_empty(): return {}
	var results: Array[Dictionary] = [first.payload.duplicate(true)]
	var distinct_targets := {String(first.payload.get("targetId", "")): true}
	var sounds: Array[DomainEvent] = []
	var sound_ids := {}
	var pending_sounds: Array[DomainEvent] = []
	var index := first_index + 1
	var last_result_end := index
	while index < events.size():
		var event := events[index]
		if event.kind == &"sound_requested":
			if String(event.payload.get("source", "")) != "classic-combat-attack":
				break
			pending_sounds.append(event)
		elif event.kind == &"combat_attack_resolved":
			var payload := event.payload
			if String(payload.get("actorId", "")) != actor_id or String(payload.get("action", "")) != action or int(payload.get("attackIndex", -1)) != results.size() or bool(payload.get("reaction", false)):
				break
			for sound: DomainEvent in pending_sounds:
				var sound_id := int(sound.payload.get("soundId", 0))
				if not sound_ids.has(sound_id):
					sounds.append(sound)
					sound_ids[sound_id] = true
			pending_sounds.clear()
			results.append(payload.duplicate(true))
			distinct_targets[String(payload.get("targetId", ""))] = true
			last_result_end = index + 1
		else:
			break
		index += 1
	if results.size() < 2 or distinct_targets.size() < 2:
		return {}
	var condensed: Array[DomainEvent] = sounds
	condensed.append(DomainEvent.new(&"combat_multi_attack_resolved", {"actorId": actor_id, "results": results}))
	return {"events": condensed, "nextIndex": last_result_end}
