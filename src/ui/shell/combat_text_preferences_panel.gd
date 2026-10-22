## Binds the authored combat-text controls to the shared preferences draft.
class_name CombatTextPreferencesPanel
extends Container

signal setting_changed(setting_id: StringName, value: Variant)

const COMPACT_BREAKPOINT := 680.0

var _binding := false
var _compact_columns := false


func _ready() -> void:
	resized.connect(_layout_columns)
	(get_node("Columns/ControlsColumn/CombatTextSpeedGroup/CombatTextSpeedSlider") as HSlider).value_changed.connect(_on_speed_changed)
	(get_node("Columns/ControlsColumn/CombatTextBackgroundGroup/CombatTextBackgroundSlider") as HSlider).value_changed.connect(_on_background_changed)
	(get_node("Columns/ControlsColumn/CombatTextMotionRow/CombatTextMotion") as OptionButton).item_selected.connect(_on_motion_selected)
	(get_node("Columns/ControlsColumn/CombatTextSizeGroup/CombatTextSizeSlider") as HSlider).value_changed.connect(_on_size_changed)
	(get_node("Columns/ControlsColumn/CombatTextTravelGroup/CombatTextTravelSlider") as HSlider).value_changed.connect(_on_travel_changed)
	(get_node("Columns/ControlsColumn/CombatTextAnchorRow/CombatTextAnchor") as OptionButton).item_selected.connect(_on_anchor_selected)
	(get_node("Columns/ControlsColumn/CombatTextOffsetGroup/CombatTextOffsetSlider") as HSlider).value_changed.connect(_on_offset_changed)
	(get_node("Columns/PreviewColumn/CombatTextReset") as Button).pressed.connect(_reset_combat_text)
	_layout_columns()


func bind_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_binding = true
	(get_node("Columns/ControlsColumn/CombatTextSpeedGroup/CombatTextSpeedSlider") as HSlider).value = settings.combat_text_speed_percent
	(get_node("Columns/ControlsColumn/CombatTextBackgroundGroup/CombatTextBackgroundSlider") as HSlider).value = settings.combat_text_background_opacity_percent
	(get_node("Columns/ControlsColumn/CombatTextMotionRow/CombatTextMotion") as OptionButton).select(0 if settings.combat_text_motion == PresentationSettings.COMBAT_TEXT_FLOATING else 1)
	(get_node("Columns/ControlsColumn/CombatTextSizeGroup/CombatTextSizeSlider") as HSlider).value = settings.combat_text_size_percent
	(get_node("Columns/ControlsColumn/CombatTextTravelGroup/CombatTextTravelSlider") as HSlider).value = settings.combat_text_travel_logical_pixels
	(get_node("Columns/ControlsColumn/CombatTextAnchorRow/CombatTextAnchor") as OptionButton).select(0 if settings.combat_text_anchor == PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON else 1)
	(get_node("Columns/ControlsColumn/CombatTextOffsetGroup/CombatTextOffsetSlider") as HSlider).value = settings.combat_text_custom_offset_y_logical_pixels
	_binding = false
	_update_value_labels(settings)
	_update_dependent_controls(settings.combat_text_motion, settings.combat_text_anchor)
	_update_preview(settings)


