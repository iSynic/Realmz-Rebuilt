## Owns the stable, editor-visible regions of the Character screen.
class_name CharacterScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func prepare_for_render() -> void:
	_clear_children(party_order_area())
	_clear_children(character_sheet_area())


func party_order_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/PartyOrderArea") as VBoxContainer


func character_sheet_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/CharacterSheetArea") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
