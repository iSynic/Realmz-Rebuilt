shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 3.0;
uniform vec4 veil : source_color = vec4(0.043, 0.082, 0.133, 0.84);

void fragment() {
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	COLOR = vec4(mix(blurred, veil.rgb, veil.a), 1.0);
}
