extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TAMPERED_FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-tampered.realmz2"
const TEST_ROOT: String = "user://test-package-task"
const PackageInstallTaskScript := preload("res://src/infrastructure/packages/package_install_task.gd")
const PackageOperationStatusScript := preload("res://src/infrastructure/packages/package_operation_status.gd"); const BundledPackageLoadTaskScript := preload("res://src/infrastructure/packages/bundled_package_load_task.gd")

const TERMINAL_WAIT_MILLISECONDS: int = 20_000
const POLL_DELAY_MILLISECONDS: int = 2


func selected_case_arguments() -> Array:
	var package := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package.is_ok(), "the package-task success fixture passes independent package validation")
	if not package.is_ok(): return []
	return [package.content.campaign_id, package.content.package_hash]


func run() -> void:
	var package := PackageRepository.new().load_package(FIXTURE_PATH); assert_true(package.is_ok(), "the package-task success fixture passes independent package validation")
	if not package.is_ok():
		return
	var campaign_id: String = package.content.campaign_id
	var package_hash: String = package.content.package_hash

	_test_successful_task(campaign_id, package_hash)
	_test_tampered_task(campaign_id, package_hash)
	_test_cancel_before_start(campaign_id, package_hash)
	_test_shutdown_joins_worker(); _test_bundled_load_task()
	_test_package_host_prewarm(campaign_id, package_hash)
	_cleanup_test_root()


