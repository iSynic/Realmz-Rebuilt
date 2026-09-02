class_name RealmzTestCase
extends RefCounted

var assertions: int = 0
var failures: Array[String] = []


func save_data(snapshot: SessionSnapshot) -> Dictionary:
	var envelope := SaveEnvelope.from_snapshot(snapshot)
	return {} if envelope == null else envelope.to_data()


func save_round_trip(snapshot: SessionSnapshot) -> SaveEnvelope:
	return SaveEnvelope.from_data(save_data(snapshot))


func continuation_data(snapshot: SessionSnapshot) -> Dictionary:
	if snapshot == null or snapshot.continuation == null:
		return {}
	var wire := snapshot.continuation.to_data()
	var payload: Dictionary = wire["data"].duplicate(true)
	payload["kind"] = wire["kind"]
	return payload


func selected_case_arguments() -> Array:
	return []


func assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)


func assert_not_null(value: Variant, message: String) -> void:
	assertions += 1
	if value == null:
		failures.append(message)


func assert_contains(text: String, expected_fragment: String, message: String) -> void:
	assertions += 1
	if not text.contains(expected_fragment):
		failures.append("%s (expected '%s' in '%s')" % [message, expected_fragment, text])
