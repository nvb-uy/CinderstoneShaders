#if !defined INCLUDE_LIGHT_COLORS_NETHER_COLOR
#define INCLUDE_LIGHT_COLORS_NETHER_COLOR

#include "/include/utility/color.glsl"

vec3 get_light_color() {
	return vec3(0.0);
}

vec3 get_ambient_color() {
#ifdef NETHER_USE_BIOME_COLOR
	vec3 nether_color  = srgb_eotf_inv(fogColor) * rec709_to_rec2020;
	     nether_color /= max(dot(nether_color, luminance_weights_rec2020), eps);
	     nether_color  = mix(vec3(1.0), nether_color, NETHER_S);
	     nether_color *= 0.05 * NETHER_I;
#else
	vec3 nether_color  = from_srgb(vec3(NETHER_R, NETHER_G, NETHER_B)) * 0.1 * NETHER_I;
#endif

#ifdef WORLD_VAAZ_WARM_AMBIENCE
	const vec3 vaaz_warm_tint = from_srgb(vec3(1.0, 0.78, 0.60));
	float ambient_luminance = max(dot(nether_color, luminance_weights_rec2020), eps);
	vec3 warm_ambient = ambient_luminance * vaaz_warm_tint / max(dot(vaaz_warm_tint, luminance_weights_rec2020), eps);

	nether_color = mix(nether_color, warm_ambient, 0.75);
	nether_color *= 1.25;
#endif

	return nether_color;
}

#endif // INCLUDE_LIGHT_COLORS_NETHER_COLOR
