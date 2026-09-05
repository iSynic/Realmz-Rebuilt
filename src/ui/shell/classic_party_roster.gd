## Binds detached party records to the scene-authored persistent roster.
class_name ClassicPartyRoster
extends PanelContainer

signal character_selected(character_id: String)
signal character_activated(character_id: String)
signal combat_auto_changed(character_id: String, enabled: bool)
signal character_selection_completed(character_ids: Array[String])
signal combat_spell_cast_requested(option: InteractionRequestValue.CastOption)
signal combat_spellbook_back_requested

const CLASSIC_PORTRAIT_STAGE_SIZE := Vector2i(50, 50)
const CLASSIC_DEATH_HEALTH := -10
const CLASSIC_PORTRAIT_SHADE_CICN := 2019
const CLASSIC_DEATH_MARKER_CICN := 2015

@export var member_row_scene: PackedScene
@export var empty_row_scene: PackedScene

@onready var _party_list: VBoxContainer = %PartyList
@onready var _heading: Label = %Heading
@onready var _party_scroll: ScrollContainer = %PartyScroll
@onready var _spellbook: CombatRosterSpellbook = $RosterColumn/CombatRosterSpellbook
@onready var _selection_cursor_layer: CanvasLayer = $CharacterSelectionCursorLayer
@onready var _selection_cursor_label: Label = %CharacterSelectionCursorCount

var _media: ClassicMediaCatalog
var _portrait_composites: Dictionary = {}
var _selected_character_id: String = ""
var _current_view: GameView
var _selection_request_id: String = ""
var _selection_count: int = 0
var _selection_eligible_ids: Array[String] = []
var _selection_order: Array[String] = []
var _combat_spellbook_active: bool = false
var _controls_ready: bool = false


func _exit_tree() -> void:
	_restore_pointer()


func _process(_delta: float) -> void:
	if not character_selection_active() or not is_instance_valid(_selection_cursor_label):
		set_process(false)
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	var viewport := get_viewport()
	if viewport != null:
		_selection_cursor_label.position = viewport.get_mouse_position() + Vector2(14.0, 10.0)


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_portrait_composites.clear()


func present(view: GameView, selected_character_id: String = "") -> void:
	_ensure_controls()
	_party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_combat_spellbook_active = false
	_current_view = view
	_selected_character_id = selected_character_id
	_clear_party()
	if view == null or not view.session_started:
		_heading.text = "Party"
		_add_empty("No active party")
		return
	_heading.text = "Party • Pick %d" % (_selection_count - _selection_order.size()) if character_selection_active() else "Party"
	var combat_active := view.combat_view != null and view.combat_view.outcome == &"active"
	var auto_character_ids: Array[String] = []
	if combat_active:
		auto_character_ids.assign(view.combat_view.auto_character_ids)
	for character: CharacterView in view.party_members:
		_add_character(character, combat_active, auto_character_ids)
	for index: int in maxi(0, 6 - view.party_members.size()):
		_add_empty("Empty position %d" % (view.party_members.size() + index + 1))


func present_ordinary_exploration(view: GameView, selected_character_id: String = "", affected_character_ids: Array[String] = []) -> void:
	_ensure_controls()
	if view == null or not view.session_started or character_selection_active() or _combat_spellbook_active or view.combat_view != null:
		present(view, selected_character_id)
		return
	for character: CharacterView in view.party_members:
		if _character_row(character.id) == null:
			present(view, selected_character_id)
			return
	_current_view = view
	var selection_changed := _selected_character_id != selected_character_id
	_selected_character_id = selected_character_id
	for character: CharacterView in view.party_members:
		if affected_character_ids.is_empty() or affected_character_ids.has(character.id):
			_update_exploration_character_row(_character_row(character.id), character)
	if selection_changed:
		_update_current_character_markers()


