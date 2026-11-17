## Sizes the battle summary cards and, in the modular combat HUD, floats the deck's pieces over the battlefield.
class_name BattleDeckLayout
extends RefCounted

## Emitted when the deck's pieces start or stop standing over the battlefield.
signal parking_changed

const LAYER := 80
const MARGIN := 8.0
const TURN_ENTRY_WIDTH := 64.0
## The HudPreferences placement index of each piece: panels 1-3, then the two extra panels.
const PLACES: Array[int] = [1, 2, 3, 7, 8]
const TURN_ORDER_PLACE := 2
## Where each piece rests until the player places it, as fractions of the free space:
## the combatant card, turn order, then the View, Action and Tactics command groups.
const RESTING: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(1.0, 1.0)]

## The window area the floating pieces may use, in viewport coordinates, and the combat HUD
## preferences that place them. The shell layout controller sets both; an empty area keeps
## the fixed deck. Piece `index` reads `preferences.panel_at(index + 1)`: panel 0 and the dock
## belong to the party roster the modular HUD shows during the battle.
static var area := Rect2()
static var preferences: HudPreferences
## Saves a placement the player finished: receives the edited combat HUD preferences.
static var save: Callable
## Returns true while something stands over the battle (the pause menu, the Combat Log).
## Floating pieces take the pointer ahead of everything else, so they step aside then.
static var obscured: Callable

var floating := false
var _overview: Control
var _active_card: Control
var _shown_card: Control
var _pieces: Array[Control] = []
var _showing_other := false
var _pending := false
var _hidden := false
var _drag := HudLiveDrag.new(_placement_rectangles, _apply_placement)
var _menu: PopupMenu
var _menu_index := -1


## Finds the authored pieces of `deck` once; later calls keep the first binding.
func bind(deck: Control) -> void:
	if _overview != null and is_instance_valid(_overview): return
	_overview = deck.get_node("%BattleOverview") as Control
	_active_card = deck.find_child("ActiveCombatant", true, false) as Control
	_shown_card = deck.find_child("InspectedCombatant", true, false) as Control
	_pieces.assign([_shown_card, deck.get_node("%BattleInitiativeHost"), deck.find_child("BattleInspectionCommandsInset", true, false), deck.get_node("%BattlePrimaryCommandsInset"), deck.find_child("BattleTurnCommandsInset", true, false)])
	for piece: Control in _pieces:
		piece.minimum_size_changed.connect(_queue_place)
	_active_card.minimum_size_changed.connect(_queue_place)
	_overview.visibility_changed.connect(_on_overview_visibility_changed)
	_menu = deck.get_node("%DeckPieceMenu") as PopupMenu
	_menu.id_pressed.connect(_on_menu_chosen)


## True while the pieces stand over the battlefield, leaving the command region empty.
func parked() -> bool:
	return floating and _overview != null and is_instance_valid(_overview) and _overview.visible


## The single floating card shows the acting combatant until the player inspects another.
func set_showing_other(other: bool) -> void:
	_showing_other = other
	_queue_place()


func apply(compact: bool) -> void:
	if _overview == null or not is_instance_valid(_overview): return
	UiSizing.minimum_size(_active_card, Vector2(220.0 if compact else 290.0, 0))
	UiSizing.minimum_size(_shown_card, Vector2(220.0 if compact else 290.0, 0))
	place()


func place() -> void:
	_pending = false
	if _overview == null or not is_instance_valid(_overview): return
	var wanted := BattleCommandScaleController.modular and area.has_area()
	if wanted != floating:
		floating = wanted
		for piece: Control in _pieces + [_active_card]:
			piece.top_level = wanted
			piece.z_index = LAYER if wanted else 0
			if not wanted: _size_piece(piece, 1.0)
		parking_changed.emit()
	_size_turn_entries()
	_active_card.visible = not floating or not _showing_other and not _hidden
	_shown_card.visible = not floating or _showing_other and not _hidden
	for index: int in range(1, _pieces.size()):
		_pieces[index].visible = not floating or not _hidden
	if not floating: return
	var free := area.grow(-MARGIN)
	for index: int in _pieces.size():
		var piece := _pieces[index]
		var panel := preferences.panel_at(index + 1) if preferences != null else null
		var factor := panel.scale if panel != null else 1.0
		_size_piece(piece, factor)
		var extent := piece.get_combined_minimum_size().min(free.size)
		var fraction := panel.position if panel != null and panel.custom_position else RESTING[index]
		var origin := (free.position + (free.size - extent) * fraction).round()
		piece.position = origin
		piece.size = extent
		if index == 0:
			_size_piece(_active_card, factor)
			_active_card.position = origin
			_active_card.size = _active_card.get_combined_minimum_size().min(free.size)


