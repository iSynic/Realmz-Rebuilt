## Owns the visible Bandage recipient controls and their supplied legal targets.
class_name BattleBandagePanel
extends VBoxContainer

signal bandage_requested(actor_id: String, target_id: String)

var _actor_id := ""
var _target_ids: Array[String] = []


func configure(actor_id: String, targets: Array[InteractionRequestValue.CombatTarget]) -> void:
	_actor_id = actor_id
	_target_ids.clear()
	var picker := $BandageRecipient as OptionButton
	picker.clear()
	for target: InteractionRequestValue.CombatTarget in targets:
		if target.id.is_empty():
			continue
		_target_ids.append(target.id)
		picker.add_item("%s • %d HP" % [target.name, target.current_health])
		picker.set_item_metadata(picker.item_count - 1, target.id)
	picker.disabled = picker.item_count == 0
	var submit := $Bandage as Button
	submit.disabled = picker.disabled
	if not submit.pressed.is_connected(_submit_selected):
		submit.pressed.connect(_submit_selected)


func eligible_ids() -> Array[String]:
	return _target_ids.duplicate()


func select(target_id: String) -> bool:
	if not visible or not _target_ids.has(target_id):
		return false
	bandage_requested.emit(_actor_id, target_id)
	return true


func _submit_selected() -> void:
	var target_id := String(($BandageRecipient as OptionButton).get_selected_metadata())
	select(target_id)
