## Binds the shell's authored narrative, status, and world-fact controls.
class_name GameShellStatusController
extends RefCounted

const ERROR := Color("ef7770")
const TEXT := Color("d8d9d2")
const SAVE_STATUS_TEXTURE_PATH := "res://src/ui/shared/assets/ui/status/save-status.png"
const JOURNAL_STATUS_TEXTURE_PATH := "res://src/ui/shared/assets/ui/status/journal-status.png"

var _host: Control
var _status_label: Label
var _narrative: RichTextLabel
var _narrative_well: PanelContainer
var _package_status: Label
var _coordinates_label: Label
var _fatigue_label: Label
var _fatigue_bar: ProgressBar
var _light_label: Label
var _clock_label: Label
var _gold_label: Label
var _activity_indicator: PanelContainer
var _activity_icon: TextureRect
var _setup_controller: CampaignPartySetupController
var _field_time_playback := ClassicFieldTimePlayback.new()
var _save_status_texture: Texture2D = load(SAVE_STATUS_TEXTURE_PATH) as Texture2D
var _journal_status_texture: Texture2D = load(JOURNAL_STATUS_TEXTURE_PATH) as Texture2D
var _activity_tween: Tween
var _latest_classic_text := ""


func initialize(
		host: Control,
		status_label: Label,
		narrative: RichTextLabel,
		narrative_well: PanelContainer,
		package_status: Label,
		coordinates_label: Label,
		fatigue_label: Label,
		fatigue_bar: ProgressBar,
		light_label: Label,
		clock_label: Label,
		gold_label: Label,
		activity_indicator: PanelContainer,
		activity_icon: TextureRect,
		setup_controller: CampaignPartySetupController
) -> void:
	_host = host
	_status_label = status_label
	_narrative = narrative
	_narrative_well = narrative_well
	_package_status = package_status
	_coordinates_label = coordinates_label
	_fatigue_label = fatigue_label
	_fatigue_bar = fatigue_bar
	_light_label = light_label
	_clock_label = clock_label
	_gold_label = gold_label
	_activity_indicator = activity_indicator
	_activity_icon = activity_icon
	_setup_controller = setup_controller


func set_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	_status_label.modulate = ERROR if is_error else TEXT
	_setup_controller.present_party_setup_status(text, is_error)


func show_activity_indicator(kind: StringName) -> void:
	match kind:
		&"save":
			_activity_icon.texture = _save_status_texture
			_activity_indicator.tooltip_text = "Adventure saved"
		&"journal":
			_activity_icon.texture = _journal_status_texture
			_activity_indicator.tooltip_text = "Added to Journal"
		_:
			return
	_activity_icon.custom_minimum_size = _activity_icon.texture.get_size()
	if _activity_tween != null and _activity_tween.is_valid():
		_activity_tween.kill()
	_activity_indicator.modulate = Color.WHITE
	_activity_indicator.visible = true
	_activity_tween = _host.create_tween()
	_activity_tween.tween_interval(1.15)
	_activity_tween.tween_property(_activity_indicator, "modulate:a", 0.0, 0.35)
	_activity_tween.tween_callback(func() -> void: _activity_indicator.visible = false)


func is_field_time_playback_active() -> bool:
	return _field_time_playback.is_active()


func present_step(step: SessionStep, current_view: GameView, picture_stage: Control) -> void:
	if step == null:
		return
	if step.state == SessionStep.State.FAILED:
		set_status("Action failed • %s" % step.error_message, true)
		append_narrative("Action failed: %s" % step.error_message)
		return
	picture_stage.visible = false
	_field_time_playback.present(_host, _clock_label, step.events)
	for event: DomainEvent in step.events:
		present_event(event, current_view)


