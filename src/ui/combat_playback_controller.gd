class_name CombatPlaybackController
extends RefCounted

signal frame_changed(frame: CombatPlaybackFrame)
signal sound_requested(event: DomainEvent)
signal playback_finished

const SOUND_FRAME_SECONDS: float = 0.01
const CUE_SECONDS: float = 0.28
const MOVE_START_SECONDS: float = 0.12
const MOVE_END_SECONDS: float = 0.14
const ATTACK_SECONDS: float = 0.18
const PROJECTILE_SECONDS: float = 0.24
const SPELL_CAST_SECONDS: float = 0.24
const SPELL_EFFECT_SECONDS: float = 0.12
const RESULT_SECONDS: float = 0.40
const DEFEAT_SECONDS: float = 0.24
const AUTOMATIC_PLAYBACK_SCALE: float = 0.75

const PLAYBACK_EVENT_KINDS: Array[StringName] = [
	&"battle_started",
	&"battle_completed",
	&"combatant_moved",
	&"combat_attack_resolved",
	&"combat_projectile_resolved",
	&"combat_spell_cast",
	&"combat_spell_projectile",
	&"combat_spell_resolved",
	&"combat_turn_undead_resolved",
	&"combatant_bandaged",
	&"combatant_bleeding_progressed",
	&"combat_bleeding_warning",
	&"combatant_bled_to_death",
	&"combat_turn_delayed",
	&"combat_turn_undone",
	&"combatant_fumbled",
	&"combat_attack_blocked",
	&"combatant_retreated",
	&"sound_requested",
]

var previous_view: GameView
var final_view: GameView
var base_view: GameView

var _frames: Array[CombatPlaybackFrame] = []
var _frame_index: int = -1
var _elapsed_seconds: float = 0.0
var _frame_started: bool = false
var _active: bool = false
var _speed_percent: int = 100


func begin(previous: GameView, events: Array[DomainEvent], final: GameView, reduced_motion: bool) -> bool:
	reset()
	previous_view = previous
	final_view = final
	base_view = _choose_base_view(previous, final)
	if base_view == null or not _has_playback_event(events):
		return false
	if reduced_motion:
		for event: DomainEvent in events:
			if event.kind == &"sound_requested":
				var sound_frame := CombatPlaybackFrame.new(&"sound", SOUND_FRAME_SECONDS)
				sound_frame.sound_event = event
				_frames.append(sound_frame)
		_frames.append(CombatPlaybackFrame.new(&"settle", 0.0))
	else:
		var hidden_combatant_ids := _build_frames(events)
		_append_next_actor_cue(hidden_combatant_ids)
		_assign_camera_focus_ids()
	if _frames.is_empty():
		return false
	_active = true
	_frame_index = 0
	return true


func reset() -> void:
	_frames.clear()
	_frame_index = -1
	_elapsed_seconds = 0.0
	_frame_started = false
	_active = false
	previous_view = null
	final_view = null
	base_view = null


func is_active() -> bool:
	return _active


func current_frame() -> CombatPlaybackFrame:
	if not _active or _frame_index < 0 or _frame_index >= _frames.size():
		return null
	return _frames[_frame_index]


func frame_count() -> int:
	return _frames.size()


func set_speed_percent(value: int) -> void:
	_speed_percent = clampi(snappedi(value, 25), 25, 200)


func advance(delta_seconds: float, sound_is_blocking: bool = false) -> void:
	if not _active:
		return
	var frame := current_frame()
	if frame == null:
		_finish()
		return
	if sound_is_blocking and not _frame_started:
		return
	if not _frame_started:
		_frame_started = true
		frame.progress = 0.0
		frame_changed.emit(frame)
		if frame.sound_event != null:
			sound_requested.emit(frame.sound_event)
	if sound_is_blocking:
		return
	_elapsed_seconds += maxf(delta_seconds, 0.0)
	frame.progress = 1.0 if frame.duration_seconds <= 0.0 else clampf(_elapsed_seconds / frame.duration_seconds, 0.0, 1.0)
	frame_changed.emit(frame)
	if _elapsed_seconds < frame.duration_seconds:
		return
	_frame_index += 1
	_elapsed_seconds = 0.0
	_frame_started = false
	if _frame_index >= _frames.size():
		_finish()


