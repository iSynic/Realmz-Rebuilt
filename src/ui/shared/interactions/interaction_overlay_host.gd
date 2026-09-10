## Mounts and positions the scene-authored overlays surrounding an interaction.

class_name InteractionOverlayHost
extends RefCounted

var _presenter: Control
var _modal_shield_scene: PackedScene
var _treasure_completion_scene: PackedScene
var _side_workspace_scene: PackedScene
var _encounter_dock_scene: PackedScene
var _application_workspace_scene: PackedScene
var _application_rect := Rect2()
var _stage_rect := Rect2()
var _textbox_rect := Rect2()
var _side_workspace_rect := Rect2()
var _modal_shield: ColorRect
var _nested_modal: Control
var _side_workspace_panel: PanelContainer
var _encounter_dock_panel: PanelContainer
var _application_workspace_panel: PanelContainer


func configure(
	presenter: Control,
	modal_shield_scene: PackedScene,
	treasure_completion_scene: PackedScene,
	side_workspace_scene: PackedScene,
	encounter_dock_scene: PackedScene,
	application_workspace_scene: PackedScene
) -> void:
	_presenter = presenter
	_modal_shield_scene = modal_shield_scene
	_treasure_completion_scene = treasure_completion_scene
	_side_workspace_scene = side_workspace_scene
	_encounter_dock_scene = encounter_dock_scene
	_application_workspace_scene = application_workspace_scene


func set_regions(application_rect: Rect2, stage_rect: Rect2, textbox_rect: Rect2, side_workspace_rect: Rect2) -> void:
	_application_rect = application_rect
	_stage_rect = stage_rect
	_textbox_rect = textbox_rect
	_side_workspace_rect = side_workspace_rect
	apply_layout()


func close_all() -> void:
	close_side_workspace()
	close_encounter_dock()
	close_application_workspace()
	close_modal_shield()
	close_nested_modal()


func release() -> void:
	for overlay in [_modal_shield, _nested_modal, _side_workspace_panel, _encounter_dock_panel, _application_workspace_panel]:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_modal_shield = null
	_nested_modal = null
	_side_workspace_panel = null
	_encounter_dock_panel = null
	_application_workspace_panel = null
	_presenter = null


func update_modal_shield(needed: bool, dim_background: bool = true) -> void:
	if not needed:
		close_modal_shield()
		return
	if _modal_shield == null:
		_modal_shield = _modal_shield_scene.instantiate() as ColorRect
		_modal_shield.z_index = _presenter.z_index - 1
		_presenter.get_parent().add_child(_modal_shield)
	_modal_shield.color = Color(0.01, 0.015, 0.02, 0.62) if dim_background else Color.TRANSPARENT
	_modal_shield.position = _application_rect.position
	_modal_shield.size = _application_rect.size
	var parent := _presenter.get_parent()
	parent.move_child(_modal_shield, modal_shield_target_index(_modal_shield.get_index(), _presenter.get_index()))


func close_modal_shield() -> void:
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


func show_treasure_confirmation(component: Control) -> void:
	close_nested_modal()
	_nested_modal = _treasure_completion_scene.instantiate() as Control
	_nested_modal.z_index = _presenter.z_index + 1
	_presenter.add_child(_nested_modal)
	var frame := _nested_modal.get_node("TreasureCompletionCenter/TreasureCompletionModal") as PanelContainer
	frame.add_child(component)
	_apply_nested_modal_layout()


func close_nested_modal() -> void:
	if _nested_modal == null:
		return
	_presenter.remove_child(_nested_modal)
	_nested_modal.queue_free()
	_nested_modal = null


func show_side_workspace(workspace: Control) -> void:
	close_side_workspace()
	if workspace == null:
		return
	_side_workspace_panel = _side_workspace_scene.instantiate() as PanelContainer
	_side_workspace_panel.z_index = _presenter.z_index + 1
	_side_workspace_panel.minimum_size_changed.connect(_apply_side_workspace_layout)
	_presenter.get_parent().add_child(_side_workspace_panel)
	var scroll := _side_workspace_panel.get_node("InteractionSideWorkspaceScroll") as ScrollContainer
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(workspace)
	_apply_side_workspace_layout()


func close_side_workspace() -> void:
	if _side_workspace_panel == null:
		return
	var workspace_parent := _side_workspace_panel.get_parent()
	if workspace_parent != null:
		workspace_parent.remove_child(_side_workspace_panel)
	_side_workspace_panel.queue_free()
	_side_workspace_panel = null


func show_encounter_dock(workspace: Control) -> void:
	close_encounter_dock()
	if workspace == null:
		return
	_encounter_dock_panel = _encounter_dock_scene.instantiate() as PanelContainer
	_encounter_dock_panel.z_index = _presenter.z_index + 1
	_presenter.get_parent().add_child(_encounter_dock_panel)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.reparent(_encounter_dock_panel)
	_apply_encounter_dock_layout()


func close_encounter_dock() -> void:
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


func show_application_workspace(workspace: Control) -> void:
	close_application_workspace()
	if workspace == null:
		return
	_application_workspace_panel = _application_workspace_scene.instantiate() as PanelContainer
	_application_workspace_panel.z_index = _presenter.z_index + 2
	_presenter.get_parent().add_child(_application_workspace_panel)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_application_workspace_panel.add_child(workspace)
	_apply_application_workspace_layout()


func close_application_workspace() -> void:
	if _application_workspace_panel == null:
		return
	var workspace_parent := _application_workspace_panel.get_parent()
	if workspace_parent != null and workspace_parent.is_queued_for_deletion():
		_application_workspace_panel = null
		return
	_application_workspace_panel.queue_free()
	_application_workspace_panel = null


func apply_layout() -> void:
	_apply_side_workspace_layout()
	_apply_encounter_dock_layout()
	_apply_application_workspace_layout()
	_apply_nested_modal_layout()


static func modal_shield_target_index(shield_index: int, presenter_index: int) -> int:
	return maxi(0, presenter_index - 1 if shield_index < presenter_index else presenter_index)


func _apply_nested_modal_layout() -> void:
	if _nested_modal != null:
		_nested_modal.position = Vector2.ZERO
		_nested_modal.size = _presenter.size


func _apply_side_workspace_layout() -> void:
	if _side_workspace_panel != null:
		_side_workspace_panel.size = _side_workspace_rect.size
		_side_workspace_panel.position = Vector2(_side_workspace_rect.end.x - _side_workspace_panel.size.x, _side_workspace_rect.position.y)


func _apply_encounter_dock_layout() -> void:
	if _encounter_dock_panel == null:
		return
	var required_height := _encounter_dock_panel.get_combined_minimum_size().y
	var dock_height := clampf(required_height, 58.0, minf(84.0, _stage_rect.size.y * 0.22))
	_encounter_dock_panel.position = Vector2(_textbox_rect.position.x, maxf(_stage_rect.position.y, _textbox_rect.position.y - dock_height - 6.0))
	_encounter_dock_panel.size = Vector2(_textbox_rect.size.x, dock_height)


func _apply_application_workspace_layout() -> void:
	if _application_workspace_panel != null:
		_application_workspace_panel.position = _application_rect.position
		_application_workspace_panel.size = _application_rect.size
