## Derives disposable map tiles without changing the complete source resource.
class_name ClassicMapAtlas
extends RefCounted

var source: MediaAsset
var texture: Texture2D
var tile_width: int
var tile_height: int
var columns: int
var rows: int
var dungeon: bool


func _init(asset: MediaAsset, source_texture: Texture2D) -> void:
	source = asset
	texture = source_texture
	tile_width = asset.tile_width
	tile_height = asset.tile_height
	columns = asset.columns
	rows = asset.rows
	dungeon = asset.resource_type == "PICT" and asset.resource_id == 302
	if dungeon and asset.width == 640 and asset.height == 640:
		var crop := source_texture.get_image().get_region(Rect2i(576, 320, 64, 64))
		crop.convert(Image.FORMAT_RGBA8)
		for y: int in 64:
			for x: int in 64:
				# Castle draws the first fifteen cells transparently; cell sixteen is the floor.
				if x >= 48 and y >= 48:
					continue
				var pixel := crop.get_pixel(x, y)
				if pixel.r > 245.0 / 255.0 and pixel.g > 245.0 / 255.0 and pixel.b > 245.0 / 255.0:
					crop.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
		texture = ImageTexture.create_from_image(crop)
		tile_width = 16
		tile_height = 16
		columns = 4
		rows = 4


func region_for(tile_id: int) -> Rect2i:
	if tile_id <= 0 or tile_id > columns * rows:
		return Rect2i()
	var index := tile_id - 1
	return Rect2i((index % columns) * tile_width, floori(float(index) / columns) * tile_height, tile_width, tile_height)
