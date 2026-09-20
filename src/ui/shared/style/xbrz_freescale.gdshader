/*
 * Adapted from libretro/glsl-shaders xbrz/shaders/xbrz-freescale.glsl
 * at commit f8e23ff880668f0f0e837a05a316534d82a7f31b.
 *
 * Hyllian's xBR-vertex code and texel mapping
 * Copyright (C) 2011/2016 Hyllian - sergiogdb@gmail.com
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * This shader also uses code and/or concepts from xBRZ as it appears
 * in the DeSmuME source code. The license for which is as follows:
 * ****************************************************************************
 * * This file is part of the HqMAME project. It is distributed under         *
 * * GNU General Public License: http://www.gnu.org/licenses/gpl-3.0          *
 * * Copyright (C) Zenju (zenju AT gmx DOT de) - All Rights Reserved          *
 * *                                                                          *
 * * Additionally and as a special exception, the author gives permission     *
 * * to link the code of this program with the MAME library (or with modified *
 * * versions of MAME that use the same license as MAME), and distribute      *
 * * linked combinations including the two. You must obey the GNU General     *
 * * Public License in all respects for all of the code used other than MAME. *
 * * If you modify this file, you may extend this exception to your version   *
 * * of the file, but you are not obligated to do so. If you do not wish to   *
 * * do so, delete this exception statement from your version.                *
 * ****************************************************************************
 */

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_texture : filter_nearest;

// The host supplies logical source and final output pixel dimensions.
uniform vec2 source_size = vec2(0.0);
uniform vec2 output_size = vec2(0.0);
// Normalized rectangle of the world viewport inside TEXTURE. UI outside this
// rectangle is never sampled or modified by the scaler.
uniform vec4 world_rect = vec4(0.0, 0.0, 1.0, 1.0);

const float EQUAL_COLOR_TOLERANCE = 30.0 / 255.0;
const float STEEP_DIRECTION_THRESHOLD = 2.2;
const float DOMINANT_DIRECTION_THRESHOLD = 3.6;

vec2 clamp_source_uv(vec2 uv, vec2 texel) {
	vec2 low = world_rect.xy + texel * 0.5;
	vec2 high = world_rect.xy + world_rect.zw - texel * 0.5;
	return clamp(uv, low, high);
}

vec4 source_pixel(vec2 offset, vec2 coord, vec2 texel) {
	return texture(source_texture, clamp_source_uv(coord + offset * texel, texel));
}

float color_distance(vec3 a, vec3 b) {
	const vec3 weight = vec3(0.2627, 0.6780, 0.0593);
	const float scale_b = 0.5 / (1.0 - weight.b);
	const float scale_r = 0.5 / (1.0 - weight.r);
	vec3 diff = a - b;
	float y = dot(diff, weight);
	float cb = scale_b * (diff.b - y);
	float cr = scale_r * (diff.r - y);
	return sqrt(y * y + cb * cb + cr * cr);
}

bool same_color(vec4 a, vec4 b) {
    return a.rgb == b.rgb;
}

bool pixels_equal(vec4 a, vec4 b) {
    return color_distance(a.rgb, b.rgb) < EQUAL_COLOR_TOLERANCE;
}

float left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale) {
	vec2 p0 = center - origin;
	vec2 projection = direction * (dot(p0, direction) / dot(direction, direction));
	vec2 distance_vector = p0 - projection;
	vec2 orthogonal = vec2(-direction.y, direction.x);
	float side = sign(dot(p0, orthogonal));
	float value = side * length(distance_vector * scale);
	return smoothstep(-sqrt(2.0) * 0.5, sqrt(2.0) * 0.5, value);
}

