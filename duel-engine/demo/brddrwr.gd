# brddrwr.gd
extends Control

const SQUARE_SIZE: float = 80.0
const BOARD_SQUARES: int = 7

var arrow_color: Color = Color("#fbbf24")

var _is_dragging: bool = false
var _drag_start: Vector2i = Vector2i(-1, -1)
var _drag_end: Vector2i = Vector2i(-1, -1)
var _arrows: Array = []
var _highlights: Array = []
func _ready():
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Size to cover the board exactly so hit-testing is correct
	size = Vector2(BOARD_SQUARES * SQUARE_SIZE, BOARD_SQUARES * SQUARE_SIZE)

# Call this from startgameplay.gd after board_renderer is positioned:
#   arrow_layer.position = board_renderer.position
func align_to_board(board_global_pos: Vector2):
	global_position = board_global_pos

func clear_arrows():
	_arrows.clear()
	_highlights.clear()
	queue_redraw()

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		clear_arrows()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var sq = _pixel_to_square(get_global_mouse_position())
			if sq.x >= 0:
				_is_dragging = true
				_drag_start = sq
				_drag_end = sq
				mouse_filter = Control.MOUSE_FILTER_STOP
				queue_redraw()
		else:
			mouse_filter = Control.MOUSE_FILTER_PASS
			_is_dragging = false
			var from = _drag_start
			var to = _pixel_to_square(get_global_mouse_position())
			_drag_start = Vector2i(-1, -1)
			_drag_end = Vector2i(-1, -1)
			if from.x >= 0 and to.x >= 0 and from != to:
				_toggle_arrow(from, to)
			elif from.x >= 0 and to == from:
				_toggle_highlight(from)
			else:
				queue_redraw()

	if event is InputEventMouseMotion and _is_dragging:
		var sq = _pixel_to_square(get_global_mouse_position())
		if sq != _drag_end:
			_drag_end = sq
			queue_redraw()

func _toggle_highlight(sq: Vector2i):
	for i in range(_highlights.size()):
		if _highlights[i] == sq:
			_highlights.remove_at(i)
			queue_redraw()
			return
	_highlights.append(sq)
	queue_redraw()

func _toggle_arrow(from_sq: Vector2i, to_sq: Vector2i):
	for i in range(_arrows.size()):
		if _arrows[i].from == from_sq and _arrows[i].to == to_sq:
			_arrows.remove_at(i)
			queue_redraw()
			return
	_arrows.append({"from": from_sq, "to": to_sq})
	queue_redraw()

# Converts a global mouse position to a board square (col, row).
# Returns (-1,-1) if outside the board.
func _pixel_to_square(global_pos: Vector2) -> Vector2i:
	var local = global_pos - global_position
	var col = int(local.x / SQUARE_SIZE)
	var row = int(local.y / SQUARE_SIZE)
	if col >= 0 and col < BOARD_SQUARES and row >= 0 and row < BOARD_SQUARES:
		return Vector2i(col, row)
	return Vector2i(-1, -1)


# Returns the center of a square in LOCAL coordinates.
# sq.x = col, sq.y = row
func _square_center(sq: Vector2i) -> Vector2:
	return Vector2(
		sq.x * SQUARE_SIZE + SQUARE_SIZE * 0.5,
		sq.y * SQUARE_SIZE + SQUARE_SIZE * 0.5
	)

func _is_l_move(from_sq: Vector2i, to_sq: Vector2i) -> bool:
	var d = to_sq - from_sq
	return (abs(d.x) == 2 and abs(d.y) == 1) or (abs(d.x) == 1 and abs(d.y) == 2) \
		or (abs(d.x) == 3 and abs(d.y) == 1) or (abs(d.x) == 1 and abs(d.y) == 3)

func _draw():
	for sq in _highlights:
		var pos = _square_center(sq)
		var half = SQUARE_SIZE * 0.5
		draw_rect(
			Rect2(pos.x - half, pos.y - half, SQUARE_SIZE, SQUARE_SIZE),
			Color(0.9, 0.2, 0.2, 0.4)
		)

	for a in _arrows:
		_draw_arrow(a.from, a.to, arrow_color)

	if _is_dragging and _drag_start.x >= 0 and _drag_end.x >= 0 and _drag_start != _drag_end:
		_draw_arrow(_drag_start, _drag_end, Color(arrow_color.r, arrow_color.g, arrow_color.b, 0.5))

func _draw_arrow(from_sq: Vector2i, to_sq: Vector2i, color: Color):
	var from_pos := _square_center(from_sq)
	var to_pos := _square_center(to_sq)
	var lw := SQUARE_SIZE * 0.09
	var hs := SQUARE_SIZE * 0.28

	if _is_l_move(from_sq, to_sq):
		var d := to_sq - from_sq
		# Travel along the longer axis first, then the shorter
		var bend_sq: Vector2i
		if abs(d.x) > abs(d.y):
			bend_sq = Vector2i(to_sq.x, from_sq.y)
		else:
			bend_sq = Vector2i(from_sq.x, to_sq.y)
		var bend := _square_center(bend_sq)
		var dir := (to_pos - bend).normalized()

		draw_line(from_pos, bend, color, lw, true)
		draw_line(bend, to_pos - dir * hs * 0.8, color, lw, true)
		draw_circle(bend, lw * 0.7, color)
		_draw_arrowhead(to_pos, dir, hs, color)
	else:
		var dir := (to_pos - from_pos).normalized()
		# Pull the tail off the center so it doesn't overlap the piece token
		var start := from_pos + dir * SQUARE_SIZE * 0.28
		var end := to_pos - dir * hs * 0.8
		draw_line(start, end, color, lw, true)
		_draw_arrowhead(to_pos, dir, hs, color)

func _draw_arrowhead(tip: Vector2, dir: Vector2, head_size: float, color: Color):
	var perp := Vector2(-dir.y, dir.x)
	var base := tip - dir * head_size
	draw_colored_polygon(
		PackedVector2Array([tip, base + perp * head_size * 0.45, base - perp * head_size * 0.45]),
		color
	)
