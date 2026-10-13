## Coordinates the managed library, bounded batch previews, and portable-art admission.
class_name ApplicationCharacterArtHost
extends RefCounted

var _repository: CharacterArtRepository
var _dialog_ref: WeakRef
var _media: PresentationMediaController
var _library: CharacterArtBundle
var _stock_entries: Array[Dictionary] = []
var _batch: CharacterArtImportBatch
var _batch_group := ""
var _generation := 0
var _busy := false
var _batch_textures: Dictionary = {}
var last_error := ""


func _init(repository: CharacterArtRepository = null) -> void:
	_repository = repository if repository != null else CharacterArtRepository.new()


func bind(dialog: CharacterArtDialog, media: PresentationMediaController) -> void:
	_dialog_ref = weakref(dialog)
	_media = media
	dialog.opened.connect(_open_library)
	dialog.sources_requested.connect(_open_sources)
	dialog.preview_requested.connect(_preview)
	dialog.batch_item_selected.connect(_select_batch_item)
	dialog.import_requested.connect(_import)
	dialog.batch_cancelled.connect(_cancel_batch)
	dialog.group_created.connect(_create_group)
	dialog.group_renamed.connect(_rename_group)
	dialog.group_removed.connect(func(name: String) -> void: _finish_edit(_repository.remove_group(name)))
	dialog.image_renamed.connect(func(group: String, id: String, label: String) -> void: _finish_edit(_repository.rename_image(group, id, label)))
	dialog.images_removed.connect(func(group: String, ids: PackedStringArray) -> void: _finish_edit(_repository.remove_images(group, ids)))
	refresh_media()


func set_stock_catalog(catalog: CharacterCatalog) -> void:
	var names := PackedStringArray()
	_stock_entries.clear()
	for race: RaceDefinition in catalog.race_definitions():
		if not DefinitionOptionView.from_race(race).available_for_creation:
			continue
		for kind: StringName in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
			for definition: CharacterAppearanceDefinition in catalog.appearance_definitions(kind):
				if definition.recommended_race_ids.has(race.id):
					if not names.has(race.name):
						names.append(race.name)
					_stock_entries.append({"id": definition.id, "label": definition.label, "kind": String(kind), "group": race.name, "builtin": true})
	_repository.set_stock_groups(names)
	refresh_media()
	if _dialog() != null and _dialog().visible and _batch == null:
		_bind_library()


func refresh_media() -> void:
	_library = _repository.media()
	if _media != null:
		_media.set_imported_character_art(_library, _repository.appearance_options())


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
	_cancel_batch()
	if not _repository.last_error.is_empty():
		_dialog().show_error(_repository.last_error)


func _bind_library() -> void:
	var entries := _stock_entries.duplicate(true)
	entries.append_array(_repository.entries())
	var catalog := _media.catalog() if _media != null else null
	for entry: Dictionary in entries:
		entry["texture"] = catalog.image_texture(catalog.asset_by_id(entry.id)) if catalog != null else null
	if _dialog() != null:
		_dialog().bind_library(_repository.groups(), entries)


func _open_sources(paths: PackedStringArray, kind: String, folder: bool) -> void:
	if _batch != null or _dialog() == null:
		return
	if folder:
		paths = CharacterArtImportBatch.folder_paths(paths[0]) if paths.size() == 1 else PackedStringArray()
	if paths.is_empty() or paths.size() > CharacterArtImportBatch.MAX_FILES:
		_dialog().show_error("Choose 1–256 PNG, JPEG or WebP images. Folder import uses only that folder, without subfolders.")
		return
	_batch = CharacterArtImportBatch.new(kind)
	_batch_group = _dialog().selected_group
	_generation += 1
	var generation := _generation
	_busy = true
	_bind_batch()
	for path: String in paths:
		await _dialog().get_tree().process_frame
		if generation != _generation or _dialog() == null:
			return
		_batch.append_file(path)
		_bind_batch()
	_busy = false
	_bind_batch()
	if not _batch.items.is_empty():
		_select_batch_item(0)


func _bind_batch() -> void:
	var rows: Array[Dictionary] = []
	for item: Dictionary in _batch.items:
		rows.append({"label": item.label, "error": item.error, "texture": _item_texture(item)})
	_dialog().bind_batch(rows, _batch.ready_count(), _busy)


func _select_batch_item(index: int) -> void:
	if _batch == null or index < 0 or index >= _batch.items.size():
		return
	var item := _batch.items[index]
	var source := item.source as CharacterArtImage
	_dialog().bind_batch_item(index, item.path.get_file(), source.image.get_size() if source != null else Vector2i.ZERO, item.mode, item.filter, item.crop)
	_dialog().bind_preview(_item_texture(item), item.error)


func _preview(index: int, mode: String, filter: String, crop: Rect2i) -> void:
	if _batch == null:
		return
	_batch.prepare_item(index, mode, filter, crop)
	_bind_batch()
	_select_batch_item(index)


func _import() -> void:
	if _batch == null or _busy:
		return
	if not _repository.import_batch(_batch, _batch_group):
		_dialog().show_error(_repository.last_error)
		return
	var count := _batch.ready_count()
	refresh_media()
	_cancel_batch()
	_dialog().show_error("Imported %d images. Identical images already in this race are kept once." % count)


func _cancel_batch() -> void:
	_generation += 1
	_batch = null
	_batch_textures.clear()
	_busy = false
	_bind_library()


func _create_group(name: String) -> void:
	if _repository.create_group(name):
		_dialog().selected_group = name.strip_edges()
		_finish_edit(true)
	else:
		_finish_edit(false)


func _rename_group(name: String, replacement: String) -> void:
	if _repository.rename_group(name, replacement):
		_dialog().selected_group = replacement.strip_edges()
		_finish_edit(true)
	else:
		_finish_edit(false)


func _finish_edit(success: bool) -> void:
	if not success:
		_dialog().show_error(_repository.last_error)
		return
	refresh_media()
	_bind_library()


func _item_texture(item: Dictionary) -> Texture2D:
	if item.png.is_empty():
		return null
	if not _batch_textures.has(item.id):
		var image := Image.new()
		_batch_textures[item.id] = ImageTexture.create_from_image(image) if image.load_png_from_buffer(item.png) == OK else null
	return _batch_textures[item.id] as Texture2D
