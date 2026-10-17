## Owns the complete editor-authored Save, Preferences, Controls, and Diagnostics layout.
class_name SystemWorkspace
extends VBoxContainer

@export var save_slot_row_scene: PackedScene

func prepare(_compact: bool) -> void:
	visible = true


func tabs() -> TabContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs") as TabContainer


func campaign_context() -> Label:
	return get_node("SystemSummary/SystemHeader/SystemCampaignContext") as Label


func save_slot_rows() -> VBoxContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/SaveSlotScroll/SaveSlotRows") as VBoxContainer


func save_browser_empty() -> PanelContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty") as PanelContainer


func save_detail_record() -> VBoxContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Record") as VBoxContainer


func save_detail_empty() -> PanelContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty") as PanelContainer


func focus_load_confirmation() -> void:
	if not is_inside_tree():
		return
	var confirm := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/ConfirmActionRow/Confirm") as Button
	if confirm.is_visible_in_tree() and not confirm.disabled:
		confirm.grab_focus()


func clear_variable_save_rows() -> void:
	var parent := save_slot_rows()
	for child: Node in parent.get_children():
		if child.has_meta(&"scenario_slot"):
			continue
		parent.remove_child(child)
		child.queue_free()


func _apply_compact_rows(parent: Node, compact: bool) -> void:
	for child: Node in parent.get_children():
		if child is BoxContainer and (child.is_in_group(&"system_setting_rows") or child.is_in_group(&"system_control_help_rows")):
			(child as BoxContainer).vertical = compact
		_apply_compact_rows(child, compact)
