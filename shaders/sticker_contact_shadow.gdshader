shader_type spatial; // Renders the sticker contact shadow inside the existing 3D book world.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix, fog_disabled; // Keeps the shadow cheap, transparent, double-sided, and independent from scene lighting.

uniform sampler2D sticker_texture : source_color; // Supplies the exact sticker artwork alpha used to shape the contact shadow.
uniform float shadow_opacity = 0.16; // Controls the subtle darkness of the resting contact shadow.
uniform float blur_radius_texels = 1.75; // Controls the small Gaussian-style softness around the sticker silhouette.

float sample_sticker_alpha(vec2 uv) { // Samples source alpha while treating coordinates outside the artwork as transparent.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { // Detects blur taps that have moved beyond the source image.
		return 0.0; // Keeps the shadow from smearing edge pixels beyond the real sticker silhouette.
	} // Completes the bounds guard for this alpha sample.
	return texture(sticker_texture, uv).a; // Returns the authored artwork alpha for this blur tap.
} // Completes the bounded alpha helper.

void fragment() { // Builds one soft black silhouette from a compact nine-tap kernel.
	vec2 source_size = max(vec2(textureSize(sticker_texture, 0)), vec2(1.0)); // Protects texel-size calculation from malformed zero-sized textures.
	vec2 texel = vec2(1.0) / source_size; // Converts one source pixel into normalized UV distance.
	vec2 blur_step = texel * blur_radius_texels; // Scales the compact kernel to the requested contact-shadow softness.
	float blurred_alpha = sample_sticker_alpha(UV) * 4.0; // Gives the center sample the strongest Gaussian-style weight.
	blurred_alpha += sample_sticker_alpha(UV + vec2(blur_step.x, 0.0)) * 2.0; // Adds the right cardinal blur sample.
	blurred_alpha += sample_sticker_alpha(UV - vec2(blur_step.x, 0.0)) * 2.0; // Adds the left cardinal blur sample.
	blurred_alpha += sample_sticker_alpha(UV + vec2(0.0, blur_step.y)) * 2.0; // Adds the lower cardinal blur sample.
	blurred_alpha += sample_sticker_alpha(UV - vec2(0.0, blur_step.y)) * 2.0; // Adds the upper cardinal blur sample.
	blurred_alpha += sample_sticker_alpha(UV + blur_step); // Adds the lower-right diagonal blur sample.
	blurred_alpha += sample_sticker_alpha(UV - blur_step); // Adds the upper-left diagonal blur sample.
	blurred_alpha += sample_sticker_alpha(UV + vec2(blur_step.x, -blur_step.y)); // Adds the upper-right diagonal blur sample.
	blurred_alpha += sample_sticker_alpha(UV + vec2(-blur_step.x, blur_step.y)); // Adds the lower-left diagonal blur sample.
	ALBEDO = vec3(0.0); // Keeps the contact shadow neutral black so page colour naturally shows through its alpha.
	ALPHA = clamp((blurred_alpha / 16.0) * shadow_opacity, 0.0, 1.0); // Applies the normalized soft silhouette at deliberately low opacity.
} // Completes the contact-shadow fragment pass.
