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
uniform vec2 surface_detail_offset = vec2(0.0); // Stores the stable per-copy handling seed offset derived from the physical sticker identity.
uniform float surface_detail_rotation = 0.0; // Stores the stable per-copy handling rotation derived from the physical sticker identity.

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

float fbm(vec2 p) { // Accumulates several frequencies of value noise for richer broad-scale handling variation.
	float total = 0.0; // Seeds the fractal sum.
	float amplitude = 0.5; // Seeds the first octave amplitude.
	for (int octave = 0; octave < 4; octave++) { // Uses a small fixed octave count to keep the handling texture inexpensive.
		total += noise2(p) * amplitude; // Adds the current octave to the accumulated fractal signal.
		p = p * 2.03 + vec2(13.1, 7.7); // Increases frequency and offsets the lattice to avoid octave alignment.
		amplitude *= 0.5; // Halves amplitude each octave for a standard fractal falloff.
	} // Completes octave accumulation.
	return total; // Returns the combined broad-to-fine fractal signal.
} // Completes fractal noise synthesis.

vec2 rotate_detail_uv(vec2 uv, float angle) { // Rotates the procedural handling space around the sticker center without affecting artwork placement.
	float sine_value = sin(angle); // Caches the handling-space sine once for efficient coordinate rotation.
	float cosine_value = cos(angle); // Caches the handling-space cosine once for the coordinate rotation.
	vec2 centered_uv = uv - vec2(0.5); // Moves the UV origin to sticker center before rotation.
	vec2 rotated_uv = vec2(centered_uv.x * cosine_value - centered_uv.y * sine_value, centered_uv.x * sine_value + centered_uv.y * cosine_value); // Applies a standard 2D rotation to the centered handling-space coordinate.
	return rotated_uv + vec2(0.5) + surface_detail_offset; // Restores center-relative coordinates and adds the stable per-copy translation seed.
} // Completes handling-space coordinate rotation.

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

