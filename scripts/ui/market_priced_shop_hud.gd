class_name MarketPricedShopHUD
extends ShopHUD

func refresh() -> void: # Reuses the complete shop refresh, then layers live-market pricing and rollover free-pack status onto the established controls.
	super.refresh() # Updates reveal state, affordability, pack selector, free availability, and code controls through the established shop logic.
	if _economy == null or _catalog == null or _shop_world == null or _shop_world.has_reward_reveal(): # Leaves startup and reveal-only copy entirely to the base implementation.
		return # Avoids overwriting unrelated status text before normal acquisition offers are active.
	if _catalog.get_pack_names().is_empty(): # Preserves the established no-content explanation when no purchasable pack exists.
		return # Leaves the base error text visible.
	var missing_pounds: int = maxi(_economy.get_pack_price() - _economy.get_currency(), 0) # Reads affordability against the selected pack's current live-market price.
	(%standard_detail as Label).text = "need £%d more" % missing_pounds if missing_pounds > 0 else "%d stickers · price follows live market value" % _economy.get_pack_size() # Explains that authored packs can now have different changing prices.
	_refresh_free_pack_bank_status() # Replaces the legacy single-cooldown wording with the current rollover bank count and timer.

func _refresh_free_pack_bank_status() -> void: # Presents stored free claims and the next six-hour accrual without coupling the base HUD to the banked economy subclass.
	if not _economy.has_method("get_free_pack_count") or not _economy.has_method("get_max_free_pack_count"): # Keeps compatibility with any future economy implementation that lacks rollover support.
		return # Leaves the base free-pack presentation unchanged for unsupported models.
	var banked_count: int = int(_economy.call("get_free_pack_count")) # Reads the authoritative number of currently stored free pack claims.
	var maximum_count: int = int(_economy.call("get_max_free_pack_count")) # Reads the configured rollover cap for concise player feedback.
	_free.disabled = banked_count <= 0 # Makes claiming depend on the stored bank rather than only a legacy ready timestamp.
	if banked_count >= maximum_count: # Detects the full rollover bank where accrual is intentionally paused.
		(%free_detail as Label).text = "%d / %d free packs banked · bank full" % [banked_count, maximum_count] # Makes the cap and paused accrual explicit.
		_free.text = "claim free pack · %d banked" % banked_count # Shows the remaining stored claims directly on the action.
		return # Avoids displaying a meaningless next-pack timer while accumulation is paused.
	var seconds_until_next: int = int(_economy.call("get_seconds_until_additional_free_pack")) if _economy.has_method("get_seconds_until_additional_free_pack") else _economy.get_free_pack_seconds_remaining() # Reads the next accrual timer even when a claim is already ready.
	if banked_count > 0: # Handles one or more ready packs while the bank still has capacity.
		(%free_detail as Label).text = "%d / %d free packs banked · next in %s" % [banked_count, maximum_count, UIFormat.duration(seconds_until_next)] # Shows both immediate inventory and continued rollover progress.
		_free.text = "claim free pack · %d banked" % banked_count # Makes repeated stored claims obvious without implying only one reward exists.
	else: # Handles an empty bank still counting toward its next free pack.
		(%free_detail as Label).text = "0 / %d banked · next free pack in %s" % [maximum_count, UIFormat.duration(seconds_until_next)] # Shows the rollover capacity even before the next reward matures.
		_free.text = "come back for your free pack" # Preserves the established unavailable-action wording while the timer runs.
