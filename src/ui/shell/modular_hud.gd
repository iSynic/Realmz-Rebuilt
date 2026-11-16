## Positions the same four authored play panels in the optional exploration layout.
class_name ModularHud
extends Control

const TITLES: Array[String] = ["Party roster", "Narration", "Commands 1", "Commands 2", "Commands 3", "Commands 4"]
const WATCHED_FIELDS: Array[StringName] = [&"current_health", &"maximum_health", &"spell_points", &"maximum_spell_points", &"level", &"brawn", &"knowledge", &"judgment", &"agility", &"vitality", &"luck", &"armor"]

var active := false
## True while the HUD serves a battle fought with the modular combat HUD: only the party
## roster and its dock show, placed by `combat_hud`; the battle deck floats its own pieces.
var combat_mode := false
var _reduced_motion := false
var _roster_rect := Rect2()
var _shell_ref: WeakRef
var _contents: Array[Control] = []
var _fixed_contents: Array[Control] = []
var _effects_panel: PanelContainer
var effects_panel: PanelContainer:
	get: return _effects_panel
var world_grid: GridContainer:
	get: return _contents[2].get_node("WorldCommandColumn/WorldCommandDeckCenter/WorldCommandDeckFrame/WorldCommandRows/WorldCommandUpperCenter/WorldCommandGrid") as GridContainer
var _panels: Array[HudPanel] = []
var _authored_rects: Array[Rect2] = []
var _authored_effect_rect: Rect2
var _settings := HudPreferences.new()
var _last_route: StringName = &""
var _party_effect_playback := false
var _arrange_draft: HudPreferences
var _drag_draft: HudPreferences
var _prompt_ref: WeakRef
var _menu_button: ClassicBitmapButton
var _command_drag: HudCommandDrag
var _all_grids: Array[GridContainer] = []
var _extra_sizes: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## The grids of the command bars in use, in bar order.
var bucket_grids: Array[GridContainer]:
	get: return _all_grids.slice(0, _settings.bucket_count)
var _menu_target := 0
var _menu_panel := 0
@onready var _live_drag := HudLiveDrag.new(_element_rectangles, _apply_placement)
var _placement_area: Rect2
var _layout_font_scale := 1.0
var _layout_ui_scale := 1.0
var _layout_narrative_scale := 1.0
@onready var panel_menu: HudPanelMenu = $PanelMenu


func initialize(shell: GameShell) -> void:
	_shell_ref = weakref(shell)
	var prompt := shell.get_parent().get_node_or_null("InteractionPanel") if shell.get_parent() != null else null
	_prompt_ref = weakref(prompt) if prompt != null else null
	_fixed_contents = [shell.get_node("%PartyRoster"), shell.get_node("%NarrativeWell"), shell.get_node("%WorldCommandPanel"), shell.get_node("%CommandPanel")]
	_bind_authored_content()
	panel_menu.arrange_requested.connect(_arrange_from_menu)
	panel_menu.surface_keep_visible_changed.connect(_pin_changed.bind(-1))
	var move := func(id: String, bar: int, rank: float) -> void:
		_commit(func(hud: HudPreferences) -> HudPreferences:
			hud.command_buckets[id] = bar
			hud.command_order[id] = rank
			return hud)
		shell.commands.rebuild()
		shell.refresh_layout()
	panel_menu.scale_requested.connect(func(direction: int) -> void:
		_commit(func(hud: HudPreferences) -> HudPreferences:
			hud.panel_at(_menu_panel).scale = hud.panel_at(_menu_panel).stepped_scale(direction)
			return hud)
		shell.refresh_layout())
	panel_menu.move_requested.connect(func() -> void: move.call(String(_menu_button.command_id), _menu_target, 900.0))
	panel_menu.shift_requested.connect(func(direction: int) -> void: move.call(String(_menu_button.command_id), _all_grids.find(_menu_button.get_parent()), HudCommandDrag.shifted_rank(_menu_button, direction)))
	_command_drag = HudCommandDrag.new(func() -> Array: return bucket_grids, move, %CommandGhost)
	for index: int in _panels.size():
		_panels[index].pin_changed.connect(_pin_changed.bind(index))
		_panels[index].options_requested.connect(_open_options.bind(index))
	shell.status.narrative_appended.connect(_narrative_appended)
	_panels[0].open_changed.connect(func(_open: bool) -> void: _place_dock())
	(%PartyDock as PartyDock).expand_requested.connect(func() -> void: _panels[0].reveal())


