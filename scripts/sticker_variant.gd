class_name StickerVariant
extends RefCounted

const EDITION_NORMAL: int = 0 # Identifies an ordinary pulled copy with the authored printed finish.
const EDITION_RAINBOW: int = 1 # Identifies the prismatic rainbow special edition.
const EDITION_SILVER: int = 2 # Identifies the reflective silver-metal special edition.
const EDITION_GOLD: int = 3 # Identifies the rarest reflective gold-metal special edition.
const SPECIAL_SUFFIX: String = "|special" # Preserves the original special-edition suffix as the gold identity so existing saves remain compatible.
const RAINBOW_SUFFIX: String = "|rainbow" # Stores the prismatic edition independently in inventory, placement, and save data.
const SILVER_SUFFIX: String = "|silver" # Stores the silver edition independently in inventory, placement, and save data.
const RAINBOW_PULL_CHANCE: float = 0.01 # Gives an ordinary pack pull a one-percent chance to become rainbow when no milestone guarantee applies.
const SILVER_PULL_CHANCE: float = 0.005 # Gives an ordinary pack pull a half-percent chance to become silver when no milestone guarantee applies.
const GOLD_PULL_CHANCE: float = 0.001 # Gives an ordinary pack pull a tenth-percent chance to become gold when no milestone guarantee applies.

static func make_key(sticker_path: String, special: bool = false) -> String: # Preserves the previous API for old callers while mapping legacy special=true explicitly to gold.
	return make_edition_key(sticker_path, EDITION_GOLD if special else EDITION_NORMAL) # Keeps old authored and saved semantics stable during the multi-edition transition.

static func make_edition_key(sticker_path: String, edition: int) -> String: # Builds one persistent inventory identity without duplicating the authored sticker resource.
	match edition: # Maps the controlled edition value to its stable suffix.
		EDITION_RAINBOW: return sticker_path + RAINBOW_SUFFIX # Stores rainbow copies separately from every other finish.
		EDITION_SILVER: return sticker_path + SILVER_SUFFIX # Stores silver copies separately from every other finish.
		EDITION_GOLD: return sticker_path + SPECIAL_SUFFIX # Reuses the legacy special suffix so all existing gold copies remain valid.
		_: return sticker_path # Keeps normal copies represented by the original resource path exactly as before.

static func get_art_path(sticker_key: String) -> String: # Resolves the authored artwork path from any normal or special-edition copy identity.
	var edition: int = get_edition(sticker_key) # Reads the controlled suffix before removing anything from the path.
	match edition: # Removes only a recognized edition suffix.
		EDITION_RAINBOW: return sticker_key.trim_suffix(RAINBOW_SUFFIX) # Resolves rainbow identity back to the shared PNG.
		EDITION_SILVER: return sticker_key.trim_suffix(SILVER_SUFFIX) # Resolves silver identity back to the shared PNG.
		EDITION_GOLD: return sticker_key.trim_suffix(SPECIAL_SUFFIX) # Resolves legacy/current gold identity back to the shared PNG.
		_: return sticker_key # Leaves ordinary authored paths unchanged.

static func get_edition(sticker_key: String) -> int: # Returns the explicit finish represented by one persistent copy key.
	if sticker_key.ends_with(RAINBOW_SUFFIX): # Checks the prismatic suffix first.
		return EDITION_RAINBOW # Reports the rainbow edition.
	if sticker_key.ends_with(SILVER_SUFFIX): # Checks the silver suffix independently.
		return EDITION_SILVER # Reports the silver edition.
	if sticker_key.ends_with(SPECIAL_SUFFIX): # Treats every preexisting special key as gold for backward compatibility.
		return EDITION_GOLD # Reports the gold edition.
	return EDITION_NORMAL # Treats every authored resource path as the normal edition.

static func is_special(sticker_key: String) -> bool: # Reports whether one copy has any premium edition finish.
	return get_edition(sticker_key) != EDITION_NORMAL # Keeps existing special-aware guards working for rainbow, silver, and gold alike.

static func get_edition_name(sticker_key: String) -> String: # Returns the concise player-facing finish name for one exact copy.
	match get_edition(sticker_key): # Converts the controlled numeric finish into display text.
		EDITION_RAINBOW: return "rainbow" # Names the prismatic edition.
		EDITION_SILVER: return "silver" # Names the silver-metal edition.
		EDITION_GOLD: return "gold" # Names the rarest gold-metal edition.
		_: return "normal" # Names ordinary printed copies.

static func roll_random_edition(random_number_generator: RandomNumberGenerator) -> int: # Performs one mutually exclusive premium-edition roll using the configured exact probabilities.
	var roll: float = random_number_generator.randf() # Draws one shared zero-to-one value so edition chances cannot overlap on the same pull.
	if roll < GOLD_PULL_CHANCE: # Reserves the first tenth-percent interval for the rarest finish.
		return EDITION_GOLD # Awards gold at exactly the configured probability.
	if roll < GOLD_PULL_CHANCE + SILVER_PULL_CHANCE: # Extends the cumulative interval by the silver half-percent probability.
		return EDITION_SILVER # Awards silver independently from gold.
	if roll < GOLD_PULL_CHANCE + SILVER_PULL_CHANCE + RAINBOW_PULL_CHANCE: # Extends the cumulative interval by the rainbow one-percent probability.
		return EDITION_RAINBOW # Awards rainbow independently from the metallic finishes.
	return EDITION_NORMAL # Leaves every remaining pull as an ordinary printed copy.

static func apply_material(sticker_mesh: StickerMesh, sticker_key: String) -> void: # Applies the exact saved edition to an already configured sticker mesh without changing geometry or peel behavior.
	if sticker_mesh == null: # Rejects missing renderers before reading their material.
		return # Leaves invalid callers harmlessly unchanged.
	var material: ShaderMaterial = sticker_mesh.material_override as ShaderMaterial # Reads the per-copy shader material created by StickerMesh.configure.
	if material == null: # Protects against an unexpected renderer/material configuration.
		return # Leaves the mesh using its configured normal appearance.
	material.set_shader_parameter("edition", get_edition(sticker_key)) # Selects normal, rainbow, silver, or gold in the shared GPU shader.
