shader_type spatial;

render_mode unshaded;

// modified version of gerardogc2378's Stars Shader: https://godotshaders.com/shader/stars-shader/

//#include "res://addons/ShaderFunction-Extras/Color/blend_modes.gdshaderinc"
//#include "res://addons/ShaderFunction-Extras/UV/uv.gdshaderinc"

uniform vec3 bg_color: source_color;

float rand (vec2 st) {
	return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	float size = 100.0;
	float prob = 0.9;
	vec2 pos = floor(1.0 / size * FRAGCOORD.xy);
	float color = 0.0;
	float star_value = rand(pos);
	
	// big stars
	if (star_value > prob)
	{
		vec2 center = size * pos + vec2(size, size) * 0.5;
		float t = 0.9 + 0.2 * sin(TIME * 8.0 + (star_value - prob) / (1.0 - prob) * 45.0);
		color = 1.0 - distance(FRAGCOORD.xy, center) / (0.5 * size);
		color = color * t / (abs(FRAGCOORD.y - center.y)) * t / (abs(FRAGCOORD.x - center.x));
	}
	// tiny stars
	else if (rand(SCREEN_UV.xy / 20.0) > 0.996)
	{
		float r = rand(SCREEN_UV.xy);
		color = r * (0.85 * sin(TIME * (r * 5.0) + 720.0 * r) + 0.95);
	}
	
	ALBEDO = vec3(color) + bg_color;
}


