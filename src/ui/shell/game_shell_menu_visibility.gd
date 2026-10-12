## Reveals the retained top menu without reserving space in hidden modes.
class_name GameShellMenuVisibility
extends RefCounted

var _owner_ref: WeakRef
var _strip: PanelContainer
var _mode := PresentationSettings.MENU_VISIBLE
var _revealed := false


func _init(owner: GameShell) -> void:
	_owner_ref = weakref(owner)
	_strip = owner.get_node("%MenuStrip") as PanelContainer


func apply(settings: PresentationSettings) -> void:
	if _mode != settings.menu_visibility:
		_revealed = false
	_mode = settings.menu_visibility
	if not allowed(): _revealed = false
	_sync()


func reveal() -> bool:
	if not allowed():
		return false
	_revealed = true
	_sync()
	return true


func dismiss() -> void:
	_revealed = false
	_sync()


func handle_pointer(event: InputEvent) -> bool:
	if _mode == PresentationSettings.MENU_VISIBLE or not event is InputEventMouseMotion:
		return false
	if not allowed():
		dismiss()
		return false
	var owner := _owner_ref.get_ref() as GameShell
	var profile := UiSizing.profile_for(owner)
	var area := profile.application_rect if profile != null else Rect2(Vector2.ZERO, owner.size)
	var point := (event as InputEventMouseMotion).position
	if _mode == PresentationSettings.MENU_HOVER and Rect2(area.position, Vector2(area.size.x, 6.0 * (profile.ui_scale if profile != null else 1.0))).has_point(point):
		reveal()
	return _revealed and _strip.get_global_rect().has_point(point)


func allowed() -> bool:
	var owner := _owner_ref.get_ref() as GameShell
	if owner == null or not owner.is_visible_in_tree():
		return false
	if owner.menu_input_blocked.is_valid() and bool(owner.menu_input_blocked.call()):
		return false
	if owner.font_picker.visible or owner.music_workspace.visible or owner.navigator.draft_dialog.visible or owner.controller.text_editor_is_open() or owner.controller.radial_is_open():
		return false
	if owner.navigator.current_screen() == &"save_load":
		return false
	var view: GameView = owner._current_view
	var request := view.active_interaction_request() if view != null else null
	return request == null or request.kind == InteractionRequest.COMBAT


func owns_reveal() -> bool:
	return _mode != PresentationSettings.MENU_VISIBLE and _revealed


func _sync() -> void:
	_strip.visible = _mode == PresentationSettings.MENU_VISIBLE or _revealed
