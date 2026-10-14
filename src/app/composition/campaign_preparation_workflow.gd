## Coordinates editable party drafts and exact-revision loads on the package worker.
class_name CampaignPreparationWorkflow
extends RefCounted

var _packages: PackageHostController
var _session: GameSessionController
var _files: ApplicationCharacterFilesHost
var _saves: SaveHostController
var _storage: ApplicationAdventureStorageHost
var _navigator: ScreenNavigator
var _settings: PresentationSettings
var _publish: Callable
var _publish_setup: Callable
var _imported: ImportedScenarioWorkflow
var _candidate: PreparedPackage
var _path := ""
var _seed := 1
var _mode: StringName = &"setup"
var _waiting := false
var _pending_update := false
var _setup_path := ""
var _selected_setup_path := ""
var _browser_campaign := ""
var _selected_key := ""
var _replacement_slot := ""
var _previews: Array[SaveSlotPreview] = []
var _revisions: Array[PackageDiscoveryResult] = []
var _campaigns: Array[CampaignPackageView] = []
var _error := ""
var _discard_completion := false
var active := false


func _init(packages: PackageHostController, session: GameSessionController, files: ApplicationCharacterFilesHost, saves: SaveHostController, storage: ApplicationAdventureStorageHost, navigator: ScreenNavigator, settings: PresentationSettings, imported: ImportedScenarioWorkflow, publish: Callable, publish_setup: Callable) -> void:
	_packages = packages
	_session = session
	_files = files
	_saves = saves
	_storage = storage
	_navigator = navigator
	_settings = settings
	_imported = imported
	_publish = publish
	_publish_setup = publish_setup
	_navigator.startup.browser_requested.connect(open_browser)
	_navigator.startup.browser_closed.connect(_browser_closed)
	_navigator.startup.wait_cancel_requested.connect(cancel_wait)
	var browser := navigator.startup.browser
	browser.campaign_selected.connect(select_campaign)
	browser.save_selected.connect(select_save)
	browser.load_requested.connect(request_load)
	browser.legacy_load_requested.connect(request_load)
	browser.refresh_requested.connect(refresh_browser)
	browser.update_requested.connect(request_update)


func begin_setup(path: String, seed_value: int) -> bool:
	_mode = &"setup"
	_seed = seed_value
	_selected_setup_path = path
	_waiting = false
	_pending_update = false
	_navigator.setup_controller.campaign_library.setup_ready = path == _setup_path and _session.view().party_setup_available
	var started := _prepare(path)
	if _candidate != null: accept_package(_candidate)
	return started


func _prepare(path: String) -> bool:
	active = true
	_discard_completion = false
	_error = ""
	if _path == path and _candidate != null:
		return true
	_path = path
	_candidate = null
	if not _packages.start_install(path):
		_fail("Scenario preparation could not start. Try again.")
		return false
	return true


func accept_setup(setup: PackageSetupResult) -> void:
	if not active or _mode != &"setup" or setup == null or not setup.is_ok() or setup.source_path != _path or _setup_path == _path and _session.view().party_setup_available:
		return
	_install_setup(setup.catalog, setup.media)


func _install_setup(catalog: ScenarioSetupCatalog, media: MediaSource) -> void:
	catalog.content.characters.install_application_catalog(_files.library_content().characters)
	var step := _session.prepare_party(catalog, _seed)
	if step.state == SessionStep.State.FAILED:
		_fail(step.error_message)
		return
	_setup_path = _path
	_navigator.setup_controller.campaign_library.setup_ready = true
	_publish_setup.call(catalog.content, media, _path)


func accept_package(prepared: PreparedPackage, source_path: String = "") -> void:
	if not active: return
	if not source_path.is_empty() and source_path != _path: return
	if _discard_completion:
		active = false
		return
	if prepared == null or not prepared.is_ok():
		_fail(prepared.error_message if prepared != null else "Scenario preparation was cancelled. Choose it again to retry.")
		return
	_candidate = prepared
	prepared.content.characters.install_application_catalog(_files.library_content().characters)
	if _mode == &"setup":
		if _setup_path != _path or not _session.view().party_setup_available:
			_install_setup(ScenarioSetupCatalog.new(prepared.content, _files.library_content().package_hash), prepared.media)
		if _waiting: request_play()
	elif _pending_update:
		_finish_update()
	elif _waiting:
		_finish_load()
	else:
		_navigator.startup.browser.set_progress("Ready to load.")


