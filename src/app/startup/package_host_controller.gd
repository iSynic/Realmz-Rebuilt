## Coordinates package host services at the application boundary.

class_name PackageHostController
extends RefCounted

const BUNDLED_CAMPAIGN_ROOT: String = "res://src/storage/packages/bundled_campaigns"
const USER_CAMPAIGN_ROOT: String = "user://packages"
const SHIPPED_BUNDLED_CAMPAIGN_IDS: Array[String] = [
	"scenario-assault-on-giant-mountain",
	"scenario-castle-in-the-clouds",
	"scenario-city-of-bywater",
	"scenario-destroy-the-necronomicon",
	"scenario-grilochs-revenge",
	"scenario-half-truth",
	"scenario-mithril-vault",
	"scenario-prelude-to-pestilence",
	"scenario-trouble-in-the-sword-lands",
	"scenario-twin-sands-of-time",
	"scenario-war-in-the-sword-lands",
	"scenario-white-dragon",
	"scenario-wrath-of-the-mind-lords",
]

var _repository: PackageRepository
var _task: PackageInstallTask
var _bundled_task: RefCounted
var _install_root: String = USER_CAMPAIGN_ROOT
var _task_source_path: String = ""
var _task_campaign_id: String = ""
var _task_is_foreground: bool = false
var _queued_foreground_path: String = ""
var _prepared_candidate: PreparedPackage
var _prepared_candidate_source_path: String = ""
var _prepared_candidate_campaign_id: String = ""
var _foreground_prepared: PreparedPackage
var _foreground_operation := PackageOperationView.new()
var _imports: ImportedScenarioLibrary
var _conversion: ClassicScenarioImportTask
var _import_source: String = ""
var _import_installing: bool = false
var imported_revision_error: String:
	get: return _imports.last_error
var prewarm_running: bool:
	get:
		_advance_task()
		return _task.snapshot().is_running() and not _task_is_foreground


func _init(repository: PackageRepository = null, install_root: String = USER_CAMPAIGN_ROOT) -> void:
	_repository = repository if repository != null else PackageRepository.new()
	_install_root = install_root
	_task = PackageInstallTask.new(_repository)
	_bundled_task = BundledPackageLoadTask.new()
	_imports = ImportedScenarioLibrary.new(install_root.get_base_dir().path_join("imported-scenarios.json"))
	_conversion = ClassicScenarioImportTask.new()
	_conversion.recover_abandoned_jobs(ProjectSettings.globalize_path(install_root.get_base_dir().path_join("import-jobs")))


func start_import(directory: String, startup_file: String = "") -> bool:
	if operation_view().is_running() or directory.is_empty():
		return false
	_conversion.close()
	var job_parent := ProjectSettings.globalize_path(_install_root.get_base_dir().path_join("import-jobs"))
	if not _conversion.start(directory, job_parent, "", startup_file):
		_import_source = ""
		_import_installing = false
		_foreground_prepared = null
		var reason := _conversion.message if _conversion.state == &"failed" else "The previous scenario importer is still stopping. Retry shortly."
		_foreground_operation = PackageOperationView.new(PackageOperationView.FAILED, &"starting", 0, 0, reason, &"scenario_import_failed", directory, &"import_scenario")
		return true
	_import_source = directory
	_import_installing = false
	_foreground_prepared = null
	_foreground_operation = PackageOperationView.new()
	_task.cancel()
	_advance_import()
	return true


func prefer_imported_revision(campaign_id: String, package_hash: String) -> bool:
	return _imports.prefer(campaign_id, package_hash)


func remove_imported_campaign(campaign_id: String) -> bool:
	if operation_view().is_running():
		return false
	if not _imports.remove_campaign(campaign_id):
		return false
	if _prepared_candidate_campaign_id == campaign_id:
		_prepared_candidate = null
		_prepared_candidate_source_path = ""
		_prepared_candidate_campaign_id = ""
	return true


func start_install(package_path: String) -> bool:
	_advance_task()
	if package_path.is_empty() or not _import_source.is_empty():
		return false
	if _prepared_candidate != null and _prepared_candidate_source_path == package_path:
		_foreground_prepared = _prepared_candidate
		_prepared_candidate = null
		_prepared_candidate_source_path = ""
		_prepared_candidate_campaign_id = ""
		_foreground_operation = PackageOperationView.new(PackageOperationView.SUCCEEDED, &"complete", 1, 1, "Campaign ready.")
		return true
	if _task.snapshot().is_running():
		if _task_source_path == package_path:
			_task_is_foreground = true
			return true
		_queued_foreground_path = package_path
		_prepared_candidate = null
		_prepared_candidate_source_path = ""
		_prepared_candidate_campaign_id = ""
		_task.cancel()
		return true
	_prepared_candidate = null
	_prepared_candidate_source_path = ""
	_prepared_candidate_campaign_id = ""
	return _start_task(package_path, "", true)


