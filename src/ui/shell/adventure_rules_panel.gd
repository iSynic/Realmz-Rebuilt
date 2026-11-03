## Binds the shared scene-authored Adventure Rules checkboxes and availability.
class_name AdventureRulesPanel
extends VBoxContainer

signal value_changed(rule: StringName, enabled: bool)

const RULE_NODES: Dictionary[StringName, String] = {&"free_targeting_cancellation": "FreeTargetingCancellation", &"bard_daggers": "BardDaggers"}

var _binding := false


func _ready() -> void:
	for rule: StringName in RULE_NODES:
		(get_node(RULE_NODES[rule]) as CheckButton).toggled.connect(func(enabled: bool) -> void: _on_toggled(rule, enabled))


func bind_rules(rules: AdventureRules, available: bool, reason: String) -> void:
	_binding = true
	var free_targeting := get_node("FreeTargetingCancellation") as CheckButton
	var bard_daggers := get_node("BardDaggers") as CheckButton
	free_targeting.button_pressed = rules.free_targeting_cancellation if rules != null else false
	bard_daggers.button_pressed = rules.bard_daggers if rules != null else false
	free_targeting.disabled = not available or rules == null
	bard_daggers.disabled = free_targeting.disabled
	var unavailable := get_node("RulesUnavailableReason") as Label
	unavailable.text = reason if not reason.is_empty() else "Adventure Rules are unavailable in this context."
	unavailable.visible = free_targeting.disabled or not reason.is_empty()
	_binding = false


func _on_toggled(rule: StringName, enabled: bool) -> void:
	if not _binding:
		value_changed.emit(rule, enabled)
