shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Surface of the water, seen from above. The shape underneath is real geometry, so rather than a
// flat wash of alpha this measures how much water the view ray actually crosses and fades the
// scene through it. That buys the three things real water does, for one texture read:
//
//   - Straight down the ray crosses only the depth of the water, so a shallow bottom stays clear
//     and a deep bottom fades.
//   - Towards a grazing angle the ray travels a long way sideways *inside* the water, so the same
//     water gets thicker and buries the bottom long before the geometry under it changes.
//   - At that same grazing angle the surface turns into a mirror, via Fresnel.
//
// All of it is gradual. Transmittance is Beer-Lambert, exp(-extinction * path), so there is no
// depth at which the bottom simply stops existing; it just goes from clear to gone. Only the
// angular term saturates, which is what a mirror does.
//
// The plane is still flat with no subdivision and the colours are still flat, and the ripple is
// two sines, so the surface keeps the low-poly look of the rest of the water. The ripple exists to
// make the Fresnel shimmer as the eye moves; without it the grazing band would be a clean arc,
// which reads as a rendering seam rather than as water.

uniform vec3 shallow_color : source_color = vec3(0.09, 0.31, 0.45);
uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.16);
uniform vec3 reflect_color : source_color = vec3(0.42, 0.56, 0.72);

// the scene's depth, auto assigned by the hint. Declared rather than using the old built-in name,
// which 4.7 removed.
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// how fast the water eats light, per metre of water crossed
uniform float extinction : hint_range(0.0, 3.0) = 0.25;
// opacity looking straight down at nothing in the way; the depth and angle terms raise it from here
uniform float shallow_opacity : hint_range(0.0, 1.0) = 0.20;
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.55;
// how much water a ray may cross before the bottom is considered gone, which keeps the very edge
// of the horizon from going hard black in one pixel
uniform float max_thickness : hint_range(1.0, 64.0) = 24.0;
uniform float ripple_strength : hint_range(0.0, 0.5) = 0.09;

float wave(vec2 p) {
	return sin(p.x * 0.22 + TIME * 0.8)
		+ sin(p.y * 0.18 - TIME * 0.56) * 0.8;
}

void fragment() {
	// world space, so the ripple is the same whether the plane is huge or small. NORMAL is already
	// in view space, so the perturbation is built in world space and then taken to view space.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = wave(world.xz);
	vec3 n = normalize((VIEW_MATRIX * vec4(normalize(vec3(w * ripple_strength, 1.0, w * ripple_strength * 0.6)), 0.0)).xyz);

	// How steeply the eye looks at the surface: near 1 when looking straight down through it, near
	// 0 when looking along it. Near 0 the surface reflects almost everything, which is the whole
	// reason the far side of a lake goes to mirror.
	vec3 v = normalize(VIEW);
	float facing = clamp(dot(n, v), 0.0, 1.0);
	float fres = pow(1.0 - facing, fresnel_power);

	// How much water is between this bit of surface and whatever is under it. The opaque scene is
	// already in the depth texture by the time a blended surface draws, so one read is the whole
	// bottom of the lake for free. Reconstructing through INV_PROJECTION_MATRIX rather than
	// dividing depth out by hand means this does not care how the projection encodes depth.
	float scene_d = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_d, 1.0);
	// both distances are measured along the view axis, so their difference is how far back the
	// bottom is, and going negative means the water is in front of the camera rather than behind
	// the thing that was sampled
	float scene_dist = -(behind.xyz / behind.w).z;
	float surface_dist = -VERTEX.z;
	float column = max(scene_dist - surface_dist, 0.0);

	// The depth above is along the view axis, but the ray has to travel to get there, and near a
	// grazing angle it travels enormously further through the same water. Dividing by the cosine
	// is what turns "deep water is dimmer" into "water seen edge on is a mirror" without a second
	// magic angle constant. The 0.05 floor keeps it finite at the exact horizon.
	float ray_cos = max(-normalize(VERTEX).z, 0.05);
	float path = min(column / ray_cos, max_thickness);
	float transmit = exp(-extinction * path);

	// Blended surfaces do not carry their own shadowing or much of their own light, so opacity is
	// driven from how much of the scene actually survives the crossing rather than from a constant.
	float obstructed = 1.0 - transmit * (1.0 - fres);
	ALPHA = clamp(mix(shallow_opacity, 1.0, obstructed), 0.0, 1.0);

	// the water body darkens with the path it took, and the surface mixes in the sky it is
	// reflecting, so the far side of the lake goes pale and bright and the near side stays blue
	ALBEDO = mix(mix(shallow_color, deep_color, 1.0 - transmit), reflect_color, fres * reflect_strength);
	ROUGHNESS = 0.08;
	METALLIC = 0.3;
}
