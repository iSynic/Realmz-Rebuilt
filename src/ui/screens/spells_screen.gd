## Owns the stable, editor-visible controls and content regions of the Spells screen.
class_name SpellsScreen
extends ScreenFrame

const BODY_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody"


func prepare_for_render() -> void:
	clear_rendered_content()
	character_area().visible = true
	section_area().visible = true
	notice_area().visible = true
	content_area().visible = true
	_alternate_content().visible = false


func prepare_alternate_layout() -> VBoxContainer:
	clear_rendered_content()
	character_area().visible = false
	section_area().visible = false
	notice_area().visible = false
	content_area().visible = false
	var alternate_content := _alternate_content()
	alternate_content.visible = true
	return alternate_content


func clear_rendered_content() -> void:
	_clear_children(character_area())
	_clear_children(section_area())
	_clear_children(notice_area())
	_clear_children(content_area())
	_clear_children(_alternate_content())
	for child: Node in body_control().get_children():
		if child not in [character_area(), section_area(), notice_area(), content_area(), _alternate_content()]:
			body_control().remove_child(child)
			child.queue_free()


func character_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/SpellCharacterArea") as VBoxContainer


func section_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/SpellSectionArea") as VBoxContainer


func notice_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/SpellNoticeArea") as VBoxContainer


func content_area() -> VBoxContainer:
	return get_node(BODY_PATH + "/SpellContentArea") as VBoxContainer


func _alternate_content() -> VBoxContainer:
	return get_node(BODY_PATH + "/SpellAlternateContent") as VBoxContainer


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
