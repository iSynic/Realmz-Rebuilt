## Connects the managed artwork library to detached UI choices and import previews.
class_name ApplicationCharacterArtHost
extends RefCounted

var _repository: CharacterArtRepository
var _dialog_ref: WeakRef
var _media: PresentationMediaController
var _source: CharacterArtImage
var _library: CharacterArtBundle
var last_error := ""


func _init(repository: CharacterArtRepository = null) -> void:
	_repository = repository if repository != null else CharacterArtRepository.new()


func bind(dialog: CharacterArtDialog, media: PresentationMediaController) -> void:
	_dialog_ref = weakref(dialog)
	_media = media
	dialog.opened.connect(_open_library)
	dialog.source_requested.connect(_open_source)
	dialog.preview_requested.connect(_preview)
	dialog.import_requested.connect(_import)
	refresh_media()


func refresh_media() -> void:
	_library = _repository.media()
	if _media != null:
		_media.set_imported_character_art(_library, _library.appearance_options())


func install_bundle(bundle: CharacterArtBundle) -> bool:
	last_error = ""
	if bundle == null:
		last_error = "Character artwork is missing or invalid."
		return false
	if not _repository.install(bundle):
		last_error = _repository.last_error
		return false
	var changed := _library == null
	for asset: MediaAsset in bundle.assets():
		if _library == null or _library.asset_by_id(asset.id) == null:
			changed = true
	if changed:
		refresh_media()
	return true


func install_save_art(snapshot: SessionSnapshot) -> bool:
	return install_bundle((snapshot as SaveEnvelope).character_art) if snapshot is SaveEnvelope else true


func _dialog() -> CharacterArtDialog:
	return _dialog_ref.get_ref() as CharacterArtDialog if _dialog_ref != null else null


func _open_library() -> void:
	_source = null
	var dialog := _dialog()
	if dialog == null:
		return
	_bind_library()
	dialog.bind_source("Choose an image…", Vector2i.ZERO)
	dialog.bind_preview(null)


func _bind_library() -> void:
	var entries: Array[Dictionary] = _library.entries() if _library != null else []
	var catalog := _media.catalog()
	for entry: Dictionary in entries:
		entry["texture"] = catalog.image_texture(catalog.asset_by_id(entry.id))
	_dialog().bind_library(entries)


func _open_source(path: String) -> void:
	_source = CharacterArtImage.new()
	if not _source.open(path):
		_dialog().bind_source(path.get_file(), Vector2i.ZERO)
		_dialog().bind_preview(null, _source.last_error)
		return
	_dialog().bind_source(path.get_file(), _source.image.get_size())


func _preview(kind: String, mode: String, filter: String, crop: Rect2i) -> void:
	if _source == null or _source.image == null:
		return
	var prepared := _source.prepare(kind, mode, filter, crop)
	_dialog().bind_preview(ImageTexture.create_from_image(prepared) if prepared != null else null, _source.last_error)


func _import(group: String, label: String, kind: String, mode: String, filter: String, crop: Rect2i) -> void:
	var id := _repository.import_image(_source, group, label, kind, mode, filter, crop)
	if id.is_empty():
		_dialog().show_error(_repository.last_error if not _repository.last_error.is_empty() else "Choose an image first.")
		return
	refresh_media()
	_bind_library()
	_dialog().finish_import(id, kind)