func _bind_authored_content() -> void:
	_contents = [
		$Roster/Surface/Column/Body/Content/PartyRoster,
		$Narration/Surface/Column/Body/Content/NarrativeWell,
		$World/Surface/Column/Body/Content/WorldCommandPanel,
		$Party/Surface/Column/Body/Content/CommandPanel,
	]
	_effects_panel = $Party/EffectsDock/EffectsPanel
	_panels = [$Roster, $Narration, $World, $Party]
	for panel: HudPanel in _panels:
		_authored_rects.append(Rect2(panel.position, panel.size))
	_authored_effect_rect = Rect2(_panels[3].position + %EffectsDock.position, %EffectsDock.size)
	_panels.append($Bucket3 as HudPanel)
	_panels.append($Bucket4 as HudPanel)
	_all_grids = [world_grid, party_grid(), $Bucket3/Surface/Column/Body/Content/Grid as GridContainer, $Bucket4/Surface/Column/Body/Content/Grid as GridContainer]


func arrange_authoring_sample(profile: UiLayoutProfile) -> void:
	if _contents.is_empty(): _bind_authored_content()
	_settings = HudPreferences.new()
	active = true
	for index: int in 4:
		_panels[index].configure(TITLES[index], _settings.panels[index], false)
	arrange(profile)


func prepare(settings: PresentationSettings, view: GameView, route: StringName, paused: bool) -> bool:
	var exploration := route == &"exploration" or paused and _last_route == &"exploration"
	if not paused: _last_route = route
	var fighting := view != null and view.session_started and view.combat_view != null and view.combat_view.outcome == &"active"
	combat_mode = fighting and settings.combat_hud.modular and _arrange_draft == null and (exploration or route == &"combat")
	var preferences := _arrange_draft if _arrange_draft != null else _drag_draft if _drag_draft != null else settings.combat_hud if combat_mode else settings.hud
	var enabled := combat_mode or preferences.modular and view != null and view.session_started and not view.party_setup_available and exploration and not fighting
	if _arrange_draft != null: enabled = true
	if enabled != active: _set_active(enabled)
	if not active: return false
	_settings = preferences.duplicate_value()
	_reduced_motion = settings.reduced_motion
	var spellbook := combat_mode and (_contents[0] as ClassicPartyRoster).combat_spellbook_active()
	for index: int in 4:
		_panels[index].visible = index == 0 or not combat_mode
		_panels[index].configure(TITLES[index], preferences.panels[index], settings.reduced_motion)
		_panels[index].set_required(spellbook if combat_mode else _arrange_draft != null or view.active_interaction_request() != null and index < 2 or _party_effect_playback and index == 0)
	for index: int in range(4, 6):
		_panels[index].visible = not combat_mode and index - 2 < preferences.bucket_count
		_panels[index].configure(TITLES[index], preferences.extra_panels[index - 4], settings.reduced_motion)
		_panels[index].set_required(_arrange_draft != null)
	_show_effects(view)
	%EffectsDock.self_modulate.a = preferences.effects_bar_opacity
	_refresh_dock.call_deferred(view)
	%StatusStrip.visible = preferences.status_strip_visible and not combat_mode
	%StatusStrip.self_modulate.a = preferences.status_strip_opacity
	return true


