## Applies the chosen interface theme to menu-style screens (those under the vault, menu
## controls or main menu theme). Screens stay authored in the default palette; this recolours the two shared
## themes, every colour and style override on controls beneath them, and their backdrops, and
## keeps doing so for controls that enter the tree later.

class_name UiThemeService
extends RefCounted

const THEME_PATHS: Array[String] = ["res://src/ui/characters/vault_theme.tres", "res://src/ui/shared/style/menu_controls_theme.tres", "res://src/ui/setup/main_menu_typography.tres", HUD_THEME_PATH]
## The modular HUD's theme: recoloured like a menu, but its commands keep their own sounds.
const HUD_THEME_PATH := "res://src/ui/shared/style/modular_controls_theme.tres"
## Menu-look types that live in the classic application theme beside the in-game classic ones.
const MENU_TYPES: Array[StringName] = [&"MenuAction", &"MenuCaption", &"MenuHeading", &"MenuDialog"]
const BACKDROP_GROUP := &"ui_theme_backdrop"
## Authored colours, kept on each recoloured resource (copies made by `duplicate()` carry them).
const AUTHORED := &"ui_theme_authored"
## Per control: override name → [authored colour, colour last applied].
const APPLIED := &"ui_theme_applied"
## Set by this service on controls whose later override changes it listens for.
const WATCHED := &"ui_theme_watched"
## Scene-set on a control that copies its colour from the theme itself; it is left alone.
const FOLLOWS := &"ui_theme_follows"
const FRAME_GROUP := &"ui_theme_frame"
## Scene-set on an unframed surface (a footer, a well, a card) that takes the faint theme
## tile without a frame, while the player's panel-texture preference is on.
const TEXTURE_GROUP := &"ui_theme_textured"
const FRAME_SCENE := "res://src/ui/shared/style/ui_theme_frame.tscn"
const BACKDROP_SCENE := "res://src/ui/shared/style/ui_theme_backdrop.tscn"
const TILE_SCENE := "res://src/ui/shared/style/ui_theme_tile.tscn"
const STYLE_COLORS: Array[StringName] = [&"bg_color", &"border_color", &"shadow_color", &"color"]

static var _current: UiThemePalette
static var _themes: Array[Theme] = []
## True while a non-default theme is shown; otherwise nothing is touched.
static var _active := false
static var _tree: SceneTree
## Instance ids of controls waiting for the next deferred pass.
static var _pending: Dictionary = {}
static var _flush_queued := false
## Strength (0–1) of the theme tile laid over framed panels; 0 leaves them flat.
static var _tile_strength := 0.0
## Class name → [colour override names, style override names].
static var _override_names: Dictionary = {}


static func current() -> UiThemePalette:
	return _current if _current != null else UiThemeCatalog.default_palette()


## Switches to `theme_id` everywhere at once. Unknown ids give the default theme. Applying
## the theme already shown does nothing, so callers may apply on every settings save.
static func apply(tree: SceneTree, theme_id: String) -> void:
	var palette := UiThemeCatalog.by_id(theme_id)
	if palette.id == current().id and (not _active or tree == null or tree == _tree):
		return
	_active = true
	_current = palette
	_load_themes()
	for theme: Theme in _themes:
		_restyle_theme(theme)
	if tree != null:
		_watch(tree)
		_walk(tree.root, false)
		for node: Node in tree.get_nodes_in_group(UiThemeBackdrop.GROUP):
			(node as UiThemeBackdrop).configure(palette)
		for node: Node in tree.get_nodes_in_group(UiThemeFrame.GROUP):
			(node as UiThemeFrame).configure(palette)
		for node: Node in tree.get_nodes_in_group(UiThemeTile.GROUP):
			(node as UiThemeTile).configure(palette, _tile_strength)
	if palette.id == UiThemeCatalog.DEFAULT_ID:
		# Everything is back to its authored colours; stop watching until a theme is chosen again.
		_active = false
		_watch(null)
		_pending.clear()