func prewarm_last_campaign(campaigns: Array[CampaignPackageView], campaign_id: String) -> bool:
	if campaign_id.is_empty():
		return false
	for campaign: CampaignPackageView in campaigns:
		if campaign.ready and campaign.campaign_id == campaign_id:
			return start_prewarm(campaign.path, campaign_id)
	return false


func start_prewarm(package_path: String, campaign_id: String) -> bool:
	_advance_task()
	if package_path.is_empty() or campaign_id.is_empty() or _task.snapshot().is_running() or _foreground_prepared != null or _foreground_operation.state != PackageOperationView.IDLE:
		return false
	if _prepared_candidate != null and _prepared_candidate_source_path == package_path:
		return true
	_prepared_candidate = null
	_prepared_candidate_source_path = ""
	_prepared_candidate_campaign_id = ""
	return _start_task(package_path, campaign_id, false)


func cancel() -> void:
	if not _import_source.is_empty() and not _import_installing:
		_conversion.cancel()
		_advance_import()
	if not _queued_foreground_path.is_empty():
		_queued_foreground_path = ""
		_task_is_foreground = true
	if _task_is_foreground:
		_task.cancel()


func operation_view() -> PackageOperationView:
	_advance_task()
	_advance_import()
	if _foreground_operation.state != PackageOperationView.IDLE:
		return _foreground_operation
	if _task_is_foreground or not _queued_foreground_path.is_empty():
		return PackageOperationView.from_status(_task.snapshot())
	return PackageOperationView.new()


func take_prepared_package() -> PreparedPackage:
	_advance_task()
	var status := _foreground_operation
	if status.is_running() or status.state == PackageOperationView.IDLE:
		return null
	var prepared := _foreground_prepared
	_foreground_prepared = null
	_foreground_operation = PackageOperationView.new()
	if not _import_source.is_empty():
		_conversion.close()
		_import_source = ""
		_import_installing = false
	return prepared


func retained_candidate_count() -> int:
	_advance_task()
	return 1 if _prepared_candidate != null else 0


func prepared_campaign_id() -> String:
	_advance_task()
	return _prepared_candidate_campaign_id


func install_sync(package_path: String) -> PreparedPackage:
	return _prepare(_repository.install_package(package_path, _install_root))


func set_application_content(content: RealmzContent, media_assets: Array[MediaAsset] = []) -> void:
	_advance_task()
	assert(not _task.snapshot().is_running(), "Application definitions cannot change during package preparation.")
	_repository.set_application_content(content, media_assets)


func discover_available_campaigns(bundled_root: String = BUNDLED_CAMPAIGN_ROOT, user_root: String = "") -> Array[CampaignPackageView]:
	var result: Array[CampaignPackageView] = []
	var bundled_hashes: Dictionary = {}
	for record: PackageDiscoveryResult in _repository.discover_campaigns([bundled_root]):
		var view := CampaignPackageView.from_discovery(record)
		view.origin = "main"
		result.append(view)
		bundled_hashes[record.package_hash] = true
	var imported: Array[PackageDiscoveryResult] = []
	for record: PackageDiscoveryResult in _repository.discover_packages([user_root if not user_root.is_empty() else _install_root]):
		if not bundled_hashes.has(record.package_hash) or _imports.contains_revision(record.campaign_id, record.package_hash):
			imported.append(record)
	for record: PackageDiscoveryResult in _imports.select_revisions(imported):
		var view := CampaignPackageView.from_discovery(record)
		view.revisions = _imports.revisions(record.campaign_id)
		result.append(view)
	return result


func load_bundled(package_path: String, expected_campaign_id: String, expected_package_hash: String) -> PreparedPackage:
	var loaded := _repository.load_bundled_package(package_path, expected_campaign_id, expected_package_hash)
	if not loaded.is_ok():
		return PreparedPackage.new("", null, null, loaded.error_code, loaded.error_message)
	return PreparedPackage.new(package_path, loaded.content, loaded.media)


func start_bundled_load(package_path: String, expected_campaign_id: String, expected_package_hash: String) -> bool:
	return _bundled_task.start(package_path, expected_campaign_id, expected_package_hash)


func bundled_load_is_running() -> bool:
	return _bundled_task.is_running()


func take_bundled_package(package_path: String) -> PreparedPackage:
	var loaded: PackageLoadResult = _bundled_task.take_result()
	if loaded == null:
		return null
	if not loaded.is_ok():
		return PreparedPackage.new("", null, null, loaded.error_code, loaded.error_message)
	return PreparedPackage.new(package_path, loaded.content, loaded.media)


func promote(prepared: PreparedPackage) -> void:
	if prepared != null and prepared.is_ok() and not prepared.installed_path.is_empty():
		_repository.promote_installed_package(prepared.installed_path)


