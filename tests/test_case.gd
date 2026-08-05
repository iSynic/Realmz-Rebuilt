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
