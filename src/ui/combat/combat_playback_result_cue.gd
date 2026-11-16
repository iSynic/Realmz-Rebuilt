## Shows the recipient and result of one committed combat playback frame beside the command region.
class_name CombatPlaybackResultCue
extends PanelContainer

@onready var _target_icon: TextureRect = %TargetIcon
@onready var _target_name: Label = %TargetName
@onready var _result: Label = %Result
@onready var _vitals: Label = %Vitals


## Presents `frame`'s result for its recipient from the detached combatant `facts`, or hides
## when the frame carries none. `suppressed` keeps it hidden while the activity strip, which
## has its own target preview, is on screen.
func present(frame: CombatPlaybackFrame, facts: Dictionary, suppressed: bool) -> void:
	visible = false
	_target_icon.texture = null
	_target_name.text = ""
	_result.text = ""
	_vitals.text = ""
	_vitals.visible = false
	if suppressed or frame == null or frame.kind != &"result" or frame.target_id.is_empty() or frame.display_text.is_empty():
		return
	var target: Dictionary = facts.get(frame.target_id, {})
	_target_name.text = String(target.get("name", ""))
	if _target_name.text.is_empty():
		return
	var icon: Variant = target.get("icon")
	if icon is Texture2D:
		_target_icon.texture = icon
	_result.text = frame.display_text
	var maximum_health := int(target.get("maximumHealth", 0))
	if maximum_health > 0 and frame.combatant_health.has(frame.target_id):
		_vitals.text = "ST %d/%d" % [int(frame.combatant_health[frame.target_id]), maximum_health]
		_vitals.visible = true
	visible = true
