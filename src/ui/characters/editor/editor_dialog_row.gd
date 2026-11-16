## One before → after statistic row in an editor dialog.

class_name EditorDialogRow
extends HBoxContainer

@onready var _stat: Label = %Stat
@onready var _change: ArrowLabel = %Change
@onready var _delta: Label = %Delta


func bind(row: Dictionary) -> void:
	_stat.text = String(row.label)
	if row.has("text"):
		_change.set_arrow_text(String(row.text), 13, &"VaultStatusGold")
		_delta.text = ""
		return
	var before := int(row.before)
	var after := int(row.after)
	_change.set_arrow_text("%s → %s" % [CharacterEditLimits.group_digits(before), CharacterEditLimits.group_digits(after)], 13, &"VaultStatusGold")
	var delta := after - before
	_delta.text = ("+" if delta >= 0 else "") + CharacterEditLimits.group_digits(delta)
	_delta.theme_type_variation = &"VaultStatusBad" if bool(row.get("bad", false)) else (&"VaultStatusGood" if after >= before else &"VaultStatusMuted")
