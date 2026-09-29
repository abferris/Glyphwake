#version 450

// Underwater tint, as a screen-space pass. Driven by Scripts/World/WaterTintEffect.gd.
//
// The problem this exists to solve: when the eye sits at the waterline, half the frame is under
// water and half is not, and how much water lies between the eye and any given pixel depends on how
// far that pixel is below the surface. Godot's Environment fog is a single density for the whole
// frame, so it can only be right when the whole frame is under water. This pass decides per pixel.
//
// The water level is not a global constant. Each authored Water/WaterZone pair is its own body and
// the caller packs them in, so an inland lake at a different height is just another body in the
// scene rather than a second code path.

layout(rgba16f, set = 0, binding = 0) uniform restrict image2D color_img;

// The depth target is not created with STORAGE usage, so it cannot be read with imageLoad. A plain
// sampler plus texelFetch is the one form that works, and texelFetch is also the right tool here
// anyway: it reads the exact texel with no filtering, and filtering a depth buffer is meaningless.
layout(set = 0, binding = 1) uniform sampler2D depth_tex;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

const int MAX_BODIES = 4;

// The camera arrives as a basis and the projection's scale factors, not as a matrix. See
// unproject() for why: inverting the view-projection matrix for this projection produces values of
// order 1e4 that are then differenced against world coordinates of order 1e3, and float32 loses
// every significant digit doing it. The same result falls out of two well-conditioned steps.
//
// Five vec4 rather than a mat4 also leaves the block comfortably inside Godot's 128 byte push
// constant limit, and the water bodies still cannot go there: they are in a storage buffer below.
layout(push_constant, std430) uniform Params {
	vec4 cam_pos;   // xyz world position of the eye, w = near plane
	vec4 cam_right; // xyz world right axis, w = tan(fov/2) * aspect
	vec4 cam_up;    // xyz world up axis, w = tan(fov/2)
	vec4 cam_fwd;   // xyz world forward axis, w = near * far
	vec4 look;      // x = body count, y = mode, z = depth range, w = spare
	vec4 tint;      // rgb underwater colour
	vec4 tuning;    // x = max path, y = energy, zw spare
	// Debug only, and only read when look.y is set. XYZ is encoded rather than just the height
	// because a height alone cannot tell a correct reconstruction from one that has landed on a
	// different piece of geometry at a similar height, which is exactly the failure that a height-only
	// probe reports as "close enough". The world X and Z are centred on the camera, which the probe
	// already knows exactly, and span half a range either side.
	vec4 debug;     // x = y base, y = y range, z = xz half range, w = spare
};

// Two vec4 per body: centre.x, centre.z, half extent.x, half extent.z, then surface height,
// priority, and two spare floats kept for alignment.
layout(set = 0, binding = 2, std430) readonly buffer Bodies {
	vec4 body[];
} bodies;

// Which authored body, if any, covers this point on the water. Returns the index, or -1 for open
// ground where nothing is under water at all.
int body_at(vec2 xz) {
	int best = -1;
	float best_priority = -1.0e9;
	int count = int(look.x);
	for (int i = 0; i < count; i++) {
		vec4 rect = bodies.body[i * 2];
		vec2 d = abs(xz - rect.xy) - rect.zw;
		if (max(d.x, d.y) > 0.0) {
			continue; // outside this body's footprint
		}
		// Overlapping footprints would otherwise pick whichever came first in the list, so the
		// authored priority decides and a higher water level wins a tie.
		float priority = bodies.body[i * 2 + 1].y;
		if (priority > best_priority) {
			best_priority = priority;
			best = i;
		}
	}
	return best;
}

// The world position this pixel shows.
//
// 4.7 renders reverse-Z: the depth buffer holds 1 at the near plane and 0 at the far plane, so the
// usual perspective remap is inverted and reading it the other way round puts every pixel on the near
// plane, which reconstructs as "just in front of the camera" and produces a perfectly plausible
// looking frame with the water in the wrong place.
//
// Depth to distance is done as a division rather than through an inverse matrix. The two-step form
// costs a handful of instructions and, unlike the matrix, stays accurate at this camera's near/far
// ratio of 80000:1.
float unproject_dist(float d) {
	float n = cam_pos.w;
	float nf = cam_fwd.w;
	float fn = nf / n - n; // far - near
	return nf / (n + d * fn);
}

