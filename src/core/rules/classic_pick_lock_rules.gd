class_name ClassicPickLockRules
extends RefCounted

const MAX_TUMBLERS: int = 6
const TRACK_END: int = 208
const JUMP_RANGE: int = 20
const ADVANCE_PERCENT: int = 55
const FRAME_RATE: int = 30
const THIEF_ABILITY_START: int = 5
const ACTION_LABELS: Array[String] = ["Acrobatics", "Detect Trap", "Disarm Trap", "Hear Noise", "Force Lock", "Move Silently", "Pick Lock", "Pick Pocket"]


static func ability_index(action_index: int) -> int:
	return THIEF_ABILITY_START + action_index if action_index >= 0 and action_index < 8 else -1


static func action_label(action_index: int) -> String:
	return ACTION_LABELS[action_index] if action_index >= 0 and action_index < ACTION_LABELS.size() else ""


static func chance(ability: int, modifier: int) -> int:
	# Castle caps only the upper bound. The encounter button is available only
	# when the authored ability plus modifier is positive.
	return mini(ability + modifier, 90)


static func preview(rng_state: RealmzRngState, authored_tumblers: int, chance_percent: int) -> Array[Array]:
	if rng_state == null or chance_percent <= 0:
		return []
	var preview_rng := RealmzRng.new()
	if not preview_rng.restore(rng_state):
		return []
	return _frames(preview_rng, authored_tumblers, chance_percent, maximum_iterations(authored_tumblers), true)


static func resolve(rng: RealmzRng, authored_tumblers: int, chance_percent: int, frame_index: int) -> Dictionary:
	var limit := maximum_iterations(authored_tumblers)
	if rng == null or chance_percent <= 0 or frame_index < 0 or frame_index > limit:
		return {}
	var frames := _frames(rng, authored_tumblers, chance_percent, frame_index, false)
	if frames.is_empty():
		return {}
	var positions: Array = frames[frames.size() - 1]
	var succeeded := true
	for position: Variant in positions:
		if int(position) < yellow_threshold(chance_percent):
			succeeded = false
			break
	return {"positions": positions.duplicate(), "succeeded": succeeded, "frameIndex": frame_index}


static func maximum_iterations(authored_tumblers: int) -> int:
	# picklock() advances every two Classic ticks and exits when its integer
	# countdown reaches zero. The final source second has no tumbler update.
	return 60 * (tumbler_count(authored_tumblers) + 1)


static func time_limit_frames(authored_tumblers: int) -> int:
	# Castle's limit is 180 + 120 ticks per tumbler. At two ticks per update,
	# this is 3 + 2 * tumblers seconds at the 30 Hz presentation cadence.
	return maximum_iterations(authored_tumblers) + FRAME_RATE


static func tumbler_count(authored_tumblers: int) -> int:
	return clampi(authored_tumblers, 0, MAX_TUMBLERS)


static func yellow_threshold(chance_percent: int) -> int:
	return 200 - 2 * chance_percent


static func green_threshold(chance_percent: int) -> int:
	return 200 - chance_percent


static func _frames(rng: RealmzRng, authored_tumblers: int, chance_percent: int, iterations: int, preview_mode: bool) -> Array[Array]:
	var count := tumbler_count(authored_tumblers)
	var yellow := yellow_threshold(chance_percent)
	var green := green_threshold(chance_percent)
	var positions: Array[int] = []
	for _index: int in count:
		positions.append(8 + int(yellow / 2.0))
	var result: Array[Array] = [positions.duplicate()]
	for _iteration: int in iterations:
		for tumbler_index: int in count:
			if positions[tumbler_index] >= green:
				continue
			var suffix := &"preview" if preview_mode else &"resolve"
			var delta := rng.draw(JUMP_RANGE, StringName("classic.pick-lock.delta.%s" % suffix))
			var advances := rng.draw(100, StringName("classic.pick-lock.direction.%s" % suffix)) <= ADVANCE_PERCENT
			positions[tumbler_index] = clampi(positions[tumbler_index] + (delta if advances else -delta), 10, TRACK_END)
		result.append(positions.duplicate())
	return result