## Lays `piece` out at `factor` times the interface's metrics: its sizes and text are set at
## that scale, not stretched, so they stay sharp. A factor of 1 returns it to the shared metrics.
func _size_piece(piece: Control, factor: float) -> void:
	var base := UiSizing.profile_for(piece.get_parent())
	if base == null or is_equal_approx(factor, 1.0):
		piece.remove_meta(&"deck_piece_scale")
		UiSizing.clear_nested(piece)
		return
	var key := Vector3(base.ui_scale, base.font_scale, factor)
	if piece.get_meta(&"deck_piece_scale", Vector3.ZERO) == key: return
	piece.set_meta(&"deck_piece_scale", key)
	UiSizing.apply_nested(piece, base.scaled(factor))


## A turn entry's portrait stretches with its button and asks for no width of its own. The
## docked deck stretches the entries; a floating one is only as wide as its minimum, so each
## entry reserves room for the portrait beside its label there.
func _size_turn_entries() -> void:
	var order := _pieces[1].find_child("BattleInitiativeOrder", true, false) as BoxContainer
	if order == null: return
	# Dropped on a side edge, or set from its menu, the turn order runs down the screen.
	order.vertical = floating and preferences != null and preferences.orientation_of(TURN_ORDER_PLACE) == "vertical"
	for entry: Node in order.get_children():
		var button := entry as Button
		if button != null and not button.is_queued_for_deletion():
			UiSizing.minimum_size(button, Vector2(TURN_ENTRY_WIDTH if floating and button.icon != null else 0.0, 28.0))


## Hides the floating pieces while something stands over the battle and returns them after.
func poll_obscured() -> void:
	var hidden: bool = floating and obscured.is_valid() and obscured.call()
	if hidden == _hidden: return
	_hidden = hidden
	place()


## Ctrl+drag moves a floating piece, as it moves an overworld HUD panel; a right-click opens
## its menu. Returns true when the event belonged to either and must not reach the battle.
func handle_input(event: InputEvent) -> bool:
	var mouse := event as InputEventMouse
	if mouse == null or preferences == null or _hidden or not parked() or not _overview.is_visible_in_tree(): return false
	var profile := UiSizing.profile_for(_overview)
	if _drag.handle(event, mouse.position, area.grow(-MARGIN), profile.ui_scale if profile != null else 1.0, preferences): return true
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT: return false
	var rectangles := _placement_rectangles()
	for index: int in rectangles.size():
		if rectangles[index].has_point(mouse.position):
			_menu_index = index
			_menu.set_item_text(_menu.get_item_index(7), "Size · %d%%" % roundi(preferences.panel_at(PLACES.find(index) + 1).scale * 100.0))
			_menu.set_item_disabled(_menu.get_item_index(4), index != TURN_ORDER_PLACE)
			_menu.set_item_checked(_menu.get_item_index(4), index == TURN_ORDER_PLACE and preferences.orientation_of(TURN_ORDER_PLACE) == "vertical")
			# A popup is its own window and does not inherit the interface theme by itself.
			var themed: Node = _overview
			while themed != null and not (themed is Control and (themed as Control).theme != null): themed = themed.get_parent()
			if themed != null: _menu.theme = (themed as Control).theme
			_menu.position = Vector2i(mouse.position)
			_menu.popup()
			return true
	return false


## Each piece's rectangle by HudPreferences placement index (PLACES); the other indices
## belong to the roster, the dock and overworld-only elements.
func _placement_rectangles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.resize(9)
	if not floating: return result
	for index: int in _pieces.size():
		var piece := _active_card if index == 0 and _active_card.visible else _pieces[index]
		result[PLACES[index]] = Rect2(piece.position, piece.size)
	return result


## Shows a placement that is still being dragged, or saves it once `finished`.
func _apply_placement(value: HudPreferences, finished: bool) -> void:
	# The extra panels hold Action and Tactics, and are only saved with all four bars counted.
	value.bucket_count = 4
	preferences = value
	place()
	if finished and save.is_valid(): save.call(value)


func _on_menu_chosen(id: int) -> void:
	if preferences == null or _menu_index < 0: return
	var draft := preferences.duplicate_value()
	if id == 0: draft.panel_at(PLACES.find(_menu_index) + 1).custom_position = false
	elif id == 1:
		draft.reset_placement()
		draft.adopt_combat_scales()
	elif id == 4: draft.set_orientation(TURN_ORDER_PLACE, "horizontal" if draft.orientation_of(TURN_ORDER_PLACE) == "vertical" else "vertical")
	elif id in [2, 3]:
		var panel := draft.panel_at(PLACES.find(_menu_index) + 1)
		panel.scale = panel.stepped_scale(1 if id == 2 else -1)
	_apply_placement(draft, true)


func _queue_place() -> void:
	if _pending or not (floating or BattleCommandScaleController.modular): return
	_pending = true
	place.call_deferred()


func _on_overview_visibility_changed() -> void:
	if floating: parking_changed.emit()
