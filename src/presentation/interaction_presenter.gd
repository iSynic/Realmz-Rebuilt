class_name InteractionPresenter
extends PanelContainer

const PickLockInteractionScript := preload("res://src/presentation/interaction_components/pick_lock_interaction.gd")
const ThiefEncounterInteractionScript := preload("res://src/presentation/interaction_components/thief_encounter_interaction.gd")

const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")

signal response_submitted(response: InteractionResponse)
signal combat_targeting_requested(request: CombatTargetingRequest)
signal combat_targeting_confirm_requested
signal combat_targeting_cancel_requested
signal combatant_focus_requested(combatant_id: String, play_sound: bool)
signal reveal_friends_requested
signal presentation_sound_requested(sound_id: int)
signal presentation_status_requested(text: String, is_error: bool)
signal combat_spellbook_requested(actor_id: String, options: Array[InteractionRequestValue.CastOption])
signal combat_spellbook_closed

@onready var _prompt: Label = %InteractionPrompt
@onready var _heading: Label = %InteractionHeading
@onready var _options: VBoxContainer = %InteractionOptions
@onready var _content: BoxContainer = $InteractionScroll/InteractionContent
@onready var _prompt_column: VBoxContainer = %PromptColumn
@onready var _scroll: ScrollContainer = $InteractionScroll
@onready var _stage_opaque_backing: ColorRect = $StageOpaqueBacking
@onready var _stage_backing: TextureRect = $StageBacking

var _request: InteractionRequest
var _component: InteractionComponent
var _stage_rect := Rect2(0.0, 28.0, 992.0, 502.0)
var _textbox_rect := Rect2(8.0, 530.0, 984.0, 182.0)
var _combat_rect := Rect2(0.0, 530.0, 1280.0, 190.0)
var _application_rect := Rect2(0.0, 32.0, 1280.0, 688.0)
var _passive_text: bool = false
var _playback_masked: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_claim_modal_layer()


func present(request: InteractionRequest, classic_text_context: String = "", game_view: GameView = null, media: ClassicMediaCatalog = null) -> void:
	_request = request
	_passive_text = false
	_playback_masked = false
	_reset_interaction_scroll()
	_clear_options()
	visible = request != null
	if visible:
		_claim_modal_layer()
	var full_stage := uses_full_stage_region(request)
	_stage_opaque_backing.visible = full_stage
	_stage_backing.visible = full_stage
	if request == null:
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
		return
	_set_heading(_heading_for_kind(request.kind))
	if request.kind == InteractionRequest.CHARACTER_SELECTION and (request.body as InteractionRequest.CharacterSelectionRequestBody).spell_context != null:
		_set_heading("Spell Target")
	_prompt.text = _prompt_for(request, classic_text_context)
	_prompt.visible = not _prompt.text.is_empty()
	if uses_application_workspace(request):
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
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
	_component.response_body_submitted.connect(_submit_body)
	_component.combat_targeting_requested.connect(func(targeting_request: CombatTargetingRequest) -> void: combat_targeting_requested.emit(targeting_request))
	_component.combat_targeting_confirm_requested.connect(func() -> void: combat_targeting_confirm_requested.emit())
	_component.combat_targeting_cancel_requested.connect(func() -> void: combat_targeting_cancel_requested.emit())
	_component.combatant_focus_requested.connect(func(combatant_id: String, play_sound: bool) -> void: combatant_focus_requested.emit(combatant_id, play_sound))
	_component.reveal_friends_requested.connect(func() -> void: reveal_friends_requested.emit())
	_component.presentation_sound_requested.connect(func(sound_id: int) -> void: presentation_sound_requested.emit(sound_id))
	_component.presentation_status_requested.connect(func(text: String, is_error: bool) -> void: presentation_status_requested.emit(text, is_error))
	_component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: combat_spellbook_requested.emit(actor_id, options))
	_component.combat_spellbook_closed.connect(func() -> void: combat_spellbook_closed.emit())
	_options.add_child(_component)
	_options.visible = true
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
	_claim_modal_layer()
	_apply_classic_region()


func set_classic_regions(stage_rect: Rect2, textbox_rect: Rect2, combat_rect: Rect2 = Rect2()) -> void:
	_stage_rect = stage_rect
	_textbox_rect = textbox_rect
	_combat_rect = combat_rect if combat_rect.has_area() else textbox_rect
	_application_rect = Rect2(
		stage_rect.position.x,
		stage_rect.position.y,
		maxf(stage_rect.size.x, _combat_rect.size.x),
		maxf(stage_rect.size.y, _combat_rect.end.y - stage_rect.position.y)
	)
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
	if visible:
		_claim_modal_layer()
	_apply_classic_region()


func has_blocking_request() -> bool:
	return _request != null or _playback_masked


func submit_active_body(body: InteractionResponse.CombatBody) -> bool:
	if _playback_masked or _request == null or _request.kind != InteractionRequest.COMBAT:
		return false
	_submit_body(body)
	return true


func submit_character_selection(character_ids: Array[String]) -> bool:
	if _playback_masked or _request == null or _request.kind != InteractionRequest.CHARACTER_SELECTION:
		return false
	var body := _request.body as InteractionRequest.CharacterSelectionRequestBody
	if body == null or character_ids.size() != body.count:
		return false
	_submit_body(InteractionResponse.SelectionBody.new(character_ids))
	return true


func accepts_combat_spatial_input() -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction and (_component as BattleInteraction).accepts_spatial_input()


func handle_fast_spell(slot_index: int, use_spell: bool) -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction and (_component as BattleInteraction).handle_fast_spell(slot_index, use_spell)


