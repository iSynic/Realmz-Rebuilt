## Keeps complete character details available without crowding the roster.
extends Button

const TOOLTIP_SCENE := "res://src/ui/shell/party_roster_tooltip.tscn"


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := load(TOOLTIP_SCENE).instantiate() as PanelContainer
	var details := panel.get_node("Details") as Label
	details.text = for_text
	details.add_theme_font_override("font", get_theme_font("font", "ClassicRosterText"))
	return panel
