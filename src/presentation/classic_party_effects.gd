class_name ClassicPartyEffects
extends RefCounted

const FIRST_RESOURCE_ID := 13992
const FRAME_COUNT := 8
const ICON_NATIVE_SIZE := 32.0
const SLOT_BORDER := 2.0
const NAMES: Array[String] = [
	"Waterworld",
	"Dragon Hide",
	"Discover Secret",
	"Wizard Eye",
	"Search",
	"Free Fall / Levitate",
	"Sentry",
	"Charm Resistance",
]


static func build_slots(grid: GridContainer) -> Array[TextureRect]:
	var slots: Array[TextureRect] = []
	for condition_index: int in range(1, 9):
		var frame := Control.new()
		frame.name = "PartyEffectSlot%d" % condition_index
		frame.custom_minimum_size = Vector2.ONE * slot_size(1)
		var background := Panel.new()
		background.name = "Background"
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.theme_type_variation = &"ClassicInset"
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(background)
		var center := CenterContainer.new()
		center.name = "Center"
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(center)
		var icon := TextureRect.new()
		icon.name = "PartyEffectIcon%d" % condition_index
		icon.custom_minimum_size = Vector2.ONE * icon_size(1)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.tooltip_text = NAMES[condition_index - 1]
		frame.tooltip_text = icon.tooltip_text
		center.add_child(icon)
		grid.add_child(frame)
		slots.append(icon)
	return slots


static func icon_size(bitmap_scale: int) -> float:
	return ICON_NATIVE_SIZE * maxi(1, bitmap_scale)


static func slot_size(bitmap_scale: int) -> float:
	return icon_size(bitmap_scale) + SLOT_BORDER * 2.0


static func texture(media: ClassicMediaCatalog, cache: Dictionary, condition_index: int, frame_index: int) -> Texture2D:
	if media == null:
		return null
	var resource_id := resource_id(condition_index, frame_index)
	if cache.has(resource_id):
		return cache[resource_id] as Texture2D
	var asset := media.asset_by_resource("cicn", resource_id)
	var result := media.image_texture(asset) if asset != null and asset.is_picture() else null
	if condition_index == ConditionRules.PARTY_SEARCHING:
		result = ClassicSearchCommandButton.remove_classic_matte(result)
	cache[resource_id] = result
	return result


static func resource_id(condition_index: int, frame_index: int) -> int:
	return FIRST_RESOURCE_ID + clampi(condition_index, 1, 8) * FRAME_COUNT + posmod(frame_index, FRAME_COUNT)
