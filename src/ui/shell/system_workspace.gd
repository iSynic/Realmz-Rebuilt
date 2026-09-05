## Owns the complete editor-authored Save, Preferences, Controls, and Diagnostics layout.
class_name SystemWorkspace
extends VBoxContainer

@export var save_slot_row_scene: PackedScene


func prepare(compact: bool) -> void:
	visible = true
	(get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns") as BoxContainer).vertical = compact
	(get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/SaveWorkspaceActions") as BoxContainer).vertical = compact
	(get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/NewSaveSlotRow") as BoxContainer).vertical = compact
	_apply_compact_rows(self, compact)
	_clear(save_slot_rows())
	get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty").visible = false
	get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty").visible = false
	save_detail_record().visible = false


func tabs() -> TabContainer:
	return get_node("SystemWorkspaceTabs") as TabContainer


func campaign_context() -> Label:
	return get_node("SystemSummary/SystemHeader/SystemCampaignContext") as Label


func save_slot_rows() -> VBoxContainer:
	return get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/SaveSlotScroll/SaveSlotRows") as VBoxContainer


func save_browser_empty() -> PanelContainer:
	return get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty") as PanelContainer


func save_detail_record() -> VBoxContainer:
	return get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Record") as VBoxContainer


func save_detail_empty() -> PanelContainer:
	return get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty") as PanelContainer


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _apply_compact_rows(parent: Node, compact: bool) -> void:
	for child: Node in parent.get_children():
		if child is BoxContainer and (child.is_in_group(&"system_setting_rows") or child.is_in_group(&"system_control_help_rows")):
			(child as BoxContainer).vertical = compact
		_apply_compact_rows(child, compact)
