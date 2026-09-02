class_name InteractionPresenter
extends PanelContainer

const ClassicTreasureTakeEffectScript := preload("res://src/presentation/classic_treasure_take_effect.gd")

const PickLockInteractionScript := preload("res://src/presentation/interaction_components/pick_lock_interaction.gd")
const ThiefEncounterInteractionScript := preload("res://src/presentation/interaction_components/thief_encounter_interaction.gd")

const LifecycleInteractionScript := preload("res://src/presentation/interaction_components/lifecycle_interaction.gd")
const FastSpellDockScript := preload("res://src/presentation/interaction_components/fast_spell_dock.gd")
const ScrollingTextInteractionScript := preload("res://src/presentation/interaction_components/scrolling_text_interaction.gd")
const LayoutPolicy := preload("res://src/presentation/interaction_layout_policy.gd")

signal response_submitted(response: InteractionResponse)
signal combat_targeting_requested(request: CombatTargetingRequest)
signal combat_targeting_confirm_requested
signal combat_targeting_cancel_requested
signal combat_targeting_rotate_requested
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
var _owns_classic_acknowledgement_cursor: bool = false
var _pending_treasure_transfer: Dictionary = {}
var _component: InteractionComponent
var _stage_rect := Rect2(0.0, 28.0, 992.0, 502.0)
var _textbox_rect := Rect2(8.0, 530.0, 984.0, 182.0)
var _combat_rect := Rect2(0.0, 530.0, 1280.0, 190.0)
var _application_rect := Rect2(0.0, 32.0, 1280.0, 688.0)
var _side_workspace_rect := Rect2(928.0, 28.0, 352.0, 502.0)
var _passive_text: bool = false
var _playback_masked: bool = false
var _playback_status_label: Label
var _autojournal_enabled: bool = false
var _treasure_recipient_id: String = ""
var _treasure_slot_order: Array[String] = []
var _side_workspace_panel: PanelContainer
var _encounter_dock_panel: PanelContainer
var _application_workspace_panel: PanelContainer
var _modal_shield: ColorRect
var _nested_modal: Control
var _combat_spellbook_open: bool = false
var _fast_spell_dock: Control
var _classic_flash_queue: Array[Dictionary] = []
var _classic_flash_layer: Control
var _classic_flash_panel: PanelContainer
var _classic_flash_shield: ColorRect
var _classic_flash_label: Label


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_claim_modal_layer()


func _gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _submit_classic_acknowledgement():
		accept_event()


func handle_global_pointer_acknowledgement(event: InputEvent) -> bool:
	var mouse_event := event as InputEventMouseButton
	return mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and _uses_global_classic_acknowledgement() and _submit_classic_acknowledgement()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	if _dismiss_classic_flash():
		get_viewport().set_input_as_handled()
		return
	if _submit_classic_acknowledgement():
		get_viewport().set_input_as_handled()


func _submit_classic_acknowledgement() -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.ACKNOWLEDGE and _component is TextChoiceInteraction and (_component as TextChoiceInteraction).submit_acknowledgement()


