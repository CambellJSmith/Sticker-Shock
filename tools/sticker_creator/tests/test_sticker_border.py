from __future__ import annotations # Allows consistent type annotations in regression fixtures.

import sys # Makes the standalone tool modules importable from repository-root test discovery.
import unittest # Runs image regressions without adding another test dependency.
from io import BytesIO # Verifies encoded PNG output rather than only in-memory images.
from pathlib import Path # Resolves the standalone tool directory.

import numpy as np # Measures silhouette coverage and contour roughness directly.
from PIL import Image, ImageDraw # Builds deterministic artwork fixtures without external assets.
from scipy import ndimage # Measures minimum backing coverage independently of the processor's output.

sys.path.insert(0, str(Path(__file__).resolve().parents[1])) # Loads the tool in the same way as its launcher.
from sticker_border import ALPHA_THRESHOLD, BorderSettings, build_sticker_shape, threshold_alpha # Exercises the public geometry API.
from sticker_png import png_bytes, sticker_palette # Exercises final exported palette and transparency.


class StickerBorderTests(unittest.TestCase): # Checks visual invariants that matter to physical sticker behaviour.
    def test_jagged_edges_are_smoothed_without_losing_artwork(self) -> None: # Verifies cleanup of repeated teeth without changing source pixels.
        source: Image.Image = Image.new("RGBA", (280, 160)) # Creates a transparent fixture with a long toothed top edge.
        drawing: ImageDraw.ImageDraw = ImageDraw.Draw(source) # Draws source detail independently of the border algorithm.
        drawing.rectangle((20, 40, 259, 139), fill="#b45628") # Creates the body of the sticker.
        for x in range(20, 260, 12): # Adds regularly spaced sharp teeth along the artwork edge.
            drawing.polygon(((x, 40), (x + 5, 23), (x + 10, 40)), fill="#b45628") # Creates rough detail that simple growth can retain.
        rough = build_sticker_shape(source, BorderSettings(3, 1)) # Produces a lightly smoothed comparison at the same requested width.
        smooth = build_sticker_shape(source, BorderSettings(3, 12)) # Requests strong cut cleanup without changing the artwork.
        rough_top = np.argmax(np.asarray(rough.backing) >= 128, axis=0)[60:220] # Measures the upper cut contour away from end corners.
        smooth_top = np.argmax(np.asarray(smooth.backing) >= 128, axis=0)[60:220] # Measures the same central portion of the cleaned outline.
        self.assertLess(np.abs(np.diff(smooth_top)).sum(), np.abs(np.diff(rough_top)).sum() / 3) # Requires a substantial reduction in teeth along the physical cut edge.
        source_visible = np.asarray(source)[np.asarray(source.getchannel("A")) > 0] # Collects the original visible pixel colours in source order.
        result_visible = np.asarray(smooth.artwork)[np.asarray(smooth.artwork.getchannel("A")) > 0] # Reads source pixels copied into the expanded canvas.
        np.testing.assert_array_equal(source_visible, result_visible) # Confirms smoothing never resamples or edits the actual illustration.

    def test_grown_backing_covers_thin_spikes_and_faint_pixels(self) -> None: # Verifies even extreme artwork points stay inside the finished border.
        source: Image.Image = Image.new("RGBA", (96, 96)) # Creates a compact fixture that touches its source canvas edge.
        drawing: ImageDraw.ImageDraw = ImageDraw.Draw(source) # Creates an isolated thin point and a mostly opaque body.
        drawing.polygon(((0, 0), (90, 40), (38, 90)), fill="#376fab") # Includes a sharp corner that smoothing must enclose.
        source.putpixel((95, 95), (255, 0, 0, 1)) # Includes a faint separated pixel in the visible coverage contract.
        shape = build_sticker_shape(source, BorderSettings(9, 20)) # Exercises outward compensation with smoothing stronger than the width.
        visible = np.asarray(shape.artwork.getchannel("A")) > 0 # Locates every artwork pixel in final canvas coordinates.
        distance = ndimage.distance_transform_edt(~visible) # Independently measures circular distance from all original artwork.
        self.assertTrue(np.all(np.asarray(shape.backing)[distance <= 9] == 255)) # Requires a fully opaque minimum backing width around every visible point.
        alpha = np.asarray(shape.backing) # Reads the resulting physical silhouette at the expanded image edges.
        self.assertFalse(np.any(alpha[[0, -1], :])) # Requires transparent top and bottom sampling margins.
        self.assertFalse(np.any(alpha[:, [0, -1]])) # Requires transparent left and right sampling margins.

    def test_enclosed_holes_fill_but_large_outer_notches_remain(self) -> None: # Distinguishes solid paper backing from an indiscriminate convex hull.
        source: Image.Image = Image.new("RGBA", (200, 180)) # Provides room for a large exterior indentation and an enclosed hole.
        drawing: ImageDraw.ImageDraw = ImageDraw.Draw(source) # Builds a deterministic concave artwork shape.
        drawing.rectangle((20, 20, 180, 160), fill="#558c39") # Starts from an opaque sticker body.
        drawing.rectangle((75, 0, 125, 100), fill=(0, 0, 0, 0)) # Cuts a broad notch connected to the outer background.
        drawing.ellipse((35, 110, 60, 135), fill=(0, 0, 0, 0)) # Adds a small enclosed transparent hole.
        shape = build_sticker_shape(source, BorderSettings(5, 3)) # Applies moderate growth without erasing the large concavity.
        self.assertEqual(shape.backing.getpixel((47, 122)), 255) # Requires solid backing underneath an enclosed artwork hole.
        self.assertEqual(shape.backing.getpixel((100, 35)), 0) # Retains the deep exterior notch as outside the sticker.

    def test_border_colour_and_antialias_survive_png_encoding(self) -> None: # Checks final file pixels rather than trusting quantizer settings.
        source: Image.Image = Image.new("RGBA", (80, 80)) # Provides an irregular opaque body inside a transparent image.
        ImageDraw.Draw(source).polygon(((12, 65), (40, 9), (70, 63)), fill="#ce4729") # Creates diagonal cut edges that need antialiasing.
        shape = build_sticker_shape(source, BorderSettings(7, 5, "#29b6d4")) # Generates a nonwhite backing to expose colour drift.
        encoded: bytes = png_bytes(sticker_palette(shape, "#29b6d4")) # Runs the complete export path including PNG palette transparency.
        with Image.open(BytesIO(encoded)) as png: # Reopens the actual saved representation.
            self.assertEqual(png.mode, "P") # Requires indexed output compatible with the existing artwork pipeline.
            self.assertLessEqual(len(png.getcolors()), 256) # Enforces the project's colour budget after adding the border.
            pixels = np.asarray(png.convert("RGBA")) # Reads decoded RGBA pixels for visual invariants.
        border_only = np.asarray(shape.artwork.getchannel("A")) == 0 # Selects border pixels by source alpha rather than their colour.
        visible_border = border_only & (pixels[:, :, 3] > 0) # Excludes fully transparent pixels from RGB assertions.
        self.assertTrue(np.all(pixels[visible_border, :3] == (41, 182, 212))) # Requires the exact selected colour across both opaque and antialiased border pixels.
        self.assertTrue(np.any((pixels[:, :, 3] > 0) & (pixels[:, :, 3] < 255))) # Requires a clean partial-alpha transition at the cut edge.
        self.assertTrue(np.all(pixels[:, :, 3][np.asarray(shape.artwork.getchannel("A")) > 0] == 255)) # Keeps all source pixels enclosed by opaque paper after quantization.

    def test_alpha_threshold_keeps_half_opaque_pixels_and_removes_weaker_pixels(self) -> None: # Protects the exact binary silhouette rule at both sides of its boundary.
        source: Image.Image = Image.new("RGBA", (3, 1)) # Creates one pixel below, at, and above the threshold.
        source.putpixel((0, 0), (34, 82, 140, ALPHA_THRESHOLD - 1)) # Supplies a nearly transparent pixel that must disappear.
        source.putpixel((1, 0), (34, 82, 140, ALPHA_THRESHOLD)) # Supplies the exact half-opaque boundary that must remain.
        source.putpixel((2, 0), (34, 82, 140, 255)) # Supplies an already opaque pixel that must remain unchanged.
        cleaned = threshold_alpha(source) # Applies the same cleanup used by preview and export.
        self.assertEqual(cleaned.getpixel((0, 0)), (0, 0, 0, 0)) # Requires removed pixels to be fully transparent, including hidden RGB.
        self.assertEqual(cleaned.getpixel((1, 0)), (34, 82, 140, 255)) # Requires the threshold boundary to become fully opaque.
        self.assertEqual(cleaned.getpixel((2, 0)), (34, 82, 140, 255)) # Preserves already opaque artwork exactly.
        self.assertEqual(source.getpixel((0, 0)), (34, 82, 140, ALPHA_THRESHOLD - 1)) # Confirms cleanup does not mutate the user's source image.

    def test_border_disabled_uses_thresholded_alpha_and_preserves_canvas(self) -> None: # Protects the explicit no-border choice while enforcing binary source alpha.
        source: Image.Image = Image.new("RGBA", (43, 37)) # Creates a source with intentional transparent padding.
        source.putpixel((21, 18), (34, 82, 140, 93)) # Gives the source a weak semitransparent pixel that must be removed.
        source.putpixel((22, 18), (34, 82, 140, 200)) # Gives the source a stronger pixel that must become fully opaque.
        shape = build_sticker_shape(source, BorderSettings(width=0)) # Requests no additional backing or canvas expansion.
        self.assertFalse(shape.has_border) # Records that border processing was explicitly disabled.
        self.assertEqual(shape.composite("#ff0000").getpixel((21, 18)), (0, 0, 0, 0)) # Removes below-threshold artwork from border-free output.
        self.assertEqual(shape.composite("#ff0000").getpixel((22, 18)), (34, 82, 140, 255)) # Makes retained border-free artwork fully opaque.
        self.assertEqual(shape.artwork.size, source.size) # Preserves intentional original padding exactly.
        self.assertEqual(source.getpixel((21, 18)), (34, 82, 140, 93)) # Keeps the caller's original pixels untouched.

    def test_opaque_rgb_and_indexed_pngs_are_supported(self) -> None: # Covers common PNG modes accepted by the existing importer.
        for mode in ("RGB", "P"): # Exercises opaque colour images and indexed artwork.
            with self.subTest(mode=mode): # Reports each input format separately if it regresses.
                source: Image.Image = Image.new(mode, (30, 20)) # Provides fully opaque artwork touching every canvas edge.
                shape = build_sticker_shape(source, BorderSettings(4, 4)) # Adds rounded backing outside the original image rectangle.
                self.assertGreater(shape.artwork.width, source.width) # Requires expansion when artwork already touches the canvas edge.
                self.assertGreater(shape.artwork.height, source.height) # Prevents top and bottom border clipping for opaque inputs.

    def test_empty_and_invalid_inputs_are_rejected(self) -> None: # Keeps unusable images and malformed recipes out of saved game content.
        with self.assertRaisesRegex(ValueError, "fully transparent"): # Requires a clear error for an invisible sticker.
            build_sticker_shape(Image.new("RGBA", (8, 8)), BorderSettings()) # Exercises empty-alpha validation before distance transforms.
        for arguments in ({"width": -1}, {"width": 1.5}, {"smoothing": 0}, {"smoothing": 129}, {"colour": "red"}, {"colour": "#abc12388"}): # Includes invalid widths, smoothing values, and nonopaque colour syntax.
            with self.subTest(arguments=arguments), self.assertRaises(ValueError): # Requires each bad recipe to fail before a save can begin.
                BorderSettings(**arguments) # Exercises shared validation independently of Tk widgets.


if __name__ == "__main__": # Supports directly running this file while developing the border processor.
    unittest.main() # Executes the image regression suite.
