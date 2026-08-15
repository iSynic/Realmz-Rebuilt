class_name PackageHostController
extends RefCounted

const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")
const PackageInstallTaskScript := preload("res://src/infrastructure/packages/package_install_task.gd")

var _repository: PackageRepository
var _task: PackageInstallTask


func _init(repository: PackageRepository = null) -> void:
	_repository = repository if repository != null else PackageRepositoryScript.new()
	_task = PackageInstallTaskScript.new(_repository)


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


func load_bundled(package_path: String, expected_campaign_id: String, expected_package_hash: String) -> PreparedPackage:
	var loaded := _repository.load_bundled_package(package_path, expected_campaign_id, expected_package_hash)
	if not loaded.is_ok():
		return PreparedPackage.new("", null, null, loaded.error_code, loaded.error_message)
	return PreparedPackage.new(package_path, loaded.content, loaded.media)


func promote(prepared: PreparedPackage) -> void:
	if prepared != null and prepared.is_ok() and not prepared.installed_path.is_empty():
		_repository.promote_installed_package(prepared.installed_path)


func close() -> void:
	_task.shutdown()
	_repository.close()


func _prepare(installation: PackageInstallResult) -> PreparedPackage:
	if installation == null:
		return PreparedPackage.new("", null, null, &"package_operation_failed", "Package operation returned no result.")
	if not installation.is_ok():
		return PreparedPackage.new("", null, null, installation.error_code, installation.error_message)
	return PreparedPackage.new(installation.installed_path, installation.package.content, installation.package.media)