func close() -> void:
	_conversion.close()
	_task.shutdown()
	_bundled_task.shutdown()
	_repository.close()
	_prepared_candidate = null
	_foreground_prepared = null


func _start_task(package_path: String, campaign_id: String, foreground: bool) -> bool:
	if not _task.start(package_path, _install_root):
		return false
	_task_source_path = package_path
	_task_campaign_id = campaign_id
	_task_is_foreground = foreground
	if foreground:
		_foreground_operation = PackageOperationView.from_status(_task.snapshot())
	return true


func _advance_task() -> void:
	var status := _task.snapshot()
	if status.is_running() or status.state == PackageOperationView.IDLE:
		if _task_is_foreground and status.is_running():
			_foreground_operation = PackageOperationView.from_status(status)
			if _import_installing:
				_foreground_operation.operation_name = &"import_scenario"
				_foreground_operation.package_path = _import_source
				_foreground_operation.phase = &"installing"
		return
	var completed_source_path := _task_source_path
	var completed_campaign_id := _task_campaign_id
	var completed_in_foreground := _task_is_foreground
	var prepared := _prepare(_task.take_result())
	_task_source_path = ""
	_task_campaign_id = ""
	_task_is_foreground = false
	if completed_in_foreground:
		_foreground_prepared = prepared
		_foreground_operation = PackageOperationView.from_status(status, completed_source_path, &"install_scenario", prepared.error_code if prepared != null else &"package_operation_failed")
		if _import_installing:
			_foreground_operation.operation_name = &"import_scenario"
			_foreground_operation.package_path = _import_source
			_foreground_operation.diagnostic_details = _conversion.diagnostic_details.duplicate()
			if prepared != null and prepared.is_ok():
				_record_import(prepared, _conversion.diagnostic_details)
				if _foreground_operation.state == PackageOperationView.SUCCEEDED:
					_foreground_operation.message = "Imported with warnings." if _conversion.warning_count > 0 or not _conversion.diagnostic_details.is_empty() else "Scenario imported."
		elif prepared != null and prepared.is_ok() and not completed_source_path.begins_with(BUNDLED_CAMPAIGN_ROOT) and not completed_source_path.begins_with(_install_root):
			_record_import(prepared)
	elif prepared != null and prepared.is_ok():
		_prepared_candidate = prepared
		_prepared_candidate_source_path = completed_source_path
		_prepared_candidate_campaign_id = completed_campaign_id
	if not _queued_foreground_path.is_empty():
		var next_path := _queued_foreground_path
		_queued_foreground_path = ""
		_prepared_candidate = null
		_prepared_candidate_source_path = ""
		_prepared_candidate_campaign_id = ""
		_start_task(next_path, "", true)


func _record_import(prepared: PreparedPackage, diagnostics: Array[String] = []) -> void:
	for record: PackageDiscoveryResult in _repository.discover_packages([prepared.installed_path.get_base_dir()]):
		if record.path == prepared.installed_path:
			var version_label := prepared.content.scenario_records.campaign.version
			if not _imports.record_install(record, diagnostics, version_label):
				_foreground_operation.state = PackageOperationView.FAILED
				_foreground_operation.message = _imports.last_error
			return
	_foreground_operation.state = PackageOperationView.FAILED
	_foreground_operation.message = "The installed package could not be added to the scenario library. Retry the import."


func _prepare(installation: PackageInstallResult) -> PreparedPackage:
	if installation == null:
		return PreparedPackage.new("", null, null, &"package_operation_failed", "Package operation returned no result.")
	if not installation.is_ok():
		return PreparedPackage.new("", null, null, installation.error_code, installation.error_message)
	return PreparedPackage.new(installation.installed_path, installation.package.content, installation.package.media)


func _advance_import() -> void:
	if _import_source.is_empty() or _import_installing:
		return
	_conversion.poll()
	_foreground_operation = PackageOperationView.new(_conversion.state, _conversion.phase, 0, 0, _conversion.message, &"scenario_import_failed", _import_source, &"import_scenario")
	_foreground_operation.startup_candidates = _conversion.startup_candidates.duplicate()
	_foreground_operation.diagnostic_details = _conversion.diagnostic_details.duplicate()
	if _conversion.state != &"succeeded":
		return
	if _task.snapshot().is_running():
		_foreground_operation.state = PackageOperationView.RUNNING
		_foreground_operation.message = "Waiting for package preparation to finish…"
		return
	_import_installing = true
	if not _start_task(_conversion.package_path, "", true):
		_foreground_operation = PackageOperationView.new(PackageOperationView.FAILED, &"installing", 0, 0, "Could not start scenario installation. Retry the import.", &"scenario_install_failed")
	_foreground_operation.phase = &"installing"
	_foreground_operation.operation_name = &"import_scenario"
	_foreground_operation.package_path = _import_source
