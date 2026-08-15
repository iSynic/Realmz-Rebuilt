class_name InteractionPresenter
extends PanelContainer

const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")

signal response_submitted(response: InteractionResponse)
signal presentation_action_requested(action: StringName, payload: Dictionary)

@onready var _prompt: Label = %InteractionPrompt
@onready var _heading: Label = %InteractionHeading
@onready var _options: VBoxContainer = %InteractionOptions
@onready var _scroll: ScrollContainer = $InteractionScroll
@onready var _stage_opaque_backing: ColorRect = $StageOpaqueBacking
@onready var _stage_backing: TextureRect = $StageBacking

var _request: InteractionRequest
var _component: InteractionComponent
var _stage_rect := Rect2(32.0, 32.0, 640.0, 480.0)
var _textbox_rect := Rect2(8.0, 424.0, 696.0, 168.0)
var _combat_rect := Rect2(0.0, 424.0, 960.0, 176.0)
var _passive_text: bool = false
var _playback_masked: bool = false


func present(request: InteractionRequest, classic_text_context: String = "", game_view: GameView = null, media: ClassicMediaCatalog = null) -> void:
	_request = request
	_passive_text = false
	_playback_masked = false
	_reset_interaction_scroll()
	_clear_options()
	visible = request != null
	var full_stage := uses_full_stage_region(request)
	_stage_opaque_backing.visible = full_stage
	_stage_backing.visible = full_stage
	if request == null:
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
		return
	_set_heading(_heading_for_kind(request.kind))
	_prompt.text = _prompt_for(request, classic_text_context)
	_prompt.visible = not _prompt.text.is_empty()
	if _is_player_map_request(request):
		_prompt.text = ""
		_prompt.visible = false
	if request.kind == &"combat_action":
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	_component = _component_for(request, game_view, media)
	if _component == null:
		_set_heading("Unsupported Interaction")
		_prompt.text = "Unsupported Realmz interaction: %s" % String(request.kind)
		_add_hint("This package cannot continue because its interaction contract is unavailable.")
		return
	_component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_component.add_theme_constant_override("separation", 8)
	_component.payload_submitted.connect(_submit_payload)
	_component.presentation_action_requested.connect(func(action: StringName, payload: Dictionary) -> void: presentation_action_requested.emit(action, payload))
	_options.add_child(_component)
	_component.build(request)
	_apply_classic_region()
	call_deferred("_prepare_interaction_focus")


func present_combat_playback_mask() -> void:
	_request = null
	_passive_text = false
	_playback_masked = true
	_reset_interaction_scroll()
	_clear_options()
	_set_heading("")
	_prompt.text = ""
	_prompt.visible = false
	_stage_opaque_backing.visible = false
	_stage_backing.visible = false
	_add_hint("Resolving combat…  Press Space to skip visual playback.")
	visible = true
	_apply_classic_region()


func set_classic_regions(stage_rect: Rect2, textbox_rect: Rect2, combat_rect: Rect2 = Rect2()) -> void:
	_stage_rect = stage_rect
	_textbox_rect = textbox_rect
	_combat_rect = combat_rect if combat_rect.has_area() else textbox_rect
	_apply_classic_region()


func dismiss_passive_text() -> bool:
	if _request != null or not visible:
		return false
	visible = false
	_passive_text = false
	_prompt.text = ""
	return true


func present_passive_classic_text(text: String) -> void:
	if _request != null:
		return
	_playback_masked = false
	_clear_options()
	_set_heading("")
	_prompt.text = text
	_prompt.visible = not text.is_empty()
	_passive_text = not text.is_empty()
	visible = not text.is_empty()
	_apply_classic_region()


func has_blocking_request() -> bool:
	return _request != null or _playback_masked


func submit_active_payload(payload: Dictionary) -> bool:
	if _playback_masked or _request == null or _request.kind != InteractionRequest.COMBAT:
		return false
	_submit_payload(payload)
	return true


func accepts_combat_spatial_input() -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction and (_component as BattleInteraction).accepts_spatial_input()


func handle_fast_spell(slot_index: int, use_spell: bool) -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction and (_component as BattleInteraction).handle_fast_spell(slot_index, use_spell)


func inspect_combatant(combatant_id: String) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).inspect_combatant(combatant_id)


func update_combat_targeting(selection: Dictionary) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).update_battlefield_targeting(selection)


func combat_targeting_cancelled() -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).battlefield_targeting_cancelled()


func set_text_scale(value: float) -> void:
	_heading.add_theme_font_size_override("font_size", int(round(18.0 * value)))
	_prompt.add_theme_font_size_override("font_size", int(round(20.0 * value)))


