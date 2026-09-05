## Selects and configures the visible component for one typed interaction request.
class_name InteractionComponentFactory
extends RefCounted

const PICK_LOCK_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/pick_lock_interaction.tscn"
const AGE_UPDATE_INTERACTION_SCENE_PATH := "res://src/ui/characters/age_update_interaction.tscn"
const TEXT_CHOICE_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/text_choice_interaction.tscn"
const PLAYER_MAP_INTERACTION_SCENE_PATH := "res://src/ui/journal/player_map_interaction.tscn"
const SCROLLING_TEXT_INTERACTION_SCENE_PATH := "res://src/ui/journal/scrolling_text_interaction.tscn"
const LIFECYCLE_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/lifecycle_interaction.tscn"
const BANK_INTERACTION_SCENE_PATH := "res://src/ui/services/bank_interaction.tscn"
const TEMPLE_INTERACTION_SCENE_PATH := "res://src/ui/services/temple_interaction.tscn"
const THIEF_ENCOUNTER_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/thief_encounter_interaction.tscn"
const LEVEL_UP_INTERACTION_SCENE_PATH := "res://src/ui/characters/level_up_interaction.tscn"
const ENCOUNTER_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/encounter_interaction.tscn"
const SHOP_INTERACTION_SCENE_PATH := "res://src/ui/services/shop_interaction.tscn"
const TREASURE_INTERACTION_SCENE_PATH := "res://src/ui/services/treasure_distribution_interaction.tscn"
const BATTLE_INTERACTION_SCENE_PATH := "res://src/ui/combat/battle_interaction.tscn"
const SELECTION_INTERACTION_SCENE_PATH := "res://src/ui/shared/interactions/selection_interaction.tscn"
const LayoutPolicy := preload("res://src/ui/shared/interactions/interaction_layout_policy.gd")


