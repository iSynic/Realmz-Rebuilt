## Owns discovered campaign rows, persisted revision errors, and recent-campaign prewarming.

class_name CampaignCatalogWorkflow
extends RefCounted

var campaigns: Array[CampaignPackageView] = []
var _package_host: PackageHostController
var _campaign_library: CampaignLibraryController
var _character_files: ApplicationCharacterFilesHost
var _presentation_settings: PresentationSettings
var _status_controller: GameShellStatusController
var _last_revision_error := ""
var _prewarm_requested := false


func _init(package_host: PackageHostController, campaign_library: CampaignLibraryController, character_files: ApplicationCharacterFilesHost, presentation_settings: PresentationSettings, status_controller: GameShellStatusController) -> void:
	_package_host = package_host
	_campaign_library = campaign_library
	_character_files = character_files
	_presentation_settings = presentation_settings
	_status_controller = status_controller


func refresh(selected_import_path: String = "") -> void:
	if _package_host.operation_view().is_running():
		return
	campaigns = _package_host.discover_available_campaigns()
	_campaign_library.set_campaigns(campaigns)
	if not selected_import_path.is_empty():
		_campaign_library.select_imported_package(selected_import_path)
	var error := _package_host.imported_revision_error
	if error.is_empty():
		_last_revision_error = ""
	elif error != _last_revision_error:
		_last_revision_error = error
		_status_controller.set_status("Scenario revision library could not be updated. %s" % error, true)
func prewarm_if_ready(application_visible: bool = true) -> void:
	var campaign_id: String = _presentation_settings.last_campaign_id if _presentation_settings != null else ""
	var library_ready: bool = _character_files != null and _character_files.library_content() != null
	if _prewarm_requested or not library_ready or not application_visible or campaign_id.is_empty():
		return
	_prewarm_requested = true
	_package_host.prewarm_last_campaign(campaigns, campaign_id)
