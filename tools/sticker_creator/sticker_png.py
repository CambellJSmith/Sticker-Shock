from __future__ import annotations # Enables consistent annotations throughout the image pipeline.

from io import BytesIO # Encodes complete PNGs before any destination is replaced.

import numpy as np # Assigns reserved palette entries with vectorized indexing.
from numpy.typing import NDArray # Types pixel and palette buffers explicitly.
from PIL import Image, ImageColor # Provides palette conversion and colour parsing.

from sticker_border import StickerShape # Shares the physical cut mask between preview and export.


def quantize_image(image: Image.Image, colours: int = 256) -> Image.Image: # Retains the established best-available RGBA quantization path.
    rgba: Image.Image = image.convert("RGBA") # Makes both quantization backends accept the same input format.
    try: # Prefers the higher-quality optional Pillow backend when installed.
        return rgba.quantize(colors=colours, method=Image.Quantize.LIBIMAGEQUANT, dither=Image.Dither.FLOYDSTEINBERG) # Reduces colours while including transparency in the palette.
    except (ValueError, AttributeError): # Supports standard Pillow wheels without libimagequant.
        return rgba.quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG) # Uses Pillow's compiled RGBA fallback.


def sticker_palette(shape: StickerShape, colour: str) -> Image.Image: # Preserves exact backing colour and clean edge alpha within the existing palette limit.
    composite: Image.Image = shape.composite(colour) # Places the unfiltered artwork over its chosen backing before colour reduction.
    if not shape.has_border: # Leaves border-free images on the original export path.
        return quantize_image(composite) # Quantizes the complete source image with the full palette budget.
    quantized: Image.Image = quantize_image(composite, 224) # Reserves palette space for the cut edge's colour and transparency ramp.
    pixels: NDArray[np.uint8] = np.array(quantized) # Copies palette indices for safe remapping of backing-only pixels.
    backing_only: NDArray[np.bool_] = np.asarray(shape.artwork.getchannel("A")) == 0 # Keeps artwork pixels out of colour-based border detection.
    alpha: NDArray[np.uint16] = np.asarray(shape.backing, dtype=np.uint16) # Uses wider arithmetic to prevent overflow during alpha quantization.
    pixels[backing_only] = (224 + (alpha[backing_only] * 31 + 127) // 255).astype(np.uint8) # Gives the border evenly spaced alpha levels with exact transparent and opaque endpoints.
    rgba_palette: list[int] = list(quantized.getpalette("RGBA") or [])[:224 * 4] # Retains the quantizer's artwork colours and alpha entries.
    rgba_palette.extend([0] * (224 * 4 - len(rgba_palette))) # Pads unused artwork entries before the reserved border range.
    rgb: tuple[int, int, int] = ImageColor.getrgb(colour) # Decodes the exact user-selected backing colour.
    for index in range(32): # Builds a small palette ramp rather than recolouring pixels one at a time.
        rgba_palette.extend((*rgb, round(index * 255 / 31))) # Keeps RGB constant across the cut edge to avoid dark halos.
    result: Image.Image = Image.fromarray(pixels).convert("P") # Creates an indexed output whose pixel values already address the final palette.
    result.putpalette(rgba_palette, rawmode="RGBA") # Installs both original artwork and reserved border palette entries.
    return result # Supplies the exact same final image to preview and disk export.


def png_bytes(image: Image.Image) -> bytes: # Produces a complete optimized PNG suitable for transactional saving.
    buffer: BytesIO = BytesIO() # Holds encoded image data without creating a partially written destination.
    image.save(buffer, format="PNG", optimize=True) # Preserves palette transparency in the saved PNG.
    return buffer.getvalue() # Returns immutable encoded content for file replacement.