## The player's panel-texture preference: lays the theme's background tile over every framed
## panel at `percent` strength, or takes it off. Themes without a tile stay flat.
static func set_surface_tile(tree: SceneTree, enabled: bool, percent: int) -> void:
	_tile_strength = clampf(percent / 100.0, 0.0, 1.0) if enabled else 0.0
	if tree == null:
		return
	for group: StringName in [FRAME_GROUP, TEXTURE_GROUP]:
		for node: Node in tree.get_nodes_in_group(group):
			if node is Control: _tile_for(node as Control, true)
	for node: Node in tree.get_nodes_in_group(UiThemeTile.GROUP):
		(node as UiThemeTile).configure(current(), _tile_strength)


## True for a control on a menu-style screen: its nearest themed ancestor uses a menu theme.
## The in-game modular HUD is themed but is not a menu screen.
static func is_menu_control(control: Control) -> bool:
	_load_themes()
	if control == null or not _is_themed(control):
		return false
	var node: Node = control
	while node != null:
		if node is Control and (node as Control).theme != null:
			return (node as Control).theme.resource_path != HUD_THEME_PATH
		node = node.get_parent()
	return false


static func _load_themes() -> void:
	if _themes.is_empty():
		for path: String in THEME_PATHS:
			_themes.append(load(path) as Theme)


static func _watch(tree: SceneTree) -> void:
	if _tree == tree:
		return
	if _tree != null and is_instance_valid(_tree) and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	_tree = tree
	if tree != null:
		tree.node_added.connect(_on_node_added)


## Themes a control the screen walk cannot reach (one under a CanvasLayer, or one wearing
## the application theme): recolours its style overrides and adds the frame or backdrop
## its groups ask for. Call it again whenever the control is shown.
static func decorate(control: Control) -> void:
	if _active:
		_restyle_control(control)
		return
	for style_name: StringName in _names_for(control)[1]:
		if control.has_theme_stylebox_override(style_name):
			restyle(control.get_theme_stylebox(style_name))


## Puts `surface` on a panel as its background (or takes it off when null) and shows the
## theme frame when `framed`.
static func dress(control: Control, surface: StyleBox, framed: bool) -> void:
	if surface != null: control.add_theme_stylebox_override("panel", surface)
	else: control.remove_theme_stylebox_override("panel")
	frame_for(control, framed)


## Shows or hides the theme frame on a panel that only sometimes wears one.
static func frame_for(control: Control, wanted: bool) -> void:
	var frame := control.get_node_or_null(^"UiThemeFrame") as UiThemeFrame
	if frame == null and wanted:
		frame = (load(FRAME_SCENE) as PackedScene).instantiate() as UiThemeFrame
		control.add_child(frame, false, Node.INTERNAL_MODE_BACK)
	if frame != null:
		frame.configure(current() if wanted else null)
	_tile_for(control, wanted)


## Adds, refreshes or clears the faint theme tile on a panel's surface.
static func _tile_for(control: Control, wanted: bool) -> void:
	var tile := control.get_node_or_null(^"UiThemeTile") as UiThemeTile
	if tile == null and wanted and _tile_strength > 0.0:
		tile = (load(TILE_SCENE) as PackedScene).instantiate() as UiThemeTile
		# First in draw order: over the panel's own surface, under everything it holds.
		control.add_child(tile, false, Node.INTERNAL_MODE_FRONT)
	if tile != null:
		tile.configure(current(), _tile_strength if wanted else 0.0)


## Recolours a style a themed control is about to use. Controls outside menu-style screens
## keep their authored colours, so shared code (UiSizing) can call this for every control.
static func restyle_for(control: Control, style: StyleBox) -> void:
	if style != null and (style.has_meta(AUTHORED) or (_active and control != null and _is_themed(control))):
		restyle(style)


