## Coordinates save host services at the application boundary.

class_name SaveHostController
extends RefCounted

var _repository: SaveRepository
var _half_truth_update: HalfTruthMediaSaveUpdate
var _shop_update: ShopSaveUpdate
var _marker_update: MarkerSaveUpdate
var _payment_update: PaymentSaveUpdate
var _program_update: ProgramSaveUpdate
var _compression_update: CompressionSaveUpdate
var _record_update: CompleteRecordSaveUpdate
var _owner_update: OwnerCorrectionSaveUpdate
var _last_error := ""
## The separate slot the last verified update would be copied to.
var _copy_slot := ""
## Updates that failed for an exact save file revision. Such a save keeps its original
## package and loads through that revision, so browsing never retries it.
var _failed_updates: Dictionary = {}
## Archive verifications reused only within one update batch.
var _batch_checks: Dictionary = {}
var _batching := false


func _init(repository: SaveRepository = null, half_truth_update: HalfTruthMediaSaveUpdate = null, shop_update: ShopSaveUpdate = null, marker_update: MarkerSaveUpdate = null, payment_update: PaymentSaveUpdate = null, program_update: ProgramSaveUpdate = null, compression_update: CompressionSaveUpdate = null, record_update: CompleteRecordSaveUpdate = null, owner_update: OwnerCorrectionSaveUpdate = null) -> void:
	_repository = repository if repository != null else SaveRepository.new()
	_half_truth_update = half_truth_update if half_truth_update != null else HalfTruthMediaSaveUpdate.new()
	_shop_update = shop_update if shop_update != null else ShopSaveUpdate.new()
	_marker_update = marker_update if marker_update != null else MarkerSaveUpdate.new()
	_payment_update = payment_update if payment_update != null else PaymentSaveUpdate.new()
	_program_update = program_update if program_update != null else ProgramSaveUpdate.new()
	_compression_update = compression_update if compression_update != null else CompressionSaveUpdate.new()
	_record_update = record_update if record_update != null else CompleteRecordSaveUpdate.new()
	_owner_update = owner_update if owner_update != null else OwnerCorrectionSaveUpdate.new()


func save(content: RealmzContent, slot_id: String, snapshot: SessionSnapshot, preview_jpeg: PackedByteArray = PackedByteArray()) -> bool:
	_last_error = ""
	if content == null:
		return false
	return _repository.save(content.campaign_id, slot_id, snapshot, preview_jpeg)


func active_slot(content: RealmzContent) -> String:
	return _repository.active_slot(content.campaign_id) if content != null else "A"


func party_sources() -> Array[SavePartySource]:
	return _repository.list_party_sources()


func read_party_source(source: SavePartySource) -> SavePartySource:
	return _repository.read_party_source(source)


func read_external_party_source(path: String) -> SavePartySource:
	return _repository.read_external_party_source(path)


func set_active_slot(content: RealmzContent, slot_id: String) -> bool:
	return content != null and _repository.set_active_slot(content.campaign_id, slot_id)


## Loads a save, first applying any pinned update that reaches `content`.
func load(content: RealmzContent, slot_id: String, backup: bool = false) -> SessionSnapshot:
	_last_error = ""
	if content == null:
		return null
	var old_hash := _repository.recorded_package_hash(content.campaign_id, slot_id, backup)
	if old_hash != content.package_hash and _can_update_file(content.campaign_id, slot_id, backup, old_hash, content.package_hash):
		if backup:
			# A backup is updated for this load only; its file stays as it is.
			var updated := _updated_envelope(content, slot_id, true, old_hash)
			if updated == null:
				_remember_failure(content.campaign_id, slot_id, true, old_hash)
			return updated
		if not _publish_update(content, slot_id, old_hash):
			_remember_failure(content.campaign_id, slot_id, false, old_hash)
			return null
	if backup:
		return _repository.load_backup(content.campaign_id, slot_id, content.package_hash)
	return _repository.load(content.campaign_id, slot_id, content.package_hash)


func campaign_previews(campaign_id: String, current_package_hash: String = "") -> Array[SaveSlotPreview]:
	var result: Array[SaveSlotPreview] = []
	result.assign(_repository.list_previews(campaign_id, ""))
	for preview: SaveSlotPreview in result:
		preview.can_update = preview.can_load and _can_update_file(campaign_id, preview.slot_id, preview.source == SaveSlotPreview.BACKUP, preview.package_hash, current_package_hash)
	return result