## The status strip repeats the facts the status controller writes into the message panel's
## hidden labels, so that controller keeps one set of labels to bind.
func _process(_delta: float) -> void:
	if not active:
		return
	# A prompt standing on the message panel replaces it; showing both would double the text.
	var prompt := _prompt_ref.get_ref() as Control if _prompt_ref != null else null
	_panels[1].modulate.a = 0.0 if prompt != null and prompt.is_visible_in_tree() and prompt.get_global_rect().intersects(_panels[1].get_global_rect()) else 1.0
	if not %StatusStrip.visible:
		return
	var facts := _contents[1].get_node("NarrativeColumn/Facts")
	var items := %StatusStrip.get_node("Items")
	for item: String in ["Clock", "Coordinates", "Gold", "Light"]:
		var source := facts.get_node(item) as Label
		var shown := items.get_node(item) as Label
		if shown.text != source.text:
			shown.text = source.text
			shown.tooltip_text = source.tooltip_text
			shown.visible = not source.text.is_empty()
	var fatigue := facts.get_node("FatigueGauge/Fatigue") as Label
	var bar := facts.get_node("FatigueGauge/FatigueBar") as ProgressBar
	(items.get_node("Fatigue") as Label).text = fatigue.text
	var shown_bar := items.get_node("FatigueBar") as ProgressBar
	if shown_bar.value != bar.value or shown_bar.max_value != bar.max_value:
		shown_bar.min_value = bar.min_value
		shown_bar.max_value = bar.max_value
		shown_bar.value = bar.value
		shown_bar.tooltip_text = bar.tooltip_text


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
	if not enabled:
		(get_node("World/Surface/Column/Body/Content/WorldCommandPanel/WorldCommandColumn/WorldCommandDeckCenter/WorldCommandDeckFrame/WorldCommandRows/WorldCommandLowerCenter") as Control).show()
		for grid: GridContainer in [world_grid, party_grid()]:
			UiSizing.constant(grid, &"h_separation", 3)
			UiSizing.constant(grid, &"v_separation", 3)
	(_contents[0].get_node("RosterColumn/Heading") as Control).visible = not enabled
	for record: Node in _contents[0].find_children("Member", "PanelContainer", true, false):
		(record as PartyRosterMemberRow).set_modular_style(enabled)
	for content: Control in _contents:
		content.custom_minimum_size = Vector2.ZERO
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.show()
	(_fixed_contents[0] as Control).visible = not enabled
	(shell.get_node("%BottomRegion") as Control).visible = not enabled
	shell.bind_hud_content(enabled)


func content(index: int) -> Control:
	return _contents[index]


func party_grid() -> GridContainer:
	return _contents[3].get_node("PartyEffectsRow/PartyCommandColumn/CommandDeckCenter/CommandDeckFrame/CommandGrid") as GridContainer


func arrange(profile: UiLayoutProfile) -> void:
	if not active: return
	if combat_mode:
		_arrange_combat(profile)
		return
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
	if not compact:
		var authored_scale := area.size / Vector2(1264.0, 704.0)
		for index: int in 4:
			var source := _authored_rects[index]
			rectangles[index] = Rect2((source.position - Vector2(8.0, 8.0)) * authored_scale, source.size * authored_scale)
			if index >= 2:
				# A command panel is exactly as large as its buttons plus the surface padding.
				var padding := (_panels[index].get_node("Surface") as Control).get_theme_stylebox(&"panel").get_minimum_size()
				rectangles[index].size = commands[index - 2].size + padding
	for index: int in 4:
		var rectangle := rectangles[index]
		if index == 0 and not compact:
			var list := _contents[0].get_node("RosterColumn/PartyScroll/PartyList") as Control
			rectangle.size.y = minf(rectangle.size.y, list.get_combined_minimum_size().y + 12.0 * profile.ui_scale)
		var preference := _settings.panels[index]
		if preference.custom_size: rectangle.size = (area.size * preference.size_fraction).clamp(minimum_panel_size(index), area.size)
		if index == 1: rectangle = _fit_narrative(rectangle)
		if not preference.custom_size: rectangle.size = (rectangle.size * preference.scale).min(area.size)
		if preference.custom_position: rectangle.position = (area.size - rectangle.size).max(Vector2.ZERO) * preference.position
		rectangle.position = rectangle.position.clamp(Vector2.ZERO, (area.size - rectangle.size).max(Vector2.ZERO))
		rectangle.position += area.position
		_panels[index].set_panel_rect(rectangle, preference.scale)
		_contents[index].custom_minimum_size.x = 0.0
		if index == 0: _roster_rect = rectangle
		_place_marker(index, rectangle, area)
	_place_dock()
	var roster := _contents[0] as ClassicPartyRoster
	roster.set_compact_layout(compact)
	for record: Node in roster.find_children("Member", "PanelContainer", true, false):
		(record as PartyRosterMemberRow).set_modular_style(true)
	_arrange_effects(area, Rect2(_panels[1].position - area.position, _panels[1].visual_rect().size), compact)


