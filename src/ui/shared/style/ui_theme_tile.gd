## Lays the interface theme's background tile faintly over its parent panel's surface, beneath
## the panel's content, for a little texture. UiThemeService adds `ui_theme_tile.tscn` to every
## framed panel while the player's panel-texture preference is on.

class_name UiThemeTile
extends Control

const GROUP := &"ui_theme_tile_fill"

var _texture: Texture2D
var _strength := 0.0


## Shows `palette`'s tile at `strength` (0–1), or nothing when it has no texture or strength is 0.
func configure(palette: UiThemePalette, strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_texture = load(palette.background_texture) as Texture2D if palette != null and _strength > 0.0 and not palette.background_texture.is_empty() else null
	visible = _texture != null
	queue_redraw()


func _draw() -> void:
	var parent := get_parent_control()
	if _texture == null or parent == null:
		return
	draw_texture_rect(_texture, Rect2(-position, parent.size), true, Color(1.0, 1.0, 1.0, _strength))
