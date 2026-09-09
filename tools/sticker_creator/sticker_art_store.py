from __future__ import annotations # Supports typed authoring records and file transactions.

import json # Persists border settings separately from game resources.
import re # Recognizes numbered artwork exported by this tool.
from dataclasses import asdict # Serializes the immutable border settings consistently.
from io import BytesIO # Opens a stable snapshot of the original image during export.
from pathlib import Path # Keeps authoring paths platform independent.
from tempfile import NamedTemporaryFile # Stages complete files beside their destinations.

from PIL import Image # Decodes source artwork without modifying its original file.

from sticker_border import BorderSettings, StickerShape, build_sticker_shape # Shares border processing across every import and edit path.
from sticker_png import png_bytes, sticker_palette # Encodes the same palette output displayed in the preview.


def replace_files(files: dict[Path, bytes], remove: tuple[Path, ...] = ()) -> None: # Commits a sticker's related files together with rollback for ordinary write failures.
    affected: set[Path] = set(files) | set(remove) # Includes renamed and deleted files in the rollback snapshot.
    previous: dict[Path, bytes | None] = {path: path.read_bytes() if path.exists() else None for path in affected} # Preserves the last usable content before staging changes.
    staged: dict[Path, Path] = {} # Tracks temporary files for replacement and cleanup.
    changed: list[Path] = [] # Records only destinations actually mutated during the transaction.
    try: # Stages all outputs before changing any live sticker content.
        for path, content in files.items(): # Encodes source, recipe, processed art, and resource as one caller-supplied group.
            path.parent.mkdir(parents=True, exist_ok=True) # Creates authoring directories only when saving a sticker.
            with NamedTemporaryFile(dir=path.parent, prefix=".sticker_", suffix=".tmp", delete=False) as temporary: # Keeps replacement on the destination filesystem.
                staged[path] = Path(temporary.name) # Registers cleanup even if writing the staged content fails.
                temporary.write(content) # Completes each file before exposing it under its final name.
        for path, temporary_path in staged.items(): # Publishes successfully staged files using atomic per-file replacement.
            temporary_path.replace(path) # Prevents readers from seeing partially encoded PNGs or resources.
            changed.append(path) # Records this destination for restoration if a later operation fails.
        for path in remove: # Removes obsolete names only after the replacement files exist.
            if path not in files and path.exists(): # Protects destinations retained by the new transaction.
                path.unlink() # Removes an old generated path or deleted sticker's authoring record.
                changed.append(path) # Includes completed deletions in rollback.
    except OSError: # Restores the previous usable state after a failed write or rename.
        for path in reversed(changed): # Reverses the completed mutations in their opposite order.
            old_content: bytes | None = previous[path] # Retrieves the exact bytes that existed before this save.
            if old_content is None: # Detects a newly created destination without earlier content.
                path.unlink(missing_ok=True) # Removes the incomplete new sticker output.
            else: # Restores an existing sticker instead of losing it during an edit.
                path.write_bytes(old_content) # Restores original source, recipe, artwork, or metadata bytes.
        raise # Preserves the original failure for the tool's error display.
    finally: # Cleans temporary output for both successful and failed transactions.
        for temporary_path in staged.values(): # Visits only temporary files created by this transaction.
            temporary_path.unlink(missing_ok=True) # Removes any staged file that was not consumed by replacement.