func _layout_columns() -> void:
	var columns := get_node_or_null("Columns") as BoxContainer
	if columns == null:
		return
	var compact := size.x < COMPACT_BREAKPOINT
	if compact == _compact_columns:
		return
	_compact_columns = compact
	columns.vertical = compact
	(get_node("Columns/PreviewColumn") as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_SHRINK_BEGIN
	columns.queue_sort()


func _on_speed_changed(value: float) -> void:
	if _binding: return
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_speed_percent", int(value))


func _on_background_changed(value: float) -> void:
	if _binding: return
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_background_opacity_percent", int(value))


func _on_motion_selected(index: int) -> void:
	if _binding: return
	var motion := PresentationSettings.COMBAT_TEXT_STATIONARY if index == 1 else PresentationSettings.COMBAT_TEXT_FLOATING
	_update_dependent_controls(motion, _selected_anchor())
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_motion", motion)


func _on_size_changed(value: float) -> void:
	if _binding: return
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_size_percent", int(value))


func _on_travel_changed(value: float) -> void:
	if _binding: return
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_travel_logical_pixels", int(value))


func _on_anchor_selected(index: int) -> void:
	if _binding: return
	var anchor := PresentationSettings.COMBAT_TEXT_ANCHOR_CUSTOM if index == 1 else PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON
	_update_dependent_controls(_selected_motion(), anchor)
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_anchor", anchor)


func _on_offset_changed(value: float) -> void:
	if _binding: return
	_update_preview_from_controls()
	setting_changed.emit(&"combat_text_custom_offset_y_logical_pixels", int(value))


func _reset_combat_text() -> void:
	var defaults := PresentationSettings.new()
	bind_settings(defaults)
	setting_changed.emit(&"combat_text_speed_percent", defaults.combat_text_speed_percent)
	setting_changed.emit(&"combat_text_background_opacity_percent", defaults.combat_text_background_opacity_percent)
	setting_changed.emit(&"combat_text_motion", defaults.combat_text_motion)
	setting_changed.emit(&"combat_text_size_percent", defaults.combat_text_size_percent)
	setting_changed.emit(&"combat_text_travel_logical_pixels", defaults.combat_text_travel_logical_pixels)
	setting_changed.emit(&"combat_text_anchor", defaults.combat_text_anchor)
	setting_changed.emit(&"combat_text_custom_offset_y_logical_pixels", defaults.combat_text_custom_offset_y_logical_pixels)


func _update_value_labels(settings: PresentationSettings) -> void:
	(get_node("Columns/ControlsColumn/CombatTextSpeedGroup/CombatTextSpeedRow/CombatTextSpeedValue") as Label).text = "%d%%" % settings.combat_text_speed_percent
	(get_node("Columns/ControlsColumn/CombatTextBackgroundGroup/CombatTextBackgroundRow/CombatTextBackgroundValue") as Label).text = "%d%%" % settings.combat_text_background_opacity_percent
	(get_node("Columns/ControlsColumn/CombatTextSizeGroup/CombatTextSizeRow/CombatTextSizeValue") as Label).text = "%d%%" % settings.combat_text_size_percent
	(get_node("Columns/ControlsColumn/CombatTextTravelGroup/CombatTextTravelRow/CombatTextTravelValue") as Label).text = "%d logical map px" % settings.combat_text_travel_logical_pixels
	(get_node("Columns/ControlsColumn/CombatTextOffsetGroup/CombatTextOffsetRow/CombatTextOffsetValue") as Label).text = "%d logical map px" % settings.combat_text_custom_offset_y_logical_pixels


func _update_dependent_controls(motion: String, anchor: String) -> void:
	(get_node("Columns/ControlsColumn/CombatTextTravelGroup/CombatTextTravelSlider") as HSlider).editable = motion != PresentationSettings.COMBAT_TEXT_STATIONARY
	(get_node("Columns/ControlsColumn/CombatTextOffsetGroup/CombatTextOffsetSlider") as HSlider).editable = anchor != PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON


func _update_preview(settings: PresentationSettings) -> void:
	(get_node("Columns/PreviewColumn/CombatTextPreview") as CombatTextPreferencesPreview).configure(
		settings.combat_text_motion,
		settings.combat_text_size_percent,
		settings.combat_text_travel_logical_pixels,
		settings.combat_text_anchor,
		settings.combat_text_custom_offset_y_logical_pixels,
		settings.combat_text_speed_percent,
		settings.combat_text_background_opacity_percent
	)


func _update_preview_from_controls() -> void:
	var settings := PresentationSettings.new()
	settings.combat_text_speed_percent = int((get_node("Columns/ControlsColumn/CombatTextSpeedGroup/CombatTextSpeedSlider") as HSlider).value)
	settings.combat_text_background_opacity_percent = int((get_node("Columns/ControlsColumn/CombatTextBackgroundGroup/CombatTextBackgroundSlider") as HSlider).value)
	settings.combat_text_motion = _selected_motion()
	settings.combat_text_size_percent = int((get_node("Columns/ControlsColumn/CombatTextSizeGroup/CombatTextSizeSlider") as HSlider).value)
	settings.combat_text_travel_logical_pixels = int((get_node("Columns/ControlsColumn/CombatTextTravelGroup/CombatTextTravelSlider") as HSlider).value)
	settings.combat_text_anchor = _selected_anchor()
	settings.combat_text_custom_offset_y_logical_pixels = int((get_node("Columns/ControlsColumn/CombatTextOffsetGroup/CombatTextOffsetSlider") as HSlider).value)
	_update_value_labels(settings)
	_update_preview(settings)


func _selected_motion() -> String:
	return PresentationSettings.COMBAT_TEXT_STATIONARY if (get_node("Columns/ControlsColumn/CombatTextMotionRow/CombatTextMotion") as OptionButton).selected == 1 else PresentationSettings.COMBAT_TEXT_FLOATING


func _selected_anchor() -> String:
	return PresentationSettings.COMBAT_TEXT_ANCHOR_CUSTOM if (get_node("Columns/ControlsColumn/CombatTextAnchorRow/CombatTextAnchor") as OptionButton).selected == 1 else PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON
