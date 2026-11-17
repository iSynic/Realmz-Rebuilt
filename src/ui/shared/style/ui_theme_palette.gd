## One interface theme: twelve role colours, an optional tiled background and a frame style.
## Menu-style screens are authored in the default palette; other themes recolour them by role.

class_name UiThemePalette
extends RefCounted

const ROLES: Array[StringName] = [&"backdrop", &"surface", &"raised", &"border", &"field", &"selected", &"accent", &"accent_text", &"text", &"muted", &"good", &"bad"]

var id: String
var title: String
## Role name → colour, one entry per ROLES.
var colors: Dictionary[StringName, Color] = {}
## A texture repeated behind menu-style screens, or "" for the flat backdrop colour.
var background_texture := ""
## How strongly the backdrop colour covers the texture (0–1).
var background_dim := 0.0
## Which ornamental frame panels wear: &"plain" (none), &"metal", &"flourish", &"forged", &"vine" or &"gilt".
var frame_style: StringName = &"plain"
## Frame art made for this theme alone; when set it replaces the shared `frame_style` art.
var frame_texture := ""
## False when the frame art carries its own colours and must not be tinted with the accent.
var frame_tinted := true


func _init(theme_id: String, theme_title: String, hex: Array[String]) -> void:
	id = theme_id
	title = theme_title
	for index: int in ROLES.size():
		colors[ROLES[index]] = Color.html(hex[index])


func with_background(texture_path: String, dim: float, frames: StringName) -> UiThemePalette:
	background_texture = texture_path
	background_dim = dim
	frame_style = frames
	return self


func with_frame(frames: StringName) -> UiThemePalette:
	frame_style = frames
	return self


## `color` as authored in `from`, recoloured for this palette: the nearest role's colour here,
## keeping the authored shade's offset from that role and its alpha.
func recolor(color: Color, from: UiThemePalette) -> Color:
	if from == null or from.id == id:
		return color
	var nearest: StringName = ROLES[0]
	var best := INF
	for role: StringName in ROLES:
		var candidate := from.colors[role]
		var distance := Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b).length_squared()
		if distance < best:
			best = distance
			nearest = role
	var source := from.colors[nearest]
	var target := colors[nearest]
	return Color(clampf(target.r + color.r - source.r, 0.0, 1.0), clampf(target.g + color.g - source.g, 0.0, 1.0), clampf(target.b + color.b - source.b, 0.0, 1.0), color.a)
