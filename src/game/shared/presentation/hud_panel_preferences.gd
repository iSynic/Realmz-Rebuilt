## Saved presentation choices for one retained HUD panel.
class_name HudPanelPreferences
extends RefCounted

var auto_hide := false
var background_opacity := 0.9
var reveal_on_hover := true
var reveal_on_changes := false
var custom_position := false
var position := Vector2.ZERO
var custom_size := false
var size_fraction := Vector2.ONE


func to_data() -> Dictionary:
	var result := {"autoHide": auto_hide, "backgroundOpacity": background_opacity,
		"revealOnHover": reveal_on_hover, "revealOnChanges": reveal_on_changes,
		"customPosition": custom_position, "x": position.x, "y": position.y}
	if custom_size: result["size"] = {"x": size_fraction.x, "y": size_fraction.y}
	return result


static func from_data(value: Variant) -> HudPanelPreferences:
	if not value is Dictionary:
		return null
	for key: String in ["autoHide", "revealOnHover", "revealOnChanges", "customPosition"]:
		if not value.get(key) is bool:
			return null
	for key: String in ["backgroundOpacity", "x", "y"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return null
		if float(number) < (0.4 if key == "backgroundOpacity" else 0.0) or float(number) > 1.0:
			return null
	var result := HudPanelPreferences.new()
	if value.has("size"):
		var dimensions: Variant = value["size"]
		if not dimensions is Dictionary: return null
		for axis: String in ["x", "y"]:
			var number: Variant = dimensions.get(axis)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) <= 0.0 or float(number) > 1.0: return null
		result.custom_size = true
		result.size_fraction = Vector2(dimensions["x"], dimensions["y"])
	result.auto_hide = value["autoHide"]
	result.background_opacity = float(value["backgroundOpacity"])
	result.reveal_on_hover = value["revealOnHover"]
	result.reveal_on_changes = value["revealOnChanges"]
	result.custom_position = value["customPosition"]
	result.position = Vector2(float(value["x"]), float(value["y"]))
	return result
