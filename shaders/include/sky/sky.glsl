#if !defined INCLUDE_SKY_SKY
#define INCLUDE_SKY_SKY

#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

uniform float lightpollution;

#if defined WORLD_OVERWORLD
uniform float eye_blocklight;

float combine_sky_pollution(float a, float b) {
	return a + b - a * b;
}

float get_moon_phase_sky_pollution() {
	float moon_pollution = linear_step(0.5, 0.8, lightpollution);
	return clamp01(moon_pollution * OVERWORLD_MOON_PHASE_POLLUTION);
}

float get_blocklight_sky_pollution() {
	float blocklight_pollution = smoothstep(
		OVERWORLD_BLOCKLIGHT_POLLUTION_START,
		1.0,
		clamp01(eye_blocklight)
	);
	return clamp01(blocklight_pollution * OVERWORLD_BLOCKLIGHT_POLLUTION);
}

float get_overworld_sky_pollution() {
	float moon_pollution = get_moon_phase_sky_pollution();
	float blocklight_pollution = get_blocklight_sky_pollution();
	return combine_sky_pollution(moon_pollution, blocklight_pollution);
}

float get_overworld_sky_visibility(float pollution_strength) {
	return clamp01(1.0 - pollution_strength * get_overworld_sky_pollution());
}

float get_overworld_star_visibility() {
	const float polluted_star_floor = 0.06;
	return mix(polluted_star_floor, 1.0, get_overworld_sky_visibility(OVERWORLD_STARS_POLLUTION));
}

float get_overworld_star_day_visibility() {
	float twilight_visibility = 1.0 - smoothstep(-0.16, 0.06, sun_dir.y);
	float daylight_visibility = 1.0 - smoothstep(0.0, 0.85, clamp01(time_sunrise + time_noon));
	return clamp01(twilight_visibility * daylight_visibility);
}
#endif

// Stars based on https://www.shadertoy.com/view/Md2SR3

vec3 unstable_star_field(vec2 coord, float star_threshold) {
	const float min_temp = 3500.0;
	const float max_temp = 9500.0;

	vec4 noise = hash4(coord);

	float star = linear_step(star_threshold, 1.0, noise.x);
	      star = pow4(star) * STARS_INTENSITY;

	float temp = mix(min_temp, max_temp, noise.y);
	vec3 color = blackbody(temp);

	const float twinkle_speed = 6.0;
	float twinkle_amount = noise.z;
	float twinkle_offset = tau * noise.w;
	star *= 1.0 - twinkle_amount * cos(frameTimeCounter * twinkle_speed + twinkle_offset);

	vec3 tint = vec3(0.4, 0.45, 0.55);
    return star * color * tint;
}

// Stabilizes the star field by sampling at the four neighboring integer coordinates and
// interpolating
vec3 stable_star_field(vec2 coord, float star_threshold) {
	coord = abs(coord) + 33.3 * step(0.0, coord);
	vec2 i, f = modf(coord, i);

	f.x = cubic_smooth(f.x);
	f.y = cubic_smooth(f.y);

	return unstable_star_field(i + vec2(0.0, 0.0), star_threshold) * (1.0 - f.x) * (1.0 - f.y)
	     + unstable_star_field(i + vec2(1.0, 0.0), star_threshold) * f.x * (1.0 - f.y)
	     + unstable_star_field(i + vec2(0.0, 1.0), star_threshold) * f.y * (1.0 - f.x)
	     + unstable_star_field(i + vec2(1.0, 1.0), star_threshold) * f.x * f.y;
}

vec3 pixelated_star_field(vec2 coord, float star_threshold, float pixel_size) {
	coord = abs(coord) + 33.3 * step(0.0, coord);

	float cell_size = max(pixel_size, 1.0);
	vec2 cell = floor(coord / cell_size) * cell_size + 0.5 * cell_size;

	return unstable_star_field(cell, star_threshold);
}

uniform sampler2D colortex14;

vec3 draw_stars(vec3 ray_dir, float galaxy_luminance) {
	// Adjust star threshold so that brightest stars appear first
#if defined WORLD_OVERWORLD
	float sky_pollution = get_overworld_sky_pollution();
	float star_threshold = 1.0 - 0.008 * STARS_COVERAGE * smoothstep(-0.2, 0.05, -sun_dir.y) - 0.5 * cube(galaxy_luminance);
	      star_threshold += 0.008 * OVERWORLD_STARS_POLLUTION * sky_pollution;
	// Keep the threshold below 1.0 so linear_step() stays stable and max pollution still leaves a few stars.
	      star_threshold = clamp(star_threshold, 0.0, 0.995);
#else
	float star_threshold = 1.0 - 0.008 * STARS_COVERAGE;
#endif

	// Project ray direction onto the plane
	vec2 coord  = ray_dir.xy * rcp(abs(ray_dir.z) + length(ray_dir.xy)) + 41.21 * sign(ray_dir.z);
	     coord *= 600.0;

	vec3 stars = pixelated_star_field(coord, star_threshold, STAR_PIXEL_SIZE);

#if defined WORLD_OVERWORLD
	// Let pollution control density, but use a dedicated fade so stars fully vanish through sunrise/day.
	stars *= get_overworld_star_visibility() * get_overworld_star_day_visibility();
#endif

	return stars;
}

