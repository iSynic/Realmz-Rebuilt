## Keeps a bounded, presentation-only combat account visible through automatic turns.
class_name CombatActivityStrip
extends HBoxContainer

const MAX_LINES := 2000
const VISIBLE_LINES := 80

signal review_requested

@onready var _actor_icon: TextureRect = %ActorIcon
@onready var _actor_name: Label = %ActorName
@onready var _actor_vitals: Label = %ActorVitals
@onready var _target_icon: TextureRect = %PreviewTargetIcon
@onready var _target_name: Label = %PreviewTargetName
@onready var _target_vitals: Label = %PreviewTargetVitals
@onready var _log: RichTextLabel = %CombatLog
@onready var _status: Label = %CombatPlaybackStatus

var _battle_id := ""
var _facts: Dictionary = {}
var _lines: Array[String] = []
var _last_frame_id := 0
var _actor_id := ""
var _target_id := ""


func _ready() -> void:
	%ReviewLog.pressed.connect(func() -> void: review_requested.emit())


func has_battle() -> bool:
	return not _battle_id.is_empty()


func begin_battle(battle_id: String) -> void:
	if battle_id == _battle_id:
		return
	_battle_id = battle_id
	_facts.clear()
	_lines.clear()
	_last_frame_id = 0
	_actor_id = ""
	_target_id = ""
	_render_log()
	_render_previews(null)


func set_facts(facts: Dictionary) -> void:
	_facts.merge(facts, true)
	_render_previews(null)


func set_turn_actor(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	if actor_id != _actor_id:
		_target_id = ""
	_actor_id = actor_id
	_render_previews(null)


func set_compact(compact: bool) -> void:
	(%ActorPreview as Control).custom_minimum_size.x = 150.0 if compact else 240.0
	(%TargetPreview as Control).custom_minimum_size.x = 150.0 if compact else 240.0
	UiSizing.font_size(_log, &"normal_font_size", 12 if compact else 14)


func set_status(text: String) -> void:
	_status.text = text


func show_frame(frame: CombatPlaybackFrame) -> void:
	if frame == null or frame.get_instance_id() == _last_frame_id:
		return
	if not frame.actor_id.is_empty():
		_actor_id = frame.actor_id
	if frame.kind == &"actor_cue":
		_target_id = ""
	elif frame.kind == &"group_result":
		_target_id = ""
	elif not frame.target_id.is_empty() and frame.target_id != _actor_id:
		_target_id = frame.target_id
	_render_previews(frame)
	_last_frame_id = frame.get_instance_id()
	var line := _frame_line(frame)
	var entries: Array[String] = []
	if frame.kind == &"group_result":
		for child: CombatPlaybackFrame in frame.group_frames:
			entries.append(_frame_line(child))
	elif not line.is_empty():
		entries.append(line)
	for entry: String in entries:
		_lines.append(entry)
		if _lines.size() > MAX_LINES: _lines.pop_front()
	if not entries.is_empty(): _render_log()


func lines() -> Array[String]:
	return _lines.duplicate()


func _frame_line(frame: CombatPlaybackFrame) -> String:
	var actor := _name_for(frame.actor_id)
	var target := _name_for(frame.target_id)
	match frame.kind:
		&"battle_cue": return frame.display_text
		&"actor_cue":
			return "%s · %s" % [frame.display_text, actor] if not frame.display_text.is_empty() else "%s acts" % actor
		&"move_end": return "%s moved" % actor
		&"swap", &"retreat": return "%s · %s" % [actor, frame.display_text]
		&"melee_attack", &"projectile": return "%s attacks %s" % [actor, target]
		&"spell_cast": return "%s · %s" % [actor, frame.display_text]
		&"result":
			return "%s · %s" % [target if not frame.target_id.is_empty() else actor, frame.display_text]
		&"defeat": return "%s · %s" % [target, frame.display_text]
		&"field_changed": return frame.display_text
	return ""


func _name_for(combatant_id: String) -> String:
	if combatant_id.is_empty():
		return "Combatant"
	var facts: Dictionary = _facts.get(combatant_id, {})
	return String(facts.get("name", combatant_id))


func _render_previews(frame: CombatPlaybackFrame) -> void:
	_bind_preview(_actor_id, _actor_icon, _actor_name, _actor_vitals, frame, "Acting")
	_bind_preview(_target_id, _target_icon, _target_name, _target_vitals, frame, "Target")


func _bind_preview(combatant_id: String, icon: TextureRect, name_label: Label, vitals: Label, frame: CombatPlaybackFrame, heading: String) -> void:
	var facts: Dictionary = _facts.get(combatant_id, {})
	icon.texture = facts.get("icon") as Texture2D
	icon.visible = icon.texture != null
	name_label.text = "%s · %s" % [heading, _name_for(combatant_id)] if not combatant_id.is_empty() else "%s · —" % heading
	var maximum := int(facts.get("maximumHealth", 0))
	var health := int(frame.combatant_health[combatant_id]) if frame != null and frame.combatant_health.has(combatant_id) else int(facts.get("currentHealth", 0))
	var details: Array[String] = []
	if maximum > 0:
		details.append("ST %d/%d • AR %d" % [health, maximum, int(facts.get("armor", 0))])
	var weapon := String(facts.get("weapon", ""))
	if not weapon.is_empty():
		var charges := int(facts.get("weaponCharges", -1))
		details.append("%s%s" % [weapon, " • Charge %d" % charges if charges >= 0 else ""])
	var attacks := String(facts.get("attacks", ""))
	if not attacks.is_empty():
		details.append("%s attacks" % attacks)
	var conditions: Array = facts.get("conditions", [])
	if not conditions.is_empty():
		details.append(String(conditions[0]))
	if heading == "Target" and frame != null and frame.kind == &"result" and frame.target_id == combatant_id and not frame.display_text.is_empty():
		details.append(frame.display_text)
	vitals.text = "\n".join(details)


func _render_log() -> void:
	_log.text = "\n".join(_lines.slice(maxi(0, _lines.size() - VISIBLE_LINES)))
	_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))
