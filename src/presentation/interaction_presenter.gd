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
var _side_workspace_rect := Rect2(928.0, 28.0, 352.0, 502.0)
var _passive_text: bool = false
var _playback_masked: bool = false
var _playback_status_label: Label
var _autojournal_enabled: bool = true
var _treasure_recipient_id: String = ""
var _side_workspace_panel: PanelContainer
var _modal_shield: ColorRect
var _nested_modal: Control
var _combat_spellbook_open: bool = false
var _floating_choice_layer: Control


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_claim_modal_layer()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _submit_classic_acknowledgement():
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	if _submit_classic_acknowledgement():
		get_viewport().set_input_as_handled()


func _submit_classic_acknowledgement() -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.ACKNOWLEDGE and _component is TextChoiceInteraction and (_component as TextChoiceInteraction).submit_acknowledgement()


func _exit_tree() -> void:
	_close_side_workspace()
	_close_modal_shield()
	_close_floating_choice_modal()


func present(request: InteractionRequest, classic_text_context: String = "", game_view: GameView = null, media: ClassicMediaCatalog = null) -> void:
	if _can_present_nested_treasure_confirmation(request):
		_request = request
		_passive_text = false
		_playback_masked = false
		visible = true
		_claim_modal_layer()
		_present_nested_treasure_confirmation(request, game_view, media)
		_apply_classic_region()
		call_deferred("_prepare_interaction_focus")
		return
	if request == null or request.kind != InteractionRequest.TREASURE_DISTRIBUTION:
		_treasure_recipient_id = ""
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
	if request.kind == InteractionRequest.SESSION_LIFECYCLE:
		_set_heading("")
	if request.kind == InteractionRequest.CHARACTER_SELECTION and (request.body as InteractionRequest.CharacterSelectionRequestBody).spell_context != null:
		_set_heading("Spell Target")
	_prompt.text = _prompt_for(request, classic_text_context)
	_prompt.visible = not _prompt.text.is_empty()
	if uses_application_workspace(request):
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	if request.kind in [InteractionRequest.AGE_UPDATE, InteractionRequest.ALLY_SELECTION, InteractionRequest.LEVEL_UP, InteractionRequest.PICK_LOCK]:
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
	_component.side_workspace_requested.connect(_show_side_workspace)
	_component.side_workspace_closed.connect(_close_side_workspace)
	if _component is TreasureDistributionInteraction:
		var treasure := _component as TreasureDistributionInteraction
		treasure.recipient_selected.connect(func(character_id: String) -> void: _treasure_recipient_id = character_id)
	_options.add_child(_component)
	_options.visible = true
	_component.build(request)
	if uses_floating_choice_modal(request):
		_mount_floating_choice_modal()
	_apply_classic_region()
	call_deferred("_prepare_interaction_focus")


func present_combat_playback_mask(frame: CombatPlaybackFrame = null) -> void:
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
	_playback_status_label = _add_hint(playback_status_text(frame))
	_playback_status_label.name = "CombatPlaybackStatus"
	visible = true
	_claim_modal_layer()
	_apply_classic_region()


func update_combat_playback_frame(frame: CombatPlaybackFrame) -> void:
	if _playback_masked and _playback_status_label != null:
		_playback_status_label.text = playback_status_text(frame)


static func playback_status_text(frame: CombatPlaybackFrame) -> String:
	if frame == null:
		return "Resolving combat…  •  Space skips visual playback"
	var action := frame.display_text
	if action.is_empty():
		action = String(frame.kind).replace("_", " ").capitalize()
	var controls := "Esc cancels Party Auto  •  Space skips visual playback" if frame.automatic else "Space skips visual playback"
	return "%s%s  •  %s" % ["Auto Turn • " if frame.automatic else "", action, controls]


