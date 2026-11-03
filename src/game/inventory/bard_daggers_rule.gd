## Decides the optional Bard Daggers Adventure Rule (FD-INVENTORY-007).

class_name BardDaggersRule
extends RefCounted

const STOCK_BARD_CASTE_ID := "classic.caste.13"
const DAGGER_CATEGORY: int = 3


## Departs from Castle only for the application-defined Bard, never a scenario's own class table.
static func admits(caste: CasteDefinition, content: RealmzContent) -> bool:
	return caste != null and caste.id == STOCK_BARD_CASTE_ID and content != null and not content.transfer_catalog.is_scenario_specific(&"castes", caste.id)


## The extra item category the adventure's rules open to this class, or -1 under Classic rules.
static func category(rules: AdventureRules, caste: CasteDefinition, content: RealmzContent) -> int:
	return DAGGER_CATEGORY if rules != null and rules.bard_daggers and admits(caste, content) else -1