void main() {
	ivec2 size = imageSize(color_img);
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}

	vec4 col = imageLoad(color_img, px);
	float d = texelFetch(depth_tex, px, 0).r;

	// Screen space is y-down, NDC is y-up, hence the negation.
	vec2 ndc = ((vec2(px) + 0.5) / vec2(size)) * 2.0 - 1.0;
	ndc.y = -ndc.y;

	float dist = unproject_dist(d);
	vec3 world_pos = cam_pos.xyz + (cam_right.xyz * (ndc.x * cam_right.w)
		+ cam_up.xyz * (ndc.y * cam_up.w) + cam_fwd.xyz) * dist;

	int idx = body_at(world_pos.xz);
	if (idx < 0) {
		imageStore(color_img, px, col);
		return;
	}
	float surface_y = bodies.body[idx * 2 + 1].x;

	// Debug view: hand the reconstructed position back to the probe as numbers, so it can be compared
	// against known geometry in metres. A category test looks decisive but is really only meaningful
	// away from its thresholds, and 10 m stripes are narrow enough that centimetres of error flip them,
	// which hides the error instead of measuring it.
	//
	// Alpha carries a known per-pixel gradient rather than opacity, which proves the probe read the
	// pixel it meant to. The raw depth is deliberately not sent: the target is 8-bit sRGB, a depth of
	// a few thousandths lands on 2/255, and linearising that back is quantisation noise rather than a
	// measurement.
	if (look.y > 0.5) {
		vec3 enc = vec3(
			(world_pos.y - debug.x) / debug.y,
			(world_pos.x - cam_pos.x) / debug.z,
			(world_pos.z - cam_pos.z) / debug.z) + vec3(0.0, 0.5, 0.5);
		imageStore(color_img, px, vec4(enc, float(px.x) / float(size.x)));
		return;
	}

	// The view ray. For a pixel showing geometry this is exact, and for a pixel showing sky the
	// reconstruction lands on the far plane, which is still the same ray and so still intersects the
	// water plane correctly.
	vec3 ray = normalize(world_pos - cam_pos.xyz);

	// A flat plane has no "t" when the ray runs parallel to it, and that shows up as a horizon which
	// is exactly the thing this pass is meant to render cleanly, so the tiny floor keeps the maths
	// finite there instead of letting a division decide the colour of the skyline.
	float denom = abs(ray.y) < 1.0e-4 ? (ray.y < 0.0 ? -1.0e-4 : 1.0e-4) : ray.y;
	float t_surface = (surface_y - cam_pos.y) / denom;
	float t_geom = length(world_pos - cam_pos.xyz);

	// How far the ray travels through water. The two cases are genuinely different and treating them
	// as one is what produced a waterline that tinted nothing at all.
	float path;
	if (cam_pos.y >= surface_y) {
		// Eye above the surface. The surface is behind the eye on this ray, or the pixel is nearer
		// than the crossing, and either way there is no water between the eye and it.
		if (t_surface <= 0.0) {
			imageStore(color_img, px, col);
			return;
		}
		path = t_geom - t_surface;
	} else {
		// Eye already under the surface, so the ray starts in water. A ray heading up leaves it
		// again, and is only under water as far as that exit; one heading down never leaves.
		float t_exit = denom > 0.0 ? t_surface : 1.0e30;
		path = min(t_geom, t_exit);
	}

	// Being under the water is not the same as being deep in it, so the first metre or so is barely
	// tinted and it thickens from there.
	path = max(path, 0.0);
	if (path <= 0.0) {
		imageStore(color_img, px, col);
		return;
	}

	// Transmittance, so the bottom fades out rather than stopping existing at some depth. The angular
	// term saturates on its own, which is what looking along a waterline does.
	float angle = max(abs(ray.y), 0.08);
	float thickness = min(path / angle, tuning.x);
	float t = clamp(thickness / look.z, 0.0, 1.0);
	vec3 water = mix(tint.rgb, tint.rgb * 0.25, t);
	imageStore(color_img, px, vec4(mix(col.rgb, water, clamp(t * tuning.y, 0.0, 1.0)), col.a));
}
