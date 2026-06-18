shader_type canvas_item;

// Matte, grainy recolor for rough/stone-like materials — no directional sheen,
// plus per-pixel grain so it reads as rough rock instead of smooth metal.
uniform vec3 shadow_color : source_color = vec3(0.20, 0.20, 0.19);
uniform vec3 mid_color : source_color = vec3(0.42, 0.41, 0.39);
uniform vec3 highlight_color : source_color = vec3(0.60, 0.58, 0.55);
uniform float roughness : hint_range(0.0, 1.0) = 0.4;

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		// Matte: map the figure's own luminance straight onto the palette (no sheen).
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		vec3 col = lum < 0.5
			? mix(shadow_color, mid_color, lum * 2.0)
			: mix(mid_color, highlight_color, (lum - 0.5) * 2.0);
		// Per-pixel grain so it looks rough/pitted.
		float n = _hash(floor(UV / TEXTURE_PIXEL_SIZE)) - 0.5;
		col = clamp(col + n * roughness * 0.3, 0.0, 1.0);
		COLOR = vec4(col, tex.a);
	}
}