func progress(operation: PackageOperationView) -> void:
	if not active: return
	if _navigator.startup.loading.visible: _navigator.startup.loading.update_progress(operation.message)
	if _navigator.startup.browser.visible: _navigator.startup.browser.set_progress(operation.message)


func owns_party_setup() -> bool:
	return not _setup_path.is_empty() and _session.view().party_setup_available


func request_play() -> SessionStep:
	if _selected_setup_path != _setup_path:
		return SessionStep.failed(_session.view().revision, &"campaign_preparing", "The selected scenario’s party rules are still preparing.")
	if not _session.view().availability(&"begin_adventure").enabled:
		return SessionStep.failed(_session.view().revision, &"party_not_ready", _session.view().availability(&"begin_adventure").reason)
	_mode = &"setup"
	if _path != _setup_path and not _prepare(_setup_path):
		return SessionStep.failed(_session.view().revision, &"preparation_failed", _error)
	if _candidate == null:
		_waiting = true
		if not _packages.operation_view().is_running() and not _prepare(_setup_path):
			return SessionStep.failed(_session.view().revision, &"preparation_failed", _error)
		_navigator.startup.show_loading(_session.view().campaign_summary.title, "party setup")
		return SessionStep.completed(_session.view().revision)
	var session := _session.session()
	if session == null: return SessionStep.failed(_session.view().revision, &"session_busy", "The party is unavailable.")
	if session.is_preparing_party():
		var activation := _session.activate_prepared_party(_candidate.content)
		if activation.state == SessionStep.State.FAILED:
			_fail(activation.error_message)
			return activation
	if not _imported.commit_prepared_revision(_candidate):
		_fail(_packages.imported_revision_error)
		return SessionStep.failed(_session.view().revision, &"revision_preference_failed", _error)
	var step := _session.submit_intent(PartyIntents.begin_adventure())
	if step.state == SessionStep.State.FAILED:
		_fail(step.error_message)
		return step
	_publish.call(_candidate)
	_waiting = false
	active = false
	_navigator.startup.finish_loading(true)
	return step


func open_browser(from_setup: bool) -> void:
	_browser_campaign = _session.view().campaign_id if from_setup and _session.view().party_setup_available else _settings.last_campaign_id
	_selected_key = ""
	refresh_browser()


func refresh_browser() -> void:
	_campaigns.clear()
	_revisions = _packages.saved_party_catalog.discover()
	var known: Dictionary = {}
	for campaign: CampaignPackageView in _packages.discover_available_campaigns():
		if known.has(campaign.campaign_id): continue
		_campaigns.append(campaign)
		known[campaign.campaign_id] = true
	for revision: PackageDiscoveryResult in _revisions:
		if not known.has(revision.campaign_id):
			_campaigns.append(CampaignPackageView.from_discovery(revision))
			known[revision.campaign_id] = true
	for campaign_id: String in _saves.saved_campaign_ids():
		if known.has(campaign_id): continue
		_campaigns.append(CampaignPackageView.new("", false, campaign_id, "", "", "Scenario package is not installed.", campaign_id))
		known[campaign_id] = true
	if not known.has(_browser_campaign): _browser_campaign = ""
	_navigator.startup.browser.set_campaigns(_campaigns, _browser_campaign)
	_refresh_previews()


func select_campaign(campaign_id: String) -> void:
	_browser_campaign = campaign_id
	_selected_key = ""
	_refresh_previews()


func _refresh_previews() -> void:
	_previews.clear()
	if not _browser_campaign.is_empty(): _previews = _saves.campaign_previews(_browser_campaign, _current_hash())
	for preview: SaveSlotPreview in _previews:
		if preview.can_load and _revision_path(preview).is_empty():
			preview.can_load = false
			preview.status = SaveSlotPreview.PACKAGE_MISMATCH
			preview.error_message = "This save needs scenario revision %s, which is not installed. Restore that exact package or use an offered Update Save action." % preview.package_hash.left(12)
	if _selected_preview() == null:
		var remembered := _saves.remembered_slot(_browser_campaign)
		var selected: SaveSlotPreview
		for preview: SaveSlotPreview in _previews:
			if not preview.can_load or preview.source != SaveSlotPreview.PRIMARY: continue
			if selected == null or preview.slot_id == remembered or selected.slot_id != remembered and preview.modified_unix > selected.modified_unix:
				selected = preview
		_selected_key = _key(selected) if selected != null else ""
	_navigator.startup.browser.set_previews(_previews, _selected_key)
	var preview := _selected_preview()
	if preview != null: select_save(preview.slot_id, preview.source == SaveSlotPreview.BACKUP)
	else: _navigator.startup.browser.set_progress("Choose a saved adventure." if not _previews.is_empty() else "No saved adventures for this scenario.")


