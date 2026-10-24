extends SceneTree

## Keep project-theme dependencies loadable before Godot's first asset import.

const STYLE_ROOT := "res://src/ui/shared/style/"
const IMAGE_ROOT := "res://src/ui/shared/assets/ui/"
const FONT_ROOT := "res://src/ui/shared/assets/fonts/"

const IMAGE_ASSETS := {
	"classic-raised-frame.png": "classic_theme_raised_frame.res",
	"classic-inset-frame.png": "classic_theme_inset_frame.res",
	"scroll-arrow-up.svg": "classic_theme_scroll_up.res",
	"scroll-arrow-down.svg": "classic_theme_scroll_down.res",
	"scroll-arrow-left.svg": "classic_theme_scroll_left.res",
	"scroll-arrow-right.svg": "classic_theme_scroll_right.res",
}
const FONT_ASSETS := {
	"AlegreyaSans-Regular.ttf": "classic_theme_alegreya_regular.res",
	"AlegreyaSans-Bold.ttf": "classic_theme_alegreya_bold.res",
	"BlackChancery-Realmz.ttf": "classic_theme_black_chancery.res",
	"InterVariable-Castle.ttf": "classic_theme_inter.res",
	"Theldrow-Rebuilt.ttf": "classic_theme_theldrow.res",
	"ChicagoFLF.ttf": "classic_theme_chicago.res",
}


func _initialize() -> void:
	var check_only: bool = "--check" in OS.get_cmdline_user_args()
	var failures: PackedStringArray = []
	for source_name: String in IMAGE_ASSETS:
		var source: Texture2D = load(IMAGE_ROOT + source_name) as Texture2D
		var target_path: String = STYLE_ROOT + str(IMAGE_ASSETS[source_name])
		if source == null:
			failures.append("Could not load " + source_name)
			continue
		if not check_only:
			var image_texture: ImageTexture = ImageTexture.create_from_image(source.get_image())
			if ResourceSaver.save(image_texture, target_path, ResourceSaver.FLAG_COMPRESS) != OK:
				failures.append("Could not write " + target_path)
				continue
		var baked: ImageTexture = load(target_path) as ImageTexture
		if baked == null or not _same_image(source.get_image(), baked.get_image()):
			failures.append("Theme image differs from source: " + source_name)
	for source_name: String in FONT_ASSETS:
		var source: FontFile = load(FONT_ROOT + source_name) as FontFile
		var target_path: String = STYLE_ROOT + str(FONT_ASSETS[source_name])
		if source == null:
			failures.append("Could not load " + source_name)
			continue
		if not check_only and ResourceSaver.save(source.duplicate(true), target_path, ResourceSaver.FLAG_COMPRESS) != OK:
			failures.append("Could not write " + target_path)
			continue
		var baked: FontFile = load(target_path) as FontFile
		if baked == null or baked.data != source.data:
			failures.append("Theme font differs from source: " + source_name)
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("Checked 12 first-import theme assets" if check_only else "Generated 12 first-import theme assets")
	quit(0 if failures.is_empty() else 1)


func _same_image(left: Image, right: Image) -> bool:
	return left.get_width() == right.get_width() and left.get_height() == right.get_height() and left.get_format() == right.get_format() and left.get_data() == right.get_data()
