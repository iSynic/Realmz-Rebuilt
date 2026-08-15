class_name SaveHostController
extends RefCounted

const SaveRepositoryScript := preload("res://src/infrastructure/saves/save_repository.gd")

var _repository: SaveRepository


func _init(repository: SaveRepository = null) -> void:
	_repository = repository if repository != null else SaveRepositoryScript.new()


func save(content: RealmzContent, slot_id: String, snapshot: SessionSnapshot) -> bool:
	if content == null:
		return false
	return _repository.save(content.campaign_id, slot_id, snapshot)


func load(content: RealmzContent, slot_id: String, backup: bool = false) -> SessionSnapshot:
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
	return result


func last_error() -> String:
	return _repository.last_error
