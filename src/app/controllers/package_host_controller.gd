class_name PackageHostController
extends RefCounted

const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const PackageInstallTaskScript := preload("res://src/infrastructure/packages/package_install_task.gd")
const BundledPackageLoadTaskScript := preload("res://src/infrastructure/packages/bundled_package_load_task.gd")
const BUNDLED_CAMPAIGN_ROOT: String = "res://src/infrastructure/campaigns"
const USER_CAMPAIGN_ROOT: String = "user://packages"

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


func _init(repository: PackageRepository = null, install_root: String = USER_CAMPAIGN_ROOT) -> void:
	_repository = repository if repository != null else PackageRepositoryScript.new()
	_install_root = install_root
	_task = PackageInstallTaskScript.new(_repository)
	_bundled_task = BundledPackageLoadTaskScript.new()


func start_install(package_path: String) -> bool:
	_advance_task()
	if package_path.is_empty():
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
	if not _queued_foreground_path.is_empty():
		_queued_foreground_path = ""
		_task_is_foreground = true
	if _task_is_foreground:
		_task.cancel()


func operation_view() -> PackageOperationView:
	_advance_task()
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
	return prepared


func retained_candidate_count() -> int:
	_advance_task()
	return 1 if _prepared_candidate != null else 0


func prepared_campaign_id() -> String:
	_advance_task()
	return _prepared_candidate_campaign_id


func prewarm_running() -> bool:
	_advance_task()
	return _task.snapshot().is_running() and not _task_is_foreground


func install_sync(package_path: String) -> PreparedPackage:
	return _prepare(_repository.install_package(package_path))


func discover_campaigns(search_roots: Array[String]) -> Array[CampaignPackageView]:
	var result: Array[CampaignPackageView] = []
	for record: PackageDiscoveryResult in _repository.discover_campaigns(search_roots):
		result.append(CampaignPackageView.from_discovery(record))
	return result


func discover_available_campaigns(bundled_root: String = BUNDLED_CAMPAIGN_ROOT, user_root: String = USER_CAMPAIGN_ROOT) -> Array[CampaignPackageView]:
	var selected_by_campaign: Dictionary = {}
	var rejected: Array[PackageDiscoveryResult] = []
	for record: PackageDiscoveryResult in _repository.discover_campaigns([bundled_root]):
		if record.ready:
			selected_by_campaign[record.campaign_id] = record
		else:
			rejected.append(record)
	for record: PackageDiscoveryResult in _repository.discover_campaigns([user_root]):
		if record.ready:
			selected_by_campaign[record.campaign_id] = record
		else:
			rejected.append(record)
	var campaign_ids: Array[String] = []
	campaign_ids.assign(selected_by_campaign.keys())
	campaign_ids.sort()
	var result: Array[CampaignPackageView] = []
	for campaign_id: String in campaign_ids:
		result.append(CampaignPackageView.from_discovery(selected_by_campaign[campaign_id]))
	for record: PackageDiscoveryResult in rejected:
		if record.campaign_id.is_empty() or not selected_by_campaign.has(record.campaign_id):
			result.append(CampaignPackageView.from_discovery(record))
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
		_foreground_operation = PackageOperationView.from_status(status)
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


func _prepare(installation: PackageInstallResult) -> PreparedPackage:
	if installation == null:
		return PreparedPackage.new("", null, null, &"package_operation_failed", "Package operation returned no result.")
	if not installation.is_ok():
		return PreparedPackage.new("", null, null, installation.error_code, installation.error_message)
	return PreparedPackage.new(installation.installed_path, installation.package.content, installation.package.media)
