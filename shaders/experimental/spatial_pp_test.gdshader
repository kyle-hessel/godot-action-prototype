shader_type spatial;

render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

uniform float z_near = 0.05;
uniform float z_far = 100.0;

varying mat4 CAMERA;

void vertex() {
	// maps onto player screen, still requires a plane as a child of the active scene camera.
	POSITION = vec4(UV*2.0-1.0, 0.0, 1.0);
	//CAMERA = INV_VIEW_MATRIX;
}

void fragment() {
	vec4 screen_col = texture(SCREEN_TEXTURE, SCREEN_UV);
	// depth value of objects in scene, stored in x.
	float screen_depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;
	
	// normalized device coordinates
	// remap from -1 to 1 for Godot.
	vec3 ndc = vec3(SCREEN_UV, screen_depth) * 2.0 - 1.0;
	
	// convert from NDC to view space to get distance from camera.
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	
	//vec4 world = CAMERA * INV_VIEW_MATRIX * vec4(ndc, 1.0);
	//vec3 world_pos = world.xyz / world.w;
	
	view.xyz /= view.w;
	
	// visualize depth by modifying its value.
	float linear_depth = view.z;
	float scaled_depth = (z_far * z_near) / (z_far + (linear_depth * (z_near - z_far)));
	
	scaled_depth = clamp(scaled_depth, 0, 1);
	
	// set viewport color equal to dynamic depth value.
	ALBEDO = vec3(scaled_depth);
}
