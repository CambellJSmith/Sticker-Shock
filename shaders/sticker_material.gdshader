shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sticker_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable; // Supplies the complete printed sticker artwork and its authoritative alpha silhouette.
uniform vec4 adhesive_color : source_color = vec4(0.91, 0.89, 0.82, 1.0); // Supplies the paper-and-adhesive colour visible on the reverse.
uniform vec2 grab_local = vec2(0.0); // Stores the local point where the sticker was grabbed.
uniform vec2 drag_local = vec2(0.0); // Stores the local drag displacement driving the peel geometry.
uniform float curl_width = 0.34; // Controls the material distance used by the rounded peel transition.
uniform float curl_growth = 0.45; // Controls how quickly the peel reaches its full rounded curl radius.
uniform float alpha_cutoff = 0.08; // Controls the source-artwork alpha threshold treated as physical sticker material.
uniform float lift_scale = 1.0; // Controls the vertical height of the physical curl.
uniform vec2 surface_detail_offset = vec2(0.0); // Offsets the procedural realism texture so duplicate stickers do not share identical wear.
uniform float surface_detail_rotation = 0.0; // Rotates the procedural realism texture so scratches and smudges vary between copies.

varying float peel_region; // Carries whether a vertex belongs to the lifted region into the fragment stage.

float hash12(vec2 p) { // Builds one repeatable pseudo-random scalar from a two-dimensional coordinate.
	vec3 p3 = fract(vec3(p.xyx) * 0.1031); // Folds the input coordinate into a low-correlation normalized seed triple.
	p3 += dot(p3, p3.yzx + 33.33); // Scrambles the seed with a self-dot perturbation for better local variation.
	return fract((p3.x + p3.y) * p3.z); // Returns the final zero-to-one hash value.
} // Completes the local coordinate hash.

float noise2(vec2 p) { // Produces smoothed value noise for procedural surface-detail synthesis.
	vec2 cell = floor(p); // Finds the integer lattice cell containing the sample point.
	vec2 local = fract(p); // Finds the local position inside the current value-noise cell.
	vec2 blend = local * local * (3.0 - 2.0 * local); // Uses Hermite smoothing so neighbouring lattice values blend without hard seams.
	float bottom_left = hash12(cell); // Reads the pseudo-random corner value at the lower-left lattice point.
	float bottom_right = hash12(cell + vec2(1.0, 0.0)); // Reads the pseudo-random corner value at the lower-right lattice point.
	float top_left = hash12(cell + vec2(0.0, 1.0)); // Reads the pseudo-random corner value at the upper-left lattice point.
	float top_right = hash12(cell + vec2(1.0, 1.0)); // Reads the pseudo-random corner value at the upper-right lattice point.
	float bottom_mix = mix(bottom_left, bottom_right, blend.x); // Interpolates the bottom edge smoothly across the cell.
	float top_mix = mix(top_left, top_right, blend.x); // Interpolates the top edge smoothly across the cell.
	return mix(bottom_mix, top_mix, blend.y); // Interpolates vertically to produce the final smooth noise sample.
} // Completes value-noise sampling.

float fbm(vec2 p) { // Accumulates several frequencies of value noise for richer broad-scale procedural wear.
	float total = 0.0; // Seeds the fractal sum.
	float amplitude = 0.5; // Seeds the first octave amplitude.
	for (int octave = 0; octave < 4; octave++) { // Uses a small fixed octave count to keep the realism texture inexpensive.
		total += noise2(p) * amplitude; // Adds the current octave to the accumulated fractal signal.
		p = p * 2.03 + vec2(13.1, 7.7); // Increases frequency and offsets the lattice to avoid octave alignment.
		amplitude *= 0.5; // Halves amplitude each octave for a standard fractal falloff.
	} // Completes octave accumulation.
	return total; // Returns the combined broad-to-fine fractal signal.
} // Completes fractal noise synthesis.

vec2 rotate_detail_uv(vec2 uv, float angle) { // Rotates the procedural surface-detail space around the sticker center without affecting artwork placement.
	float sine_value = sin(angle); // Caches the detail-space sine once for efficient coordinate rotation.
	float cosine_value = cos(angle); // Caches the detail-space cosine once for efficient coordinate rotation.
	vec2 centered_uv = uv - vec2(0.5); // Moves the UV origin to sticker center before rotation.
	vec2 rotated_uv = vec2(centered_uv.x * cosine_value - centered_uv.y * sine_value, centered_uv.x * sine_value + centered_uv.y * cosine_value); // Applies a standard 2D rotation to the centered detail-space coordinate.
	return rotated_uv + vec2(0.5) + surface_detail_offset; // Restores center-relative coordinates and adds the per-copy offset used to vary wear patterns.
} // Completes detail-space coordinate rotation.

