/*
    crt-pi - A Raspberry Pi friendly CRT shader.

    Adapted from libretro/glsl-shaders crt/shaders/crt-pi.glsl at commit
    f8e23ff880668f0f0e837a05a316534d82a7f31b.

    Copyright (C) 2015-2016 davej

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation; either version 2 of the License, or (at your
    option) any later version.

    This Godot 4 CanvasItem port keeps the source gamma, bloom, and mask
    calculations, with output-pixel scanlines. Curvature is intentionally
    omitted for the Rebuilt composed-surface contract.
*/

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_texture : filter_nearest;
uniform vec2 source_size = vec2(1.0);
uniform vec2 output_size = vec2(1.0);
uniform vec4 region_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float mask_strength : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 1.0;
uniform float filter_strength : hint_range(0.0, 1.0) = 1.0;

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

// Explicit bilinear sampling keeps viewport textures consistent on Mobile and GL.
vec4 source_at(vec2 uv, vec2 texel) {
	ivec2 dimensions = textureSize(source_texture, 0);
	vec2 pixel = clamp_region_uv(uv, texel) * vec2(dimensions) - vec2(0.5);
	ivec2 low = ivec2(floor(pixel));
	ivec2 high = min(low + ivec2(1), dimensions - ivec2(1));
	vec2 blend = fract(pixel);
	vec4 top = mix(texelFetch(source_texture, low, 0),
		texelFetch(source_texture, ivec2(high.x, low.y), 0), blend.x);
	vec4 bottom = mix(texelFetch(source_texture, ivec2(low.x, high.y), 0),
		texelFetch(source_texture, high, 0), blend.x);
	return mix(top, bottom, blend.y);
}

float physical_scanline(float output_y) {
	// Two lit rows and one dim row per physical triplet; their mean is one.
	return mod(floor(output_y), 3.0) < 2.0 ? 1.10 : 0.80;
}

void fragment() {
	if (UV.x < region_rect.x || UV.y < region_rect.y ||
		UV.x > region_rect.x + region_rect.z ||
		UV.y > region_rect.y + region_rect.w) {
		ivec2 dimensions = textureSize(source_texture, 0);
		ivec2 pixel = clamp(ivec2(floor(UV * vec2(dimensions))), ivec2(0), dimensions - ivec2(1));
		COLOR = texelFetch(source_texture, pixel, 0);
	} else {

	vec2 logical_source = safe_source_size();
	vec2 texel = region_rect.zw / logical_source;
	vec4 direct = texture(source_texture, clamp_region_uv(UV, texel));
	vec3 colour = direct.rgb;
	float alpha = direct.a;
	if (filter_strength > 0.0) {
		vec2 local_uv = (UV - region_rect.xy) / region_rect.zw;
		vec2 source_position = local_uv * logical_source;
		float source_y = floor(source_position.y) + 0.5;
		float delta_y = source_position.y - source_y;
		// Average one source-line period rather than aliasing its contrast.
		float mean_weight = SCANLINE_GAP_BRIGHTNESS + (4.0 / 3.0) *
			(1.0 - SCANLINE_GAP_BRIGHTNESS) *
			sqrt((1.0 - SCANLINE_GAP_BRIGHTNESS) / SCANLINE_WEIGHT);
		// The source's non-SHARPER path filters horizontally and snaps Y.
		float dy = delta_y * delta_y;
		dy *= dy * 8.0;
		dy /= logical_source.y;
		dy *= sign(delta_y);
		vec2 sample_uv = region_rect.xy + vec2(local_uv.x,
			(source_y / logical_source.y) + dy) * region_rect.zw;
		vec4 sampled = source_at(sample_uv, texel);
		vec3 beam = pow(max(sampled.rgb, vec3(0.0)), vec3(INPUT_GAMMA));
		beam *= mean_weight * BLOOM_FACTOR;
		colour = mix(colour, pow(max(beam, vec3(0.0)), vec3(1.0 / OUTPUT_GAMMA)), filter_strength);
		alpha = mix(alpha, sampled.a, filter_strength);
	}
	colour *= mix(1.0, physical_scanline(FRAGCOORD.y), scanline_strength);

	// MASK_TYPE 1 from the pinned source: alternating green/magenta cells.
	float which_mask = fract(FRAGCOORD.x * 0.5);
	vec3 pattern = which_mask < 0.5
		? vec3(0.70, 1.0, 0.70)
		: vec3(1.0, 0.70, 1.0);
	vec3 mask = mix(vec3(1.0), pattern, clamp(mask_strength, 0.0, 1.0));
	COLOR = vec4(colour * mask, alpha);
	}
}