func _exit_tree() -> void:
	_set_classic_acknowledgement_cursor(false)
	_close_side_workspace()
	_close_encounter_dock()
	_close_application_workspace()
	_close_modal_shield()
	_close_fast_spell_dock()
	_close_classic_flash()


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
		_treasure_slot_order.clear()
	else:
		_update_treasure_slot_order(request)
	_request = request
	_set_classic_acknowledgement_cursor(_uses_global_classic_acknowledgement())
	_passive_text = false
	_playback_masked = false
	_reset_interaction_scroll()
	_clear_options()
	visible = request != null
	if visible:
		_claim_modal_layer()
	var full_stage := LayoutPolicy.uses_full_stage_region(request)
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
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if LayoutPolicy.uses_classic_click_modal(request) else HORIZONTAL_ALIGNMENT_LEFT
	_prompt.visible = not _prompt.text.is_empty()
	if LayoutPolicy.uses_application_workspace(request):
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	if request.kind in [InteractionRequest.AGE_UPDATE, InteractionRequest.ALLY_SELECTION, InteractionRequest.LEVEL_UP, InteractionRequest.PICK_LOCK]:
		_set_heading("")
		_prompt.text = ""
		_prompt.visible = false
	if LayoutPolicy.is_player_map_request(request) or LayoutPolicy.is_scrolling_text_request(request):
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
	_component.combat_targeting_rotate_requested.connect(func() -> void: combat_targeting_rotate_requested.emit())
	_component.combatant_focus_requested.connect(func(combatant_id: String, play_sound: bool) -> void: combatant_focus_requested.emit(combatant_id, play_sound))
	_component.reveal_friends_requested.connect(func() -> void: reveal_friends_requested.emit())
	_component.presentation_sound_requested.connect(func(sound_id: int) -> void: presentation_sound_requested.emit(sound_id))
	_component.presentation_status_requested.connect(func(text: String, is_error: bool) -> void: presentation_status_requested.emit(text, is_error))
	_component.combat_spellbook_requested.connect(func(actor_id: String, options: Array[InteractionRequestValue.CastOption]) -> void: combat_spellbook_requested.emit(actor_id, options))
	_component.combat_spellbook_closed.connect(func() -> void: combat_spellbook_closed.emit())
	_component.side_workspace_requested.connect(_show_side_workspace)
	_component.side_workspace_closed.connect(_close_side_workspace)
	_component.encounter_dock_requested.connect(_show_encounter_dock)
	_component.encounter_dock_closed.connect(_close_encounter_dock)
	_component.application_workspace_requested.connect(_show_application_workspace)
	_component.application_workspace_closed.connect(_close_application_workspace)
	if _component is TreasureDistributionInteraction:
		var treasure := _component as TreasureDistributionInteraction
		treasure.recipient_selected.connect(func(character_id: String) -> void: _treasure_recipient_id = character_id)
	_options.add_child(_component)
	_options.visible = true
	_component.build(request)
	if request.kind == InteractionRequest.COMBAT:
		_mount_fast_spell_dock(request.body as InteractionRequest.CombatRequestBody, game_view, media)
	_apply_classic_region()
	call_deferred("_prepare_interaction_focus")


func present_combat_playback_mask(frame: CombatPlaybackFrame = null) -> void:
	_request = null
	_set_classic_acknowledgement_cursor(false)
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
	var stage_inset := maxf(0.0, stage_rect.position.x - _combat_rect.position.x)
	var application_top := maxf(0.0, stage_rect.position.y - stage_inset)
	_application_rect = Rect2(
		_combat_rect.position.x,
		application_top,
		_combat_rect.size.x,
		maxf(stage_rect.end.y, _combat_rect.end.y) - application_top
	)
	_side_workspace_rect = Rect2(outer_stage.end.x, outer_stage.position.y, maxf(0.0, _combat_rect.end.x - outer_stage.end.x), maxf(0.0, _application_rect.end.y - outer_stage.position.y))
	if _component is BattleInteraction:
		(_component as BattleInteraction).set_command_scale(LayoutPolicy.combat_command_scale(_combat_rect))
	_apply_classic_region()
	_apply_fast_spell_dock_layout()
	_apply_classic_flash_layout()


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


func queue_classic_flash_messages(messages: Array[Dictionary]) -> void:
	for message: Dictionary in messages:
		var text := String(message.get("text", "")).strip_edges()
		if not text.is_empty():
			_classic_flash_queue.append({"text": text, "soundId": int(message.get("soundId", 0))})
	_show_next_classic_flash()


func _show_next_classic_flash() -> void:
	if _classic_flash_panel != null or _classic_flash_queue.is_empty() or get_parent() == null:
		return
	_classic_flash_layer = Control.new()
	_classic_flash_layer.name = "ClassicFlashLayer"
	_classic_flash_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_classic_flash_layer.z_index = z_index + 20
	get_parent().add_child(_classic_flash_layer)
	_classic_flash_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_classic_flash_shield = ColorRect.new()
	_classic_flash_shield.name = "ClassicFlashShield"
	_classic_flash_shield.color = Color(0.01, 0.015, 0.02, 0.42)
	_classic_flash_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_classic_flash_layer.add_child(_classic_flash_shield)
	_classic_flash_shield.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_classic_flash_panel = PanelContainer.new()
	_classic_flash_panel.name = "ClassicFlashMessage"
	_classic_flash_panel.theme_type_variation = &"ClassicInset"
	_classic_flash_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_classic_flash_panel.z_index = 1
	_classic_flash_layer.add_child(_classic_flash_panel)
	_classic_flash_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_classic_flash_panel.add_child(content)
	var label := Label.new()
	label.name = "ClassicFlashText"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("f0d05b"))
	content.add_child(label)
	_classic_flash_label = label
	var acknowledge := Button.new()
	acknowledge.name = "ClassicFlashContinue"
	acknowledge.text = "Continue"
	acknowledge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	acknowledge.pressed.connect(_dismiss_classic_flash)
	content.add_child(acknowledge)
	_classic_flash_panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_dismiss_classic_flash()
	)
	_apply_classic_flash_layout()
	_present_next_classic_flash()


