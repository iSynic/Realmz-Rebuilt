## Measures synchronous controller focus selection at both accepted layouts.
extends SceneTree

const SAMPLE_COUNT := 1000
const LIMIT_USEC := 2000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Dictionary = {}
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(800, 600)]:
		var root := Control.new()
		root.size = viewport_size
		get_root().add_child(root)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.size = Vector2(viewport_size) - Vector2(40, 40)
		grid.position = Vector2(20, 20)
		root.add_child(grid)
		for index: int in 64:
			var button := Button.new()
			button.text = "Action %d" % index
			button.custom_minimum_size = Vector2(80, 36)
			button.set_meta("focus_group", "probe")
			grid.add_child(button)
		await process_frame
		var navigator := ControllerFocusNavigator.new()
		navigator.focus_first(root)
		for warmup: int in 32:
			navigator.move(root, Vector2i.RIGHT if warmup % 2 == 0 else Vector2i.LEFT)
		var samples: Array[int] = []
		for sample: int in SAMPLE_COUNT:
			var started := Time.get_ticks_usec()
			navigator.move(root, Vector2i.RIGHT if sample % 2 == 0 else Vector2i.LEFT)
			samples.append(Time.get_ticks_usec() - started)
		samples.sort()
		var p95 := samples[int(ceili(samples.size() * 0.95)) - 1]
		results["%dx%d" % [viewport_size.x, viewport_size.y]] = {"samples": samples.size(), "p50Usec": samples[floori(samples.size() / 2.0)], "p95Usec": p95, "maximumUsec": samples[-1]}
		root.free()
		if p95 > LIMIT_USEC:
			printerr("Controller focus p95 exceeded %d usec at %s." % [LIMIT_USEC, viewport_size])
			quit(1)
			return
	print(JSON.stringify({"controllerNavigation": results, "p95LimitUsec": LIMIT_USEC}))
	quit(0)
