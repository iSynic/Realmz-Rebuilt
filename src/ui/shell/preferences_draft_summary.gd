## Reads the Settings draft back onto its controls: tints the label of every changed setting,
## names the changes for the footer, and restores the page's settings to their defaults.

class_name PreferencesDraftSummary
extends RefCounted

const SETTING_META := &"setting_id"
## On a tinted label: the colour overrides it had before, to put back.
const TINT_META := &"draft_tint_previous"
const CHANGED_COLOR := Color(0.867, 0.729, 0.416, 1)
const LABEL_COLORS: Array[StringName] = [&"font_color", &"font_pressed_color", &"font_hover_color", &"font_hover_pressed_color", &"font_focus_color"]
const NAMED_CHANGES := 3


## Marks changed settings and returns the footer line, such as
## "2 unsaved changes · Interface theme, CRT effect".
static func refresh(workspace: Control, draft: PreferencesDraft) -> String:
	var titles: Array[String] = []
	for control: Control in _setting_controls(workspace, draft):
		var setting_id: StringName = control.get_meta(SETTING_META)
		var changed: bool = draft.values.get(setting_id) != draft.baseline.get(setting_id)
		var label := _label_for(control)
		if label == null:
			continue
		_tint(label, changed)
		var title := _title(label)
		if changed and not title.is_empty() and not titles.has(title):
			titles.append(title)
	if not draft.is_dirty():
		return "No unsaved changes"
	if titles.is_empty():
		return "Unsaved changes"
	var named := ", ".join(titles.slice(0, NAMED_CHANGES))
	if titles.size() > NAMED_CHANGES:
		named += " and %d more" % (titles.size() - NAMED_CHANGES)
	return "%d unsaved change%s · %s" % [titles.size(), "" if titles.size() == 1 else "s", named]


## Stages the default value of every setting that has a tagged control on these pages. Controller
## bindings, HUD layout, fonts, combat text and the indoor party icon keep their values.
static func restore_defaults(workspace: Control, draft: PreferencesDraft) -> void:
	var defaults := PresentationSettings.new()
	for control: Control in _setting_controls(workspace, draft):
		var setting_id: StringName = control.get_meta(SETTING_META)
		draft.set_value(setting_id, defaults.get(setting_id))


static func _setting_controls(workspace: Control, draft: PreferencesDraft) -> Array[Control]:
	var result: Array[Control] = []
	if workspace == null or draft == null or draft.values == null:
		return result
	for node: Node in workspace.find_children("*", "Control", true, false):
		if node.has_meta(SETTING_META) and String(node.get_meta(SETTING_META)) in draft.values:
			result.append(node as Control)
	return result


## A toggle carries its own label; a field's label is the caption that starts its row.
static func _label_for(control: Control) -> Control:
	if control is CheckButton:
		return control
	var row := control.get_parent()
	return row.get_child(0) as Label if row != null and row.get_child_count() > 0 else null


## The label's text without a trailing live value ("Combat speed  •  100%").
static func _title(label: Control) -> String:
	return String(label.get("text")).get_slice("  •", 0).strip_edges()


## Tints a changed setting's label and puts back whatever colour it had once it is unchanged.
static func _tint(label: Control, changed: bool) -> void:
	var tinted: bool = label.has_meta(TINT_META)
	if changed == tinted:
		return
	var names: Array[StringName] = LABEL_COLORS if label is CheckButton else ([&"font_color"] as Array[StringName])
	if changed:
		var previous := {}
		for color_name: StringName in names:
			if label.has_theme_color_override(color_name):
				previous[color_name] = label.get_theme_color(color_name)
			label.add_theme_color_override(color_name, CHANGED_COLOR)
		label.set_meta(TINT_META, previous)
		return
	var restored: Dictionary = label.get_meta(TINT_META)
	for color_name: StringName in names:
		if restored.has(color_name):
			label.add_theme_color_override(color_name, restored[color_name])
		else:
			label.remove_theme_color_override(color_name)
	label.remove_meta(TINT_META)
