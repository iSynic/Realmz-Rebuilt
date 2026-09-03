## Owns the stable, editor-visible regions of the Character screen.
class_name CharacterScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"

@export var party_order_row_scene: PackedScene


func prepare_for_render() -> void:
	_clear_children(party_order_rows())
	party_order_summary().visible = false
	party_order_editor().visible = false
	character_sheet().visible = false
	empty_state().visible = false


func party_order_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/PartyOrderArea") as VBoxContainer


func character_sheet_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/CharacterSheetArea") as VBoxContainer


func party_order_summary() -> PanelContainer:
	return get_node(BODY_PATH + "/PartyOrderArea/PartyOrderSummary") as PanelContainer


func party_order_editor() -> PanelContainer:
	return get_node(BODY_PATH + "/PartyOrderArea/PartyOrderEditor") as PanelContainer


func party_order_rows() -> VBoxContainer:
	return get_node(BODY_PATH + "/PartyOrderArea/PartyOrderEditor/EditorContent/PartyOrderRows") as VBoxContainer


func character_sheet() -> ClassicCharacterSheet:
	return get_node(BODY_PATH + "/CharacterSheetArea/ClassicCharacterSheet") as ClassicCharacterSheet


func empty_state() -> PanelContainer:
	return get_node(BODY_PATH + "/CharacterSheetArea/CharacterEmptyState") as PanelContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
