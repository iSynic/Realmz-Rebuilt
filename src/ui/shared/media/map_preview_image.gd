## Turns a save's map preview JPEG into a texture without the black border the map leaves
## outside its edges (a party near the top of a land map shows a black band above it).

class_name MapPreviewImage
extends RefCounted

## A pixel this dark (0–1 brightness) counts as off-map; JPEG noise keeps true black slightly above 0.
const OFF_MAP := 0.06
## A border row or column this much off-map is trimmed. A corner of the map can reach into an
## off-map band, so the band need not be entirely black.
const MOSTLY := 0.75
## At most this share of each side is trimmed, so a dark map can never be peeled away to a sliver.
const MAX_TRIM := 0.25


static func texture(jpeg: PackedByteArray) -> Texture2D:
	if jpeg.is_empty():
		return null
	var image := Image.new()
	if image.load_jpg_from_buffer(jpeg) != OK:
		return null
	var used := _map_rect(image)
	if used.size != image.get_size():
		image = image.get_region(used)
	return ImageTexture.create_from_image(image)


## The rectangle inside any border rows and columns that are mostly off-map.
static func _map_rect(image: Image) -> Rect2i:
	var width := image.get_width()
	var height := image.get_height()
	var limit_y := floori(height * MAX_TRIM)
	var limit_x := floori(width * MAX_TRIM)
	var top := 0
	while top < limit_y and _dark_row(image, top):
		top += 1
	var bottom := height - 1
	while bottom > height - 1 - limit_y and _dark_row(image, bottom):
		bottom -= 1
	var left := 0
	while left < limit_x and _dark_column(image, left, top, bottom):
		left += 1
	var right := width - 1
	while right > width - 1 - limit_x and _dark_column(image, right, top, bottom):
		right -= 1
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


## Off-map area is one solid block from the map's edge, so a row counts only when an unbroken dark
## run from its left or right end covers most of it. Dark paths and lit spots inside a map break that run.
static func _dark_row(image: Image, y: int) -> bool:
	var samples: Array[bool] = []
	for x: int in range(0, image.get_width(), 2):
		samples.append(image.get_pixel(x, y).get_luminance() <= OFF_MAP)
	return _edge_run(samples) >= samples.size() * MOSTLY


static func _dark_column(image: Image, x: int, top: int, bottom: int) -> bool:
	var samples: Array[bool] = []
	for y: int in range(top, bottom + 1, 2):
		samples.append(image.get_pixel(x, y).get_luminance() <= OFF_MAP)
	return _edge_run(samples) >= samples.size() * MOSTLY


## The longer of the dark runs that start at either end.
static func _edge_run(samples: Array[bool]) -> int:
	var from_start := 0
	while from_start < samples.size() and samples[from_start]:
		from_start += 1
	var from_end := 0
	while from_end < samples.size() and samples[samples.size() - 1 - from_end]:
		from_end += 1
	return maxi(from_start, from_end)
