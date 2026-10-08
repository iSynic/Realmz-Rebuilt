## Binds detached character facts to the editable Classic roster record.
class_name PartyRosterMemberRow
extends PanelContainer

@export var condition_badge_scene: PackedScene

var _compact_layout := false
var _condition_icon_ids: Array[int] = []
var _condition_icon_textures: Array[Texture2D] = []
var _condition_icon_labels: Array[String] = []


func _ready() -> void:
	$Character/Details/Record.minimum_size_changed.connect(_update_height)
	resized.connect(_apply_layout)
	_apply_layout()


func current_marker() -> ColorRect:
	return $Character/CurrentCharacterMarker as ColorRect


func character_button() -> Button:
	return $Character as Button


func selection_number() -> Label:
	return $Character/SelectionNumber as Label


func auto_toggle() -> Button:
	return $Character/CombatAuto as Button


func set_compact_layout(compact: bool) -> void:
	_compact_layout = compact
	if is_node_ready():
		_apply_layout()


func set_selected(selected: bool) -> void:
	$SelectionOutline.visible = selected


func bind_character(character: CharacterView, current_health: int, state_text: String) -> void:
	var spell_points := "%d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "—"
	var summary := "%s\nHP %d/%d • SP %s • ATK %s • AR %d\n%s / %s" % [
		character.name, current_health, character.maximum_health, spell_points,
		character.attacks_per_round, character.armor, character.race_name, character.caste_name,
	]
	character_button().text = summary
	character_button().accessibility_name = "%s. Level %d. Movement %d/%d. %s" % [
		summary, character.level, character.movement, character.maximum_movement, state_text,
	]
	$Character/Details/Record/IdentityCell/Identity/CharacterName.text = character.name
	$Character/Details/Record/IdentityCell/Identity/ArmorCell/Armor/Value.text = str(character.armor)
	$Character/Details/Record/CharacterRoleCell/CharacterRoleLine/CharacterRole.text = "%s / %s" % [character.race_name, character.caste_name]
	$Character/Details/Record/Vitals/HealthCell/Health/Value.text = "%d/%d" % [current_health, character.maximum_health]
	$Character/Details/Record/Vitals/HealthCell/Health/Value.modulate = Color("e66e6d") if current_health * 2 < character.maximum_health else Color.WHITE
	$Character/Details/Record/Vitals/SpellPointsCell/SpellPoints/Value.text = spell_points
	$Character/Details/Record/Actions/AttacksCell/Attacks/Value.text = character.attacks_per_round
	$Character/Details/Record/Actions/MovementCell/Movement/Value.text = "%d/%d" % [character.movement, character.maximum_movement]


func set_condition_icons(resource_ids: Array[int], textures: Array[Texture2D], labels: Array[String]) -> void:
	if resource_ids == _condition_icon_ids and textures == _condition_icon_textures and labels == _condition_icon_labels:
		return
	_condition_icon_ids.assign(resource_ids)
	_condition_icon_textures.assign(textures)
	_condition_icon_labels.assign(labels)
	_render_condition_icons()


func _render_condition_icons() -> void:
	var strip := $Character/Details/Record/CharacterRoleCell/CharacterRoleLine/ConditionIcons as HBoxContainer
	for child: Node in strip.get_children():
		strip.remove_child(child)
		child.free()
	var visible_indices: Array[int] = []
	if _compact_layout and _condition_icon_ids.size() > 2:
		var illness_index := _condition_icon_ids.find(181)
		if illness_index >= 0:
			visible_indices.append(illness_index)
	for index in _condition_icon_ids.size():
		if visible_indices.has(index):
			continue
		if _compact_layout and visible_indices.size() >= 2:
			break
		visible_indices.append(index)
	for index: int in visible_indices:
		if _condition_icon_textures[index] == null:
			continue
		var badge := condition_badge_scene.instantiate() as Control
		badge.name = "ConditionIcon%d" % _condition_icon_ids[index]
		(badge.get_node("Icon") as TextureRect).texture = _condition_icon_textures[index]
		badge.tooltip_text = _condition_icon_labels[index]
		strip.add_child(badge)
	if visible_indices.size() < _condition_icon_ids.size():
		var badge := condition_badge_scene.instantiate() as Control
		badge.name = "AdditionalConditions"
		badge.get_node("Icon").hide()
		var count := badge.get_node("Count") as Label
		count.text = "+%d" % (_condition_icon_ids.size() - visible_indices.size())
		count.show()
		strip.add_child(badge)
	strip.visible = strip.get_child_count() > 0


func _apply_layout() -> void:
	$Character/Details/Record/IdentityCell/Identity.vertical = _compact_layout
	var profile := UiSizing.profile_for(self)
	var available := size.x - 50.0 * (profile.bitmap_scale if profile != null else 1) - 12.0 * (profile.ui_scale if profile != null else 1.0)
	for grid: GridContainer in [$Character/Details/Record/Vitals, $Character/Details/Record/Actions]:
		grid.columns = 1 if _compact_layout or _natural_grid_width(grid) > available else 2
	_render_condition_icons()
	_update_height()


func _natural_grid_width(grid: GridContainer) -> float:
	var width := 0.0
	for cell: PanelContainer in grid.get_children():
		var fields := cell.get_child(0) as HBoxContainer
		var value := fields.get_node("Value") as Label
		width += value.get_theme_font("font").get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x + (fields.get_node("Caption") as Label).get_combined_minimum_size().x + fields.get_theme_constant("separation") + cell.get_theme_stylebox("panel").get_minimum_size().x
	return width


func _update_height() -> void:
	var profile := UiSizing.profile_for(self)
	var scale := profile.ui_scale if profile != null else 1.0
	custom_minimum_size.y = maxf(76.0 * scale, $Character/Details/Record.get_combined_minimum_size().y + 2.0 * scale)


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	var button := character_button()
	var native := button.get_meta("native_portrait") as Texture2D if button.has_meta("native_portrait") else null
	if native != null:
		var image := native.get_image()
		image.resize(image.get_width() * profile.bitmap_scale, image.get_height() * profile.bitmap_scale, Image.INTERPOLATE_NEAREST)
		button.icon = ImageTexture.create_from_image(image)
	var portrait_width := 50.0 * profile.bitmap_scale
	$Character/Details.offset_left = portrait_width + 6.0 * profile.ui_scale
	$Character/PortraitDivider.offset_left = portrait_width + 2.0 * profile.ui_scale
	$Character/PortraitDivider.offset_right = portrait_width + 3.0 * profile.ui_scale
	$Character/CombatAuto.offset_right = portrait_width
	_apply_layout()
