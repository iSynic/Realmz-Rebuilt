class_name RealmzTestCase
extends RefCounted

var assertions: int = 0
var failures: Array[String] = []

const TEST_APPLICATION_LIBRARY_PATH := "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const TEST_APPLICATION_LIBRARY_ID := "realmz-classic-character-library"
const TEST_APPLICATION_LIBRARY_HASH := "c7e093f46bcca49d2382d68c2995ae5ff90c0e706dbd538682b613af9b80e0bd"


func test_package_repository() -> PackageRepository:
	var repository := PackageRepository.new(); var application_library := repository.load_bundled_package(TEST_APPLICATION_LIBRARY_PATH, TEST_APPLICATION_LIBRARY_ID, TEST_APPLICATION_LIBRARY_HASH)
	if application_library.is_ok():
		repository.set_application_content(application_library.content, application_library.media.assets())
	return repository


func load_test_package(path: String) -> PackageLoadResult:
	var repository := test_package_repository()
	var loaded := repository.load_package(path); assert_true(loaded.is_ok(), "shared test package loads through the application-plus-scenario catalog boundary: %s" % loaded.error_message); return loaded


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
