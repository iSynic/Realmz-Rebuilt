shader_type canvas_item;
render_mode unshaded;

// Remake target plates preserve the Classic colored lettering, but their gray
// surface belongs to the old chrome. Keep saturated glyph pixels and reveal
// the native Rebuilt inset beneath every neutral source pixel.
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float highest = max(source.r, max(source.g, source.b));
	float lowest = min(source.r, min(source.g, source.b));
	float chroma = highest - lowest;
	float glyph_alpha = smoothstep(0.025, 0.10, chroma) * source.a;
	COLOR = vec4(source.rgb, glyph_alpha);
}
