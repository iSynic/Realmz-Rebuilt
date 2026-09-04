## Exposes the editor-authored party-setup inspection overlay.

extends PanelContainer


func sheet_host() -> VBoxContainer:
	return %CharacterInspectionSheetHost as VBoxContainer