func present_event(event: DomainEvent, current_view: GameView) -> void:
	match event.kind:
		&"message_shown":
			var text := String(event.payload.get("text", "Message"))
			_latest_classic_text = text
			append_narrative(text)
			set_status("Continue when ready" if bool(event.payload.get("classicClick", false)) else text)
		&"party_created":
			set_status("Party created • the adventure begins")
			append_narrative("The party enters the realm.")
		&"party_moved": set_status("%s • %d,%d" % [current_view.party_map_id if current_view != null else "Map", int(event.payload.get("x", 0)), int(event.payload.get("y", 0))])
		&"movement_blocked": set_status("That way is blocked")
		&"search_completed": append_narrative("The party searches the area.")
		&"camp_mode_changed": append_narrative("The party makes camp." if bool(event.payload.get("camping", false)) else "The party breaks camp.")
		&"character_age_changed": _present_age_change(event)
		&"door_opened": append_narrative("A door opens.")
		&"secret_discovered": append_narrative("A secret is revealed.")
		&"battle_started": append_narrative("Battle begins.")
		&"battle_completed": append_narrative("Battle completed • %s" % event.payload.get("outcome", "resolved"))


func _present_age_change(event: DomainEvent) -> void:
	var direction := int(event.payload.get("transition", 0))
	var age_group := int(event.payload.get("ageGroup", 0))
	var age_name := CharacterView.age_group_label(age_group)
	var character_name := String(event.payload.get("characterName", "A party member"))
	var text := "%s has grown into the %s age group." % [character_name, age_name] if direction > 0 else "%s has returned to the %s age group." % [character_name, age_name]
	set_status(text)
	append_narrative(text)


func append_narrative(text: String) -> void:
	if _narrative.text.is_empty() or _narrative.text == "Choose a validated Realmz campaign to begin.":
		_narrative.text = text
	else:
		_narrative.append_text("\n\n%s" % text)
	_narrative.scroll_to_line(_narrative.get_line_count())


func present_inactive() -> void:
	_latest_classic_text = ""
	_package_status.text = "No campaign"
	_clock_label.text = "Day —"
	_gold_label.text = "Gold —"
	_coordinates_label.text = "Map —"
	_fatigue_label.text = "Fatigue —"
	_fatigue_bar.value = 4.0
	_fatigue_bar.tooltip_text = "No active party fatigue."
	_light_label.text = "Light —"


func present_world_facts(game_view: GameView, include_gold: bool = true) -> void:
	_clock_label.text = "Day %d • %02d:%02d" % [game_view.realmz_day, game_view.realmz_hour, game_view.realmz_minute]
	if include_gold:
		_gold_label.text = "Gold %d" % game_view.pooled_gold
	_coordinates_label.text = location_fact_text(game_view)
	_fatigue_label.text = "Fatigue %d" % game_view.party_fatigue
	_fatigue_bar.value = game_view.party_fatigue
	_fatigue_bar.tooltip_text = "Fatigue %d / 135" % game_view.party_fatigue
	_light_label.text = "Light %d" % game_view.party_summary.light_remaining if game_view.party_summary != null else "Light —"


func set_campaign_title(title: String) -> void:
	_package_status.text = title


func reset_classic_text() -> void:
	_latest_classic_text = ""


func latest_classic_text() -> String:
	return _latest_classic_text


func narrative_region(shell: Control) -> Rect2:
	if _narrative_well == null or not _narrative_well.is_inside_tree():
		return Rect2()
	var local_origin := shell.get_global_transform().affine_inverse() * _narrative_well.global_position
	return Rect2(local_origin, _narrative_well.size)


static func location_fact_text(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Map —"
	var coordinates := "?,?" if game_view.map_view != null and game_view.map_view.coordinates_hidden else "%d,%d" % [game_view.party_coordinate.x, game_view.party_coordinate.y]
	var compass := ""
	if game_view.map_view != null and game_view.map_view.level_type == &"dungeon" and game_view.map_view.compass_enabled:
		compass = " • Compass %s" % ["N", "E", "S", "W"][clampi(game_view.map_view.dungeon_heading, 1, 4) - 1]
	return "%s • %s%s" % [game_view.party_map_id, coordinates, compass]
