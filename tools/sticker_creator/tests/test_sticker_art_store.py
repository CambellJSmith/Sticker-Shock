from __future__ import annotations # Supports typed source-store regression fixtures.

import sys # Makes standalone tool modules available during repository-root discovery.
import json # Writes a pre-threshold recipe to verify upgrade behavior for existing authored stickers.
import unittest # Supplies dependency-free persistence regression tests.
from pathlib import Path # Creates isolated source and output directories.
from tempfile import TemporaryDirectory # Keeps generated fixtures outside repository artwork.
from unittest.mock import patch # Injects a write failure to verify rollback behaviour.

from PIL import Image, ImageDraw # Creates small deterministic source PNGs.

sys.path.insert(0, str(Path(__file__).resolve().parents[1])) # Matches the standalone launcher's module lookup.
from sticker_art_store import StickerArtStore, replace_files # Exercises the authoring store's public persistence API.
from sticker_border import ALPHA_THRESHOLD, BorderSettings # Supplies reproducible border recipes and the persisted cleanup marker.


class StickerArtStoreTests(unittest.TestCase): # Protects original pixels, edit idempotence, and complete save behaviour.
    def setUp(self) -> None: # Creates one isolated authoring workspace per test.
        temporary: TemporaryDirectory[str] = TemporaryDirectory() # Holds generated test content for automatic cleanup.
        self.addCleanup(temporary.cleanup) # Removes fixture files even after a failed assertion.
        self.root: Path = Path(temporary.name) # Provides a shared fixture root for source, runtime art, and recipes.
        self.source: Path = self.root / "input.png" # Represents the user's original external artwork.
        image: Image.Image = Image.new("RGBA", (64, 52)) # Provides transparent artwork with a clear silhouette.
        ImageDraw.Draw(image).ellipse((6, 4, 58, 48), fill="#b85b27") # Draws content whose output changes visibly with border settings.
        image.save(self.source) # Writes a known original PNG for byte-preservation checks.
        self.store: StickerArtStore = StickerArtStore(self.root / "source_art", self.root / "art") # Uses temporary roots instead of repository content.
        self.destination: Path = self.root / "art" / "000001_first.png" # Matches the runtime filename convention.
        self.settings: BorderSettings = BorderSettings(7, 5, "#abcdef") # Provides a nondefault recipe that must survive editing.

    def _save(self, settings: BorderSettings | None = None) -> None: # Imports the fixture through the same bundle API used by the tool.
        replace_files(self.store.prepare(1, self.source, self.destination, settings or self.settings)) # Publishes source, recipe, and runtime PNG together.

    def test_import_preserves_exact_original_and_recipe(self) -> None: # Verifies reversible authoring records are created with new artwork.
        original: bytes = self.source.read_bytes() # Captures the user's image before any processing.
        self._save() # Creates the bordered runtime output and authoring files.
        source_path, settings = self.store.load(1, self.destination) # Restores the editable original and cut recipe.
        self.assertEqual(source_path.read_bytes(), original) # Requires byte-for-byte original preservation.
        self.assertEqual(self.source.read_bytes(), original) # Ensures the external input file is never overwritten.
        self.assertEqual(settings, self.settings) # Restores colour, width, and smoothing exactly.
        self.assertNotEqual(self.destination.read_bytes(), original) # Confirms the game receives processed artwork rather than the preserved source.

    def test_recolour_and_repeated_edits_do_not_accumulate_borders(self) -> None: # Protects the physical silhouette against repeated authoring passes.
        self._save() # Creates the first bordered version from the unmodified source.
        new_settings: BorderSettings = BorderSettings(13, 9, "#5238ad") # Changes both cut geometry and colour for an edit.
        original_path, _settings = self.store.load(1, self.destination) # Opens the saved original for editing.
        replace_files(self.store.prepare(1, original_path, self.destination, new_settings, self.destination)) # Saves the changed border from original pixels.
        edited: bytes = self.destination.read_bytes() # Captures the correct once-generated result.
        fresh: Path = self.root / "art" / "000002_fresh.png" # Provides a separate destination for an equivalent fresh import.
        replace_files(self.store.prepare(2, self.source, fresh, new_settings)) # Generates the expected result directly from the same input.
        self.assertEqual(edited, fresh.read_bytes()) # Requires editing to match a fresh render exactly.
        replace_files(self.store.prepare(1, self.destination, self.destination, new_settings, self.destination)) # Exercises reselecting the tool-generated PNG itself.
        self.assertEqual(self.destination.read_bytes(), edited) # Prevents stacked borders or repeated quantization after reimport.

    def test_metadata_only_rename_reuses_output_and_stable_source(self) -> None: # Verifies renaming does not alter pixels or orphan authoring records.
        self._save() # Establishes an authored sticker with a stable source record.
        previous: bytes = self.destination.read_bytes() # Captures the exact PNG before a metadata-only rename.
        original_path, settings = self.store.load(1, self.destination) # Restores source and recipe for the edit.
        renamed: Path = self.root / "art" / "000001_renamed.png" # Changes only the runtime display-name portion of the filename.
        with patch("sticker_art_store.build_sticker_shape", side_effect=AssertionError("unexpected re-render")): # Requires unchanged edits to reuse exported pixels.
            replace_files(self.store.prepare(1, original_path, renamed, settings, self.destination), (self.destination,)) # Publishes the rename while retaining stable authoring identities.
        self.assertFalse(self.destination.exists()) # Removes the obsolete runtime filename after successful publication.
        self.assertEqual(renamed.read_bytes(), previous) # Preserves the exact exported PNG during metadata-only edits.
        self.assertEqual(self.store.load(1, renamed)[0], original_path) # Keeps the original source path independent of the sticker's name.

    def test_replacement_art_becomes_the_new_original(self) -> None: # Verifies future edits use newly selected source artwork.
        self._save() # Creates an initial authored sticker.
        replacement: Path = self.root / "replacement.png" # Represents a new user-selected illustration.
        Image.new("RGBA", (27, 41), "#24bd76").save(replacement) # Makes the replacement visibly and dimensionally distinct.
        replace_files(self.store.prepare(1, replacement, self.destination, self.settings, self.destination)) # Replaces runtime artwork and original source in one save.
        self.assertEqual(self.store.load(1, self.destination)[0].read_bytes(), replacement.read_bytes()) # Requires later border edits to start from the replacement pixels.

    def test_legacy_metadata_edit_writes_thresholded_runtime_art(self) -> None: # Upgrades existing runtime-only stickers while preserving their archived source bytes.
        self.destination.parent.mkdir(parents=True) # Creates a runtime-only legacy sticker without authoring records.
        original: bytes = self.source.read_bytes() # Captures the legacy PNG before the tool archives it.
        self.destination.write_bytes(original) # Represents the artwork saved by an earlier version of the tool.
        source_path, settings = self.store.load(1, self.destination) # Opens the legacy sticker for normal metadata editing.
        self.assertEqual(settings.width, 0) # Leaves the border disabled on legacy content by default.
        replace_files(self.store.prepare(1, source_path, self.destination, settings, self.destination)) # Archives the legacy original while saving the edit.
        archived_source, _recipe = self.store.paths(1) # Resolves the new stable source record after the upgrade.
        self.assertEqual(archived_source.read_bytes(), original) # Keeps the exact legacy input in the reversible source record.
        with Image.open(self.destination) as output: # Reopens the newly written runtime representation.
            self.assertTrue(all(value in {0, 255} for value in output.convert("RGBA").getchannel("A").getextrema())) # Requires binary alpha after the upgrade.

    def test_old_authored_recipe_is_reprocessed_with_binary_alpha(self) -> None: # Ensures authored stickers from before the cleanup marker are upgraded on edit.
        source_path, recipe_path = self.store.paths(1) # Resolves the stable authoring paths used by an older tool version.
        source_path.parent.mkdir(parents=True) # Creates the preserved source directory for the simulated record.
        image = Image.new("RGBA", (12, 12)) # Creates a compact source with one weak and one retained pixel.
        image.putpixel((3, 3), (210, 40, 70, ALPHA_THRESHOLD - 1)) # Supplies the partial alpha that old output could retain.
        image.putpixel((8, 8), (210, 40, 70, 255)) # Keeps one visible pixel so the sticker remains valid.
        image.save(source_path) # Stores the original bytes exactly as an old authoring record would.
        recipe_path.write_text(json.dumps({"version": 1, "border": {"width": 0, "smoothing": 5, "colour": "#abcdef"}}), encoding="utf-8") # Omits the new cleanup marker to represent old metadata.
        self.destination.parent.mkdir(parents=True) # Creates the runtime directory for the simulated old export.
        self.destination.write_bytes(source_path.read_bytes()) # Starts from an old runtime PNG that has not been normalized.
        replace_files(self.store.prepare(1, source_path, self.destination, BorderSettings(0, 5, "#abcdef"), self.destination)) # Rebuilds the old record from its preserved source.
        with Image.open(self.destination) as output: # Reads the edited runtime PNG after processing.
            self.assertTrue(all(value in {0, 255} for value in output.convert("RGBA").getchannel("A").getextrema())) # Requires weak source alpha to be removed.
        recipe = json.loads(recipe_path.read_text(encoding="utf-8")) # Reads the upgraded recipe marker.
        self.assertEqual(recipe["alpha_threshold"], ALPHA_THRESHOLD) # Records that future metadata-only edits can safely reuse the output.

    def test_missing_original_and_empty_art_leave_existing_files_untouched(self) -> None: # Prevents destructive fallbacks when a new render cannot be built safely.
        self._save() # Creates a valid original, recipe, and runtime output.
        previous: bytes = self.destination.read_bytes() # Records the working PNG before failure cases.
        missing_source, _recipe = self.store.paths(1) # Locates the source record required for reversible edits.
        missing_source.unlink() # Simulates an incomplete authoring checkout.
        with self.assertRaisesRegex(ValueError, "original artwork is missing"): # Requires explicit source recovery rather than border stacking.
            self.store.load(1, self.destination) # Attempts to reopen a sticker whose preserved original is absent.
        empty: Path = self.root / "empty.png" # Provides unusable replacement artwork.
        Image.new("RGBA", (10, 10)).save(empty) # Writes an entirely transparent input fixture.
        with self.assertRaises(ValueError): # Requires failed processing to occur before file publication.
            self.store.prepare(2, empty, self.destination, self.settings) # Attempts a replacement without invoking the transaction writer.
        self.assertEqual(self.destination.read_bytes(), previous) # Leaves the working exported sticker intact after both failures.

    def test_save_rolls_back_all_completed_replacements_on_failure(self) -> None: # Checks the multi-file consistency risk introduced by preserving authoring records.
        self._save() # Establishes a complete valid sticker bundle.
        definition: Path = self.root / "definition.tres" # Represents runtime metadata updated with an edited image.
        definition.write_bytes(b"old definition") # Gives the transaction existing metadata to preserve.
        files: dict[Path, bytes] = self.store.prepare(1, self.source, self.destination, BorderSettings(4, 3, "#1188ee")) # Builds a changed authoring bundle without publishing it.
        files[definition] = b"new definition" # Adds a final destination that will trigger the simulated failure.
        before: dict[Path, bytes] = {path: path.read_bytes() for path in files} # Captures all previous files for exact rollback checks.
        original_replace = Path.replace # Preserves the real replacement operation for all other destinations.
        def fail_definition(path: Path, target: Path) -> Path: # Injects failure only after earlier bundle files have been replaced.
            if target == definition: # Targets the final runtime metadata publication.
                raise OSError("simulated save failure") # Forces the transaction down its rollback path.
            return original_replace(path, target) # Lets preceding source, recipe, and image replacements complete normally.
        with patch.object(Path, "replace", fail_definition), self.assertRaises(OSError): # Verifies the original failure is reported after restoration.
            replace_files(files) # Attempts the full edited-sticker save.
        self.assertEqual({path: path.read_bytes() for path in files}, before) # Requires exact previous bytes across the entire bundle.
        self.assertFalse(list(self.root.rglob("*.tmp"))) # Ensures failed transactions leave no staged image files behind.

    def test_deletion_removes_original_recipe_and_runtime_art(self) -> None: # Keeps deletion and later ID reuse consistent with authoring persistence.
        self._save() # Creates all authoring and runtime files for one sticker.
        paths: tuple[Path, ...] = (*self.store.paths(1), self.destination) # Lists this sticker's complete artwork bundle.
        replace_files({}, paths) # Deletes the bundle through the same transaction helper as the UI.
        self.assertTrue(all(not path.exists() for path in paths)) # Prevents a reused ID from inheriting a deleted sticker's border recipe.


if __name__ == "__main__": # Supports direct execution while developing authoring persistence.
    unittest.main() # Runs the source-store regression suite.
