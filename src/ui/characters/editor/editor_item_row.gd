## One carried item in the editor. Unidentified items show only their unidentified name.

class_name EditorItemRow
extends PanelContainer

signal action_requested(operation: Dictionary)

var _instance_id := ""
var _equipped := false

@onready var _name: Label = %ItemName
@onready var _facts: Label = %Facts
@onready var _equip: Button = %Equip
@onready var _identify: Button = %Identify
@onready var _remove: Button = %Remove


func _ready() -> void:
	_equip.pressed.connect(func() -> void: action_requested.emit({"kind": &"equip", "instance_id": _instance_id, "equipped": not _equipped}))
	_identify.pressed.connect(func() -> void: action_requested.emit({"kind": &"identify", "instance_id": _instance_id}))
	_remove.pressed.connect(func() -> void: action_requested.emit({"kind": &"remove_item", "instance_id": _instance_id}))


func bind(row: Dictionary, rules_reason: String) -> void:
	_instance_id = RowFields.text(row, "instanceId")
	_equipped = RowFields.flag(row, "equipped")
	_name.text = RowFields.text(row, "name")
	var facts: Array[String] = ["Equipped" if _equipped else "Carried", "weight %d" % RowFields.number(row, "weight")]
	if RowFields.number(row, "charges") > 0:
		facts.append("%d charges" % RowFields.number(row, "charges"))
	elif RowFields.number(row, "charges") < 0:
		facts.append("unlimited charges")
	if RowFields.flag(row, "cursed"):
		facts.append("Cursed · can be removed here")
	if not RowFields.flag(row, "identified"):
		facts.append("Unidentified")
	var equip_reason := RowFields.text(row, "equipReason")
	var editable: bool = row.editable
	var blocked := rules_reason if not rules_reason.is_empty() else "This item comes from its scenario, not the Classic library, so it stays as it is."
	if not editable:
		facts.append(blocked)
	elif not equip_reason.is_empty():
		facts.append(equip_reason)
	_facts.text = " · ".join(facts)
	_facts.tooltip_text = _facts.text
	_equip.text = "Unequip" if _equipped else "Equip"
	_equip.disabled = not editable or not equip_reason.is_empty()
	_equip.tooltip_text = blocked if not editable else (equip_reason if _equip.disabled else ("Unequip %s." if _equipped else "Equip %s.") % _name.text)
	_identify.visible = not RowFields.flag(row, "identified")
	_identify.disabled = not editable
	_identify.tooltip_text = blocked if not editable else "Reveal this item's name and facts."
	_remove.disabled = not editable
	_remove.tooltip_text = blocked if not editable else "Remove %s from this character." % _name.text
