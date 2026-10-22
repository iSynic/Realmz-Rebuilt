## Resolves and composes native party portraits from the active media catalog.
class_name PartyRosterPortraits
extends RefCounted

const CLASSIC_PORTRAIT_STAGE_SIZE := Vector2i(50, 50)
const CLASSIC_DEATH_HEALTH := -10
const CLASSIC_PORTRAIT_SHADE_CICN := 2019
const CLASSIC_DEATH_MARKER_CICN := 2015
const HEALTH_UNSPECIFIED := -100_000

var _media: ClassicMediaCatalog
var _portrait_composites: Dictionary = {}


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_portrait_composites.clear()


func health_shade(health: int) -> int:
	return 2 if health <= CLASSIC_DEATH_HEALTH else 1 if health < 1 else 0


func roster_portrait_texture(character: CharacterView, health: int = HEALTH_UNSPECIFIED) -> Texture2D:
	var state := health_shade(character.current_health if health == HEALTH_UNSPECIFIED else health)
	var cache_key := "%s|%d" % [character.portrait_id, state]
	if _portrait_composites.has(cache_key):
		return _portrait_composites[cache_key] as Texture2D
	var portrait := _portrait_texture(character.portrait_id)
	if portrait == null and state == 0:
		return null
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, portrait)
	if state > 0:
		_blend_centered(image, _resource_texture(CLASSIC_PORTRAIT_SHADE_CICN))
	if state == 2:
		_blend_centered(image, _resource_texture(CLASSIC_DEATH_MARKER_CICN))
	var composite := ImageTexture.create_from_image(image)
	_portrait_composites[cache_key] = composite
	return composite


func effect_portrait_texture(base_icon: Texture2D, resource_id: int) -> Texture2D:
	var image := Image.create(CLASSIC_PORTRAIT_STAGE_SIZE.x, CLASSIC_PORTRAIT_STAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_blend_centered(image, base_icon)
	_blend_centered(image, _resource_texture(resource_id))
	return ImageTexture.create_from_image(image)


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null or asset_id.is_empty():
		return null
	var asset := _media.asset_by_id(asset_id)
	if asset == null or not asset.is_picture():
		return null
	return _media.image_texture(asset)


func _resource_texture(resource_id: int) -> Texture2D:
	if _media == null:
		return null
	var asset := _media.asset_by_resource("cicn", resource_id)
	return _media.image_texture(asset) if asset != null and asset.is_picture() else null


static func _blend_centered(destination: Image, texture: Texture2D) -> void:
	if texture == null:
		return
	var source := texture.get_image()
	if source == null or source.is_empty():
		return
	var width := mini(source.get_width(), destination.get_width())
	var height := mini(source.get_height(), destination.get_height())
	var source_position := Vector2i((source.get_width() - width) / 2, (source.get_height() - height) / 2)
	var destination_position := Vector2i((destination.get_width() - width) / 2, (destination.get_height() - height) / 2)
	destination.blend_rect(source, Rect2i(source_position, Vector2i(width, height)), destination_position)