vec3 draw_galaxy(vec3 ray_dir, out float galaxy_luminance) {
    const vec3 galaxy_tint = vec3(0.5, 0.5, 0.7) * GALAXY_INTENSITY;

    float galaxy_intensity = 0.6 * linear_step(-0.1, 0.25, -sun_dir.y);

#if defined WORLD_OVERWORLD
    galaxy_intensity *= get_overworld_sky_visibility(OVERWORLD_GALAXY_POLLUTION);
#endif

    float lon_rotation = radians(30.0); // Base rotation of the sky

    float lon = atan(ray_dir.x, ray_dir.z) + lon_rotation;

	float lat = mix(fast_acos(-ray_dir.y), pi - fast_acos(-ray_dir.y), HEMISPHERE);

    vec3 galaxy = texture(
        colortex14,
        vec2(lon * rcp(tau) + 0.5, lat * rcp(pi))
    ).rgb;

    galaxy = srgb_eotf_inv(galaxy) * rec709_to_working_color;

    galaxy *= galaxy_intensity * galaxy_tint;

    galaxy_luminance = dot(galaxy, luminance_weights_rec709);

    galaxy = mix(
        vec3(galaxy_luminance),
        galaxy,
        1.2
    );

    return max0(galaxy);
}

//----------------------------------------------------------------------------//
#if   defined WORLD_OVERWORLD

#include "/include/light/colors/light_color.glsl"
#include "/include/light/colors/weather_color.glsl"
#include "/include/light/bsdf.glsl"
#include "/include/sky/atmosphere.glsl"
#include "/include/sky/projection.glsl"
#include "/include/utility/geometry.glsl"

const float sun_luminance  = 40.0; // luminance of sun disk
const float moon_luminance = 4.0; // luminance of moon disk

vec3 draw_sun(vec3 ray_dir) {
	float nu = dot(ray_dir, sun_dir);

	// Limb darkening model from http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
	const vec3 alpha = vec3(0.429, 0.522, 0.614);
	float center_to_edge = max0(sun_angular_radius - fast_acos(nu));
	vec3 limb_darkening = pow(vec3(1.0 - sqr(1.0 - center_to_edge)), 0.5 * alpha);

	return sun_luminance * sun_color * step(0.0, center_to_edge) * limb_darkening;
}

