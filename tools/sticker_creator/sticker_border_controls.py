from __future__ import annotations # Supports typed reusable border controls.

from collections.abc import Callable # Describes the authoring store's original-artwork resolver.
from pathlib import Path # Converts selected file text into a worker-friendly path.
import tkinter as tk # Owns form variables and colour swatches.
from tkinter import colorchooser, ttk # Supplies a native custom colour picker and themed controls.

from sticker_border import BorderSettings # Validates and snapshots the current border recipe.
from sticker_preview import StickerPreview # Keeps preview rendering and threading out of form code.


class BorderControls(ttk.Frame): # Composes colour, growth, smoothing, and an exact export preview.
    def __init__(self, parent: tk.Misc, source_var: tk.StringVar, resolve_source: Callable[[Path], Path], initial: BorderSettings = BorderSettings()) -> None: # Shares one control implementation between single and batch imports.
        super().__init__(parent, style="Panel.TFrame", padding=(0, 8)) # Matches the surrounding dark authoring panel.
        self._source_var: tk.StringVar = source_var # Observes artwork selection without owning the rest of the sticker form.
        self._width_var: tk.StringVar = tk.StringVar(self, str(initial.width)) # Keeps temporarily incomplete numeric edits representable.
        self._smoothing_var: tk.StringVar = tk.StringVar(self, str(initial.smoothing)) # Stores the pixel scale of cut-line cleanup.
        self._colour_var: tk.StringVar = tk.StringVar(self, initial.colour) # Accepts direct hex entry as well as the picker and preset grid.
        self._refresh_id: str | None = None # Debounces repeated field updates into one preview request.
        self._traces: list[tuple[tk.StringVar, str]] = [] # Tracks variable listeners for explicit cleanup.
        self.columnconfigure(0, weight=1) # Lets controls use space left beside the fixed preview.
        controls: ttk.Frame = ttk.Frame(self, style="Panel.TFrame") # Groups border controls independently of the preview surface.
        controls.grid(row=0, column=0, sticky="nw", padx=(0, 16)) # Places editable fields on the left of the preview.
        ttk.Label(controls, text="die-cut border", style="Header.TLabel").grid(row=0, column=0, columnspan=3, sticky="ew", pady=(0, 8)) # Gives the panel a compact readable title.
        ttk.Label(controls, text="width (px)", style="Panel.TLabel").grid(row=1, column=0, sticky="w", padx=(0, 10)) # Identifies the outward growth distance.
        ttk.Spinbox(controls, textvariable=self._width_var, from_=0, to=256, width=6).grid(row=1, column=1, sticky="w", pady=3) # Allows direct pixel entry and incremental adjustment.
        ttk.Label(controls, text="0 = no border", style="Muted.TLabel").grid(row=1, column=2, sticky="w", padx=(8, 0)) # Makes the disabled and legacy state explicit.
        ttk.Label(controls, text="smoothing (px)", style="Panel.TLabel").grid(row=2, column=0, sticky="w", padx=(0, 10)) # Distinguishes cut smoothing from artwork filtering.
        ttk.Spinbox(controls, textvariable=self._smoothing_var, from_=1, to=128, width=6).grid(row=2, column=1, sticky="w", pady=3) # Controls how much fine contour detail is removed.
        colour_row: ttk.Frame = ttk.Frame(controls, style="Panel.TFrame") # Holds the swatch, hex field, and custom picker together.
        colour_row.grid(row=3, column=0, columnspan=3, sticky="w", pady=(8, 4)) # Keeps colour selection on one compact row.
        self._swatch: tk.Button = tk.Button(colour_row, width=3, bg=initial.colour, relief="flat", command=self._choose_colour) # Opens the custom colour picker from the current colour swatch.
        self._swatch.pack(side="left", padx=(0, 7)) # Places the visible selected colour beside its editable hex value.
        ttk.Entry(colour_row, textvariable=self._colour_var, width=10).pack(side="left") # Supports exact colour matching by hex entry.
        ttk.Button(colour_row, text="choose colour…", command=self._choose_colour).pack(side="left", padx=(7, 0)) # Exposes the native colour wheel or colour grid dialog.
        palette: ttk.Frame = ttk.Frame(controls, style="Panel.TFrame") # Provides immediately accessible common backing colours.
        palette.grid(row=4, column=0, columnspan=3, sticky="w", pady=(4, 0)) # Places the preset grid under custom colour controls.
        for colour in ("#ffffff", "#181a1d", "#b7bdc8", "#ef6673", "#f3a54c", "#f2d66d", "#75c79a", "#73b9ef", "#af8ee5"): # Supplies neutral and saturated choices without restricting custom colours.
            tk.Button(palette, bg=colour, activebackground=colour, width=2, relief="flat", command=lambda chosen=colour: self._colour_var.set(chosen)).pack(side="left", padx=(0, 3)) # Applies a preset through the same validated variable as the picker.
        self._preview: StickerPreview = StickerPreview(self, resolve_source) # Creates an independent background preview renderer.
        self._preview.grid(row=0, column=1, sticky="ne") # Fits the final sticker alongside its border controls.
        for variable in (self._source_var, self._width_var, self._smoothing_var, self._colour_var): # Observes only values that affect the finished sticker.
            self._traces.append((variable, variable.trace_add("write", self._schedule_preview))) # Debounces all relevant edits through one handler.
        self.bind("<Destroy>", self._destroyed, add="+") # Releases listeners when a batch dialog or the application closes.
        self._schedule_preview() # Requests an initial preview when artwork is already selected.

    def settings(self) -> BorderSettings: # Returns a validated immutable recipe for saving or a batch snapshot.
        try: # Converts numeric entries without silently clipping or rounding the user's input.
            width: int = int(self._width_var.get()) # Reads outward growth in original-image pixels.
            smoothing: int = int(self._smoothing_var.get()) # Reads the jagged-detail smoothing scale.
        except ValueError as error: # Handles partially entered or nonnumeric form values.
            raise ValueError("border width and smoothing must be whole numbers of pixels") from error # Keeps validation feedback actionable.
        return BorderSettings(width, smoothing, self._colour_var.get().strip()) # Applies common range and colour validation before any save.

    def set_settings(self, settings: BorderSettings) -> None: # Restores a saved border recipe without reusing its processed image as input.
        self._width_var.set(str(settings.width)) # Restores the authored pixel growth.
        self._smoothing_var.set(str(settings.smoothing)) # Restores the authored cleanup scale.
        self._colour_var.set(settings.colour) # Restores the exact chosen colour and schedules one debounced preview.

    def _choose_colour(self) -> None: # Opens the platform's full custom colour picker.
        current: str = self._colour_var.get() # Starts from the editable colour text when valid.
        try: # Falls back safely if the hex field is currently incomplete.
            BorderSettings(colour=current) # Validates only the picker start colour.
        except ValueError: # Allows the picker to repair invalid manual colour entry.
            current = "#ffffff" # Supplies a valid initial swatch to the native dialog.
        _rgb, chosen = colorchooser.askcolor(color=current, parent=self.winfo_toplevel(), title="border colour") # Provides custom colour selection and an explicit cancel action.
        if chosen is not None: # Leaves the existing colour unchanged when the picker is cancelled.
            self._colour_var.set(chosen) # Routes the chosen colour through normal recipe validation and preview.

    def _schedule_preview(self, *_arguments: str) -> None: # Coalesces rapid typing and spinner updates before starting image processing.
        if self._refresh_id is not None: # Replaces a previous debounce callback when another field changes.
            self.after_cancel(self._refresh_id) # Avoids processing intermediate text or superseded settings.
        self._refresh_id = self.after(180, self._refresh_preview) # Leaves the event loop responsive while the user edits controls.

    def _refresh_preview(self) -> None: # Captures current UI values for the background preview queue.
        self._refresh_id = None # Marks the debounce timer as consumed.
        try: # Keeps invalid intermediate settings out of the processing pipeline.
            settings: BorderSettings = self.settings() # Validates colour, growth, and smoothing together.
        except ValueError as error: # Shows form errors without opening repeated modal dialogs.
            self._preview.clear(str(error)) # Clears stale results and displays the field correction needed.
            return # Waits for the next edit before trying to render again.
        self._swatch.configure(bg=settings.colour, activebackground=settings.colour) # Keeps the selected-colour swatch synchronized with typed hex values.
        selected: str = self._source_var.get() # Reads artwork selection on the owning Tk thread.
        if not selected: # Handles an empty or cleared sticker form.
            self._preview.clear() # Removes the previous sticker without starting a worker request.
            return # Waits until artwork is selected.
        self._preview.request(Path(selected), settings) # Sends a plain recipe snapshot to the background renderer.

    def _destroyed(self, event: tk.Event) -> None: # Releases deferred work and external variable subscriptions.
        if event.widget is not self: # Ignores destruction notifications belonging to nested controls.
            return # Leaves cleanup to this panel's own destruction event.
        if self._refresh_id is not None: # Cancels any preview request still waiting in the debounce timer.
            self.after_cancel(self._refresh_id) # Prevents calls into destroyed controls.
        for variable, trace_id in self._traces: # Removes listeners on form variables that may outlive this panel.
            variable.trace_remove("write", trace_id) # Avoids stale callbacks after closing and reopening batch import.
