## Supplies detached font choices and validated managed imports to presentation.
class_name ApplicationFontHost
extends RefCounted

var resolver := FontResolver.new()
var _repository: FontLibraryRepository
var _dialog: FontPickerDialog


func _init(directory: String = "user://fonts") -> void:
	_repository = FontLibraryRepository.new(directory)
	_refresh()


func bind(dialog: FontPickerDialog) -> void:
	_dialog = dialog
	dialog.resolver = resolver
	dialog.opened.connect(_refresh)
	dialog.import_requested.connect(_import)


func _refresh() -> void:
	var choices: Array[FontResolver.Choice] = []
	for record: Dictionary in _repository.list_fonts():
		choices.append(FontResolver.Choice.new("imported:" + String(record.id), String(record.name), "Imported"))
	choices.sort_custom(func(left: FontResolver.Choice, right: FontResolver.Choice) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	resolver.configure_imports(choices, _repository.font_path)
	if _dialog != null and not _repository.last_error.is_empty():
		_dialog.refresh_library(_repository.last_error)


func _import(path: String) -> void:
	var outcome := _repository.import_font(path)
	_refresh()
	_dialog.refresh_library("%s is already in your font library." % outcome.name if outcome.ok and outcome.duplicate else "Imported %s. Choose it from Imported to preview it." % outcome.name if outcome.ok else String(outcome.error))
