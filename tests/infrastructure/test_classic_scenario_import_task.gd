extends RealmzTestCase

const TaskScript := preload("res://src/storage/packages/classic_scenario_import_task.gd")
const TestFiles := preload("res://tests/infrastructure/imported_scenario_test_files.gd")
const TEST_ROOT: String = "user://test-classic-scenario-import-task"


class FakeProcessDriver extends TaskScript.ProcessDriver:
	var running: bool = false
	var started: bool = false
	var killed: bool = false
	var request: Dictionary = {}

	func start_process(_executable: String, arguments: PackedStringArray) -> int:
		started = true
		request = JSON.parse_string(FileAccess.get_file_as_string(arguments[1]))
		running = true
		return 84721

	func is_process_running(process_id: int) -> bool:
		return process_id == 84721 and running

	func kill_process(process_id: int) -> Error:
		killed = process_id == 84721
		return OK


func run() -> void:
	_test_request_identity_and_owned_cancellation()
	TestFiles.remove_tree(TEST_ROOT)


func _test_request_identity_and_owned_cancellation() -> void:
	TestFiles.remove_tree(TEST_ROOT)
	var importer_root := ProjectSettings.globalize_path(TEST_ROOT.path_join("importer"))
	var support_root := importer_root.path_join("support")
	DirAccess.make_dir_recursive_absolute(support_root)
	var executable_path := importer_root.path_join("providence-native-adapter.exe" if OS.get_name() == "Windows" else "providence-native-adapter")
	TestFiles.write_bytes(executable_path, PackedByteArray([1, 2, 3]))
	TestFiles.write_bytes(support_root.path_join("support.bin"), PackedByteArray([4, 5, 6]))
	var manifest := {
		"formatVersion": 1,
		"executable": {"path": executable_path.get_file(), "sha256": FileAccess.get_sha256(executable_path)},
		"supportFiles": [{"path": "support.bin", "sha256": FileAccess.get_sha256(support_root.path_join("support.bin"))}],
	}
	TestFiles.write_text(importer_root.path_join("build-manifest.json"), JSON.stringify(manifest))
	var jobs := ProjectSettings.globalize_path(TEST_ROOT.path_join("jobs"))
	var driver := FakeProcessDriver.new()
	var task: RefCounted = TaskScript.new(driver)
	assert_false(task.start("user://source", jobs, importer_root, "nested/STARTUP.SCN"), "a selected startup cannot escape the source folder")
	assert_true(task.start("user://source", jobs, importer_root, "STARTUP.SCN"), "a valid selected basename starts the owned import worker")
	_wait_until_started(task, driver)
	assert_true(driver.started, "the verified bundle starts the converter through the owned process boundary")
	if not driver.started:
		task.close()
		TestFiles.remove_tree(TEST_ROOT)
		return
	assert_equal(driver.request.get("applicationLibraryIdentity"), {"campaignId": ApplicationLibraryIdentity.CAMPAIGN_ID, "packageHash": ApplicationLibraryIdentity.PACKAGE_HASH}, "the request pins the exact application package identity")
	assert_equal(driver.request.get("startupFile"), "STARTUP.SCN", "the request forwards only the selected startup basename")
	var events_path: String = str(driver.request.get("outputDirectory", "")).path_join("events.jsonl")
	DirAccess.make_dir_recursive_absolute(events_path.get_base_dir())
	TestFiles.write_text(events_path, "not-json\n" + JSON.stringify({"formatVersion": 1, "event": "startup_selection", "data": {"candidates": ["A.SCN", "B.SCN", "../unsafe.SCN"]}}) + "\n")
	task.poll()
	assert_equal(task.startup_candidates, ["A.SCN", "B.SCN"], "ambiguous startup candidates expose safe basenames for the retry UI")
	var job_path: String = str(driver.request.get("outputDirectory", "")).get_base_dir()
	task.cancel()
	assert_true(driver.killed and task.state == &"cancelled", "cancellation requests termination and publishes a cancelled state")
	task.poll()
	assert_true(DirAccess.dir_exists_absolute(job_path), "staging remains owned while the killed converter may still be using it")
	driver.running = false
	task.poll()
	assert_false(DirAccess.dir_exists_absolute(job_path), "staging is removed after the converter is confirmed stopped")
	task.close()
	var report_driver := FakeProcessDriver.new()
	task = TaskScript.new(report_driver)
	assert_true(task.start("user://source", jobs, importer_root), "a later conversion can reuse the verified bundle after cancellation cleanup")
	_wait_until_started(task, report_driver)
	var report_events := str(report_driver.request.get("outputDirectory", "")).path_join("events.jsonl")
	var source_report := {"formatVersion": 1, "sourceName": "source", "unsupportedInstructions": [{"message": "Unknown opcode 30000"}]}
	TestFiles.write_text(report_events, JSON.stringify({"formatVersion": 1, "event": "diagnostics", "data": source_report}) + "\n")
	task.poll()
	var built_package := str(report_driver.request.get("outputDirectory", "")).path_join("built.realmz2")
	TestFiles.write_bytes(built_package, PackedByteArray([11, 12, 13]))
	var completed_report := {"packagePath": built_package, "campaignId": "source-campaign", "packageHash": "a".repeat(64), "warningCount": 1, "warnings": ["Deferred reference"]}
	TestFiles.write_text(report_events, FileAccess.get_file_as_string(report_events) + JSON.stringify({"formatVersion": 1, "event": "complete", "data": completed_report}) + "\n")
	report_driver.running = false
	task.poll()
	assert_equal(task.state, &"succeeded", "the task accepts completion only after the package path exists")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(task.report_path))
	assert_true(report is Dictionary and report.get("sourceName") == "source" and report.get("packageHash") == "a".repeat(64) and report.get("unsupportedInstructions", []).size() == 1, "the final compatibility report keeps initial inventory and gains exact installed revision identity")
	task.close()
	TestFiles.write_text(importer_root.path_join("build-manifest.json"), "not-json")
	driver = FakeProcessDriver.new()
	task = TaskScript.new(driver)
	assert_true(task.start("user://source", jobs, importer_root), "an executable with a malformed manifest enters asynchronous bundle verification")
	var deadline := Time.get_ticks_msec() + 10000
	while task.state == &"running" and Time.get_ticks_msec() < deadline:
		task.poll()
		OS.delay_msec(2)
	assert_equal(task.state, &"failed", "a malformed importer manifest fails before any converter process starts")
	assert_contains(task.message, "build manifest is missing or invalid", "the bundle-integrity failure explains the required repair")
	assert_false(driver.started, "an invalid importer bundle never starts a process")
	task.close()


func _wait_until_started(task: RefCounted, driver: FakeProcessDriver) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not driver.started and Time.get_ticks_msec() < deadline:
		task.poll()
		OS.delay_msec(2)
	task.poll()
