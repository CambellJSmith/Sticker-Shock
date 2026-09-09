from __future__ import annotations # Supports immutable preview job annotations.

import threading # Keeps native image processing off the Tk event thread.
from collections.abc import Callable # Types the managed-source resolver supplied by the authoring store.
from pathlib import Path # Identifies artwork without reading Tk variables from a worker.
from os import stat_result # Types source revision metadata used by the preview cache.
from queue import Empty, Queue # Delivers the latest preview request and result safely between threads.
import tkinter as tk # Owns canvas presentation and event scheduling on the main thread.
from tkinter import ttk # Uses the tool's existing themed widget system.

from PIL import Image, ImageDraw, ImageTk # Composites a transparency checkerboard and displays the finished PNG preview.

from sticker_border import BorderSettings, StickerShape, build_sticker_shape # Shares the exact export geometry with live previews.
from sticker_png import sticker_palette # Shows the final palette conversion rather than an approximate border effect.

PreviewJob = tuple[int, Path, BorderSettings] # Carries a versioned snapshot of one preview request.
PreviewResult = tuple[int, Image.Image | None, str] # Carries rendered pixels or a readable processing error.


class StickerPreview(ttk.Frame): # Presents exact exported pixels while keeping editing responsive.
    def __init__(self, parent: tk.Misc, resolve_source: Callable[[Path], Path]) -> None: # Builds the preview surface and a single bounded worker queue.
        super().__init__(parent, style="Panel.TFrame") # Adopts the surrounding authoring panel appearance.
        self._resolve_source: Callable[[Path], Path] = resolve_source # Reuses preserved originals when a generated image is selected.
        self._jobs: Queue[PreviewJob] = Queue(maxsize=1) # Replaces obsolete queued work instead of spawning a thread per keystroke.
        self._results: Queue[PreviewResult] = Queue() # Transfers finished images without any worker-side Tk calls.
        self._closed: threading.Event = threading.Event() # Lets the worker stop cleanly when its widget is destroyed.
        self._version: int = 0 # Rejects stale images after the selected artwork or border settings change.
        self._photo: ImageTk.PhotoImage | None = None # Keeps the current Tk image alive while the canvas uses it.
        self._canvas: tk.Canvas = tk.Canvas(self, width=220, height=164, bg="#303238", highlightthickness=0) # Provides a compact checkerboard preview beside the controls.
        self._canvas.pack() # Keeps preview geometry fixed while the form stretches.
        self._caption: ttk.Label = ttk.Label(self, text="choose artwork to preview", style="Muted.TLabel", wraplength=230) # Describes the active result or its processing state.
        self._caption.pack(fill="x", pady=(4, 0)) # Places feedback directly below the image.
        self._poll_id: str = self.after(60, self._poll) # Schedules all Tk result handling on the main event loop.
        self.bind("<Destroy>", self._destroyed, add="+") # Cancels polling and signals shutdown when the preview is removed.
        threading.Thread(target=StickerPreview._work, args=(self._closed, self._jobs, self._results, resolve_source), daemon=True, name="sticker_preview").start() # Keeps Tk widget references out of the worker's lifetime and garbage collection.

    def clear(self, message: str = "choose artwork to preview") -> None: # Invalidates outstanding work when the form has no usable recipe.
        self._version += 1 # Prevents an old worker result from overwriting the new empty state.
        self._canvas.delete("all") # Removes stale art after selection or validation changes.
        self._photo = None # Releases the obsolete Tk image reference.
        self._caption.configure(text=message) # Displays validation guidance beside the border controls.

    def request(self, path: Path, settings: BorderSettings) -> None: # Queues a recipe snapshot without touching shared Tk state from a worker.
        self._version += 1 # Gives the new request a unique display generation.
        self._caption.configure(text="updating preview…") # Makes long image processing visible without freezing editing.
        try: # Discards work that has not started and is already obsolete.
            self._jobs.get_nowait() # Keeps only the most recent pending recipe.
        except Empty: # Handles a worker that already consumed the earlier request.
            pass # Leaves the bounded queue ready for the latest request.
        self._jobs.put_nowait((self._version, path, settings)) # Submits plain immutable input values to the background worker.

    @staticmethod # Prevents the worker from retaining or finalizing Tk widgets on a background thread.
    def _work(closed: threading.Event, jobs: Queue[PreviewJob], results: Queue[PreviewResult], resolve_source: Callable[[Path], Path]) -> None: # Processes requests sequentially with a one-entry geometry cache.
        cached_key: tuple[Path, int, int, int, int] | None = None # Identifies the source revision and cut geometry of the cached mask.
        cached_shape: StickerShape | None = None # Reuses expensive distance transforms when only the backing colour changes.
        while not closed.is_set(): # Keeps background processing alive only while its widget exists.
            try: # Waits briefly so widget destruction can stop an idle worker.
                version, selected_path, settings = jobs.get(timeout=0.2) # Retrieves the latest submitted recipe without reading Tk variables.
            except Empty: # Rechecks shutdown after an idle interval.
                continue # Waits for new artwork or changed settings.
            try: # Converts unreadable artwork and invalid processing into preview feedback.
                source_path: Path = resolve_source(selected_path) # Finds the original for previously exported tool artwork.
                source_stat: stat_result = source_path.stat() # Reads file revision information for the small geometry cache.
                key: tuple[Path, int, int, int, int] = (source_path, source_stat.st_mtime_ns, source_stat.st_size, settings.width, settings.smoothing) # Invalidates geometry for source, width, or smoothing changes.
                if cached_shape is None or cached_key != key: # Avoids regenerating the cut mask for colour-only edits.
                    with Image.open(source_path) as source_image: # Keeps file handles scoped to a single decoding operation.
                        cached_shape = build_sticker_shape(source_image, settings) # Runs the same coverage-preserving smoothing used during import.
                    cached_key = key # Publishes the completed geometry as the current cache entry.
                exported: Image.Image = sticker_palette(cached_shape, settings.colour).convert("RGBA") # Uses the exact exported colour and edge-alpha palette.
                dimensions: str = f"{exported.width} × {exported.height} px · export preview" # Reports final canvas size in source-image pixels.
                exported.thumbnail((212, 156), Image.Resampling.LANCZOS) # Fits the complete sticker only after full-resolution processing finishes.
                board: Image.Image = Image.new("RGBA", (220, 164), "#42454b") # Provides a dark-neutral transparency checkerboard.
                drawing: ImageDraw.ImageDraw = ImageDraw.Draw(board) # Draws a small fixed checkerboard without scaling source artwork.
                for y in range(0, 164, 12): # Visits preview rows only rather than iterating over source-image pixels.
                    for x in range(0, 220, 12): # Creates evenly sized cells across the preview surface.
                        if (x // 12 + y // 12) % 2 == 0: # Alternates two neutral tones so transparent regions remain readable.
                            drawing.rectangle((x, y, x + 11, y + 11), fill="#595c62") # Draws one checker cell behind the sticker.
                board.alpha_composite(exported, ((220 - exported.width) // 2, (164 - exported.height) // 2)) # Centers the finished image without clipping its cut outline.
                results.put((version, board, dimensions)) # Returns pixels for the Tk thread to display.
            except Exception as error: # Keeps a bad image from terminating future previews.
                results.put((version, None, str(error))) # Delivers the failure through the normal result queue.

    def _poll(self) -> None: # Applies completed results exclusively on Tk's main thread.
        try: # Drains completed results before scheduling the next lightweight poll.
            while True: # Consumes stale generations as well as the latest finished image.
                version, preview, caption = self._results.get_nowait() # Retrieves one worker result without blocking input.
                if version != self._version: # Ignores outdated work after subsequent edits.
                    continue # Prevents a previous border choice from flashing over the current one.
                self._canvas.delete("all") # Replaces the previous preview or empty state.
                self._photo = ImageTk.PhotoImage(preview) if preview is not None else None # Constructs Tk image objects only on their owning thread.
                if self._photo is not None: # Shows a new image only when processing completed successfully.
                    self._canvas.create_image(0, 0, anchor="nw", image=self._photo) # Displays the composed checkerboard and finished sticker.
                self._caption.configure(text=caption) # Shows final dimensions or the associated error.
        except Empty: # Ends draining once every completed result has been handled.
            pass # Keeps the UI event loop free between small polls.
        self._poll_id = self.after(60, self._poll) # Continues polling while the widget remains alive.

    def _destroyed(self, event: tk.Event) -> None: # Stops worker and timer ownership when this preview is destroyed.
        if event.widget is self: # Ignores destruction notifications belonging to child widgets.
            self._closed.set() # Stops the background loop after any active processing completes.
            self.after_cancel(self._poll_id) # Prevents callbacks targeting a deleted Tk widget.
