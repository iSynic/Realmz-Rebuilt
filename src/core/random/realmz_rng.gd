class_name RealmzRng
extends RefCounted

const MULTIPLIER: int = 16_807
const MODULUS: int = 2_147_483_647
const RAW_SCALE: int = 32_768
const DEFAULT_TRACE_LIMIT: int = 4_096
const UNLIMITED_TRACE: int = -1

var _state: int
var _draw_count: int = 0
var _trace: Array[Dictionary] = []
var _trace_limit: int
var _trace_start: int = 0


func _init(initial_seed: int = 1, trace_limit: int = DEFAULT_TRACE_LIMIT) -> void:
	_state = _normalize_seed(initial_seed)
	_trace_limit = trace_limit if trace_limit >= 0 else UNLIMITED_TRACE


static func for_oracle(initial_seed: int = 1) -> RealmzRng:
	return RealmzRng.new(initial_seed, UNLIMITED_TRACE)


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
	_append_trace({
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
	_annotate_between_trace(low, high, result)
	return result


func draw_between_classic(low: int, high: int, semantic_tag: StringName) -> int:
	var result := draw_classic(classic_range_width(low, high), semantic_tag) - 1 + low
	_annotate_between_trace(low, high, result)
	return result


static func classic_range_width(low: int, high: int) -> int:
	return ((high - low + 1 + 32_768) & 0xffff) - 32_768


static func classic_between_bounds(low: int, high: int) -> Vector2i:
	var range_width := classic_range_width(low, high)
	if range_width > 0:
		return Vector2i(low, low + range_width - 1)
	if range_width == 0:
		return Vector2i(low, low)
	return Vector2i(low + range_width + 1, low)


func _annotate_between_trace(low: int, high: int, result: int) -> void:
	var latest := _latest_trace_entry()
	if not latest.is_empty():
		latest["low"] = low
		latest["high"] = high
		latest["result"] = result


func snapshot() -> RealmzRngState:
	return RealmzRngState.new(_state, _draw_count)


func checkpoint() -> Dictionary:
	return {
		"generatorState": _state,
		"drawCount": _draw_count,
		"trace": trace(),
		"sourcePosition": _source_position(),
	}


func rollback(checkpoint_data: Dictionary) -> bool:
	if not checkpoint_data.has("generatorState") or not checkpoint_data.has("drawCount") or not checkpoint_data.has("trace") or not checkpoint_data.has("sourcePosition"):
		return false
	var generator_state := int(checkpoint_data["generatorState"])
	var draw_count := int(checkpoint_data["drawCount"])
	var trace_value: Variant = checkpoint_data["trace"]
	if generator_state <= 0 or generator_state >= MODULUS or draw_count < 0 or not trace_value is Array or (_trace_limit >= 0 and trace_value.size() > _trace_limit):
		return false
	var restored_trace: Array[Dictionary] = []
	for entry: Variant in trace_value:
		if not entry is Dictionary:
			return false
		restored_trace.append((entry as Dictionary).duplicate(true))
	if not _restore_source_position(checkpoint_data["sourcePosition"]):
		return false
	_state = generator_state
	_draw_count = draw_count
	_trace = restored_trace
	_trace_start = 0
	return true


func restore(state: RealmzRngState) -> bool:
	if state == null or state.generator_state <= 0 or state.generator_state >= MODULUS or state.draw_count < 0:
		return false
	_state = state.generator_state
	_draw_count = state.draw_count
	_trace.clear()
	_trace_start = 0
	return true


func trace() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for offset: int in _trace.size():
		ordered.append(_trace[(_trace_start + offset) % _trace.size()].duplicate(true))
	return ordered


func trace_limit() -> int:
	return _trace_limit


func _append_trace(entry: Dictionary) -> void:
	if _trace_limit == 0:
		return
	if _trace_limit < 0 or _trace.size() < _trace_limit:
		_trace.append(entry)
		return
	_trace[_trace_start] = entry
	_trace_start = (_trace_start + 1) % _trace_limit


func _latest_trace_entry() -> Dictionary:
	if _trace.is_empty():
		return {}
	var index := (_trace_start + _trace.size() - 1) % _trace.size()
	return _trace[index]


func _next_raw() -> int:
	_state = (_state * MULTIPLIER) % MODULUS
	var low_word: int = _state & 0xffff
	if low_word == 0x8000:
		return 0
	if low_word >= 0x8000:
		return low_word - 0x10000
	return low_word


func _source_position() -> Variant:
	return null


func _restore_source_position(value: Variant) -> bool:
	return value == null


static func _normalize_seed(initial_seed: int) -> int:
	var normalized: int = initial_seed % MODULUS
	if normalized < 0:
		normalized += MODULUS
	return 1 if normalized == 0 else normalized