vec4 get_clouds_and_aurora(vec3 ray_dir, vec3 clear_sky) {
#if   defined PROGRAM_DEFERRED0
	ivec2 texel   = ivec2(gl_FragCoord.xy);
	      texel.x = texel.x % (sky_map_res.x - 4);

	float dither = interleaved_gradient_noise(vec2(texel));

	// Render clouds
	#ifndef BLOCKY_CLOUDS
	const vec3 air_viewer_pos = vec3(0.0, planet_radius, 0.0);
	CloudsResult result = draw_clouds(air_viewer_pos, ray_dir, clear_sky, -1.0, dither);
	#else
	CloudsResult result = clouds_not_hit;
	#endif

	// Render aurora
	vec3 aurora = draw_aurora(ray_dir, dither);

	return vec4(
		result.scattering + aurora * result.transmittance,
		result.transmittance
	);
#else
	return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

vec3 draw_sky(vec3 ray_dir, vec3 atmosphere) {
	vec3 sky = vec3(0.0);

#if defined SHADOW
	// Trick to make stars rotate with sun and moon
	mat3 rot = (sunAngle < 0.5)
		? mat3(shadowModelViewInverse)
		: mat3(-shadowModelViewInverse[0].xyz, shadowModelViewInverse[1].xyz, -shadowModelViewInverse[2].xyz);

	vec3 celestial_dir = ray_dir * rot;
#endif

	// Galaxy
#ifdef GALAXY
	float galaxy_luminance;
	sky += draw_galaxy(celestial_dir, galaxy_luminance);
#else
	const float galaxy_luminance = 0.0;
#endif

	// Sun, moon and stars

#if defined PROGRAM_DEFERRED4
	vec4 vanilla_sky = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0);
	vec3 vanilla_sky_color = from_srgb(vanilla_sky.rgb);
	uint vanilla_sky_id = uint(255.0 * vanilla_sky.a);

#ifdef STARS
	sky += draw_stars(celestial_dir, galaxy_luminance);
#endif

#ifdef VANILLA_SUN
	if (vanilla_sky_id == 2) {
		const vec3 brightness_scale = sunlight_color * sun_luminance;
		sky += vanilla_sky_color * brightness_scale * sun_color;
	}
#else
	sky += draw_sun(ray_dir);
#endif

	if (moonPhase != 4 && vanilla_sky_id == 3 && max_of(vanilla_sky_color) > 0.1) {
		const vec3 brightness_scale = sunlight_color * moon_luminance;
		sky *= 0.0; // Hide stars behind moon
		sky += vanilla_sky_color * brightness_scale;
	}

#ifdef CUSTOM_SKY
	if (vanilla_sky_id == 4) {
		sky += vanilla_sky_color * CUSTOM_SKY_BRIGHTNESS;
	}
#endif
#endif

	// Sky gradient

	sky *= atmosphere_transmittance(ray_dir.y, planet_radius) * (1.0 - rainStrength);
	sky += atmosphere;

	// Rain
	vec3 rain_sky = get_weather_color() * (1.0 - exp2(-0.8 / clamp01(ray_dir.y)));
	sky = mix(sky, rain_sky, rainStrength * mix(1.0, 0.9, time_sunrise + time_sunset));

	// Clouds

	vec4 clouds = get_clouds_and_aurora(ray_dir, sky);
	sky *= clouds.a;   // transmittance
	sky += clouds.rgb; // scattering

	// Fade lower part of sky into cave fog color when underground so that the sky isn't visible
	// beyond the render distance
	float underground_sky_fade = biome_cave * smoothstep(-0.1, 0.1, 0.4 - ray_dir.y);
	sky = mix(sky, vec3(0.0), underground_sky_fade);

	return sky;
}

vec3 draw_sky(vec3 ray_dir) {
	vec3 atmosphere = atmosphere_scattering(ray_dir, sun_color, sun_dir, moon_color, moon_dir);
	return draw_sky(ray_dir, atmosphere);
}

//----------------------------------------------------------------------------//
#elif defined WORLD_NETHER

vec3 draw_sky(vec3 ray_dir) {
	return ambient_color;
}

//----------------------------------------------------------------------------//
#elif defined WORLD_END

#include "/include/misc/end_lighting_fix.glsl"
#include "/include/sky/atmosphere.glsl"

const float sun_solid_angle = cone_angle_to_solid_angle(sun_angular_radius);
const vec3 end_sun_color = vec3(0.80, 0.1, 0.4);

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 pixelate_end_black_hole_coord(vec2 coord, float grid_scale) {
	const float sprite_extent = 3.0;
	float grid = max(END_BLACK_HOLE_PIXEL_GRID * grid_scale, 1.0);

	vec2 sprite_uv = coord / (2.0 * sprite_extent) + 0.5;
	     sprite_uv = (floor(sprite_uv * grid) + 0.5) / grid;

	return (sprite_uv - 0.5) * (2.0 * sprite_extent);
}

vec2 get_end_black_hole_plane(vec3 ray_dir, vec3 tangent, vec3 bitangent, float scale, float grid_scale) {
	vec2 plane = vec2(dot(ray_dir, tangent), dot(ray_dir, bitangent)) * rcp(max(scale, eps));
	return pixelate_end_black_hole_coord(plane * rcp(max(sun_angular_radius, eps)), grid_scale) * sun_angular_radius;
}

vec3 end_black_hole_plane_to_ray_dir(vec2 plane, vec3 tangent, vec3 bitangent) {
	return normalize(sun_dir + plane.x * tangent + plane.y * bitangent);
}

vec3 getCosmicGlow(vec3 ray_dir, int iterations) {
    vec3 totalGlow = vec3(0.0);

    for (int i = 0; i < iterations; i++) {
        vec3 randomPosition = vec3(rand(vec2(i, i)), rand(vec2(i + 1, i + 1)), rand(vec2(i + 2, i + 2)));
        vec3 cosmicColor = vec3(rand(vec2(i + 3, i + 3)), rand(vec2(i + 4, i + 4)), rand(vec2(i + 5, i + 5))) * 0.15;

        float glowRadius = 1.5;
        float distanceToGlow = length(ray_dir - randomPosition);
        float glow = smoothstep(glowRadius, 0.0, distanceToGlow);
        totalGlow += cosmicColor * glow / 8 * END_COSMIC_GLOW_INTENSITY;
    }

    return totalGlow;
}

