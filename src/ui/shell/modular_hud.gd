## Positions the same four authored play panels in the optional exploration layout.
class_name ModularHud
extends Control

const TITLES: Array[String] = ["Party roster", "Narration", "World commands", "Party commands"]
const WATCHED_FIELDS: Array[StringName] = [&"current_health", &"maximum_health", &"spell_points", &"maximum_spell_points", &"level", &"brawn", &"knowledge", &"judgment", &"agility", &"vitality", &"luck", &"armor"]

var active := false
var _shell_ref: WeakRef
var _contents: Array[Control] = []
var _parents: Array[Node] = []
var _indices: Array[int] = []
var _styles: Array[StyleBox] = []
var _panels: Array[HudPanel] = []
var _settings := HudPreferences.new()
var _last_route: StringName = &""
var _party_effect_playback := false
var _arrange_draft: HudPreferences
var _placement_area: Rect2
var _layout_font_scale := 1.0
var _layout_ui_scale := 1.0
var _layout_narrative_scale := 1.0
@onready var panel_menu: HudPanelMenu = $PanelMenu


func initialize(shell: GameShell) -> void:
	_shell_ref = weakref(shell)
	_contents = [shell.get_node("%PartyRoster"), shell.get_node("%NarrativeWell"), shell.get_node("%WorldCommandPanel"), shell.get_node("%CommandPanel")]
	_panels = [$Roster, $Narration, $World, $Party]
	_panels[3].companion_surface = %EffectsDock
	_panels[3].open_changed.connect(func(open: bool) -> void: %EffectsDock.visible = active and open)
	panel_menu.arrange_requested.connect(_arrange_from_menu)
	for index: int in 4:
		var content := _contents[index]
		_parents.append(content.get_parent())
		_indices.append(content.get_index())
		_styles.append(content.get_theme_stylebox("panel") if content.has_theme_stylebox_override("panel") else null)
		_panels[index].pin_changed.connect(_pin_changed.bind(index))
		_panels[index].options_requested.connect(_open_options.bind(index))
	shell.status.narrative_appended.connect(_narrative_appended)


func prepare(settings: PresentationSettings, view: GameView, route: StringName, paused: bool) -> bool:
	var exploration := route == &"exploration" or paused and _last_route == &"exploration"
	if not paused: _last_route = route
	var preferences := _arrange_draft if _arrange_draft != null else settings.hud
	var enabled := preferences.modular and view != null and view.session_started and not view.party_setup_available and exploration and (view.combat_view == null or view.combat_view.outcome != &"active")
	if _arrange_draft != null: enabled = true
	if enabled != active: _set_active(enabled)
	if not active: return false
	_settings = preferences.duplicate_value()
	for index: int in 4:
		_panels[index].configure(TITLES[index], preferences.panels[index], settings.reduced_motion)
		_panels[index].set_required(_arrange_draft != null or view.active_interaction_request() != null and index < 2 or _party_effect_playback and index == 0)
	%EffectsDock.visible = _panels[3].is_open()
	%EffectsDock.self_modulate.a = preferences.panels[3].background_opacity
	return true


func set_party_effect_playback(enabled: bool) -> void:
	_party_effect_playback = enabled
	if active:
		_panels[0].set_required(enabled)


func world_reveal_contains_point(point: Vector2) -> bool:
	return active and _panels[2].reveal_handle_contains_point(point)