func inspect_combatant(combatant_id: String) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).inspect_combatant(combatant_id)


func update_combat_targeting(selection: CombatTargetingState) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).update_battlefield_targeting(selection)


func combat_targeting_cancelled() -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).battlefield_targeting_cancelled()


func cast_combat_spell(option: InteractionRequestValue.CastOption) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).cast_spell_option(option)


func close_combat_spellbook() -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).close_spellbook()


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
			var selection := SelectionInteraction.new()
			selection.configure(media, game_view)
			return selection
		&"treasure_distribution":
			var treasure := TreasureDistributionInteraction.new()
			treasure.configure(_application_rect.size.x < 1000.0)
			return treasure
		&"level_up":
			var level_up := LevelUpInteraction.new()
			level_up.configure(game_view, media)
			return level_up
		&"complex_encounter":
			return EncounterInteraction.new()
		&"thief_encounter":
			var thief := ThiefEncounterInteractionScript.new()
			thief.configure(media)
			return thief
		&"pick_lock":
			var pick_lock := PickLockInteractionScript.new()
			pick_lock.configure(media)
			return pick_lock
		&"shop_action":
			var shop := ShopInteraction.new()
			shop.configure(_application_rect.size.x < 1000.0)
			return shop
		&"temple_action":
			var temple := TempleInteraction.new()
			temple.configure(media, _application_rect.size.x < 1000.0)
			return temple
		&"bank_action", &"pooled_wealth_departure":
			var bank := BankInteraction.new()
			bank.configure(_application_rect.size.x < 1000.0)
			return bank
		&"combat_action":
			var battle := BattleInteraction.new()
			battle.configure(_combatant_icon_textures(game_view, media))
			return battle
		&"session_lifecycle":
			return LifecycleInteractionScript.new()
	return null


func _combatant_icon_textures(game_view: GameView, media: ClassicMediaCatalog) -> Dictionary:
	var result: Dictionary = {}
	if game_view == null or game_view.combat_view == null or media == null:
		return result
	for character: CharacterView in game_view.party_members:
		var texture := media.image_texture(media.asset_by_id(character.combat_icon_id))
		if texture != null:
			result[character.id] = texture
	for monster: MonsterView in game_view.combat_view.monsters:
		var texture := media.image_texture(media.asset_by_resource(monster.icon_resource_type, monster.icon_id))
		if texture != null:
			result[monster.id] = texture
	return result


func _submit_body(body: InteractionResponse.Body) -> void:
	if _request == null:
		return
	var response := InteractionPresenter.response_for(_request, body)
	_request = null
	visible = false
	response_submitted.emit(response)


static func response_for(request: InteractionRequest, body: InteractionResponse.Body) -> InteractionResponse:
	assert(request != null, "An interaction response requires its originating request")
	return InteractionResponse.new(request.request_id, request.kind, body)


func _clear_options() -> void:
	combat_spellbook_closed.emit()
	_component = null
	_options.visible = false
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
		var region := _application_rect if uses_application_workspace(_request) else _stage_rect
		position = region.position
		size = region.size
	else:
		theme_type_variation = &"ClassicInset"
		var desired := Vector2(minf(700.0, _stage_rect.size.x - 20.0), minf(520.0, _stage_rect.size.y - 20.0))
		desired.x = maxf(300.0, desired.x)
		desired.y = maxf(260.0, desired.y)
		position = _stage_rect.position + (_stage_rect.size - desired) * 0.5
		size = desired
	_apply_content_layout()


func _apply_content_layout() -> void:
	var split_textbox := uses_textbox_region(_request, _passive_text) and (_request == null or _request.kind != InteractionRequest.COMBAT)
	_content.vertical = not split_textbox
	if split_textbox:
		var available_width := _textbox_rect.size.x
		var prompt_width := minf(620.0, maxf(320.0, available_width * 0.66))
		if _request != null and _request.kind == InteractionRequest.WORD_AND_ACTION:
			prompt_width = minf(620.0, maxf(300.0, available_width - 410.0))
		_prompt_column.custom_minimum_size.x = prompt_width
		_prompt_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_options.custom_minimum_size.x = 220.0
	else:
		_prompt_column.custom_minimum_size.x = 0.0
		_prompt_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_options.custom_minimum_size.x = 0.0


static func uses_textbox_region(request: InteractionRequest, passive_text: bool = false) -> bool:
	return passive_text or request != null and not _is_player_map_request(request) and request.kind in [&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"character_selection", &"complex_encounter", &"combat_action"]


static func uses_full_stage_region(request: InteractionRequest) -> bool:
	return request != null and (request.kind == InteractionRequest.ALLY_SELECTION or uses_application_workspace(request))


static func uses_application_workspace(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.TREASURE_DISTRIBUTION, InteractionRequest.LEVEL_UP, InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE]


static func interaction_region(request: InteractionRequest, textbox_rect: Rect2, _unused_stage_rect: Rect2, combat_rect: Rect2 = Rect2()) -> Rect2:
	if request == null or request.kind != &"combat_action":
		return textbox_rect
	return combat_rect if combat_rect.has_area() else textbox_rect


func _add_hint(text: String) -> void:
	_options.visible = true
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


func _claim_modal_layer() -> void:
	var parent := get_parent()
	if parent != null and get_index() != parent.get_child_count() - 1:
		parent.move_child(self, parent.get_child_count() - 1)


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
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice":
			return ""
		&"age_update":
			return "Age Update"
		&"complex_encounter", &"thief_encounter":
			return "Encounter"
		&"pick_lock":
			return "Pick Lock"
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