vec3 draw_sun(vec3 ray_dir) {
	vec3 cosmic_glow = vec3(0.0);
	#ifdef END_COSMIC_GLOW
	cosmic_glow = getCosmicGlow(ray_dir, 5);
	#endif

	if (dot(ray_dir, sun_dir) <= 0.0) return cosmic_glow;

	vec3 tangent = sun_dir.y == 1.0 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), sun_dir));
	vec3 bitangent = normalize(cross(tangent, sun_dir));

	vec2 black_hole_plane = get_end_black_hole_plane(ray_dir, tangent, bitangent, END_BLACK_HOLE_SCALE, 1.0);
	vec2 flare_plane      = get_end_black_hole_plane(ray_dir, tangent, bitangent, END_BLACK_HOLE_FLARE_SCALE, END_BLACK_HOLE_FLARE_PIXEL_GRID_SCALE);

	vec3 black_hole_ray_dir = end_black_hole_plane_to_ray_dir(black_hole_plane, tangent, bitangent);
	vec3 flare_ray_dir      = end_black_hole_plane_to_ray_dir(flare_plane, tangent, bitangent);

	float r_hole  = fast_acos(dot(black_hole_ray_dir, sun_dir));
	float r_flare = fast_acos(dot(flare_ray_dir, sun_dir));

	flare_ray_dir.z *= -0.1; flare_ray_dir.x *= -1.52;

	flare_ray_dir *= mat3(
        cos(radians(-90.0)), -sin(radians(90.0)), 1.0,
        sin(radians(90.0)), cos(radians(-90.0)), 2.0,
        -0.0, 0.0, 0.0
    );

	flare_ray_dir += 0.15;

	// Sun disk

	vec3 sun_disk = vec3(r_hole < sun_angular_radius);

	// Solar flare effect

	// Transform the coordinate space such that z is parallel to sun_dir
	mat3 rot = mat3(tangent, bitangent, sun_dir);

	// Vector from ray dir to sun dir
	vec2 q = ((flare_ray_dir + sun_dir) * rot).xy;

	float theta = fract(linear_step(-pi, pi, atan(q.y, q.x)) + 0.015 * frameTimeCounter - 0.33 * r_flare);

	float flare1 = texture(noisetex, vec2(theta, r_flare - 0.025 * frameTimeCounter * 1.25)).x;
    flare1 = pow5(flare1) * exp(-25.0 * (r_flare - sun_angular_radius));
    flare1 = r_hole < sun_angular_radius ? 0.0 : flare1;

    float theta2 = fract(linear_step(-pi, pi, atan(q.y, q.x)) + -0.0002 * frameTimeCounter - 0.33 * (r_flare + 0.05));
    float flare2 = texture(noisetex, vec2(theta2, r_flare - 0.025 * frameTimeCounter)).x;
    flare2 = pow5(flare2) * exp(-20.0 * (r_flare - sun_angular_radius / 2.0));
    flare2 = r_hole < sun_angular_radius ? 0.0 : flare2;

    vec3 flare_color1 = end_sun_color;
    vec3 flare_color2 = vec3(0.8, 0.3, 0.0);

	vec3 black_hole = vec3(0.0);

	#ifdef END_BLACK_HOLE
	black_hole =
		(vec3(0.0, 0.0, 0.0) * max0(sun_disk)) * 100.0
		+ flare_color1 * rcp(sun_solid_angle) * max0(0.5 * flare1)
		+ flare_color2 * rcp(sun_solid_angle) * max0(1.5 * flare2);
	#endif

	return cosmic_glow + black_hole;
}

vec3 draw_sky(vec3 ray_dir) {
	// Sky gradient

	float up_gradient = linear_step(0.0, 0.4, ray_dir.y) + linear_step(0.1, 0.8, -ray_dir.y);
	vec3 sky = ambient_color * mix(0.1, 0.04, up_gradient);
	float mie_phase = cornette_shanks_phase(dot(ray_dir, sun_dir), 0.6);
	sky += 0.1 * (ambient_color + 0.5 * end_sun_color) * mie_phase;

#if defined PROGRAM_DEFERRED4
	// Sun

	sky += draw_sun(ray_dir);

	// Stars

	vec3 stars_fade = exp2(-0.1 * max0(1.0 - ray_dir.y) / max(ambient_color, eps)) * linear_step(-0.2, 0.0, ray_dir.y);
	sky += draw_stars(ray_dir, 0.0).xzy * stars_fade;
#endif

	return sky;
}

#endif

#endif // INCLUDE_SKY_SKY
