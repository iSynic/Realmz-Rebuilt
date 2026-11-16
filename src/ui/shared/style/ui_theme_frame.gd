## Draws an interface theme's ornamental frame over its parent panel: a soft drop shadow
## for depth, then a nine-patch border tinted with the theme's accent. UiThemeService adds
## `ui_theme_frame.tscn` to every "ui_theme_frame" node; themes without frame art hide it.

class_name UiThemeFrame
extends Control

const GROUP := &"ui_theme_frame_fill"
const TEXTURES := {
	&"metal": "res://src/ui/shared/assets/ui/theme-frame-metal.png",
	&"flourish": "res://src/ui/shared/assets/ui/theme-frame-flourish.png",
	&"forged": "res://src/ui/shared/assets/ui/theme-frame-forged.png",
	&"vine": "res://src/ui/shared/assets/ui/theme-frame-vine.png",
	&"gilt": "res://src/ui/shared/assets/ui/theme-frame-gilt.png",
}
## Corner size as a share of the art's width (20 of 64 pixels); edges stretch between corners.
const CORNER_SHARE := 20.0 / 64.0
const SHADOW_SIZE := 10
const SHADOW_OFFSET := Vector2(0.0, 4.0)

var _border: StyleBoxTexture
var _shadow: StyleBoxFlat


## Shows `palette`'s frame, or nothing when it has no frame art.
func configure(palette: UiThemePalette) -> void:
	var path := ""
	if palette != null:
		path = palette.frame_texture if not palette.frame_texture.is_empty() else String(TEXTURES.get(palette.frame_style, ""))
	visible = not path.is_empty()
	if not visible:
		return
	_border = StyleBoxTexture.new()
	_border.texture = load(path) as Texture2D
	_border.draw_center = false
	_border.set_texture_margin_all(roundf(_border.texture.get_width() * CORNER_SHARE))
	_border.modulate_color = palette.colors[&"accent"] if palette.frame_tinted else Color.WHITE
	_shadow = StyleBoxFlat.new()
	_shadow.draw_center = false
	_shadow.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	_shadow.shadow_size = SHADOW_SIZE
	_shadow.shadow_offset = SHADOW_OFFSET
	queue_redraw()


func _draw() -> void:
	var parent := get_parent_control()
	if _border == null or parent == null:
		return
	var area := Rect2(-position, parent.size)
	draw_style_box(_shadow, area)
	draw_style_box(_border, area)
