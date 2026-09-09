shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sticker_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable; // Supplies the complete printed sticker artwork and its authoritative alpha silhouette.
uniform bool special_edition = false; // Switches only this exact physical copy into the shiny gold-metal front treatment.
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

float scratch_line(float phase, float width) { // Builds one softened scratch core from a directional repeating line field.
	float distance_from_core = abs(sin(phase)); // Measures the distance from the centre of the current scratch line.
	return 1.0 - smoothstep(0.0, width, distance_from_core); // Converts that distance into a soft-edged scratch mask.
} // Completes scratch-line shaping.

vec2 rotate_surface_space(vec2 coordinate, float angle) { // Rotates one independent damage layer without changing the supplied artwork UVs.
	float sine_value = sin(angle); // Caches the damage-layer sine for the coordinate rotation.
	float cosine_value = cos(angle); // Caches the damage-layer cosine for the coordinate rotation.
	return vec2(coordinate.x * cosine_value - coordinate.y * sine_value, coordinate.x * sine_value + coordinate.y * cosine_value); // Returns the rotated procedural-detail coordinate.
} // Completes independent damage-space rotation.

vec2 rotate_detail_uv(vec2 uv, float angle) { // Rotates the procedural surface-detail space around the sticker center without affecting artwork placement.
	float sine_value = sin(angle); // Caches the detail-space sine once for efficient coordinate rotation.
	float cosine_value = cos(angle); // Caches the detail-space cosine once for the coordinate rotation.
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
	float scuff_strength = smoothstep(0.68, 0.9, fbm(detail_uv * 19.0 + vec2(6.4, -7.8))); // Produces tiny matte scuffs and rub marks that help mask the regularity of the scratch layers.
	float scratch_field = fbm(detail_uv * vec2(24.0, 8.0) + vec2(8.0, -1.0)); // Distorts the thin scratch lines so they drift and vary like real handling wear.
	float fine_scratch_phase = detail_uv.x * 220.0 + scratch_field * 10.0; // Creates the drifting high-frequency phase used by fine hairline damage.
	float fine_scratch_outer = scratch_line(fine_scratch_phase, 0.07); // Defines the faint outer wear halo around shallow hairline scratches.
	float fine_scratch_core = scratch_line(fine_scratch_phase, 0.032); // Defines the narrow centre of shallow hairline scratches.
	float fine_scratch_cluster = smoothstep(0.73, 0.9, fbm(detail_uv * 31.0 + vec2(-10.3, 4.7))); // Gates fine scratches into irregular handling clusters rather than covering the whole sticker evenly.
	float fine_scratch_depth = mix(0.20, 0.42, noise2(detail_uv * 18.0 + vec2(2.1, -4.7))); // Gives each fine scratch a restrained random depth.
	float fine_scratch_strength = fine_scratch_core * fine_scratch_cluster * fine_scratch_depth; // Produces the weighted shallow-scratch core.
	float fine_scratch_edge = max(fine_scratch_outer - fine_scratch_core, 0.0) * fine_scratch_cluster * fine_scratch_depth; // Produces the subtle edge catch around each fine scratch.
	vec2 medium_detail_uv = rotate_surface_space(detail_uv + vec2(3.7, -5.2), 0.68); // Rotates the medium-wear layer so scratches do not share one direction.
	float medium_field = noise2(medium_detail_uv * vec2(18.0, 6.0) + vec2(4.6, -3.2)); // Warps medium scratches with inexpensive local variation.
	float medium_scratch_phase = medium_detail_uv.x * 108.0 + medium_field * 8.0; // Creates the directional phase for wider handling scratches.
	float medium_scratch_outer = scratch_line(medium_scratch_phase, 0.13); // Defines the broader outer wear around medium scratches.
	float medium_scratch_core = scratch_line(medium_scratch_phase, 0.06); // Defines the darker centre of medium scratches.
	float medium_scratch_cluster = smoothstep(0.72, 1.02, scuff_strength + medium_field * 0.22); // Allows medium scratches to appear in broken, rubbed areas only.
	float medium_scratch_depth = mix(0.38, 0.76, noise2(medium_detail_uv * 8.0 + vec2(-7.1, 5.8))); // Gives medium scratches visibly different depths.
	float medium_scratch_strength = medium_scratch_core * medium_scratch_cluster * medium_scratch_depth; // Produces the weighted medium-scratch core.
	float medium_scratch_edge = max(medium_scratch_outer - medium_scratch_core, 0.0) * medium_scratch_cluster * medium_scratch_depth; // Produces the lit shoulder around medium scratches.
	vec2 deep_detail_uv = rotate_surface_space(detail_uv + vec2(-6.2, 2.7), -0.49); // Rotates the deep-gouge layer into a third direction.
	float deep_field = noise2(deep_detail_uv * vec2(10.0, 3.0) + vec2(7.1, -9.4)); // Supplies broad variation for the deepest damaged areas.
	float deep_warp = noise2(deep_detail_uv * vec2(5.0, 13.0) + vec2(-3.1, 11.7)); // Breaks the deep scratch phase into irregular sections.
	float deep_scratch_phase = deep_detail_uv.x * 55.0 + deep_field * 6.0 + deep_warp * 2.0; // Creates sparse, wider gouge paths.
	float deep_scratch_outer = scratch_line(deep_scratch_phase, 0.18); // Defines the wide worn shoulder around a deep gouge.
	float deep_scratch_core = scratch_line(deep_scratch_phase, 0.075); // Defines the concentrated dark channel at the bottom of a deep gouge.
	float deep_scratch_cluster = smoothstep(0.74, 0.93, deep_field * 0.70 + scuff_strength * 0.30); // Keeps the deepest damage sparse while reusing existing wear fields for lower fragment cost.
	float deep_scratch_depth = mix(0.62, 1.0, deep_field); // Gives each deep gouge a strong but varied material depth.
	float deep_scratch_strength = deep_scratch_core * deep_scratch_cluster * deep_scratch_depth; // Produces the weighted deep-gouge core.
	float deep_scratch_edge = max(deep_scratch_outer - deep_scratch_core, 0.0) * deep_scratch_cluster * deep_scratch_depth; // Produces the exposed edge highlight around deep gouges.
	float scratch_darkening = fine_scratch_strength * 0.018 + medium_scratch_strength * 0.055 + deep_scratch_strength * 0.12; // Converts material depth into progressively darker scratch channels.
	float scratch_matte = fine_scratch_strength * 0.07 + medium_scratch_strength * 0.16 + deep_scratch_strength * 0.30; // Converts material depth into progressively rougher damaged laminate.
	float scratch_specular_loss = fine_scratch_strength * 0.04 + medium_scratch_strength * 0.11 + deep_scratch_strength * 0.24; // Removes more clean gloss from deeper damage.
	float scratch_edge = fine_scratch_edge * 0.32 + medium_scratch_edge * 0.68 + deep_scratch_edge; // Combines the depth-specific edge catches into one restrained highlight signal.
	float smudge_strength = smoothstep(0.57, 0.83, broad_smudge_noise) * mix(0.6, 1.0, smudge_detail_noise); // Combines broad and fine noise into soft oily-smudge zones reminiscent of fingerprints.
	float micro_roughness = (micro_rough_noise - 0.5) * 0.10; // Converts the fine grain signal into a small signed roughness perturbation.
	if (FRONT_FACING) { // Selects the printed front face when the artwork side is visible.
		if (special_edition) { // Gives special copies a glossy gold-metal front with a recurring premium light sweep.
			float artwork_value = dot(artwork.rgb, vec3(0.299, 0.587, 0.114)); // Converts the original art into luminance so details remain readable after the gold material replacement.
			vec3 dark_gold = vec3(0.34, 0.12, 0.015); // Keeps dark artwork regions visibly bronze-gold instead of collapsing toward black.
			vec3 bright_gold = vec3(1.0, 0.72, 0.16); // Gives light artwork regions a bright warm polished-gold response.
			vec3 gold_albedo = mix(dark_gold, bright_gold, smoothstep(0.03, 0.97, artwork_value)); // Maps the complete original value range into a readable gold palette.
			gold_albedo *= 1.0 - scratch_darkening * 0.24; // Preserves subtle physical wear without crushing shadow values.
			gold_albedo += vec3(0.10, 0.055, 0.010) * scratch_edge; // Lets scratches catch warm metallic highlights.
			float shimmer_cycle = mod(TIME, 4.4); // Creates one repeatable premium sweep followed by a short resting interval before the next pass.
			float shimmer_active = 1.0 - step(1.35, shimmer_cycle); // Keeps the artificial streak visible only during the opening part of each cycle.
			float shimmer_progress = clamp(shimmer_cycle / 1.35, 0.0, 1.0); // Converts the active sweep time into a stable zero-to-one travel amount.
			float shimmer_axis = UV.x + UV.y * 0.55; // Tilts the streak diagonally so it reads as a moving light reflection across the sticker face.
			float shimmer_position = mix(-0.28, 1.83, shimmer_progress); // Moves the streak fully from outside one edge to beyond the opposite edge.
			float shimmer_distance = abs(shimmer_axis - shimmer_position); // Measures each fragment's distance from the moving diagonal light centre.
			float shimmer_core = (1.0 - smoothstep(0.0, 0.035, shimmer_distance)) * shimmer_active; // Builds the narrow bright white-gold centre line.
			float shimmer_halo = (1.0 - smoothstep(0.025, 0.16, shimmer_distance)) * shimmer_active; // Builds a broader warm glow around the premium streak.
			float shimmer_strength = clamp(shimmer_core + shimmer_halo * 0.58, 0.0, 1.0); // Combines core and halo into one bounded material response.
			gold_albedo += vec3(0.34, 0.19, 0.035) * shimmer_halo; // Warms the gold beneath the passing halo before the brightest centre arrives.
			gold_albedo += vec3(0.58, 0.50, 0.34) * shimmer_core; // Adds a strong near-white premium highlight through the centre of the sweep.
			ALBEDO = clamp(gold_albedo, vec3(0.0), vec3(1.0)); // Writes the animated gold base colour used by Godot's combined diffuse and metal response.
			METALLIC = 0.68; // Keeps the surface convincingly metallic while retaining enough diffuse energy for the compatibility renderer and flat scene lighting.
			ROUGHNESS = clamp(0.16 + micro_roughness * 0.18 + scratch_matte * 0.18 + scuff_strength * 0.035 - shimmer_strength * 0.10, 0.045, 0.34); // Temporarily polishes the material under the moving streak so the sweep catches sharper scene highlights too.
			SPECULAR = clamp(0.88 + shimmer_strength * 0.10, 0.0, 1.0); // Reinforces the artificial glint with a brief stronger specular response under its centre and halo.
			EMISSION = gold_albedo * 0.075 + vec3(1.0, 0.78, 0.34) * (shimmer_halo * 0.18 + shimmer_core * 0.52); // Makes the streak clearly visible in every scene while retaining the established nonblack gold floor.
		} else { // Preserves the established printed-laminate response for ordinary copies.
			float fingerprint_gloss = smudge_strength * 0.18; // Makes oily-touch areas slightly glossier and smoother than untouched laminate.
			float scuff_matte = scuff_strength * 0.08; // Adds a faint extra roughness lift for generalized rub wear.
			vec3 front_albedo = artwork.rgb; // Uses the supplied sticker image directly without adding any generated colour or border.
			front_albedo *= 1.0 - scratch_darkening; // Darkens deeper scratch channels more strongly while preserving the supplied artwork colours.
			front_albedo += vec3(0.020, 0.017, 0.014) * scratch_edge; // Adds a restrained exposed-laminate catch along scratch shoulders so depth reads under soft light.
			front_albedo += vec3(0.012) * fingerprint_gloss; // Gives smudged areas a faint cloudy lift that reads like natural skin-oil residue.
			ALBEDO = clamp(front_albedo, vec3(0.0), vec3(1.0)); // Writes the final subtly weathered colour while guarding against tiny procedural overflow.
			METALLIC = 0.0; // Keeps ordinary stickers as printed laminate rather than metal.
			ROUGHNESS = clamp(mix(0.34, 0.40, peel_region) + micro_roughness + scratch_matte + scuff_matte - fingerprint_gloss, 0.05, 0.98); // Balances laminate, peel response, and realistic touch wear into one physically plausible roughness value.
			SPECULAR = clamp(0.55 + fingerprint_gloss * 0.35 - scratch_specular_loss, 0.02, 0.95); // Lets smudges catch a little more highlight while deeper scratches break the laminate gloss.
			EMISSION = vec3(0.0); // Keeps ordinary artwork fully dependent on scene lighting.
		} // Completes normal-versus-special front material selection.
	} else { // Selects the fibrous adhesive paper wherever the source artwork defines physical sticker material.
		NORMAL = -NORMAL; // Flips the shading normal so the reverse side receives light correctly.
		float paper_variation = 0.965 + 0.035 * sin(UV.x * 173.0 + UV.y * 229.0); // Adds a very small procedural paper variation without a second texture.
		float fiber_noise = fbm(detail_uv * 95.0 + vec2(2.8, -4.4)); // Adds faint fibrous grain so the reverse side is not perfectly uniform.
		ALBEDO = adhesive_color.rgb * paper_variation * (0.97 + 0.06 * fiber_noise); // Applies the warm adhesive-paper colour across the exact source-alpha silhouette.
		METALLIC = 0.0; // Keeps the adhesive reverse as paper even when the printed front is a special gold edition.
		ROUGHNESS = clamp(0.90 + (fiber_noise - 0.5) * 0.05, 0.0, 1.0); // Makes the sticker reverse substantially rougher than the printed face while adding slight tactile variation.
		SPECULAR = 0.18; // Keeps only a weak broad reflection on the adhesive surface.
		EMISSION = vec3(0.0); // Keeps the paper reverse fully lit by the scene.
	} // Completes front-versus-back material selection.
} // Completes sticker material shading.