## Recolours one style box for the current theme from its authored colours. A colour a script
## changes on an already recoloured style is not noticed; change the authored style instead.
static func restyle(style: StyleBox) -> void:
	# A style recoloured earlier is always brought to the current theme, even with the service
	# off: a copy cached while a theme was shown would otherwise bring that theme back.
	if style == null or (not _active and not style.has_meta(AUTHORED)):
		return
	var authored: Dictionary = style.get_meta(AUTHORED, {})
	if style is StyleBoxTexture:
		# Bevel and frame art is grey; it takes the theme's border hue through its tint.
		if not authored.has(&"modulate_color"):
			authored[&"modulate_color"] = (style as StyleBoxTexture).modulate_color
		var base := UiThemeCatalog.default_palette().colors[&"border"]
		var now := current().colors[&"border"]
		var tinted: Color = authored[&"modulate_color"]
		tinted = Color(tinted.r * clampf(now.r / base.r, 0.5, 2.0), tinted.g * clampf(now.g / base.g, 0.5, 2.0), tinted.b * clampf(now.b / base.b, 0.5, 2.0), tinted.a)
		if tinted != (style as StyleBoxTexture).modulate_color:
			(style as StyleBoxTexture).modulate_color = tinted
	for property: StringName in STYLE_COLORS:
		if not property in style:
			continue
		if not authored.has(property):
			authored[property] = style.get(property)
		# Setting an unchanged colour would still notify every control using the style.
		var authored_color: Color = authored[property]
		var shown := _recolor(authored_color)
		if shown != style.get(property):
			style.set(property, shown)
	style.set_meta(AUTHORED, authored)


## Recolours an application theme copy, classic types included, so the classic screens
## follow the interface theme. The default theme leaves it exactly as authored.
static func restyle_menu_types(theme: Theme) -> void:
	if _active and theme != null:
		_restyle_theme(theme)


static func _recolor(color: Color) -> Color:
	return current().recolor(color, UiThemeCatalog.default_palette())


## Recolours a shared theme through one merge. Changing its items one at a time would notify
## every control under it once per item, which takes many seconds on a full screen.
static func _restyle_theme(theme: Theme, only: Array[StringName] = []) -> void:
	var authored: Dictionary = theme.get_meta(AUTHORED, {})
	var recolored := Theme.new()
	for type_name: StringName in theme.get_type_list():
		if not only.is_empty() and not type_name in only:
			continue
		for color_name: StringName in theme.get_color_list(type_name):
			var color_key := "%s/%s" % [type_name, color_name]
			if not authored.has(color_key):
				authored[color_key] = theme.get_color(color_name, type_name)
			var authored_color: Color = authored[color_key]
			recolored.set_color(color_name, type_name, _recolor(authored_color))
		for style_name: StringName in theme.get_stylebox_list(type_name):
			var style_key := "%s//%s" % [type_name, style_name]
			if not authored.has(style_key):
				authored[style_key] = theme.get_stylebox(style_name, type_name)
			var authored_style: StyleBox = authored[style_key]
			var copy := authored_style.duplicate() as StyleBox
			restyle(copy)
			recolored.set_stylebox(style_name, type_name, copy)
	theme.set_meta(AUTHORED, authored)
	theme.merge_with(recolored)


static func _walk(node: Node, themed: bool) -> void:
	if node is Control:
		var own := (node as Control).theme
		# The nearest theme decides: a classic subtree inside a menu screen stays classic.
		if own != null:
			themed = own in _themes
			if not themed and own.has_color(&"font_color", &"MenuHeading"):
				restyle_menu_types(own)
		if themed:
			_restyle_control(node as Control)
	for child: Node in node.get_children(true):
		_walk(child, themed)


static func _on_node_added(node: Node) -> void:
	if node is Control:
		_queue(node.get_instance_id())


## Restyles a control on the next deferred pass, after scripts finished setting its overrides.
static func _queue(instance_id: int) -> void:
	if not _active:
		return
	_pending[instance_id] = true
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


static func _flush() -> void:
	_flush_queued = false
	var pending := _pending.keys()
	_pending.clear()
	if not _active:
		return
	for instance_id: int in pending:
		var control := instance_from_id(instance_id) as Control
		# The play screen's own surfaces keep their authored colours but still take the tile.
		if control != null and control.is_inside_tree() and control.is_in_group(TEXTURE_GROUP): _tile_for(control, true)
		if control != null and control.is_inside_tree() and _is_themed(control):
			_restyle_control(control)