func _test_successful_task(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root(); var task_repository := PackageRepository.new(); var task: RefCounted = PackageInstallTaskScript.new(task_repository); assert_true(task.start(FIXTURE_PATH, TEST_ROOT), "a package install task starts from the positive fixture")
	var observed_phases: Array[StringName] = []; var terminal := _wait_for_terminal(task, observed_phases)
	assert_not_null(terminal, "the successful package task reaches a bounded terminal state")
	if terminal == null:
		task.shutdown(); _cleanup_test_root(); return
	assert_equal(terminal.state, PackageOperationStatusScript.SUCCEEDED, "the package task reaches terminal success"); assert_true(observed_phases.has(&"complete"), "the worker publishes a meaningful terminal progress phase")
	assert_equal([terminal.completed, terminal.total, terminal.progress_ratio()], [1, 1, 1.0], "successful progress is complete and bounded")

	var result: RefCounted = task.take_result(); assert_not_null(result, "a successful package result is handed off to the caller")
	if result != null:
		assert_true(result.is_ok(), "the handed-off package result is typed success"); assert_equal(result.package.content.campaign_id, campaign_id, "the result retains the validated campaign identity")
		assert_true(FileAccess.file_exists(result.installed_path), "the successful result points to the immutable installed package"); assert_contains(result.installed_path, package_hash, "the successful result path carries the package hash")
	assert_true(task.take_result() == null, "a package result is consumed exactly once"); var idle: RefCounted = task.snapshot()
	assert_equal([idle.state, idle.phase, idle.completed, idle.total], [PackageOperationStatusScript.IDLE, &"", 0, 0], "taking the result resets the task to idle")
	task.shutdown(); _cleanup_test_root()


func _test_tampered_task(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root(); var task: RefCounted = PackageInstallTaskScript.new(); assert_true(task.start(TAMPERED_FIXTURE_PATH, TEST_ROOT), "a package install task starts from the tampered fixture"); var terminal := _wait_for_terminal(task)
	assert_not_null(terminal, "the tampered package task reaches a bounded terminal state")
	if terminal == null:
		task.shutdown(); _cleanup_test_root(); return
	assert_equal(terminal.state, PackageOperationStatusScript.FAILED, "the tampered package task reaches terminal failure")
	var result: RefCounted = task.take_result(); assert_not_null(result, "a typed failure result is handed off for a tampered package")
	if result != null:
		assert_false(result.is_ok(), "a tampered package cannot produce a successful install"); assert_equal(result.error_code, &"package_validation_failed", "the worker preserves the repository validation error code")
		assert_contains(result.error_message, "failed size or SHA-256", "the worker preserves the repository validation error message")
		assert_true(result.installed_path.is_empty(), "a failed package result has no installed path"); assert_true(result.package == null, "a failed package result has no validated package payload")
	assert_false(FileAccess.file_exists(_installed_path(campaign_id, package_hash)), "a tampered package leaves no immutable installation"); task.shutdown(); _cleanup_test_root()


func _test_cancel_before_start(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root(); var task: RefCounted = PackageInstallTaskScript.new(); task.cancel(); var before_start: RefCounted = task.snapshot()
	assert_equal([before_start.state, before_start.phase], [PackageOperationStatusScript.IDLE, &""], "cancellation before start is a deterministic no-op"); assert_false(FileAccess.file_exists(_installed_path(campaign_id, package_hash)), "cancellation before start leaves no immutable installation")
	task.shutdown(); _cleanup_test_root()


func _test_shutdown_joins_worker() -> void:
	_cleanup_test_root(); var task: RefCounted = PackageInstallTaskScript.new()
	assert_true(task.start(TAMPERED_FIXTURE_PATH, TEST_ROOT), "a worker starts before shutdown is requested")
	task.shutdown(); var after_shutdown: RefCounted = task.snapshot()
	assert_true(after_shutdown.state == PackageOperationStatusScript.FAILED or after_shutdown.state == PackageOperationStatusScript.CANCELLED, "shutdown joins the started worker at a terminal state")
	var result: RefCounted = task.take_result()
	assert_not_null(result, "a joined worker retains one result for explicit consumption"); assert_true(task.take_result() == null, "shutdown does not duplicate the worker result")
	task.shutdown(); _cleanup_test_root()


func _test_bundled_load_task() -> void:
	var task: RefCounted = BundledPackageLoadTaskScript.new(); var deadline := Time.get_ticks_msec() + TERMINAL_WAIT_MILLISECONDS
	assert_true(task.start("res://src/infrastructure/characters/realmz-classic-character-library.realmz2", "realmz-classic-character-library", "6e3f23c9a452f70b25040c729e17533de5ddf0c420ff35484fc52f6e0dd25e68"), "the built-in library starts outside the first-frame boundary")
	while task.is_running() and Time.get_ticks_msec() < deadline: OS.delay_msec(POLL_DELAY_MILLISECONDS)
	var result: PackageLoadResult = task.take_result()
	assert_true(result != null and result.is_ok() and result.content.race_definitions().size() == 30, "the asynchronous built-in load returns the complete trusted Classic library"); assert_true(task.take_result() == null, "the built-in result is consumed exactly once"); task.shutdown()


func _test_package_host_prewarm(campaign_id: String, package_hash: String) -> void:
	_cleanup_test_root(); var campaign := CampaignPackageView.new(FIXTURE_PATH, true, campaign_id, package_hash); var host := PackageHostController.new(PackageRepository.new(), TEST_ROOT)
	assert_false(host.prewarm_last_campaign([campaign], "missing.campaign"), "a missing last-played campaign falls back without starting package work"); assert_true(host.prewarm_last_campaign([campaign], campaign_id), "the resolved last-played campaign starts on the existing cancellable package worker"); _wait_for_host_prewarm(host)
	assert_equal([host.retained_candidate_count(), host.prepared_campaign_id()], [1, campaign_id], "successful prewarm retains exactly one identity-bound prepared candidate")
	assert_true(host.start_install(FIXTURE_PATH), "selecting the matching campaign claims its prepared candidate"); var claimed_operation := host.operation_view(); var claimed := host.take_prepared_package()
	assert_true(claimed_operation.state == PackageOperationView.SUCCEEDED and claimed != null and claimed.is_ok() and claimed.content.campaign_id == campaign_id and host.retained_candidate_count() == 0, "matching selection returns the validated package immediately and consumes the retained candidate")
	host.close(); _cleanup_test_root(); host = PackageHostController.new(PackageRepository.new(), TEST_ROOT)
	assert_true(host.start_prewarm(TAMPERED_FIXTURE_PATH, "broken.campaign"), "a failed background preparation starts independently of foreground UI state"); _wait_for_host_prewarm(host)
	assert_equal(host.retained_candidate_count(), 0, "failed prewarm retains no package and permits retry")
	assert_true(host.start_prewarm(FIXTURE_PATH, campaign_id), "a later valid prewarm retries after background failure"); _wait_for_host_prewarm(host)
	assert_equal(host.retained_candidate_count(), 1, "retry retains the successfully validated candidate")
	assert_true(host.start_install(TAMPERED_FIXTURE_PATH), "selecting a different campaign supersedes the retained candidate with foreground priority"); var superseded_operation := _wait_for_host_operation(host); var superseded := host.take_prepared_package()
	assert_true(superseded_operation.state == PackageOperationView.FAILED and superseded != null and not superseded.is_ok() and host.retained_candidate_count() == 0, "different-campaign supersession preserves validation failure and leaves no stale prepared package")
	host.close(); _cleanup_test_root(); host = PackageHostController.new(PackageRepository.new(), TEST_ROOT)
	assert_true(host.start_install(FIXTURE_PATH), "foreground preparation starts before cooperative cancellation"); host.cancel()
	var cancelled_operation := _wait_for_host_operation(host)
	assert_equal(cancelled_operation.state, PackageOperationView.CANCELLED, "foreground cancellation reaches a typed terminal state without publishing a prepared candidate")
	host.take_prepared_package(); assert_equal(host.retained_candidate_count(), 0, "cancelled preparation retains no package"); host.close(); _cleanup_test_root()


func _wait_for_host_prewarm(host: PackageHostController) -> void:
	var deadline := Time.get_ticks_msec() + TERMINAL_WAIT_MILLISECONDS
	while host.prewarm_running() and Time.get_ticks_msec() < deadline: OS.delay_msec(POLL_DELAY_MILLISECONDS)


func _wait_for_host_operation(host: PackageHostController) -> PackageOperationView:
	var deadline := Time.get_ticks_msec() + TERMINAL_WAIT_MILLISECONDS; var operation := host.operation_view()
	while operation.is_running() and Time.get_ticks_msec() < deadline:
		OS.delay_msec(POLL_DELAY_MILLISECONDS); operation = host.operation_view()
	return operation


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
