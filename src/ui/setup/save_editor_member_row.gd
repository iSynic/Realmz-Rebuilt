## One roster entry in the save editor: Adventure settings or a party member.

class_name SaveEditorMemberRow
extends Button

## Selects this row's page: "" for Adventure settings, otherwise a character ID.
var page_id := ""


## `tag_role`: &"good" (joins), &"gold" (edits), &"bad" (leaves) or &"" for none.
func bind(id: String, title: String, detail: String, portrait: Texture2D, tag: String, tag_role: StringName, struck: bool) -> void:
	page_id = id
	var title_label := %Title as Label
	title_label.text = title
	title_label.theme_type_variation = &"VaultStatusMuted" if struck else &""
	(%Detail as Label).text = detail
	(%Portrait as TextureRect).texture = portrait
	(%Portrait as TextureRect).visible = portrait != null or not id.is_empty()
	(%Portrait as TextureRect).modulate.a = 0.45 if struck else 1.0
	var tag_label := %Tag as Label
	tag_label.text = tag
	tag_label.visible = not tag.is_empty()
	tag_label.theme_type_variation = {&"good": &"VaultStatusGood", &"bad": &"VaultStatusBad"}.get(tag_role, &"VaultStatusGold")
	accessibility_name = "%s. %s. %s" % [title, detail, tag]
	tooltip_text = detail


## The 800x600 portrait strip: portrait and tag only, with the name kept in the tooltip.
func set_strip(enabled: bool) -> void:
	var text := get_node("Row/Text") as Control
	var has_portrait := not page_id.is_empty()
	text.visible = not enabled or not has_portrait
	# The Adventure tile keeps its summary ("Hard · 1 ally"); portraits rely on their tag and tooltip.
	(%Detail as Control).visible = not enabled or not has_portrait
	custom_minimum_size = Vector2(64 if has_portrait else 150, 64) if enabled else Vector2(0, 56)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if enabled else Control.SIZE_EXPAND_FILL
	tooltip_text = "%s · %s" % [(%Title as Label).text, (%Detail as Label).text] if enabled else (%Detail as Label).text
