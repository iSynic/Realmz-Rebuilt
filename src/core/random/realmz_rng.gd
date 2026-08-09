class_name RealmzRng
extends RefCounted

const MULTIPLIER: int = 16_807
const MODULUS: int = 2_147_483_647
const RAW_SCALE: int = 32_768

var _state: int
var _draw_count: int = 0
var _trace: Array[Dictionary] = []


func _init(initial_seed: int = 1) -> void:
	_state = _normalize_seed(initial_seed)


func draw(range_max: int, semantic_tag: StringName) -> int:
	if range_max <= 0 or range_max > 32_767:
		push_error("RealmzRng range must be between 1 and 32767.")
		return 0
	return _draw_scaled(range_max, semantic_tag)


func draw_classic(range_value: int, semantic_tag: StringName) -> int:
	if range_value < -32_768 or range_value > 32_767:
		push_error("Castle Rand range must fit a signed 16-bit value.")
		return 0
	return _draw_scaled(range_value, semantic_tag)


func _draw_scaled(range_value: int, semantic_tag: StringName) -> int:
	var raw: int = _next_raw()
	var positive_raw: int = -raw if raw < 0 else raw
	# C integer division truncates toward zero for Castle's signed Rand parameter.
	var result: int = 1 + int(float(positive_raw * range_value) / float(RAW_SCALE))
	_trace.append({
		"drawIndex": _draw_count,
		"tag": String(semantic_tag),
		"range": range_value,
		"raw": raw,
		"result": result,
	})
	_draw_count += 1
	return result


func draw_between(low: int, high: int, semantic_tag: StringName) -> int:
	if high < low or high - low + 1 > 32_767:
		push_error("RealmzRng inclusive range is invalid.")
		return low
	var result := draw(high - low + 1, semantic_tag) - 1 + low
	_trace[-1]["low"] = low
	_trace[-1]["high"] = high
	_trace[-1]["result"] = result
	return result


func snapshot() -> RealmzRngState:
	return RealmzRngState.new(_state, _draw_count)


func restore(state: RealmzRngState) -> bool:
	if state == null or state.generator_state <= 0 or state.generator_state >= MODULUS or state.draw_count < 0:
		return false
	_state = state.generator_state
	_draw_count = state.draw_count
	_trace.clear()
	return true


func trace() -> Array[Dictionary]:
	return _trace.duplicate(true)


func _next_raw() -> int:
	_state = (_state * MULTIPLIER) % MODULUS
	var low_word: int = _state & 0xffff
	if low_word == 0x8000:
		return 0
	if low_word >= 0x8000:
		return low_word - 0x10000
	return low_word


static func _normalize_seed(initial_seed: int) -> int:
	var normalized: int = initial_seed % MODULUS
	if normalized < 0:
		normalized += MODULUS
	return 1 if normalized == 0 else normalized