void vertex() { // Deforms the subdivided sticker grid into a physical cylindrical peel.
	vec2 flat_position = VERTEX.xz; // Reads the undeformed sticker-plane position.
	float drag_distance = length(drag_local); // Measures how far the grabbed material point has moved.
	peel_region = 0.0; // Resets the lifted-region marker for the current vertex.
	if (drag_distance > 0.0001) { // Avoids unstable normalization while the sticker is flat.
		vec2 peel_direction = drag_local / drag_distance; // Defines the direction from the original grab point toward the cursor.
		vec2 fold_axis = vec2(-peel_direction.y, peel_direction.x); // Defines the fold axis perpendicular to the drag direction.
		float active_curl_width = min(curl_width, max(drag_distance * curl_growth, 0.002)); // Shrinks the bend radius naturally during the first part of a peel.
		float radius = active_curl_width / PI; // Converts the chosen half-circle arc length into its cylinder radius.
		float grab_projection = dot(grab_local, peel_direction); // Projects the grab point onto the peel direction.
		float point_projection = dot(flat_position, peel_direction); // Projects the current material vertex onto the peel direction.
		float axis_projection = dot(flat_position, fold_axis); // Preserves the vertex position along the fold axis.
		float fold_projection = grab_projection + (drag_distance + active_curl_width) * 0.5; // Places the fold so the grabbed point follows the cursor exactly after the rounded bend.
		if (point_projection < fold_projection) { // Deforms only material that has passed onto the peeled side of the fold.
			float peeled_distance = fold_projection - point_projection; // Measures material distance behind the moving fold.
			float mapped_projection = point_projection; // Stores the deformed coordinate along the peel direction.
			float height = 0.0; // Stores the vertical lift produced by the curl.
			float projection_derivative = 1.0; // Stores the deformed directional tangent used for the surface normal.
			float height_derivative = 0.0; // Stores the vertical directional tangent used for the surface normal.
			if (peeled_distance < active_curl_width) { // Wraps the bend region around a half cylinder.
				float angle = peeled_distance / radius; // Converts material distance through the bend into a rotation angle.
				mapped_projection = fold_projection - radius * sin(angle); // Keeps the peel tangent continuous where it leaves the page.
				height = radius * (1.0 - cos(angle)) * lift_scale; // Raises the material smoothly through the cylindrical curl.
				projection_derivative = cos(angle); // Rotates the in-plane tangent through the bend.
				height_derivative = -sin(angle) * lift_scale; // Rotates the vertical component of the tangent through the bend.
			} else { // Handles material that has completed the half-circle bend.
				mapped_projection = fold_projection + (peeled_distance - active_curl_width); // Reflects the peeled sheet back across the fold while preserving material length.
				height = radius * 2.0 * lift_scale; // Holds fully folded material above the page at the cylinder diameter.
				projection_derivative = -1.0; // Reverses the material tangent after a complete half turn.
				height_derivative = 0.0; // Keeps the fully peeled sheet locally parallel to the page.
			} // Completes bend-region selection.
			vec2 mapped_position = peel_direction * mapped_projection + fold_axis * axis_projection; // Reconstructs the deformed planar coordinates from the fold basis.
			vec3 fold_tangent = vec3(fold_axis.x, 0.0, fold_axis.y); // Builds the unchanged tangent running along the fold axis.
			vec3 peel_tangent = vec3(peel_direction.x * projection_derivative, height_derivative, peel_direction.y * projection_derivative); // Builds the rotated tangent running through the curl.
			VERTEX = vec3(mapped_position.x, height, mapped_position.y); // Moves the vertex into its curled 3D position.
			NORMAL = normalize(cross(fold_tangent, peel_tangent)); // Rotates the surface normal with the physical material bend.
			peel_region = 1.0; // Marks the vertex as belonging to peeled material for subtle material response.
		} // Completes peeled-side deformation.
	} // Completes active-peel handling.
} // Completes sticker geometry deformation.

