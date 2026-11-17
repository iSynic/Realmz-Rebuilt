## Builds the save editor's repeated rows: allies, changes and controller prompt glyphs.

class_name SaveEditorRows
extends RefCounted

const ALLY_ROW := "res://src/ui/setup/save_editor_ally_row.tscn"
const CHANGE_ROW := "res://src/ui/setup/save_editor_change_row.tscn"
const PROMPT := "res://src/ui/setup/save_editor_prompt.tscn"


## An ally: combat icon, name over detail, an optional Joins/Leaves tag and one action.
static func ally(title: String, detail: String, tag: String, action: String, icon: Texture2D, on_action: Callable) -> Control:
	var row := (load(ALLY_ROW) as PackedScene).instantiate() as Control
	# Every sprite is centred and scaled to fit the same square cell, whatever its source size.
	var art := row.get_node(^"Art") as TextureRect
	art.texture = icon
	art.modulate.a = 0.45 if tag == "Leaves" else 1.0
	_bind_text(row, title, detail, &"VaultStatusMuted" if tag == "Leaves" else &"")
	var tag_label := row.get_node(^"Tag") as Label
	tag_label.visible = not tag.is_empty()
	tag_label.text = tag
	tag_label.theme_type_variation = &"VaultStatusGood" if tag == "Joins" else &"VaultStatusBad"
	_bind_action(row, action, "%s %s." % [action, title], on_action)
	return row


## A listed change: label over detail with one action (Undo, or Open for a member's edits).
static func change(row_data: Dictionary, action: String, tooltip: String, on_action: Callable) -> Control:
	var row := (load(CHANGE_ROW) as PackedScene).instantiate() as Control
	_bind_text(row, RowFields.text(row_data, "label"), RowFields.text(row_data, "detail"), &"")
	(row.get_node(^"Text/Title") as Control).tooltip_text = "%s · %s" % [row_data.label, row_data.detail]
	_bind_action(row, action, tooltip, on_action)
	return row


## Controller glyph and caption pairs for the save editor. `member_page` names LB/RB "Tabs", else "Pages".
static func prompt_items(family: String, preferences: ControllerPreferences, member_page: bool) -> Array[PackedStringArray]:
	var triggers: Array = {ControllerPreferences.PROMPT_PLAYSTATION: ["L2", "R2"], ControllerPreferences.PROMPT_SWITCH: ["ZL", "ZR"]}.get(family, ["LT", "RT"])
	var items: Array[PackedStringArray] = [
		PackedStringArray(["D-pad", "Navigate"]),
		PackedStringArray([_label(preferences, family, &"realmz_controller_confirm", ControllerBindingLabels.face(&"south", family)), "Select"]),
		PackedStringArray([_label(preferences, family, &"realmz_controller_action_radial", ControllerBindingLabels.face(&"west", family)), "Undo"]),
		PackedStringArray(["%s/%s" % [_label(preferences, family, &"realmz_controller_section_previous", "LB"), _label(preferences, family, &"realmz_controller_section_next", "RB")], "Tabs" if member_page else "Pages"]),
		PackedStringArray(["%s/%s" % [_label(preferences, family, &"realmz_controller_character_previous", str(triggers[0])), _label(preferences, family, &"realmz_controller_character_next", str(triggers[1]))], "Party"]),
		PackedStringArray([_label(preferences, family, &"realmz_controller_workspace_radial", ControllerBindingLabels.face(&"north", family)), "Changes"]),
		PackedStringArray([_label(preferences, family, &"realmz_controller_system", "Start"), "Save"]),
		PackedStringArray([_label(preferences, family, &"realmz_controller_back", ControllerBindingLabels.face(&"east", family)), "Cancel"]),
	]
	return items


static func prompt(glyph_text: String, caption_text: String, glyph_style: StyleBox) -> Control:
	var row := (load(PROMPT) as PackedScene).instantiate() as Control
	var glyph := row.get_node(^"Glyph") as Label
	glyph.text = glyph_text
	if glyph_style != null:
		glyph.add_theme_stylebox_override(&"normal", glyph_style)
	(row.get_node(^"Caption") as Label).text = caption_text
	return row


## Trigger bindings report raw axes ("Axis 4+"); the familiar trigger names read better.
static func _label(preferences: ControllerPreferences, family: String, action: StringName, fallback: String) -> String:
	var text := ControllerBindingLabels.action(preferences, action, family, fallback)
	return fallback if text.begins_with("Axis") else text


## Title over detail; a "before → after" detail uses the row's arrow label instead.
static func _bind_text(row: Control, title: String, detail: String, title_variation: StringName) -> void:
	var label := row.get_node(^"Text/Title") as Label
	label.text = title
	label.theme_type_variation = title_variation
	var plain := row.get_node(^"Text/Detail") as Label
	var arrows := row.get_node(^"Text/Arrows") as ArrowLabel
	var has_arrow := detail.contains(" %s " % ArrowLabel.ARROW)
	plain.visible = not has_arrow
	arrows.visible = has_arrow
	plain.text = detail
	if has_arrow:
		arrows.set_arrow_text(detail, 12, &"VaultStatusMuted", true)


## An empty `text` hides the row's action.
static func _bind_action(row: Control, text: String, tooltip: String, on_action: Callable) -> void:
	var button := row.get_node(^"Action") as Button
	button.visible = not text.is_empty()
	button.text = text
	button.tooltip_text = tooltip
	if not text.is_empty():
		button.pressed.connect(on_action)


## The row in `list` holding keyboard or controller focus, or -1.
static func focused_index(list: Node) -> int:
	var owner := list.get_viewport().gui_get_focus_owner() if list.is_inside_tree() else null
	if owner == null or not list.is_ancestor_of(owner):
		return -1
	for index: int in list.get_child_count():
		if list.get_child(index) == owner or list.get_child(index).is_ancestor_of(owner):
			return index
	return -1


## Focuses the action of the row now at `index` (or the last row) after a list is rebuilt; false when none can take it.
static func focus_row(list: Node, index: int) -> bool:
	for candidate: int in range(mini(index, list.get_child_count() - 1), -1, -1):
		var row := list.get_child(candidate)
		if row.is_queued_for_deletion():
			continue
		for child: Node in row.get_children():
			if child is Button and (child as Button).visible and not (child as Button).disabled:
				(child as Button).grab_focus()
				return true
	return false
