shader_type spatial;

render_mode diffuse_toon, specular_toon;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture;

uniform float brightness : hint_range(0.0, 20.0) = 2.0;
uniform float contrast_multiplier : hint_range(0.1, 1.0) = 0.8;
uniform float l_thresh_multiplier : hint_range(0.1, 1.0) = 0.5;
uniform float lightshadow_transition : hint_range(0.0, 1.0) = 0.1;
uniform float max_distance : hint_range(50.0, 200000.0) = 4000.0;
uniform vec4 shadow_tint : source_color;
uniform vec4 light_tint : source_color;


void vertex()
{
	// Set shader position to fill screen.
	POSITION = vec4(UV*2.0-1.0, 0.0, 1.0);
}

void fragment() 
{
	vec4 screen_col = texture(SCREEN_TEXTURE, SCREEN_UV);
	float screen_depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;
	
	// get usable screen-depth
	// see: https://docs.godotengine.org/en/latest/tutorials/shaders/advanced_postprocessing.html#depth-texture
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, screen_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  	view.xyz /= view.w;
  	float linear_depth = -view.z;
	
	// desaturate
	float screen_avg = screen_col.r + screen_col.g + screen_col.b / 3.0;
	
	// create flat lighting by stepping it.
	//vec3 light_threshold = step(l_thresh_multiplier, screen_col.rgb);
	//float light_threshold_desat = step(l_thresh_multiplier, screen_avg);
	
	// create flatter lighting by smooth stepping it within a small range, and step it everywhere else.
	float thresh_upper = l_thresh_multiplier + lightshadow_transition * 0.5;
	float thresh_lower = l_thresh_multiplier - lightshadow_transition * 0.5;
	float light_threshold_desat = smoothstep(thresh_lower, thresh_upper, screen_avg) * contrast_multiplier;
	//float inverted_result = 1.0 - (light_threshold_desat * contrast_multiplier);
	vec4 light_lerp = mix(shadow_tint, light_tint, light_threshold_desat);
	
	// brightness adjustment
	vec3 brightness_val = mix(vec3(0.0), screen_col.rgb, brightness);
	vec3 color_brightness = brightness_val * light_lerp.rgb;
	
	// depth check (stops sky from being included, or more)
	float depth_value = step(max_distance, linear_depth);
	vec3 final_color = mix(color_brightness, screen_col.rgb, depth_value);
	
	ALBEDO = final_color;
	EMISSION = final_color;
	
	//ALBEDO = screen_col.rgb * contrast_multiplier;
	//EMISSION = screen_col.rgb * contrast_multiplier;
}