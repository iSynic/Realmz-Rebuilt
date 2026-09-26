## Connects imported scenario actions to package preparation and detached campaign views.

class_name ImportedScenarioWorkflow
extends RefCounted

signal campaign_refresh_requested(selected_import_path: String)

var _package_host: PackageHostController
var _campaign_library: CampaignLibraryController
var _character_files: ApplicationCharacterFilesHost
var _status_controller: GameShellStatusController
var _pending_revision_id := ""
var _pending_revision_hash := ""


func _init(package_host: PackageHostController, campaign_library: CampaignLibraryController, character_files: ApplicationCharacterFilesHost, status_controller: GameShellStatusController) -> void:
	_package_host = package_host
	_campaign_library = campaign_library
	_character_files = character_files
	_status_controller = status_controller


func bind() -> void:
	_campaign_library.import_requested.connect(_begin_import)
	_campaign_library.startup_selection_requested.connect(_begin_import)
	_campaign_library.revision_requested.connect(_prefer_revision)
	_campaign_library.removal_requested.connect(_remove_campaign)


func complete_operation(operation: PackageOperationView, prepared: PreparedPackage) -> bool:
	if operation == null or operation.operation_name != &"import_scenario":
		return false
	if operation.state == PackageOperationView.SUCCEEDED and prepared != null and prepared.is_ok():
		campaign_refresh_requested.emit(prepared.installed_path)
	return true


func _begin_import(directory: String, startup_file: String = "") -> void:
	if not _character_files.library_ready():
		_status_controller.set_status("Finishing the built-in Classic definitions…", false)
		return
	if _package_host.start_import(directory, startup_file):
		_campaign_library.set_package_operation(_package_host.operation_view())


func _prefer_revision(campaign_id: String, package_hash: String) -> void:
	for campaign: CampaignPackageView in _campaign_library.campaigns:
		if campaign.origin != "imported" or campaign.campaign_id != campaign_id: continue
		for revision: Dictionary in campaign.revisions:
			if revision.get("package_hash") != package_hash: continue
			_pending_revision_id = campaign_id
			_pending_revision_hash = package_hash
			_campaign_library.preview_revision(campaign, package_hash, String(revision.get("path", "")))
			_campaign_library.start_requested.emit(String(revision.get("path", "")), 1)
			return
	_status_controller.set_status("That scenario revision is no longer available. Refresh the library and try again.", true)


func commit_prepared_revision(prepared: PreparedPackage) -> bool:
	var matching := prepared.content.campaign_id == _pending_revision_id and prepared.content.package_hash == _pending_revision_hash
	_pending_revision_id = ""
	_pending_revision_hash = ""
	for campaign: CampaignPackageView in _campaign_library.campaigns:
		if campaign.origin != "imported" or campaign.campaign_id != prepared.content.campaign_id: continue
		for revision: Dictionary in campaign.revisions:
			if revision.get("path") == prepared.installed_path and revision.get("package_hash") == prepared.content.package_hash: matching = true
	return not matching or _package_host.prefer_imported_revision(prepared.content.campaign_id, prepared.content.package_hash)


func prepare_party(prepared: PreparedPackage, controller: GameSessionController, seed_value: int) -> SessionStep:
	if prepared == null:
		return SessionStep.failed(0, &"package_operation_failed", "Package operation returned no result.")
	if not prepared.is_ok():
		return SessionStep.failed(0, prepared.error_code, prepared.error_message)
	prepared.content.characters.install_application_catalog(_character_files.library_content().characters)
	var previous := controller.session()
	var step := controller.start(prepared.content, seed_value)
	if step.state == SessionStep.State.FAILED:
		return step
	if not commit_prepared_revision(prepared):
		controller.replace_session(previous)
		return SessionStep.failed(controller.view().revision, &"revision_preference_failed", _package_host.imported_revision_error)
	return step


func _remove_campaign(campaign_id: String) -> void:
	if _package_host.remove_imported_campaign(campaign_id):
		campaign_refresh_requested.emit("")
		_status_controller.set_status("Imported scenario removed from the library. Saved adventures are preserved.", false)
		return
	_status_controller.set_status("Could not remove the imported scenario. %s" % _package_host.imported_revision_error, true)
