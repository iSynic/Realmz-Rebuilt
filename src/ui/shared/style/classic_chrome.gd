## Gives the classic screens the menu chrome: every bevelled stone panel and button in an
## application theme copy becomes a flat themed surface with a hairline border, and the
## parchment item ledger becomes dark rows. Margins are kept, so layouts do not move. The
## colours are the default palette's roles, which UiThemeService then recolours per theme.

class_name ClassicChrome
extends RefCounted

const SURFACE := Color(0.082, 0.133, 0.18, 0.98)
const RAISED := Color(0.102, 0.169, 0.224, 1.0)
const FIELD := Color(0.149, 0.247, 0.298, 1.0)
const SELECTED := Color(0.141, 0.204, 0.239, 1.0)
const BORDER := Color(0.165, 0.247, 0.302, 1.0)
const ACCENT := Color(0.867, 0.729, 0.416, 1.0)
const TEXT := Color(0.886, 0.886, 0.855, 1.0)
## Fill and border for each control state a bevelled style can stand for.
const STATES := {
	&"normal": [RAISED, Color(0.867, 0.729, 0.416, 0.5)], &"tab_unselected": [RAISED, BORDER], &"read_only": [RAISED, BORDER],
	&"hover": [FIELD, ACCENT], &"tab_hovered": [FIELD, ACCENT],
	&"pressed": [Color(0.867, 0.729, 0.416, 0.28), ACCENT], &"tab_selected": [Color(0.867, 0.729, 0.416, 0.28), ACCENT],
	&"disabled": [Color(0.082, 0.133, 0.18, 0.6), Color(0.165, 0.247, 0.302, 0.6)],
	&"tab_disabled": [Color(0.082, 0.133, 0.18, 0.6), Color(0.165, 0.247, 0.302, 0.6)],
}
## The parchment ledger styles, by "Type/style", and the fill and border that replace them.
const LEDGER := {
	"ClassicItemLedger/panel": [SURFACE, Color(0.867, 0.729, 0.416, 0.55)],
	"ClassicItemLedgerRow/panel": [RAISED, BORDER],
	"ClassicItemLedgerSelectedRow/panel": [SELECTED, ACCENT],
	"ClassicItemLedgerButton/hover": [Color(0.149, 0.247, 0.298, 0.6), Color(0.149, 0.247, 0.298, 0.0)],
	"ClassicTextWell/panel": [RAISED, BORDER],
	# A prompt standing on the message well wears the well's surface, not a black block.
	"ClassicTextboxOverlay/panel": [RAISED, BORDER],
	"ItemList/panel": [RAISED, BORDER],
}


static func modernize(theme: Theme) -> void:
	for type_name: StringName in theme.get_type_list():
		for style_name: StringName in theme.get_stylebox_list(type_name):
			var style := theme.get_stylebox(style_name, type_name)
			var key := "%s/%s" % [type_name, style_name]
			if style is StyleBoxTexture:
				theme.set_stylebox(style_name, type_name, _flat(type_name, style_name, style))
			elif LEDGER.has(key) and style is StyleBoxFlat:
				var copy := style.duplicate() as StyleBoxFlat
				copy.bg_color = LEDGER[key][0]
				copy.border_color = LEDGER[key][1]
				theme.set_stylebox(style_name, type_name, copy)
	# Equipped items read as a group: a warmer fill and an accent edge on the left.
	var equipped := theme.get_stylebox(&"panel", &"ClassicItemLedgerRow").duplicate() as StyleBoxFlat
	equipped.bg_color = FIELD
	equipped.border_color = ACCENT
	equipped.border_width_left = 3
	theme.set_type_variation(&"ClassicItemLedgerEquippedRow", &"PanelContainer")
	theme.set_stylebox(&"panel", &"ClassicItemLedgerEquippedRow", equipped)
	# In the trade and shop lists a row is only its name button, so that carries the shading.
	theme.set_type_variation(&"ClassicItemLedgerEquippedButton", &"ClassicItemLedgerButton")
	for state: StringName in [&"normal", &"pressed", &"disabled"]:
		theme.set_stylebox(state, &"ClassicItemLedgerEquippedButton", equipped)
	# A screen's main action is filled with the accent and lettered in the surface colour.
	theme.set_type_variation(&"ClassicPrimaryButton", &"Button")
	for state: StringName in [&"normal", &"hover", &"pressed"]:
		var main := theme.get_stylebox(&"normal", &"Button").duplicate() as StyleBoxFlat
		main.bg_color = ACCENT.lightened(0.14) if state == &"hover" else ACCENT.darkened(0.12) if state == &"pressed" else ACCENT
		main.border_color = ACCENT
		theme.set_stylebox(state, &"ClassicPrimaryButton", main)
	for color_name: StringName in [&"font_color", &"font_focus_color", &"font_hover_color", &"font_hover_pressed_color", &"font_pressed_color"]:
		theme.set_color(color_name, &"ClassicPrimaryButton", SURFACE)
	# The row itself shows which item is selected, so its name button draws no second box.
	theme.set_stylebox(&"focus", &"ClassicItemLedgerButton", StyleBoxEmpty.new())
	# Stat cells are lines in a column now, not boxes.
	var cell := theme.get_stylebox(&"panel", &"ClassicInventoryFactCell").duplicate() as StyleBoxFlat
	cell.bg_color = Color(RAISED, 0.0)
	cell.set_border_width_all(0)
	cell.border_width_bottom = 1
	cell.border_color = BORDER
	theme.set_stylebox(&"panel", &"ClassicInventoryFactCell", cell)
	# Ledger text was dark ink on paper.
	theme.set_color(&"font_color", &"ClassicItemLedgerButton", TEXT)
	for color_name: StringName in [&"font_focus_color", &"font_hover_color", &"font_hover_pressed_color", &"font_pressed_color"]:
		theme.set_color(color_name, &"ClassicItemLedgerButton", ACCENT)


static func _flat(type_name: StringName, style_name: StringName, bevel: StyleBox) -> StyleBoxFlat:
	var flat := StyleBoxFlat.new()
	var sunken := String(type_name).contains("Inset") or String(type_name).contains("Well") or String(type_name).contains("Badge") or String(type_name).begins_with("Slate")
	var colors: Array = STATES.get(style_name, [RAISED if sunken else SURFACE, Color(0.867, 0.729, 0.416, 0.55)])
	flat.bg_color = colors[0]
	flat.border_color = colors[1]
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(3)
	for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		flat.set_content_margin(side, bevel.get_margin(side))
	return flat