## In a battle only the roster is placed: at the right edge until the player moves it, and
## the full height of the window while it holds the open combat spellbook.
func _arrange_combat(profile: UiLayoutProfile) -> void:
	var area := profile.application_rect.grow(-8.0)
	_placement_area = area
	_layout_font_scale = profile.font_scale
	_layout_ui_scale = profile.ui_scale
	_layout_narrative_scale = profile.narrative_font_scale
	var roster := _contents[0] as ClassicPartyRoster
	var spellbook := roster.combat_spellbook_active()
	# The roster's heading names the caster while it holds the spellbook.
	(roster.get_node("RosterColumn/Heading") as Control).visible = spellbook
	var width := minf(area.size.x * 0.44, maxf(344.0 * profile.ui_scale, profile.party_width))
	var list := roster.get_node("RosterColumn/PartyScroll/PartyList") as Control
	var rectangle := Rect2(Vector2(area.size.x - width, 0.0), Vector2(width, area.size.y if spellbook else minf(area.size.y, list.get_combined_minimum_size().y + 12.0 * profile.ui_scale)))
	var preference := _settings.panels[0]
	if not spellbook and preference.custom_size: rectangle.size = (area.size * preference.size_fraction).clamp(minimum_panel_size(0), area.size)
	elif not spellbook: rectangle.size = (rectangle.size * preference.scale).min(area.size)
	if not spellbook and preference.custom_position: rectangle.position = (area.size - rectangle.size).max(Vector2.ZERO) * preference.position
	rectangle.position = rectangle.position.clamp(Vector2.ZERO, (area.size - rectangle.size).max(Vector2.ZERO)) + area.position
	_panels[0].set_panel_rect(rectangle, 1.0 if spellbook else preference.scale)
	_contents[0].custom_minimum_size.x = 0.0
	_roster_rect = rectangle
	_place_marker(0, rectangle, area)
	_place_dock()
	roster.set_compact_layout(profile.id == UiLayoutProfile.COMPACT)


## A closed panel's marker sits on the window edge nearest to where the panel was placed,
## level with the panel's centre, so it follows the panel when the player moves it.
func _place_marker(index: int, rectangle: Rect2, area: Rect2) -> void:
	var centre := rectangle.get_center()
	if index >= 2:
		# A closed command bar shows its first command, so it reads as a bucket of buttons.
		_panels[index].dock_icon = null
		for child: Node in _all_grids[index - 2].get_children():
			if _panels[index].dock_icon == null and child is ClassicBitmapButton and (child as Control).visible: _panels[index].dock_icon = (child as ClassicBitmapButton).radial_art_texture()
	var gaps := {
		&"left": rectangle.position.x - area.position.x, &"right": area.end.x - rectangle.end.x,
		&"top": rectangle.position.y - area.position.y, &"bottom": area.end.y - rectangle.end.y,
	}
	# Ties go to the edge the panel uses by default: the long sides for the columns, the bottom for narration.
	var order: Array[StringName] = [&"right", &"left", &"bottom", &"top"]
	if index == 1: order = [&"bottom", &"top", &"left", &"right"]
	elif index >= 2: order = [&"left", &"right", &"bottom", &"top"]
	var edge := order[0]
	for candidate: StringName in order:
		if gaps[candidate] < gaps[edge] - 0.5: edge = candidate
	var dock := Vector2(area.position.x - 8.0 if edge == &"left" else area.end.x + 8.0, centre.y)
	if edge in [&"top", &"bottom"]: dock = Vector2(centre.x, area.position.y - 8.0 if edge == &"top" else area.end.y + 8.0)
	# The party dock stands in for the roster's marker, so that one sits off screen.
	_panels[index].set_dock_marker(edge, (dock if index != 0 else dock + Vector2(4096.0, 0.0)) - rectangle.position)


