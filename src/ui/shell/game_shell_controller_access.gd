## Binds shell focus, spell browsing and controller prompt responsibilities.
class_name GameShellControllerAccess
extends RefCounted

var _shell: Variant

func _init(shell: Variant) -> void:
	_shell = shell

var radial: GameShellControllerRadials:
	get: return GameShellControllerRadials.new(_shell)
var text: GameShellControllerText:
	get: return GameShellControllerText.new(_shell)
var pause: GameShellPauseController:
	get: return _shell._pause_controller


func show_prompts(family: String, context: StringName = &"") -> void:
	_shell._pause_controller.set_controller_prompts(family)
	_shell._controller_prompts.present(family, context, _shell._presentation_settings.controller)
	if _shell._pause_controller.is_open(): _shell._controller_prompts.hide_prompts()
	_shell._navigator.setup_controller.campaign_library.show_controller_hint(family, _shell._presentation_settings.controller)
	_shell._controller_radial.set_prompt_family(family)


func hide_prompts() -> void:
	_shell._controller_prompts.hide_prompts()
	_shell._pause_controller.set_controller_prompts("")


func show_detail(value: String) -> void: _shell._controller_prompts.set_detail(value)


func navigation_workspace_focus_root() -> Node:
	if _shell.hud_arrange.visible: return _shell.hud_arrange
	if not _shell.pause_active and _shell.hud.focus_root() != null: return _shell.hud.focus_root()
	if _shell.character_art.visible: return _shell.character_art.controller_focus_root()
	if _shell.font_picker.visible: return _shell.font_picker.controller_focus_root()
	var icon_picker: IndoorPartyIconPicker = _shell.navigator.content_presenter.system_preferences.indoor_icon_picker()
	if icon_picker != null and icon_picker.picker_is_open(): return icon_picker.controller_focus_root()
	if _shell.music_workspace.visible: return _shell.music_workspace.controller_focus_root()
	return _shell._navigator if _shell._pause_controller.workspace_is_open() else null


func cycle_navigation_workspace_tab(delta: int) -> void:
	if _shell.music_workspace.visible: _shell.music_workspace.controller_cycle_tab(delta)


func spellbook_focus_root() -> Control:
	var book: CombatRosterSpellbook = _shell._party_roster.controller_spellbook()
	if book != null: return book
	return _shell._navigator.content_presenter.spellbook.controller_focus_root() if _shell._navigator.current_screen() == &"spells" else null


func cycle_spellbook_level(delta: int) -> bool:
	var book: CombatRosterSpellbook = _shell._party_roster.controller_spellbook()
	return book.controller_cycle_section(delta) if book != null else _shell._navigator.content_presenter.spellbook.controller_cycle_section(delta)


func focus_spellbook_selection() -> bool:
	var book: CombatRosterSpellbook = _shell._party_roster.controller_spellbook()
	return book.focus_selected_spell() if book != null else _shell._navigator.content_presenter.spellbook.focus_selected_spell()


func show_spellbook_prompts(encounter: bool = false) -> void:
	var levels: bool = encounter or _shell._party_roster.controller_spellbook() != null or _shell._navigator.content_presenter.spellbook.controller_browses_levels
	_shell._controller_prompts.present_spellbook(_shell._presentation_settings.controller, levels)


func close_spellbook() -> void:
	var book: CombatRosterSpellbook = _shell._party_roster.controller_spellbook()
	if book != null: book.back_requested.emit()
	else: _shell._navigator.handle_back()


func select_relative_character(delta: int) -> bool: return _shell._party_roster.controller_select_relative(delta)


func cycle_section(delta: int) -> bool: return _shell._navigator.content_presenter.navigate_section(_shell._navigator.current_screen(), &"", delta)


func receive_binding(action_id: StringName, descriptor: Dictionary) -> void: _shell._navigator.content_presenter.receive_controller_binding(action_id, descriptor)


func cancel_binding_capture() -> void: _shell._navigator.content_presenter.cancel_controller_binding_capture()


func set_live_input(value: String) -> void: _shell._navigator.content_presenter.set_controller_live_input(value)


func handle_navigation_modal_input(event: InputEvent) -> bool:
	if _shell.hud.handle_input(event): return true
	if _shell.hud_arrange.handle_input(event): return true
	if _shell.character_art.visible and not _shell._controller_keyboard.is_open():
		if event.is_action_pressed(&"realmz_back"):
			_shell.character_art.dismiss()
			_shell.get_viewport().set_input_as_handled()
			return true
		return true
	if _shell.font_picker.visible and not _shell._controller_keyboard.is_open():
		if event.is_action_pressed(&"realmz_back"):
			_shell.font_picker.close()
			_shell.get_viewport().set_input_as_handled()
			return true
		return true
	return _shell._navigator.draft_dialog.handle_input(event)


func handle_navigation_modal_controller(action: StringName, pressed: bool, direction: Vector2i = Vector2i.ZERO) -> bool:
	if _shell.hud.handle_controller(action, pressed, direction): return true
	if _shell.hud_arrange.handle_controller(action, pressed, direction): return true
	return _shell._navigator.draft_dialog.handle_controller(action, pressed, direction)
