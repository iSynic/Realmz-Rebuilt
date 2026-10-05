## Owns the retry controls for imports with multiple valid startup records.

extends RefCounted

signal selection_requested(directory: String, native_menu_selection: int, startup_file: String)

var _selection_row: HBoxContainer
var _selector: OptionButton
var _submit_button: Button
var _directory: String = ""
var _native_menu_selection: int = 0


func bind(panel: Control) -> void:
	_selection_row = panel.get_node("%StartupSelectionRow") as HBoxContainer
	_selector = panel.get_node("%StartupCandidateSelector") as OptionButton
	_submit_button = panel.get_node("%UseStartupCandidate") as Button
	_submit_button.pressed.connect(_submit_selected)


func present(operation: RefCounted, failed: bool) -> bool:
	_directory = operation.package_path
	_native_menu_selection = operation.native_menu_selection
	var candidates: Array[String] = operation.startup_candidates
	var required: bool = failed and operation.operation_name == &"import_scenario" and not candidates.is_empty()
	_selection_row.visible = required
	if required:
		_selector.clear()
		for candidate: String in candidates:
			_selector.add_item(candidate)
		_submit_button.disabled = not required
	return required


func _submit_selected() -> void:
	if _selector.selected < 0 or _selector.selected >= _selector.item_count:
		return
	selection_requested.emit(_directory, _native_menu_selection, _selector.get_item_text(_selector.selected))