func skip() -> bool:
	if not _active:
		return false
	var first_unplayed := _frame_index + 1 if _frame_started else _frame_index
	for index: int in range(maxi(first_unplayed, 0), _frames.size()):
		var frame := _frames[index]
		if frame.sound_event != null:
			sound_requested.emit(frame.sound_event)
	_finish()
	return true


func _finish() -> void:
	_active = false
	playback_finished.emit()


func _has_playback_event(events: Array[DomainEvent]) -> bool:
	for event: DomainEvent in events:
		if event.kind == &"sound_requested" and event.payload.get("source") == "classic-combat-auto-toggle":
			continue
		if event.kind in PLAYBACK_EVENT_KINDS:
			return true
	return false


func _choose_base_view(previous: GameView, final: GameView) -> GameView:
	if previous != null and previous.combat_view != null and previous.combat_view.battlefield != null:
		return previous
	if final != null and final.combat_view != null and final.combat_view.battlefield != null:
		return final
	return null


func _build_frames(events: Array[DomainEvent]) -> Array[String]:
	var positions := _positions_for(base_view)
	var hidden: Array[String] = []
	var accelerated_sequence := false
	var automatic_sequence := false
	for event: DomainEvent in events:
		if event.kind == &"combat_auto_started":
			accelerated_sequence = true
			automatic_sequence = true
			continue
		if event.kind == &"combat_auto_completed":
			accelerated_sequence = false
			automatic_sequence = false
			continue
		if event.kind == &"battle_started":
			accelerated_sequence = true
		var first_frame_index := _frames.size()
		match event.kind:
			&"sound_requested":
				var sound_frame := _new_frame(&"sound", SOUND_FRAME_SECONDS, positions, hidden)
				sound_frame.sound_event = event
				_frames.append(sound_frame)
			&"battle_started":
				var started := _new_frame(&"battle_cue", CUE_SECONDS, positions, hidden)
				started.display_text = "Battle begins"
				_frames.append(started)
			&"battle_completed":
				var completed := _new_frame(&"battle_cue", CUE_SECONDS, positions, hidden)
				completed.display_text = String(event.payload.get("outcome", "Battle complete")).replace("_", " ").capitalize()
				_frames.append(completed)
			&"combatant_moved":
				_append_movement(event, positions, hidden)
			&"combat_attack_resolved":
				_append_attack(event, positions, hidden)
			&"combat_projectile_resolved":
				_append_projectile(event, positions, hidden)
			&"combat_spell_cast":
				_append_spell_cast(event, positions, hidden)
			&"combat_spell_projectile":
				_append_spell_projectile(event, positions, hidden)
			&"combat_spell_resolved":
				_append_spell_result(event, positions, hidden)
			&"combat_turn_undead_resolved":
				_append_turn_undead_result(event, positions, hidden)
			&"combatant_bandaged":
				_append_simple_result(event, positions, hidden, &"healing", "Bandaged")
			&"combatant_bleeding_progressed":
				_append_bleeding_result(event, positions, hidden, false)
			&"combat_bleeding_warning":
				_append_simple_result(event, positions, hidden, &"bleeding", "Bleeding wounds remain")
			&"combatant_bled_to_death":
				_append_bleeding_result(event, positions, hidden, true)
			&"combat_turn_delayed":
				_append_simple_result(event, positions, hidden, &"delay", "Delayed")
			&"combat_turn_undone":
				_append_movement(event, positions, hidden)
			&"combatant_fumbled":
				_append_simple_result(event, positions, hidden, &"fumble", "Fumble")
			&"combat_attack_blocked":
				_append_simple_result(event, positions, hidden, &"blocked", "Blocked")
			&"combatant_retreated":
				var actor_id := String(event.payload.get("actorId", event.payload.get("characterId", "")))
				var retreat := _new_frame(&"retreat", RESULT_SECONDS, positions, hidden)
				retreat.actor_id = actor_id
				retreat.target_id = actor_id
				retreat.display_text = "Escaped"
				retreat.result_kind = &"retreat"
				_frames.append(retreat)
				if not actor_id.is_empty() and not hidden.has(actor_id):
					hidden.append(actor_id)
		var automatic_event := automatic_sequence or bool(event.payload.get("automatic", false))
		if accelerated_sequence or automatic_event:
			_accelerate_frames(first_frame_index, automatic_event)
	return hidden


