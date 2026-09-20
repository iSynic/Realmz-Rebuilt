/*
 * PUBLIC DOMAIN CRT STYLED SCAN-LINE SHADER
 *
 *   by Timothy Lottes
 *
 * This is more along the style of a really good CGA arcade monitor.
 * With RGB inputs instead of NTSC.
 * The shadow mask example has the mask rotated 90 degrees for less
 * chromatic aberration.
 *
 * Left it unoptimized to show the theory behind the algorithm.
 *
 * It is an example what I personally would want as a display option for
 * pixel art games.
 * Please take and use, change, or whatever.
 *
 * The source adaptation is pinned to
 * libretro/slang-shaders crt/shaders/crt-lottes.slang at commit
 * afb1416b6b85d3e53c6e586a9209cb9097c7b4a4.
 *
 * This Godot 4 CanvasItem port removes the source shader's vertex/UBO
 * plumbing and intentionally disables curvature (Warp is identity). The
 * filtering, bloom, linear-gamma option, and shadow-mask calculations remain.
 */

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_texture : filter_nearest;
uniform vec2 source_size = vec2(1.0);
uniform vec2 output_size = vec2(1.0);
uniform vec4 region_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool mask_enabled = true;

uniform float hard_scan = -8.0;
uniform float hard_pix = -3.0;
uniform float mask_dark = 0.5;
uniform float mask_light = 1.5;
uniform bool scale_in_linear_gamma = true;
uniform float shadow_mask = 3.0;
uniform float bright_boost = 1.0;
uniform float hard_bloom_pix = -1.5;
uniform float hard_bloom_scan = -2.0;
uniform float bloom_amount = 0.15;
uniform float shape = 2.0;

vec2 safe_source_size() {
	return max(source_size, vec2(1.0));
}

vec2 clamp_region_uv(vec2 uv) {
	vec2 texel = region_rect.zw / safe_source_size();
	return clamp(uv, region_rect.xy + texel * 0.5,
		region_rect.xy + region_rect.zw - texel * 0.5);
}

