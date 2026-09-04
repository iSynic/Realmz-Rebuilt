@tool
## Binds representative detached game views through major production screen controllers.

extends RefCounted

const SUPPORTED_SURFACES: Array[String] = [
	"character-sheet",
	"inventory",
	"spells",
	"services",
	"roster-spellbook",
]


static func supports(surface_id: String) -> bool:
	return surface_id in SUPPORTED_SURFACES


static func bind(surface: Node, surface_id: String, profile: String) -> bool:
	if surface == null or not supports(surface_id):
		return false
	var view := _game_view(profile)
	var compact := profile == "Compact"
	match surface_id:
		"character-sheet": _bind_character_screen(surface as CharacterScreen, view, compact)
		"inventory": _bind_inventory_screen(surface as InventoryScreen, view, compact)
		"spells": _bind_spells_screen(surface as SpellsScreen, view, compact)
		"services": _bind_services_screen(surface as ServicesScreen, view, compact)
		"roster-spellbook": _bind_roster(surface as ClassicPartyRoster, view, profile)
		_: return false
	surface.set_meta("realmz_builder_profile", profile)
	return true


static func _bind_character_screen(screen: CharacterScreen, view: GameView, compact: bool) -> void:
	var controller := CharacterScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.present(screen, view, {}, PresentationSettings.new())
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_inventory_screen(screen: InventoryScreen, view: GameView, compact: bool) -> void:
	var controller := InventoryScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.present(screen, view, null, 1.0)
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_spells_screen(screen: SpellsScreen, view: GameView, compact: bool) -> void:
	var controller := SpellsScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.present(screen, view, null, 1.0, screen.find_child("SpellsBackHost", true, false))
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_services_screen(screen: ServicesScreen, view: GameView, compact: bool) -> void:
	var controller := ServicesScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.present(screen, view)
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_roster(roster: ClassicPartyRoster, view: GameView, profile: String) -> void:
	roster.present(view, view.party_members[0].id if not view.party_members.is_empty() else "")
	if profile not in ["Empty", "Error"] and not view.party_members.is_empty():
		roster.present_combat_spellbook(view.party_members[0].id, _cast_options(view.party_members[0]))


static func _game_view(profile: String) -> GameView:
	var view := GameView.new(1, profile != "Error", null)
	view.party_summary = PartySummaryView.new()
	view.set_action_availability(&"reorder_party", profile != "Unavailable", "Party order is locked during this preview state.")
	view.set_action_availability(&"change_character_appearance", profile != "Unavailable", "Appearance changes are unavailable.")
	view.set_action_availability(&"money_action", profile != "Unavailable", "Party wealth is unavailable.")
	view.set_action_availability(&"service_action", profile != "Unavailable", "No location service is available.")
	if profile in ["Empty", "Error"]:
		return view
	var count := 6 if profile == "Long Content" else 2
	for index: int in count:
		var character := _character(index, profile == "Unavailable", profile == "Long Content")
		view.party_members.append(character)
		view.party_summary.character_ids.append(character.id)
	view.money_workspace = _money_workspace(view.party_members, profile == "Unavailable")
	view.party_summary.pooled_gold = view.money_workspace.pooled_gold
	view.pooled_gold = view.money_workspace.pooled_gold
	return view


static func _character(index: int, unavailable: bool, long_content: bool) -> CharacterView:
	var names: Array[String] = ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"]
	var state := CharacterState.new("builder.character.%d" % index, names[index], 24 + index, 42 + index * 2)
	state.level = 4 + index
	state.experience = 1200 + index * 325
	state.spell_points = 18 + index * 2
	state.maximum_spell_points = 30 + index * 3
	state.spellcaster_type = 1
	state.armor = 8 + index
	state.magic_resistance = 10 + index
	state.carried_load = 420 + index * 35
	state.maximum_load = 1800
	state.money.gold = 80 + index * 20
	var result := CharacterView.new(state)
	var record_count := 14 if long_content else 4
	for item_index: int in record_count:
		result.items.append(_item(index, item_index, unavailable))
	for spell_index: int in record_count:
		result.spells.append(_spell(spell_index, unavailable))
	return result


