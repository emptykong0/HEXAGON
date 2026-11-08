shader_type canvas_item;
render_mode unshaded;

uniform float match_mist : hint_range(0.0, 1.0) = 0.0;
uniform float dusk : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 ice = COLOR.rgb;
	vec3 daylight = mix(ice, vec3(0.63, 0.74, 0.82), 0.42 * match_mist);
	// Translucent ice catches the last light after the mountain shadows deepen.
	vec3 twilight = vec3(0.035, 0.075, 0.14) + ice * ice * vec3(0.34, 0.49, 0.57);
	COLOR.rgb = mix(daylight, twilight, dusk);
}
