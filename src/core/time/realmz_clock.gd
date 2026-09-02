class_name RealmzClock
extends RefCounted

const MINUTES_PER_DAY: int = 1_440

var _total_minutes: int = 0


func _init(initial_total_minutes: int = 0) -> void:
	_total_minutes = maxi(initial_total_minutes, 0)


func advance_minutes(minutes: int) -> bool:
	if minutes < 0:
		return false
	_total_minutes += minutes
	return true


func set_total_minutes(minutes: int) -> bool:
	if minutes < 0:
		return false
	_total_minutes = minutes
	return true


func total_minutes() -> int:
	return _total_minutes


func day() -> int:
	return 1 + floori(float(_total_minutes) / float(MINUTES_PER_DAY))


func hour() -> int:
	return floori(float(_total_minutes % MINUTES_PER_DAY) / 60.0)


func minute() -> int:
	return _total_minutes % 60


func to_data() -> Dictionary:
	return {"totalMinutes": _total_minutes}


static func from_data(data: Variant) -> RealmzClock:
	if not data is Dictionary or not data.has("totalMinutes"):
		return null
	var minutes: int = data["totalMinutes"] if data["totalMinutes"] is int else int(data["totalMinutes"]) if data["totalMinutes"] is float and is_equal_approx(data["totalMinutes"], round(data["totalMinutes"])) else -1
	if minutes < 0:
		return null
	return RealmzClock.new(minutes)
