## Owns application-level adventure save, restore, and save-preview operations.
class_name ApplicationAdventureStorageHost
extends RefCounted

var _repository_host: SaveHostController
var _session: GameSessionController
var _shell: GameShell
var _load_committed_operation: Callable


func _init(
		repository_host: SaveHostController,
		session: GameSessionController,
		shell: GameShell,
		load_committed_operation: Callable
) -> void:
	_repository_host = repository_host
	_session = session
	_shell = shell
	_load_committed_operation = load_committed_operation


func save(content: RealmzContent, slot_id: String) -> bool:
	if content == null:
		_shell.status.set_status("Save failed • no package loaded", true)
		return false
	var saved := _repository_host.save(content, slot_id, _session.session().snapshot())
	_shell.status.set_status("Saved %s" % slot_id if saved else "Save failed • %s" % _repository_host.last_error(), not saved)
	if saved:
		refresh(content)
		_shell.status.show_activity_indicator(&"save")
	return saved


func load(content: RealmzContent, slot_id: String, backup: bool = false) -> SessionStep:
	if content == null:
		_shell.status.set_status("Load failed • no package loaded", true)
		return SessionStep.failed(0, "no_package_loaded", "Load a package before restoring a save.")
	var envelope := _repository_host.load(content, slot_id, backup)
	if envelope == null:
		_shell.status.set_status("Load failed • %s" % _repository_host.last_error(), true)
		return SessionStep.failed(_session.view().revision, "save_load_failed", _repository_host.last_error())
	var step := _session.restore(content, envelope)
	if step.state != SessionStep.State.FAILED:
		_load_committed_operation.call()
	var status := "Loaded %s %s" % ["backup" if backup else "save", slot_id] if step.state != SessionStep.State.FAILED else "Load failed • %s" % step.error_message
	_shell.status.set_status(status, step.state == SessionStep.State.FAILED)
	return step


func refresh(content: RealmzContent) -> void:
	_shell.navigator.content_presenter.set_save_previews(_repository_host.previews(content))
	if _shell.navigator.current_screen() == &"system" and _session.view().session_started:
		_shell.navigator.refresh_current_workspace()
