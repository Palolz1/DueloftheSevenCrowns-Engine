# brddrwr.gd
# Board annotations, the way chess sites do them:
#   right-click a square        -> mark it (again to remove)
#   right-drag square to square -> arrow (again to remove)
#   hold Shift / Ctrl / Alt     -> red / blue / yellow instead of green
#   left-click the board, C, or the Clear button -> remove everything
# Marks are drawn by BoardRenderer underneath the pieces; arrows are drawn
# here, above the pieces. This node is a CanvasGroup so the arrows are made
# see-through as a whole: crossing or bending arrows don't get darker where
# their parts overlap.
# Everything is stored in board squares (row, col), so it survives flips.
extends CanvasGroup

const CELL := 80.0
const OPACITY := 0.82

const COLORS := {
	"green":  Color("#2fbf71"),
	"red":    Color("#e8485c"),
	"blue":   Color("#4c8dff"),
	"yellow": Color("#f2c230"),
}

var board = null            # BoardRenderer (set by StartGameplay)
var flipped := false        # kept for the old API; BoardRenderer decides
var arrows: Array = []      # {from: Vector2i(row, col), to: Vector2i, color: String}
var marks: Array = []       # {sq: Vector2i, color: String}

var _drag_from := Vector2i(-1, -1)
var _drag_to := Vector2i(-1, -1)
var _drag_color := "green"
var _canvas: Node2D


func _ready():
	z_index = 50
	self_modulate = Color(1, 1, 1, OPACITY)
	# Draw on a child: a CanvasGroup composites its children.
	_canvas = Node2D.new()
	_canvas.draw.connect(_draw_arrows)
	add_child(_canvas)


func align_to_board(board_global_pos: Vector2):
	global_position = board_global_pos


func set_flipped(f: bool):
	flipped = f
	_redraw()


func clear_arrows():
	if arrows.is_empty() and marks.is_empty():
		return
	arrows.clear()
	marks.clear()
	_redraw()


# ---- Input ----------------------------------------------------------------
func _input(event: InputEvent):
	if board == null or not board.visible:
		return
	var root := get_parent().get_parent()
	var info = root.get_node_or_null("Info") if root != null else null
	if info != null and info.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		clear_arrows()
		return

	var sq := _square_under_mouse()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and sq.x >= 0:
				_drag_from = sq
				_drag_to = sq
				_drag_color = _color_from_modifiers(event)
				_redraw()
			elif not event.pressed and _drag_from.x >= 0:
				var from := _drag_from
				_drag_from = Vector2i(-1, -1)
				_drag_to = Vector2i(-1, -1)
				if sq == from:
					_toggle_mark(from, _drag_color)
				elif sq.x >= 0:
					_toggle_arrow(from, sq, _drag_color)
				_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and sq.x >= 0:
			clear_arrows()
	elif event is InputEventMouseMotion and _drag_from.x >= 0:
		if sq.x >= 0 and sq != _drag_to:
			_drag_to = sq
			_redraw()


func _square_under_mouse() -> Vector2i:
	return board.local_to_board(board.get_local_mouse_position())


func _color_from_modifiers(e: InputEventWithModifiers) -> String:
	if e.shift_pressed:
		return "red"
	if e.ctrl_pressed or e.meta_pressed:
		return "blue"
	if e.alt_pressed:
		return "yellow"
	return "green"


# Same shape and colour again removes it; another colour recolours it.
func _toggle_arrow(from: Vector2i, to: Vector2i, color: String):
	for i in arrows.size():
		if arrows[i].from == from and arrows[i].to == to:
			if arrows[i].color == color:
				arrows.remove_at(i)
			else:
				arrows[i].color = color
			return
	arrows.append({"from": from, "to": to, "color": color})


func _toggle_mark(sq: Vector2i, color: String):
	for i in marks.size():
		if marks[i].sq == sq:
			if marks[i].color == color:
				marks.remove_at(i)
			else:
				marks[i].color = color
			return
	marks.append({"sq": sq, "color": color})


func _redraw():
	if _canvas != null:
		_canvas.queue_redraw()
	if board != null:
		var m := []
		for mk in marks:
			m.append({"sq": mk.sq, "color": COLORS[mk.color]})
		board.set_marks(m)


# ---- Drawing --------------------------------------------------------------
func _center(sq: Vector2i) -> Vector2:
	return board.cell_center(sq.x, sq.y) if board != null else Vector2.ZERO


func _draw_arrows():
	if board == null:
		return
	for a in arrows:
		_draw_arrow(a.from, a.to, COLORS[a.color])
	if _drag_from.x >= 0 and _drag_to.x >= 0 and _drag_to != _drag_from:
		var c: Color = COLORS[_drag_color]
		_draw_arrow(_drag_from, _drag_to, Color(c, 0.6))


# Leaping moves (Knight 2+1, Paladin 3+1) get an L-shaped arrow, like a
# knight arrow in chess: along the longer side first, then the short one.
static func _is_leap(d: Vector2i) -> bool:
	var a := absi(d.x)
	var b := absi(d.y)
	return (a == 1 and (b == 2 or b == 3)) or (b == 1 and (a == 2 or a == 3))


func _draw_arrow(from: Vector2i, to: Vector2i, color: Color):
	var w := CELL * 0.17          # shaft width
	var head_len := CELL * 0.42
	var head_w := CELL * 0.50
	var p0 := _center(from)
	var p2 := _center(to)
	var pts: Array = [p0]
	var d := to - from
	if _is_leap(d):
		# bend at the square that shares the row/col of the long leg
		var bend := Vector2i(to.x, from.y) if absi(d.x) > absi(d.y) else Vector2i(from.x, to.y)
		pts.append(_center(bend))
	pts.append(p2)

	# stop the tip a little short of the target centre
	var last_dir: Vector2 = (pts[-1] - pts[-2]).normalized()
	var tip: Vector2 = pts[-1] - last_dir * CELL * 0.10
	var head_base: Vector2 = tip - last_dir * head_len
	pts[-1] = head_base

	# shaft (round start, square joint at the bend)
	draw_circle_on(pts[0], w * 0.5, color)
	for i in pts.size() - 1:
		_canvas.draw_line(pts[i], pts[i + 1], color, w, true)
	if pts.size() == 3:
		_canvas.draw_rect(Rect2(pts[1] - Vector2(w, w) * 0.5, Vector2(w, w)), color)
	# head
	var perp := Vector2(-last_dir.y, last_dir.x)
	_canvas.draw_colored_polygon(PackedVector2Array([
		tip, head_base + perp * head_w * 0.5, head_base - perp * head_w * 0.5]), color)


func draw_circle_on(p: Vector2, r: float, color: Color):
	_canvas.draw_circle(p, r, color, true, -1.0, true)
