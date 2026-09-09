class_name SpecialEditionBookWorld
extends BookWorld

func begin_manual_placement(sticker_key: String, pending_index: int) -> bool: # Enters book placement mode for one normal or special copy selected from the collection.
	_clear_manual_preview() # Removes any stale temporary preview before composing the newly selected collected sticker.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the real imported PNG while preserving edition identity separately.
	var texture_resource: Resource = ResourceLoader.load(artwork_path, "Texture2D") # Loads the shared authored artwork through Godot's imported resource cache.
	if texture_resource is not Texture2D: # Rejects missing or incompatible artwork before changing world state.
		push_error("manual sticker texture could not be loaded: %s" % artwork_path) # Reports the exact invalid authored resource for debugging.
		return false # Leaves the book in normal interaction mode when preview composition cannot succeed.
	_manual_pending_index = pending_index # Stores the exact current pending index represented by this reserved collection copy.
	_manual_sticker_path = sticker_key # Preserves the normal-or-special identity for controller validation and persistent placement.
	_manual_sticker_size = _catalog.get_default_size(sticker_key) # Uses the catalogue's edition-normalized aspect-preserving physical dimensions.
	_manual_preview = StickerPlacementPreview.new() # Creates the temporary floating front-face sticker composition.
	_manual_preview.name = "manual_placement_preview" # Gives the runtime helper a readable scene-tree name.
	$world.add_child(_manual_preview) # Parents the preview into the book world so its world transform matches page coordinates directly.
	_manual_preview.configure(_manual_sticker_size, texture_resource as Texture2D, StickerVariant.is_special(sticker_key)) # Builds the exact sheet and applies the shiny gold-metal treatment when this reserved copy is special.
	_manual_physical_size = _manual_preview.get_physical_size() # Caches exact artwork bounds once so pointer movement never regenerates contour data.
	_hud.set_placing(true) # Shows the explicit escape route while the selected collection copy remains unresolved.
	_hud.set_status("move over a page · click to place") # Explains manual placement while making the canonical book orientation explicit.
	_update_manual_preview(get_viewport().get_mouse_position()) # Positions the newly created sticker immediately beneath the current pointer when possible.
	return true # Reports that the selected collection copy successfully entered manual book placement mode.

func _process(delta: float) -> void: # Advances the short post-placement delay before returning to the collection that initiated placement.
	if _return_to_shop_remaining < 0.0: # Skips all timer work when no manual placement has just been committed.
		return # Leaves ordinary book and peel processing entirely to their own components.
	_return_to_shop_remaining -= delta # Advances the existing post-slam visibility delay without adding another timer object.
	if _return_to_shop_remaining <= 0.0: # Detects when the newly placed sticker has had enough time to visibly complete its landing.
		_return_to_shop_remaining = -1.0 # Clears the one-shot transition timer before routing to another destination.
		_controller.show_collection() # Returns to the collection so the player can choose another available normal or special copy deliberately.

func _commit_manual_placement() -> void: # Converts the currently previewed collection sticker into authoritative persistent book state.
	if _manual_preview == null or not _manual_target_valid: # Rejects clicks while no collection copy is carried or its complete sheet does not fit on a page.
		return # Leaves the reserved copy untouched until the player chooses a valid physical target.
	var committed: bool = _controller.commit_manual_placement(_manual_pending_index, _manual_sticker_path, _manual_sticker_size, _manual_target_page, _manual_world_xz) # Lets the root coordinator validate exact edition identity and persist the physical placement atomically.
	if not committed: # Handles a stale pending index or any unexpected authoritative-state mismatch safely.
		_hud.set_status("could not place this sticker. try again.") # Reports that persistence rejected the physical commit.
		return # Keeps the preview active so the player does not silently lose a collected copy.
	_clear_manual_preview() # Removes the temporary floating sheet and projected guide because a real physical Sticker now owns the committed placement.
	_hud.set_status("stuck! returning to collection…") # Confirms the physical placement while the new sticker completes its bounce-and-slam.
	_return_to_shop_remaining = MANUAL_RETURN_DELAY # Reuses the established short landing delay before returning to the collection.