func _present_next_classic_flash() -> void:
	if _classic_flash_panel == null or _classic_flash_label == null or _classic_flash_queue.is_empty():
		return
	var message: Dictionary = _classic_flash_queue.pop_front()
	_classic_flash_label.text = String(message["text"])
	var sound_id := int(message.get("soundId", 0))
	if sound_id > 0:
		presentation_sound_requested.emit(sound_id)


func _dismiss_classic_flash() -> bool:
	if _classic_flash_panel == null:
		return false
	if _classic_flash_queue.is_empty():
		_close_classic_flash(false)
	else:
		_present_next_classic_flash()
	return true


func _close_classic_flash(clear_queue: bool = true) -> void:
	if _classic_flash_layer != null:
		var parent := _classic_flash_layer.get_parent()
		if parent != null:
			parent.remove_child(_classic_flash_layer)
		_classic_flash_layer.queue_free()
	_classic_flash_layer = null
	_classic_flash_panel = null
	_classic_flash_shield = null
	_classic_flash_label = null
	if clear_queue:
		_classic_flash_queue.clear()


func _apply_classic_flash_layout() -> void:
	if _classic_flash_layer == null or _classic_flash_panel == null or _classic_flash_shield == null:
		return
	_classic_flash_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_classic_flash_layer.position = Vector2.ZERO
	_classic_flash_layer.size = (get_parent() as Control).size if get_parent() is Control else _application_rect.end
	_classic_flash_shield.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_classic_flash_shield.position = _application_rect.position
	_classic_flash_shield.size = _application_rect.size
	var region := LayoutPolicy.classic_flash_modal_rect(_application_rect, _textbox_rect)
	_classic_flash_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_classic_flash_panel.custom_minimum_size = region.size
	_classic_flash_panel.position = region.position
	_classic_flash_panel.size = region.size


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


func set_fast_spell_dock_held(held: bool) -> bool:
	if _playback_masked or _request == null or _request.kind != InteractionRequest.COMBAT or _fast_spell_dock == null:
		return false
	return _fast_spell_dock.set_held(held)


func activate_fast_spell_from_dock(slot_index: int) -> bool:
	if _fast_spell_dock != null:
		_fast_spell_dock.set_held(false)
	return handle_fast_spell(slot_index, true)


func inspect_combatant(combatant_id: String) -> void:
	if _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction:
		(_component as BattleInteraction).inspect_combatant(combatant_id)


func open_combatant_inspection(combatant_id: String) -> bool:
	return _request != null and _request.kind == InteractionRequest.COMBAT and _component is BattleInteraction and (_component as BattleInteraction).open_combatant_inspection(combatant_id)


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
	if LayoutPolicy.is_player_map_request(request):
		var player_map := PlayerMapInteraction.new()
		player_map.configure(game_view, media)
		return player_map
	if LayoutPolicy.is_scrolling_text_request(request):
		var scrolling_text := ScrollingTextInteractionScript.new()
		scrolling_text.configure(media)
		return scrolling_text
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
			treasure.configure(media, game_view, _application_rect.size.x < 1000.0, _treasure_recipient_id, _treasure_slot_order)
			return treasure
		&"level_up":
			var level_up := LevelUpInteraction.new()
			level_up.configure(game_view, media)
			return level_up
		&"complex_encounter":
			var encounter := EncounterInteraction.new()
			encounter.configure(media, game_view, _application_rect.size.x < 1000.0)
			return encounter
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
			battle.configure(_combatant_icon_textures(game_view, media), LayoutPolicy.combat_command_scale(_combat_rect))
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


func _spell_animation_frames(game_view: GameView, media: ClassicMediaCatalog, bindings: Array[InteractionRequestValue.FastSpell]) -> Dictionary:
	var result: Dictionary = {}
	if game_view == null or media == null:
		return result
	var requested_spell_ids: Dictionary = {}
	for binding: InteractionRequestValue.FastSpell in bindings:
		if not binding.spell_id.is_empty():
			requested_spell_ids[binding.spell_id] = true
	for character: CharacterView in game_view.party_members:
		for spell: SpellView in character.spells:
			if not requested_spell_ids.has(spell.id) or result.has(spell.id):
				continue
			var frames: Array[Texture2D] = []
			for resource_id: int in spell.animation_resource_ids:
				var texture := media.image_texture(media.asset_by_resource(spell.animation_resource_type, resource_id))
				if texture == null:
					frames.clear()
					break
				frames.append(texture)
			if frames.size() == spell.animation_resource_ids.size() and not frames.is_empty():
				result[spell.id] = frames
	return result


