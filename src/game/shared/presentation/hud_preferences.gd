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
## The modular status strip (clock, position, gold, light, fatigue) and its background opacity.
var status_strip_visible := true
var status_strip_opacity := 0.85
## The party effects bar: active effects always show; this keeps the empty bar on screen too.
var effects_bar_visible := true
var effects_bar_opacity := 0.85
## Player placement of the status strip and the party dock, as fractions of the free space;
## without one the strip sits top centre and the dock follows the roster.
var status_strip_custom_position := false
var status_strip_position := Vector2.ZERO
var party_dock_custom_position := false
var party_dock_position := Vector2.ZERO
## Commands the player moved: command id to command bar (0 is the first), and command id
## to its rank within the bar (lower comes first). A command not listed keeps the bar its
## group belongs to and its usual place.
var command_buckets: Dictionary = {}
var command_order: Dictionary = {}
## How many command bars the modular HUD shows (2 to 4), with the settings and orientation
## of the third and fourth; those two float where the player puts them.
var bucket_count := 2
var extra_panels: Array[HudPanelPreferences] = [HudPanelPreferences.new(), HudPanelPreferences.new()]
var extra_orientations: Array[String] = ["auto", "auto"]


func _init() -> void:
	for index: int in 4:
		var panel := HudPanelPreferences.new()
		panel.reveal_on_changes = index in [PanelId.ROSTER, PanelId.NARRATION]
		panels.append(panel)


## The overworld HUD a new or reset profile starts with (`HudDefaultLayouts.OVERWORLD`).
## `HudPreferences.new()` stays the plain docked arrangement that saved settings are read over.
static func overworld_default() -> HudPreferences:
	var result := from_data(HudDefaultLayouts.OVERWORLD.duplicate(true))
	return result if result != null else HudPreferences.new()


## The combat HUD's starting arrangement (`HudDefaultLayouts.COMBAT`): the roster tucks away
## to its dock until wanted, so the battlefield stays clear, and the pieces start enlarged.
static func combat_default() -> HudPreferences:
	var result := from_data(HudDefaultLayouts.COMBAT.duplicate(true))
	if result != null:
		return result
	result = HudPreferences.new()
	result.panels[PanelId.ROSTER].auto_hide = true
	result.adopt_combat_scales()
	return result


## The battle deck's pieces start larger than the interface: the combatant card and turn
## order (panels 1 and 2) by a quarter, the command groups (panel 3 and both extra panels) by
## a half. The roster keeps its ordinary size. Also applied to a combat HUD saved before
## scales existed, and by the piece menu's reset.
func adopt_combat_scales() -> void:
	for index: int in range(1, 6):
		panel_at(index).scale = 1.25 if index < 3 else 1.5
	# The extra panels are only saved with all four bars counted.
	bucket_count = 4


## Records where the player put a HUD element: 0-3 are the panels, 4 the effects bar, 5 the
## status strip and 6 the party dock. `fraction` is its place within the free space. When
## `edge` names the window edge it was dropped on (&"left", &"right", &"top", &"bottom"),
## the command bars and the effects bar turn to run along that edge.
func place(index: int, fraction: Vector2, edge: StringName) -> void:
	if index < 4:
		panels[index].custom_position = true
		panels[index].position = fraction
	elif index == 4:
		effects_custom_position = true
		effects_position = fraction
	elif index == 5:
		status_strip_custom_position = true
		status_strip_position = fraction
	elif index == 6:
		party_dock_custom_position = true
		party_dock_position = fraction
	else:
		extra_panels[index - 7].custom_position = true
		extra_panels[index - 7].position = fraction
	var turned := "vertical" if edge in [&"left", &"right"] else "horizontal"
	if edge != &"" and index >= 2 and index <= 4: strip_orientations[index - 2] = turned
	elif edge != &"" and index >= 7: extra_orientations[index - 7] = turned


## The orientation of placement element `index` ("auto" when it has none to set): 2-4 are
## the first two command bars and the effects bar, 7 and 8 the extra command bars.
func orientation_of(index: int) -> String:
	if index >= 2 and index <= 4: return strip_orientations[index - 2]
	return extra_orientations[index - 7] if index >= 7 else "auto"


func set_orientation(index: int, value: String) -> void:
	if index >= 2 and index <= 4: strip_orientations[index - 2] = value
	elif index >= 7: extra_orientations[index - 7] = value


## The settings of HUD panel `index`: 0-3 the fixed four, 4 and 5 the extra command bars.
func panel_at(index: int) -> HudPanelPreferences:
	return panels[index] if index < 4 else extra_panels[index - 4]


## Returns every element to its automatic place, size and orientation.
func reset_placement() -> void:
	for panel: HudPanelPreferences in panels:
		panel.custom_position = false
		panel.custom_size = false
	strip_orientations.assign(["auto", "auto", "auto"])
	effects_custom_position = false
	status_strip_custom_position = false
	party_dock_custom_position = false
	command_buckets.clear()
	command_order.clear()
	extra_orientations.assign(["auto", "auto"])
	for panel: HudPanelPreferences in extra_panels:
		panel.custom_position = false


func duplicate_value() -> HudPreferences:
	return from_data(to_data())


