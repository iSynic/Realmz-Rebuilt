extends SceneTree

const PACKAGE_REPOSITORY_SCRIPT := preload("res://src/infrastructure/packages/package_repository.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_discovery_probe.gd -- <package-root>")
		call_deferred("_quit_cleanly", 2)
		return
	var repository := PACKAGE_REPOSITORY_SCRIPT.new()
	var started_at := Time.get_ticks_msec()
	var campaigns := repository.discover_campaigns([arguments[0]])
	var elapsed_ms := Time.get_ticks_msec() - started_at
	var ready_count := 0
	for campaign: PackageDiscoveryResult in campaigns:
		if campaign.ready:
			ready_count += 1
	print(CanonicalJson.encode({
		"campaigns": campaigns.size(),
		"discoveryMs": elapsed_ms,
		"ready": ready_count,
	}))
	repository.close()
	call_deferred("_quit_cleanly", 0)


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
