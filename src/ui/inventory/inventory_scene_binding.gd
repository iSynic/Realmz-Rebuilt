## Applies shared visual binding and scroll mechanics to authored Inventory scenes.
class_name InventorySceneBinding
extends RefCounted

var text_scale: float = 1.0


func appearance_texture(asset_id: String, media: ClassicMediaCatalog) -> Texture2D:
	if media == null or asset_id.is_empty():
		return null
	return media.image_texture(media.asset_by_id(asset_id))


func bind_label(label: Label, text: String, color: Color = Color.WHITE, size: int = 15) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * text_scale)))


func add_text_row(parent: Container, scene: PackedScene, text: String, color: Color, size: int = 13) -> Label:
	var row := scene.instantiate() as Label
	bind_label(row, text, color, size)
	parent.add_child(row)
	return row


func clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


func clear_command_connections(button: ClassicBitmapButton) -> void:
	for connection: Dictionary in button.command_requested.get_connections():
		button.command_requested.disconnect(connection["callable"] as Callable)


func clear_children(parent: Container) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func capture_item_scroll(parent: Container, rendered_character_id: String, selected_character_id: String, current_position: int) -> int:
	if rendered_character_id != selected_character_id:
		return current_position
	var scroll := parent.find_child("InventoryItemScroll", true, false) as ScrollContainer
	return scroll.scroll_vertical if scroll != null else current_position


func restore_item_scroll(scroll: ScrollContainer, desired_position: int) -> void:
	var scroll_ref: WeakRef = weakref(scroll)
	var tree := Engine.get_main_loop() as SceneTree
	tree.process_frame.connect(func() -> void:
		var current_scroll := scroll_ref.get_ref() as ScrollContainer
		if current_scroll == null or not current_scroll.is_inside_tree():
			return
		var current_bar := current_scroll.get_v_scroll_bar()
		var maximum := maxi(0, int(current_bar.max_value - current_bar.page))
		current_scroll.scroll_vertical = clampi(desired_position, 0, maximum)
	, CONNECT_ONE_SHOT)