func _mount_fast_spell_dock(body: InteractionRequest.CombatRequestBody, game_view: GameView, media: ClassicMediaCatalog) -> void:
	_close_fast_spell_dock()
	if body == null:
		return
	_fast_spell_dock = FastSpellDockScript.new()
	_fast_spell_dock.configure(body.fast_spells, _spell_animation_frames(game_view, media, body.fast_spells))
	_fast_spell_dock.slot_activated.connect(func(slot_index: int) -> void: activate_fast_spell_from_dock(slot_index))
	get_parent().add_child(_fast_spell_dock)
	_apply_fast_spell_dock_layout()


func _close_fast_spell_dock() -> void:
	if _fast_spell_dock == null:
		return
	var dock_parent: Node = _fast_spell_dock.get_parent()
	if dock_parent != null:
		dock_parent.remove_child(_fast_spell_dock)
	_fast_spell_dock.queue_free()
	_fast_spell_dock = null


func _apply_fast_spell_dock_layout() -> void:
	if _fast_spell_dock != null:
		_fast_spell_dock.set_stage_rect(_stage_rect)


func _submit_body(body: InteractionResponse.Body) -> void:
	if _request == null:
		return
	_close_side_workspace()
	_close_encounter_dock()
	_close_application_workspace()
	_close_modal_shield()
	var response := InteractionPresenter.response_for(_request, body)
	var preserve_treasure_workspace := _component is TreasureDistributionInteraction and body is InteractionResponse.TreasureBody and (body as InteractionResponse.TreasureBody).action in [&"assign", &"done"]
	_request = null
	_set_classic_acknowledgement_cursor(false)
	_close_fast_spell_dock()
	if not preserve_treasure_workspace:
		visible = false
	response_submitted.emit(response)


func _uses_global_classic_acknowledgement() -> bool:
	if _request == null or _request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := _request.body as InteractionRequest.AcknowledgeBody
	return body != null and body.presentation in [&"classic-textbox", &"classic-click-modal"]


func _set_classic_acknowledgement_cursor(enabled: bool) -> void:
	if enabled:
		if _owns_classic_acknowledgement_cursor:
			return
		var asset_id := &"interaction.cursor.continue"
		var texture := ClassicUiAssetCatalog.texture(asset_id)
		if texture != null:
			Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, ClassicUiAssetCatalog.cursor_hotspot(asset_id))
			_owns_classic_acknowledgement_cursor = true
	elif _owns_classic_acknowledgement_cursor:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		_owns_classic_acknowledgement_cursor = false


func capture_treasure_transfer() -> bool:
	if not _component is TreasureDistributionInteraction:
		return false
	_pending_treasure_transfer = (_component as TreasureDistributionInteraction).take_committed_transfer_path()
	return not _pending_treasure_transfer.is_empty()


func begin_treasure_transfer(reduced_motion: bool) -> bool:
	var path := _pending_treasure_transfer
	_pending_treasure_transfer = {}
	if path.is_empty():
		return false
	if reduced_motion:
		presentation_sound_requested.emit(6002)
		return true
	var effect_layer := CanvasLayer.new()
	effect_layer.name = "TreasureTakeEffectLayer"
	effect_layer.layer = 200
	add_child(effect_layer)
	var pulse := ClassicTreasureTakeEffectScript.new() as Control
	pulse.name = "TreasureTakeEffect"
	effect_layer.add_child(pulse)
	var source := path["from"] as Vector2
	var tween := pulse.call("begin", path.get("texture") as Texture2D, String(path.get("instanceId", ""))) as Tween
	pulse.position = source - pulse.size * 0.5
	tween.finished.connect(func() -> void:
		effect_layer.queue_free()
		presentation_sound_requested.emit(6002)
	)
	return true


