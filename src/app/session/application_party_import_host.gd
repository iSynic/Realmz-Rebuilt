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
var _source_state: GameState
var _adopt_changed := false
var _task := PackageReadTask.new()
var _open := false
var _art_host: ApplicationCharacterArtHost
var _rows: Array[Dictionary] = []


func _init(saves: SaveHostController, packages: PackageHostController, session: GameSessionController, shell: GameShell, destination: Callable, art_host: ApplicationCharacterArtHost = null) -> void:
	_saves = saves
	_packages = packages
	_session = session
	_setup = shell.navigator.setup_controller
	_destination = destination
	_art_host = art_host
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
	_setup.party_import_adopt_changed_requested.connect(func(adopt: bool) -> void:
		var host := owner.get_ref() as ApplicationPartyImportHost
		if host != null: host.set_adopt_changed(adopt))
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
	_source_state = null
	_sources = _saves.party_sources()
	_package_records = _packages.saved_party_catalog.discover()
	PartyImportViewBuilder.sort_sources(_sources, _package_records)
	_rows.clear()
	for source: SavePartySource in _sources:
		_rows.append(PartyImportViewBuilder.source_row(source, _package_records))
	_setup.show_party_import({"phase": "selection", "sources": _rows})


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
	_source_state = null
	_adopt_changed = false
	if not source.is_valid():
		_show_error(PartyImportViewBuilder.error_reason(source.error))
		return
	var record := PartyImportViewBuilder.package_for(source, _package_records)
	if record == null:
		_show_error(PartyImportViewBuilder.missing_package_reason(source, _package_records))
		return
	if not _task.start(record.path):
		_show_error("The scenario this save needs could not start loading. Choose the save again.")
		return
	_setup.show_party_import({"phase": "loading", "sources": _rows, "reading": "Reading %s · %s…" % [PartyImportViewBuilder.title_for(source.campaign_id, _package_records), PartyImportViewBuilder.slot_label(source)]})


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
	_source_state = restored.candidate.state
	_review_current_setup(_source_state)


## Re-reviews the loaded source with or without the destination's changed item versions.
func set_adopt_changed(adopt: bool) -> void:
	if not _open or _source_state == null or _source_content == null or adopt == _adopt_changed:
		return
	_adopt_changed = adopt
	_review_current_setup(_source_state)


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
	_review = PartyTransferRules.prepare(source_state, _source_content, destination, _session.view().revision, _source.source_file_hash, _adopt_changed)
	_show_review("")


## Each character becomes one card; eligible characters fill the open slots in source order.
func _show_review(error: String) -> void:
	var cards: Array[Dictionary] = []
	var remaining := _review.available_slots
	var art := _source.envelope.character_art if _source.envelope != null else null
	for candidate: PartyTransferCandidate in _review.candidates:
		var selected := candidate.eligible() and remaining > 0
		if selected: remaining -= 1
		cards.append(PartyImportViewBuilder.candidate_card(candidate, _source_content, selected, art))
	var destination := _destination.call() as RealmzContent
	_setup.show_party_import({"phase": "review", "candidates": cards, "available_slots": _review.available_slots, "left_behind": _review.left_behind, "changed_items": _review.changed_items, "adopt_changed": _adopt_changed, "source_line": PartyImportViewBuilder.source_line(_source, _package_records), "destination": "Joining %s" % destination.campaign.title if destination != null and destination.campaign != null else "", "error": error})


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
	if _art_host != null and not _art_host.install_save_art(current.envelope):
		_show_review(_art_host.last_error)
		return
	var step := _session.submit_intent(PartyIntents.import_saved_party(members, _review))
	if step.state == SessionStep.State.FAILED:
		_show_review(step.error_message)
		return
	cancel()


func cancel() -> void:
	_open = false
	_task.shutdown()
	_sources.clear()
	_rows.clear()
	_package_records.clear()
	_source = null
	_source_content = null
	_review = null
	_setup.close_party_import()


## A failure keeps the source list so the player can choose again.
func _show_error(message: String) -> void:
	var title := "Couldn't read %s · %s" % [PartyImportViewBuilder.title_for(_source.campaign_id, _package_records), PartyImportViewBuilder.slot_label(_source)] if _source != null else "Couldn't read that save"
	_setup.show_party_import({"phase": "error", "sources": _rows, "error_title": title, "message": message})
