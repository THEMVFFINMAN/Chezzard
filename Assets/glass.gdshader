shader_type canvas_item;

// Translucent glass: tints the figure, makes it semi-transparent, and adds a
// bright top rim so it reads as fragile/see-through.
uniform vec3 glass_tint : source_color = vec3(0.60, 0.80, 0.95);
uniform vec3 rim_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float transparency : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = tex;
	} else {
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		vec3 col = mix(glass_tint * 0.5, glass_tint, lum);
		col = mix(col, rim_color, pow(1.0 - UV.y, 3.0) * 0.6); // top sheen
		COLOR = vec4(col, tex.a * transparency);
	}
}
