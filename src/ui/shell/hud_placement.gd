## Turns a pointer drop into a HUD placement: a fraction of the free space, caught by a
## window edge when the element is let go close to one.

class_name HudPlacement
extends RefCounted

const SNAP_DISTANCE := 28.0


## Writes element `index` into `draft` with its top-left at `location`. A positive `snap`
## catches the element on any window edge closer than that many pixels and re-orients it.
static func drop(draft: HudPreferences, index: int, location: Vector2, element_size: Vector2, area: Rect2, snap: float) -> void:
	var available := (area.size - element_size).max(Vector2.ZERO)
	var local := (location - area.position).clamp(Vector2.ZERO, available)
	var gaps := {&"left": local.x, &"right": available.x - local.x, &"top": local.y, &"bottom": available.y - local.y}
	var caught: StringName = &""
	for edge: StringName in gaps:
		if gaps[edge] <= snap and (caught == &"" or gaps[edge] < gaps[caught]):
			caught = edge
	if snap > 0.0:
		if gaps[&"left"] <= snap: local.x = 0.0
		elif gaps[&"right"] <= snap: local.x = available.x
		if gaps[&"top"] <= snap: local.y = 0.0
		elif gaps[&"bottom"] <= snap: local.y = available.y
	var fraction := Vector2(local.x / available.x if available.x > 0.0 else 0.0, local.y / available.y if available.y > 0.0 else 0.0)
	draft.place(index, fraction, caught if snap > 0.0 else &"")


## The window edge a stored fraction rests on, or &"" when it floats. A corner counts as
## a side edge when `prefer_sides` is set and as top or bottom otherwise.
static func edge(fraction: Vector2, prefer_sides: bool) -> StringName:
	var side: StringName = &"left" if fraction.x <= 0.001 else &"right" if fraction.x >= 0.999 else &""
	var end: StringName = &"top" if fraction.y <= 0.001 else &"bottom" if fraction.y >= 0.999 else &""
	if prefer_sides:
		return side if side != &"" else end
	return end if end != &"" else side

## The roster panel height that shows every party row: the rows plus whatever the panel
## surface, its margins and the roster's own frame add around them in the current theme.
static func roster_fit_height(panel: Control, roster: Control) -> float:
	var surface := panel.get_node("Surface") as Control
	var body := surface.get_node("Column/Body") as Control
	var scroll := roster.get_node("RosterColumn/PartyScroll") as Control
	var chrome := surface.get_combined_minimum_size().y - body.get_combined_minimum_size().y
	chrome += (body.get_node("Content") as Control).get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
	return (scroll.get_node("PartyList") as Control).get_combined_minimum_size().y + chrome
