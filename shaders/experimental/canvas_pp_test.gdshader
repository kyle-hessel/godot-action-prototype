shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

//uniform float offset = 1.0;

uniform float hue : hint_range(0.0, 6.283185) = 0.0;
uniform float saturation : hint_range(0.0, 4.0) = 1.0;
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float contrast : hint_range(0.0, 4.0) = 1.0;

void fragment() 
{
	//*** B&W
	//vec4 bg = texture(SCREEN_TEXTURE, SCREEN_UV);
	//float avg = bg.r + bg.g + bg.b / 3.0;
	//COLOR.rgb = vec3(avg, avg, avg);
	
	//*** Chromatic Abberation
	//vec4 g_channel = texture(SCREEN_TEXTURE, SCREEN_UV);
	//vec4 r_channel = texture(SCREEN_TEXTURE, vec2(SCREEN_UV.x + (offset * SCREEN_PIXEL_SIZE.x), SCREEN_UV.y));
	//vec4 b_channel = texture(SCREEN_TEXTURE, vec2(SCREEN_UV.x - (offset * SCREEN_PIXEL_SIZE.x), SCREEN_UV.y));
	//COLOR = vec4(r_channel.r, g_channel.g, b_channel.b, 1.0);
	
	//*** hue/saturation/brightness/contrast
	
	
	// fetching rgb
	COLOR = texture(SCREEN_TEXTURE, UV);
	vec3 color = COLOR.rgb;
	//RGB to YIQ
	mat3 RGB_to_YIQ = mat3(
		vec3(0.2989, 0.5959, 0.2115), 
		vec3(0.5870, -0.2774, -0.5229), 
		vec3(0.1140, -0.3216, 0.3114)
	);
	color *= RGB_to_YIQ; // account for YIQ in our color vector
	
	// hue shift
	float sin_hue = sin(hue);
	float cos_hue = cos(hue);
	mat3 hue_shift = mat3(
		vec3(1.0 , 0, 0),			// Y
		vec3(0, cos_hue, -sin_hue),	// I
		vec3(0, sin_hue, cos_hue)	// Q
	);
	
	color *= hue_shift; // apply hue shift
	
	// saturation shift
	mat3 sat_shift = mat3(
		vec3(1.0, 0, 0),
		vec3(0, saturation, 0),
		vec3(0, 0, saturation)
	);
	
	color *= sat_shift; // apply saturation shift
	
	// YIQ back to RGB
	color = inverse(RGB_to_YIQ) * color;
	
	// brightness
	color = mix(vec3(0.0), color.rgb, brightness);
	
	// contrast
	color = mix(vec3(0.5), color.rgb, contrast);
	
	// applying color to fragment output
	COLOR = vec4(color, 1.0);
}
