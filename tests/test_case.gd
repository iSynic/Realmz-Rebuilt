class_name RealmzTestCase
extends RefCounted

var assertions: int = 0
var failures: Array[String] = []


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