func select_save(slot: String, backup: bool) -> void:
	_selected_key = "%s:%s" % [slot, "backup" if backup else "primary"]
	_waiting = false
	_pending_update = false
	_mode = &"load"
	_replacement_slot = ""
	var preview := _selected_preview()
	if preview == null or not preview.can_load:
		_packages.cancel()
		_candidate = null
		_discard_completion = true
		active = true
		return
	_prepare(_revision_path(preview))
	_navigator.startup.browser.set_progress("Ready to load." if _candidate != null else "Preparing the saved adventure’s scenario…")


func request_load(slot: String, backup: bool, replacement_slot: String = "") -> void:
	var key := "%s:%s" % [slot, "backup" if backup else "primary"]
	if key != _selected_key: select_save(slot, backup)
	var preview := _selected_preview()
	if preview == null or not preview.can_load: return
	_replacement_slot = replacement_slot
	_waiting = true
	if _candidate != null:
		_finish_load()
		return
	if not _packages.operation_view().is_running() and not _prepare(_revision_path(preview)): return
	_navigator.startup.show_loading(_campaign_title(), "saved adventures")


func _finish_load() -> void:
	var preview := _selected_preview()
	if preview == null or _candidate.content.package_hash != preview.package_hash or _candidate.content.campaign_id != preview.campaign_id:
		_fail("The prepared scenario does not match the selected save. Select the save again to retry.")
		return
	var step := _storage.load(_candidate.content, preview.slot_id, preview.source == SaveSlotPreview.BACKUP, _replacement_slot)
	if step == null or step.state == SessionStep.State.FAILED:
		_fail(step.error_message if step != null else "The adventure is still busy.")
		return
	_publish.call(_candidate)
	active = false
	_waiting = false
	_setup_path = ""
	_navigator.startup.finish_loading(true)


func request_update(slot: String, backup: bool) -> void:
	_selected_key = "%s:%s" % [slot, "backup" if backup else "primary"]
	var preview := _selected_preview()
	if preview == null or not preview.can_update: return
	_mode = &"load"
	_pending_update = true
	_waiting = false
	for campaign: CampaignPackageView in _campaigns:
		if campaign.campaign_id == _browser_campaign and campaign.package_hash == _current_hash():
			_prepare(campaign.path)
			if _candidate != null: _finish_update()
			return


func _finish_update() -> void:
	_pending_update = false
	var preview := _selected_preview()
	if preview == null: return
	var updated_slot := _storage.update_save(_candidate.content, preview.slot_id, preview.source == SaveSlotPreview.BACKUP)
	if not updated_slot.is_empty():
		_selected_key = updated_slot + ":primary"
		refresh_browser()
	else:
		_fail(_saves.last_error())


func cancel_wait() -> void:
	_waiting = false
	_navigator.startup.finish_loading()


func _browser_closed() -> void:
	_waiting = false
	_pending_update = false
	_discard_completion = true
	_packages.cancel()


func _fail(message: String) -> void:
	_error = message
	_candidate = null
	if _mode == &"setup": _selected_setup_path = _setup_path
	_waiting = false
	_pending_update = false
	_navigator.startup.finish_loading()
	_navigator.startup.browser.set_progress(message + " Select Load to retry.")
	_navigator.setup_controller.campaign_library.set_package_operation(PackageOperationView.new(PackageOperationView.FAILED, &"", 0, 0, message, &"preparation_failed", _path, &"install_scenario"))


func _selected_preview() -> SaveSlotPreview:
	for preview: SaveSlotPreview in _previews:
		if _key(preview) == _selected_key: return preview
	return null


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)]


func _revision_path(preview: SaveSlotPreview) -> String:
	for revision: PackageDiscoveryResult in _revisions:
		if revision.ready and revision.campaign_id == preview.campaign_id and revision.package_hash == preview.package_hash: return revision.path
	return ""


func _current_hash() -> String:
	for campaign: CampaignPackageView in _campaigns:
		if campaign.campaign_id == _browser_campaign: return campaign.package_hash
	return ""


func _campaign_title() -> String:
	for campaign: CampaignPackageView in _campaigns:
		if campaign.campaign_id == _browser_campaign: return campaign.display_name
	return "saved adventure"
