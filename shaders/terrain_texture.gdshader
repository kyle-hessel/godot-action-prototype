shader_type spatial;

uniform sampler2D terrain_low;
uniform sampler2D terrain_high;
uniform float min_low_height = -0.30;
uniform float max_high_height = 1.6;
varying float vertex_y;
uniform vec2 uv_scale = vec2(5);

void fragment() {
	float vert_weight = vertex_y;
	
	vec3 terrain_one = texture(terrain_low, UV * uv_scale).rgb;
	vec3 terrain_two = texture(terrain_high, UV * uv_scale).rgb;
	
	float weight = smoothstep(min_low_height, max_high_height, vert_weight);
	vec3 final_color = mix(terrain_one, terrain_two, weight);
	
	ALBEDO = final_color.rgb;
}

void vertex() {
	vertex_y = VERTEX.y;
}
