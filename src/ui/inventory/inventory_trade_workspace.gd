## Owns the complete, editor-visible two-pack Trade composition.
class_name InventoryTradeWorkspace
extends PanelContainer


func ledgers() -> BoxContainer:
	return get_node("Content/InventoryTradeLedgers") as BoxContainer


func source_ledger() -> InventoryTradeLedger:
	return get_node("Content/InventoryTradeLedgers/SourceLedger") as InventoryTradeLedger


func target_ledger() -> InventoryTradeLedger:
	return get_node("Content/InventoryTradeLedgers/TargetLedger") as InventoryTradeLedger


func divider() -> InventoryTradeDivider:
	return get_node("Content/InventoryTradeLedgers/InventoryTradeDivider") as InventoryTradeDivider


func status_label() -> Label:
	return get_node("Content/TradeStatus") as Label


func item_record() -> InventorySelectedItemRecord:
	return get_node("Content/TradeItemInspector/InventorySelectedItemRecord") as InventorySelectedItemRecord
