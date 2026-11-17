## One character from a saved party, drawn as its own card. The card is the focus and toggle
## target; its check only mirrors the selection. Long lists clamp until the card is focused.
class_name PartyImportCandidateCard
extends Button

const CLAMP := 4

var index := -1
var _card: Dictionary = {}
var _expanded := false

@onready var _content: Control = $CardContent
@onready var _check: CheckBox = $CardContent/Check
@onready var _portrait: TextureRect = $CardContent/PortraitTile/Portrait
@onready var _missing: Label = $CardContent/PortraitTile/Missing
@onready var _icon: TextureRect = $CardContent/IconTile/Icon
@onready var _name: Label = $CardContent/Body/NameLine/Name
@onready var _identity: Label = $CardContent/Body/NameLine/Identity
@onready var _stats: Label = $CardContent/Body/Stats
@onready var _reasons: Label = $CardContent/Body/Reasons
@onready var _items: Label = $CardContent/Body/Lists/ItemsColumn/Values
@onready var _magic: Label = $CardContent/Body/Lists/MagicColumn/Values
@onready var _left: Label = $CardContent/Body/Lists/LeftColumn/Values

var _fitted_width := -1.0

func _ready() -> void:
	_content.minimum_size_changed.connect(_fit_height)
	toggled.connect(func(pressed: bool) -> void: _check.set_pressed_no_signal(pressed))
	focus_entered.connect(_set_expanded.bind(true))
	focus_exited.connect(_set_expanded.bind(false))
	_fit_height()


func bind(card: Dictionary, card_index: int) -> void:
	_card = card
	index = card_index
	name = "Candidate%d" % card_index
	var portrait: Texture2D = card.get("portrait")
	_portrait.texture = portrait
	_missing.visible = portrait == null
	var icon: Texture2D = card.get("icon")
	_icon.texture = icon
	_name.text = RowFields.text(card, "name", "Character")
	_identity.text = RowFields.text(card, "identity", "")
	_stats.text = RowFields.text(card, "stats", "")
	var reasons: Array = card.get("reasons", [])
	_reasons.visible = not reasons.is_empty()
	_reasons.text = "\n".join(reasons.map(func(reason: Variant) -> String: return "•  %s" % reason))
	_left.tooltip_text = RowFields.text(card, "left_tooltip", "")
	_bind_lists()


## Selection state and why the card can't be toggled, from the dialog's slot accounting.
func set_choice(selected: bool, blocked_reason: String) -> void:
	set_pressed_no_signal(selected)
	_check.set_pressed_no_signal(selected)
	disabled = not blocked_reason.is_empty()
	focus_mode = Control.FOCUS_ALL
	_check.disabled = disabled
	tooltip_text = blocked_reason if disabled else ("Leave %s behind." if selected else "Bring %s into the party.") % _name.text
	var state := "selected" if selected else "not selected"
	accessibility_name = "%s, %s, %s, %s" % [_name.text, _identity.text, state, blocked_reason if disabled else _stats.text]


func _set_expanded(expanded: bool) -> void:
	if expanded == _expanded:
		return
	_expanded = expanded
	_bind_lists()


func _bind_lists() -> void:
	var items: Array = _card.get("items", [])
	var magic: Array = _card.get("magic", [])
	var left: Array = _card.get("left", [])
	_items.text = _list_text(items, "None")
	_magic.text = _list_text(magic, "—")
	_left.text = _list_text(left, "None")


func _list_text(values: Array, empty: String) -> String:
	if values.is_empty():
		return empty
	if _expanded or values.size() <= CLAMP:
		return ", ".join(values)
	return "%s  +%d more" % [", ".join(values.slice(0, CLAMP)), values.size() - CLAMP]


## Wrapped text measured at a transient narrow width must not latch a tall card; re-measure
## once the final width is laid out.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not is_equal_approx(size.x, _fitted_width):
		_fitted_width = size.x
		_fit_height.call_deferred()


func _fit_height() -> void:
	custom_minimum_size.y = maxf(68.0, _content.get_combined_minimum_size().y + 24.0)