vec3 to_linear(vec3 colour) {
	if (!scale_in_linear_gamma) {
		return colour;
	}
	vec3 low = colour / 12.92;
	vec3 high = pow((colour + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(high, low, step(colour, vec3(0.04045)));
}

vec3 to_srgb(vec3 colour) {
	if (!scale_in_linear_gamma) {
		return colour;
	}
	vec3 low = colour * 12.92;
	vec3 high = 1.055 * pow(max(colour, vec3(0.0)), vec3(0.41666)) - 0.055;
	return mix(high, low, step(colour, vec3(0.0031308)));
}

vec3 fetch_pixel(vec2 position, vec2 offset) {
	vec2 source = safe_source_size();
	vec2 uv = (floor(position * source + offset) + vec2(0.5)) / source;
	uv = region_rect.xy + uv * region_rect.zw;
	return to_linear(bright_boost * texture(source_texture, clamp_region_uv(uv)).rgb);
}

vec2 distance_to_texel(vec2 position) {
	vec2 source = safe_source_size();
	position *= source;
	return -((position - floor(position)) - vec2(0.5));
}

float gaussian(float position, float scale) {
	return exp2(scale * pow(abs(position), shape));
}

vec3 horizontal3(vec2 position, float offset) {
	vec3 b = fetch_pixel(position, vec2(-1.0, offset));
	vec3 c = fetch_pixel(position, vec2(0.0, offset));
	vec3 d = fetch_pixel(position, vec2(1.0, offset));
	float distance_x = distance_to_texel(position).x;
	float wb = gaussian(distance_x - 1.0, hard_pix);
	float wc = gaussian(distance_x, hard_pix);
	float wd = gaussian(distance_x + 1.0, hard_pix);
	return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

vec3 horizontal5(vec2 position, float offset) {
	vec3 a = fetch_pixel(position, vec2(-2.0, offset));
	vec3 b = fetch_pixel(position, vec2(-1.0, offset));
	vec3 c = fetch_pixel(position, vec2(0.0, offset));
	vec3 d = fetch_pixel(position, vec2(1.0, offset));
	vec3 e = fetch_pixel(position, vec2(2.0, offset));
	float distance_x = distance_to_texel(position).x;
	float wa = gaussian(distance_x - 2.0, hard_pix);
	float wb = gaussian(distance_x - 1.0, hard_pix);
	float wc = gaussian(distance_x, hard_pix);
	float wd = gaussian(distance_x + 1.0, hard_pix);
	float we = gaussian(distance_x + 2.0, hard_pix);
	return (a * wa + b * wb + c * wc + d * wd + e * we) /
		(wa + wb + wc + wd + we);
}

vec3 horizontal7(vec2 position, float offset) {
	vec3 a = fetch_pixel(position, vec2(-3.0, offset));
	vec3 b = fetch_pixel(position, vec2(-2.0, offset));
	vec3 c = fetch_pixel(position, vec2(-1.0, offset));
	vec3 d = fetch_pixel(position, vec2(0.0, offset));
	vec3 e = fetch_pixel(position, vec2(1.0, offset));
	vec3 f = fetch_pixel(position, vec2(2.0, offset));
	vec3 g = fetch_pixel(position, vec2(3.0, offset));
	float distance_x = distance_to_texel(position).x;
	float wa = gaussian(distance_x - 3.0, hard_bloom_pix);
	float wb = gaussian(distance_x - 2.0, hard_bloom_pix);
	float wc = gaussian(distance_x - 1.0, hard_bloom_pix);
	float wd = gaussian(distance_x, hard_bloom_pix);
	float we = gaussian(distance_x + 1.0, hard_bloom_pix);
	float wf = gaussian(distance_x + 2.0, hard_bloom_pix);
	float wg = gaussian(distance_x + 3.0, hard_bloom_pix);
	return (a * wa + b * wb + c * wc + d * wd + e * we + f * wf + g * wg) /
		(wa + wb + wc + wd + we + wf + wg);
}

float scan(vec2 position, float offset) {
	return gaussian(distance_to_texel(position).y + offset, hard_scan);
}

float bloom_scan(vec2 position, float offset) {
	return gaussian(distance_to_texel(position).y + offset, hard_bloom_scan);
}

vec3 tri(vec2 position) {
	return horizontal3(position, -1.0) * scan(position, -1.0) +
		horizontal5(position, 0.0) * scan(position, 0.0) +
		horizontal3(position, 1.0) * scan(position, 1.0);
}

vec3 bloom(vec2 position) {
	return horizontal5(position, -2.0) * bloom_scan(position, -2.0) +
		horizontal7(position, -1.0) * bloom_scan(position, -1.0) +
		horizontal7(position, 0.0) * bloom_scan(position, 0.0) +
		horizontal7(position, 1.0) * bloom_scan(position, 1.0) +
		horizontal5(position, 2.0) * bloom_scan(position, 2.0);
}

vec3 mask(vec2 pixel_position) {
	vec3 result = vec3(mask_dark);
	if (shadow_mask == 1.0) {
		float line = mask_light;
		float odd = fract(pixel_position.x * 0.166666666) < 0.5 ? 1.0 : 0.0;
		if (fract((pixel_position.y + odd) * 0.5) < 0.5) line = mask_dark;
		float stripe = fract(pixel_position.x * 0.333333333);
		if (stripe < 0.333) result.r = mask_light;
		else if (stripe < 0.666) result.g = mask_light;
		else result.b = mask_light;
		result *= line;
	} else if (shadow_mask == 2.0 || shadow_mask == 3.0 || shadow_mask == 4.0) {
		vec2 position = pixel_position;
		if (shadow_mask == 3.0) position.x += position.y * 3.0;
		if (shadow_mask == 4.0) {
			position = floor(position * vec2(1.0, 0.5));
			position.x += position.y * 3.0;
		}
		float stripe = fract(position.x * (shadow_mask == 2.0 ? 0.333333333 : 0.166666666));
		if (stripe < 0.333) result.r = mask_light;
		else if (stripe < 0.666) result.g = mask_light;
		else result.b = mask_light;
	}
	return result;
}

void fragment() {
	if (UV.x < region_rect.x || UV.y < region_rect.y ||
		UV.x > region_rect.x + region_rect.z ||
		UV.y > region_rect.y + region_rect.w) {
		COLOR = texture(source_texture, UV);
	} else {

	vec2 local_uv = (UV - region_rect.xy) / region_rect.zw;
	// Curvature is disabled: the pinned shader's Warp function is identity.
	vec2 position = local_uv;
	vec3 result = tri(position) + bloom(position) * bloom_amount;
	if (mask_enabled) {
		result *= mask(local_uv * max(output_size, vec2(1.0)) * 1.000001);
	}
	vec2 alpha_uv = region_rect.xy + local_uv * region_rect.zw;
	float alpha = texture(source_texture, clamp_region_uv(alpha_uv)).a;
	COLOR = vec4(to_srgb(result), alpha);
	}
}
