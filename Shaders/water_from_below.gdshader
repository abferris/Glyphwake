shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_front, unshaded;

// Underside of the water surface. Applied to a second, coincident copy of the water plane that
// only draws back faces (cull_front), so it is invisible from above the water, where
// water_from_above.gdshader draws the surface instead.
//
// The ceiling is one continuous surface, not a disc. Physically there is a Snell's window and a
// total-internal-reflection surround, but splitting on the critical angle puts a hard-edged
// circle overhead, and a circle up there reads as a spotlight or a hole rather than as water.
// So the two tones are close and the ramp spans the whole dome: grazing angles reflect the dim
// water below, and straight up is only a little lighter because the sky reads through the thin
// part of the surface. The surface is identified by the ripples and the moving shimmer, not by
// an edge. The underwater fog in CameraController fades it with depth.

uniform vec4 window_color : source_color = vec4(0.30, 0.55, 0.68, 0.60);
uniform vec4 mirror_color : source_color = vec4(0.18, 0.40, 0.52, 0.92);
uniform float ripple_strength : hint_range(0.0, 0.5) = 0.12;
uniform float ripple_scale : hint_range(0.0, 1.0) = 0.22;
uniform float ripple_speed : hint_range(0.0, 3.0) = 0.8;
uniform float shimmer : hint_range(0.0, 0.5) = 0.16;

float wave(vec2 p) {
	return sin(p.x * ripple_scale + TIME * ripple_speed)
		+ sin(p.y * ripple_scale * 0.83 - TIME * ripple_speed * 0.7) * 0.8;
}

void fragment() {
	// world space, so the ripples are the same whether the plane is huge or small
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = wave(world.xz);
	// the plane is flat and horizontal, so its world normal is straight up plus the ripple.
	// It has to be built in world space and then taken to view space: NORMAL is already the
	// view space normal, so perturbing it with world space offsets would slide the ripples
	// around as the camera turns.
	vec3 n = normalize((VIEW_MATRIX * vec4(normalize(vec3(w * ripple_strength, 1.0, w * ripple_strength * 0.6)), 0.0)).xyz);

	// How steeply the eye looks at the surface: near 1 when looking straight up through it, near
	// 0 when looking along it. The plane's normal points up, away from an eye underneath, so the
	// dot product is negative from below and abs() is what turns it back into an angle.
	float facing = abs(dot(n, normalize(VIEW)));

	// full range on purpose, so there is no boundary anywhere on the dome to read as a circle
	float up = smoothstep(0.0, 1.0, facing);
	vec3 col = mix(mirror_color.rgb, window_color.rgb, up);
	// the shimmer moves, so the ceiling reads as a surface even where the fog flattens its colour
	col += shimmer * (0.5 + 0.5 * sin(w * 1.7 + TIME * 1.3));
	ALBEDO = col;

	ALPHA = mix(mirror_color.a, window_color.a, up);
}
