#BoardRenderer.gd
# Draws the board, highlights, move hints and pieces.
#
# Orientation: board row 0 is White's back rank. By default it is drawn at the
# top (White plays "down"); with `flipped` the board is rotated 180 degrees.
# Every board->screen conversion goes through cell_pos()/cell_center() and
# every screen->board conversion through view_to_board(), so input, animation
# and drawings all follow the flip.
extends Node2D

const ROWS = 7
const COLS = 7
const CELL_SIZE = 80
const FRAME = 26          # frame / coordinate gutter around the squares
const BOARD_PX = CELL_SIZE * 7

var flipped := false

# Palette
var board_light = Color("#e8dcc2")
var board_dark = Color("#a27d58")
var frame_color = Color("#1a1f33")
var frame_line = Color("#e2b65a")
var sel_color = Color("#f2cf6b")
var check_color = Color("#ff4d5e")
var last_move_color = Color("#f5c443")
var legal_dot_color = Color(0.06, 0.09, 0.16, 0.38)
var capture_color = Color("#ff5a6a")
var hover_legal_color = Color("#22d3ee")
var hover_guard_color = Color("#e879f9")
var hover_friend_color = Color("#5b8df0")
var hover_source_color = Color("#22d3ee")
var hint_color = Color("#22d3ee")
var coord_color = Color("#8b95b0")

var white_token_color = Color("#f4efe3")
var black_token_color = Color("#262d43")
var white_token_border = Color("#b8924a")
var black_token_border = Color("#59647f")

var piece_image_names = {
	"wK": "king", "wN": "knight", "wC": "cardinal", "wP": "paladin",
	"wM": "marshal", "wD": "donkey", "wL": "lancer", "wW": "warden",
	"bK": "king", "bN": "knight", "bC": "cardinal", "bP": "paladin",
	"bM": "marshal", "bD": "donkey", "bL": "lancer", "bW": "warden"
}

var _texture_cache = {}

# Last render() state, used by _draw()
var _board: Array = []
var _selected: Array = []
var _legal: Array = []
var _last_move = null
var _in_check := false
var _turn := "white"
var _hover_moves: Array = []
var _hovered: Array = []
var _game_over := false


# ---------------------------------------------------------------------------
# Coordinates
# ---------------------------------------------------------------------------
func cell_pos(r: int, c: int) -> Vector2:
	var vr := (6 - r) if flipped else r
	var vc := (6 - c) if flipped else c
	return Vector2(vc * CELL_SIZE, vr * CELL_SIZE)

func cell_center(r: int, c: int) -> Vector2:
	return cell_pos(r, c) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5

# Screen (view) row/col -> board row/col. The transform is its own inverse.
func view_to_board(vr: int, vc: int) -> Vector2i:
	if flipped:
		return Vector2i(6 - vr, 6 - vc)
	return Vector2i(vr, vc)

# Local pixel position -> board square, or (-1, -1) when off the board.
func local_to_board(p: Vector2) -> Vector2i:
	if p.x < 0 or p.y < 0:
		return Vector2i(-1, -1)
	var vc := int(p.x / CELL_SIZE)
	var vr := int(p.y / CELL_SIZE)
	if vr >= ROWS or vc >= COLS:
		return Vector2i(-1, -1)
	return view_to_board(vr, vc)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
func render(board: Array, selected: Array, legal_moves: Array, last_move, in_check: bool, turn: String, hint_arrow = null, hover_moves: Array = [], game_over_reason: String = "", winner: String = "", hovered_square: Array = [], skip_squares: Array = []):
	_board = board
	_selected = selected
	_legal = legal_moves
	_last_move = last_move
	_in_check = in_check
	_turn = turn
	_hover_moves = hover_moves
	_hovered = hovered_square
	_game_over = game_over_reason != ""

	for child in get_children():
		if child.has_method("is_animating"):
			continue
		child.queue_free()

	_add_pieces(board, skip_squares)
	if hint_arrow != null:
		_add_hint_arrow(hint_arrow)
	queue_redraw()


func _draw():
	_draw_frame()
	_draw_squares()
	if _board.is_empty():
		return
	_draw_highlights()
	_draw_legal_moves()
	_draw_hover()
	_draw_coordinates()
	if _game_over:
		draw_rect(Rect2(Vector2.ZERO, Vector2(BOARD_PX, BOARD_PX)), Color(0.03, 0.04, 0.08, 0.45))


