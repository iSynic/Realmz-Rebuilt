/*
    crt-pi - A Raspberry Pi friendly CRT shader.

    Adapted from libretro/glsl-shaders crt/shaders/crt-pi.glsl at commit
    f8e23ff880668f0f0e837a05a316534d82a7f31b.

    Copyright (C) 2015-2016 davej

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation; either version 2 of the License, or (at your
    option) any later version.

    This Godot 4 CanvasItem port keeps the source scanline, gamma, bloom, and
    mask calculations. Curvature is intentionally omitted for the Rebuilt
    composed-surface contract.
*/

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_texture : filter_linear;
uniform sampler2D passthrough_texture : filter_nearest;
uniform vec2 source_size = vec2(1.0);
uniform vec2 output_size = vec2(1.0);
uniform vec4 region_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float mask_strength : hint_range(0.0, 1.0) = 1.0;

const float SCANLINE_WEIGHT = 6.0;
const float SCANLINE_GAP_BRIGHTNESS = 0.12;
const float BLOOM_FACTOR = 1.5;
const float INPUT_GAMMA = 2.4;
const float OUTPUT_GAMMA = 2.2;

vec2 safe_source_size() {
	return max(source_size, vec2(1.0));
}

vec2 clamp_region_uv(vec2 uv, vec2 texel) {
	vec2 low = region_rect.xy + texel * 0.5;
	vec2 high = region_rect.xy + region_rect.zw - texel * 0.5;
	return clamp(uv, low, high);
}

vec4 source_at(vec2 uv, vec2 texel) {
	return texture(source_texture, clamp_region_uv(uv, texel));
}

float scanline_weight(float distance_px) {
	return max(1.0 - distance_px * distance_px * SCANLINE_WEIGHT,
		SCANLINE_GAP_BRIGHTNESS);
}

float scanline(float distance_px, float filter_width) {
	float weight = scanline_weight(distance_px);
	weight += scanline_weight(distance_px - filter_width);
	weight += scanline_weight(distance_px + filter_width);
	return weight * 0.3333333;
}

void fragment() {
	if (UV.x < region_rect.x || UV.y < region_rect.y ||
		UV.x > region_rect.x + region_rect.z ||
		UV.y > region_rect.y + region_rect.w) {
		COLOR = texture(passthrough_texture, UV);
	} else {

	vec2 logical_source = safe_source_size();
	vec2 logical_output = max(output_size, vec2(1.0));
	vec2 texel = region_rect.zw / logical_source;
	vec2 local_uv = (UV - region_rect.xy) / region_rect.zw;
	vec2 source_position = local_uv * logical_source;
	float source_y = floor(source_position.y) + 0.5;
	float delta_y = source_position.y - source_y;
	float filter_width = (logical_source.y / logical_output.y) / 3.0;
	float line_weight = scanline(delta_y, filter_width) * BLOOM_FACTOR;

	// The original's non-SHARPER path preserves horizontal filtering while
	// snapping only the scanline coordinate. The region clamp prevents atlas
	// or composed-surface neighbors from entering the sample.
	float dy = delta_y * delta_y;
	dy *= dy * 8.0;
	dy /= logical_source.y;
	dy *= sign(delta_y);
	vec2 sample_uv = region_rect.xy + vec2(local_uv.x,
		(source_y / logical_source.y) + dy) * region_rect.zw;
	vec4 sampled = source_at(sample_uv, texel);

	vec3 colour = pow(max(sampled.rgb, vec3(0.0)), vec3(INPUT_GAMMA));
	colour *= line_weight;
	colour = pow(max(colour, vec3(0.0)), vec3(1.0 / OUTPUT_GAMMA));

	// MASK_TYPE 1 from the pinned source: alternating green/magenta cells.
	float which_mask = fract(local_uv.x * logical_output.x * 0.5);
	vec3 pattern = which_mask < 0.5
		? vec3(0.70, 1.0, 0.70)
		: vec3(1.0, 0.70, 1.0);
	vec3 mask = mix(vec3(1.0), pattern, clamp(mask_strength, 0.0, 1.0));
	COLOR = vec4(colour * mask, sampled.a);
	}
}