func minimum_panel_size(index: int) -> Vector2:
	var minimum := Vector2(280.0, 160.0) if index == 0 else Vector2(320.0, 120.0)
	minimum *= maxf(_layout_ui_scale, _layout_font_scale if index == 0 else _layout_narrative_scale)
	if index == 0: minimum.x = maxf(minimum.x, _roster_reading_width())
	return minimum.min(_placement_area.size)


func _roster_reading_width() -> float:
	var required := 0.0
	for row: Node in _contents[0].find_children("Member", "PanelContainer", true, false):
		var details := row.get_node("Character/Details") as Control
		for cell: Control in details.get_node("Record/Stats").get_children():
			var fields := cell.get_child(0) as HBoxContainer
			var value := fields.get_node("Value") as Label
			var text_width := value.get_theme_font("font").get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, value.get_theme_font_size("font_size")).x
			var caption := fields.get_node("Caption") as Label
			required = maxf(required, details.offset_left + text_width + caption.get_combined_minimum_size().x + fields.get_theme_constant("separation") + 32.0)
	return required


func _fit_narrative(rectangle: Rect2) -> Rect2:
	var facts := _contents[1].get_node("NarrativeColumn/Facts") as GridContainer
	facts.add_theme_constant_override("h_separation", roundi(14.0 * _layout_font_scale))
	facts.columns = 3
	while facts.columns > 1 and facts.get_combined_minimum_size().x + 12.0 > rectangle.size.x:
		facts.columns -= 1
	rectangle.size.x = maxf(rectangle.size.x, facts.get_combined_minimum_size().x + 12.0)
	var narrative := _contents[1].get_node("NarrativeColumn/NarrativeText") as RichTextLabel
	var line_height := narrative.get_theme_font_size("normal_font_size") * 1.4
	rectangle.size.y = maxf(rectangle.size.y, facts.get_combined_minimum_size().y + line_height * 3.0 + 20.0)
	rectangle.size = rectangle.size.min(_placement_area.size)
	return rectangle


func _arrange_effects(area: Rect2, narration: Rect2, compact: bool) -> void:
	var grid := %EffectsDock.get_node("EffectsPanel/EffectsColumn/EffectsGrid") as GridContainer
	var cell := (grid.get_child(0) as Control).get_combined_minimum_size()
	var spacing := Vector2(grid.get_theme_constant("h_separation"), grid.get_theme_constant("v_separation"))
	grid.columns = _strip_columns(8, cell + spacing, area.size, _settings.strip_orientations[2], 8 if 8.0 * (cell.x + spacing.x) <= narration.size.x else 4)
	var effect_size := Vector2(grid.columns, ceili(8.0 / grid.columns)) * (cell + spacing) - spacing
	var effect_position := Vector2(narration.end.x - effect_size.x, narration.position.y - effect_size.y - 8.0)
	if not compact and _settings.strip_orientations[2] == "auto" and not _settings.effects_custom_position:
		effect_position = (_authored_effect_rect.position - Vector2(8.0, 8.0)) * (area.size / Vector2(1264.0, 704.0))
	if _settings.strip_orientations[2] == "vertical":
		effect_position = Vector2(_panels[0].position.x - area.position.x - effect_size.x - 8.0, 0.0)
	if _settings.effects_custom_position: effect_position = (area.size - effect_size).max(Vector2.ZERO) * _settings.effects_position
	effect_position = effect_position.clamp(Vector2.ZERO, (area.size - effect_size).max(Vector2.ZERO))
	# The effects bar hangs off the second command bar, so it shares that bar's scale.
	%EffectsDock.position = (area.position - _panels[3].position + effect_position) / _panels[3].scale
	%EffectsDock.size = effect_size
	if compact and _settings.strip_orientations[2] == "auto" and not _settings.panels[0].custom_position and not _settings.panels[0].custom_size and not _settings.effects_custom_position:
		_panels[0].size.y = minf(_panels[0].size.y, maxf(minimum_panel_size(0).y, %EffectsDock.global_position.y - _panels[0].global_position.y - 8.0))


