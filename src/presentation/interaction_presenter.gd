class_name InteractionPresenter
extends PanelContainer

signal response_submitted(response: InteractionResponse)

@onready var _prompt: Label = %InteractionPrompt
@onready var _heading: Label = %InteractionHeading
@onready var _options: VBoxContainer = %InteractionOptions

var _request: InteractionRequest
var _component: InteractionComponent
var _stage_rect := Rect2(32.0, 32.0, 640.0, 480.0)
var _textbox_rect := Rect2(8.0, 424.0, 696.0, 168.0)
var _passive_text: bool = false


func present(request: InteractionRequest, classic_text_context: String = "") -> void:
	_request = request
	_passive_text = false
	_clear_options()
	visible = request != null
	if request == null:
		_set_heading("")
		_prompt.text = ""
		return
	_set_heading(_heading_for_kind(request.kind))
	_prompt.text = _prompt_for(request, classic_text_context)
	_component = _component_for(request.kind)
	if _component == null:
		_set_heading("Unsupported Interaction")
		_prompt.text = "Unsupported Realmz interaction: %s" % String(request.kind)
		_add_hint("This package cannot continue because its interaction contract is unavailable.")
		return
	_component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_component.add_theme_constant_override("separation", 8)
	_component.payload_submitted.connect(_submit_payload)
	_options.add_child(_component)
	_component.build(request)
	_apply_classic_region()
	call_deferred("_focus_first_control")


func set_classic_regions(stage_rect: Rect2, textbox_rect: Rect2) -> void:
	_stage_rect = stage_rect
	_textbox_rect = textbox_rect
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
	_clear_options()
	_set_heading("")
	_prompt.text = text
	_passive_text = not text.is_empty()
	visible = not text.is_empty()
	_apply_classic_region()


func has_blocking_request() -> bool:
	return _request != null


func set_text_scale(value: float) -> void:
	_heading.add_theme_font_size_override("font_size", int(round(18.0 * value)))
	_prompt.add_theme_font_size_override("font_size", int(round(20.0 * value)))


func _component_for(kind: StringName) -> InteractionComponent:
	match kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice":
			return TextChoiceInteraction.new()
		&"character_selection", &"ally_selection":
			return SelectionInteraction.new()
		&"complex_encounter":
			return EncounterInteraction.new()
		&"shop_action":
			return ShopInteraction.new()
		&"temple_action":
			return TempleInteraction.new()
		&"bank_action":
			return BankInteraction.new()
		&"combat_action":
			return BattleInteraction.new()
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
	return InteractionResponse.new(request.request_id, request.kind, payload)


func _clear_options() -> void:
	_component = null
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


func _apply_classic_region() -> void:
	if not is_inside_tree():
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if uses_textbox_region(_request, _passive_text):
		theme_type_variation = &"ClassicOpenRight"
		position = _textbox_rect.position
		size = _textbox_rect.size
	else:
		theme_type_variation = &"ClassicInset"
		var desired := Vector2(minf(700.0, _stage_rect.size.x - 20.0), minf(520.0, _stage_rect.size.y - 20.0))
		desired.x = maxf(300.0, desired.x)
		desired.y = maxf(260.0, desired.y)
		position = _stage_rect.position + (_stage_rect.size - desired) * 0.5
		size = desired


static func uses_textbox_region(request: InteractionRequest, passive_text: bool = false) -> bool:
	return passive_text or request != null and request.kind in [&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice"]


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


static func _title_for_kind(kind: StringName) -> String:
	return String(kind).replace("_", " ").capitalize()


static func _prompt_for(request: InteractionRequest, classic_text_context: String) -> String:
	var explicit_prompt := String(request.payload.get("prompt", "")).strip_edges()
	if not explicit_prompt.is_empty():
		return explicit_prompt
	if request.kind == InteractionRequest.YES_NO:
		var authored_context := classic_text_context.strip_edges()
		if not authored_context.is_empty():
			return authored_context
		return "Choose Yes or No to continue."
	return _title_for_kind(request.kind)


static func _heading_for_kind(kind: StringName) -> String:
	match kind:
		&"acknowledge":
			return ""
		&"yes_no":
			return "Question"
		&"encounter_choice", &"scenario_choice", &"complex_encounter":
			return "Encounter"
		&"character_selection", &"ally_selection":
			return "Character Selection"
		&"shop_action":
			return "Shop"
		&"temple_action":
			return "Temple"
		&"bank_action":
			return "Bank"
		&"combat_action":
			return "Battle"
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
