class_name MarketPricedShopHUD
extends ShopHUD

func refresh() -> void: # Reuses the complete shop refresh, then replaces the obsolete fixed-price explanation with live-market context.
	super.refresh() # Updates reveal state, affordability, pack selector, free cooldown, and code controls through the established shop logic.
	if _economy == null or _catalog == null or _shop_world == null or _shop_world.has_reward_reveal(): # Leaves startup and reveal-only copy entirely to the base implementation.
		return # Avoids overwriting unrelated status text before normal acquisition offers are active.
	if _catalog.get_pack_names().is_empty(): # Preserves the established no-content explanation when no purchasable pack exists.
		return # Leaves the base error text visible.
	var missing_pounds: int = maxi(_economy.get_pack_price() - _economy.get_currency(), 0) # Reads affordability against the selected pack's current live-market price.
	(%standard_detail as Label).text = "need £%d more" % missing_pounds if missing_pounds > 0 else "%d stickers · price follows live market value" % _economy.get_pack_size() # Explains that authored packs can now have different changing prices.
