# Economy balance

Sticker-Shock uses the collector market as both the sticker resale system and the pricing authority for paid packs. The economy is intentionally tuned so buying packs and selling their contents is sustainable over long play rather than an unavoidable currency sink.

## Paid-pack target

`GuaranteedSpecialStickerEconomy` calculates the current expected resale value of the selected pack from the same live market quotes used by the collector exchange.

The calculation:

1. groups the current pack's pullable stickers by authored rarity;
2. averages the current normal-edition market quote within each represented rarity;
3. applies the same rarity weights used by actual pack generation, re-normalized around rarities present in that pack;
4. multiplies by the five-sticker pack size;
5. applies the exact expected-value contribution of random rainbow, silver, and gold editions;
6. divides the result by `PACK_TARGET_RESALE_RETURN`;
7. rounds downward to a readable five-pound price step.

`PACK_TARGET_RESALE_RETURN` is currently `1.12`. Before rounding, this means the pack's current expected resale value is targeted at 112% of its purchase price. Individual packs can still lose money because rarity and edition pulls are random, while sufficiently many packs should produce a positive average return when their contents are sold at the quoted market value.

The previous model multiplied expected resale value by `1.28` and then added a jackpot premium. That created a structural house edge: repeated buying and immediate selling necessarily drained player currency. The new model removes both that markup and the separate jackpot surcharge.

## Market crashes and rallies

Pack pricing follows the same live market multipliers as resale values. There is no longer a high fixed minimum pack price that can remain expensive while sticker resale values crash. The minimum paid-pack price is only the normal five-pound display step, while the existing `MAX_DYNAMIC_PACK_PRICE` still prevents extreme rallies from making a pack inaccessible.

Because purchase prices and resale quotes move from the same current market state, buying during a depressed market is not automatically punitive. Holding stickers and selling after favorable market movement can produce additional profit beyond the built-in long-run expected return.

## Special-edition guarantees

The lifetime guaranteed rainbow, silver, and gold pulls are not included in paid-pack pricing. Random edition probabilities are included because they are a permanent property of every pack; one-time milestone guarantees are treated as progression rewards and therefore provide extra value when reached.

Free packs continue to provide pure positive value and remain a recovery mechanism, but the paid economy no longer depends on waiting for free packs to avoid eventual bankruptcy.

## Future content

The model does not use a fixed monetary value for a pack. Adding new stickers or changing pack composition automatically changes the selected pack's expected resale calculation through current catalogue membership, rarity availability, and live market quotes. This keeps the economy aligned with future sticker additions without requiring a new hard-coded pack price.