func to_data() -> Dictionary:
	var values: Array[Dictionary] = []
	for panel: HudPanelPreferences in panels:
		values.append(panel.to_data())
	var result := {"modular": modular, "compactCommands": compact_commands, "panels": values, "stripOrientations": strip_orientations.duplicate()}
	result["statusStrip"] = {"visible": status_strip_visible, "opacity": status_strip_opacity}
	result["effectsBar"] = {"visible": effects_bar_visible, "opacity": effects_bar_opacity}
	if effects_custom_position:
		result["effectsPosition"] = {"x": effects_position.x, "y": effects_position.y}
	if status_strip_custom_position:
		result["statusStripPosition"] = {"x": status_strip_position.x, "y": status_strip_position.y}
	if party_dock_custom_position:
		result["partyDockPosition"] = {"x": party_dock_position.x, "y": party_dock_position.y}
	if not command_buckets.is_empty():
		result["commandBuckets"] = command_buckets.duplicate()
	if not command_order.is_empty():
		result["commandOrder"] = command_order.duplicate()
	if bucket_count != 2:
		result["bucketCount"] = bucket_count
		result["extraPanels"] = [extra_panels[0].to_data(), extra_panels[1].to_data()]
		result["extraOrientations"] = extra_orientations.duplicate()
	return result


static func from_data(value: Variant) -> HudPreferences:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	if not data.get("modular") is bool or not data.get("panels") is Array:
		return null
	var stored_panels: Array = data["panels"]
	if stored_panels.size() != 4:
		return null
	if not data.get("compactCommands", false) is bool:
		return null
	var result := HudPreferences.new()
	var orientations: Variant = data.get("stripOrientations", ["auto", "auto", "auto"])
	if not orientations is Array: return null
	var turns: Array = orientations
	if turns.size() != 3: return null
	for orientation: Variant in turns:
		if not orientation is String or orientation not in ORIENTATIONS: return null
	result.strip_orientations.assign(turns)
	result.modular = data["modular"]
	result.compact_commands = data.get("compactCommands", false)
	for key: String in ["effectsPosition", "statusStripPosition", "partyDockPosition"]:
		if not data.has(key): continue
		var placement: Variant = data[key]
		if not placement is Dictionary: return null
		var spot: Dictionary = placement
		for axis: String in ["x", "y"]:
			var number: Variant = spot.get(axis)
			if not (number is int or number is float) or not is_finite(float(number)) or float(number) < 0.0 or float(number) > 1.0: return null
		result.place(4 if key == "effectsPosition" else 5 if key == "statusStripPosition" else 6, Vector2(placement["x"], placement["y"]), &"")
	if not _read_extra_bars(data, result): return null
	for key: String in ["commandBuckets", "commandOrder"]:
		var moved: Variant = data.get(key, {})
		if not moved is Dictionary: return null
		for command: Variant in moved:
			var number: Variant = moved[command]
			if not command is String or not (number is int or number is float) or not is_finite(float(number)): return null
			if key == "commandBuckets" and not int(number) in [0, 1, 2, 3]: return null
			if key == "commandBuckets": result.command_buckets[command] = int(number)
			else: result.command_order[command] = float(number)
	var strip := _surface(data, "statusStrip", result.status_strip_visible, result.status_strip_opacity)
	var effects := _surface(data, "effectsBar", result.effects_bar_visible, result.effects_bar_opacity)
	if strip.is_empty() or effects.is_empty(): return null
	result.status_strip_visible = strip[0]
	result.status_strip_opacity = strip[1]
	result.effects_bar_visible = effects[0]
	result.effects_bar_opacity = effects[1]
	for index: int in 4:
		var panel := HudPanelPreferences.from_data(stored_panels[index])
		if panel == null or (index in [PanelId.WORLD, PanelId.PARTY] and (panel.reveal_on_changes or panel.custom_size)):
			return null
		result.panels[index] = panel
	return result


## Reads an optional {visible, opacity} entry as [visible, opacity]; empty when it is malformed.
static func _surface(value: Dictionary, key: String, default_visible: bool, default_opacity: float) -> Array:
	if not value.has(key):
		return [default_visible, default_opacity]
	var entry: Variant = value[key]
	if not entry is Dictionary:
		return []
	var surface: Dictionary = entry
	if not surface.get("visible") is bool:
		return []
	var opacity: Variant = surface.get("opacity")
	if not (opacity is int or opacity is float) or not is_finite(float(opacity)) or float(opacity) < 0.0 or float(opacity) > 1.0:
		return []
	return [surface["visible"], float(opacity)]


## Reads the optional bar count and the two extra bars into `result`; false when malformed.
static func _read_extra_bars(value: Dictionary, result: HudPreferences) -> bool:
	var count: Variant = value.get("bucketCount", 2)
	if not (count is int or count is float) or not int(count) in [2, 3, 4]: return false
	result.bucket_count = int(count)
	var stored_extras: Variant = value.get("extraPanels", [])
	var stored_turns: Variant = value.get("extraOrientations", ["auto", "auto"])
	if not stored_extras is Array or not stored_turns is Array: return false
	var extras: Array = stored_extras
	var turns: Array = stored_turns
	if extras.size() > 2 or turns.size() != 2: return false
	for index: int in extras.size():
		var extra := HudPanelPreferences.from_data(extras[index])
		if extra == null or extra.reveal_on_changes or extra.custom_size: return false
		result.extra_panels[index] = extra
	for turn: Variant in turns:
		if not turn is String or turn not in ORIENTATIONS: return false
	result.extra_orientations.assign(turns)
	return true
