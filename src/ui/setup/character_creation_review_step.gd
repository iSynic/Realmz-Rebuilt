## Exposes the editor-authored review status and shared character-sheet host.

extends VBoxContainer


func status_label() -> Label:
	return %ReviewStatus as Label


func sheet_host() -> VBoxContainer:
	return %ReviewSheetHost as VBoxContainer