func _component_for(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> InteractionComponent:
	if _is_player_map_request(request):
		var player_map := PlayerMapInteraction.new()
		player_map.configure(game_view, media)
		return player_map
	match request.kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice":
			return TextChoiceInteraction.new()
		&"age_update":
			return AgeUpdateInteraction.new()
		&"character_selection", &"ally_selection":
			return SelectionInteraction.new()
		&"treasure_distribution":
			return TreasureDistributionInteraction.new()
		&"level_up":
			return LevelUpInteraction.new()
		&"complex_encounter":
			return EncounterInteraction.new()
		&"shop_action":
			return ShopInteraction.new()
		&"temple_action":
			return TempleInteraction.new()
		&"bank_action", &"pooled_wealth_departure":
			return BankInteraction.new()
		&"combat_action":
			return BattleInteraction.new()
		&"session_lifecycle":
			return LifecycleInteractionScript.new()
	return null


func _submit_payload(payload: Dictionary) -> void:
	if _request == null:
		return
	var response := InteractionPresenter.response_for(_request, payload)
	_request = null
	visible = false
	response_submitted.emit(response)


static func response_for(request: InteractionRequest, payload: Dictionary) -> InteractionResponse:
	assert(request != null, "An interaction response requires its originating request")
	return InteractionResponse.from_data(request.request_id, request.kind, payload)


func _clear_options() -> void:
	_component = null
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


func _apply_classic_region() -> void:
	if not is_inside_tree():
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _playback_masked:
		theme_type_variation = &"ClassicOpenRight"
		position = _combat_rect.position
		size = _combat_rect.size
	elif uses_textbox_region(_request, _passive_text):
		theme_type_variation = &"ClassicOpenRight"
		var region := interaction_region(_request, _textbox_rect, _stage_rect, _combat_rect)
		position = region.position
		size = region.size
	elif uses_full_stage_region(_request):
		theme_type_variation = &"ClassicInset"
		position = _stage_rect.position
		size = _stage_rect.size
	else:
		theme_type_variation = &"ClassicInset"
		var desired := Vector2(minf(700.0, _stage_rect.size.x - 20.0), minf(520.0, _stage_rect.size.y - 20.0))
		desired.x = maxf(300.0, desired.x)
		desired.y = maxf(260.0, desired.y)
		position = _stage_rect.position + (_stage_rect.size - desired) * 0.5
		size = desired


static func uses_textbox_region(request: InteractionRequest, passive_text: bool = false) -> bool:
	return passive_text or request != null and not _is_player_map_request(request) and request.kind in [&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"combat_action"]


static func uses_full_stage_region(request: InteractionRequest) -> bool:
	return request != null and request.kind == InteractionRequest.ALLY_SELECTION


static func interaction_region(request: InteractionRequest, textbox_rect: Rect2, _unused_stage_rect: Rect2, combat_rect: Rect2 = Rect2()) -> Rect2:
	if request == null or request.kind != &"combat_action":
		return textbox_rect
	return combat_rect if combat_rect.has_area() else textbox_rect


func _add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	_options.add_child(label)


func _focus_first_control() -> void:
	var first := _first_focusable(_options)
	if first != null:
		first.grab_focus()


func _prepare_interaction_focus() -> void:
	_reset_interaction_scroll()
	_focus_first_control()
	_reset_interaction_scroll()


func _reset_interaction_scroll() -> void:
	_scroll.scroll_horizontal = 0
	_scroll.scroll_vertical = 0


static func _title_for_kind(kind: StringName) -> String:
	return String(kind).replace("_", " ").capitalize()


static func _prompt_for(request: InteractionRequest, classic_text_context: String) -> String:
	var explicit_prompt := request.body.prompt_text().strip_edges()
	if not explicit_prompt.is_empty():
		return explicit_prompt
	if request.kind == InteractionRequest.YES_NO:
		var authored_context := classic_text_context.strip_edges()
		if not authored_context.is_empty():
			return authored_context
		return "Choose Yes or No to continue."
	return _title_for_kind(request.kind)


static func _is_player_map_request(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := request.body as InteractionRequest.AcknowledgeBody
	return body != null and body.presentation == &"player-map"


static func _heading_for_kind(kind: StringName) -> String:
	match kind:
		&"acknowledge":
			return ""
		&"age_update":
			return "Age Update"
		&"yes_no":
			return "Question"
		&"encounter_choice", &"scenario_choice", &"complex_encounter":
			return "Encounter"
		&"character_selection", &"ally_selection":
			return "Character Selection"
		&"treasure_distribution":
			return "Treasure"
		&"level_up":
			return "Level Up"
		&"shop_action":
			return "Shop"
		&"temple_action":
			return "Temple"
		&"bank_action":
			return "Bank"
		&"pooled_wealth_departure":
			return "Pooled Wealth"
		&"combat_action":
			return "Battle"
		&"session_lifecycle":
			return "Adventure"
	return _title_for_kind(kind)


func _set_heading(value: String) -> void:
	_heading.text = value
	_heading.visible = not value.is_empty()


static func _first_focusable(parent: Node) -> Control:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).visible and (child as Control).focus_mode != Control.FOCUS_NONE and not (child is BaseButton and (child as BaseButton).disabled):
			return child as Control
		var nested := _first_focusable(child)
		if nested != null:
			return nested
	return null