func _draw_frame():
	var outer := Rect2(Vector2(-FRAME, -FRAME), Vector2(BOARD_PX + FRAME * 2, BOARD_PX + FRAME * 2))
	# soft drop shadow
	for i in range(6, 0, -1):
		draw_rect(outer.grow(float(i) * 3.0), Color(0, 0, 0, 0.045), true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = frame_color
	sb.set_corner_radius_all(14)
	sb.border_color = Color("#2a3556")
	sb.set_border_width_all(1)
	draw_style_box(sb, outer)
	# thin gold inlay around the squares
	draw_rect(Rect2(Vector2(-4, -4), Vector2(BOARD_PX + 8, BOARD_PX + 8)), Color(frame_line, 0.85), false, 2.0)


func _draw_squares():
	for r in range(ROWS):
		for c in range(COLS):
			var color = board_light if (r + c) % 2 == 0 else board_dark
			draw_rect(Rect2(cell_pos(r, c), Vector2(CELL_SIZE, CELL_SIZE)), color)


func _tint(r: int, c: int, color: Color, alpha: float):
	draw_rect(Rect2(cell_pos(r, c), Vector2(CELL_SIZE, CELL_SIZE)), Color(color, alpha))


func _draw_highlights():
	if _last_move != null:
		for pos in _last_move:
			_tint(pos[0], pos[1], last_move_color, 0.42)
	if not _selected.is_empty():
		_tint(_selected[0], _selected[1], sel_color, 0.62)
	if _in_check:
		for r in range(ROWS):
			for c in range(COLS):
				if _board[r][c] == _turn[0] + "K":
					var ctr := cell_center(r, c)
					_tint(r, c, check_color, 0.55)
					draw_circle(ctr, CELL_SIZE * 0.47, Color(check_color, 0.55))


func _draw_legal_moves():
	for move in _legal:
		var r = move["to_row"]
		var c = move["to_col"]
		var ctr := cell_center(r, c)
		if _board[r][c] != "":
			draw_arc(ctr, CELL_SIZE * 0.44, 0, TAU, 48, Color(capture_color, 0.85), 5.0, true)
		else:
			draw_circle(ctr, CELL_SIZE * 0.15, legal_dot_color)


func _draw_hover():
	if _hovered.is_empty():
		return
	var src := Rect2(cell_pos(_hovered[0], _hovered[1]), Vector2(CELL_SIZE, CELL_SIZE))
	draw_rect(src.grow(-2), Color(hover_source_color, 0.9), false, 3.0)
	for move in _hover_moves:
		var r = move["to_row"]
		var c = move["to_col"]
		var ctr := cell_center(r, c)
		if _board[r][c] != "":
			var col: Color = hover_friend_color if move.get("is_friendly", false) else hover_guard_color
			draw_arc(ctr, CELL_SIZE * 0.44, 0, TAU, 48, Color(col, 0.9), 4.0, true)
		else:
			draw_circle(ctr, CELL_SIZE * 0.11, Color(hover_legal_color, 0.75))


func _draw_coordinates():
	var font := UITheme.ui(600)
	var fs := 13
	for vc in range(COLS):
		var c := (6 - vc) if flipped else vc
		var txt := char(97 + c)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(vc * CELL_SIZE + CELL_SIZE / 2.0 - w / 2.0, BOARD_PX + FRAME * 0.5 + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, coord_color)
	for vr in range(ROWS):
		var r := (6 - vr) if flipped else vr
		var txt := str(7 - r)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-FRAME * 0.5 - w / 2.0, vr * CELL_SIZE + CELL_SIZE / 2.0 + 5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, coord_color)


# ---------------------------------------------------------------------------
# Child nodes (pieces, hint arrow)
# ---------------------------------------------------------------------------
func _add_pieces(board: Array, skip_squares: Array):
	for r in range(ROWS):
		for c in range(COLS):
			if board[r][c] == "":
				continue
			var skip := false
			for sq in skip_squares:
				if sq[0] == r and sq[1] == c:
					skip = true
					break
			if not skip:
				var p := make_piece_visual(board[r][c])
				p.position = cell_center(r, c)
				add_child(p)


# Token + sprite, centred on (0, 0). Shared with PieceAnimator.
func make_piece_visual(code: String) -> Node2D:
	var container := Node2D.new()
	var image_name = piece_image_names.get(code, "")
	var is_white := code.begins_with("w")

	var token := Panel.new()
	var d := 60
	token.position = Vector2(-d / 2.0, -d / 2.0)
	token.size = Vector2(d, d)
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = white_token_color if is_white else black_token_color
	st.set_corner_radius_all(d / 2)
	st.border_color = white_token_border if is_white else black_token_border
	st.set_border_width_all(2)
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 5
	st.shadow_offset = Vector2(0, 3)
	st.anti_aliasing = true
	token.add_theme_stylebox_override("panel", st)
	container.add_child(token)

	if image_name != "":
		var sprite := Sprite2D.new()
		sprite.texture = _get_texture(image_name)
		sprite.scale = Vector2(1.5, 1.5)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		container.add_child(sprite)
	return container


func _add_hint_arrow(arrow: Array):
	var from_pos := cell_center(arrow[0], arrow[1])
	var to_pos := cell_center(arrow[2], arrow[3])
	var direction := (to_pos - from_pos).normalized()
	var head := 22.0
	var start := from_pos + direction * 24.0
	var base := to_pos - direction * head

	var line := Line2D.new()
	line.add_point(start)
	line.add_point(base)
	line.width = 9
	line.default_color = Color(hint_color, 0.85)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5
	add_child(line)

	var perp := Vector2(-direction.y, direction.x)
	var tip := Polygon2D.new()
	tip.polygon = PackedVector2Array([to_pos, base + perp * head * 0.6, base - perp * head * 0.6])
	tip.color = Color(hint_color, 0.85)
	tip.z_index = 5
	add_child(tip)


func _get_texture(image_name: String) -> Texture2D:
	if image_name in _texture_cache:
		return _texture_cache[image_name]
	var path = "res://piecepng/" + image_name + ".png"
	var texture = load(path) as Texture2D
	if texture == null:
		push_error("Failed to load piece texture: " + path)
		texture = PlaceholderTexture2D.new()
		texture.size = Vector2(32, 32)
	_texture_cache[image_name] = texture
	return texture
