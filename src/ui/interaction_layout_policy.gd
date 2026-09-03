class_name InteractionLayoutPolicy
extends RefCounted

const COMBAT_COMMAND_BASE_WIDTH := 1280.0
const COMBAT_COMMAND_BASE_HEIGHT := 100.0
const COMBAT_FIXED_HEIGHT := 90.0


static func textbox_theme_variation(request: InteractionRequest = null) -> StringName:
	return &"ClassicOpenRight" if request != null and request.kind == InteractionRequest.COMBAT else &"ClassicTextboxOverlay"


static func preferred_modal_size(request: InteractionRequest, available_size: Vector2) -> Vector2:
	var preferred := Vector2(700.0, 520.0)
	var minimum := Vector2(300.0, 260.0)
	if request != null:
		match request.kind:
			InteractionRequest.SESSION_LIFECYCLE:
				var lifecycle := request.body as InteractionRequest.LifecycleRequestBody
				preferred = Vector2(560.0, 220.0) if lifecycle != null and lifecycle.operation != &"quit-application" else Vector2(460.0, 135.0)
				minimum = Vector2(420.0, 190.0) if lifecycle != null and lifecycle.operation != &"quit-application" else Vector2(340.0, 135.0)
			InteractionRequest.WORD_AND_ACTION:
				preferred = Vector2(720.0, 260.0)
				minimum = Vector2(520.0, 180.0)
			InteractionRequest.THIEF_ENCOUNTER:
				preferred = Vector2(760.0, minf(410.0, available_size.y - 20.0))
				minimum = Vector2(560.0, 310.0)
			InteractionRequest.LEVEL_UP:
				var body := request.body as InteractionRequest.LevelUpRequestBody
				preferred = Vector2(1080.0, minf(760.0, available_size.y - 20.0)) if body != null and body.mode == &"spell-selection" else Vector2(760.0, 430.0)
			InteractionRequest.ALLY_SELECTION:
				preferred = Vector2(820.0, 500.0)
	var desired := Vector2(minf(preferred.x, available_size.x - 20.0), minf(preferred.y, available_size.y - 20.0))
	return Vector2(maxf(minimum.x, desired.x), maxf(minimum.y, desired.y))


static func floating_choice_rect(stage_rect: Rect2, textbox_rect: Rect2, minimum: Vector2) -> Rect2:
	var available_width := minf(maxf(300.0, stage_rect.size.x - 20.0), maxf(300.0, textbox_rect.size.x))
	var modal_size := Vector2(
		minf(maxf(520.0, minimum.x), available_width),
		minf(maxf(116.0, minimum.y), maxf(116.0, stage_rect.size.y - 20.0))
	)
	var lower_right := Vector2(minf(stage_rect.end.x - 10.0, textbox_rect.end.x), minf(stage_rect.end.y - 10.0, textbox_rect.position.y - 8.0))
	return Rect2(
		Vector2(maxf(stage_rect.position.x + 10.0, lower_right.x - modal_size.x), maxf(stage_rect.position.y + 10.0, lower_right.y - modal_size.y)),
		modal_size
	)


static func uses_textbox_region(request: InteractionRequest, passive_text: bool = false) -> bool:
	return passive_text or request != null and not uses_classic_click_modal(request) and not is_player_map_request(request) and not is_scrolling_text_request(request) and request.kind in [&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"character_selection", &"complex_encounter", &"combat_action"]


static func uses_classic_click_modal(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := request.body as InteractionRequest.AcknowledgeBody
	return body != null and body.presentation == &"classic-click-modal"


static func classic_click_modal_rect(application_rect: Rect2, textbox_rect: Rect2) -> Rect2:
	var desired := Vector2(minf(174.0, application_rect.size.x - 40.0), minf(60.0, application_rect.size.y - 40.0))
	var preferred_y := textbox_rect.position.y - desired.y - 12.0
	return Rect2(
		Vector2(
			application_rect.position.x + (application_rect.size.x - desired.x) * 0.5,
			clampf(preferred_y, application_rect.position.y + 20.0, application_rect.end.y - desired.y - 20.0)
		),
		desired
	)


static func classic_flash_modal_rect(application_rect: Rect2, textbox_rect: Rect2) -> Rect2:
	var desired := Vector2(minf(520.0, application_rect.size.x - 40.0), minf(118.0, application_rect.size.y - 40.0))
	var preferred_y := textbox_rect.position.y - desired.y - 12.0
	return Rect2(
		Vector2(
			application_rect.position.x + (application_rect.size.x - desired.x) * 0.5,
			clampf(preferred_y, application_rect.position.y + 20.0, application_rect.end.y - desired.y - 20.0)
		),
		desired
	)


static func interaction_vertical_scroll_mode(request: InteractionRequest) -> int:
	return ScrollContainer.SCROLL_MODE_DISABLED if request != null and request.kind in [InteractionRequest.SHOP, InteractionRequest.SESSION_LIFECYCLE] else ScrollContainer.SCROLL_MODE_AUTO


static func combat_command_scale(combat_rect: Rect2) -> float:
	if not combat_rect.has_area():
		return 1.0
	var width_scale := combat_rect.size.x / COMBAT_COMMAND_BASE_WIDTH
	var available_command_height := maxf(0.0, combat_rect.size.y - COMBAT_FIXED_HEIGHT)
	var height_scale := available_command_height / COMBAT_COMMAND_BASE_HEIGHT
	return clampf(minf(width_scale, height_scale), 1.0, 2.0)


static func uses_floating_choice_modal(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.YES_NO, InteractionRequest.ENCOUNTER_CHOICE, InteractionRequest.INDEXED_CHOICE]


static func uses_full_stage_region(request: InteractionRequest) -> bool:
	return uses_application_workspace(request) or is_scrolling_text_request(request)


static func uses_application_workspace(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.TREASURE_DISTRIBUTION, InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK, InteractionRequest.POOLED_WEALTH_DEPARTURE]


static func uses_application_modal_region(request: InteractionRequest) -> bool:
	return request != null and request.kind in [InteractionRequest.PICK_LOCK, InteractionRequest.SESSION_LIFECYCLE, InteractionRequest.ALLY_SELECTION, InteractionRequest.LEVEL_UP]


static func interaction_region(request: InteractionRequest, textbox_rect: Rect2, combat_rect: Rect2 = Rect2()) -> Rect2:
	if request == null or request.kind != &"combat_action":
		return textbox_rect
	return combat_rect if combat_rect.has_area() else textbox_rect


static func is_player_map_request(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := request.body as InteractionRequest.AcknowledgeBody
	return body != null and body.presentation == &"player-map"


static func is_scrolling_text_request(request: InteractionRequest) -> bool:
	if request == null or request.kind != InteractionRequest.ACKNOWLEDGE:
		return false
	var body := request.body as InteractionRequest.AcknowledgeBody
	return body != null and body.presentation == &"classic-scrolling-text"
