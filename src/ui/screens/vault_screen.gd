## Owns the stable, editor-visible Character Files library and inspection layout.
class_name VaultScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"

@export var character_card_scene: PackedScene
@export var history_row_scene: PackedScene


func prepare_list_layout(compact: bool) -> void:
	_clear_children(character_file_list())
	_clear_children(history_rows())
	header_area().visible = true
	list_area().visible = true
	history_area().visible = true
	inspection_area().visible = false
	empty_state().visible = false
	current_title().visible = true
	eligibility_context().visible = false
	history_title().visible = false
	character_file_list().columns = 1 if compact else 2


func prepare_inspection_layout() -> void:
	header_area().visible = false
	list_area().visible = false
	history_area().visible = false
	inspection_area().visible = true


func header_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultHeaderArea") as VBoxContainer


func list_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultListArea") as VBoxContainer


func history_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultHistoryArea") as VBoxContainer


func inspection_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultInspectionArea") as VBoxContainer


func list_back_button() -> Button:
	return get_node(BODY_PATH + "/VaultHeaderArea/CharacterFilesHeader/Back") as Button


func available_count() -> Label:
	return get_node(BODY_PATH + "/VaultHeaderArea/CharacterFilesHeader/AvailableCount") as Label


func empty_state() -> PanelContainer:
	return get_node(BODY_PATH + "/VaultListArea/VaultEmptyState") as PanelContainer


func current_title() -> Label:
	return get_node(BODY_PATH + "/VaultListArea/CurrentTitle") as Label


func eligibility_context() -> Label:
	return get_node(BODY_PATH + "/VaultListArea/EligibilityContext") as Label


func character_file_list() -> GridContainer:
	return get_node(BODY_PATH + "/VaultListArea/CharacterFileList") as GridContainer


func history_toggle() -> Button:
	return get_node(BODY_PATH + "/VaultHistoryArea/HistoryToggle") as Button


func history_title() -> Label:
	return get_node(BODY_PATH + "/VaultHistoryArea/HistoryTitle") as Label


func history_rows() -> VBoxContainer:
	return get_node(BODY_PATH + "/VaultHistoryArea/HistoryRows") as VBoxContainer


func inspection_back_button() -> Button:
	return get_node(BODY_PATH + "/VaultInspectionArea/InspectionHeader/Back") as Button


func inspection_heading() -> Label:
	return get_node(BODY_PATH + "/VaultInspectionArea/InspectionHeader/Heading") as Label


func inspection_eligibility() -> Label:
	return get_node(BODY_PATH + "/VaultInspectionArea/Eligibility") as Label


func character_sheet() -> ClassicCharacterSheet:
	return get_node(BODY_PATH + "/VaultInspectionArea/VaultCharacterSheet") as ClassicCharacterSheet


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
