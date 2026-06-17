shader_type canvas_item;

// Recolors a sprite to look like polished iron: the figure's own shading is
// remapped onto a steel ramp (shadow -> mid -> highlight) with a vertical sheen
// so the top catches more "light". Tweak the colors/sheen in the Inspector.
uniform vec3 shadow_color : source_color = vec3(0.16, 0.18, 0.23);
uniform vec3 mid_color : source_color = vec3(0.48, 0.52, 0.60);
uniform vec3 highlight_color : source_color = vec3(0.92, 0.95, 1.0);
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex; // keep transparent background
	} else {
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		float sheen = 1.0 - UV.y; // brighter toward the top of the piece
		float t = clamp(lum * (1.0 - sheen_strength) + sheen * sheen_strength, 0.0, 1.0);
		vec3 metal = t < 0.5
			? mix(shadow_color, mid_color, t * 2.0)
			: mix(mid_color, highlight_color, (t - 0.5) * 2.0);
		COLOR = vec4(metal, tex.a);
	}
}