class StickerArtStore: # Owns original artwork and border recipes independently of the game catalogue.
    def __init__(self, source_root: Path, art_root: Path) -> None: # Receives explicit roots so authoring can also be tested in isolation.
        self.source_root: Path = source_root # Stores original PNGs outside the runtime sticker discovery folder.
        self.art_root: Path = art_root # Identifies tool-generated game artwork when it is selected again.

    def paths(self, sticker_id: int) -> tuple[Path, Path]: # Uses stable numeric identities rather than display names for authoring records.
        return self.source_root / f"{sticker_id:06d}.png", self.source_root / f"{sticker_id:06d}.json" # Keeps source and recipe paths stable when a sticker is renamed.

    def load(self, sticker_id: int, fallback_art: Path) -> tuple[Path, BorderSettings]: # Restores editable originals while leaving legacy imports unchanged by default.
        source_path, recipe_path = self.paths(sticker_id) # Resolves both parts of the authoring record.
        if not recipe_path.exists(): # Recognizes content created before border authoring was available.
            return fallback_art, BorderSettings(width=0) # Starts legacy edits with their existing image and no added border.
        if not source_path.is_file(): # Avoids quietly treating already-bordered output as the lost original.
            raise ValueError("the saved original artwork is missing; restore its source_art PNG before editing") # Explains why a fresh safe render cannot be produced.
        try: # Validates persisted settings before returning them to the editor.
            record: dict[str, object] = json.loads(recipe_path.read_text(encoding="utf-8")) # Loads the versioned recipe associated with this sticker identity.
            if record.get("version") != 1 or not isinstance(record.get("border"), dict): # Rejects unsupported or malformed authoring records.
                raise ValueError("unsupported border recipe") # Prevents guessing settings and accumulating an incorrect border.
            settings: BorderSettings = BorderSettings(**record["border"]) # Reuses the same validation as the UI controls.
        except (TypeError, AttributeError, ValueError) as error: # Converts malformed JSON and settings into a useful authoring error.
            raise ValueError(f"could not read border settings for #{sticker_id:06d}: {error}") from error # Identifies the record that needs restoring.
        return source_path, settings # Supplies the unmodified original and its saved cut settings.

    def resolve_source(self, selected: Path) -> Path: # Avoids stacking a second border when a managed output is imported again.
        if selected.parent.resolve() != self.art_root.resolve(): # Accepts normal external artwork without interpreting its filename.
            return selected # Leaves user-provided source locations untouched.
        match: re.Match[str] | None = re.match(r"^(\d+)_", selected.name) # Recognizes stable IDs in generated artwork filenames.
        if match is None: # Allows unnumbered legacy artwork in the output directory.
            return selected # Treats the selected image as its own original when no record can exist.
        source_path, _settings = self.load(int(match.group(1)), selected) # Resolves saved originals and validates any existing recipe.
        return source_path # Routes every managed re-import through the original pixels.

    def prepare(self, sticker_id: int, selected: Path, destination: Path, settings: BorderSettings, existing_art: Path | None = None) -> dict[Path, bytes]: # Builds a complete authoring bundle without mutating any existing file.
        source_path: Path = self.resolve_source(selected) # Resolves managed exports back to their preserved original artwork.
        original_bytes: bytes = source_path.read_bytes() # Takes one stable source snapshot before image processing or renaming.
        original_destination, recipe_destination = self.paths(sticker_id) # Assigns stable authoring paths for this sticker.
        output_bytes: bytes | None = None # Allows unchanged edits to reuse their exact existing exported PNG.
        if existing_art is not None and existing_art.exists() and recipe_destination.exists(): # Checks for an unchanged authored sticker before repeating quantization.
            old_source, old_settings = self.load(sticker_id, existing_art) # Loads the previous authoritative recipe.
            if settings == old_settings and old_source.read_bytes() == original_bytes: # Compares source content and settings rather than just filenames.
                output_bytes = existing_art.read_bytes() # Makes metadata-only edits and renames lossless for the exported image.
        if output_bytes is None: # Processes new imports, changed borders, and replacement artwork from their original pixels.
            with Image.open(BytesIO(original_bytes)) as source_image: # Decodes the stable original snapshot without touching the user's file.
                shape: StickerShape = build_sticker_shape(source_image, settings) # Builds one covered and smoothed physical silhouette.
                output_bytes = original_bytes if settings.width == 0 and existing_art == selected else png_bytes(sticker_palette(shape, settings.colour)) # Preserves unmodified legacy edits and otherwise exports the chosen border.
        recipe: str = json.dumps({"version": 1, "border": asdict(settings)}, indent=2) + "\n" # Saves the exact cut recipe without adding Godot resource fields.
        return {original_destination: original_bytes, recipe_destination: recipe.encode("utf-8"), destination: output_bytes} # Leaves publication to the caller's complete sticker transaction.