func _set_active(enabled: bool) -> void:
	active = enabled
	visible = enabled
	panel_menu.close()
	var shell := _shell_ref.get_ref() as GameShell
	var effects := shell.get_node("%EffectsPanel")
	if not enabled:
		(shell.get_node("%BottomRegion") as Control).show()
		(shell.get_node("%Facts") as GridContainer).remove_theme_constant_override("h_separation")
	var row := shell.get_node("%PartyEffectsRow")
	effects.reparent(%EffectsDock if enabled else row, false)
	if not enabled: row.move_child(effects, 1)
	if not enabled: (shell.get_node("%EffectsGrid") as GridContainer).columns = 2
	if not enabled:
		(shell.get_node("%WorldCommandLowerGrid") as Control).get_parent().show()
		for grid: GridContainer in [shell.get_node("%WorldCommandGrid"), shell.get_node("%CommandGrid")]:
			UiSizing.constant(grid, &"h_separation", 3)
			UiSizing.constant(grid, &"v_separation", 3)
	(_contents[0].get_node("RosterColumn/Heading") as Control).visible = not enabled
	for record: Node in _contents[0].find_children("Member", "PanelContainer", true, false):
		(record as PartyRosterMemberRow).set_modular_style(enabled)
	for index: int in 4:
		var content := _contents[index]
		content.reparent(_panels[index].content_host() if enabled else _parents[index], false)
		content.custom_minimum_size = Vector2.ZERO
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.z_index = 0
		if enabled:
			content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			content.show()
		else:
			_parents[index].move_child(content, _indices[index])
			if _styles[index] != null: content.add_theme_stylebox_override("panel", _styles[index])
			else: content.remove_theme_stylebox_override("panel")


func arrange(profile: UiLayoutProfile) -> void:
	if not active: return
	for content: Control in _contents:
		if not content.get_theme_stylebox("panel") is StyleBoxEmpty:
			content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var area := profile.application_rect.grow(-8.0)
	_placement_area = area
	_layout_font_scale = profile.font_scale
	_layout_ui_scale = profile.ui_scale
	_layout_narrative_scale = profile.narrative_font_scale
	var compact := profile.id == UiLayoutProfile.COMPACT
	var commands := _arrange_commands(profile, area)
	var strip_width := maxf(commands[0].size.x if _settings.strip_orientations[0] != "horizontal" else 0.0, commands[1].size.x if _settings.strip_orientations[1] != "horizontal" else 0.0)
	var gap := 12.0
	var roster_width := minf(area.size.x * 0.44, maxf(344.0 * profile.ui_scale, profile.party_width))
	var narrative_height := minf(160.0 * profile.font_scale, area.size.y * 0.35)
	var narrative_width := maxf(320.0 * profile.font_scale, area.size.x - strip_width - gap - (0.0 if compact else roster_width + gap))
	var rectangles: Array[Rect2] = [
		Rect2(Vector2(area.size.x - roster_width, 0), Vector2(roster_width, area.size.y - narrative_height - gap if compact else area.size.y)),
		Rect2(Vector2(strip_width + gap, area.size.y - narrative_height), Vector2(narrative_width, narrative_height)),
		commands[0], commands[1],
	]
	for index: int in 4:
		var rectangle := rectangles[index]
		if index == 0 and not compact:
			var list := _contents[0].get_node("RosterColumn/PartyScroll/PartyList") as Control
			rectangle.size.y = minf(rectangle.size.y, list.get_combined_minimum_size().y + 12.0 * profile.ui_scale)
		var preference := _settings.panels[index]
		if preference.custom_size: rectangle.size = (area.size * preference.size_fraction).clamp(minimum_panel_size(index), area.size)
		if index == 1: rectangle = _fit_narrative(rectangle)
		if preference.custom_position: rectangle.position = (area.size - rectangle.size).max(Vector2.ZERO) * preference.position
		rectangle.position = rectangle.position.clamp(Vector2.ZERO, (area.size - rectangle.size).max(Vector2.ZERO))
		rectangle.position += area.position
		_panels[index].set_panel_rect(rectangle)
		_contents[index].custom_minimum_size.x = 0.0
		var handle := _panels[index].get_node("Handle") as Control
		handle.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var dock := Vector2(area.end.x - 24.0, area.position.y + area.size.y * 0.28)
		if index == 1: dock = Vector2(area.position.x + area.size.x * 0.5 - 16.0, area.end.y - 80.0)
		elif index >= 2: dock = Vector2(area.position.x, area.position.y + area.size.y * (0.2 if index == 2 else 0.6))
		handle.position = dock - rectangle.position
	var roster := _contents[0] as ClassicPartyRoster
	roster.set_compact_layout(compact)
	for record: Node in roster.find_children("Member", "PanelContainer", true, false):
		(record as PartyRosterMemberRow).set_modular_style(true)
	_arrange_effects(area, Rect2(_panels[1].position - area.position, _panels[1].size), compact)


