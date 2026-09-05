@tool
## Binds representative detached game views through major production screen controllers.

extends RefCounted

const SUPPORTED_SURFACES: Array[String] = [
	"character-sheet",
	"inventory",
	"spells",
	"services",
	"roster-spellbook",
	"character-files",
	"allies",
	"bestiary",
	"maps-journal",
	"system",
	"application-shell",
	"campaign-selection",
	"party-assembly",
	"character-creation",
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
		"character-files": _bind_vault_screen(surface as VaultScreen, view, profile, compact)
		"allies": _bind_creature_screen(surface as CreatureLibraryScreen, view, profile, compact, true)
		"bestiary": _bind_creature_screen(surface as CreatureLibraryScreen, view, profile, compact, false)
		"maps-journal": _bind_journal_screen(surface as JournalScreen, view, compact)
		"system": _bind_system_screen(surface as SystemScreen, view, profile, compact)
		"application-shell": _bind_application_shell(surface as GameShell, view)
		"campaign-selection": _bind_campaign_selection(surface as CampaignSelectionPanel, view, profile)
		"party-assembly": _bind_party_setup(surface as PartySetupWorkspace, view, profile, false)
		"character-creation": _bind_party_setup(surface as PartySetupWorkspace, view, profile, true)
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


static func _bind_vault_screen(screen: VaultScreen, view: GameView, profile: String, compact: bool) -> void:
	var controller := CharacterScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.set_vault_revisions(_vault_revisions(view, profile))
	controller.present_vault(screen, view, {}, 1.0)
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_creature_screen(screen: CreatureLibraryScreen, view: GameView, profile: String, compact: bool, allies: bool) -> void:
	var controller := CreatureLibraryScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	_populate_creatures(view, profile)
	if allies:
		controller.present_allies(screen, view, null, 1.0)
	else:
		controller.present_bestiary(screen, view, null, 1.0)
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_journal_screen(screen: JournalScreen, view: GameView, compact: bool) -> void:
	var controller := MapsJournalScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.present(screen, view, null)
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_system_screen(screen: SystemScreen, view: GameView, profile: String, compact: bool) -> void:
	var controller := SystemScreenController.new()
	controller.set_layout_profile(UiLayoutProfile.COMPACT if compact else UiLayoutProfile.WIDE)
	controller.set_save_previews(_save_previews(profile))
	controller.present(screen, view, PresentationSettings.new())
	screen.set_meta("realmz_builder_controller", controller)


static func _bind_application_shell(shell: GameShell, view: GameView) -> void:
	if shell.is_node_ready():
		shell.present(view)
		shell.status.set_status("Realmz Builder representative application state")
		return
	(shell.find_child("PackageStatus", true, false) as Label).text = view.campaign_summary.title if view.campaign_summary != null else "No campaign"
	(shell.find_child("Status", true, false) as Label).text = "Realmz Builder representative application state"
	var roster := shell.find_child("PartyRoster", true, false) as ClassicPartyRoster
	roster.present(view, view.party_members[0].id if not view.party_members.is_empty() else "")


static func _bind_campaign_selection(panel: CampaignSelectionPanel, view: GameView, profile: String) -> void:
	var controller := CampaignLibraryController.new()
	controller.attach(panel)
	controller.bind_campaign_panel(panel)
	controller.set_campaigns(_campaigns(profile))
	controller.set_selected_campaign_summary(view.campaign_summary if profile != "Empty" else null)
	controller.show_campaign()
	panel.set_meta("realmz_builder_controller", controller)


static func _bind_party_setup(workspace: PartySetupWorkspace, view: GameView, profile: String, creator: bool) -> void:
	_prepare_party_setup_view(view, profile)
	var controller := CampaignPartySetupController.new()
	controller.attach(workspace)
	controller.campaign_library.build_campaign_overlay()
	controller.bind_setup_workspace(workspace)
	controller.campaign_library.set_campaigns(_campaigns(profile))
	controller.set_vault_revisions(_vault_revisions(view, profile))
	controller.set_view(view)
	controller.show_party_setup()
	if creator:
		(workspace.find_child("CreateCharacter", true, false) as Button).pressed.emit()
	workspace.set_meta("realmz_builder_controller", controller)


static func _game_view(profile: String) -> GameView:
	var view := GameView.new(1, profile != "Error", null)
	view.party_summary = PartySummaryView.new()
	view.campaign_id = "realmz-builder"
	view.rules_version = "realmz-classic-1"
	view.campaign_summary = CampaignSummaryView.new()
	view.campaign_summary.campaign_id = view.campaign_id
	view.campaign_summary.title = "City of Bywater"
	view.set_action_availability(&"reorder_party", profile != "Unavailable", "Party order is locked during this preview state.")
	view.set_action_availability(&"change_character_appearance", profile != "Unavailable", "Appearance changes are unavailable.")
	view.set_action_availability(&"money_action", profile != "Unavailable", "Party wealth is unavailable.")
	view.set_action_availability(&"service_action", profile != "Unavailable", "No location service is available.")
	view.set_action_availability(&"import_vault_character", profile != "Unavailable", "Character import is unavailable.")
	view.set_action_availability(&"set_location_note", profile != "Unavailable", "Location notes are unavailable.")
	view.set_action_availability(&"remove_party_member", profile != "Unavailable", "The party order is locked.")
	view.set_action_availability(&"begin_adventure", profile != "Unavailable", "The party cannot begin this adventure.")
	view.set_action_availability(&"generate_character_draft", profile != "Unavailable", "Character generation is unavailable.")
	view.set_action_availability(&"finalize_character", profile != "Unavailable", "This character cannot be finalized.")
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
	_populate_journal(view, profile)
	return view


static func _prepare_party_setup_view(view: GameView, profile: String) -> void:
	view.party_setup_available = true
	view.party_setup = PartySetupView.new()
	view.party_setup.available_monster_sets.assign([0, -1, 1])
	for character: CharacterView in view.party_members:
		view.party_setup.current_party_levels += character.level
	view.party_setup.experience_percent = 100
	view.campaign_summary.version = "1.0"
	view.campaign_summary.author = "The Realmz Guild"
	view.campaign_summary.maximum_party_size = 6
	view.campaign_summary.maximum_level = 10
	view.campaign_summary.maximum_party_levels = 42
	view.campaign_summary.recommended_party_levels = 24
	view.campaign_summary.guidance_authored = true
	view.campaign_summary.restriction_description = "A company of six experienced adventurers is recommended."
	if profile == "Error":
		view.campaign_summary.restriction_description = "The selected scenario could not be fully validated."


static func _campaigns(profile: String) -> Array[CampaignPackageView]:
	var result: Array[CampaignPackageView] = []
	if profile == "Empty":
		return result
	var count := 8 if profile == "Long Content" else 3
	for index: int in count:
		var ready := profile != "Error" or index > 0
		result.append(CampaignPackageView.new(
			"res://packages/builder-%d.realmz2" % index,
			ready,
			"builder.campaign.%d" % index,
			("%x" % (index + 1)).repeat(64).left(64),
			"realmz-classic-1",
			"Package validation failed." if not ready else "",
			["City of Bywater", "Assault on Giant Mountain", "War in the Sword Lands"][index % 3]
		))
	return result


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


static func _vault_revisions(view: GameView, profile: String) -> Array[CharacterVaultRevisionView]:
	var result: Array[CharacterVaultRevisionView] = []
	if profile in ["Empty", "Error"]:
		return result
	for index: int in view.party_members.size():
		var character := view.party_members[index]
		var revision := CharacterVaultRevisionView.new()
		revision.character_id = character.id
		revision.revision_hash = ("%x" % (index + 10)).repeat(64).left(64)
		revision.name = character.name
		revision.level = character.level
		revision.race_id = character.race_id
		revision.caste_id = character.caste_id
		revision.is_current = true
		revision.eligible = profile != "Unavailable"
		if not revision.eligible:
			revision.eligibility_reasons.append("This character is not eligible for the selected campaign.")
		revision.character = character
		result.append(revision)
	return result


static func _populate_creatures(view: GameView, profile: String) -> void:
	if profile in ["Empty", "Error"]:
		return
	var count := 10 if profile == "Long Content" else 3
	for index: int in count:
		var definition := _monster_definition(index)
		view.bestiary_entries.append(MonsterCatalogEntryView.new(definition))
		var state := MonsterState.new("builder.ally.%d" % index, definition.id, definition.name, 12 + index, 20 + index, definition.hit_dice, 8, definition.armor, definition.magic_resistance, 4, false)
		view.party_allies.append(MonsterView.new(state, definition))


static func _monster_definition(index: int) -> MonsterDefinition:
	var names: Array[String] = ["Allied Knight", "Forest Wolf", "Goblin Archer", "Cave Bear"]
	var definition := MonsterDefinition.new(
		"classic.monster.%d" % (index + 1), index + 1, names[index % names.size()], 2 + index % 5, 0, 8, 6 + index, 10 + index,
		[0, 0, 0, 0], [20, 20, 20, 20, 20, 20, 20, 20], [0, 0, 0, 0, 0, 0], [0, 0, 0], [], [], [], [], 100 + index,
		"A source-backed creature record represented through the shared library workspace."
	)
	definition.movement_max = 6
	definition.attack_count = 2
	return definition


static func _populate_journal(view: GameView, profile: String) -> void:
	var record_count := 18 if profile == "Long Content" else 3
	for index: int in record_count:
		view.journal_entries.append(JournalEntryView.new(100 + index, "Journal account %d: the company records a warning, a landmark, and the road ahead." % (index + 1)))
	var note := LocationNoteView.new("land:0", "Northern Reaches", &"land", 0, Vector2i(12, 82), "A sheltered camp lies beside the old road.", 0, 1, true)
	view.location_notes.append(note)
	view.current_location_note = note
	var definition := PlayerMapDefinition.new("builder.map.2", 2, "Cavern Route", "Unknown map", PlayerMapDefinition.PICTURE, "land:0", Vector2i.ZERO, 16, "", "", "", Rect2i(), [], "A map showing the concealed road into the keep.")
	var player_map := PlayerMapView.new(definition)
	view.acquired_player_maps.append(player_map)
	view.player_map_menu_entries.append(player_map)
	view.party_summary.acquired_map_ids.append(player_map.id)


static func _save_previews(profile: String) -> Array[SaveSlotPreview]:
	var result: Array[SaveSlotPreview] = []
	if profile in ["Empty", "Error"]:
		return result
	var count := 8 if profile == "Long Content" else 2
	for index: int in count:
		var preview := SaveSlotPreview.new("quick" if index == 0 else "journey-%d" % index, SaveSlotPreview.PRIMARY, SaveSlotPreview.CORRUPT if profile == "Unavailable" and index == 0 else SaveSlotPreview.VALID)
		preview.campaign_id = "realmz-builder"
		preview.package_hash = "a".repeat(64)
		preview.rules_version = "realmz-classic-1"
		preview.realmz_day = 12
		preview.realmz_hour = 7 + index
		preview.map_id = "land:0"
		preview.coordinate = Vector2i(12 + index, 82)
		preview.character_names.assign(["Kevlar", "Lothlorian", "Silver Leaf"])
		preview.can_load = preview.status == SaveSlotPreview.VALID
		preview.error_message = "The save record could not be validated." if not preview.can_load else ""
		result.append(preview)
	return result