func present_combat_spellbook(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void:
	_ensure_controls()
	_combat_spellbook_active = true
	_clear_party()
	var actor_name := actor_id
	if _current_view != null:
		for character: CharacterView in _current_view.party_members:
			if character.id == actor_id:
				actor_name = character.name
				break
	_heading.text = "Spellcasting • %s" % actor_name
	_party_scroll.visible = false
	_spellbook.present(actor_id, options, _current_view, size.x)


func close_combat_spellbook() -> void:
	if not _combat_spellbook_active:
		return
	_combat_spellbook_active = false
	if _current_view != null:
		present(_current_view, _selected_character_id)


func combat_spellbook_active() -> bool:
	return _combat_spellbook_active


func _add_character(character: CharacterView, combat_active: bool, auto_character_ids: Array[String]) -> void:
	var record := member_row_scene.instantiate() as PartyRosterMemberRow
	var row := record.character_button()
	row.set_meta("character_id", character.id)
	var base_tooltip := "Level %d • %s / %s • Movement %d/%d" % [character.level, character.race_name, character.caste_name, character.movement, character.maximum_movement]
	var condition_text := _condition_summary(character.condition_values)
	if not condition_text.is_empty():
		base_tooltip += " • %s" % condition_text
	row.set_meta("base_tooltip", base_tooltip)
	row.set_meta("condition_values", character.condition_values.duplicate())
	_bind_character_text(row, character)
	var portrait := _roster_portrait_texture(character)
	if portrait != null:
		row.icon = portrait
	var selecting := character_selection_active()
	record.current_marker().visible = not selecting
	record.current_marker().set_meta("character_id", character.id)
	record.current_marker().color = Color("e0bc53") if character.id == _selected_character_id else Color.TRANSPARENT
	record.selection_number().visible = selecting
	var selected_index := _selection_order.find(character.id)
	record.selection_number().text = str(_selection_count - selected_index) if selected_index >= 0 else ""
	row.disabled = selecting and not _selection_eligible_ids.has(character.id)
	row.tooltip_text = "This character is not eligible for the current selection." if row.disabled else base_tooltip
	if not selecting:
		row.tooltip_text += " • Current character; click to open its record." if character.id == _selected_character_id else " • Click to make this the current character."
	row.pressed.connect(_activate_character.bind(character.id))
	_bind_auto_toggle(record.auto_toggle(), character, combat_active and not selecting, auto_character_ids.has(character.id))
	_party_list.add_child(record)


func _bind_character_text(row: Button, character: CharacterView) -> void:
	var action_fact := "SP %d/%d" % [character.spell_points, character.maximum_spell_points] if character.maximum_spell_points > 0 else "Attacks %d" % character.normal_attacks
	row.text = "%s\nHP %d/%d  •  %s  •  AR %d\n%s / %s" % [
		character.name,
		character.current_health,
		character.maximum_health,
		action_fact,
		character.armor,
		character.race_name,
		character.caste_name,
	]


func _bind_auto_toggle(toggle: Button, character: CharacterView, visible: bool, enabled: bool) -> void:
	toggle.visible = visible
	if not visible:
		return
	var available := character.current_health > 0 and not character.traitor
	toggle.disabled = not available
	toggle.accessibility_name = "Persistent Auto for %s" % character.name
	toggle.button_pressed = enabled
	toggle.tooltip_text = _combat_auto_tooltip(enabled, available)
	toggle.toggled.connect(func(value: bool) -> void:
		toggle.tooltip_text = _combat_auto_tooltip(value, available)
		combat_auto_changed.emit(character.id, value)
	)


func _activate_character(character_id: String) -> void:
	if character_selection_active():
		_toggle_character_selection(character_id)
		return
	var already_selected := character_id == _selected_character_id
	_selected_character_id = character_id
	_update_current_character_markers()
	if already_selected:
		character_activated.emit(character_id)
	else:
		character_selected.emit(character_id)


func _update_exploration_character_row(row: Button, character: CharacterView) -> void:
	if row == null:
		return
	_bind_character_text(row, character)
	var previous_condition_values: Array = row.get_meta("condition_values", []) as Array
	if previous_condition_values == character.condition_values:
		return
	var base_tooltip := "Level %d • %s / %s • Movement %d/%d" % [character.level, character.race_name, character.caste_name, character.movement, character.maximum_movement]
	var condition_text := _condition_summary(character.condition_values)
	if not condition_text.is_empty():
		base_tooltip += " • %s" % condition_text
	row.set_meta("base_tooltip", base_tooltip)
	row.set_meta("condition_values", character.condition_values.duplicate())
	row.tooltip_text = base_tooltip + (" • Current character; click to open its record." if character.id == _selected_character_id else " • Click to make this the current character.")


func _update_current_character_markers() -> void:
	for marker: Node in _party_list.find_children("CurrentCharacterMarker", "ColorRect", true, false):
		(marker as ColorRect).color = Color("e0bc53") if String(marker.get_meta("character_id")) == _selected_character_id else Color.TRANSPARENT
	for row: Node in _party_list.find_children("*", "Button", true, false):
		if row.has_meta("character_id"):
			(row as Button).tooltip_text = String(row.get_meta("base_tooltip")) + (" • Current character; click to open its record." if String(row.get_meta("character_id")) == _selected_character_id else " • Click to make this the current character.")


static func _combat_auto_tooltip(enabled: bool, available: bool) -> String:
	if not available:
		return "Persistent Auto requires a living loyal party character."
	return "Persistent Auto is on. Click to control this character manually." if enabled else "Persistent Auto is off. Click to automate this character's next combat activation."


func present_character_selection(request: InteractionRequest) -> void:
	if request == null or request.kind != InteractionRequest.CHARACTER_SELECTION:
		clear_character_selection()
		return
	var body := request.body as CharacterSelectionRequestBody
	if body == null:
		clear_character_selection()
		return
	if request.request_id != _selection_request_id:
		_selection_request_id = request.request_id
		_selection_count = body.count
		_selection_eligible_ids.clear()
		for candidate: InteractionRequestValue.SelectionCandidate in body.eligible:
			_selection_eligible_ids.append(candidate.id)
		_selection_order.clear()
		call_deferred("_focus_first_eligible")
	_update_selection_cursor()
	_represent()
	_update_selection_cursor()


func clear_character_selection() -> void:
	if not character_selection_active():
		return
	_selection_request_id = ""
	_selection_count = 0
	_selection_eligible_ids.clear()
	_selection_order.clear()
	_restore_pointer()
	_represent()


func character_selection_active() -> bool:
	return not _selection_request_id.is_empty()


func _toggle_character_selection(character_id: String) -> void:
	if not _selection_eligible_ids.has(character_id):
		return
	var existing := _selection_order.find(character_id)
	if existing >= 0:
		_selection_order.remove_at(existing)
	else:
		_selection_order.append(character_id)
	_update_selection_cursor()
	_represent()
	if _selection_order.size() == _selection_count:
		var selected: Array[String] = []
		for character: CharacterView in _current_view.party_members:
			if _selection_order.has(character.id):
				selected.append(character.id)
		_restore_pointer()
		character_selection_completed.emit(selected)


func _represent() -> void:
	if _current_view != null:
		present(_current_view, _selected_character_id)


func _focus_first_eligible() -> void:
	for row: Node in _party_list.find_children("*", "Button", true, false):
		if row is Button and row.has_meta("character_id") and not (row as Button).disabled:
			(row as Button).grab_focus()
			return


func _update_selection_cursor() -> void:
	var remaining := _selection_count - _selection_order.size()
	if remaining < 1:
		_restore_pointer()
		return
	_ensure_controls()
	_selection_cursor_label.text = str(remaining)
	_selection_cursor_label.visible = true
	set_process(true)
	_process(0.0)


func _restore_pointer() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	set_process(false)
	if is_instance_valid(_selection_cursor_label):
		_selection_cursor_label.visible = false
		_selection_cursor_label.text = ""


func play_character_effect(character_id: String, first_resource_id: int, frame_count: int) -> void:
	if character_id.is_empty() or first_resource_id <= 0 or frame_count <= 0:
		return
	var row := _character_row(character_id)
	if row == null:
		return
	var base_icon := row.icon
	var tween := create_tween()
	for frame_index: int in frame_count:
		tween.tween_callback(_set_character_effect_frame.bind(row, base_icon, first_resource_id + frame_index))
		tween.tween_interval(0.055)
	tween.tween_callback(_restore_character_effect.bind(row, base_icon))


func _character_row(character_id: String) -> Button:
	for node: Node in _party_list.find_children("*", "Button", true, false):
		if node.has_meta("character_id") and String(node.get_meta("character_id")) == character_id:
			return node as Button
	return null


func _set_character_effect_frame(row: Button, base_icon: Texture2D, resource_id: int) -> void:
	if not is_instance_valid(row):
		return
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, base_icon)
	_blend_centered(image, _resource_texture(resource_id))
	row.icon = ImageTexture.create_from_image(image)


