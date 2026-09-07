shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D sticker_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable; // Supplies the source artwork alpha that directly defines the final sticker silhouette.
uniform vec4 outline_color : source_color = vec4(0.72, 0.82, 0.94, 0.42); // Controls the faint projected landing-guide colour and opacity.
uniform vec2 texel_size = vec2(0.001); // Stores one source artwork texel in normalized UV coordinates for stable contour thickness.
uniform float outline_width_pixels = 2.25; // Controls how far inward from the supplied alpha edge the faint landing contour is drawn.
uniform float alpha_cutoff = 0.08; // Matches the primary sticker material's source-alpha threshold so both shaders agree on the physical footprint.

float sample_alpha(vec2 sample_uv) { // Reads artwork alpha while treating coordinates outside the image rectangle as transparent.
	if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) { // Detects samples outside the supplied artwork bounds.
		return 0.0; // Treats all external space as non-sticker material so image-edge silhouettes still receive an outline.
	} // Completes safe source bounds handling.
	return texture(sticker_texture, sample_uv).a; // Returns filtered source artwork coverage at the requested coordinate.
} // Completes source-alpha sampling.

void fragment() { // Draws a faint contour immediately inside the source artwork alpha silhouette.
	float center_alpha = sample_alpha(UV); // Reads the authoritative sticker coverage at this fragment.
	float body_coverage = smoothstep(alpha_cutoff * 0.5, alpha_cutoff, center_alpha); // Converts source alpha into a stable antialiased physical-coverage value.
	if (body_coverage <= 0.001) { // Rejects fragments outside the actual supplied sticker artwork.
		discard; // Prevents the landing guide from expanding beyond the user's own alpha silhouette.
	} // Completes non-sticker rejection.
	vec2 step_uv = texel_size * outline_width_pixels; // Converts the desired inward contour thickness from source pixels into normalized UV space.
	float minimum_neighbor_coverage = 1.0; // Seeds the most transparent nearby sample used to detect proximity to the alpha edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(1.0, 0.0)))); // Tests the right side of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(-1.0, 0.0)))); // Tests the left side of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(0.0, 1.0)))); // Tests the lower side of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(0.0, -1.0)))); // Tests the upper side of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(0.70710678, 0.70710678)))); // Tests the lower-right diagonal of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(-0.70710678, 0.70710678)))); // Tests the lower-left diagonal of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(-0.70710678, -0.70710678)))); // Tests the upper-left diagonal of the local artwork edge.
	minimum_neighbor_coverage = min(minimum_neighbor_coverage, smoothstep(alpha_cutoff * 0.5, alpha_cutoff, sample_alpha(UV + step_uv * vec2(0.70710678, -0.70710678)))); // Tests the upper-right diagonal of the local artwork edge.
	float edge_strength = body_coverage * (1.0 - minimum_neighbor_coverage); // Keeps only supplied sticker pixels lying close enough to transparent artwork space to form the contour.
	if (edge_strength <= 0.001) { // Rejects interior fragments that are not near the source alpha edge.
		discard; // Prevents translucent fill from appearing through the center of the predicted sticker.
	} // Completes non-edge rejection.
	ALBEDO = outline_color.rgb; // Uses the neutral unlit contour colour without introducing a fake sticker copy.
	ALPHA = outline_color.a * edge_strength; // Keeps the landing guide faint while preserving stronger alpha exactly at the supplied sticker edge.
} // Completes source-alpha landing-outline material.
