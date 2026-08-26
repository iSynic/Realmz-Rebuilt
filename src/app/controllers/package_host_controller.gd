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


func _init(repository: PackageRepository = null) -> void:
	_repository = repository if repository != null else PackageRepositoryScript.new()
	_task = PackageInstallTaskScript.new(_repository)
	_bundled_task = BundledPackageLoadTaskScript.new()


func start_install(package_path: String) -> bool:
	return _task.start(package_path)


func cancel() -> void:
	_task.cancel()


func operation_view() -> PackageOperationView:
	return PackageOperationView.from_status(_task.snapshot())


func take_prepared_package() -> PreparedPackage:
	var status := operation_view()
	if status.is_running() or status.state == PackageOperationView.IDLE:
		return null
	return _prepare(_task.take_result())


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


func _prepare(installation: PackageInstallResult) -> PreparedPackage:
	if installation == null:
		return PreparedPackage.new("", null, null, &"package_operation_failed", "Package operation returned no result.")
	if not installation.is_ok():
		return PreparedPackage.new("", null, null, installation.error_code, installation.error_message)
	return PreparedPackage.new(installation.installed_path, installation.package.content, installation.package.media)