func minimum_panel_size(index: int) -> Vector2:
	var minimum := Vector2(280.0, 160.0) if index == 0 else Vector2(320.0, 120.0)
	minimum *= maxf(_layout_ui_scale, _layout_font_scale if index == 0 else _layout_narrative_scale)
	if index == 0: minimum.x = maxf(minimum.x, _roster_reading_width())
	return minimum.min(_placement_area.size)


func _roster_reading_width() -> float:
	var required := 0.0
	for row: Node in _contents[0].find_children("Member", "PanelContainer", true, false):
		var details := row.get_node("Character/Details") as Control
		for group: String in ["Vitals", "Actions"]:
			for cell: Control in details.get_node("Record/" + group).get_children():
				var fields := cell.get_child(0) as HBoxContainer
				var value := fields.get_node("Value") as Label
				var text_width := value.get_theme_font("font").get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x
				var caption := fields.get_node("Caption") as Label
				required = maxf(required, details.offset_left + text_width + caption.get_combined_minimum_size().x + fields.get_theme_constant("separation") + 32.0)
	return required


func _fit_narrative(rectangle: Rect2) -> Rect2:
	var shell := _shell_ref.get_ref() as GameShell
	var facts := shell.get_node("%Facts") as GridContainer
	facts.add_theme_constant_override("h_separation", roundi(8.0 * _layout_font_scale))
	facts.columns = 3
	while facts.columns > 1 and facts.get_combined_minimum_size().x + 12.0 > rectangle.size.x:
		facts.columns -= 1
	rectangle.size.x = maxf(rectangle.size.x, facts.get_combined_minimum_size().x + 12.0)
	var narrative := shell.get_node("%NarrativeText") as RichTextLabel
	var line_height := narrative.get_theme_font_size("normal_font_size") * 1.4
	rectangle.size.y = maxf(rectangle.size.y, facts.get_combined_minimum_size().y + line_height * 3.0 + 20.0)
	rectangle.size = rectangle.size.min(_placement_area.size)
	return rectangle


func _arrange_effects(area: Rect2, narration: Rect2, compact: bool) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	var grid := shell.get_node("%EffectsGrid") as GridContainer
	var cell := (grid.get_child(0) as Control).get_combined_minimum_size()
	var spacing := Vector2(grid.get_theme_constant("h_separation"), grid.get_theme_constant("v_separation"))
	grid.columns = _strip_columns(8, cell + spacing, area.size, _settings.strip_orientations[2], 8 if 8.0 * (cell.x + spacing.x) <= narration.size.x else 4)
	var effect_size := Vector2(grid.columns, ceili(8.0 / grid.columns)) * (cell + spacing) - spacing
	var effect_position := Vector2(narration.end.x - effect_size.x, narration.position.y - effect_size.y - 8.0)
	if _settings.strip_orientations[2] == "vertical":
		effect_position = Vector2(_panels[0].position.x - area.position.x - effect_size.x - 8.0, 0.0)
	if _settings.effects_custom_position: effect_position = (area.size - effect_size).max(Vector2.ZERO) * _settings.effects_position
	effect_position = effect_position.clamp(Vector2.ZERO, (area.size - effect_size).max(Vector2.ZERO))
	%EffectsDock.position = area.position - _panels[3].position + effect_position
	%EffectsDock.size = effect_size
	if compact and _settings.strip_orientations[2] == "auto" and not _settings.panels[0].custom_position and not _settings.panels[0].custom_size and not _settings.effects_custom_position:
		_panels[0].size.y = minf(_panels[0].size.y, maxf(minimum_panel_size(0).y, %EffectsDock.global_position.y - _panels[0].global_position.y - 8.0))


