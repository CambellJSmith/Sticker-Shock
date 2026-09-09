class_name MarketPriceChart
extends Control

const CHART_PADDING: float = 18.0 # Keeps the plotted series clear of the panel edges.
const GRID_DIVISIONS: int = 4 # Draws a restrained stock-chart grid without excessive visual noise.

var _prices: PackedFloat32Array = PackedFloat32Array() # Stores the chronological quote series currently shown.

func set_prices(prices: PackedFloat32Array) -> void: # Replaces the visible quote series and schedules one efficient redraw.
	_prices = prices.duplicate() # Owns a stable local copy so external market mutations cannot change the active draw unexpectedly.
	queue_redraw() # Requests a new cached CanvasItem draw pass only when market data changes.

func _draw() -> void: # Draws the complete lightweight stock-style chart using native CanvasItem primitives.
	var chart_rect: Rect2 = Rect2(Vector2(CHART_PADDING, CHART_PADDING), size - Vector2(CHART_PADDING * 2.0, CHART_PADDING * 2.0)) # Defines the padded plotting area from current Control size.
	if chart_rect.size.x <= 1.0 or chart_rect.size.y <= 1.0: # Rejects drawing before layout has produced usable dimensions.
		return # Leaves the chart empty until the container is ready.
	var grid_color: Color = Color(0.24, 0.28, 0.34, 0.34) # Uses a subdued neutral grid suited to the existing dark UI.
	for division: int in range(GRID_DIVISIONS + 1): # Draws evenly spaced horizontal reference lines.
		var ratio: float = float(division) / float(GRID_DIVISIONS) # Converts grid index into normalized vertical position.
		var y: float = lerpf(chart_rect.position.y, chart_rect.end.y, ratio) # Resolves the actual local y-coordinate.
		draw_line(Vector2(chart_rect.position.x, y), Vector2(chart_rect.end.x, y), grid_color, 1.0, true) # Draws one antialiased horizontal guide.
	if _prices.size() < 2: # Requires at least two quotes before a price path can exist.
		return # Keeps the empty grid visible while history is still being established.
	var minimum_price: float = _prices[0] # Seeds the visible y-range from the first quote.
	var maximum_price: float = _prices[0] # Seeds the visible y-range maximum from the first quote.
	for price: float in _prices: # Scans the compact history once to find chart bounds.
		minimum_price = minf(minimum_price, price) # Expands the lower bound when required.
		maximum_price = maxf(maximum_price, price) # Expands the upper bound when required.
	var price_span: float = maxf(maximum_price - minimum_price, maxf(maximum_price * 0.04, 1.0)) # Prevents a flat market from producing a zero-height plotting range.
	var range_padding: float = price_span * 0.12 # Adds breathing room above and below the visible series.
	minimum_price -= range_padding # Extends the lower chart bound slightly.
	maximum_price += range_padding # Extends the upper chart bound slightly.
	price_span = maximum_price - minimum_price # Recalculates the final padded y-range.
	var points: PackedVector2Array = PackedVector2Array() # Allocates the polyline points used by one native draw call.
	points.resize(_prices.size()) # Reserves the exact required capacity once.
	for index: int in range(_prices.size()): # Converts every chronological quote into chart coordinates.
		var x_ratio: float = float(index) / float(_prices.size() - 1) # Maps time order from left to right.
		var y_ratio: float = (_prices[index] - minimum_price) / price_span # Normalizes the current quote inside the visible price range.
		var x: float = lerpf(chart_rect.position.x, chart_rect.end.x, x_ratio) # Resolves horizontal plot position.
		var y: float = lerpf(chart_rect.end.y, chart_rect.position.y, y_ratio) # Resolves vertical plot position with higher prices toward the top.
		points[index] = Vector2(x, y) # Stores the final antialiased line coordinate.
	var rising: bool = _prices[_prices.size() - 1] >= _prices[0] # Determines whether the visible window closed above or below where it began.
	var line_color: Color = Color(0.42, 0.90, 0.66, 1.0) if rising else Color(0.96, 0.48, 0.48, 1.0) # Uses familiar market green/red semantics without affecting other UI theming.
	draw_polyline(points, line_color, 2.5, true) # Draws the complete live series in one efficient antialiased call.
	var latest_point: Vector2 = points[points.size() - 1] # Retrieves the newest quote position for a live-market endpoint marker.
	draw_circle(latest_point, 4.0, line_color) # Marks the most recent published quote clearly.