func _spawn_placement_record(placement: Dictionary, animate_landing: bool) -> void: # Recreates one persistent normal or special placement as a fully interactive physical Sticker node.
	var page_index: int = maxi(int(placement.get("page", 0)), 0) # Retrieves the absolute virtual page assigned to this persistent sticker copy.
	if StickerBookLayout.get_spread_index_for_page(page_index) != _active_spread_index: # Rejects hidden-spread placements before allocating textures, mesh, picking, or shader resources.
		return # Defers physical composition until the player opens the placement's virtual spread.
	var sticker_key: String = str(placement.get("path", "")) # Retrieves the edition-aware identity persisted for this physical copy.
	var artwork_path: String = StickerVariant.get_art_path(sticker_key) # Resolves the real imported artwork shared by normal and special editions.
	var texture_resource: Resource = ResourceLoader.load(artwork_path, "Texture2D") # Loads the artwork through Godot's resource-aware texture cache.
	if texture_resource is not Texture2D: # Rejects saved placements whose authored artwork is no longer available or compatible.
		push_error("saved sticker texture could not be loaded: %s" % artwork_path) # Reports the exact missing physical design for development diagnostics.
		return # Leaves the rest of the book usable instead of creating an invalid Sticker node.
	var sticker_size: Vector2 = Vector2(float(placement.get("size_x", 1.0)), float(placement.get("size_y", 1.0))) # Restores the exact original artwork physical dimensions.
	var stack_order: int = maxi(int(placement.get("stack", 0)), 0) # Restores the logical paper layer used by this physical sticker.
	var stack_height: float = StickerBookLayout.get_stack_height(stack_order) # Converts logical paper order into the exact flat world y position.
	var sticker: Sticker = SpecialEditionSticker.new() if StickerVariant.is_special(sticker_key) else Sticker.new() # Chooses the gold-metal visual component only for physical copies that were actually pulled special.
	sticker.name = str(placement.get("id", artwork_path.get_file().get_basename())) # Uses the stable physical placement identifier as the runtime node name when available.
	_sticker_root.add_child(sticker) # Parents the physical sticker under the dedicated book composition node.
	sticker.global_position = Vector3(float(placement.get("x", 0.0)), stack_height, float(placement.get("z", 0.0))) # Restores its persistent page-space position and paper layer.
	sticker.rotation_degrees.y = 0.0 # Restores every attached book sticker at its canonical source artwork orientation before peel geometry is configured.
	sticker.configure(sticker_size, texture_resource as Texture2D) # Builds picking, peel mesh, reverse material, landing outline, and the special front when applicable.
	sticker.set_stack_height(stack_height) # Synchronizes the Sticker component's autonomous landing and return height with persistent stack order.
	var placement_id: String = str(placement.get("id", "")) # Retrieves the stable physical identifier used for future movement saves.
	var runtime_id: int = sticker.get_instance_id() # Retrieves the runtime node key used for fast metadata lookup during pointer interaction.
	_sticker_ids[runtime_id] = placement_id # Associates the interactive node with its authoritative persistent physical record.
	_sticker_pages[runtime_id] = page_index # Associates the interactive node with its absolute virtual page so movement can persist page changes correctly.
	_sticker_stacks[runtime_id] = stack_order # Associates the interactive node with its current logical paper layer.
	_sticker_paths[runtime_id] = sticker_key # Preserves the exact normal-or-special identity so inspection can reproduce the correct material treatment.
	_stack_counter = maxi(_stack_counter, stack_order) # Ensures future grabs and new placements always rise above this restored sticker.
	if animate_landing: # Plays the requested physical arrival only for newly committed manual or auto-packed stickers.
		sticker.begin_new_sticker_landing(Vector2(sticker.global_position.x, sticker.global_position.z), stack_height) # Starts the little upward kick followed by the hard flat page slam.
