## Binds one fast-spell assignment to the reusable dock-slot scene.

class_name FastSpellDockSlot
extends Button

var _preview: TextureRect
var _key_label: Label


func configure(slot_index: int, binding: InteractionRequestValue.FastSpell, frames: Array) -> void:
	_bind_scene_nodes()
	disabled = not binding.enabled
	tooltip_text = "%s • Power %d%s" % [binding.spell_name, binding.power, "" if binding.enabled else " • %s" % binding.reason]
	_preview.name = "FastSpellDockPreview%d" % slot_index
	_preview.texture = frames[0] as Texture2D if not frames.is_empty() else null
	_key_label.name = "FastSpellDockKey%d" % slot_index
	_key_label.text = "%s · P%d" % ["0" if slot_index == 9 else str(slot_index + 1), binding.power]
	_key_label.add_theme_color_override("font_color", Color("f0ce59") if binding.enabled else Color("8c8170"))


func set_preview_texture(texture: Texture2D) -> void:
	_bind_scene_nodes()
	_preview.texture = texture


func _bind_scene_nodes() -> void:
	if _preview != null:
		return
	_preview = get_node("Content/Preview") as TextureRect
	_key_label = get_node("Content/KeyLabel") as Label