static func _item(character_index: int, index: int, unavailable: bool) -> ItemView:
	var names: Array[String] = ["Longsword", "Shield", "Chain Armor", "Iron Rations", "Torch", "Wand"]
	var definition := ItemDefinition.new("classic.item.%d" % (800 + index), 800 + index, names[index % names.size()], "Unknown item", "A portable item resolved from the active application and scenario catalogs.")
	definition.cost = 100 + index * 25
	definition.weight = 10 + index
	definition.hands = 1 if index % 3 == 0 else 0
	definition.vs_small = 8 if index % 3 == 0 else 0
	var item := ItemView.new(ItemInstance.new("builder.item.%d.%d" % [character_index, index], definition.id, 4, index < 2, index % 4 != 3), definition)
	var reason := "This action is unavailable in the selected preview state."
	item.actions.equip = ActionAvailabilityView.new(&"equip_item", not unavailable, reason if unavailable else "")
	item.actions.drop = ActionAvailabilityView.new(&"drop_item", not unavailable, reason if unavailable else "")
	item.actions.trade = ActionAvailabilityView.new(&"trade_item", not unavailable, reason if unavailable else "")
	return item


static func _spell(index: int, unavailable: bool) -> SpellView:
	var names: Array[String] = ["Bless", "Magic Darts", "Flame Bolt", "Heal", "Shield", "Web"]
	var definition := SpellDefinition.new("classic.spell.%d" % (1101 + index), 1101 + index, names[index % names.size()], "A complete spell record bound through the production spellbook.")
	definition.cost = 2 + index % 4
	definition.in_camp = true
	definition.range_min = 1
	definition.range_max = 5
	definition.damage_min = 1
	definition.damage_max = 6
	var spell := SpellView.new(definition)
	spell.field_cast = ActionAvailabilityView.new(&"cast_spell", not unavailable, "Spellcasting is unavailable." if unavailable else "")
	spell.power_levels.assign([1, 2, 3])
	spell.structural_power_levels.assign([1, 2, 3])
	return spell


static func _money_workspace(characters: Array[CharacterView], unavailable: bool) -> MoneyWorkspaceView:
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = 460
	workspace.pooled_gems = 3
	workspace.pooled_jewelry = 1
	workspace.banked_gold = 2400
	workspace.pool = ActionAvailabilityView.new(&"money_action", not unavailable, "No wealth may be pooled now." if unavailable else "")
	workspace.share = ActionAvailabilityView.new(&"money_action", not unavailable, "No wealth may be shared now." if unavailable else "")
	for character: CharacterView in characters:
		var state := CharacterState.new(character.id, character.name, character.current_health, character.maximum_health)
		state.money.gold = character.gold
		state.carried_load = character.carried_load
		state.maximum_load = character.maximum_load
		var row := MoneyCharacterView.new(state)
		for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
			var availability := ActionAvailabilityView.new(&"money_action", not unavailable, "This transfer is unavailable." if unavailable else "")
			row.transfers.append(MoneyTransferView.new(denomination, 5 if denomination == &"gold" else 1, availability, availability))
		workspace.characters.append(row)
	return workspace


static func _cast_options(character: CharacterView) -> Array[InteractionRequestValue.CastOption]:
	var result: Array[InteractionRequestValue.CastOption] = []
	for spell: SpellView in character.spells.slice(0, mini(4, character.spells.size())):
		var option := InteractionRequestValue.CastOption.new()
		option.source_kind = &"spell"
		option.spell_id = spell.id
		option.spell_name = spell.name
		option.power = 2
		option.cost = spell.cost * 2
		option.target_mode = &"automatic"
		result.append(option)
	return result
