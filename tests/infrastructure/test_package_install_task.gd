extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TAMPERED_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-tampered.realmz2"
const TEST_ROOT: String = "user://test-package-task"
const PackageInstallTaskScript := preload("res://src/infrastructure/packages/package_install_task.gd")
const PackageOperationStatusScript := preload("res://src/infrastructure/packages/package_operation_status.gd")

const TERMINAL_WAIT_MILLISECONDS: int = 20_000
const POLL_DELAY_MILLISECONDS: int = 2


func selected_case_arguments() -> Array:
	var package := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package.is_ok(), "the package-task success fixture passes independent package validation")
	if not package.is_ok():
		return []
	return [package.content.campaign_id, package.content.package_hash]


func run() -> void:
	var package := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package.is_ok(), "the package-task success fixture passes independent package validation")
	if not package.is_ok():
		return
	var campaign_id: String = package.content.campaign_id
	var package_hash: String = package.content.package_hash

	_test_successful_task(campaign_id, package_hash)
	_test_tampered_task(campaign_id, package_hash)
	_test_cancel_before_start(campaign_id, package_hash)
	_test_shutdown_joins_worker()
	_cleanup_test_root()


func _test_successful_task(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root()
	var task_repository := PackageRepository.new()
	var task: RefCounted = PackageInstallTaskScript.new(task_repository)
	assert_true(task.start(FIXTURE_PATH, TEST_ROOT), "a package install task starts from the positive fixture")
	var observed_phases: Array[StringName] = []
	var terminal := _wait_for_terminal(task, observed_phases)
	assert_not_null(terminal, "the successful package task reaches a bounded terminal state")
	if terminal == null:
		task.shutdown()
		_cleanup_test_root()
		return
	assert_equal(terminal.state, PackageOperationStatusScript.SUCCEEDED, "the package task reaches terminal success")
	assert_true(observed_phases.has(&"complete"), "the worker publishes a meaningful terminal progress phase")
	assert_equal([terminal.completed, terminal.total, terminal.progress_ratio()], [1, 1, 1.0], "successful progress is complete and bounded")

	var result: RefCounted = task.take_result()
	assert_not_null(result, "a successful package result is handed off to the caller")
	if result != null:
		assert_true(result.is_ok(), "the handed-off package result is typed success")
		assert_equal(result.package.content.campaign_id, campaign_id, "the result retains the validated campaign identity")
		assert_true(FileAccess.file_exists(result.installed_path), "the successful result points to the immutable installed package")
		assert_contains(result.installed_path, package_hash, "the successful result path carries the package hash")
	assert_true(task.take_result() == null, "a package result is consumed exactly once")
	var idle: RefCounted = task.snapshot()
	assert_equal([idle.state, idle.phase, idle.completed, idle.total], [PackageOperationStatusScript.IDLE, &"", 0, 0], "taking the result resets the task to idle")
	task.shutdown()
	_cleanup_test_root()


func _test_tampered_task(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root()
	var task: RefCounted = PackageInstallTaskScript.new()
	assert_true(task.start(TAMPERED_FIXTURE_PATH, TEST_ROOT), "a package install task starts from the tampered fixture")
	var terminal := _wait_for_terminal(task)
	assert_not_null(terminal, "the tampered package task reaches a bounded terminal state")
	if terminal == null:
		task.shutdown()
		_cleanup_test_root()
		return
	assert_equal(terminal.state, PackageOperationStatusScript.FAILED, "the tampered package task reaches terminal failure")
	var result: RefCounted = task.take_result()
	assert_not_null(result, "a typed failure result is handed off for a tampered package")
	if result != null:
		assert_false(result.is_ok(), "a tampered package cannot produce a successful install")
		assert_equal(result.error_code, &"package_validation_failed", "the worker preserves the repository validation error code")
		assert_contains(result.error_message, "failed size or SHA-256", "the worker preserves the repository validation error message")
		assert_true(result.installed_path.is_empty(), "a failed package result has no installed path")
		assert_true(result.package == null, "a failed package result has no validated package payload")
	assert_false(FileAccess.file_exists(_installed_path(campaign_id, package_hash)), "a tampered package leaves no immutable installation")
	task.shutdown()
	_cleanup_test_root()


func _test_cancel_before_start(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root()
	var task: RefCounted = PackageInstallTaskScript.new()
	task.cancel()
	var before_start: RefCounted = task.snapshot()
	assert_equal([before_start.state, before_start.phase], [PackageOperationStatusScript.IDLE, &""], "cancellation before start is a deterministic no-op")
	assert_false(FileAccess.file_exists(_installed_path(campaign_id, package_hash)), "cancellation before start leaves no immutable installation")
	task.shutdown()
	_cleanup_test_root()


func _test_shutdown_joins_worker() -> void:
	_cleanup_test_root()
	var task: RefCounted = PackageInstallTaskScript.new()
	assert_true(task.start(TAMPERED_FIXTURE_PATH, TEST_ROOT), "a worker starts before shutdown is requested")
	task.shutdown()
	var after_shutdown: RefCounted = task.snapshot()
	assert_true(after_shutdown.state == PackageOperationStatusScript.FAILED or after_shutdown.state == PackageOperationStatusScript.CANCELLED, "shutdown joins the started worker at a terminal state")
	var result: RefCounted = task.take_result()
	assert_not_null(result, "a joined worker retains one result for explicit consumption")
	assert_true(task.take_result() == null, "shutdown does not duplicate the worker result")
	task.shutdown()
	_cleanup_test_root()


func _wait_for_terminal(task: RefCounted, observed_phases: Array[StringName] = []) -> RefCounted:
	var deadline := Time.get_ticks_msec() + TERMINAL_WAIT_MILLISECONDS
	while Time.get_ticks_msec() < deadline:
		var status: RefCounted = task.snapshot()
		if status.phase != &"" and not observed_phases.has(status.phase):
			observed_phases.append(status.phase)
		if not status.is_running() and status.state != PackageOperationStatusScript.IDLE:
			return status
		OS.delay_msec(POLL_DELAY_MILLISECONDS)
	var timed_out: RefCounted = task.snapshot()
	if timed_out.phase != &"" and not observed_phases.has(timed_out.phase):
		observed_phases.append(timed_out.phase)
	return timed_out


func _installed_path(campaign_id: String, package_hash: String) -> String:
	return TEST_ROOT.path_join(campaign_id).path_join("%s.realmz2" % package_hash)


func _cleanup_test_root() -> void:
	var root := _verified_test_root()
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return
	_remove_tree(root, root)


func _verified_test_root() -> String:
	var expected := ProjectSettings.globalize_path("user://").simplify_path().path_join("test-package-task")
	var actual := ProjectSettings.globalize_path(TEST_ROOT).simplify_path()
	return actual if actual == expected else ""


func _remove_tree(path: String, verified_root: String) -> void:
	if path != verified_root and not path.begins_with(verified_root + "/"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories():
		_remove_tree(path.path_join(directory_name), verified_root)
	DirAccess.remove_absolute(path)
