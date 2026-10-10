## Owns application-level adventure save, restore, and save-preview operations.
class_name ApplicationAdventureStorageHost
extends RefCounted

var _repository_host: SaveHostController
var _session: GameSessionController
var _shell: GameShell
var _load_committed_operation: Callable
var _map_preview_operation: Callable
var party_import: ApplicationPartyImportHost
var _deferred_load: Dictionary = {}


func _init(
		repository_host: SaveHostController,
		session: GameSessionController,
		shell: GameShell,
		load_committed_operation: Callable,
		map_preview_operation: Callable = Callable(),
		packages: PackageHostController = null,
		character_files: ApplicationCharacterFilesHost = null,
		destination: Callable = Callable()
) -> void:
	_repository_host = repository_host
	_session = session
	_shell = shell
	_load_committed_operation = load_committed_operation
	_map_preview_operation = map_preview_operation
	if packages != null and character_files != null:
		party_import = ApplicationPartyImportHost.new(repository_host, packages, session, shell, destination)
		var import_owner: WeakRef = weakref(party_import)
		var library_owner: WeakRef = weakref(character_files)
		shell.navigator.setup_controller.party_import_requested.connect(func() -> void:
			var host := import_owner.get_ref() as ApplicationPartyImportHost
			var library := library_owner.get_ref() as ApplicationCharacterFilesHost
			if host != null and library != null and library.library_media() != null:
				host.open(library.library_content(), library.library_media().assets())
		)


func save(content: RealmzContent, slot_id: String) -> bool:
	if _session.is_busy() or _session.resolution_failed:
		_shell.status.set_status("Combat resolution failed. Load a saved adventure or return to the main menu." if _session.resolution_failed else "Save unavailable while combat is resolving.", true)
		return false
	if content == null:
		_shell.status.set_status("Save failed • no package loaded", true)
		return false
	var resolved_slot := _repository_host.active_slot(content) if slot_id == "quick" else slot_id
	var preview_jpeg := PackedByteArray()
	if _map_preview_operation.is_valid() and _session.view().map_view != null and _session.view().map_view.level_type == &"land":
		preview_jpeg = _map_preview_operation.call()
		if preview_jpeg.is_empty() and DisplayServer.get_name() != "headless":
			_shell.status.set_status("Save failed • the overworld map preview is not ready", true)
			return false
	var saved := _repository_host.save(content, resolved_slot, _session.session().snapshot(), preview_jpeg)
	if saved and resolved_slot.length() == 1 and SaveRepository.CLASSIC_SLOTS.contains(resolved_slot):
		if not _repository_host.set_active_slot(content, resolved_slot):
			_shell.status.set_status("Saved %s, but could not remember the active Quick Save slot." % resolved_slot, true)
			refresh(content, resolved_slot)
			return true
	_shell.status.set_status("Saved %s" % resolved_slot if saved else "Save failed • %s" % _repository_host.last_error(), not saved)
	if saved:
		refresh(content, resolved_slot)
		_shell.status.show_activity_indicator(&"save")
	return saved