static func _is_themed(control: Control) -> bool:
	var node: Node = control
	while node != null:
		if node is Control and (node as Control).theme != null:
			return (node as Control).theme in _themes
		node = node.get_parent()
	return false


static func _restyle_control(control: Control) -> void:
	# Overrides a script sets later (a resize, a rebind) come back through this hook.
	var watched: int = control.get_meta(WATCHED, 0)
	if watched != control.get_instance_id():
		control.set_meta(WATCHED, control.get_instance_id())
		control.theme_changed.connect(_queue.bind(control.get_instance_id()))
	var follows: bool = control.get_meta(FOLLOWS, false)
	if follows:
		return
	var names: Array = _names_for(control)
	var applied: Dictionary = control.get_meta(APPLIED, {})
	for color_name: StringName in names[0]:
		if control.has_theme_color_override(color_name):
			var current_color := control.get_theme_color(color_name)
			var shown := _remember(applied, color_name, current_color)
			# Only real changes are written: an override notifies the control, and screens that
			# rebuild on that notice would otherwise be restyled again without end.
			if shown != current_color:
				control.add_theme_color_override(color_name, shown)
	for style_name: StringName in names[1]:
		if control.has_theme_stylebox_override(style_name):
			var style := control.get_theme_stylebox(style_name)
			# A style saved in a file or inside a scene is shared by every control that loads it,
			# so this control gets a private copy and the shared one keeps its authored colours.
			if _is_shared_file(style):
				style = style.duplicate() as StyleBox
				control.add_theme_stylebox_override(style_name, style)
			restyle(style)
	if control is ColorRect:
		var fill := _remember(applied, &"@color", (control as ColorRect).color)
		if fill != (control as ColorRect).color:
			(control as ColorRect).color = fill
	if not applied.is_empty():
		control.set_meta(APPLIED, applied)
	if control.is_in_group(BACKDROP_GROUP) and control.get_node_or_null(^"UiThemeBackdrop") == null:
		var backdrop := (load(BACKDROP_SCENE) as PackedScene).instantiate() as UiThemeBackdrop
		control.add_child(backdrop, false, Node.INTERNAL_MODE_FRONT)
		backdrop.configure(_current)
	if control.is_in_group(FRAME_GROUP) and control.get_node_or_null(^"UiThemeFrame") == null:
		var frame := (load(FRAME_SCENE) as PackedScene).instantiate() as UiThemeFrame
		# Last in draw order, so the border sits over the panel's content edge.
		control.add_child(frame, false, Node.INTERNAL_MODE_BACK)
		frame.configure(_current)
	if control.is_in_group(FRAME_GROUP) or control.is_in_group(TEXTURE_GROUP): _tile_for(control, true)


static func _is_shared_file(style: StyleBox) -> bool:
	return not style.resource_path.is_empty()


## Records `current` as the authored colour unless it is the colour this service last applied,
## then returns the colour to show now.
static func _remember(applied: Dictionary, key: StringName, current_color: Color) -> Color:
	var entry: Array = applied.get(key, [])
	var authored: Color = entry[0] if entry.size() == 2 and current_color == entry[1] else current_color
	var shown := _recolor(authored)
	applied[key] = [authored, shown]
	return shown


static func _names_for(control: Control) -> Array:
	var class_key := control.get_class()
	if not _override_names.has(class_key):
		var colors: Array[StringName] = []
		var styles: Array[StringName] = []
		for property: Dictionary in control.get_property_list():
			var property_name := RowFields.text(property, "name")
			if property_name.begins_with("theme_override_colors/"):
				colors.append(StringName(property_name.trim_prefix("theme_override_colors/")))
			elif property_name.begins_with("theme_override_styles/"):
				styles.append(StringName(property_name.trim_prefix("theme_override_styles/")))
		_override_names[class_key] = [colors, styles]
	return _override_names[class_key]