func _accelerate_frames(first_frame_index: int, automatic: bool) -> void:
	for index: int in range(first_frame_index, _frames.size()):
		var frame := _frames[index]
		frame.automatic = automatic
		if frame.sound_event != null or frame.duration_seconds <= 0.0:
			continue
		frame.duration_seconds *= AUTOMATIC_PLAYBACK_SCALE


func _append_movement(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var actor_id := String(event.payload.get("actorId", ""))
	var from_coordinate := _payload_coordinate(event.payload.get("from"))
	var to_coordinate := _payload_coordinate(event.payload.get("to"))
	if from_coordinate.x < 0:
		from_coordinate = _position_for(actor_id, positions)
	var start := _new_frame(&"move_start", MOVE_START_SECONDS, positions, hidden)
	start.actor_id = actor_id
	start.from_coordinate = from_coordinate
	start.to_coordinate = to_coordinate
	_frames.append(start)
	if not actor_id.is_empty() and to_coordinate.x >= 0:
		positions[actor_id] = to_coordinate
	var arrived := _new_frame(&"move_end", MOVE_END_SECONDS, positions, hidden)
	arrived.actor_id = actor_id
	arrived.from_coordinate = from_coordinate
	arrived.to_coordinate = to_coordinate
	_frames.append(arrived)


func _append_attack(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var attack := _new_frame(&"melee_attack", ATTACK_SECONDS, positions, hidden)
	attack.actor_id = String(event.payload.get("actorId", ""))
	attack.target_id = String(event.payload.get("targetId", ""))
	attack.from_coordinate = _position_for(attack.actor_id, positions)
	attack.to_coordinate = _position_for(attack.target_id, positions)
	_frames.append(attack)
	_append_result(event, positions, hidden)


func _append_projectile(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var projectile := _new_frame(&"projectile", PROJECTILE_SECONDS, positions, hidden)
	projectile.actor_id = String(event.payload.get("actorId", ""))
	projectile.target_id = String(event.payload.get("targetId", ""))
	projectile.from_coordinate = _position_for(projectile.actor_id, positions)
	projectile.to_coordinate = _position_for(projectile.target_id, positions)
	_frames.append(projectile)
	_append_result(event, positions, hidden)


func _append_spell_cast(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var cast := _new_frame(&"spell_cast", SPELL_CAST_SECONDS, positions, hidden)
	cast.actor_id = String(event.payload.get("actorId", ""))
	cast.target_id = String(event.payload.get("targetId", ""))
	cast.from_coordinate = _position_for(cast.actor_id, positions)
	cast.to_coordinate = _payload_coordinate(event.payload.get("areaCenter"))
	if cast.to_coordinate.x < 0:
		cast.to_coordinate = _position_for(cast.target_id, positions)
	cast.effect_resource_id = int(event.payload.get("classicEffectResourceId", 0))
	cast.display_text = "Cast %s" % String(event.payload.get("spellName", event.payload.get("spellId", "spell")))
	_frames.append(cast)


func _append_spell_projectile(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var projectile := _new_frame(&"spell_projectile", PROJECTILE_SECONDS, positions, hidden)
	projectile.actor_id = String(event.payload.get("actorId", ""))
	projectile.target_id = String(event.payload.get("targetId", ""))
	projectile.from_coordinate = _position_for(projectile.actor_id, positions)
	projectile.to_coordinate = _position_for(projectile.target_id, positions)
	projectile.battle_tile_id = int(event.payload.get("classicBattleTileId", 0))
	_frames.append(projectile)


func _append_spell_result(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	_append_result(event, positions, hidden)
	if bool(event.payload.get("defeated", false)):
		return
	var effect_ids: Array = event.payload.get("classicResolutionEffectResourceIds", []) as Array
	for effect_value: Variant in effect_ids:
		var effect := _new_frame(&"spell_effect", SPELL_EFFECT_SECONDS, positions, hidden)
		effect.actor_id = String(event.payload.get("actorId", ""))
		effect.target_id = String(event.payload.get("targetId", ""))
		effect.to_coordinate = _payload_coordinate(event.payload.get("areaCenter"))
		if effect.to_coordinate.x < 0:
			effect.to_coordinate = _position_for(effect.target_id, positions)
		effect.effect_resource_id = int(effect_value)
		effect.display_text = String(event.payload.get("spellName", event.payload.get("spellId", "Spell effect")))
		_frames.append(effect)


func _append_turn_undead_result(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var result_kind := StringName(event.payload.get("result", "resisted"))
	var text := "Resist" if result_kind == &"resisted" else "Destroyed" if result_kind == &"destroyed" else "Turned"
	var target_id := String(event.payload.get("targetId", ""))
	if result_kind == &"destroyed":
		_hide_combatant(target_id, hidden)
	var result := _new_frame(&"result", RESULT_SECONDS, positions, hidden)
	result.actor_id = String(event.payload.get("actorId", ""))
	result.target_id = target_id
	result.result_kind = result_kind
	result.display_text = text
	_frames.append(result)
	if result_kind == &"turned":
		for _frame_index_value: int in int(event.payload.get("effectFrameCount", 0)):
			var effect := _new_frame(&"spell_effect", SPELL_EFFECT_SECONDS, positions, hidden)
			effect.actor_id = String(event.payload.get("actorId", ""))
			effect.target_id = String(event.payload.get("targetId", ""))
			effect.to_coordinate = _position_for(effect.target_id, positions)
			effect.effect_resource_id = int(event.payload.get("effectResourceId", 0)) + _frame_index_value
			_frames.append(effect)


func _append_bleeding_result(event: DomainEvent, positions: Dictionary, hidden: Array[String], defeated: bool) -> void:
	var target_id := String(event.payload.get("characterId", ""))
	if defeated:
		_hide_combatant(target_id, hidden)
	var frame := _new_frame(&"result", RESULT_SECONDS, positions, hidden)
	frame.target_id = target_id
	frame.result_kind = &"bleeding"
	frame.display_text = "Bled to death" if defeated else "Bleeding"
	_frames.append(frame)


func _append_simple_result(event: DomainEvent, positions: Dictionary, hidden: Array[String], result_kind: StringName, text: String) -> void:
	var frame := _new_frame(&"result", RESULT_SECONDS, positions, hidden)
	frame.actor_id = String(event.payload.get("actorId", ""))
	frame.target_id = String(event.payload.get("targetId", frame.actor_id))
	frame.result_kind = result_kind
	frame.display_text = text
	_frames.append(frame)


func _append_result(event: DomainEvent, positions: Dictionary, hidden: Array[String]) -> void:
	var target_id := String(event.payload.get("targetId", ""))
	var defeated := bool(event.payload.get("defeated", false))
	if defeated:
		_hide_combatant(target_id, hidden)
	var result := _new_frame(&"result", RESULT_SECONDS, positions, hidden)
	result.actor_id = String(event.payload.get("actorId", ""))
	result.target_id = target_id
	result.result_kind = _result_kind(event.payload)
	result.display_amount = int(event.payload.get("healing", event.payload.get("damage", 0)))
	result.display_text = _result_text(result.result_kind, result.display_amount)
	result.effect_resource_id = int(event.payload.get("classicResultEffectResourceId", 0))
	_frames.append(result)
	if defeated and not result.target_id.is_empty():
		var defeat := _new_frame(&"defeat", DEFEAT_SECONDS, positions, hidden)
		defeat.target_id = result.target_id
		defeat.result_kind = &"defeat"
		defeat.display_text = "Defeated"
		_frames.append(defeat)


static func _hide_combatant(combatant_id: String, hidden: Array[String]) -> void:
	if not combatant_id.is_empty() and not hidden.has(combatant_id):
		hidden.append(combatant_id)


func _append_next_actor_cue(hidden_combatant_ids: Array[String]) -> void:
	if final_view == null or final_view.combat_view == null or final_view.combat_view.outcome != &"active":
		return
	var prior_actor := previous_view.combat_view.active_actor_id if previous_view != null and previous_view.combat_view != null else ""
	var next_actor := final_view.combat_view.active_actor_id
	var prior_round := previous_view.combat_view.round_number if previous_view != null and previous_view.combat_view != null else -1
	if next_actor == prior_actor and final_view.combat_view.round_number == prior_round:
		return
	var positions := _positions_for(final_view)
	var cue := _new_frame(&"actor_cue", CUE_SECONDS, positions, hidden_combatant_ids)
	cue.actor_id = next_actor
	cue.target_id = next_actor
	cue.display_text = "Round %d" % final_view.combat_view.round_number if final_view.combat_view.round_number != prior_round else ""
	_frames.append(cue)


func _assign_camera_focus_ids() -> void:
	var latest_focus_id := ""
	for frame: CombatPlaybackFrame in _frames:
		var frame_focus_id := frame.actor_id if not frame.actor_id.is_empty() else frame.target_id
		if not frame_focus_id.is_empty():
			latest_focus_id = frame_focus_id
		frame.camera_focus_id = latest_focus_id
	var next_focus_id := ""
	for index: int in range(_frames.size() - 1, -1, -1):
		var frame := _frames[index]
		if not frame.camera_focus_id.is_empty():
			next_focus_id = frame.camera_focus_id
		elif not next_focus_id.is_empty():
			frame.camera_focus_id = next_focus_id


func _new_frame(kind: StringName, duration: float, positions: Dictionary, hidden: Array[String]) -> CombatPlaybackFrame:
	var frame := CombatPlaybackFrame.new(kind, duration * 100.0 / float(_speed_percent))
	frame.combatant_positions = positions.duplicate(true)
	frame.hidden_combatant_ids = hidden.duplicate()
	return frame


func _positions_for(view: GameView) -> Dictionary:
	var result: Dictionary = {}
	if view == null or view.combat_view == null or view.combat_view.battlefield == null:
		return result
	for character: CharacterView in view.party_members:
		var coordinate := view.combat_view.battlefield.character_position(character.id)
		if coordinate.x >= 0:
			result[character.id] = coordinate
	for monster: MonsterView in view.combat_view.monsters:
		var coordinate := view.combat_view.battlefield.monster_position(monster.id)
		if coordinate.x >= 0:
			result[monster.id] = coordinate
	return result


func _position_for(combatant_id: String, positions: Dictionary) -> Vector2i:
	var value: Variant = positions.get(combatant_id)
	if value is Vector2i:
		return value
	var coordinate := _view_position(previous_view, combatant_id)
	if coordinate.x >= 0:
		return coordinate
	return _view_position(final_view, combatant_id)


func _view_position(view: GameView, combatant_id: String) -> Vector2i:
	if view == null or view.combat_view == null:
		return Vector2i(-1, -1)
	return ClassicBattlefieldPresenter.actor_position(view.combat_view, view.party_members, combatant_id)


static func _payload_coordinate(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


static func _result_kind(payload: Dictionary) -> StringName:
	if bool(payload.get("fumble", false)):
		return &"fumble"
	if bool(payload.get("blocked", false)):
		return &"blocked"
	if bool(payload.get("immune", false)):
		return &"immune"
	if bool(payload.get("resisted", false)):
		return &"resisted"
	if bool(payload.get("saved", false)):
		return &"saved"
	if not bool(payload.get("hit", true)):
		return &"miss"
	if int(payload.get("healing", 0)) > 0:
		return &"healing"
	if int(payload.get("damage", 0)) > 0:
		return &"damage"
	if payload.has("appliedCondition") or payload.has("partyCondition"):
		return &"condition"
	if int(payload.get("clearedConditionCount", 0)) > 0 or payload.has("clearedCondition"):
		return &"condition_cleared"
	if int(payload.get("spellPointDelta", 0)) != 0:
		return &"spell_points"
	if bool(payload.get("allegianceChanged", false)) or payload.has("traitorAfter"):
		return &"allegiance"
	if payload.has("transformedDefinitionAfter"):
		return &"transformed"
	if not String(payload.get("specialResult", "")).is_empty():
		return StringName(payload.get("specialResult"))
	if int(payload.get("duration", 0)) > 0:
		return &"affected"
	return &"no_effect"


static func _result_text(result_kind: StringName, amount: int) -> String:
	match result_kind:
		&"miss":
			return "Miss"
		&"blocked":
			return "Blocked"
		&"immune":
			return "Immune"
		&"resisted":
			return "Resist"
		&"saved":
			return "Saved"
		&"fumble":
			return "Fumble"
		&"healing":
			return "+%d" % amount
		&"damage":
			return str(amount)
		&"condition":
			return "Condition applied"
		&"condition_cleared":
			return "Condition cleared"
		&"spell_points":
			return "Spell points changed"
		&"allegiance":
			return "Allegiance changed"
		&"transformed":
			return "Transformed"
		&"affected":
			return "Affected"
	return "No effect"
