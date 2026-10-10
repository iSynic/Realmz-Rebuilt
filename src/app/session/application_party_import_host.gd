## Owns detached save selection, exact-package validation, and reviewed admission.
class_name ApplicationPartyImportHost
extends RefCounted

var _saves: SaveHostController
var _packages: PackageHostController
var _session: GameSessionController
var _setup: CampaignPartySetupController
var _destination: Callable
var _sources: Array[SavePartySource] = []
var _package_records: Array[PackageDiscoveryResult] = []
var _source: SavePartySource
var _source_content: RealmzContent
var _review: PartyTransferReview
var _task := PackageReadTask.new()
var _open := false


func _init(saves: SaveHostController, packages: PackageHostController, session: GameSessionController, shell: GameShell, destination: Callable) -> void:
	_saves = saves
	_packages = packages
	_session = session
	_setup = shell.navigator.setup_controller
	_destination = destination
	shell.tree_exiting.connect(cancel)
	var owner: WeakRef = weakref(self)
	_setup.party_import_source_requested.connect(func(index: int) -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.select_source(index))
	_setup.party_import_external_source_requested.connect(func(path: String) -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.select_external(path))
	_setup.party_import_selected_requested.connect(func(indices: Array[int]) -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.import_selected(indices))
	_setup.party_import_cancel_requested.connect(func() -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.cancel())
	_setup.party_import_refresh_requested.connect(func() -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.refresh())


func open(application: RealmzContent, assets: Array[MediaAsset]) -> void:
	if not _session.view().party_setup_available or application == null:
		return
	cancel()
	_task.configure(application, assets)
	_open = true
	refresh()


func refresh() -> void:
	if not _open:
		return
	_task.shutdown()
	_source_content = null
	_review = null
	_sources = _saves.party_sources()
	_package_records = _packages.saved_party_catalog.discover()
	var rows: Array[Dictionary] = []
	for source: SavePartySource in _sources:
		var record := _package_for(source)
		var title := record.display_name if record != null and not record.display_name.is_empty() else source.campaign_id
		if title.is_empty(): title = "External save"
		var detail := source.error
		if detail.is_empty() and record == null:
			detail = _missing_package_message(source)
		if detail.is_empty(): detail = "Required package available. " + ", ".join(source.party_names)
		var date := Time.get_datetime_string_from_unix_time(source.modified_unix).replace("T", " ")
		rows.append({"label": "%s · %s%s · %s" % [title, source.slot_id, " (backup)" if source.source_kind == &"backup" else "", date], "detail": detail, "valid": source.is_valid() and record != null})
	_setup.show_party_import({"phase": "selection", "sources": rows, "message": "Choose a saved adventure. Its world state stays behind."})


func select_source(index: int) -> void:
	if _open and index >= 0 and index < _sources.size():
		_prepare(_saves.read_party_source(_sources[index]))


func select_external(path: String) -> void:
	if _open:
		_prepare(_saves.read_external_party_source(path))


func _prepare(source: SavePartySource) -> void:
	_task.shutdown()
	_review = null
	_source_content = null
	_source = source
	if not source.is_valid():
		_show_error(source.error)
		return
	var record := _package_for(source)
	if record == null:
		_show_error(_missing_package_message(source))
		return
	if not _task.start(record.path):
		_show_error("The source package could not start loading. Choose the save again.")
		return
	_setup.show_party_import({"phase": "loading", "message": "Validating the exact source package and saved adventure…"})


func poll() -> void:
	if not _open or _task.is_running():
		return
	var loaded := _task.take_result()
	if loaded == null:
		return
	if not loaded.is_ok():
		_show_error(loaded.error_message)
		return
	var restored := SessionRestoreValidator.validate(loaded.content, _source.envelope)
	if not restored.ok:
		_show_error(restored.error_message)
		return
	_source_content = loaded.content
	_review_current_setup(restored.candidate.state)


func _review_current_setup(source_state: GameState) -> void:
	if (_session.is_busy() or _session.resolution_failed):
		_show_error("Combat resolution failed. Load a saved adventure or return to the main menu." if _session.resolution_failed else "Wait for combat resolution before importing a party.")
		return
	var content := _destination.call() as RealmzContent
	var snapshot := _session.session().snapshot()
	if content == null or snapshot == null or not _session.view().party_setup_available:
		_show_error("Return to new-adventure party setup before importing.")
		return
	var destination := SessionWorkflowContext.new(content, snapshot.game_state, RealmzRules.new(), null, null, null)
	_review = PartyTransferRules.prepare(source_state, _source_content, destination, _session.view().revision, _source.source_file_hash)
	var rows: Array[Dictionary] = []
	var remaining := _review.available_slots
	for candidate: PartyTransferCandidate in _review.candidates:
		var character := candidate.character
		var detail := "\n".join(candidate.reasons)
		if character != null:
			detail += "\nLevel %d · HP %d/%d · SP %d/%d\nPersonal money: %d gold, %d gems, %d jewelry\nKept: %s\nRemoved: %s" % [character.level, character.current_health, character.maximum_health, character.spell_points, character.maximum_spell_points, character.money.gold, character.money.gems, character.money.jewelry, ", ".join(candidate.retained) if not candidate.retained.is_empty() else "No portable possessions", "\n".join(candidate.removed) if not candidate.removed.is_empty() else "None"]
		var selected := candidate.eligible() and remaining > 0
		if selected: remaining -= 1
		rows.append({"name": character.name if character != null else "Invalid character", "eligible": candidate.eligible(), "selected": selected, "detail": detail.strip_edges()})
	_setup.show_party_import({"phase": "review", "candidates": rows, "available_slots": _review.available_slots, "left_behind": _review.left_behind, "message": "Review the heroes and possessions that can join this adventure."})


func import_selected(indices: Array[int]) -> void:
	if not _open or _review == null:
		return
	var current := _saves.read_party_source(_source)
	if not current.is_valid() or current.source_file_hash != _review.source_file_hash:
		_prepare(current)
		return
	var destination := _destination.call() as RealmzContent
	if destination == null or destination.package_hash != _review.destination_package_hash or _session.view().revision != _review.destination_revision:
		_review_current_setup(_source.envelope.game_state)
		return
	var members: Array[CharacterState] = []
	var seen: Array[int] = []
	for index: int in indices:
		if index < 0 or index >= _review.candidates.size() or seen.has(index) or not _review.candidates[index].eligible():
			_show_error("The selected heroes are unavailable. Choose the save again.")
			return
		seen.append(index)
	# Source order remains stable even when selection gestures arrive out of order.
	seen.sort()
	for index: int in seen: members.append(_review.candidates[index].character)
	var step := _session.submit_intent(PartyIntents.import_saved_party(members, _review))
	if step.state == SessionStep.State.FAILED:
		_show_error(step.error_message)
		return
	cancel()


func cancel() -> void:
	_open = false
	_task.shutdown()
	_sources.clear()
	_package_records.clear()
	_source = null
	_source_content = null
	_review = null
	_setup.close_party_import()


func _package_for(source: SavePartySource) -> PackageDiscoveryResult:
	for record: PackageDiscoveryResult in _package_records:
		if record.ready and record.campaign_id == source.campaign_id and record.package_hash == source.package_hash:
			return record
	return null


static func _missing_package_message(source: SavePartySource) -> String:
	return "Install the exact %s package revision %s through Choose Scenario, then Refresh. Other revisions cannot open this save." % [source.campaign_id, source.package_hash]


func _show_error(message: String) -> void:
	_setup.show_party_import({"phase": "error", "message": message})