func _strip_columns(count: int, cell: Vector2, available: Vector2, orientation: String, automatic: int) -> int:
	if orientation == "horizontal": return clampi(floori(available.x / cell.x), 1, count)
	if orientation == "vertical": return ceili(float(count) / maxi(1, floori(available.y / cell.y)))
	return automatic


func _arrange_commands(profile: UiLayoutProfile, area: Rect2) -> Array[Rect2]:
	var padding := 2 if _settings.compact_commands else 8
	var world := world_grid
	var party := party_grid()
	var icon_size := Vector2(32, 32)
	var grids := bucket_grids
	for grid: GridContainer in grids:
		for button: Node in grid.get_children():
			if not button is ClassicBitmapButton: continue
			var texture := (button as ClassicBitmapButton).radial_art_texture()
			if button.visible and texture != null: icon_size = icon_size.max(texture.get_size())
	var available_height := maxf(216.0, area.size.y - 112.0)
	var art_scale := profile.bitmap_scale
	while art_scale > 1 and (7 * (icon_size.y * art_scale + 2 * padding) + 8 > available_height or 7 * (icon_size.x * art_scale + 2 * padding) > area.size.x):
		art_scale -= 1
	var cell := icon_size * art_scale + Vector2.ONE * 2 * padding
	var columns := 1 if 13 * cell.y + 8 <= available_height else 2
	var counts: Array[int] = [0, 0, 0, 0]
	for index: int in grids.size():
		for child: Node in grids[index].get_children():
			if child is BaseButton and (child as BaseButton).visible: counts[index] += 1
		counts[index] = maxi(1, counts[index])
	for index: int in grids.size():
		var grid := grids[index]
		grid.columns = _strip_columns(counts[index], cell, area.size, _settings.strip_orientations[index] if index < 2 else _settings.extra_orientations[index - 2], columns)
		if index >= 2: _extra_sizes[index - 2] = Vector2(mini(grid.columns, counts[index]), ceili(float(counts[index]) / grid.columns)) * cell
		grid.add_theme_constant_override("h_separation", 0)
		grid.add_theme_constant_override("v_separation", 0)
		for child: Node in grid.get_children():
			if child is BaseButton and child.has_method("set_modular_icon_layout"):
				child.call("set_modular_icon_layout", art_scale, padding)
				(child as Control).custom_minimum_size = cell
	(_contents[2].get_node("WorldCommandColumn/WorldCommandDeckCenter/WorldCommandDeckFrame/WorldCommandRows/WorldCommandLowerCenter") as Control).hide()
	(_contents[3].get_node("PartyEffectsRow/TorchDock") as Control).hide()
	# Reflow after command refresh briefly restores the larger Fixed artwork metrics.
	(_contents[3].get_node("PartyEffectsRow") as BoxContainer).queue_sort()
	var world_size := Vector2(mini(world.columns, counts[0]), ceili(float(counts[0]) / world.columns)) * cell
	var party_size := Vector2(mini(party.columns, counts[1]), ceili(float(counts[1]) / party.columns)) * cell
	var party_position := Vector2(0, world_size.y + 8)
	if _settings.strip_orientations[0] == "horizontal" and _settings.strip_orientations[1] == "horizontal" and world_size.x + party_size.x + 8 <= area.size.x:
		party_position = Vector2(world_size.x + 8, 0)
	return [Rect2(Vector2.ZERO, world_size), Rect2(party_position, party_size)]


## Keeps the party dock current and flashes members with bad news: stamina lost or a harmful
## condition starting. Healing, recovery and conditions ending stay quiet. The full roster
## opens on its own only when the party itself changes.
func observe(previous: GameView, current: GameView) -> void:
	if not active or current == null:
		return
	_refresh_dock.call_deferred(current)
	_show_effects(current)
	if previous == null or not previous.session_started or previous.campaign_id != current.campaign_id: return
	if not _settings.panels[0].reveal_on_changes: return
	var affected: Array[String] = []
	for index: int in current.party_members.size():
		var after := current.party_members[index]
		var before := previous.party_members[index] if index < previous.party_members.size() else null
		if before == null or before.id != after.id:
			_panels[0].reveal(4.0)
			return
		if after.current_health < (%PartyDock as PartyDock).shown_health(after.id, before.current_health) or RosterConditionIcons.harmful_condition_started(before.condition_values, after.condition_values):
			affected.append(after.id)
	if not affected.is_empty():
		(%PartyDock as PartyDock).flash.call_deferred(affected, _reduced_motion)


