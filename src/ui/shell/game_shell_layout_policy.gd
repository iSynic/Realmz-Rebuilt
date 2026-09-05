## Calculates the stable responsive dimensions used by the scene-backed shell.
class_name GameShellLayoutPolicy
extends RefCounted


static func party_effect_icon_size(bitmap_scale: int) -> float:
	return ClassicPartyEffects.icon_size(bitmap_scale)


static func party_effect_slot_size(bitmap_scale: int) -> float:
	return ClassicPartyEffects.slot_size(bitmap_scale)


static func party_roster_height(viewport_height: float, menu_height: float, stage_height: float, combat_spellbook_active: bool) -> float:
	return viewport_height - menu_height if combat_spellbook_active else stage_height


static func party_roster_z_index(combat_spellbook_active: bool) -> int:
	return 81 if combat_spellbook_active else 14


static func combat_spellbook_roster_width(viewport_width: float, party_width: float, ui_scale: float, combat_spellbook_active: bool) -> float:
	return maxf(party_width, minf(352.0 * ui_scale, viewport_width - 320.0 * ui_scale)) if combat_spellbook_active else party_width


static func combat_spellbook_stage_width(stage_width: float, viewport_width: float, roster_width: float) -> float:
	return minf(stage_width, viewport_width - roster_width)


static func exploration_footer_width(viewport_size: Vector2, profile: UiLayoutProfile, route_id: StringName) -> float:
	return ScreenNavigator.spell_screen_rect_for(profile, viewport_size).position.x if route_id == &"spells" else viewport_size.x
