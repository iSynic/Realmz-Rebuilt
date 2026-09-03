class_name InteractionComponentFactory
extends RefCounted

const PickLockInteractionScript := preload("res://src/ui/interaction_components/pick_lock_interaction.gd")
const ThiefEncounterInteractionScript := preload("res://src/ui/interaction_components/thief_encounter_interaction.gd")
const LifecycleInteractionScript := preload("res://src/ui/interaction_components/lifecycle_interaction.gd")
const ScrollingTextInteractionScript := preload("res://src/ui/interaction_components/scrolling_text_interaction.gd")
const LayoutPolicy := preload("res://src/ui/interaction_layout_policy.gd")


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
		var player_map := PlayerMapInteraction.new()
		player_map.configure(game_view, media)
		return player_map
	if LayoutPolicy.is_scrolling_text_request(request):
		var scrolling_text := ScrollingTextInteractionScript.new()
		scrolling_text.configure(media)
		return scrolling_text
	match request.kind:
		&"acknowledge", &"yes_no", &"encounter_choice", &"scenario_choice":
			var text_choice := TextChoiceInteraction.new()
			text_choice.configure(autojournal_enabled)
			return text_choice
		&"age_update":
			var age_update := AgeUpdateInteraction.new()
			age_update.configure(media)
			return age_update
		&"character_selection", &"ally_selection":
			var selection := SelectionInteraction.new()
			selection.configure(media, game_view)
			return selection
		&"treasure_distribution":
			var treasure := TreasureDistributionInteraction.new()
			treasure.configure(media, game_view, compact, treasure_recipient_id, treasure_slot_order)
			return treasure
		&"level_up":
			var level_up := LevelUpInteraction.new()
			level_up.configure(game_view, media)
			return level_up
		&"complex_encounter":
			var encounter := EncounterInteraction.new()
			encounter.configure(media, game_view, compact)
			return encounter
		&"thief_encounter":
			var thief := ThiefEncounterInteractionScript.new()
			thief.configure(media)
			return thief
		&"pick_lock":
			var pick_lock := PickLockInteractionScript.new()
			pick_lock.configure(media)
			return pick_lock
		&"shop_action":
			var shop := ShopInteraction.new()
			shop.configure(media, compact)
			return shop
		&"temple_action":
			var temple := TempleInteraction.new()
			temple.configure(media, compact)
			return temple
		&"bank_action", &"pooled_wealth_departure":
			var bank := BankInteraction.new()
			bank.configure(compact)
			return bank
		&"combat_action":
			var battle := BattleInteraction.new()
			battle.configure(_combatant_icon_textures(game_view, media), LayoutPolicy.combat_command_scale(combat_rect))
			return battle
		&"session_lifecycle":
			return LifecycleInteractionScript.new()
	return null


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