func remembered_slot(campaign_id: String) -> String:
	return _repository.active_slot(campaign_id)


func saved_campaign_ids() -> Array[String]:
	return _repository.campaign_ids()


func previews(content: RealmzContent) -> Array[SaveSlotPreview]:
	if content == null:
		return []
	var result: Array[SaveSlotPreview] = []
	result.assign(_repository.list_previews(content.campaign_id, content.package_hash))
	for preview: SaveSlotPreview in result:
		preview.can_update = preview.status == SaveSlotPreview.PACKAGE_MISMATCH and _can_update_file(preview.campaign_id, preview.slot_id, preview.source == SaveSlotPreview.BACKUP, preview.package_hash, content.package_hash)
		# Loading applies the verified update, so the save loads like any other.
		preview.can_load = preview.can_load or preview.can_update
	return result


## Applies every pinned update that reaches `content` to the listed primary saves.
## Each is verified exactly as a load would be, then republished in its own slot:
## the original becomes that slot's backup and the Quick Save target follows it.
## Returns the updated slots; a failed update leaves its save as it was.
func apply_updates(content: RealmzContent) -> Array[String]:
	var updated: Array[String] = []
	var failure := ""
	for slot_id: String in pending_updates(content):
		if apply_update(content, slot_id):
			updated.append(slot_id)
		elif failure.is_empty():
			failure = _last_error
	finish_updates()
	_last_error = failure
	return updated


## Starts an update batch and returns the primary saves a pinned update can still reach.
## Kept earlier backups and saves whose update already failed are left as they are.
func pending_updates(content: RealmzContent) -> Array[String]:
	_last_error = ""
	_batching = true
	_batch_checks.clear()
	var pending: Array[String] = []
	if content == null:
		return pending
	for preview: SaveSlotPreview in _repository.list_previews(content.campaign_id, ""):
		if preview.source == SaveSlotPreview.PRIMARY and preview.status == SaveSlotPreview.VALID and preview.package_hash != content.package_hash and not SaveRepository.is_kept_backup(preview.slot_id) and _can_update_file(content.campaign_id, preview.slot_id, false, preview.package_hash, content.package_hash):
			pending.append(preview.slot_id)
	return pending


## Applies one batch entry; a failure is remembered so the save keeps loading on its original revision.
func apply_update(content: RealmzContent, slot_id: String) -> bool:
	_last_error = ""
	if content == null:
		return false
	var old_hash := _repository.recorded_package_hash(content.campaign_id, slot_id, false)
	if old_hash.is_empty() or old_hash == content.package_hash or not _can_update_file(content.campaign_id, slot_id, false, old_hash, content.package_hash):
		return false
	if _publish_update(content, slot_id, old_hash):
		# Decode the slot's new files now, so the batch's final listing stays quick.
		_repository.list_previews(content.campaign_id, "")
		return true
	_remember_failure(content.campaign_id, slot_id, false, old_hash)
	return false


func finish_updates() -> void:
	_batching = false
	_batch_checks.clear()


## Whether the last attempt to update this exact save file failed.
func update_failed(campaign_id: String, slot_id: String, backup: bool, old_hash: String) -> bool:
	return _failed_updates.has(_failure_key(campaign_id, slot_id, backup, old_hash))


func _can_update_file(campaign_id: String, slot_id: String, backup: bool, old_hash: String, current_hash: String) -> bool:
	return _can_update(campaign_id, old_hash, current_hash) and not update_failed(campaign_id, slot_id, backup, old_hash)


func _remember_failure(campaign_id: String, slot_id: String, backup: bool, old_hash: String) -> void:
	_failed_updates[_failure_key(campaign_id, slot_id, backup, old_hash)] = _last_error


func _failure_key(campaign_id: String, slot_id: String, backup: bool, old_hash: String) -> String:
	return "%s|%s|%s|%s|%s" % [campaign_id, slot_id, backup, old_hash, _repository.file_identity(campaign_id, slot_id, backup)]


