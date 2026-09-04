## Exposes the authored Race and Caste selectors and their detached detail fields.

extends VBoxContainer


func race_options() -> ClassicDefinitionToggleList:
	return %RaceList as ClassicDefinitionToggleList


func caste_options() -> ClassicDefinitionToggleList:
	return %CasteList as ClassicDefinitionToggleList
