## Binds the shared scene-authored Adventure Rules controls and availability.
class_name AdventureRulesPanel
extends VBoxContainer

signal value_changed(rule: StringName, value: Variant)

const RULE_NODES: Dictionary[StringName, String] = {&"free_targeting_cancellation": "FreeTargetingCancellation", &"bard_daggers": "BardDaggers"}
const SPEED_SLIDER := "MoneyTransferSpeedRow/MoneyTransferSpeedSlider"

var _binding := false


func _ready() -> void:
	for rule: StringName in RULE_NODES:
		(get_node(RULE_NODES[rule]) as CheckButton).toggled.connect(func(enabled: bool) -> void: _on_changed(rule, enabled))
	(get_node(SPEED_SLIDER) as HSlider).value_changed.connect(func(value: float) -> void:
		_show_speed(roundi(value))
		_on_changed(&"money_transfer_speed", roundi(value)))


func bind_rules(rules: AdventureRules, available: bool, reason: String) -> void:
	_binding = true
	var free_targeting := get_node("FreeTargetingCancellation") as CheckButton
	var bard_daggers := get_node("BardDaggers") as CheckButton
	var speed := get_node(SPEED_SLIDER) as HSlider
	free_targeting.button_pressed = rules.free_targeting_cancellation if rules != null else false
	bard_daggers.button_pressed = rules.bard_daggers if rules != null else false
	speed.value = rules.money_transfer_speed if rules != null else 1
	_show_speed(roundi(speed.value))
	free_targeting.disabled = not available or rules == null
	bard_daggers.disabled = free_targeting.disabled
	speed.editable = not free_targeting.disabled
	var unavailable := get_node("RulesUnavailableReason") as Label
	unavailable.text = reason if not reason.is_empty() else "Adventure Rules are unavailable in this context."
	unavailable.visible = free_targeting.disabled or not reason.is_empty()
	_binding = false


func _show_speed(speed: int) -> void:
	(get_node("MoneyTransferSpeedRow/MoneyTransferSpeedValue") as Label).text = "%dx" % speed
	(get_node(SPEED_SLIDER) as HSlider).tooltip_text = "Money transfer speed %dx" % speed


func _on_changed(rule: StringName, value: Variant) -> void:
	if not _binding:
		value_changed.emit(rule, value)
