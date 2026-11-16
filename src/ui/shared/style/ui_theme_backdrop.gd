## Draws an interface theme's tiled background across the whole window, behind its parent's content: the texture, the theme's dimming
## colour and an edge vignette. UiThemeService adds `ui_theme_backdrop.tscn` to every
## "ui_theme_backdrop" node.

class_name UiThemeBackdrop
extends Control

const GROUP := &"ui_theme_backdrop_fill"

static var _vignette: GradientTexture2D

var _texture: Texture2D
var _dim := Color.TRANSPARENT


## Shows `palette`'s background, or nothing when it has no texture.
func configure(palette: UiThemePalette) -> void:
	_texture = load(palette.background_texture) as Texture2D if palette != null and not palette.background_texture.is_empty() else null
	_dim = Color(palette.colors[&"backdrop"], palette.background_dim) if _texture != null else Color.TRANSPARENT
	visible = _texture != null
	queue_redraw()


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	# A backdrop placed in a scene, not added by the service, picks up the theme by itself.
	if _texture == null:
		configure(UiThemeService.current())


func _draw() -> void:
	if _texture == null:
		return
	# The whole window, not only the parent: a screen inset inside the shell's frame would
	# otherwise leave a rim of the shell's own background around the tile.
	var area := get_global_transform().affine_inverse() * get_viewport_rect()
	draw_texture_rect(_texture, area, true)
	draw_rect(area, _dim)
	draw_texture_rect(_edge_vignette(), area, false)


static func _edge_vignette() -> GradientTexture2D:
	if _vignette == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.12), Color(0, 0, 0, 0.8)])
		_vignette = GradientTexture2D.new()
		_vignette.gradient = gradient
		_vignette.fill = GradientTexture2D.FILL_RADIAL
		_vignette.fill_from = Vector2(0.5, 0.45)
		_vignette.fill_to = Vector2(1.15, 0.45)
		_vignette.width = 256
		_vignette.height = 256
	return _vignette
