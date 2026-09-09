shader_type spatial; // Renders the sticker contact shadow inside the existing 3D book world.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix, fog_disabled; // Keeps the shadow cheap, transparent, double-sided, and independent from scene lighting.

uniform sampler2D sticker_texture : source_color; // Supplies the exact sticker artwork alpha used to shape the contact shadow.
uniform vec2 sticker_size = vec2(1.0); // Stores the original physical sticker dimensions used to reconstruct local material positions from UVs.
uniform vec2 sticker_texel_size = vec2(1.0); // Stores normalized source-pixel size supplied once by GDScript so fragments never query texture dimensions.
uniform float shadow_opacity = 0.16; // Controls the subtle darkness of the resting contact shadow.
uniform float blur_radius_texels = 1.75; // Controls the small Gaussian-style softness around the sticker silhouette.
uniform bool peel_active = false; // Selects whether the shadow should be clipped to the material still touching the page.
uniform vec2 peel_direction = vec2(1.0, 0.0); // Stores the normalized local peel direction supplied once per drag update.
uniform float fold_projection = 0.0; // Stores the moving local fold boundary shared with the physical peel geometry.

float contact_mask(vec2 uv) { // Returns whether one source-material sample is still on the page-facing side of the peel fold.
	if (!peel_active) { // Handles the normal resting sticker without unnecessary projection work.
		return 1.0; // Keeps every authored alpha sample available to the complete contact shadow.
	} // Completes the flat-state fast path.
	vec2 local_position = (uv - vec2(0.5)) * sticker_size; // Reconstructs the exact undeformed local material point represented by this artwork UV.
	float point_projection = dot(local_position, peel_direction); // Projects the material point onto the same axis used by the physical peel shader.
	return step(fold_projection, point_projection); // Keeps only material at or ahead of the fold, which is the portion still resting on the page.
} // Completes attached-material classification.

float sample_contact_alpha(vec2 uv) { // Samples source alpha after removing material that has already lifted away from the page.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { // Detects blur taps that have moved beyond the source image.
		return 0.0; // Keeps the shadow from smearing edge pixels beyond the real sticker silhouette.
	} // Completes the bounds guard for this alpha sample.
	return texture(sticker_texture, uv).a * contact_mask(uv); // Contributes shadow only where authored sticker material still remains physically attached.
} // Completes bounded peel-aware alpha sampling.

void fragment() { // Builds one soft black silhouette from only the sticker material still touching the page.
	vec2 blur_step = sticker_texel_size * blur_radius_texels; // Scales the precomputed source-pixel size to the requested contact-shadow softness.
	float blurred_alpha = sample_contact_alpha(UV) * 4.0; // Gives the center attached-material sample the strongest Gaussian-style weight.
	blurred_alpha += sample_contact_alpha(UV + vec2(blur_step.x, 0.0)) * 2.0; // Adds the right cardinal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV - vec2(blur_step.x, 0.0)) * 2.0; // Adds the left cardinal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV + vec2(0.0, blur_step.y)) * 2.0; // Adds the lower cardinal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV - vec2(0.0, blur_step.y)) * 2.0; // Adds the upper cardinal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV + blur_step); // Adds the lower-right diagonal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV - blur_step); // Adds the upper-left diagonal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV + vec2(blur_step.x, -blur_step.y)); // Adds the upper-right diagonal attached-material blur sample.
	blurred_alpha += sample_contact_alpha(UV + vec2(-blur_step.x, blur_step.y)); // Adds the lower-left diagonal attached-material blur sample.
	ALBEDO = vec3(0.0); // Keeps the contact shadow neutral black so page colour naturally shows through its alpha.
	ALPHA = clamp((blurred_alpha / 16.0) * shadow_opacity, 0.0, 1.0); // Applies the normalized soft attached-area silhouette at deliberately low opacity.
} // Completes the peel-aware contact-shadow fragment pass.
