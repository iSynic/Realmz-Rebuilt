## Owns the complete, editor-visible two-pack Trade composition.
class_name InventoryTradeWorkspace
extends PanelContainer

var _source_ledger: InventoryTradeLedger
var _target_ledger: InventoryTradeLedger


func ledgers() -> BoxContainer:
	return get_node("Content/InventoryTradeLedgers") as BoxContainer


func source_ledger() -> InventoryTradeLedger:
	if _source_ledger == null:
		_source_ledger = get_node("Content/InventoryTradeLedgers/SourceLedger") as InventoryTradeLedger
	return _source_ledger


func target_ledger() -> InventoryTradeLedger:
	if _target_ledger == null:
		_target_ledger = get_node("Content/InventoryTradeLedgers/TargetLedger") as InventoryTradeLedger
	return _target_ledger


func divider() -> InventoryTradeDivider:
	return get_node("Content/InventoryTradeLedgers/InventoryTradeDivider") as InventoryTradeDivider


func status_label() -> Label:
	return get_node("Content/TradeStatus") as Label


func item_record() -> InventorySelectedItemRecord:
	return get_node("Content/TradeItemInspector/RecordScroll/InventorySelectedItemRecord") as InventorySelectedItemRecord
