## Defines the pure gameplay Realmz clock contract.

class_name RealmzClock
extends RefCounted

const MINUTES_PER_DAY: int = 1_440
const MIN_COMPONENT: int = -2_147_483_648
const MAX_COMPONENT: int = 2_147_483_647
const HOUR_ADVANCED: int = 1
const MIDNIGHT: int = 2

var _day: int = 1
var _hour: int = 0
var _minute: int = 0


func _init(initial_total_minutes: int = 0) -> void:
	set_total_minutes(maxi(initial_total_minutes, 0))


func advance_minutes(minutes: int) -> bool:
	if minutes < 0 or minutes > MAX_COMPONENT:
		return false
	if minutes == 0:
		return true
	var minute_sum := _minute + minutes
	var carry := int(floor(float(minute_sum) / 60.0)) if minute_sum >= 60 else 0
	var hour_sum := _hour + carry
	var days := int(floor(float(hour_sum) / 24.0)) if hour_sum >= 24 else 0
	return set_components(_day + days, hour_sum - days * 24, minute_sum - carry * 60)


func set_total_minutes(minutes: int) -> bool:
	if minutes < 0:
		return false
	return set_components(1 + int(minutes / MINUTES_PER_DAY), int((minutes % MINUTES_PER_DAY) / 60), minutes % 60)


func set_components(day_value: int, hour_value: int, minute_value: int) -> bool:
	if not valid_component(day_value) or not valid_component(hour_value) or not valid_component(minute_value):
		return false
	_day = day_value
	_hour = hour_value
	_minute = minute_value
	return true


func alter_classic(mode: int, days: int, hours: int, minutes: int) -> int:
	var next_day := _day
	var next_hour := _hour
	var next_minute := _minute
	if mode == 1:
		if days != -1: next_day = days
		if hours != -1: next_hour = hours
		if minutes != -1: next_minute = minutes
	elif mode == 2:
		next_day += days
		next_hour += hours
		if not valid_component(next_day) or not valid_component(next_hour): return -1
		# newland.c: opcode 63 carries hours once, before adding minutes.
		if next_hour > 23:
			next_day += 1
			next_hour -= 24
		next_minute += minutes
		if not valid_component(next_minute): return -1
		if next_minute > 59:
			next_hour += 1
			next_minute -= 60
	# timeclick(0,0) jumps past minute carry and hourly recovery.
	var flags := 0
	if next_hour == 24:
		next_day += 1
		next_hour -= 24
		flags = MIDNIGHT
	return flags if set_components(next_day, next_hour, next_minute) else -1


func advance_classic_click(minutes: int) -> int:
	var next_day := _day
	var next_hour := _hour
	var next_minute := _minute + minutes
	if not valid_component(next_minute): return -1
	var flags := 0
	if next_minute >= 60:
		next_minute -= 60
		next_hour += 1
		flags = HOUR_ADVANCED
		if next_hour == 24:
			next_day += 1
			next_hour -= 24
			flags |= MIDNIGHT
	return flags if minutes in [1, 5] and set_components(next_day, next_hour, next_minute) else -1


func total_minutes() -> int:
	# A duration measure for callers, never the authoritative representation.
	return (_day - 1) * MINUTES_PER_DAY + _hour * 60 + _minute


func day() -> int:
	return _day


func hour() -> int:
	return _hour


func minute() -> int:
	return _minute


func to_data() -> Dictionary:
	return {"day": _day, "hour": _hour, "minute": _minute}


static func from_data(data: Variant) -> RealmzClock:
	if not data is Dictionary:
		return null
	var result := RealmzClock.new()
	if data.size() == 1 and data.has("totalMinutes"):
		var value: Variant = data["totalMinutes"]
		if not _integer(value) or value < 0:
			return null
		return result if result.set_total_minutes(int(value)) else null
	if data.size() != 3:
		return null
	for field: String in ["day", "hour", "minute"]:
		if not data.has(field) or not _integer(data[field]) or not valid_component(int(data[field])):
			return null
	return result if result.set_components(int(data["day"]), int(data["hour"]), int(data["minute"])) else null


static func valid_component(value: int) -> bool:
	return value >= MIN_COMPONENT and value <= MAX_COMPONENT


static func _integer(value: Variant) -> bool:
	return value is int or value is float and is_finite(value) and value == floor(value) and absf(value) <= 9_007_199_254_740_991.0
