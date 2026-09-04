## Maps each stable player-intent kind to its one accepted feature payload.

class_name PlayerIntentRegistry
extends RefCounted


static func payload_matches(kind: PlayerIntent.Kind, payload: PlayerIntentPayload) -> bool:
	match kind:
		PlayerIntent.Kind.SEARCH, PlayerIntent.Kind.TOGGLE_SEARCH, PlayerIntent.Kind.USE_TORCH, PlayerIntent.Kind.CONTEXTUAL_ENCOUNTER, PlayerIntent.Kind.CAMP, PlayerIntent.Kind.REST, PlayerIntent.Kind.HEAL, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT, PlayerIntent.Kind.FINALIZE_CHARACTER:
			return payload is EmptyIntentPayload
		PlayerIntent.Kind.MOVE:
			return payload is ExplorationIntentPayloads.Move
		PlayerIntent.Kind.DUNGEON_TURN:
			return payload is ExplorationIntentPayloads.DungeonTurn and (payload as ExplorationIntentPayloads.DungeonTurn).delta in [-1, 1]
		PlayerIntent.Kind.USE_ITEM:
			return payload is InventoryIntentPayloads.Use
		PlayerIntent.Kind.USE_ITEM_ON_TARGET:
			return payload is InventoryIntentPayloads.Target
		PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.SET_FAST_SPELL:
			return payload is SpellIntentPayload
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			return payload is CombatIntentPayloads.Action
		PlayerIntent.Kind.CREATE_PARTY:
			return payload is PartyIntentPayloads.Party
		PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS:
			return payload is PartyIntentPayloads.SetupOptions
		PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
			return payload is PartyIntentPayloads.VaultImport
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT:
			return payload is PartyIntentPayloads.Draft
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PlayerIntent.Kind.REORDER_PARTY:
			return payload is PartyIntentPayloads.StringList
		PlayerIntent.Kind.REMOVE_PARTY_MEMBER:
			return payload is PartyIntentPayloads.Character
		PlayerIntent.Kind.CHANGE_CHARACTER_APPEARANCE:
			return payload is PartyIntentPayloads.Appearance
		PlayerIntent.Kind.EQUIP_ITEM, PlayerIntent.Kind.UNEQUIP_ITEM, PlayerIntent.Kind.DROP_ITEM, PlayerIntent.Kind.SPLIT_ITEM, PlayerIntent.Kind.JOIN_ITEM, PlayerIntent.Kind.TRADE_ITEM:
			return payload is InventoryIntentPayloads.Action
		PlayerIntent.Kind.MONEY_ACTION:
			return payload is EconomyIntentPayloads.Money
		PlayerIntent.Kind.SERVICE_ACTION:
			return payload is EconomyIntentPayloads.Service
		PlayerIntent.Kind.COMBAT_MOVE:
			return payload is CombatIntentPayloads.Move
		PlayerIntent.Kind.SET_COMBAT_AUTO:
			return payload is CombatIntentPayloads.Auto
		PlayerIntent.Kind.SET_LOCATION_NOTE:
			return payload is ExplorationIntentPayloads.LocationNote
	return false