void fragment() { // Shades the artwork-defined sticker surface, adhesive reverse, and subtle handling wear.
	vec4 artwork = texture(sticker_texture, UV); // Samples the original artwork directly because its alpha is now the complete physical sticker silhouette.
	if (artwork.a < alpha_cutoff) { // Rejects every fragment the supplied artwork marks as transparent.
		discard; // Removes transparent image space from colour, depth, and shadow rendering.
	} // Completes source-alpha silhouette clipping.
	vec2 detail_uv = rotate_detail_uv(UV, surface_detail_rotation); // Builds the stable per-sticker realism-texture coordinate that moves naturally with the sheet.
	float broad_smudge_noise = fbm(detail_uv * 5.5 + vec2(1.7, -3.4)); // Creates low-frequency patchiness used as the basis for oily fingerprint-like smudges.
	float smudge_detail_noise = fbm(detail_uv * 17.0 + vec2(-5.3, 9.1)); // Adds finer breakup so the broad smudge zones do not look airbrushed.
	float micro_rough_noise = fbm(detail_uv * 75.0 + vec2(14.2, 3.6)); // Supplies very fine grain that breaks up perfectly uniform laminate reflections.
	float scratch_field = fbm(detail_uv * vec2(24.0, 8.0) + vec2(8.0, -1.0)); // Distorts the thin scratch lines so they drift and vary like real handling wear.
	float scratch_lines = pow(1.0 - abs(sin(detail_uv.x * 220.0 + scratch_field * 10.0)), 42.0); // Creates sparse hairline scratches from a sharpened directional stripe pattern.
	float scratch_mask = smoothstep(0.73, 0.9, fbm(detail_uv * 31.0 + vec2(-10.3, 4.7))); // Gates scratches into occasional clusters rather than covering the whole sticker evenly.
	float scratch_strength = scratch_lines * scratch_mask; // Produces the final sparse scratch signal used by colour and gloss variation.
	float scuff_strength = smoothstep(0.68, 0.9, fbm(detail_uv * 19.0 + vec2(6.4, -7.8))); // Produces tiny matte scuffs and rub marks from general handling.
	float smudge_strength = smoothstep(0.57, 0.83, broad_smudge_noise) * mix(0.6, 1.0, smudge_detail_noise); // Combines broad and fine noise into soft oily-smudge zones reminiscent of fingerprints.
	float micro_roughness = (micro_rough_noise - 0.5) * 0.10; // Converts the fine grain signal into a small signed roughness perturbation.
	if (FRONT_FACING) { // Selects the printed front face when the artwork side is visible.
		float fingerprint_gloss = smudge_strength * 0.18; // Makes oily-touch areas slightly glossier and smoother than untouched laminate.
		float scratch_matte = scratch_strength * 0.15; // Makes scratch clusters slightly rougher and more light-scattering than clean laminate.
		float scuff_matte = scuff_strength * 0.08; // Adds a faint extra roughness lift for generalized rub wear.
		vec3 front_albedo = artwork.rgb; // Uses the supplied sticker image directly without adding any generated colour or border.
		front_albedo *= 1.0 - scratch_strength * 0.035; // Very slightly darkens scratched zones so the wear reads without obviously tinting the artwork.
		front_albedo += vec3(0.012) * fingerprint_gloss; // Gives smudged areas a faint cloudy lift that reads like natural skin-oil residue.
		ALBEDO = clamp(front_albedo, vec3(0.0), vec3(1.0)); // Writes the final subtly weathered colour while guarding against tiny procedural overflow.
		ROUGHNESS = clamp(mix(0.34, 0.40, peel_region) + micro_roughness + scratch_matte + scuff_matte - fingerprint_gloss, 0.05, 0.98); // Balances laminate, peel response, and realistic touch wear into one physically plausible roughness value.
		SPECULAR = clamp(0.55 + fingerprint_gloss * 0.35 - scratch_matte * 0.18, 0.02, 0.95); // Lets smudges catch a little more highlight while scratches break highlights slightly.
	} else { // Selects the fibrous adhesive paper wherever the source artwork defines physical sticker material.
		NORMAL = -NORMAL; // Flips the shading normal so the reverse side receives light correctly.
		float paper_variation = 0.965 + 0.035 * sin(UV.x * 173.0 + UV.y * 229.0); // Adds a very small procedural paper variation without a second texture.
		float fiber_noise = fbm(detail_uv * 95.0 + vec2(2.8, -4.4)); // Adds faint fibrous grain so the reverse side is not perfectly uniform.
		ALBEDO = adhesive_color.rgb * paper_variation * (0.97 + 0.06 * fiber_noise); // Applies the warm adhesive-paper colour across the exact source-alpha silhouette.
		ROUGHNESS = clamp(0.90 + (fiber_noise - 0.5) * 0.05, 0.0, 1.0); // Makes the sticker reverse substantially rougher than the printed face while adding slight tactile variation.
		SPECULAR = 0.18; // Keeps only a weak broad reflection on the adhesive surface.
	} // Completes front-versus-back material selection.
} // Completes sticker material shading.
