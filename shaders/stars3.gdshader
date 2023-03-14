shader_type spatial;

render_mode unshaded;

#include "res://addons/ShaderFunction-Extras/UV/uv.gdshaderinc"

uniform float star_size_inverse = 2.0;
uniform float starlight_falloff = 2.5;

mat2 rot(float a) {
	float s = sin(a), c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

void fragment() {
	vec3 col = vec3(0);
	
	// make a star
	vec2 uv = ((SCREEN_UV - .5) / SCREEN_UV * star_size_inverse) * starlight_falloff;
	uv.x *= 2.5;
	
	float dist = length(uv);
	
	float m = .02 / dist;
	col += m;
	
	float rays = max(0, 1. - abs(uv.x * uv.y * 500.));
	col += rays;
	
	//uv *= rot(PI / 4.);
	uv = uv_rotate(uv, SCREEN_UV - .5, PI / 4.);
	
	rays = max(0, 1. - abs(uv.x * uv.y * 500.));
	col += rays * .3;
	
	ALBEDO = col;
	//ALPHA = 0.8;
}
