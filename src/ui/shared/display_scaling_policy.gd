## Calculates the one window-to-application transform used by rendering and input.
class_name DisplayScalingPolicy
extends RefCounted

const BASE_SIZE := Vector2i(1280, 720)


static func geometry(window_size: Vector2i, mode: String) -> Dictionary:
	var size := Vector2i(maxi(window_size.x, 1), maxi(window_size.y, 1))
	if mode in [PresentationSettings.DISPLAY_RESPONSIVE, PresentationSettings.DISPLAY_INTEGER_CANVAS] or size.x < BASE_SIZE.x or size.y < BASE_SIZE.y:
		return {"source_size": size, "screen_rect": Rect2(Vector2.ZERO, Vector2(size)), "scale": 1.0, "effective_mode": PresentationSettings.DISPLAY_RESPONSIVE if mode != PresentationSettings.DISPLAY_INTEGER_CANVAS else mode}
	if mode == PresentationSettings.DISPLAY_INTEGER_WINDOW:
		var factor := maxi(1, mini(floori(float(size.x) / BASE_SIZE.x), floori(float(size.y) / BASE_SIZE.y)))
		var drawn := Vector2(BASE_SIZE * factor)
		return {"source_size": BASE_SIZE, "screen_rect": Rect2((Vector2(size) - drawn) * 0.5, drawn), "scale": float(factor), "effective_mode": mode}
	var factor := minf(float(size.x) / BASE_SIZE.x, float(size.y) / BASE_SIZE.y)
	var source := Vector2i(ceili(float(size.x) / factor), ceili(float(size.y) / factor))
	var drawn := Vector2(source) * factor
	return {"source_size": source, "screen_rect": Rect2((Vector2(size) - drawn) * 0.5, drawn), "scale": factor, "effective_mode": PresentationSettings.DISPLAY_FILL_WINDOW}
