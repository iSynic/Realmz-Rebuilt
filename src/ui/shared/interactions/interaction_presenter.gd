## Presents interaction presenter through the Godot interface.

class_name InteractionPresenter
extends PanelContainer


const LayoutPolicy := preload("res://src/ui/shared/interactions/interaction_layout_policy.gd")
const ComponentFactory := preload("res://src/ui/shared/interactions/interaction_component_factory.gd")

@export var classic_flash_overlay_scene: PackedScene
@export var modal_shield_scene: PackedScene
@export var treasure_completion_modal_scene: PackedScene
@export var side_workspace_scene: PackedScene
@export var encounter_dock_scene: PackedScene
@export var application_workspace_scene: PackedScene
@export var hint_scene: PackedScene
@export var fast_spell_dock_scene: PackedScene

signal response_submitted(response: InteractionResponse)
signal presentation_sound_requested(sound_id: int)
signal presentation_status_requested(text: String, is_error: bool)

var combat: CombatInteractionController:
	get: return _combat

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
var _overlays: InteractionOverlayHost
var _combat: CombatInteractionController
var _flash: InteractionFlashController


func _ready() -> void:
	_combat = CombatInteractionController.new()
	_combat.configure(get_parent(), fast_spell_dock_scene)
	_combat.response_body_submitted.connect(_submit_body)
	_combat.layout_changed.connect(_apply_classic_region)
	_overlays = InteractionOverlayHost.new()
	_overlays.configure(self, modal_shield_scene, treasure_completion_modal_scene, side_workspace_scene, encounter_dock_scene, application_workspace_scene)
	_overlays.set_regions(_application_rect, _stage_rect, _textbox_rect, _side_workspace_rect)
	_flash = InteractionFlashController.new()
	_flash.configure(self, classic_flash_overlay_scene)
	_flash.set_regions(_application_rect, _textbox_rect)
	_flash.sound_requested.connect(func(sound_id: int) -> void: presentation_sound_requested.emit(sound_id))


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
	if _flash.dismiss():
		get_viewport().set_input_as_handled()
		return
	if _submit_classic_acknowledgement():
		get_viewport().set_input_as_handled()


func _submit_classic_acknowledgement() -> bool:
	return not _playback_masked and _request != null and _request.kind == InteractionRequest.ACKNOWLEDGE and _component is TextChoiceInteraction and (_component as TextChoiceInteraction).submit_acknowledgement()


func _exit_tree() -> void:
	_set_classic_acknowledgement_cursor(false)
	if _overlays != null:
		_overlays.close_all()
	if _combat != null:
		_combat.clear()
	if _flash != null:
		_flash.close()


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
	if not _begin_request(request):
		return
	_present_request_text(request, classic_text_context)
	_mount_request_component(request, game_view, media)


func _begin_request(request: InteractionRequest) -> bool:
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
		return false
	return true


func _present_request_text(request: InteractionRequest, classic_text_context: String) -> void:
	_set_heading(ComponentFactory.heading_for_kind(request.kind))
	if request.kind == InteractionRequest.SESSION_LIFECYCLE:
		_set_heading("")
	if request.kind == InteractionRequest.CHARACTER_SELECTION and (request.body as CharacterSelectionRequestBody).spell_context != null:
		_set_heading("Spell Target")
	_prompt.text = ComponentFactory.prompt_for(request, classic_text_context)
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