static func create(
	request: InteractionRequest,
	game_view: GameView,
	media: ClassicMediaCatalog,
	compact: bool,
	autojournal_enabled: bool,
	treasure_recipient_id: String,
	treasure_slot_order: Array[String],
	combat_rect: Rect2
) -> InteractionComponent:
	if LayoutPolicy.is_player_map_request(request):
		return _create_player_map(game_view, media)
	if LayoutPolicy.is_scrolling_text_request(request):
		return _create_scrolling_text(media)
	match request.kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"age_update":
			return _create_narrative_component(request.kind, media, autojournal_enabled)
		&"character_selection", &"ally_selection", &"treasure_distribution", &"level_up":
			return _create_party_component(request.kind, game_view, media, compact, treasure_recipient_id, treasure_slot_order)
		&"complex_encounter", &"thief_encounter", &"pick_lock", &"shop_action", &"temple_action", &"bank_action", &"pooled_wealth_departure":
			return _create_workspace_component(request.kind, game_view, media, compact)
		&"combat_action": return _create_combat_component(game_view, media, compact, combat_rect)
		&"session_lifecycle": return (load(LIFECYCLE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as InteractionComponent
	return null


static func _create_player_map(game_view: GameView, media: ClassicMediaCatalog) -> PlayerMapInteraction:
	var component := (load(PLAYER_MAP_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as PlayerMapInteraction
	component.configure(game_view, media)
	return component


static func _create_scrolling_text(media: ClassicMediaCatalog) -> ScrollingTextInteraction:
	var component := (load(SCROLLING_TEXT_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as ScrollingTextInteraction
	component.configure(media)
	return component


static func _create_narrative_component(kind: StringName, media: ClassicMediaCatalog, autojournal_enabled: bool) -> InteractionComponent:
	if kind == &"age_update":
		var age_update := (load(AGE_UPDATE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as AgeUpdateInteraction
		age_update.configure(media)
		return age_update
	var text_choice := (load(TEXT_CHOICE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as TextChoiceInteraction
	text_choice.configure(autojournal_enabled)
	return text_choice


static func _create_party_component(kind: StringName, game_view: GameView, media: ClassicMediaCatalog, compact: bool, treasure_recipient_id: String, treasure_slot_order: Array[String]) -> InteractionComponent:
	match kind:
		&"character_selection", &"ally_selection":
			var selection := (load(SELECTION_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as SelectionInteraction
			selection.configure(media, game_view)
			return selection
		&"treasure_distribution":
			var treasure := (load(TREASURE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as TreasureDistributionInteraction
			treasure.configure(media, game_view, compact, treasure_recipient_id, treasure_slot_order)
			return treasure
		&"level_up":
			var level_up := (load(LEVEL_UP_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as LevelUpInteraction
			level_up.configure(game_view, media)
			return level_up
	return null


static func _create_workspace_component(kind: StringName, game_view: GameView, media: ClassicMediaCatalog, compact: bool) -> InteractionComponent:
	match kind:
		&"complex_encounter":
			var encounter := (load(ENCOUNTER_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as EncounterInteraction
			encounter.configure(media, game_view, compact)
			return encounter
		&"thief_encounter":
			var thief := (load(THIEF_ENCOUNTER_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as ThiefEncounterInteraction
			thief.configure(media)
			return thief
		&"pick_lock":
			var pick_lock := (load(PICK_LOCK_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as PickLockInteraction
			pick_lock.configure(media)
			return pick_lock
		&"shop_action", &"temple_action": return _create_service_component(kind, media, compact)
		&"bank_action", &"pooled_wealth_departure":
			var bank := (load(BANK_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as BankInteraction
			bank.configure(compact)
			return bank
	return null


static func _create_service_component(kind: StringName, media: ClassicMediaCatalog, compact: bool) -> InteractionComponent:
	if kind == &"shop_action":
		var shop := (load(SHOP_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as ShopInteraction
		shop.configure(media, compact)
		return shop
	var temple := (load(TEMPLE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as TempleInteraction
	temple.configure(media, compact)
	return temple


static func _create_combat_component(game_view: GameView, media: ClassicMediaCatalog, compact: bool, combat_rect: Rect2) -> BattleInteraction:
	var battle := (load(BATTLE_INTERACTION_SCENE_PATH) as PackedScene).instantiate() as BattleInteraction
	battle.configure(_combatant_icon_textures(game_view, media), LayoutPolicy.combat_command_scale(combat_rect), compact)
	return battle


static func fast_spell_animation_frames(game_view: GameView, media: ClassicMediaCatalog, bindings: Array[InteractionRequestValue.FastSpell]) -> Dictionary:
	var result: Dictionary = {}
	if game_view == null or media == null: return result
	var requested_spell_ids: Dictionary = {}
	for binding: InteractionRequestValue.FastSpell in bindings:
		if not binding.spell_id.is_empty(): requested_spell_ids[binding.spell_id] = true
	for character: CharacterView in game_view.party_members:
		for spell: SpellView in character.spells:
			if not requested_spell_ids.has(spell.id) or result.has(spell.id): continue
			var frames: Array[Texture2D] = []
			for resource_id: int in spell.animation_resource_ids:
				var texture := media.image_texture(media.asset_by_resource(spell.animation_resource_type, resource_id))
				if texture == null:
					frames.clear()
					break
				frames.append(texture)
			if frames.size() == spell.animation_resource_ids.size() and not frames.is_empty(): result[spell.id] = frames
	return result


static func heading_for_kind(kind: StringName) -> String:
	match kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice", &"complex_encounter": return ""
		&"age_update": return "Age Update"
		&"thief_encounter": return "Encounter"
		&"pick_lock": return "Pick Lock"
		&"character_selection", &"ally_selection": return "Character Selection"
		&"treasure_distribution": return "Treasure"
		&"level_up": return "Level Up"
		&"shop_action": return "Shop"
		&"temple_action": return "Temple"
		&"bank_action": return "Bank"
		&"pooled_wealth_departure": return "Pooled Wealth"
		&"combat_action": return "Battle"
		&"session_lifecycle": return "Adventure"
	return title_for_kind(kind)


static func title_for_kind(kind: StringName) -> String:
	return String(kind).replace("_", " ").capitalize()


static func prompt_for(request: InteractionRequest, classic_text_context: String) -> String:
	var explicit_prompt := request.body.prompt_text().strip_edges()
	if not explicit_prompt.is_empty():
		return explicit_prompt
	if request.kind == InteractionRequest.ACKNOWLEDGE:
		return ""
	if request.kind == InteractionRequest.YES_NO:
		var authored_context := classic_text_context.strip_edges()
		return authored_context if not authored_context.is_empty() else "Choose Yes or No to continue."
	return title_for_kind(request.kind)


static func _combatant_icon_textures(game_view: GameView, media: ClassicMediaCatalog) -> Dictionary:
	var result: Dictionary = {}
	if game_view == null or game_view.combat_view == null or media == null: return result
	for character: CharacterView in game_view.party_members:
		var texture := media.image_texture(media.asset_by_id(character.combat_icon_id))
		if texture != null: result[character.id] = texture
	for monster: MonsterView in game_view.combat_view.monsters:
		var texture := media.image_texture(media.asset_by_resource(monster.icon_resource_type, monster.icon_id))
		if texture != null: result[monster.id] = texture
	return result
