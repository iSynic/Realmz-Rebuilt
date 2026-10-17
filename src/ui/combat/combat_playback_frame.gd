## Presents combat playback frame through the Godot interface.

class_name CombatPlaybackFrame
extends RefCounted

var kind: StringName
var duration_seconds: float
var progress: float = 0.0
var actor_id: String = ""
var target_id: String = ""
var camera_focus_id: String = ""
var from_coordinate := Vector2i(-1, -1)
var to_coordinate := Vector2i(-1, -1)
var combatant_positions: Dictionary = {}
var summoned_monsters: Dictionary = {}
var summoned_sizes: Dictionary = {}
var hidden_combatant_ids: Array[String] = []
var persistent_fields: Array[PersistentCombatFieldView] = []
var combatant_health: Dictionary = {}
var combatant_backdrops: Dictionary = {}
var active_combatant_id := ""
var result_kind: StringName = &""
var display_text: String = ""
var display_amount: int = 0
var damage_type: int = 0
var effect_resource_type: String = "cicn"
var effect_resource_id: int = 0
var force_recipient_backdrop := false
var battle_tile_id: int = 0
var sound_event: DomainEvent
var automatic: bool = false
var group_frames: Array[CombatPlaybackFrame] = []


func _init(frame_kind: StringName, frame_duration_seconds: float) -> void:
	kind = frame_kind
	duration_seconds = maxf(frame_duration_seconds, 0.0)


func include_effect(frame: CombatPlaybackFrame) -> void:
	if frame == null or frame == self or group_frames.has(frame): return
	group_frames.append(frame)
	if frame.combatant_health.has(frame.target_id):
		combatant_health[frame.target_id] = frame.combatant_health[frame.target_id]
	if frame.combatant_backdrops.has(frame.target_id):
		combatant_backdrops[frame.target_id] = frame.combatant_backdrops[frame.target_id]


func has_numeric_result() -> bool:
	return display_amount > 0 and result_kind in [&"damage", &"elemental_damage", &"saved", &"healing"]


func position_for(combatant_id: String) -> Vector2i:
	var value: Variant = combatant_positions.get(combatant_id)
	if value is Vector2i:
		return value
	return Vector2i(-1, -1)


func hides(combatant_id: String) -> bool:
	return hidden_combatant_ids.has(combatant_id)


func set_result(payload: Dictionary) -> void:
	actor_id = String(payload.get("actorId", ""))
	target_id = String(payload.get("resultTargetId", payload.get("targetId", "")))
	result_kind = CombatPlaybackResultText.kind(payload)
	damage_type = int(payload.get("damageType", 0))
	display_amount = int(payload.get("healing", 0)) if result_kind == &"healing" else int(payload.get("damage", 0))
	display_text = CombatPlaybackResultText.text_for(result_kind, display_amount, payload)
	effect_resource_id = int(payload.get("classicResultEffectResourceId", 0))


func set_elemental_result(attacker_id: String, component: Dictionary) -> void:
	actor_id = attacker_id
	target_id = String(component["targetId"])
	result_kind = &"elemental_damage"
	damage_type = ["fire", "cold", "electrical", "chemical", "mental"].find(String(component["element"])) + 1
	display_amount = int(component["amount"])
	display_text = "%d %s damage" % [display_amount, String(component["element"])]
	effect_resource_id = int(component["effectResourceId"])
	effect_resource_type = String(component["effectResourceType"])
	sound_event = DomainEvent.new(&"sound_requested", component["soundRequest"].duplicate(true))


func set_monster_status(event: DomainEvent) -> bool:
	if not bool(event.payload.get("announced", false)) or not event.payload.has("classicResultEffectResourceId"):
		return false
	actor_id = String(event.payload.get("actorId", ""))
	target_id = String(event.payload.get("targetId", ""))
	result_kind = &"monster_status"
	var labels := {1: "Frightened", 2: "Paralyzed", 3: "Cursed", 4: "Stupid", 5: "Entangled", 6: "Poisoned", 7: "Confused", 10: "Charmed", 16: "Diseased"}
	display_text = labels.get(int(event.payload.get("specialCode", 0)), "Affected")
	effect_resource_id = int(event.payload["classicResultEffectResourceId"])
	sound_event = DomainEvent.new(&"sound_requested", {"soundId": event.payload["classicOverlaySoundId"], "waitForCompletion": false, "source": "classic-monster-status-overlay"})
	return true


func as_account() -> CombatPlaybackFrame:
	kind = &"account_result"
	duration_seconds = 0.0
	return self


static func without_motion(frames: Array[CombatPlaybackFrame]) -> Array[CombatPlaybackFrame]:
	var retained: Array[CombatPlaybackFrame] = []
	for frame: CombatPlaybackFrame in frames:
		if frame.kind in [&"group_result", &"group_defeat"]:
			var group_sound := frame.sound_event
			for child: CombatPlaybackFrame in frame.group_frames:
				if frame.kind == &"group_defeat":
					child.sound_event = group_sound
					group_sound = null
				retained.append(child.as_account())
		elif frame.kind in [&"result", &"defeat"]:
			retained.append(frame.as_account())
		elif frame.sound_event != null:
			frame.kind = &"sound"
			frame.duration_seconds = 0.01
			retained.append(frame)
	return retained
