## A brief coloured glow around the window edge when the party comes to harm: stamina lost,
## or poison or disease taking hold. It is a cue only: it never takes input, it can be
## switched off, and under reduced motion it holds faintly and ends without fading.

class_name ScreenEdgeFlash
extends Control

const SECONDS := 0.9
const DEPTH := 0.1
const PEAK := 0.6
const STILL_PEAK := 0.3
const POISON_COLOR := Color(0.36, 0.78, 0.3)
const DISEASE_COLOR := Color(0.74, 0.62, 0.2)

var reduced_motion := false
var _color := Color.TRANSPARENT
var _strength := 0.0:
	set(value):
		_strength = value
		queue_redraw()
var _tween: Tween
## The stamina each member was last seen with, so a loss is shown once: as combat playback
## reaches it, not again when the settled view arrives.
var _seen_health: Dictionary = {}


## The harm between two views of the same adventure: `&"harm"` for stamina lost to a blow or
## a hazard, `&"poison"` or `&"disease"` when that condition starts or costs stamina outside
## a fight, and an empty name when nothing bad happened. A plain loss outranks the others.
## `seen` holds stamina already shown for a member, in place of the previous view's figure.
static func cause(previous: GameView, current: GameView, seen: Dictionary = {}) -> StringName:
	if previous == null or current == null or not previous.session_started or previous.campaign_id != current.campaign_id:
		return &""
	var fighting := current.combat_view != null
	var found := &""
	for index: int in mini(previous.party_members.size(), current.party_members.size()):
		var before := previous.party_members[index]
		var after := current.party_members[index]
		if before.id != after.id:
			return &""
		var lost := after.current_health < RowFields.number(seen, after.id, before.current_health)
		for condition: int in [ConditionRules.DISEASED, ConditionRules.POISONED]:
			var cue: StringName = &"disease" if condition == ConditionRules.DISEASED else &"poison"
			var now := _has(after.condition_values, condition)
			if now and (not _has(before.condition_values, condition) or lost and not fighting):
				found = cue if found != &"harm" else found
				lost = lost and fighting
		if lost:
			found = &"harm"
	return found


## Pulses for whatever `cause` finds between the two views, when `settings` allows it.
func observe(previous: GameView, current: GameView, settings: PresentationSettings) -> void:
	var found := cause(previous, current, _seen_health)
	_seen_health.clear()
	if current != null:
		for member: CharacterView in current.party_members:
			_seen_health[member.id] = member.current_health
	reduced_motion = settings.reduced_motion
	if settings.harm_edge_flash and found != &"":
		pulse(_color_for(found))


## Pulses as a combat playback `frame` shows a member of `view`'s party losing stamina, so
## the glow lands with the blow and not when the turn settles.
func observe_frame(frame: CombatPlaybackFrame, view: GameView, settings: PresentationSettings) -> void:
	var found := &""
	for member: CharacterView in view.party_members:
		if not frame.combatant_health.has(member.id):
			continue
		var health := RowFields.number(frame.combatant_health, member.id)
		if health < RowFields.number(_seen_health, member.id, member.current_health):
			# A condition's own result frame names it; anything else is a blow.
			var condition := frame.result_kind == &"condition_damage" and frame.target_id == member.id
			found = &"harm" if not condition or found == &"harm" else &"poison" if frame.display_text.begins_with("Poison") else &"disease"
		_seen_health[member.id] = health
	reduced_motion = settings.reduced_motion
	if settings.harm_edge_flash and found != &"":
		pulse(_color_for(found))


## Shows the glow in `color` and lets it fade.
func pulse(color: Color) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_color = color
	_strength = STILL_PEAK if reduced_motion else PEAK
	_tween = create_tween()
	if reduced_motion:
		_tween.tween_interval(SECONDS)
		_tween.tween_property(self, "_strength", 0.0, 0.0)
	else:
		_tween.tween_property(self, "_strength", 0.0, SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## How strongly the glow shows now, from 0 to its peak.
func strength() -> float:
	return _strength


static func _color_for(found: StringName) -> Color:
	return POISON_COLOR if found == &"poison" else DISEASE_COLOR if found == &"disease" else UiThemeService.current().colors[&"bad"]


static func _has(values: Array[int], index: int) -> bool:
	return index < values.size() and values[index] != 0


func _draw() -> void:
	if _strength <= 0.0:
		return
	var depth := minf(size.x, size.y) * DEPTH
	var lit := Color(_color, _strength)
	var clear := Color(_color, 0.0)
	var outer := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	var inner := PackedVector2Array([Vector2(depth, depth), Vector2(size.x - depth, depth), size - Vector2(depth, depth), Vector2(depth, size.y - depth)])
	for side: int in 4:
		var next := (side + 1) % 4
		draw_polygon(PackedVector2Array([outer[side], outer[next], inner[next], inner[side]]), PackedColorArray([lit, lit, clear, clear]))
