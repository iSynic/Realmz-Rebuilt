## Binds the shared scene-authored Adventure Rules checkbox and availability.
class_name AdventureRulesPanel
extends VBoxContainer

signal value_changed(enabled: bool)

var _binding := false


func _ready() -> void:
	(get_node("FreeTargetingCancellation") as CheckButton).toggled.connect(_on_toggled)


func bind_rules(rules: AdventureRules, available: bool, reason: String) -> void:
	_binding = true
	var checkbox := get_node("FreeTargetingCancellation") as CheckButton
	checkbox.button_pressed = rules.free_targeting_cancellation if rules != null else false
	checkbox.disabled = not available or rules == null
	var unavailable := get_node("RulesUnavailableReason") as Label
	unavailable.text = reason if not reason.is_empty() else "Adventure Rules are unavailable in this context."
	unavailable.visible = checkbox.disabled or not reason.is_empty()
	_binding = false


func _on_toggled(enabled: bool) -> void:
	if not _binding:
		value_changed.emit(enabled)
