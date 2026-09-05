## Binds variable character-sheet records and media into the authored scene hierarchy.

class_name CharacterSheetSceneBinding
extends RefCounted


const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const GOOD := Color("75c889")
const BAD := Color("ef7770")

var text_scale: float = 1.0
var layout_profile: StringName = UiLayoutProfile.WIDE
var textures: Dictionary = {}
var media: ClassicMediaCatalog
var metric_row_scene: PackedScene
var record_card_scene: PackedScene
var item_card_scene: PackedScene
var spell_card_scene: PackedScene


func configure(next_textures: Dictionary, next_text_scale: float, next_layout_profile: StringName, next_media: ClassicMediaCatalog, metric_rows: PackedScene, record_cards: PackedScene, item_cards: PackedScene, spell_cards: PackedScene) -> void:
	textures = next_textures
	text_scale = next_text_scale
	layout_profile = next_layout_profile
	media = next_media
	metric_row_scene = metric_rows
	record_card_scene = record_cards
	item_card_scene = item_cards
	spell_card_scene = spell_cards


func bind_label(label: Label, text: String, color: Color = Color.WHITE, font_size: int = 15) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(font_size) * text_scale)))


func bind_existing_label(root: Node, path: NodePath, value: String, color: Color, font_size: int) -> void:
	bind_label(root.get_node(path) as Label, value, color, font_size)


func bind_identity_media(root: Node, path: NodePath, asset_id: String, fallback_text: String, role: String, minimum_size: Vector2) -> void:
	var frame := root.get_node(path) as PanelContainer
	var image := frame.get_child(0) as TextureRect
	var fallback := frame.get_child(1) as Label
	var texture := textures.get(asset_id) as Texture2D
	frame.custom_minimum_size = minimum_size
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	fallback.text = fallback_text if not fallback_text.is_empty() else "?"
	fallback.tooltip_text = "%s media unavailable." % role if texture == null else role
	bind_label(fallback, fallback.text, MUTED, 18)


func bind_appearance_media(frame: PanelContainer, asset_id: String, fallback_text: String, role: String) -> void:
	var image := frame.get_node("Image") as TextureRect
	var fallback := frame.get_node("Fallback") as Label
	var texture := textures.get(asset_id) as Texture2D
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	fallback.text = fallback_text if not fallback_text.is_empty() else "?"
	fallback.tooltip_text = "%s media unavailable." % role if texture == null else role
	bind_label(fallback, fallback.text, MUTED, 18)


func bind_metric_region(panel: PanelContainer, metrics: Array[CharacterMetricView], empty_text: String = "") -> void:
	var rows := panel.get_node("Content/MetricRows") as GridContainer
	clear_children(rows)
	bind_metric_rows(rows, metrics, empty_text)


func bind_metric_rows(parent: Container, metrics: Array[CharacterMetricView], empty_text: String = "") -> void:
	if metrics.is_empty() and not empty_text.is_empty():
		var empty_row := metric_row_scene.instantiate() as HBoxContainer
		bind_label(empty_row.get_node("MetricName") as Label, empty_text, MUTED, 13)
		empty_row.get_node("MetricValue").visible = false
		parent.add_child(empty_row)
		return
	for metric: CharacterMetricView in metrics:
		var row := metric_row_scene.instantiate() as HBoxContainer
		var name_label := row.get_node("MetricName") as Label
		var value_label := row.get_node("MetricValue") as Label
		bind_label(name_label, metric.name, MUTED, 14)
		bind_label(value_label, _metric_value_text(metric), GOOD if metric.value > 0 else BAD if metric.value < 0 else Color("e0e2e5"), 14)
		if not metric.detail.is_empty():
			name_label.tooltip_text = metric.detail
			value_label.tooltip_text = metric.detail
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if layout_profile == UiLayoutProfile.COMPACT else HORIZONTAL_ALIGNMENT_RIGHT
		parent.add_child(row)


