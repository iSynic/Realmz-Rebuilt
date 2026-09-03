## Binds one denomination exchange row without owning money rules.
class_name MoneyTransferRow
extends PanelContainer


func bind(transfer: MoneyTransferView, character_name: String, media: ClassicMediaCatalog) -> void:
	name = "MoneyTransfer_%s" % String(transfer.denomination)
	var icon := $Content/Icon as ClassicContentIcon
	icon.name = "Money%sIcon" % String(transfer.denomination).capitalize()
	icon.configure(
		"cicn",
		ServicesScreenController.wealth_resource_id(transfer.denomination),
		media,
		32.0,
		String(transfer.denomination).capitalize(),
		"Classic wealth image unavailable"
	)
	($Content/Denomination as Label).text = "%s  ×%d" % [String(transfer.denomination).capitalize(), transfer.amount]
	($Content/ToCharacter as Button).text = "To %s" % character_name


func to_pool_button() -> Button:
	return $Content/ToPool as Button


func to_character_button() -> Button:
	return $Content/ToCharacter as Button
