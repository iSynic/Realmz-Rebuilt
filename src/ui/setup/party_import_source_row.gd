## One saved adventure in the import list. Unusable saves stay focusable but inert, so a
## controller player can still reach and read why they can't be imported.
class_name PartyImportSourceRow
extends Button

const QUIET := Color(0.373, 0.443, 0.486)

@onready var _content: Control = $RowContent
@onready var _title: Label = $RowContent/Summary/TitleLine/Title
@onready var _slot: Label = $RowContent/Summary/TitleLine/Slot
@onready var _backup: Control = $RowContent/Summary/TitleLine/BackupTag
@onready var _party: Label = $RowContent/Summary/Party
@onready var _when: Label = $RowContent/When
@onready var _chevron: Label = $RowContent/Chevron

var _fitted_width := -1.0

func _ready() -> void:
	# The row is a Button, so it grows with its wrapped content explicitly.
	_content.minimum_size_changed.connect(_fit_height)
	_fit_height()


func bind(row: Dictionary, busy: bool) -> void:
	var usable := RowFields.flag(row, "valid", false)
	_title.text = RowFields.text(row, "title", "Saved adventure")
	_slot.text = RowFields.text(row, "slot", "")
	_backup.visible = RowFields.flag(row, "backup", false)
	_when.text = RowFields.text(row, "when", "")
	var reason := RowFields.text(row, "reason", "")
	_party.text = RowFields.text(row, "party", "") if usable else reason
	_chevron.visible = usable
	# Unusable rows read as quiet text: grey title and a muted reason.
	_title.theme_type_variation = &"VaultStatusGold" if usable else &"VaultText"
	_title.modulate = Color.WHITE if usable else Color(1, 1, 1, 0.75)
	_party.modulate = Color.WHITE if usable else QUIET.lightened(0.15)
	disabled = not usable or busy
	focus_mode = Control.FOCUS_ALL
	tooltip_text = RowFields.text(row, "tooltip", "")
	var state := "Not available, %s" % reason if not usable else RowFields.text(row, "party", "")
	accessibility_name = "%s, %s, %s, %s" % [_title.text, _slot.text, _when.text, state]


## Wrapped text measured at a transient narrow width must not latch a tall card; re-measure
## once the final width is laid out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not is_equal_approx(size.x, _fitted_width):
		_fitted_width = size.x
		_fit_height.call_deferred()


func _fit_height() -> void:
	custom_minimum_size.y = maxf(56.0, _content.get_combined_minimum_size().y + 16.0)
