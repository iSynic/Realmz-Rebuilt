## Owns retained saved-adventure browsing and cancellable loading overlays.
class_name StartupWorkspaceController
extends Control

signal browser_requested(from_setup: bool)
signal browser_closed
signal wait_cancel_requested

@onready var browser: SavedAdventureBrowser = $SavedAdventureBrowser
@onready var loading: LoadingAdventureView = $LoadingAdventure
@onready var save_editor: SaveEditorWorkspace = $SaveEditorWorkspace
var _from_setup := false
var _before_open: Callable
var _return_to_origin: Callable
var _finish_wait: Callable
var _changed: Callable


func _ready() -> void:
	browser.back_requested.connect(close_browser)
	loading.cancel_requested.connect(func() -> void: wait_cancel_requested.emit())


func bind(before_open: Callable, return_to_origin: Callable, finish_wait: Callable, changed: Callable) -> void:
	_before_open = before_open
	_return_to_origin = return_to_origin
	_finish_wait = finish_wait
	_changed = changed


func show_browser(from_setup: bool = false) -> void:
	_from_setup = from_setup
	_before_open.call()
	browser.show()
	browser_requested.emit(from_setup)
	(browser.get_node("%CampaignPicker") as Control).grab_focus()
	_changed.call()


func close_browser() -> void:
	browser.hide()
	browser_closed.emit()
	_return_to_origin.call(_from_setup)
	_changed.call()


## Opens the save editor over the browser; closing it returns there with the slot still selected.
func show_save_editor(session: SaveEditorSession, media: ClassicMediaCatalog, compact: bool) -> void:
	save_editor.bind(session, media, compact)
	_changed.call()


func save_editor_compact() -> bool:
	var profile := UiSizing.profile_for(save_editor)
	return profile != null and profile.id == UiLayoutProfile.COMPACT


func close_save_editor() -> void:
	save_editor.hide()
	browser.get_node("%LoadButton").grab_focus()
	_changed.call()


func show_loading(campaign_title: String, return_label: String) -> void:
	loading.show_wait(campaign_title, return_label)
	_changed.call()


func finish_loading(entered_adventure: bool = false) -> void:
	loading.hide_wait()
	if entered_adventure: browser.hide()
	_finish_wait.call(entered_adventure)
	_changed.call()


func handle_back() -> bool:
	if loading.visible:
		wait_cancel_requested.emit()
		return true
	if save_editor.visible:
		return save_editor.handle_back()
	return browser.handle_back() if browser.visible else false


func is_active() -> bool:
	return browser != null and browser.visible or loading != null and loading.visible or save_editor != null and save_editor.visible


func set_layout(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2) -> void:
	for overlay: Control in [browser, loading]:
		if overlay == null: continue
		overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		overlay.position = origin
		overlay.size = viewport_size
		overlay.set_layout_profile(profile)
	if save_editor != null:
		save_editor.set_anchors_preset(Control.PRESET_TOP_LEFT)
		save_editor.position = origin
		save_editor.size = viewport_size
		save_editor.set_layout_profile(profile)
