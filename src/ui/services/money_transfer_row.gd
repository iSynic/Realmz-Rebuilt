## Binds one denomination exchange row without owning money rules.
class_name MoneyTransferRow
extends PanelContainer


func bind(transfer: MoneyTransferView, pooled: int, carried: int, media: ClassicMediaCatalog) -> void:
	name = "MoneyTransfer_%s" % String(transfer.denomination)
	var icon := $Content/Icon as ClassicContentIcon
	icon.configure(
		"cicn",
		ServicesScreenController.wealth_resource_id(transfer.denomination),
		media,
		32.0,
		String(transfer.denomination).capitalize(),
		"Classic wealth image unavailable"
	)
	($Content/Denomination as Label).text = String(transfer.denomination).capitalize()
	($Content/PoolCount as Label).text = str(pooled)
	($Content/CharacterCount as Label).text = str(carried)
	($Content/ToPool as Button).text = "← %d" % transfer.amount
	($Content/ToCharacter as Button).text = "%d →" % transfer.amount


func to_pool_button() -> Button:
	return $Content/ToPool as Button


func to_character_button() -> Button:
	return $Content/ToCharacter as Button
