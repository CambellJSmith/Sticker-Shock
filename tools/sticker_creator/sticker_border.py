from __future__ import annotations # Allows typed helpers to refer to their own classes.

import re # Validates explicit RGB colour values.
from dataclasses import dataclass # Keeps border recipes immutable across UI and worker threads.

import numpy as np # Performs mask arithmetic without Python pixel loops.
from numpy.typing import NDArray # Describes the dense mask buffers passed between processing steps.
from PIL import Image, ImageColor # Loads artwork and decodes the chosen backing colour.
from scipy import ndimage # Supplies compiled Euclidean distance and smoothing operations.


@dataclass(frozen=True) # Makes a submitted border recipe safe to share with background work.
class BorderSettings: # Describes the cut geometry independently of the source artwork.
    width: int = 12 # Controls the minimum outward growth in source-image pixels.
    smoothing: int = 8 # Controls the scale of jagged detail removed from the cut line.
    colour: str = "#ffffff" # Stores the opaque backing colour as an RGB hex string.

    def __post_init__(self) -> None: # Rejects invalid recipes before allocating image buffers.
        if type(self.width) is not int or not 0 <= self.width <= 256: # Bounds growth while allowing an explicitly disabled border.
            raise ValueError("border width must be a whole number from 0 to 256 pixels") # Explains how to correct the width field.
        if type(self.smoothing) is not int or not 1 <= self.smoothing <= 128: # Keeps enabled cut outlines smoothed and bounds filter work.
            raise ValueError("edge smoothing must be a whole number from 1 to 128 pixels") # Explains how to correct the smoothing field.
        if not isinstance(self.colour, str) or re.fullmatch(r"#[0-9a-fA-F]{6}", self.colour) is None: # Accepts unambiguous opaque RGB colours only.
            raise ValueError("border colour must be a hex colour such as #ffffff") # Gives an example of valid colour syntax.
        object.__setattr__(self, "colour", self.colour.lower()) # Normalizes equivalent colours for recipe comparison and caching.


@dataclass(frozen=True) # Keeps the reusable cut mask separate from colour and palette conversion.
class StickerShape: # Holds the original pixels aligned with their smoothed backing.
    artwork: Image.Image # Retains the untouched artwork on its final expanded canvas.
    backing: Image.Image # Stores the antialiased physical silhouette as an alpha mask.
    has_border: bool # Distinguishes disabled borders from a generated backing.

    def composite(self, colour: str) -> Image.Image: # Recolours the backing without repeating the expensive cut calculation.
        if not self.has_border: # Preserves the original transparency when the border is disabled.
            return self.artwork.copy() # Returns a caller-owned image suitable for palette conversion.
        background: Image.Image = Image.new("RGBA", self.artwork.size, ImageColor.getrgb(colour) + (0,)) # Creates a uniform backing in the requested colour.
        background.putalpha(self.backing) # Uses the smoothed cut edge as the physical sticker silhouette.
        return Image.alpha_composite(background, self.artwork) # Places the original artwork over its opaque backing without filtering the art.


def build_sticker_shape(source: Image.Image, settings: BorderSettings) -> StickerShape: # Grows and smooths a cut outline while preserving every visible source pixel.
    artwork: Image.Image = source.convert("RGBA") # Normalizes indexed and RGB PNG inputs without resizing their artwork.
    if artwork.getchannel("A").getbbox() is None: # Detects empty artwork before invoking distance transforms.
        raise ValueError("the PNG is fully transparent; choose artwork with visible pixels") # Reports an unusable sticker image.
    if settings.width == 0: # Supports legacy stickers and deliberate border-free imports.
        return StickerShape(artwork, artwork.getchannel("A"), False) # Keeps the original canvas and alpha intact.
    padding: int = settings.width + settings.smoothing * 4 + 4 # Leaves room for outward smoothing compensation and transparent edge pixels.
    canvas_size: tuple[int, int] = (artwork.width + padding * 2, artwork.height + padding * 2) # Expands both axes without stretching the source image.
    if canvas_size[0] * canvas_size[1] > 25_000_000: # Bounds peak memory used by native distance-transform buffers.
        raise ValueError("the bordered image is too large; reduce the artwork resolution or border settings") # Offers a practical correction before expensive allocation.
    padded_art: Image.Image = Image.new("RGBA", canvas_size) # Creates transparent space for the complete cut outline.
    padded_art.paste(artwork, (padding, padding)) # Copies pixels directly instead of applying alpha twice.
    visible: NDArray[np.bool_] = np.asarray(padded_art.getchannel("A")) > 0 # Includes faint and isolated artwork pixels in the coverage guarantee.
    filled: NDArray[np.bool_] = ndimage.binary_fill_holes(visible) # Makes enclosed gaps solid backing while retaining exterior concavities.
    outside: NDArray[np.float32] = ndimage.distance_transform_edt(~filled).astype(np.float32) # Measures circular growth instead of square-kernel dilation.
    required: NDArray[np.bool_] = outside <= settings.width # Records the complete minimum-width backing that smoothing must enclose.
    signed: NDArray[np.float32] = outside - ndimage.distance_transform_edt(filled).astype(np.float32) # Describes the cut boundary as a continuous signed distance field.
    del outside # Releases the intermediate distance buffer before smoothing.
    smooth: NDArray[np.float32] = ndimage.gaussian_filter(signed, sigma=settings.smoothing, mode="nearest") # Removes fine teeth and notches without blurring the artwork itself.
    del signed # Releases the unsmoothed field before output composition.
    level: float = max(float(settings.width), float(smooth[required].max()) + 1.0) # Moves the smooth contour outward enough to cover the full grown silhouette.
    alpha: NDArray[np.uint8] = np.rint(np.clip(level - smooth + 0.5, 0.0, 1.0) * 255.0).astype(np.uint8) # Sharpens the smoothed field into a clean antialiased cut edge.
    backing: Image.Image = Image.fromarray(alpha) # Converts the final cut mask back into a compact Pillow image.
    bounds: tuple[int, int, int, int] | None = backing.getbbox() # Finds actual backing bounds after the conservative working padding.
    if bounds is None: # Guards against an invalid intermediate mask rather than creating an empty sticker.
        raise ValueError("could not create a cut outline for this artwork") # Leaves file creation to the caller only after a valid result exists.
    left: int = min(padding, bounds[0] - 2) # Retains the complete original canvas plus a transparent sampling margin.
    top: int = min(padding, bounds[1] - 2) # Avoids discarding source padding or clipping the upper cut edge.
    right: int = max(padding + artwork.width, bounds[2] + 2) # Retains the original image extent while removing unused working space.
    bottom: int = max(padding + artwork.height, bounds[3] + 2) # Leaves transparent pixels around the lower cut edge.
    crop: tuple[int, int, int, int] = (left, top, right, bottom) # Applies identical geometry to artwork and backing.
    return StickerShape(padded_art.crop(crop), backing.crop(crop), True) # Returns reusable cut geometry without changing the source illustration.