func set_classic_regions(stage_rect: Rect2, textbox_rect: Rect2, combat_rect: Rect2 = Rect2()) -> void:
	_stage_rect = stage_rect
	_textbox_rect = textbox_rect
	_combat_rect = combat_rect if combat_rect.has_area() else textbox_rect
	var outer_stage := stage_rect.grow(8.0)
	_side_workspace_rect = Rect2(outer_stage.end.x, outer_stage.position.y, maxf(0.0, _combat_rect.end.x - outer_stage.end.x), outer_stage.size.y)
	var stage_inset := maxf(0.0, stage_rect.position.x - _combat_rect.position.x)
	var application_top := maxf(0.0, stage_rect.position.y - stage_inset)
	_application_rect = Rect2(
		_combat_rect.position.x,
		application_top,
		_combat_rect.size.x,
		maxf(stage_rect.end.y, _combat_rect.end.y) - application_top
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


func handle_back_request() -> bool:
	return not _playback_masked and _request != null and _component != null and _component.handle_back()


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


func set_combat_spellbook_open(open: bool) -> void:
	if _combat_spellbook_open == open:
		return
	_combat_spellbook_open = open
	_apply_classic_region()


func set_text_scale(value: float) -> void:
	_heading.add_theme_font_size_override("font_size", int(round(18.0 * value)))
	_prompt.add_theme_font_size_override("font_size", int(round(18.0 * value)))


func set_autojournal_enabled(enabled: bool) -> void:
	_autojournal_enabled = enabled


func _component_for(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> InteractionComponent:
	if _is_player_map_request(request):
		var player_map := PlayerMapInteraction.new()
		player_map.configure(game_view, media)
		return player_map
	match request.kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice":
			var text_choice := TextChoiceInteraction.new()
			text_choice.configure(_autojournal_enabled)
			return text_choice
		&"age_update":
			var age_update := AgeUpdateInteraction.new()
			age_update.configure(media)
			return age_update
		&"character_selection", &"ally_selection":
			var selection := SelectionInteraction.new()
			selection.configure(media, game_view)
			return selection
		&"treasure_distribution":
			var treasure := TreasureDistributionInteraction.new()
			treasure.configure(media, game_view, _application_rect.size.x < 1000.0, _treasure_recipient_id)
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
			shop.configure(media, _application_rect.size.x < 1000.0)
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
	_close_side_workspace()
	_close_floating_choice_modal()
	var response := InteractionPresenter.response_for(_request, body)
	var preserve_treasure_workspace := _component is TreasureDistributionInteraction and body is InteractionResponse.TreasureBody and (body as InteractionResponse.TreasureBody).action in [&"assign", &"done"]
	_request = null
	if not preserve_treasure_workspace:
		visible = false
	response_submitted.emit(response)


func begin_treasure_transfer(reduced_motion: bool) -> bool:
	if not _component is TreasureDistributionInteraction:
		return false
	var path := (_component as TreasureDistributionInteraction).take_committed_transfer_path()
	if path.is_empty():
		return false
	if reduced_motion:
		presentation_sound_requested.emit(6002)
		return true
	var pulse := TextureRect.new()
	pulse.name = "TreasureTransferPulse"
	pulse.texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	pulse.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pulse.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.z_index = 200
	pulse.size = Vector2(50.0, 60.0)
	add_child(pulse)
	var source := path["from"] as Vector2
	var target := path["to"] as Vector2
	pulse.global_position = source - pulse.size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(pulse, "global_position", target - Vector2(11.0, 13.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(pulse, "size", Vector2(22.0, 26.0), 0.18)
	tween.tween_property(pulse, "modulate", Color("f0d05b"), 0.09)
	tween.chain().tween_property(pulse, "modulate", Color("62d8ff"), 0.09)
	tween.finished.connect(func() -> void:
		pulse.queue_free()
		presentation_sound_requested.emit(6002)
	)
	return true


static func response_for(request: InteractionRequest, body: InteractionResponse.Body) -> InteractionResponse:
	assert(request != null, "An interaction response requires its originating request")
	return InteractionResponse.new(request.request_id, request.kind, body)


func _clear_options() -> void:
	_combat_spellbook_open = false
	combat_spellbook_closed.emit()
	_close_side_workspace()
	_close_nested_modal()
	_close_floating_choice_modal()
	_component = null
	_playback_status_label = null
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
		if _combat_spellbook_open and _request != null and _request.kind == InteractionRequest.COMBAT:
			region.size.x = minf(region.size.x, maxf(0.0, _side_workspace_rect.position.x - region.position.x))
		position = region.position
		size = region.size
	elif uses_full_stage_region(_request):
		theme_type_variation = &"ClassicInset"
		var region := _application_rect if uses_application_workspace(_request) or _request.kind == InteractionRequest.SESSION_LIFECYCLE else _stage_rect
		position = region.position
		size = region.size
	else:
		theme_type_variation = &"ClassicInset"
		var modal_region := _application_rect if uses_application_modal_region(_request) else _stage_rect
		var desired := preferred_modal_size(_request, modal_region.size)
		position = modal_region.position + (modal_region.size - desired) * 0.5
		size = desired
	_update_modal_shield(not _playback_masked and _request != null and not uses_textbox_region(_request) and not uses_full_stage_region(_request))
	_apply_content_layout()
	_apply_floating_choice_layout()
	_apply_side_workspace_layout()
	_apply_nested_modal_layout()


static func preferred_modal_size(request: InteractionRequest, available_size: Vector2) -> Vector2:
	var preferred := Vector2(700.0, 520.0)
	var minimum := Vector2(300.0, 260.0)
	if request != null:
		match request.kind:
			InteractionRequest.SESSION_LIFECYCLE:
				preferred = Vector2(460.0, 122.0)
				minimum = Vector2(340.0, 110.0)
			InteractionRequest.WORD_AND_ACTION:
				preferred.y = 380.0
			InteractionRequest.LEVEL_UP:
				var body := request.body as InteractionRequest.LevelUpRequestBody
				preferred = Vector2(1080.0, available_size.y - 20.0) if body != null and body.mode == &"spell-selection" else Vector2(760.0, 430.0)
			InteractionRequest.ALLY_SELECTION:
				preferred = Vector2(820.0, 500.0)
	var desired := Vector2(minf(preferred.x, available_size.x - 20.0), minf(preferred.y, available_size.y - 20.0))
	return Vector2(maxf(minimum.x, desired.x), maxf(minimum.y, desired.y))


func _update_modal_shield(needed: bool) -> void:
	if not needed:
		_close_modal_shield()
		return
	if _modal_shield == null:
		_modal_shield = ColorRect.new()
		_modal_shield.name = "LockedModalShield"
		_modal_shield.color = Color(0.01, 0.015, 0.02, 0.62)
		_modal_shield.mouse_filter = Control.MOUSE_FILTER_STOP
		_modal_shield.z_index = z_index - 1
		get_parent().add_child(_modal_shield)
	_modal_shield.position = _application_rect.position
	_modal_shield.size = _application_rect.size
	var parent := get_parent()
	parent.move_child(_modal_shield, modal_shield_target_index(_modal_shield.get_index(), get_index()))


static func modal_shield_target_index(shield_index: int, presenter_index: int) -> int:
	# Moving an existing shield to the presenter's index swaps their order when
	# the shield is already before it. Keep the shield immediately behind the
	# presenter across every rerender so it can never own modal button clicks.
	return maxi(0, presenter_index - 1 if shield_index < presenter_index else presenter_index)


func _close_modal_shield() -> void:
	if _modal_shield == null:
		return
	var shield_parent := _modal_shield.get_parent()
	if shield_parent != null:
		shield_parent.remove_child(_modal_shield)
	_modal_shield.queue_free()
	_modal_shield = null


func _can_present_nested_treasure_confirmation(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.TREASURE_DISTRIBUTION or not _component is TreasureDistributionInteraction:
		return false
	var body := request.body as InteractionRequest.TreasureRequestBody
	return body != null and body.mode == &"completion-confirmation"


func _present_nested_treasure_confirmation(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> void:
	_close_nested_modal()
	_nested_modal = Control.new()
	_nested_modal.name = "TreasureCompletionModalLayer"
	_nested_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_nested_modal.z_index = z_index + 1
	add_child(_nested_modal)
	var shade := ColorRect.new()
	shade.name = "TreasureCompletionShield"
	shade.color = Color(0.01, 0.015, 0.02, 0.68)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nested_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nested_modal.add_child(center)
	var frame := PanelContainer.new()
	frame.name = "TreasureCompletionModal"
	frame.theme_type_variation = &"ClassicInset"
	frame.custom_minimum_size = Vector2(560.0, 210.0)
	center.add_child(frame)
	var component := _component_for(request, game_view, media)
	_component = component
	component.response_body_submitted.connect(_submit_body)
	frame.add_child(component)
	component.build(request)


func _close_nested_modal() -> void:
	if _nested_modal == null:
		return
	remove_child(_nested_modal)
	_nested_modal.queue_free()
	_nested_modal = null


func _mount_floating_choice_modal() -> void:
	_close_floating_choice_modal()
	if _component == null or _component.get_parent() != _options:
		return
	_floating_choice_layer = Control.new()
	_floating_choice_layer.name = "FloatingChoiceModal"
	_floating_choice_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floating_choice_layer.z_index = z_index + 2
	get_parent().add_child(_floating_choice_layer)
	_component.reparent(_floating_choice_layer)
	_options.visible = false


func _close_floating_choice_modal() -> void:
	if _floating_choice_layer == null:
		return
	var modal_parent := _floating_choice_layer.get_parent()
	if modal_parent != null:
		modal_parent.remove_child(_floating_choice_layer)
	_floating_choice_layer.queue_free()
	_floating_choice_layer = null


func _apply_floating_choice_layout() -> void:
	if _floating_choice_layer == null or _component == null:
		return
	var rect := floating_choice_rect(_stage_rect, _textbox_rect, _component.get_combined_minimum_size())
	_floating_choice_layer.position = rect.position
	_floating_choice_layer.size = rect.size
	_component.position = Vector2.ZERO
	_component.size = rect.size


static func floating_choice_rect(stage_rect: Rect2, textbox_rect: Rect2, minimum: Vector2) -> Rect2:
	var modal_size := Vector2(
		minf(maxf(300.0, minimum.x), maxf(300.0, stage_rect.size.x - 24.0)),
		maxf(46.0, minimum.y)
	)
	return Rect2(
		Vector2(stage_rect.end.x - modal_size.x - 10.0, maxf(stage_rect.position.y + 10.0, textbox_rect.position.y - modal_size.y - 8.0)),
		modal_size
	)


func _apply_nested_modal_layout() -> void:
	if _nested_modal == null:
		return
	_nested_modal.position = Vector2.ZERO
	_nested_modal.size = size


func _show_side_workspace(workspace: Control) -> void:
	_close_side_workspace()
	if workspace == null:
		return
	_side_workspace_panel = PanelContainer.new()
	_side_workspace_panel.name = "InteractionSideWorkspace"
	_side_workspace_panel.theme_type_variation = &"ClassicInset"
	_side_workspace_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_side_workspace_panel.z_index = z_index + 1
	get_parent().add_child(_side_workspace_panel)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_workspace_panel.add_child(workspace)
	_apply_side_workspace_layout()


func _close_side_workspace() -> void:
	if _side_workspace_panel == null:
		return
	var workspace_parent := _side_workspace_panel.get_parent()
	if workspace_parent != null:
		workspace_parent.remove_child(_side_workspace_panel)
	_side_workspace_panel.queue_free()
	_side_workspace_panel = null


func _apply_side_workspace_layout() -> void:
	if _side_workspace_panel == null:
		return
	_side_workspace_panel.position = _side_workspace_rect.position
	_side_workspace_panel.size = _side_workspace_rect.size


func _apply_content_layout() -> void:
	var split_textbox := uses_textbox_region(_request, _passive_text) and _request != null and _request.kind == InteractionRequest.CHARACTER_SELECTION
	_content.vertical = not split_textbox
	if split_textbox:
		var available_width := _textbox_rect.size.x
		var prompt_width := minf(620.0, maxf(320.0, available_width * 0.66))
		if _request != null and _request.kind == InteractionRequest.WORD_AND_ACTION:
			prompt_width = 300.0 if available_width < 900.0 else minf(620.0, maxf(300.0, available_width - 410.0))
		_prompt_column.custom_minimum_size.x = prompt_width
		_prompt_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_options.custom_minimum_size.x = 220.0
	else:
		_prompt_column.custom_minimum_size.x = 0.0
		_prompt_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_options.custom_minimum_size.x = 0.0
	_options.custom_minimum_size.y = maxf(0.0, size.y - 16.0) if uses_application_modal_region(_request) else 0.0


static func uses_textbox_region(request: InteractionRequest, passive_text: bool = false) -> bool:
	return passive_text or request != null and not _is_player_map_request(request) and request.kind in [&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"character_selection", &"combat_action"]


static func uses_floating_choice_modal(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.YES_NO, InteractionRequest.ENCOUNTER_CHOICE, InteractionRequest.INDEXED_CHOICE]


static func uses_full_stage_region(request: InteractionRequest) -> bool:
	return uses_application_workspace(request)


static func uses_application_workspace(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.TREASURE_DISTRIBUTION, InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE]


static func uses_application_modal_region(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.LEVEL_UP:
		return false
	var body := request.body as InteractionRequest.LevelUpRequestBody
	return body != null and body.mode == &"spell-selection"


static func interaction_region(request: InteractionRequest, textbox_rect: Rect2, _unused_stage_rect: Rect2, combat_rect: Rect2 = Rect2()) -> Rect2:
	if request == null or request.kind != &"combat_action":
		return textbox_rect
	return combat_rect if combat_rect.has_area() else textbox_rect


func _add_hint(text: String) -> Label:
	_options.visible = true
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("d5b45d"))
	_options.add_child(label)
	return label


func _focus_first_control() -> void:
	var preferred := _component.preferred_initial_focus() if _component != null else null
	var first := preferred if preferred != null else _first_focusable(_options)
	if first == null and _floating_choice_layer != null:
		first = _first_focusable(_floating_choice_layer)
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
