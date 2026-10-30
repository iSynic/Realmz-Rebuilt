## Emits local Adventure Rules edits and action requests to SystemScreenController.
class_name AdventureRulesSettingsPage
extends VBoxContainer

signal value_changed(enabled: bool)
signal apply_requested
signal cancel_requested

var panel: AdventureRulesPanel:
	get: return get_node("AdventureRulesScroll/AdventureRulesContent/AdventureRulesPanel") as AdventureRulesPanel


func _ready() -> void:
	panel.value_changed.connect(func(enabled: bool) -> void: value_changed.emit(enabled))
	(get_node("RulesActions/ApplyRules") as Button).pressed.connect(func() -> void: apply_requested.emit())
	(get_node("RulesActions/CancelRules") as Button).pressed.connect(func() -> void: cancel_requested.emit())


var disease_damage_icon: CheckButton:
	get: return get_node("AdventureRulesScroll/AdventureRulesContent/DiseaseDamageIcon") as CheckButton


## Apply and Cancel cover both the per-adventure rules draft and this page's global display preference.
func bind_rules(rules: AdventureRules, available: bool, reason: String, status: String, can_apply: bool, can_cancel: bool) -> void:
	panel.bind_rules(rules, available, reason)
	(get_node("RulesDraftStatus") as Label).text = status
	(get_node("RulesActions/ApplyRules") as Button).disabled = not can_apply
	(get_node("RulesActions/CancelRules") as Button).disabled = not can_cancel