## The effects bar is its own element: an active party effect always shows it, and the
## "keep visible" preference keeps the empty bar on screen as well.
func _show_effects(view: GameView) -> void:
	var any_active := false
	if view != null and view.party_summary != null:
		var values := view.party_summary.condition_values
		for index: int in range(1, mini(values.size(), 9)):
			any_active = any_active or values[index] != 0
	%EffectsDock.visible = active and not combat_mode and (_settings.effects_bar_visible or any_active)


## Rebuilds the dock from the view, taking portraits and the selection from the roster rows,
## which the shell has refreshed by the time this deferred call runs.
func _refresh_dock(view: GameView) -> void:
	if not active or view == null:
		return
	var portraits := {}
	var selected := {}
	for record: Node in _contents[0].find_children("Member", "PanelContainer", true, false):
		var row := record as PartyRosterMemberRow
		var id := String(row.character_button().get_meta("character_id", ""))
		portraits[id] = row.character_button().icon
		selected[id] = row.current_marker().visible
	var members: Array[Dictionary] = []
	for member: CharacterView in view.party_members:
		var buffs := 0
		for index: int in member.condition_values.size():
			if member.condition_values[index] != 0 and not RosterConditionIcons.HARMFUL.has(index):
				buffs += 1
		var caster := member.maximum_spell_points > 0
		members.append({
			"id": member.id, "portrait": portraits.get(member.id), "selected": bool(selected.get(member.id, false)),
			"stamina": float(member.current_health) / maxf(1.0, member.maximum_health),
			"spell": float(member.spell_points) / maxf(1.0, member.maximum_spell_points) if caster else -1.0,
			"buffs": buffs, "afflicted": not RosterConditionIcons.icon_ids(member).is_empty(),
			"tooltip": "%s\nStamina %d/%d%s" % [member.name, member.current_health, member.maximum_health, "\nSpell points %d/%d" % [member.spell_points, member.maximum_spell_points] if caster else ""],
		})
	(%PartyDock as PartyDock).present(members, _layout_ui_scale)
	_place_dock()


## Places the party dock and the status strip. The dock shows while the full roster is
## closed; unplaced it sits on the roster's side of the window, level with the roster's top.
## The strip sits top centre unless placed. Both run along a window edge they rest on.
func _place_dock() -> void:
	var dock := %PartyDock as PartyDock
	var area := _placement_area
	dock.visible = active and (not _panels[0].is_open() or _live_drag.is_active() or _arrange_draft != null)
	var entries := dock.get_node("Entries") as BoxContainer
	var reach := area.grow(6.0)
	entries.vertical = not (_settings.party_dock_custom_position and HudPlacement.edge(_settings.party_dock_position, true) in [&"top", &"bottom"])
	dock.reset_size()
	var left := _roster_rect.get_center().x < area.get_center().x
	dock.position = Vector2(reach.position.x if left else reach.end.x - dock.size.x, clampf(_roster_rect.position.y, reach.position.y, maxf(reach.position.y, reach.end.y - dock.size.y)))
	if _settings.party_dock_custom_position:
		dock.position = reach.position + (reach.size - dock.size).max(Vector2.ZERO) * _settings.party_dock_position
	# The third and fourth command bars float: beside the first bar until the player moves them.
	for index: int in range(4, 6):
		var extra_scale := _settings.extra_panels[index - 4].scale
		var extent := ((_extra_sizes[index - 4] + (_panels[index].get_node("Surface") as Control).get_theme_stylebox(&"panel").get_minimum_size()) * extra_scale).min(area.size)
		var corner := Vector2(_panels[2].visual_rect().size.x + 8.0 + (index - 4) * (extent.x + 8.0), 0.0)
		if _settings.extra_panels[index - 4].custom_position: corner = (area.size - extent).max(Vector2.ZERO) * _settings.extra_panels[index - 4].position
		var rectangle := Rect2(area.position + corner.clamp(Vector2.ZERO, (area.size - extent).max(Vector2.ZERO)), extent)
		_panels[index].set_panel_rect(rectangle, extra_scale)
		_place_marker(index, rectangle, area)
	var strip := %StatusStrip as Control
	(strip.get_node("Items") as BoxContainer).vertical = _settings.status_strip_custom_position and HudPlacement.edge(_settings.status_strip_position, false) in [&"left", &"right"]
	strip.reset_size()
	strip.position = Vector2(area.position.x + (area.size.x - strip.size.x) * 0.5, area.position.y)
	if _settings.status_strip_custom_position:
		strip.position = area.position + (area.size - strip.size).max(Vector2.ZERO) * _settings.status_strip_position


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
	for index: int in 4: result.append(_panels[index].visual_rect() if _panels[index].visible else Rect2())
	for surface: Control in [%EffectsDock, %StatusStrip, %PartyDock]:
		result.append(Rect2(surface.global_position - global_position, surface.size) if surface.visible else Rect2())
	for index: int in range(4, 6):
		result.append(_panels[index].visual_rect() if _panels[index].visible else Rect2())
	return result


