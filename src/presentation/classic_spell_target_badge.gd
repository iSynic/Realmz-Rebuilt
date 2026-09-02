class_name ClassicSpellTargetBadge
extends PanelContainer

const TARGET_TEXT_SHADER_PATH := "res://src/presentation/assets/shaders/classic_spell_target_text.gdshader"

var _target_text_shader: Shader = load(TARGET_TEXT_SHADER_PATH) as Shader


func present(target_type: int, target_size: int, semantic_label: String, minimum_size: Vector2 = Vector2(48.0, 48.0)) -> bool:
	name = "ClassicSpellTargetBadge"
	theme_type_variation = &"ClassicSpellTargetBadge"
	custom_minimum_size = minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = semantic_label
	var asset_id := _asset_id(target_type, target_size)
	set_meta(&"target_asset_id", asset_id)
	var texture := ClassicUiAssetCatalog.texture(asset_id) if not asset_id.is_empty() else null
	if texture == null:
		return false
	var target_text := TextureRect.new()
	target_text.name = "ClassicSpellTargetText"
	target_text.texture = texture
	target_text.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	target_text.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	target_text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	target_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cutout := ShaderMaterial.new()
	cutout.shader = _target_text_shader
	target_text.material = cutout
	add_child(target_text)
	return true


static func _asset_id(target_type: int, target_size: int) -> StringName:
	if target_type == 5 and target_size == 0:
		return &"spells.target.self"
	return {
		7: &"spells.target.party",
		9: &"spells.target.all_friendly",
		10: &"spells.target.all_enemy",
		12: &"spells.target.everyone",
	}.get(target_type, &"")