func _strip_columns(count: int, cell: Vector2, available: Vector2, orientation: String, automatic: int) -> int:
	if orientation == "horizontal": return clampi(floori(available.x / cell.x), 1, count)
	if orientation == "vertical": return ceili(float(count) / maxi(1, floori(available.y / cell.y)))
	return automatic


func _arrange_commands(profile: UiLayoutProfile, area: Rect2) -> Array[Rect2]:
	var shell := _shell_ref.get_ref() as GameShell
	var padding := 2 if _settings.compact_commands else 8
	var world := shell.get_node("%WorldCommandGrid") as GridContainer
	var party := shell.get_node("%CommandGrid") as GridContainer
	var icon_size := Vector2(32, 32)
	for grid: GridContainer in [world, party]:
		for button: Node in grid.get_children():
			if not button is ClassicBitmapButton: continue
			var texture := (button as ClassicBitmapButton).radial_art_texture()
			if button.visible and texture != null: icon_size = icon_size.max(texture.get_size())
	var available_height := maxf(216.0, area.size.y - 112.0)
	var art_scale := profile.bitmap_scale
	while art_scale > 1 and (7 * (icon_size.y * art_scale + 2 * padding) + 8 > available_height or 7 * (icon_size.x * art_scale + 2 * padding) > area.size.x):
		art_scale -= 1
	var cell := icon_size * art_scale + Vector2.ONE * 2 * padding
	var columns := 1 if 12 * cell.y + 8 <= available_height else 2
	for index: int in 2:
		var grid := world if index == 0 else party
		grid.columns = _strip_columns(7 if index == 0 else 5, cell, area.size, _settings.strip_orientations[index], columns)
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 0)
		for child: Node in grid.get_children():
			if child is BaseButton and child.has_method("set_modular_icon_layout"):
				child.call("set_modular_icon_layout", art_scale, padding)
				(child as Control).custom_minimum_size = cell
	(shell.get_node("%WorldCommandLowerGrid") as Control).get_parent().hide()
	(shell.get_node("%TorchDock") as Control).hide()
	# Reflow after command refresh briefly restores the larger Fixed artwork metrics.
	(shell.get_node("%PartyEffectsRow") as BoxContainer).queue_sort()
	var world_size := Vector2(world.columns, ceili(7.0 / world.columns)) * cell
	var party_size := Vector2(party.columns, ceili(5.0 / party.columns)) * cell
	var party_position := Vector2(0, world_size.y + 8)
	if _settings.strip_orientations[0] == "horizontal" and _settings.strip_orientations[1] == "horizontal" and world_size.x + party_size.x + 8 <= area.size.x:
		party_position = Vector2(world_size.x + 8, 0)
	return [Rect2(Vector2.ZERO, world_size), Rect2(party_position, party_size)]


func observe(previous: GameView, current: GameView) -> void:
	if not active or previous == null or current == null or not previous.session_started or previous.campaign_id != current.campaign_id: return
	if not _settings.panels[0].reveal_on_changes: return
	if previous.party_members.size() != current.party_members.size():
		_panels[0].reveal(4.0)
		return
	for index: int in current.party_members.size():
		var before := previous.party_members[index]
		var after := current.party_members[index]
		if before.id != after.id or before.condition_values.map(func(value: int) -> bool: return value != 0) != after.condition_values.map(func(value: int) -> bool: return value != 0):
			_panels[0].reveal(4.0)
			return
		for field: StringName in WATCHED_FIELDS:
			if before.get(field) != after.get(field):
				_panels[0].reveal(4.0)
				return


func _narrative_appended(text: String) -> void:
	if active and _settings.panels[1].reveal_on_changes and not text.strip_edges().is_empty():
		_panels[1].reveal(maxf(5.0, text.split(" ", false).size() / 3.0))


func focus_panel(index: int) -> void:
	if not active or index < 0 or index >= 4: return
	_open_options(_panels[index].position, index)


