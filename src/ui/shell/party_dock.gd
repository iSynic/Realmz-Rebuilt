## The collapsed party roster: a slim dock of portraits with stamina, spell-point and buff
## bars. Pointing at it asks for the full roster; bad news flashes the affected members.

class_name PartyDock
extends PanelContainer

signal expand_requested

const HOVER_DWELL_MS := 250

@export var entry_scene: PackedScene

var _hover_started_ms := -1
var _shown_health: Dictionary = {}

@onready var _entries: BoxContainer = $Entries


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover_started_ms = Time.get_ticks_msec())
	mouse_exited.connect(func() -> void: _hover_started_ms = -1)


func _process(_delta: float) -> void:
	if _hover_started_ms < 0 or not is_visible_in_tree():
		return
	# Children take the pointer too, so the dock's own exit signal is not the whole story.
	if not get_global_rect().has_point(get_global_mouse_position()):
		_hover_started_ms = -1
	elif Time.get_ticks_msec() - _hover_started_ms >= HOVER_DWELL_MS:
		_hover_started_ms = -1
		expand_requested.emit()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		expand_requested.emit()


## Shows one entry per member, in order; `members` are PartyDockEntry facts.
func present(members: Array[Dictionary], ui_scale: float) -> void:
	_shown_health.clear()
	while _entries.get_child_count() > members.size():
		var extra := _entries.get_child(_entries.get_child_count() - 1)
		_entries.remove_child(extra)
		extra.queue_free()
	while _entries.get_child_count() < members.size():
		_entries.add_child(entry_scene.instantiate())
	for index: int in members.size():
		(_entries.get_child(index) as PartyDockEntry).bind(members[index], ui_scale)
	reset_size()


## Flashes the entries of the members named in `ids`.
func flash(ids: Array[String], reduced_motion: bool) -> void:
	for child: Node in _entries.get_children():
		var entry := child as PartyDockEntry
		if ids.has(entry.character_id):
			entry.flash(reduced_motion)


## Follows combat playback: each stamina bar shows `health_by_id` as the frames arrive, and a
## member who has just lost stamina flashes then, not when the turn settles.
func present_playback_health(members: Array[CharacterView], health_by_id: Dictionary, reduced_motion: bool) -> void:
	for child: Node in _entries.get_children():
		var entry := child as PartyDockEntry
		for member: CharacterView in members:
			if member.id != entry.character_id or not health_by_id.has(member.id):
				continue
			var health := RowFields.number(health_by_id, member.id)
			var before := shown_health(member.id, member.current_health)
			_shown_health[member.id] = health
			entry.show_stamina(float(health) / maxf(1.0, member.maximum_health))
			if health < before:
				entry.flash(reduced_motion)


## The stamina playback last showed for a member, or `fallback` when it showed none.
func shown_health(character_id: String, fallback: int) -> int:
	return RowFields.number(_shown_health, character_id, fallback)