static func _restore_character_effect(row: Button, base_icon: Texture2D) -> void:
	if is_instance_valid(row):
		row.icon = base_icon


func _add_empty(text: String) -> void:
	var row := empty_row_scene.instantiate() as Label
	row.text = text
	_party_list.add_child(row)


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null or asset_id.is_empty():
		return null
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_picture():
		return null
	return _media.image_texture(asset)


func _roster_portrait_texture(character: CharacterView) -> Texture2D:
	var state := 2 if character.current_health <= CLASSIC_DEATH_HEALTH else 1 if character.current_health < 1 else 0
	var cache_key := "%s|%d" % [character.portrait_id, state]
	if _portrait_composites.has(cache_key):
		return _portrait_composites[cache_key] as Texture2D
	var portrait := _portrait_texture(character.portrait_id)
	if portrait == null and state == 0:
		return null
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, portrait)
	if state > 0:
		_blend_centered(image, _resource_texture(CLASSIC_PORTRAIT_SHADE_CICN))
	if state == 2:
		_blend_centered(image, _resource_texture(CLASSIC_DEATH_MARKER_CICN))
	var composite := ImageTexture.create_from_image(image)
	_portrait_composites[cache_key] = composite
	return composite


func _resource_texture(resource_id: int) -> Texture2D:
	if _media == null:
		return null
	var asset := _media.asset_by_resource("cicn", resource_id)
	return _media.image_texture(asset) if asset != null and asset.is_picture() else null