func _update_treasure_slot_order(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.TreasureRequestBody
	if body == null or body.mode != &"ordinary":
		return
	var continues_current_layout := body.items.is_empty() or body.items.any(func(item: InteractionRequestValue.RewardItem) -> bool: return _treasure_slot_order.has(item.instance_id))
	if not _treasure_slot_order.is_empty() and not continues_current_layout:
		_treasure_slot_order.clear()
	for item: InteractionRequestValue.RewardItem in body.items:
		if not _treasure_slot_order.has(item.instance_id):
			_treasure_slot_order.append(item.instance_id)


static func response_for(request: InteractionRequest, body: InteractionResponse.Body) -> InteractionResponse:
	assert(request != null, "An interaction response requires its originating request")
	return InteractionResponse.new(request.request_id, request.kind, body)


func _clear_options() -> void:
	_combat_spellbook_open = false
	combat_spellbook_closed.emit()
	_close_side_workspace()
	_close_encounter_dock()
	_close_application_workspace()
	_close_nested_modal()
	_close_fast_spell_dock()
	_component = null
	_playback_status_label = null
	_options.visible = false
	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


func _apply_classic_region() -> void:
	if not is_inside_tree():
		return
	# Lifecycle dialogs are content-sized. Release any height retained from a
	# previously mounted application modal before assigning their compact frame.
	if _request != null and _request.kind == InteractionRequest.SESSION_LIFECYCLE:
		_options.custom_minimum_size.y = 0.0
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if _playback_masked:
		theme_type_variation = &"ClassicOpenRight"
		position = _combat_rect.position
		size = _combat_rect.size
	elif LayoutPolicy.uses_classic_click_modal(_request):
		theme_type_variation = &"ClassicInset"
		_content.custom_minimum_size.x = 0.0
		var region := LayoutPolicy.classic_click_modal_rect(_application_rect, _textbox_rect)
		position = region.position
		size = region.size
	elif LayoutPolicy.uses_floating_choice_modal(_request):
		theme_type_variation = &"ClassicInset"
		var region := LayoutPolicy.floating_choice_rect(_stage_rect, _textbox_rect, _content.get_combined_minimum_size() + Vector2(16.0, 16.0))
		position = region.position
		size = region.size
	elif LayoutPolicy.uses_textbox_region(_request, _passive_text):
		theme_type_variation = LayoutPolicy.textbox_theme_variation(_request)
		var region := LayoutPolicy.interaction_region(_request, _textbox_rect, _combat_rect)
		if _combat_spellbook_open and _request != null and _request.kind == InteractionRequest.COMBAT:
			region.size.x = minf(region.size.x, maxf(0.0, _side_workspace_rect.position.x - region.position.x))
		position = region.position
		size = region.size
	elif LayoutPolicy.uses_full_stage_region(_request):
		theme_type_variation = &"ClassicInset"
		var region := _application_rect if LayoutPolicy.uses_application_workspace(_request) or _request.kind == InteractionRequest.SESSION_LIFECYCLE else _stage_rect
		position = region.position
		size = region.size
	else:
		theme_type_variation = &"ClassicInset"
		var modal_region := _application_rect if LayoutPolicy.uses_application_modal_region(_request) else _stage_rect
		var desired := LayoutPolicy.preferred_modal_size(_request, modal_region.size)
		if _request != null and _request.kind == InteractionRequest.THIEF_ENCOUNTER:
			desired.y = minf(maxf(280.0, _content.get_combined_minimum_size().y + 16.0), modal_region.size.y - 20.0)
		position = modal_region.position + (modal_region.size - desired) * 0.5
		size = desired
	var encounter_surface := _request != null and _request.kind in [InteractionRequest.WORD_AND_ACTION, InteractionRequest.THIEF_ENCOUNTER]
	_update_modal_shield(not _playback_masked and _request != null and (encounter_surface or not LayoutPolicy.uses_textbox_region(_request)) and not LayoutPolicy.uses_full_stage_region(_request), not encounter_surface)
	_apply_content_layout()
	_apply_side_workspace_layout()
	_apply_encounter_dock_layout()
	_apply_application_workspace_layout()
	_apply_nested_modal_layout()


func _update_modal_shield(needed: bool, dim_background: bool = true) -> void:
	if not needed:
		_close_modal_shield()
		return
	if _modal_shield == null:
		_modal_shield = ColorRect.new()
		_modal_shield.name = "LockedModalShield"
		_modal_shield.mouse_filter = Control.MOUSE_FILTER_STOP
		_modal_shield.z_index = z_index - 1
		get_parent().add_child(_modal_shield)
	_modal_shield.color = Color(0.01, 0.015, 0.02, 0.62) if dim_background else Color.TRANSPARENT
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
	if shield_parent != null and shield_parent.is_queued_for_deletion():
		_modal_shield = null
		return
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
	var scroll := ScrollContainer.new()
	scroll.name = "InteractionSideWorkspaceScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_workspace_panel.add_child(scroll)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(workspace)
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


func _show_encounter_dock(workspace: Control) -> void:
	_close_encounter_dock()
	if workspace == null:
		return
	_encounter_dock_panel = PanelContainer.new()
	_encounter_dock_panel.name = "EncounterCommandDock"
	_encounter_dock_panel.theme_type_variation = &"ClassicInset"
	_encounter_dock_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_encounter_dock_panel.z_index = z_index + 1
	get_parent().add_child(_encounter_dock_panel)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.reparent(_encounter_dock_panel)
	_apply_encounter_dock_layout()


func _close_encounter_dock() -> void:
	if _encounter_dock_panel == null:
		return
	var dock_parent := _encounter_dock_panel.get_parent()
	if dock_parent != null and dock_parent.is_queued_for_deletion():
		_encounter_dock_panel = null
		return
	if dock_parent != null:
		dock_parent.remove_child(_encounter_dock_panel)
	_encounter_dock_panel.queue_free()
	_encounter_dock_panel = null


func _apply_encounter_dock_layout() -> void:
	if _encounter_dock_panel == null:
		return
	var required_height := _encounter_dock_panel.get_combined_minimum_size().y
	var dock_height := clampf(required_height, 58.0, minf(84.0, _stage_rect.size.y * 0.22))
	_encounter_dock_panel.position = Vector2(_textbox_rect.position.x, maxf(_stage_rect.position.y, _textbox_rect.position.y - dock_height - 6.0))
	_encounter_dock_panel.size = Vector2(_textbox_rect.size.x, dock_height)


func _show_application_workspace(workspace: Control) -> void:
	_close_application_workspace()
	if workspace == null:
		return
	_application_workspace_panel = PanelContainer.new()
	_application_workspace_panel.name = "InteractionApplicationWorkspace"
	_application_workspace_panel.theme_type_variation = &"ClassicInset"
	_application_workspace_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_application_workspace_panel.z_index = z_index + 2
	get_parent().add_child(_application_workspace_panel)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_application_workspace_panel.add_child(workspace)
	_apply_application_workspace_layout()


func _close_application_workspace() -> void:
	if _application_workspace_panel == null:
		return
	var workspace_parent := _application_workspace_panel.get_parent()
	if workspace_parent != null and workspace_parent.is_queued_for_deletion():
		_application_workspace_panel = null
		return
	_application_workspace_panel.queue_free()
	_application_workspace_panel = null


func _apply_application_workspace_layout() -> void:
	if _application_workspace_panel == null:
		return
	_application_workspace_panel.position = _application_rect.position
	_application_workspace_panel.size = _application_rect.size


func _apply_content_layout() -> void:
	var split_textbox := LayoutPolicy.uses_textbox_region(_request, _passive_text) and _request != null and _request.kind == InteractionRequest.CHARACTER_SELECTION
	var encounter_textbox := _request != null and _request.kind == InteractionRequest.WORD_AND_ACTION
	_content.custom_minimum_size.x = 0.0 if LayoutPolicy.uses_classic_click_modal(_request) else 280.0
	_scroll.vertical_scroll_mode = LayoutPolicy.interaction_vertical_scroll_mode(_request)
	_content.vertical = not split_textbox
	_prompt.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if encounter_textbox else Control.SIZE_EXPAND_FILL
	_options.size_flags_stretch_ratio = 2.0 if encounter_textbox else 1.0
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
	if LayoutPolicy.uses_application_workspace(_request):
		# Full-stage workspaces are assigned from the stable shell region. Using
		# this control's content-driven size here would create a minimum-size
		# feedback loop whenever a route expands to fill the available height.
		_options.custom_minimum_size.y = maxf(0.0, _application_rect.size.y - 22.0)
	elif _request != null and _request.kind == InteractionRequest.SESSION_LIFECYCLE:
		_options.custom_minimum_size.y = 0.0
	else:
		_options.custom_minimum_size.y = maxf(0.0, size.y - 16.0) if LayoutPolicy.uses_application_modal_region(_request) or LayoutPolicy.is_scrolling_text_request(_request) else 0.0


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
	if request.kind == InteractionRequest.ACKNOWLEDGE:
		return ""
	if request.kind == InteractionRequest.YES_NO:
		var authored_context := classic_text_context.strip_edges()
		if not authored_context.is_empty():
			return authored_context
		return "Choose Yes or No to continue."
	return _title_for_kind(request.kind)


static func _heading_for_kind(kind: StringName) -> String:
	match kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"complex_encounter":
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
