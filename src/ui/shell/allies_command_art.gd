## Composes the Party footer Allies command art from the battle icons of the first three traveling allies.
##
## The first ally stands in front with the next two behind it, so the composite stays within the
## footprint of the other command art. With no travelers, three faint empty slots keep the same shape.
class_name AlliesCommandArt
extends RefCounted

const ICON_SIZE := 32
const MAXIMUM_ALLIES := 3
const SLOT_COLOR := Color(0.55, 0.57, 0.6, 0.55)
## Back-left, back-right, then front; the first traveler is drawn last so it stays on top.
const POSITIONS: Array[Vector2i] = [Vector2i(7, 8), Vector2i(0, 0), Vector2i(14, 0)]
const TWO_POSITIONS: Array[Vector2i] = [Vector2i(14, 8), Vector2i(0, 0)]

var _key: Array = []
var _texture: Texture2D


## Returns the cached composite while the media catalog and traveling icons are unchanged.
func texture(media: ClassicMediaCatalog, game_view: GameView) -> Texture2D:
	var travelers: Array[MonsterView] = []
	var key: Array = [media]
	for ally: MonsterView in (game_view.party_allies if game_view != null else travelers):
		if ally.icon_id > 0 and travelers.size() < MAXIMUM_ALLIES:
			travelers.append(ally)
			key.append("%s:%d" % [ally.icon_resource_type, ally.icon_id])
	if _texture != null and key == _key:
		return _texture
	var icons: Array[Image] = []
	for ally: MonsterView in travelers:
		var icon := _icon_image(media, ally)
		if icon != null:
			icons.append(icon)
	_key = key
	_texture = ImageTexture.create_from_image(_compose(icons))
	return _texture


static func _compose(icons: Array[Image]) -> Image:
	var positions: Array[Vector2i] = TWO_POSITIONS if icons.size() == 2 else POSITIONS
	var canvas_size := Vector2i(ICON_SIZE, ICON_SIZE) if icons.size() == 1 else Vector2i(ICON_SIZE + 14, ICON_SIZE + 8)
	var canvas := Image.create_empty(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	if icons.is_empty():
		for index: int in [1, 2, 0]:
			_outline(canvas, Rect2i(POSITIONS[index], Vector2i(ICON_SIZE, ICON_SIZE)))
		return canvas
	for index: int in range(icons.size() - 1, -1, -1):
		var icon := icons[index]
		var offset := Vector2i.ZERO if icons.size() == 1 else positions[index]
		offset += (Vector2i(ICON_SIZE, ICON_SIZE) - icon.get_size()) / 2
		canvas.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), offset)
	return canvas


static func _outline(canvas: Image, rect: Rect2i) -> void:
	for x: int in range(rect.position.x + 2, rect.end.x - 2):
		canvas.set_pixel(x, rect.position.y, SLOT_COLOR)
		canvas.set_pixel(x, rect.end.y - 1, SLOT_COLOR)
	for y: int in range(rect.position.y + 2, rect.end.y - 2):
		canvas.set_pixel(rect.position.x, y, SLOT_COLOR)
		canvas.set_pixel(rect.end.x - 1, y, SLOT_COLOR)


## Native icon pixels, reduced by a whole-number factor only when a large icon exceeds one cell.
static func _icon_image(media: ClassicMediaCatalog, ally: MonsterView) -> Image:
	if media == null:
		return null
	var texture := media.image_texture(media.asset_by_resource(ally.icon_resource_type, ally.icon_id))
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	var factor := ceili(float(maxi(image.get_width(), image.get_height())) / ICON_SIZE)
	if factor > 1:
		image.resize(maxi(1, image.get_width() / factor), maxi(1, image.get_height() / factor), Image.INTERPOLATE_NEAREST)
	return image