static func _blend_centered(destination: Image, texture: Texture2D) -> void:
	if texture == null:
		return
	var source := texture.get_image()
	if source == null or source.is_empty():
		return
	var width := mini(source.get_width(), destination.get_width())
	var height := mini(source.get_height(), destination.get_height())
	var source_position := Vector2i((source.get_width() - width) / 2, (source.get_height() - height) / 2)
	var destination_position := Vector2i((destination.get_width() - width) / 2, (destination.get_height() - height) / 2)
	destination.blend_rect(source, Rect2i(source_position, Vector2i(width, height)), destination_position)


func _condition_summary(values: Array[int]) -> String:
	var active: Array[String] = []
	for index: int in values.size():
		if values[index] != 0:
			active.append("Condition %d" % (index + 1))
			if active.size() == 2:
				break
	return ", ".join(active)


func _clear_party() -> void:
	for child: Node in _party_list.get_children():
		_party_list.remove_child(child)
		child.queue_free()
	_party_scroll.visible = true
	_spellbook.close()


func _ensure_controls() -> void:
	if _party_list == null:
		_party_list = get_node("RosterColumn/PartyScroll/PartyList") as VBoxContainer
	if _heading == null:
		_heading = get_node("RosterColumn/Heading") as Label
	if _party_scroll == null:
		_party_scroll = get_node("RosterColumn/PartyScroll") as ScrollContainer
	if _spellbook == null:
		_spellbook = get_node("RosterColumn/CombatRosterSpellbook") as CombatRosterSpellbook
	if _selection_cursor_layer == null:
		_selection_cursor_layer = get_node("CharacterSelectionCursorLayer") as CanvasLayer
	if _selection_cursor_label == null:
		_selection_cursor_label = get_node("CharacterSelectionCursorLayer/CharacterSelectionCursorCount") as Label
	if _controls_ready:
		return
	_controls_ready = true
	_spellbook.cast_requested.connect(func(option: InteractionRequestValue.CastOption) -> void: combat_spell_cast_requested.emit(option))
	_spellbook.back_requested.connect(func() -> void: combat_spellbook_back_requested.emit())
