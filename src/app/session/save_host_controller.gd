## Coordinates save host services at the application boundary.

class_name SaveHostController
extends RefCounted

var _repository: SaveRepository
var _half_truth_update: HalfTruthMediaSaveUpdate
var _shop_update: ShopSaveUpdate
var _last_error := ""


func _init(repository: SaveRepository = null, half_truth_update: HalfTruthMediaSaveUpdate = null, shop_update: ShopSaveUpdate = null) -> void:
	_repository = repository if repository != null else SaveRepository.new()
	_half_truth_update = half_truth_update if half_truth_update != null else HalfTruthMediaSaveUpdate.new()
	_shop_update = shop_update if shop_update != null else ShopSaveUpdate.new()


func save(content: RealmzContent, slot_id: String, snapshot: SessionSnapshot, preview_jpeg: PackedByteArray = PackedByteArray()) -> bool:
	_last_error = ""
	if content == null:
		return false
	return _repository.save(content.campaign_id, slot_id, snapshot, preview_jpeg)


func active_slot(content: RealmzContent) -> String:
	return _repository.active_slot(content.campaign_id) if content != null else "A"


func set_active_slot(content: RealmzContent, slot_id: String) -> bool:
	return content != null and _repository.set_active_slot(content.campaign_id, slot_id)


func load(content: RealmzContent, slot_id: String, backup: bool = false) -> SessionSnapshot:
	_last_error = ""
	if content == null:
		return null
	if backup:
		return _repository.load_backup(content.campaign_id, slot_id, content.package_hash)
	return _repository.load(content.campaign_id, slot_id, content.package_hash)


func previews(content: RealmzContent) -> Array[SaveSlotPreview]:
	if content == null:
		return []
	var result: Array[SaveSlotPreview] = []
	result.assign(_repository.list_previews(content.campaign_id, content.package_hash))
	for preview: SaveSlotPreview in result:
		preview.can_update = preview.status == SaveSlotPreview.PACKAGE_MISMATCH and (_half_truth_update.eligible(preview.campaign_id, preview.package_hash, content.package_hash) or _shop_update.eligible(preview.campaign_id, preview.package_hash, content.package_hash))
	return result


func assign_legacy_slot(content: RealmzContent, envelope: SessionSnapshot, replacement_slot: String = "") -> String:
	_last_error = ""
	if content == null or not envelope is SaveEnvelope:
		_last_error = "A validated legacy save is required."
		return ""
	return _repository.copy_to_scenario_slot(content.campaign_id, envelope as SaveEnvelope, replacement_slot)


func update_save(content: RealmzContent, slot_id: String, backup: bool = false) -> String:
	_last_error = ""
	if content == null:
		return ""
	var shop_transition := _shop_update.transition(content.campaign_id, content.package_hash)
	var media_update := _half_truth_update.eligible(content.campaign_id, HalfTruthMediaSaveUpdate.OLD_PACKAGE_HASH, content.package_hash)
	if shop_transition.is_empty() and not media_update:
		_last_error = "This campaign revision has no verified save update."
		return ""
	var old_hash: String = HalfTruthMediaSaveUpdate.OLD_PACKAGE_HASH if media_update else shop_transition.oldPackageHash
	var original := _repository.read_for_explicit_update(content.campaign_id, slot_id, old_hash, backup)
	if original == null:
		_last_error = _repository.last_error
		return ""
	var valid := _half_truth_update.validate_archives(content) if media_update else _shop_update.validate_archives(content)
	if not valid:
		_last_error = _half_truth_update.last_error if media_update else _shop_update.last_error
		return ""
	var source_data := original.to_data()
	var updated_data := source_data.duplicate(true)
	updated_data["packageHash"] = content.package_hash
	var updated := SaveEnvelope.from_data(updated_data)
	if updated == null:
		_last_error = "The updated save could not be decoded."
		return ""
	var detached := GameSession.new()
	var restored := detached.restore(content, updated)
	if restored.state == SessionStep.State.FAILED:
		_last_error = "The corrected package cannot restore this save: %s" % restored.error_message
		return ""
	var restored_data := SaveEnvelope.from_snapshot(detached.snapshot()).to_data()
	if not _same_gameplay_state(updated_data, restored_data):
		_last_error = "The updated save changed during detached restoration."
		return ""
	var target_slot := _half_truth_update.updated_slot_id(slot_id, backup) if media_update else _shop_update.updated_slot_id(slot_id, backup, content.package_hash)
	if not _repository.save_new_copy(content.campaign_id, target_slot, updated):
		_last_error = _repository.last_error
		return ""
	var readback := _repository.load(content.campaign_id, target_slot, content.package_hash)
	if readback == null or readback.to_data() != updated_data:
		_last_error = "The copied save failed final readback."
		return ""
	return target_slot


func _same_gameplay_state(expected: Dictionary, snapshot: Dictionary) -> bool:
	for field: String in ["campaignId", "rulesVersion", "deviationIds", "gameState", "rng", "scenarioVm", "scenarioActionState", "sessionContinuation", "battleReturnContinuation", "sessionInteraction"]:
		if expected[field] != snapshot[field]:
			return false
	return true


func last_error() -> String:
	return _last_error if not _last_error.is_empty() else _repository.last_error