func focus_root() -> Control:
	if panel_menu.visible: return panel_menu
	for panel: HudPanel in _panels:
		if active and panel.owns_content_focus(): return panel
	return null


func placement_area() -> Rect2:
	return _placement_area


func panel_rectangles() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for panel: HudPanel in _panels: result.append(Rect2(panel.position, panel.size))
	result.append(Rect2(%EffectsDock.global_position - global_position, %EffectsDock.size))
	return result


func begin_arrangement(value: HudPreferences) -> void:
	z_index = 110
	update_arrangement(value)


func update_arrangement(value: HudPreferences) -> void:
	_arrange_draft = value.duplicate_value()
	(_shell_ref.get_ref() as GameShell).refresh_layout()


func end_arrangement() -> void:
	_arrange_draft = null
	z_index = 15
	(_shell_ref.get_ref() as GameShell).refresh_layout()


func release_panel_focus() -> bool:
	if panel_menu.visible:
		panel_menu.close()
		return true
	var panel := focus_root() as HudPanel
	if panel == null: return false
	panel.release_panel_focus()
	return true


func handle_controller(action: StringName, pressed: bool, direction: Vector2i) -> bool:
	if panel_menu.handle_controller(action, pressed, direction): return true
	var root := focus_root()
	if root != null and action in [&"realmz_controller_section_previous", &"realmz_controller_section_next"]:
		if pressed: ControllerFocusNavigator.new().focus_next(root, action == &"realmz_controller_section_previous")
		return true
	if root != null and action == &"realmz_controller_inspect":
		if pressed: (_shell_ref.get_ref() as GameShell).controller.show_detail(ControllerFocusNavigator.new().inspection_text(root))
		return true
	if focus_root() != $Narration: return false
	var vertical := direction.y
	if action == &"realmz_controller_scroll_up": vertical = -1
	elif action == &"realmz_controller_scroll_down": vertical = 1
	if vertical == 0: return false
	if pressed:
		var narrative := _contents[1].get_node("NarrativeColumn/NarrativeText") as RichTextLabel
		var scroll := narrative.get_v_scroll_bar()
		scroll.value += vertical * narrative.get_theme_font_size("normal_font_size") * 3.0
	return true


func handle_input(event: InputEvent) -> bool:
	if panel_menu.handle_input(event): return true
	var shell := _shell_ref.get_ref() as GameShell
	if not active or shell.pause_active or shell.hud_arrange.visible or shell.controller.radial.is_open(): return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if %EffectsDock.is_visible_in_tree() and %EffectsDock.get_global_rect().has_point(get_global_mouse_position()):
			_open_options(get_global_mouse_position(), 3)
			get_viewport().set_input_as_handled()
			return true
		for panel: HudPanel in _panels:
			if not panel.is_open() and panel.request_options_at(get_global_mouse_position()):
				get_viewport().set_input_as_handled()
				return true
		for index: int in range(_panels.size() - 1, -1, -1):
			if _panels[index].is_open() and _panels[index].request_options_at(get_global_mouse_position()):
				get_viewport().set_input_as_handled()
				return true
	return false


func _open_options(location: Vector2, index: int) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	panel_menu.open(_panels[index], location, shell.controller.pause.allowed())


func _arrange_from_menu() -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if not shell.controller.pause.open(): return
	shell.controller.pause.activate(&"interface")
	shell.hud_arrange.open(shell)


func _pin_changed(pinned: bool, index: int) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if shell == null: return
	var baseline := shell.settings
	var candidate := PresentationSettings.from_data(baseline.to_data())
	candidate.hud.panels[index].auto_hide = not pinned
	var commit := shell.navigator.content_presenter.system_preferences.commit_preferences
	var error := String(commit.call(baseline, candidate)) if commit.is_valid() else "Settings storage is unavailable."
	if not error.is_empty():
		shell.status.set_status(error, true)
		shell.refresh_layout()
