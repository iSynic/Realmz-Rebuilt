## Presents one isolated Providence preview through the production application shell.

extends Node


func launch(
	request: DevelopmentPreviewRequest,
	session: GameSessionController,
	presentation: PresentationCoordinator,
	media: PresentationMediaController,
	shell: GameShell,
	content_ready: Callable
) -> void:
	_run.call_deferred(request, session, presentation, media, shell, content_ready)


func _run(
	request: DevelopmentPreviewRequest,
	session: GameSessionController,
	presentation: PresentationCoordinator,
	media: PresentationMediaController,
	shell: GameShell,
	content_ready: Callable
) -> void:
	shell.status.set_status("Preparing Providence preview…")
	await get_tree().process_frame
	var preview := DevelopmentPreviewSession.new()
	if not preview.load_request(request):
		_finish_failure(request, preview, shell)
		return
	content_ready.call(preview.content)
	media.set_application_character_media(preview.application_media)
	media.set_package_media(preview.package_media)
	if not preview.start(session):
		_finish_failure(request, preview, shell)
		return
	presentation.refresh()
	shell.status.set_status("Providence preview • %s" % String(request.target_kind))
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw
	var write_error := DevelopmentPreviewResultWriter.write(request, preview.ready_fields())
	if not write_error.is_empty():
		printerr("PREVIEW_RESULT_REJECTED write_failed: %s" % write_error)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if write_error.is_empty() else 1)


func _finish_failure(request: DevelopmentPreviewRequest, preview: DevelopmentPreviewSession, shell: GameShell) -> void:
	shell.status.set_status("Preview failed • %s" % preview.error_message, true)
	var write_error := DevelopmentPreviewResultWriter.write(request, preview.failure_fields())
	if not write_error.is_empty():
		printerr("PREVIEW_RESULT_REJECTED write_failed: %s" % write_error)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)