void fragment() {
	// The compositor may apply this material to the whole composed viewport.
	// Preserve UI and other pixels outside the selected world rectangle exactly.
	if (UV.x < world_rect.x || UV.y < world_rect.y ||
		UV.x > world_rect.x + world_rect.z || UV.y > world_rect.y + world_rect.w) {
		COLOR = texture(source_texture, UV);
	} else {
	vec2 source = source_size;
	vec2 output = output_size;
	vec2 texel = world_rect.zw / source;
	vec2 scale = output / source;
	vec2 local_uv = (UV - world_rect.xy) / world_rect.zw;
	vec2 position = fract(local_uv * source) - vec2(0.5);
	vec2 coord = UV - position * texel;

	vec4 A = source_pixel(vec2(-1.0, -1.0), coord, texel);
	vec4 B = source_pixel(vec2( 0.0, -1.0), coord, texel);
	vec4 C = source_pixel(vec2( 1.0, -1.0), coord, texel);
	vec4 D = source_pixel(vec2(-1.0,  0.0), coord, texel);
	vec4 center_px = source_pixel(vec2( 0.0,  0.0), coord, texel);
	vec4 F = source_pixel(vec2( 1.0,  0.0), coord, texel);
	vec4 G = source_pixel(vec2(-1.0,  1.0), coord, texel);
	vec4 H = source_pixel(vec2( 0.0,  1.0), coord, texel);
	vec4 I = source_pixel(vec2( 1.0,  1.0), coord, texel);

	// Edge tests follow xBRZ's four diagonal taps on the opaque composed source.
	// The source alpha follows the color interpolation at blended edges.
	vec4 result = center_px;
	ivec4 blend = ivec4(0);
	if (!((same_color(center_px, F) && same_color(H, I)) ||
		(same_color(center_px, H) && same_color(F, I)))) {
		float hf = color_distance(G.rgb, center_px.rgb) + color_distance(center_px.rgb, C.rgb) +
			color_distance(source_pixel(vec2(0.0, 2.0), coord, texel).rgb, I.rgb) +
			color_distance(I.rgb, source_pixel(vec2(2.0, 0.0), coord, texel).rgb) +
			4.0 * color_distance(H.rgb, F.rgb);
		float ei = color_distance(D.rgb, H.rgb) + color_distance(H.rgb, source_pixel(vec2(1.0, 2.0), coord, texel).rgb) +
			color_distance(B.rgb, F.rgb) + color_distance(F.rgb, source_pixel(vec2(2.0, 1.0), coord, texel).rgb) +
			4.0 * color_distance(center_px.rgb, I.rgb);
		blend.z = (hf < ei && !same_color(center_px, F) && !same_color(center_px, H))
			? ((DOMINANT_DIRECTION_THRESHOLD * hf < ei) ? 2 : 1) : 0;
	}
	if (!((same_color(D, center_px) && same_color(G, H)) ||
		(same_color(D, G) && same_color(center_px, H)))) {
		float ge = color_distance(source_pixel(vec2(-2.0, 1.0), coord, texel).rgb, D.rgb) + color_distance(D.rgb, B.rgb) +
			color_distance(source_pixel(vec2(-1.0, 2.0), coord, texel).rgb, H.rgb) + color_distance(H.rgb, F.rgb) + 4.0 * color_distance(G.rgb, center_px.rgb);
		float dh = color_distance(source_pixel(vec2(-2.0, 0.0), coord, texel).rgb, G.rgb) + color_distance(G.rgb, source_pixel(vec2(0.0, 2.0), coord, texel).rgb) +
			color_distance(A.rgb, center_px.rgb) + color_distance(center_px.rgb, I.rgb) + 4.0 * color_distance(D.rgb, H.rgb);
		blend.w = (ge > dh && !same_color(center_px, D) && !same_color(center_px, H))
			? ((DOMINANT_DIRECTION_THRESHOLD * dh < ge) ? 2 : 1) : 0;
	}
	if (!((same_color(B, C) && same_color(center_px, F)) ||
		(same_color(B, center_px) && same_color(C, F)))) {
		float ec = color_distance(D.rgb, B.rgb) + color_distance(B.rgb, source_pixel(vec2(1.0, -2.0), coord, texel).rgb) +
			color_distance(H.rgb, F.rgb) + color_distance(F.rgb, source_pixel(vec2(2.0, -1.0), coord, texel).rgb) + 4.0 * color_distance(center_px.rgb, C.rgb);
		float bf = color_distance(A.rgb, center_px.rgb) + color_distance(center_px.rgb, I.rgb) + color_distance(source_pixel(vec2(0.0, -2.0), coord, texel).rgb, C.rgb) +
			color_distance(C.rgb, source_pixel(vec2(2.0, 0.0), coord, texel).rgb) + 4.0 * color_distance(B.rgb, F.rgb);
		blend.y = (ec > bf && !same_color(center_px, B) && !same_color(center_px, F))
			? ((DOMINANT_DIRECTION_THRESHOLD * bf < ec) ? 2 : 1) : 0;
	}
	if (!((same_color(A, B) && same_color(D, center_px)) ||
		(same_color(A, D) && same_color(B, center_px)))) {
		float db = color_distance(source_pixel(vec2(-2.0, 0.0), coord, texel).rgb, A.rgb) + color_distance(A.rgb, source_pixel(vec2(0.0, -2.0), coord, texel).rgb) +
			color_distance(G.rgb, center_px.rgb) + color_distance(center_px.rgb, C.rgb) + 4.0 * color_distance(D.rgb, B.rgb);
		float ae = color_distance(source_pixel(vec2(-2.0, -1.0), coord, texel).rgb, D.rgb) + color_distance(D.rgb, H.rgb) +
			color_distance(source_pixel(vec2(-1.0, -2.0), coord, texel).rgb, B.rgb) + color_distance(B.rgb, F.rgb) + 4.0 * color_distance(A.rgb, center_px.rgb);
		blend.x = (db < ae && !same_color(center_px, D) && !same_color(center_px, B))
			? ((DOMINANT_DIRECTION_THRESHOLD * db < ae) ? 2 : 1) : 0;
	}

	// Four line blends. The result alpha follows the same interpolation as RGB.
	if (blend.z != 0) {
		float fg = color_distance(F.rgb, G.rgb);
		float hc = color_distance(H.rgb, C.rgb);
		bool line_blend = blend.z == 2 || !(
			(blend.y != 0 && !pixels_equal(center_px, G)) ||
			(blend.w != 0 && !pixels_equal(center_px, C)) ||
			(pixels_equal(G, H) && pixels_equal(H, I) && pixels_equal(I, F) && pixels_equal(F, C) && !pixels_equal(center_px, I)));
		vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
		vec2 direction = vec2(1.0, -1.0);
		if (line_blend) {
			bool shallow = STEEP_DIRECTION_THRESHOLD * fg <= hc && !same_color(center_px, G) && !same_color(D, G);
			bool steep = STEEP_DIRECTION_THRESHOLD * hc <= fg && !same_color(center_px, C) && !same_color(B, C);
			origin = shallow ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
			direction.x += shallow ? 1.0 : 0.0;
			direction.y -= steep ? 1.0 : 0.0;
		}
		vec4 line = mix(H, F, step(color_distance(center_px.rgb, F.rgb), color_distance(center_px.rgb, H.rgb)));
		result = mix(result, line, left_ratio(position, origin, direction, scale));
	}
	if (blend.w != 0) {
		float ha = color_distance(H.rgb, A.rgb);
		float di = color_distance(D.rgb, I.rgb);
		bool line_blend = blend.w == 2 || !(
			(blend.z != 0 && !pixels_equal(center_px, A)) ||
			(blend.x != 0 && !pixels_equal(center_px, I)) ||
			(pixels_equal(A, D) && pixels_equal(D, G) && pixels_equal(G, H) && pixels_equal(H, I) && !pixels_equal(center_px, G)));
		vec2 origin = vec2(-1.0 / sqrt(2.0), 0.0);
		vec2 direction = vec2(1.0, 1.0);
		if (line_blend) {
			bool shallow = STEEP_DIRECTION_THRESHOLD * ha <= di && !same_color(center_px, A) && !same_color(B, A);
			bool steep = STEEP_DIRECTION_THRESHOLD * di <= ha && !same_color(center_px, I) && !same_color(F, I);
			origin = shallow ? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
			direction.y += shallow ? 1.0 : 0.0;
			direction.x += steep ? 1.0 : 0.0;
		}
		vec4 line = mix(H, D, step(color_distance(center_px.rgb, D.rgb), color_distance(center_px.rgb, H.rgb)));
		result = mix(result, line, left_ratio(position, origin, direction, scale));
	}
	if (blend.y != 0) {
		float bi = color_distance(B.rgb, I.rgb);
		float fa = color_distance(F.rgb, A.rgb);
		bool line_blend = blend.y == 2 || !(
			(blend.x != 0 && !pixels_equal(center_px, I)) ||
			(blend.z != 0 && !pixels_equal(center_px, A)) ||
			(pixels_equal(I, F) && pixels_equal(F, C) && pixels_equal(C, B) && pixels_equal(B, A) && !pixels_equal(center_px, C)));
		vec2 origin = vec2(1.0 / sqrt(2.0), 0.0);
		vec2 direction = vec2(-1.0, -1.0);
		if (line_blend) {
			bool shallow = STEEP_DIRECTION_THRESHOLD * bi <= fa && !same_color(center_px, I) && !same_color(H, I);
			bool steep = STEEP_DIRECTION_THRESHOLD * fa <= bi && !same_color(center_px, A) && !same_color(D, A);
			origin = shallow ? vec2(0.25, 0.0) : vec2(0.5, 0.0);
			direction.y -= shallow ? 1.0 : 0.0;
			direction.x -= steep ? 1.0 : 0.0;
		}
		vec4 line = mix(F, B, step(color_distance(center_px.rgb, B.rgb), color_distance(center_px.rgb, F.rgb)));
		result = mix(result, line, left_ratio(position, origin, direction, scale));
	}
	if (blend.x != 0) {
		float dc = color_distance(D.rgb, C.rgb);
		float bg = color_distance(B.rgb, G.rgb);
		bool line_blend = blend.x == 2 || !(
			(blend.w != 0 && !pixels_equal(center_px, C)) ||
			(blend.y != 0 && !pixels_equal(center_px, G)) ||
			(pixels_equal(C, B) && pixels_equal(B, A) && pixels_equal(A, D) && pixels_equal(D, G) && !pixels_equal(center_px, A)));
		vec2 origin = vec2(0.0, -1.0 / sqrt(2.0));
		vec2 direction = vec2(-1.0, 1.0);
		if (line_blend) {
			bool shallow = STEEP_DIRECTION_THRESHOLD * dc <= bg && !same_color(center_px, C) && !same_color(F, C);
			bool steep = STEEP_DIRECTION_THRESHOLD * bg <= dc && !same_color(center_px, G) && !same_color(H, G);
			origin = shallow ? vec2(0.0, -0.25) : vec2(0.0, -0.5);
			direction.x -= shallow ? 1.0 : 0.0;
			direction.y += steep ? 1.0 : 0.0;
		}
		vec4 line = mix(D, B, step(color_distance(center_px.rgb, B.rgb), color_distance(center_px.rgb, D.rgb)));
		result = mix(result, line, left_ratio(position, origin, direction, scale));
	}
	COLOR = result;
	}
}