void fragment() { // Shades the artwork-defined sticker surface, adhesive reverse, and oily handling residue.
	vec4 artwork = texture(sticker_texture, UV); // Samples the original artwork directly because its alpha is now the complete physical sticker silhouette.
	if (artwork.a < alpha_cutoff) { // Rejects every fragment the supplied artwork marks as transparent.
		discard; // Removes transparent image space from colour, depth, and shadow rendering.
	} // Completes source-alpha silhouette clipping.
	vec2 detail_uv = rotate_detail_uv(UV, surface_detail_rotation); // Builds the stable per-copy handling space that moves naturally with this physical sheet.
	float instance_seed_a = hash12(surface_detail_offset * vec2(13.71, 29.43) + vec2(surface_detail_rotation * 0.73, 4.17)); // Derives one stable per-copy random channel from the physical sticker identity.
	float instance_seed_b = hash12(surface_detail_offset * vec2(-37.11, 17.83) + vec2(9.31, surface_detail_rotation * 1.19)); // Derives an independent per-copy channel so broad grease does not move as one shared template.
	float instance_seed_c = hash12(surface_detail_offset * vec2(23.57, -41.29) + vec2(surface_detail_rotation * 1.61, -6.73)); // Derives an independent per-copy channel for secondary blotch structure and scale.
	float instance_seed_d = hash12(surface_detail_offset * vec2(-53.17, -11.97) + vec2(15.41, surface_detail_rotation * 2.03)); // Derives an independent per-copy channel for smudge density and fine detail.
	vec2 broad_offset = vec2(instance_seed_a * 31.0 - 15.5, instance_seed_b * 37.0 - 18.5); // Sends the broad grease layer to a distinct region of procedural space for this copy.
	vec2 secondary_offset = vec2(instance_seed_c * 43.0 - 21.5, instance_seed_a * 47.0 - 23.5); // Gives the secondary grease layer its own unrelated per-copy translation.
	vec2 smudge_offset = vec2(instance_seed_d * 53.0 - 26.5, instance_seed_c * 59.0 - 29.5); // Gives cloudy smudges their own unrelated per-copy translation.
	vec2 micro_offset = vec2(instance_seed_b * 67.0 - 33.5, instance_seed_d * 71.0 - 35.5); // Gives laminate microstructure a separate per-copy translation from all visible grease shapes.
	float broad_scale = mix(3.3, 6.2, instance_seed_c); // Varies the physical size of broad greasy regions between individual sticker copies.
	float secondary_scale = mix(7.6, 13.4, instance_seed_d); // Varies the size of medium oily blotches independently from the broad layer.
	float smudge_scale = mix(16.0, 28.0, instance_seed_b); // Varies cloudy handling-mark scale so duplicates do not share the same visual rhythm.
	float micro_scale = mix(62.0, 92.0, instance_seed_a); // Varies only fine laminate breakup without changing the authored artwork.
	float broad_grease_noise = fbm(detail_uv * broad_scale + broad_offset); // Creates a genuinely per-instance broad grease structure rather than a translated common pattern.
	float secondary_grease_noise = fbm(detail_uv * secondary_scale + secondary_offset); // Creates independent medium grease structure for this physical copy.
	float smudge_detail_noise = fbm(detail_uv * smudge_scale + smudge_offset); // Creates independent cloudy handling residue for this physical copy.
	float micro_surface_noise = fbm(detail_uv * micro_scale + micro_offset); // Creates independent fine laminate variation for this physical copy.
	float grease_blend = mix(0.54, 0.82, instance_seed_b); // Changes how much broad versus medium structure dominates each copy's oily residue.
	float grease_shape = mix(secondary_grease_noise, broad_grease_noise, grease_blend); // Combines independently seeded grease scales with a per-copy structural balance.
	float grease_threshold_low = mix(0.43, 0.54, instance_seed_d); // Varies how much of this copy is occupied by visible grease without changing its persistent identity.
	float grease_threshold_high = grease_threshold_low + mix(0.16, 0.25, instance_seed_c); // Varies edge softness and patch coverage while preserving a usable threshold range.
	float grease_strength = smoothstep(grease_threshold_low, grease_threshold_high, grease_shape) * mix(0.58, 1.0, smudge_detail_noise); // Produces per-copy oily patches whose position, size, density, and internal breakup all differ.
	float smudge_blend = mix(0.46, 0.74, instance_seed_a); // Changes the balance between medium blotches and fine cloudy residue on each physical copy.
	float smudge_shape = mix(smudge_detail_noise, secondary_grease_noise, smudge_blend); // Combines independently seeded layers into the softer smudge distribution.
	float smudge_threshold_low = mix(0.46, 0.57, instance_seed_c); // Varies cloudy smudge coverage independently from grease coverage.
	float smudge_threshold_high = smudge_threshold_low + mix(0.15, 0.23, instance_seed_b); // Varies cloudy smudge edge softness between individual copies.
	float smudge_strength = smoothstep(smudge_threshold_low, smudge_threshold_high, smudge_shape) * (1.0 - grease_strength * 0.55); // Produces distinct hazy handling residue around each copy's unique oily patches.
	float grease_gloss = grease_strength * mix(0.25, 0.36, instance_seed_a); // Gives individual copies modestly different oily gloss intensity without changing the material class.
	float grease_specular = grease_strength * mix(0.23, 0.34, instance_seed_d); // Gives individual copies modestly different highlight strength across their unique grease pattern.
	float smudge_haze = smudge_strength * mix(0.085, 0.135, instance_seed_b); // Gives cloudy marks a per-copy haze level while keeping them secondary to grease.
	float smudge_specular_loss = smudge_strength * mix(0.075, 0.125, instance_seed_c); // Gives cloudy marks a per-copy reflection suppression range.
	float micro_roughness = (micro_surface_noise - 0.5) * mix(0.060, 0.090, instance_seed_d); // Converts unique fine laminate grain into restrained per-copy roughness variation.
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
			ALBEDO = clamp(gold_albedo, vec3(0.0), vec3(1.0)); // Writes the animated gold base colour without imprinting handling marks into the artwork itself.
			METALLIC = 0.68; // Keeps the surface convincingly metallic while retaining enough diffuse energy for compatibility rendering.
			ROUGHNESS = clamp(0.16 + micro_roughness * 0.18 + smudge_haze * 0.75 - grease_gloss * 0.42 - shimmer_strength * 0.10, 0.035, 0.38); // Lets grease and cloudy handling residue alter only the local shininess of the premium gold finish.
			SPECULAR = clamp(0.88 + shimmer_strength * 0.10 + grease_specular * 0.30 - smudge_specular_loss * 0.35, 0.10, 1.0); // Makes oily gold patches catch stronger highlights while cloudy smudges soften them.
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
			silver_albedo += vec3(0.32, 0.36, 0.42) * sweep_halo + vec3(0.58) * sweep_core; // Makes the silver pass visually unmistakable.
			ALBEDO = clamp(silver_albedo, vec3(0.0), vec3(1.0)); // Writes the cool-metal artwork replacement without colouring the handling residue.
			METALLIC = 0.76; // Gives silver a slightly stronger metal response than gold.
			ROUGHNESS = clamp(0.14 + micro_roughness * 0.16 + smudge_haze * 0.72 - grease_gloss * 0.38 - sweep_core * 0.08, 0.03, 0.34); // Makes greasy and hazy splotches visibly alter the polished silver reflection.
			SPECULAR = clamp(0.94 + grease_specular * 0.20 - smudge_specular_loss * 0.30, 0.12, 1.0); // Gives greasy silver patches a stronger reflected highlight while hazier marks soften it.
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
			ALBEDO = clamp(prismatic_albedo, vec3(0.0), vec3(1.0)); // Writes the animated prismatic face colour without imprinting grease into the artwork.
			METALLIC = 0.38; // Gives the holographic foil a reflective coated-metal feel without turning it into plain metal.
			ROUGHNESS = clamp(0.18 + micro_roughness * 0.16 + smudge_haze * 0.72 - grease_gloss * 0.40 - sweep_core * 0.08, 0.035, 0.38); // Makes irregular handling residue visibly change the holographic surface shininess.
			SPECULAR = clamp(0.91 + grease_specular * 0.22 - smudge_specular_loss * 0.30, 0.12, 1.0); // Gives oily foil patches stronger highlights while cloudy smudges diffuse them.
			EMISSION = rainbow * (0.055 + foil_wave * 0.035) + vec3(0.92) * sweep_core * 0.24; // Makes the moving spectrum visible even under weak ambient lighting.
		} else { // Preserves the established printed-laminate response for ordinary copies.
			vec3 front_albedo = artwork.rgb; // Uses the supplied sticker image directly with no generated damage marks, dark channels, or grease colour.
			ALBEDO = front_albedo; // Keeps all handling residue out of the artwork colour so it appears only through reflected light.
			METALLIC = 0.0; // Keeps ordinary stickers as printed laminate rather than metal.
			ROUGHNESS = clamp(mix(0.34, 0.40, peel_region) + micro_roughness + smudge_haze - grease_gloss, 0.06, 0.72); // Creates clear soft-edged shiny grease patches and slightly hazier fingerprint-like smudges across the laminate.
			SPECULAR = clamp(0.55 + grease_specular - smudge_specular_loss, 0.18, 0.92); // Lets oily splotches catch stronger highlights while cloudy handling marks locally soften the reflection.
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