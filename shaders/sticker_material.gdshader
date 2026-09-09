shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sticker_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable; // Supplies the complete printed sticker artwork and its authoritative alpha silhouette.
uniform bool special_edition = false; // Preserves the legacy gold switch for compatibility with older callers while explicit editions use the integer selector.
uniform int edition = 0; // Selects normal, rainbow, silver, or gold for this exact physical copy.
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
	float cosine_value = cos(angle); // Caches the damage-layer cosine once for efficient coordinate rotation.
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
	float fine_scratch_phase = detail_uv.x * 220.0 + scratch_field * 10.0; // Creates the drifting high-frequency phase used by dense fine hairline damage.
	float fine_scratch_core = scratch_line(fine_scratch_phase, 0.055); // Widens the fine hairline core so substantially more scratches register in reflected light.
	float fine_scratch_cluster = smoothstep(0.52, 0.78, fbm(detail_uv * 31.0 + vec2(-10.3, 4.7))); // Spreads fine scratches through much more of the laminate while retaining irregular clustering.
	float fine_scratch_depth = mix(0.35, 0.70, noise2(detail_uv * 18.0 + vec2(2.1, -4.7))); // Gives fine scratches enough depth variation to create an obvious roughness and gloss response.
	float fine_scratch_strength = fine_scratch_core * fine_scratch_cluster * fine_scratch_depth; // Produces the stronger shallow-scratch wear signal.
	vec2 medium_detail_uv = rotate_surface_space(detail_uv + vec2(3.7, -5.2), 0.68); // Rotates the medium-wear layer so scratches do not share one direction.
	float medium_field = noise2(medium_detail_uv * vec2(18.0, 6.0) + vec2(4.6, -3.2)); // Warps medium scratches with inexpensive local variation.
	float medium_scratch_phase = medium_detail_uv.x * 108.0 + medium_field * 8.0; // Creates the directional phase for wider handling scratches.
	float medium_scratch_core = scratch_line(medium_scratch_phase, 0.09); // Widens medium scratches so they interrupt highlights clearly at normal gameplay scale.
	float medium_scratch_cluster = smoothstep(0.45, 0.76, scuff_strength + medium_field * 0.30); // Makes medium scratches considerably more common across handled laminate regions.
	float medium_scratch_depth = mix(0.55, 0.95, noise2(medium_detail_uv * 8.0 + vec2(-7.1, 5.8))); // Gives medium scratches a strong range of material damage.
	float medium_scratch_strength = medium_scratch_core * medium_scratch_cluster * medium_scratch_depth; // Produces the stronger medium-scratch wear signal.
	vec2 deep_detail_uv = rotate_surface_space(detail_uv + vec2(-6.2, 2.7), -0.49); // Rotates the deep-gouge layer into a third direction.
	float deep_field = noise2(deep_detail_uv * vec2(10.0, 3.0) + vec2(7.1, -9.4)); // Supplies broad variation for the deepest damaged areas.
	float deep_warp = noise2(deep_detail_uv * vec2(5.0, 13.0) + vec2(-3.1, 11.7)); // Breaks the deep scratch phase into irregular sections.
	float deep_scratch_phase = deep_detail_uv.x * 55.0 + deep_field * 6.0 + deep_warp * 2.0; // Creates sparse, wider gouge paths.
	float deep_scratch_core = scratch_line(deep_scratch_phase, 0.105); // Widens deep gouges enough to produce strong isolated breaks in the laminate finish.
	float deep_scratch_cluster = smoothstep(0.55, 0.78, deep_field * 0.72 + scuff_strength * 0.28); // Allows deep scratches to appear substantially more often without making them uniformly distributed.
	float deep_scratch_depth = mix(0.78, 1.10, deep_field); // Gives the deepest gouges enough strength to dominate local surface response.
	float deep_scratch_strength = deep_scratch_core * deep_scratch_cluster * deep_scratch_depth; // Produces the stronger deep-gouge wear signal.
	float scratch_darkening = fine_scratch_strength * 0.06 + medium_scratch_strength * 0.18 + deep_scratch_strength * 0.42; // Makes progressively deeper scratches visibly darken the printed surface much more strongly.
	float scratch_matte = fine_scratch_strength * 0.18 + medium_scratch_strength * 0.38 + deep_scratch_strength * 0.72; // Makes scratched laminate dramatically rougher where the coating has been damaged.
	float scratch_specular_loss = fine_scratch_strength * 0.18 + medium_scratch_strength * 0.42 + deep_scratch_strength * 0.80; // Strongly destroys clean specular response inside scratch channels while leaving intact laminate glossy.
	float smudge_strength = smoothstep(0.57, 0.83, broad_smudge_noise) * mix(0.6, 1.0, smudge_detail_noise); // Combines broad and fine noise into soft oily-smudge zones reminiscent of fingerprints.
	float micro_roughness = (micro_rough_noise - 0.5) * 0.10; // Converts the fine grain signal into a small signed roughness perturbation.
	if (FRONT_FACING) { // Selects the printed front face when the artwork side is visible.
		int active_edition = edition; // Reads the explicit current finish selected by the edition-aware game systems.
		if (active_edition == 0 && special_edition) { // Preserves pre-migration callers that only know the original boolean special flag.
			active_edition = 3; // Interprets legacy special=true as gold exactly as old saves and code did.
		} // Completes legacy material compatibility.
		if (active_edition == 3) { // Gives gold copies the established glossy premium-metal treatment.
			float artwork_value = dot(artwork.rgb, vec3(0.299, 0.587, 0.114)); // Converts the original art into luminance so details remain readable after the gold material replacement.
			vec3 dark_gold = vec3(0.34, 0.12, 0.015); // Keeps dark artwork regions visibly bronze-gold instead of collapsing toward black.
			vec3 bright_gold = vec3(1.0, 0.72, 0.16); // Gives light artwork regions a bright warm polished-gold response.
			vec3 gold_albedo = mix(dark_gold, bright_gold, smoothstep(0.03, 0.97, artwork_value)); // Maps the complete original value range into a readable gold palette.
			gold_albedo *= 1.0 - scratch_darkening * 0.55; // Makes scratches clearly darken premium gold while preserving enough colour to read the metallic finish.
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
			METALLIC = 0.68; // Keeps the surface convincingly metallic while retaining enough diffuse energy for compatibility rendering.
			ROUGHNESS = clamp(0.16 + micro_roughness * 0.18 + scratch_matte * 0.55 + scuff_strength * 0.035 - shimmer_strength * 0.10, 0.045, 0.72); // Lets damaged gold become dramatically rough while intact areas remain premium and reflective.
			SPECULAR = clamp(0.88 + shimmer_strength * 0.10 - scratch_specular_loss * 0.55, 0.04, 1.0); // Allows scratches to carve obvious dead zones through the polished gold reflection.
			EMISSION = gold_albedo * 0.075 + vec3(1.0, 0.78, 0.34) * (shimmer_halo * 0.18 + shimmer_core * 0.52); // Keeps gold visible under weak scene reflections and strongly emphasizes the sweep.
		} else if (active_edition == 2) { // Gives silver copies a bright polished cool-metal finish distinct from gold.
			float artwork_value = dot(artwork.rgb, vec3(0.299, 0.587, 0.114)); // Preserves artwork detail through luminance rather than tinting the original colours.
			vec3 silver_albedo = mix(vec3(0.16, 0.18, 0.21), vec3(0.96, 0.98, 1.0), smoothstep(0.03, 0.97, artwork_value)); // Maps artwork values into a readable steel-to-bright-silver range.
			float sweep_cycle = mod(TIME + 0.8, 4.8); // Offsets silver's sweep timing from gold so adjacent variants do not animate identically.
			float sweep_active = 1.0 - step(1.25, sweep_cycle); // Gives the reflection a brief active pass with a longer rest.
			float sweep_progress = clamp(sweep_cycle / 1.25, 0.0, 1.0); // Normalizes the active silver pass.
			float sweep_axis = UV.x + UV.y * 0.48; // Tilts the silver reflection diagonally across the face.
			float sweep_distance = abs(sweep_axis - mix(-0.30, 1.78, sweep_progress)); // Measures fragment distance from the moving reflection band.
			float sweep_core = (1.0 - smoothstep(0.0, 0.030, sweep_distance)) * sweep_active; // Creates the crisp polished-metal highlight core.
			float sweep_halo = (1.0 - smoothstep(0.02, 0.14, sweep_distance)) * sweep_active; // Creates the broader reflected-light halo.
			silver_albedo *= 1.0 - scratch_darkening * 0.50; // Makes physical scratch channels readily visible across the bright silver finish.
			silver_albedo += vec3(0.32, 0.36, 0.42) * sweep_halo + vec3(0.58) * sweep_core; // Makes the silver pass visually unmistakable.
			ALBEDO = clamp(silver_albedo, vec3(0.0), vec3(1.0)); // Writes the cool-metal artwork replacement.
			METALLIC = 0.76; // Gives silver a slightly stronger metal response than gold.
			ROUGHNESS = clamp(0.14 + micro_roughness * 0.16 + scratch_matte * 0.52 - sweep_core * 0.08, 0.04, 0.70); // Allows scratches to break the mirror-like silver finish into visibly rough channels.
			SPECULAR = clamp(0.94 - scratch_specular_loss * 0.58, 0.04, 1.0); // Strongly suppresses silver highlights inside scratched regions while preserving clean metal elsewhere.
			EMISSION = silver_albedo * 0.045 + vec3(0.88, 0.95, 1.0) * (sweep_halo * 0.12 + sweep_core * 0.34); // Keeps silver readable and gives its sweep a cool artificial lift.
		} else if (active_edition == 1) { // Gives rainbow copies an animated prismatic foil finish while preserving the underlying artwork structure.
			float artwork_value = dot(artwork.rgb, vec3(0.299, 0.587, 0.114)); // Uses luminance to preserve the design beneath the moving foil colours.
			float rainbow_phase = UV.x * 1.65 + UV.y * 1.15 + TIME * 0.075; // Moves a broad prismatic spectrum slowly across the sticker surface.
			vec3 rainbow = 0.58 + 0.42 * cos(6.2831853 * (rainbow_phase + vec3(0.00, 0.33, 0.67))); // Generates a smooth full-spectrum foil palette without a lookup texture.
			vec3 prismatic_albedo = mix(rainbow * 0.32, rainbow, smoothstep(0.04, 0.96, artwork_value)); // Uses artwork luminance to keep dark and light design regions legible inside the spectrum.
			prismatic_albedo = mix(prismatic_albedo, artwork.rgb, 0.16); // Retains a small amount of authored colour identity beneath the foil treatment.
			float foil_wave = 0.5 + 0.5 * sin((UV.x - UV.y * 0.62) * 42.0 + TIME * 1.35); // Adds fine moving iridescent bands that make the prismatic surface feel holographic.
			prismatic_albedo += rainbow * foil_wave * 0.16; // Brightens alternating foil bands with the local spectrum colour.
			float sweep_cycle = mod(TIME + 1.7, 4.1); // Gives rainbow its own recurring premium sweep cadence.
			float sweep_active = 1.0 - step(1.2, sweep_cycle); // Restricts the strongest shine to the active sweep interval.
			float sweep_progress = clamp(sweep_cycle / 1.2, 0.0, 1.0); // Normalizes prismatic sweep travel.
			float sweep_distance = abs(UV.x + UV.y * 0.58 - mix(-0.32, 1.86, sweep_progress)); // Moves the bright band across the same physical face diagonally.
			float sweep_core = (1.0 - smoothstep(0.0, 0.035, sweep_distance)) * sweep_active; // Creates the near-white central foil flash.
			float sweep_halo = (1.0 - smoothstep(0.025, 0.17, sweep_distance)) * sweep_active; // Creates a wide rainbow-reflection halo.
			prismatic_albedo += rainbow * sweep_halo * 0.26 + vec3(0.46) * sweep_core; // Makes the premium pass visibly travel across the holographic spectrum.
			prismatic_albedo *= 1.0 - scratch_darkening * 0.46; // Makes scratches visibly cut through the holographic laminate without obscuring the foil identity.
			ALBEDO = clamp(prismatic_albedo, vec3(0.0), vec3(1.0)); // Writes the animated prismatic face colour.
			METALLIC = 0.38; // Gives the holographic foil a reflective coated-metal feel without turning it into plain metal.
			ROUGHNESS = clamp(0.18 + micro_roughness * 0.16 + scratch_matte * 0.48 - sweep_core * 0.08, 0.05, 0.72); // Lets scratches create obvious rough bands through the otherwise glossy holographic surface.
			SPECULAR = clamp(0.91 - scratch_specular_loss * 0.54, 0.04, 1.0); // Makes scratched foil lose reflected highlight intensity sharply while clean foil stays bright.
			EMISSION = rainbow * (0.055 + foil_wave * 0.035) + vec3(0.92) * sweep_core * 0.24; // Makes the moving spectrum visible even under weak ambient lighting.
		} else { // Preserves the established printed-laminate response for ordinary copies.
			float fingerprint_gloss = smudge_strength * 0.18; // Makes oily-touch areas slightly glossier and smoother than untouched laminate.
			float scuff_matte = scuff_strength * 0.08; // Adds a faint extra roughness lift for generalized rub wear.
			vec3 front_albedo = artwork.rgb; // Uses the supplied sticker image directly without adding any generated colour or border.
			front_albedo *= 1.0 - scratch_darkening; // Darkens scratch channels strongly while preserving the supplied artwork everywhere the laminate remains intact.
			front_albedo += vec3(0.012) * fingerprint_gloss; // Gives smudged areas a faint cloudy lift that reads like natural skin-oil residue.
			ALBEDO = clamp(front_albedo, vec3(0.0), vec3(1.0)); // Writes the final heavily scratched but otherwise colour-faithful artwork.
			METALLIC = 0.0; // Keeps ordinary stickers as printed laminate rather than metal.
			ROUGHNESS = clamp(mix(0.34, 0.40, peel_region) + micro_roughness + scratch_matte + scuff_matte - fingerprint_gloss, 0.05, 0.98); // Lets scratch damage produce very strong roughness contrast against intact glossy laminate.
			SPECULAR = clamp(0.55 + fingerprint_gloss * 0.35 - scratch_specular_loss, 0.02, 0.95); // Lets scratches aggressively kill clean highlights while oily areas retain their independent gloss behavior.
			EMISSION = vec3(0.0); // Keeps ordinary artwork fully dependent on scene lighting.
		} // Completes front material selection.
	} else { // Selects the fibrous adhesive paper wherever the source artwork defines physical sticker material.
		NORMAL = -NORMAL; // Flips the shading normal so the reverse side receives light correctly.
		float paper_variation = 0.965 + 0.035 * sin(UV.x * 173.0 + UV.y * 229.0); // Adds a very small procedural paper variation without a second texture.
		float fiber_noise = fbm(detail_uv * 95.0 + vec2(2.8, -4.4)); // Adds faint fibrous grain so the reverse side is not perfectly uniform.
		ALBEDO = adhesive_color.rgb * paper_variation * (0.97 + 0.06 * fiber_noise); // Applies the warm adhesive-paper colour across the exact source-alpha silhouette.
		METALLIC = 0.0; // Keeps the adhesive reverse as paper regardless of the printed-front edition.
		ROUGHNESS = clamp(0.90 + (fiber_noise - 0.5) * 0.05, 0.0, 1.0); // Makes the sticker reverse substantially rougher than the printed face while adding slight tactile variation.
		SPECULAR = 0.18; // Keeps only a weak broad reflection on the adhesive surface.
		EMISSION = vec3(0.0); // Keeps the paper reverse fully lit by the scene.
	} // Completes front-versus-back material selection.
} // Completes sticker material shading.