## Runs an archive verification once per batch; outside a batch every call verifies again.
func _batch_check(key: String, check: Callable) -> Variant:
	if _batching and _batch_checks.has(key):
		return _batch_checks[key]
	var result: Variant = check.call()
	if _batching and result:
		_batch_checks[key] = result
	return result


func _publish_update(content: RealmzContent, slot_id: String, old_hash: String) -> bool:
	var updated := _updated_envelope(content, slot_id, false, old_hash)
	if updated == null:
		return false
	if not _repository.publish_update(content.campaign_id, slot_id, updated):
		_last_error = _repository.last_error
		return false
	return true


func _can_update(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	return _owner_update.eligible(campaign_id, old_hash, current_hash) or _record_update.eligible(campaign_id, old_hash, current_hash) or _compression_update.eligible(campaign_id, old_hash, current_hash) or _program_update.eligible(campaign_id, old_hash, current_hash) or _payment_update.eligible(campaign_id, old_hash, current_hash) or _marker_update.eligible(campaign_id, old_hash, current_hash) or _shop_update.eligible(campaign_id, old_hash, current_hash) or _half_truth_update.eligible(campaign_id, old_hash, current_hash)


func assign_legacy_slot(content: RealmzContent, envelope: SessionSnapshot, replacement_slot: String = "") -> String:
	_last_error = ""
	if content == null or not envelope is SaveEnvelope:
		_last_error = "A validated legacy save is required."
		return ""
	return _repository.copy_to_scenario_slot(content.campaign_id, envelope as SaveEnvelope, replacement_slot)


## Maintainer acceptance route: writes the verified update to a separate copy and leaves the source untouched.
func update_save(content: RealmzContent, slot_id: String, backup: bool = false) -> String:
	var updated := _updated_envelope(content, slot_id, backup, _repository.recorded_package_hash(content.campaign_id, slot_id, backup) if content != null else "")
	if updated == null:
		return ""
	var target_slot := _copy_slot
	if not _repository.save_new_copy(content.campaign_id, target_slot, updated):
		_last_error = _repository.last_error
		return ""
	var readback := _repository.load(content.campaign_id, target_slot, content.package_hash)
	if readback == null or readback.to_data() != updated.to_data():
		_last_error = "The copied save failed final readback."
		return ""
	return target_slot


## The verified save `slot_id` becomes under `content`, without writing anything.
func _updated_envelope(content: RealmzContent, slot_id: String, backup: bool, old_hash: String) -> SaveEnvelope:
	_last_error = ""
	_copy_slot = ""
	if content == null:
		return null
	if not old_hash.is_empty():
		if _owner_update.eligible(content.campaign_id, old_hash, content.package_hash):
			return _update_owner_corrected_save(content, slot_id, backup, old_hash)
		if _record_update.eligible(content.campaign_id, old_hash, content.package_hash):
			return _update_complete_record_save(content, slot_id, backup, old_hash)
		if _compression_update.eligible(content.campaign_id, old_hash, content.package_hash):
			return _update_compressed_save(content, slot_id, backup, old_hash)
		if _program_update.eligible(content.campaign_id, old_hash, content.package_hash):
			return _update_program_save(content, slot_id, backup, old_hash)
		if _payment_update.eligible(content.campaign_id, old_hash, content.package_hash):
			return _update_payment_save(content, slot_id, backup)
	var shop_transition := _shop_update.transition(content.campaign_id, content.package_hash)
	var marker_transition := _marker_update.transition(content.campaign_id, content.package_hash)
	var media_update := _half_truth_update.eligible(content.campaign_id, HalfTruthMediaSaveUpdate.OLD_PACKAGE_HASH, content.package_hash)
	if shop_transition.is_empty() and marker_transition.is_empty() and not media_update:
		_last_error = "This campaign revision has no verified save update."
		return null
	var transition_hash: String = marker_transition.previousPackage.packageHash if not marker_transition.is_empty() else (HalfTruthMediaSaveUpdate.OLD_PACKAGE_HASH if media_update else shop_transition.oldPackageHash)
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, transition_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	var valid := _marker_update.validate_archives(content) if not marker_transition.is_empty() else (_half_truth_update.validate_archives(content) if media_update else _shop_update.validate_archives(content))
	if not valid:
		_last_error = _marker_update.last_error if not marker_transition.is_empty() else (_half_truth_update.last_error if media_update else _shop_update.last_error)
		return null
	var target_slot := _marker_update.updated_slot_id(slot_id, backup, content.package_hash) if not marker_transition.is_empty() else (_half_truth_update.updated_slot_id(slot_id, backup) if media_update else _shop_update.updated_slot_id(slot_id, backup, content.package_hash))
	return _verified_update(content, original, target_slot)


func _update_compressed_save(content: RealmzContent, slot_id: String, backup: bool, old_hash: String) -> SaveEnvelope:
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, old_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	if not _batch_check("compression|%s|%s" % [old_hash, content.package_hash], _compression_update.validate_archives.bind(content)):
		_last_error = _compression_update.last_error
		return null
	return _verified_update(content, original, _compression_update.updated_slot_id(slot_id, backup, content.package_hash))


func _update_payment_save(content: RealmzContent, slot_id: String, backup: bool) -> SaveEnvelope:
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, _payment_update.previous_hash(), backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	if not _payment_update.validate_archives(content):
		_last_error = _payment_update.last_error
		return null
	return _verified_update(content, original, _payment_update.updated_slot_id(slot_id, backup, content.package_hash))


func _update_owner_corrected_save(content: RealmzContent, slot_id: String, backup: bool, old_hash: String) -> SaveEnvelope:
	# Verify the exact package chain before reading the save body.
	if not _batch_check("owner|%s|%s" % [old_hash, content.package_hash], _owner_update.validate_archives.bind(content, old_hash)):
		_last_error = _owner_update.last_error
		return null
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, old_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	return _verified_update(content, original, _owner_update.updated_slot_id(slot_id, backup, content.package_hash))


func _update_program_save(content: RealmzContent, slot_id: String, backup: bool, old_hash: String) -> SaveEnvelope:
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, old_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	if not _batch_check("program|%s|%s" % [old_hash, content.package_hash], _program_update.validate_archives.bind(content)):
		_last_error = _program_update.last_error
		return null
	return _verified_update(content, original, _program_update.updated_slot_id(slot_id, backup, content.package_hash))


func _update_complete_record_save(content: RealmzContent, slot_id: String, backup: bool, old_hash: String) -> SaveEnvelope:
	# Verify the exact package pair before reading or translating the save body.
	var pair: Dictionary = _batch_check("record|%s|%s" % [old_hash, content.package_hash], _record_update.validate_archives.bind(content, old_hash))
	if pair.is_empty():
		_last_error = _record_update.last_error
		return null
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, old_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return null
	var translator := CompleteRecordStateUpdate.new()
	var translated := translator.translate(original, pair, content.package_hash)
	if translated.is_empty():
		_last_error = translator.last_error
		return null
	return _verified_update(content, original, _record_update.updated_slot_id(slot_id, backup, content.package_hash), translated)


## Rebinds the save to `content` and requires an unchanged detached restoration.
## `copy_slot` names the separate copy an explicit acceptance update writes.
func _verified_update(content: RealmzContent, original: SaveEnvelope, copy_slot: String, translated_data: Dictionary = {}) -> SaveEnvelope:
	var source_data := original.to_data()
	var updated_data := source_data.duplicate(true) if translated_data.is_empty() else translated_data.duplicate(true)
	updated_data["packageHash"] = content.package_hash
	var updated := SaveEnvelope.from_data(updated_data)
	if updated == null:
		_last_error = "The updated save could not be decoded."
		return null
	var detached := GameSession.new()
	var restored := detached.restore(content, updated)
	if restored.state == SessionStep.State.FAILED:
		_last_error = "The corrected package cannot restore this save: %s" % restored.error_message
		return null
	var restored_data := SaveEnvelope.from_snapshot(detached.snapshot()).to_data()
	if not _same_gameplay_state(updated_data, restored_data):
		_last_error = "The updated save changed during detached restoration."
		return null
	_copy_slot = copy_slot
	return updated


func _same_gameplay_state(expected: Dictionary, snapshot: Dictionary) -> bool:
	for field: String in ["campaignId", "rulesVersion", "deviationIds", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "battleReturnContinuation", "sessionInteraction"]:
		if expected[field] != snapshot[field]:
			return false
	return true


func last_error() -> String:
	return _last_error if not _last_error.is_empty() else _repository.last_error
