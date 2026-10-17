## Optional modular HUD configuration, isolated from adventure persistence.
class_name HudPreferences
extends RefCounted

enum PanelId { ROSTER, NARRATION, WORLD, PARTY }

const ORIENTATIONS: Array[String] = ["auto", "horizontal", "vertical"]

var strip_orientations: Array[String] = ["auto", "auto", "auto"]
var modular := false
var compact_commands := false
var effects_custom_position := false
var effects_position := Vector2.ZERO
var panels: Array[HudPanelPreferences] = []


func _init() -> void:
	for index: int in 4:
		var panel := HudPanelPreferences.new()
		panel.reveal_on_changes = index in [PanelId.ROSTER, PanelId.NARRATION]
		panels.append(panel)


func duplicate_value() -> HudPreferences:
	return from_data(to_data())


func to_data() -> Dictionary:
	var values: Array[Dictionary] = []
	for panel: HudPanelPreferences in panels:
		values.append(panel.to_data())
	var result := {"modular": modular, "compactCommands": compact_commands, "panels": values, "stripOrientations": strip_orientations.duplicate()}
	if effects_custom_position:
		result["effectsPosition"] = {"x": effects_position.x, "y": effects_position.y}
	return result


static func from_data(value: Variant) -> HudPreferences:
	if not value is Dictionary or not value.get("modular") is bool or not value.get("panels") is Array:
		return null
	if value["panels"].size() != 4:
		return null
	if not value.get("compactCommands", false) is bool:
		return null
	var result := HudPreferences.new()
	var orientations: Variant = value.get("stripOrientations", ["auto", "auto", "auto"])
	if not orientations is Array or orientations.size() != 3: return null
	for orientation: Variant in orientations:
		if not orientation is String or orientation not in ORIENTATIONS: return null
	result.strip_orientations.assign(orientations)
	result.modular = value["modular"]
	result.compact_commands = value.get("compactCommands", false)
	if value.has("effectsPosition"):
		var placement: Variant = value["effectsPosition"]
		if not placement is Dictionary: return null
		for axis: String in ["x", "y"]:
			var number: Variant = placement.get(axis)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0.0 or float(number) > 1.0: return null
		result.effects_custom_position = true
		result.effects_position = Vector2(placement["x"], placement["y"])
	for index: int in 4:
		var panel := HudPanelPreferences.from_data(value["panels"][index])
		if panel == null or (index in [PanelId.WORLD, PanelId.PARTY] and (panel.reveal_on_changes or panel.custom_size)):
			return null
		result.panels[index] = panel
	return result