func bind_item_region(frame: PanelContainer, items: Array[ItemView], empty_text: String) -> void:
	var content := frame.get_node("Content") as VBoxContainer
	bind_label(content.get_node("Header/Count") as Label, "%d item%s" % [items.size(), "" if items.size() == 1 else "s"], MUTED, 13)
	var rows := content.get_node("Items") as VBoxContainer
	clear_children(rows)
	if items.is_empty():
		var empty_card := record_card_scene.instantiate() as PanelContainer
		bind_label(empty_card.get_node("Content/Title") as Label, empty_text, MUTED, 13)
		empty_card.get_node("Content/Subtitle").visible = false
		empty_card.get_node("Content/Detail").visible = false
		rows.add_child(empty_card)
		return
	for item: ItemView in items:
		rows.add_child(_equipment_item_card(item))


func character_spell_card(spell: SpellView) -> PanelContainer:
	var panel := spell_card_scene.instantiate() as PanelContainer
	_bind_media_frame(panel.get_node("Content/Media") as PanelContainer, spell.icon_resource_type, spell.icon_id, "✦")
	bind_label(panel.get_node("Content/Text/Name") as Label, spell.name, GOLD, 15)
	bind_label(panel.get_node("Content/Text/Facts") as Label, "Level %d • %d SP • Range %d–%d" % [ClassicSpellLevel.from_classic_id(spell.classic_id), absi(spell.cost), spell.range_min, spell.range_max], Color("e0e2e5"), 12)
	bind_label(panel.get_node("Content/Text/Description") as Label, spell.description, MUTED, 12)
	return panel


func add_record_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var card := record_card_scene.instantiate() as PanelContainer
	bind_label(card.get_node("Content/Title") as Label, title, GOLD, 16)
	bind_label(card.get_node("Content/Subtitle") as Label, subtitle, Color("e0e2e5"), 14)
	var detail_label := card.get_node("Content/Detail") as Label
	detail_label.visible = not detail.is_empty()
	bind_label(detail_label, detail, MUTED, 13)
	parent.add_child(card)


func metric(metric_name: String, value: int, detail: String = "") -> CharacterMetricView:
	return CharacterMetricView.new(StringName(metric_name.to_lower().replace(" ", "-")), 0, metric_name, value, detail)


func recommended_appearance_first(options: Array[CharacterAppearanceOptionView], race_id: String) -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if option.is_recommended_for(race_id):
			result.append(option)
	for option: CharacterAppearanceOptionView in options:
		if not option.is_recommended_for(race_id):
			result.append(option)
	return result


func clear_option_button(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection["callable"] as Callable)
	picker.clear()


func clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


func clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _equipment_item_card(item: ItemView) -> PanelContainer:
	var panel := item_card_scene.instantiate() as PanelContainer
	panel.tooltip_text = "Item instance %s" % item.instance_id
	_bind_media_frame(panel.get_node("Content/Media") as PanelContainer, item.icon_resource_type, item.icon_id, "◈")
	var facts: Array[String] = ["Identified" if item.identified else "Unidentified"]
	if item.charges != 0:
		facts.append("%d charges" % item.charges)
	bind_label(panel.get_node("Content/Text/Name") as Label, item.name, GOLD, 15)
	bind_label(panel.get_node("Content/Text/Facts") as Label, " • ".join(facts), Color("e0e2e5"), 13)
	bind_label(panel.get_node("Content/Text/Meta") as Label, "%d weight • value %d" % [item.weight, item.value], MUTED, 12)
	return panel


func _metric_value_text(metric_value: CharacterMetricView) -> String:
	if metric_value.value in [0, 1] and metric_value.detail in ["Yes", "No"]:
		return metric_value.detail
	if not metric_value.detail.is_empty() and metric_value.name in ["Attacks / Round", "Movement", "Stamina", "Spell Points", "Load"]:
		return metric_value.detail
	if metric_value.detail == "Permanent":
		return "Permanent"
	return "%+d" % metric_value.value if metric_value.value > 0 else str(metric_value.value)


func _bind_media_frame(frame: PanelContainer, resource_type: String, resource_id: int, fallback_text: String) -> void:
	var asset: MediaAsset = media.asset_by_resource(resource_type, resource_id) if media != null and resource_id != 0 else null
	var texture := media.image_texture(asset) if asset != null else null
	var image := frame.get_node("Image") as TextureRect
	var fallback := frame.get_node("Fallback") as Label
	image.texture = texture
	image.visible = texture != null
	fallback.visible = texture == null
	bind_label(fallback, fallback_text, MUTED, 18)
