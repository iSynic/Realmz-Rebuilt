## Binds one editable wealth chip to a detached Classic denomination value.
class_name WealthChip
extends PanelContainer


func bind(denomination: StringName, value: int, media: ClassicMediaCatalog) -> void:
	var icon := $Content/Icon as ClassicContentIcon
	($Content/Text/Heading as Label).text = String(denomination).capitalize()
	($Content/Text/Amount as Label).text = str(value)
	icon.configure(
		"cicn",
		ServicesScreenController.wealth_resource_id(denomination),
		media,
		32.0,
		String(denomination).capitalize(),
		"Classic wealth image unavailable"
	)