func _mount_request_component(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> void:
	_component = _create_component(request, game_view, media)
	if _component == null:
		_set_heading("Unsupported Interaction")
		_prompt.text = "Unsupported Realmz interaction: %s" % String(request.kind)
		_add_hint("This package cannot continue because its interaction contract is unavailable.")
		return
	_component.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_component.add_theme_constant_override("separation", 8)
	_component.response_body_submitted.connect(_submit_body)
	_component.presentation_sound_requested.connect(func(sound_id: int) -> void: presentation_sound_requested.emit(sound_id))
	_component.presentation_status_requested.connect(func(text: String, is_error: bool) -> void: presentation_status_requested.emit(text, is_error))
	_component.side_workspace_requested.connect(_overlays.show_side_workspace)
	_component.side_workspace_closed.connect(_overlays.close_side_workspace)
	_component.encounter_dock_requested.connect(_overlays.show_encounter_dock)
	_component.encounter_dock_closed.connect(_overlays.close_encounter_dock)
	_component.application_workspace_requested.connect(_overlays.show_application_workspace)
	_component.application_workspace_closed.connect(_overlays.close_application_workspace)
	if _component is TreasureDistributionInteraction:
		var treasure := _component as TreasureDistributionInteraction
		treasure.recipient_selected.connect(func(character_id: String) -> void: _treasure_recipient_id = character_id)
	_options.add_child(_component)
	_options.visible = true
	_component.build(request)
	if _component is BattleInteraction:
		_combat.bind(_component as BattleInteraction, request.body as CombatRequestBody, game_view, media)
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
	_playback_status_label = _add_hint(CombatPlaybackController.status_text(frame))
	_playback_status_label.name = "CombatPlaybackStatus"
	visible = true
	_claim_modal_layer()
	_apply_classic_region()


func update_combat_playback_frame(frame: CombatPlaybackFrame) -> void:
	if _playback_masked and _playback_status_label != null:
		_playback_status_label.text = CombatPlaybackController.status_text(frame)


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
	_overlays.set_regions(_application_rect, _stage_rect, _textbox_rect, _side_workspace_rect)
	_flash.set_regions(_application_rect, _textbox_rect)
	var compact := _application_rect.size.x < 1000.0
	if _component != null:
		_component.set_layout_profile(compact)
	_combat.set_command_layout(LayoutPolicy.combat_command_scale(_combat_rect), compact)
	_apply_classic_region()
	_combat.set_stage_rect(_stage_rect)


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
	_flash.queue_messages(messages)


func has_blocking_request() -> bool:
	return _request != null or _playback_masked or _flash.is_open()


func handle_back_request() -> bool:
	return not _playback_masked and _request != null and _component != null and _component.handle_back()


func submit_character_selection(character_ids: Array[String]) -> bool:
	if _playback_masked or _request == null or _request.kind != InteractionRequest.CHARACTER_SELECTION:
		return false
	var body := _request.body as CharacterSelectionRequestBody
	if body == null or character_ids.size() != body.count:
		return false
	_submit_body(InteractionResponse.SelectionBody.new(character_ids))
	return true


func set_text_scale(value: float) -> void:
	_heading.add_theme_font_size_override("font_size", int(round(18.0 * value)))
	_prompt.add_theme_font_size_override("font_size", int(round(18.0 * value)))


func set_autojournal_enabled(enabled: bool) -> void:
	_autojournal_enabled = enabled


func _create_component(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> InteractionComponent:
	return ComponentFactory.create(request, game_view, media, _application_rect.size.x < 1000.0, _autojournal_enabled, _treasure_recipient_id, _treasure_slot_order, _combat_rect)


func _submit_body(body: InteractionResponse.Body) -> void:
	if _request == null:
		return
	_overlays.close_side_workspace()
	_overlays.close_encounter_dock()
	_overlays.close_application_workspace()
	_overlays.close_modal_shield()
	var response := InteractionResponse.new(_request.request_id, _request.kind, body)
	var preserve_treasure_workspace := _component is TreasureDistributionInteraction and body is InteractionResponse.TreasureBody and (body as InteractionResponse.TreasureBody).action in [&"assign", &"done"]
	_request = null
	_set_classic_acknowledgement_cursor(false)
	_combat.clear()
	if not preserve_treasure_workspace:
		visible = false
	response_submitted.emit(response)


func _uses_global_classic_acknowledgement() -> bool:
	if _request == null or _request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := _request.body as AcknowledgeRequestBody
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
	var pulse := ClassicTreasureTakeEffect.new() as Control
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
	var body := request.body as TreasureRequestBody
	if body == null or body.mode != &"ordinary":
		return
	var continues_current_layout := body.items.is_empty() or body.items.any(func(item: InteractionRequestValue.RewardItem) -> bool: return _treasure_slot_order.has(item.instance_id))
	if not _treasure_slot_order.is_empty() and not continues_current_layout:
		_treasure_slot_order.clear()
	for item: InteractionRequestValue.RewardItem in body.items:
		if not _treasure_slot_order.has(item.instance_id):
			_treasure_slot_order.append(item.instance_id)


func _clear_options() -> void:
	_combat.clear()
	_overlays.close_side_workspace()
	_overlays.close_encounter_dock()
	_overlays.close_application_workspace()
	_overlays.close_nested_modal()
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
		if _combat.is_spellbook_open() and _request != null and _request.kind == InteractionRequest.COMBAT:
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
	_overlays.update_modal_shield(not _playback_masked and _request != null and (encounter_surface or not LayoutPolicy.uses_textbox_region(_request)) and not LayoutPolicy.uses_full_stage_region(_request), not encounter_surface)
	_apply_content_layout()
	_overlays.apply_layout()


func _can_present_nested_treasure_confirmation(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.TREASURE_DISTRIBUTION or not _component is TreasureDistributionInteraction:
		return false
	var body := request.body as TreasureRequestBody
	return body != null and body.mode == &"completion-confirmation"


func _present_nested_treasure_confirmation(request: InteractionRequest, game_view: GameView, media: ClassicMediaCatalog) -> void:
	var component := _create_component(request, game_view, media)
	_component = component
	component.response_body_submitted.connect(_submit_body)
	_overlays.show_treasure_confirmation(component)
	component.build(request)


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
	var label := hint_scene.instantiate() as Label
	label.text = text
	_options.add_child(label)
	return label


func _prepare_interaction_focus() -> void:
	_reset_interaction_scroll()
	var preferred := _component.preferred_initial_focus() if _component != null else null
	var first := preferred if preferred != null else _first_focusable(_options)
	if first != null:
		first.grab_focus()
	_reset_interaction_scroll()


func _reset_interaction_scroll() -> void:
	_scroll.scroll_horizontal = 0
	_scroll.scroll_vertical = 0


func _claim_modal_layer() -> void:
	var parent := get_parent()
	if parent != null and get_index() != parent.get_child_count() - 1:
		parent.move_child(self, parent.get_child_count() - 1)


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