func load(content: RealmzContent, slot_id: String, backup: bool = false, replacement_slot: String = "") -> SessionStep:
	if _session.is_busy():
		_deferred_load = {"content": content, "slot": slot_id, "backup": backup, "replacement": replacement_slot}
		_shell.status.set_status("Loading after this activation.")
		return null
	if content == null:
		_shell.status.set_status("Load failed • no package loaded", true)
		return SessionStep.failed(0, "no_package_loaded", "Load a package before restoring a save.")
	var envelope := _repository_host.load(content, slot_id, backup)
	if envelope == null:
		_shell.status.set_status("Load failed • %s" % _repository_host.last_error(), true)
		return SessionStep.failed(_session.view().revision, "save_load_failed", _repository_host.last_error())
	var resolved_slot := slot_id
	var previous_slot := ""
	if slot_id in ["quick", "quick-2"]:
		# This copies supported v5 records to A–J slots; it never migrates an older save schema.
		var validation := GameSession.new().restore(content, envelope)
		if validation.state == SessionStep.State.FAILED:
			_shell.status.set_status("Load failed • %s" % validation.error_message, true)
			return validation
		resolved_slot = _repository_host.assign_legacy_slot(content, envelope, replacement_slot)
		if resolved_slot.is_empty():
			_shell.status.set_status("Load failed • %s" % _repository_host.last_error(), true)
			return SessionStep.failed(_session.view().revision, "save_slot_assignment_failed", _repository_host.last_error())
		if not _repository_host.set_active_slot(content, resolved_slot):
			var message := "Copied to Slot %s, but could not remember its Quick Save assignment. The current adventure is unchanged. %s" % [resolved_slot, _repository_host.last_error()]
			refresh(content, resolved_slot)
			_shell.status.set_status(message, true)
			return SessionStep.failed(_session.view().revision, "save_slot_assignment_failed", message)
	elif resolved_slot.length() == 1 and SaveRepository.CLASSIC_SLOTS.contains(resolved_slot):
		var validation := GameSession.new().restore(content, envelope)
		if validation.state == SessionStep.State.FAILED:
			_shell.status.set_status("Load failed • %s" % validation.error_message, true)
			return validation
		previous_slot = _repository_host.active_slot(content)
		if not _repository_host.set_active_slot(content, resolved_slot):
			var message := "Could not remember Slot %s as the Quick Save target. The current adventure is unchanged. %s" % [resolved_slot, _repository_host.last_error()]
			_shell.status.set_status("Load failed • %s" % message, true)
			return SessionStep.failed(_session.view().revision, "save_slot_assignment_failed", message)
	var step := _session.restore(content, envelope)
	if step.state != SessionStep.State.FAILED:
		_load_committed_operation.call()
		refresh(content, resolved_slot)
	elif not previous_slot.is_empty() and not _repository_host.set_active_slot(content, previous_slot):
		_shell.status.set_status("Load failed • %s; previous Quick Save target could not be restored." % step.error_message, true)
		return step
	var status := "Loaded %s %s" % ["backup" if backup else "save", slot_id] if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	if step.state != SessionStep.State.FAILED and resolved_slot != slot_id:
		status = "Loaded into Slot %s • Quick Save uses %s • earlier save preserved" % [resolved_slot, resolved_slot]
	_shell.status.set_status(status, step.state == SessionStep.State.FAILED)
	return step


func update_save(content: RealmzContent, slot_id: String, backup: bool = false) -> bool:
	if _session.is_busy():
		_shell.status.set_status("Save updating is unavailable while combat is resolving.", true)
		return false
	var updated_slot := _repository_host.update_save(content, slot_id, backup)
	if updated_slot.is_empty():
		_shell.status.set_status("Save update failed • %s" % _repository_host.last_error(), true)
		return false
	_shell.navigator.content_presenter.set_save_previews(_repository_host.previews(content), updated_slot, _repository_host.active_slot(content))
	if _shell.navigator.current_screen() == &"save_load":
		_shell.navigator.refresh_current_workspace()
	_shell.status.set_status("Updated copy %s verified • original unchanged" % updated_slot)
	_shell.status.show_activity_indicator(&"save")
	return true


func poll() -> void:
	if _session.is_busy() or _deferred_load.is_empty(): return
	var request := _deferred_load
	_deferred_load = {}
	self.load(request["content"], request["slot"], request["backup"], request["replacement"])


func refresh(content: RealmzContent, selected_slot_id: String = "") -> void:
	_shell.navigator.content_presenter.set_save_previews(_repository_host.previews(content), selected_slot_id, _repository_host.active_slot(content))
	if _shell.navigator.current_screen() == &"save_load" and _session.view().session_started:
		_shell.navigator.refresh_current_workspace()
