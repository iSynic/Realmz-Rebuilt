## Filters a retained composed surface; xBRZ precedes CRT only when both are active.
class_name DisplayFilterPresenter
extends RefCounted

const XBRZ_SHADER := "res://src/ui/shared/style/xbrz_freescale.gdshader"
const CRT_PI_SHADER := "res://src/ui/shared/style/crt_pi.gdshader"
const CRT_LOTTES_SHADER := "res://src/ui/shared/style/crt_lottes.gdshader"

var _xbrz_material: ShaderMaterial
var _crt_pi_material: ShaderMaterial
var _crt_lottes_material: ShaderMaterial


func apply(screen: TextureRect, content: SubViewport, filter_pass: SubViewport, filter_input: TextureRect, smoothing: String, crt_enabled: bool, crt_shader: String, crt_area: String, geometry: Dictionary, world_region: Rect2, world_zoom: int) -> void:
	var scale: float = geometry["scale"]
	var full := Rect2(Vector2.ZERO, Vector2(content.size))
	var world := world_region.intersection(full)
	var world_only_smoothing := smoothing == PresentationSettings.SMOOTHING_WORLD or smoothing == PresentationSettings.SMOOTHING_WINDOW and scale <= 1.0 and world_zoom > 1
	var use_xbrz := smoothing != PresentationSettings.SMOOTHING_OFF and (scale > 1.0 or world_zoom > 1) and (not world_only_smoothing or world.has_area())
	var use_crt := crt_enabled and (crt_area == PresentationSettings.CRT_WINDOW or world.has_area())
	filter_pass.render_target_update_mode = SubViewport.UPDATE_ALWAYS if use_xbrz and use_crt else SubViewport.UPDATE_DISABLED
	filter_input.material = null
	screen.material = null
	screen.texture = content.get_texture()
	if use_xbrz:
		var xbrz_region := world if world_only_smoothing else full
		var xbrz := _xbrz()
		if xbrz == null:
			return
		xbrz.set_shader_parameter("source_size", xbrz_region.size / float(world_zoom if world_only_smoothing else 1))
		xbrz.set_shader_parameter("source_texture", content.get_texture())
		xbrz.set_shader_parameter("output_size", xbrz_region.size * scale)
		xbrz.set_shader_parameter("world_rect", _normalized(xbrz_region, full.size))
		if use_crt:
			filter_input.material = xbrz
			screen.texture = filter_pass.get_texture()
		else:
			screen.material = xbrz
	if use_crt:
		var crt := _crt(crt_shader)
		if crt == null:
			return
		var crt_region := world if crt_area == PresentationSettings.CRT_WORLD else full
		var effective_zoom := world_zoom if crt_area == PresentationSettings.CRT_WORLD else 1
		crt.set_shader_parameter("source_texture", screen.texture)
		if crt_shader == PresentationSettings.CRT_PI:
			crt.set_shader_parameter("passthrough_texture", screen.texture)
		crt.set_shader_parameter("source_size", crt_region.size / float(effective_zoom))
		crt.set_shader_parameter("output_size", crt_region.size * scale)
		crt.set_shader_parameter("region_rect", _normalized(crt_region, full.size))
		var mask_allowed := scale * float(effective_zoom) >= 2.0
		if crt_shader == PresentationSettings.CRT_PI:
			crt.set_shader_parameter("mask_strength", 1.0 if mask_allowed else 0.0)
		else:
			crt.set_shader_parameter("mask_enabled", mask_allowed)
		screen.material = crt


func _xbrz() -> ShaderMaterial:
	if _xbrz_material == null:
		_xbrz_material = _material(XBRZ_SHADER)
	return _xbrz_material


func _crt(shader_id: String) -> ShaderMaterial:
	if shader_id == PresentationSettings.CRT_LOTTES:
		if _crt_lottes_material == null:
			_crt_lottes_material = _material(CRT_LOTTES_SHADER)
		return _crt_lottes_material
	if _crt_pi_material == null:
		_crt_pi_material = _material(CRT_PI_SHADER)
	return _crt_pi_material


static func _material(path: String) -> ShaderMaterial:
	var shader := load(path) as Shader
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


static func _normalized(region: Rect2, full_size: Vector2) -> Vector4:
	return Vector4(region.position.x / full_size.x, region.position.y / full_size.y, region.size.x / full_size.x, region.size.y / full_size.y)