## Every movable element in placement order: the four panels, the effects bar, the status
## strip, the party dock and the extra command bars. Hidden ones report an empty rectangle.
func _element_rectangles() -> Array[Rect2]:
	var result := panel_rectangles()
	for index: int in 6:
		if not _panels[index].is_open(): result[index if index < 4 else index + 3] = Rect2()
	return result


## Shows a placement that is still being dragged, or saves it once `finished`.
func _apply_placement(value: HudPreferences, finished: bool) -> void:
	_drag_draft = null if finished else value.duplicate_value()
	if finished: _commit(func(_hud: HudPreferences) -> HudPreferences: return value)
	(_shell_ref.get_ref() as GameShell).refresh_layout()


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
	if _command_drag.handle(event, get_global_mouse_position()) or _live_drag.handle(event, get_global_mouse_position() - global_position, _placement_area, _layout_ui_scale, _settings):
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if %EffectsDock.is_visible_in_tree() and %EffectsDock.get_global_rect().has_point(get_global_mouse_position()):
			panel_menu.open_surface(_settings.effects_bar_visible, get_global_mouse_position(), shell.controller.pause.allowed())
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
	_menu_button = null
	_menu_target = (index - 1) % _settings.bucket_count
	_menu_panel = index
	if index >= 2:
		# The button under the pointer, or for a controller the focused one, can be moved on.
		var focused := get_viewport().gui_get_focus_owner()
		for child: Node in _all_grids[index - 2].get_children():
			var button := child as ClassicBitmapButton
			if button != null and button.visible and (button.get_global_rect().has_point(get_global_mouse_position()) or button == focused):
				_menu_button = button
	panel_menu.open(_panels[index], location, shell.controller.pause.allowed() and not combat_mode, "" if _menu_button == null else "Move button to %s" % TITLES[2 + _menu_target])


func _arrange_from_menu() -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if not shell.controller.pause.open(): return
	shell.controller.pause.activate(&"interface")
	shell.hud_arrange.open(shell)


func _pin_changed(pinned: bool, index: int) -> void:
	_commit(func(hud: HudPreferences) -> HudPreferences:
		if index < 0: hud.effects_bar_visible = pinned
		else: hud.panel_at(index).auto_hide = not pinned
		return hud)


## Saves the HUD preferences returned by `edit`, which receives a copy of the current ones.
func _commit(edit: Callable) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if shell == null: return
	var baseline := shell.settings
	var candidate := PresentationSettings.from_data(baseline.to_data())
	# A battle's roster and dock keep their own places in the combat HUD preferences.
	if combat_mode: candidate.combat_hud = (edit.call(candidate.combat_hud) as HudPreferences).duplicate_value()
	else: candidate.hud = (edit.call(candidate.hud) as HudPreferences).duplicate_value()
	var commit := shell.navigator.content_presenter.system_preferences.commit_preferences
	var error := String(commit.call(baseline, candidate)) if commit.is_valid() else "Settings storage is unavailable."
	if not error.is_empty():
		shell.status.set_status(error, true)
		shell.refresh_layout()
