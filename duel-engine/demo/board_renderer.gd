#BoardRenderer.gd
extends Node2D

const ROWS = 7
const COLS = 7
const CELL_SIZE = 80

# Modern dark theme palette
var board_light = Color("#d4c5a9")
var board_dark = Color("#8b7355")
var sel_color = Color("#4ade80")
var hover_color = Color("#1e40af")
var check_color = Color("#ef4444")
var last_move_color = Color("#fbbf24")
var legal_dot_color = Color("#4ade80")
var capture_color = Color("#ef4444")
var hover_legal_color = Color("#22d3ee")
var hover_guard_color = Color("#e879f9")
var hover_source_color = Color("#fbbf24")

var white_token_color = Color("#e2e8f0")
var black_token_color = Color("#1e293b")

# Board shadow / frame
var board_bg_color = Color("#0f172a")
var board_border_color = Color("#334155")
var board_shadow_color = Color(0, 0, 0, 0.4)

var piece_image_names = {
	"wK": "king", "wN": "knight", "wC": "cardinal", "wP": "paladin",
	"wM": "marshal", "wD": "donkey", "wL": "lancer", "wW": "warden",
	"bK": "king", "bN": "knight", "bC": "cardinal", "bP": "paladin",
	"bM": "marshal", "bD": "donkey", "bL": "lancer", "bW": "warden"
}

var _texture_cache = {}

func render(board: Array, selected: Array, legal_moves: Array, last_move, in_check: bool, turn: String, hint_arrow = null, hover_moves: Array = [], game_over_reason: String = "", winner: String = "", hovered_square: Array = [], skip_squares: Array = []):
	for child in get_children():
		if child.has_method("is_animating"):
			continue
		child.queue_free()

	_draw_board_frame()
	_draw_squares()
	_draw_highlights(selected, last_move, in_check, turn)
	_draw_legal_moves(legal_moves, board)
	_draw_pieces(board, skip_squares)
	_draw_hover_moves(hover_moves, board, hovered_square)
	_draw_coordinates()
	if hint_arrow != null:
		_draw_hint_arrow(hint_arrow)
	if game_over_reason != "":
		_draw_game_over_overlay(game_over_reason, winner)

func _draw_board_frame():
	var board_w = COLS * CELL_SIZE
	var board_h = ROWS * CELL_SIZE
	var padding = 12
	var corner_radius = 8

	# Drop shadow
	var shadow = Panel.new()
	shadow.position = Vector2(padding, padding)
	shadow.size = Vector2(board_w, board_h)
	var shadow_style = StyleBoxFlat.new()
	shadow_style.bg_color = board_shadow_color
	shadow_style.corner_radius_top_left = corner_radius
	shadow_style.corner_radius_top_right = corner_radius
	shadow_style.corner_radius_bottom_left = corner_radius
	shadow_style.corner_radius_bottom_right = corner_radius
	shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(shadow)

	# Outer border / frame
	var frame = Panel.new()
	frame.position = Vector2.ZERO
	frame.size = Vector2(board_w, board_h)
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = board_bg_color
	frame_style.corner_radius_top_left = corner_radius
	frame_style.corner_radius_top_right = corner_radius
	frame_style.corner_radius_bottom_left = corner_radius
	frame_style.corner_radius_bottom_right = corner_radius
	frame_style.border_width_left = 3
	frame_style.border_width_right = 3
	frame_style.border_width_top = 3
	frame_style.border_width_bottom = 3
	frame_style.border_color = board_border_color
	frame.add_theme_stylebox_override("panel", frame_style)
	add_child(frame)

func _draw_squares():
	for r in range(ROWS):
		for c in range(COLS):
			var color = board_light if (r + c) % 2 == 0 else board_dark
			var rect = ColorRect.new()
			rect.position = Vector2(c * CELL_SIZE, r * CELL_SIZE)
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			rect.color = color
			add_child(rect)

func _draw_hint_arrow(arrow: Array):
	var fr = arrow[0]
	var fc = arrow[1]
	var to_r = arrow[2]
	var to_c = arrow[3]

	var from_pos = Vector2(fc * CELL_SIZE + CELL_SIZE / 2, fr * CELL_SIZE + CELL_SIZE / 2)
	var to_pos = Vector2(to_c * CELL_SIZE + CELL_SIZE / 2, to_r * CELL_SIZE + CELL_SIZE / 2)

	var direction = (to_pos - from_pos).normalized()
	var arrow_size = 16.0
	var angle = 0.5

	var p1 = to_pos - direction.rotated(angle) * arrow_size
	var p2 = to_pos - direction.rotated(-angle) * arrow_size
	var base_center = (p1 + p2) / 2

	var line = Line2D.new()
	line.add_point(from_pos)
	line.add_point(base_center)
	line.width = 5
	line.default_color = Color("#22d3ee")
	add_child(line)

	var head = Polygon2D.new()
	head.polygon = PackedVector2Array([to_pos, p1, p2])
	head.color = Color("#22d3ee")
	add_child(head)

func _draw_highlights(selected, last_move, in_check: bool, turn: String):
	if last_move != null:
		for pos in last_move:
			add_child(_create_highlight(pos[0], pos[1], last_move_color))

	if not selected.is_empty():
		add_child(_create_highlight(selected[0], selected[1], sel_color))

	if in_check:
		for r in range(ROWS):
			for c in range(COLS):
				var piece = get_parent().game_state.get_piece_at(r, c)
				if piece == turn[0] + "K":
					add_child(_create_highlight(r, c, check_color, 0.4))

func _draw_hover_moves(hover_moves: Array, board: Array, hovered_square: Array):
	if not hovered_square.is_empty():
		var hr = hovered_square[0]
		var hc = hovered_square[1]
		var source = _create_highlight(hr, hc, hover_source_color, 0.35)
		add_child(source)

	for move in hover_moves:
		var to_r = move["to_row"]
		var to_c = move["to_col"]
		if board[to_r][to_c] != "":
			if move.get("is_friendly", false):
				add_child(_create_highlight(to_r, to_c, Color("#3b82f6"), 0.5))
			else:
				add_child(_create_highlight(to_r, to_c, hover_guard_color, 0.5))
		else:
			add_child(_create_legal_dot(to_r, to_c))

func _draw_legal_moves(legal_moves: Array, board: Array):
	for move in legal_moves:
		var to_r = move["to_row"]
		var to_c = move["to_col"]
		if board[to_r][to_c] != "":
			add_child(_create_capture_marker(to_r, to_c))
		else:
			add_child(_create_legal_dot(to_r, to_c))

func _draw_pieces(board: Array, skip_squares: Array = []):
	for r in range(ROWS):
		for c in range(COLS):
			if board[r][c] != "":
				var skip := false
				for sq in skip_squares:
					if sq[0] == r and sq[1] == c:
						skip = true
						break
				if skip:
					continue
				add_child(_create_piece(r, c, board[r][c]))

func _draw_coordinates():
	var coord_color = Color("#94a3b8")

	for i in range(COLS):
		var label = Label.new()
		label.text = char(97 + i)
		label.position = Vector2(i * CELL_SIZE + CELL_SIZE/2 - 5, ROWS * CELL_SIZE + 6)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", coord_color)
		add_child(label)

	for i in range(ROWS):
		var label = Label.new()
		label.text = str(7 - i)
		label.position = Vector2(-18, i * CELL_SIZE + CELL_SIZE/2 - 10)
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", coord_color)
		add_child(label)

func _draw_game_over_overlay(reason: String, winner: String):
	var overlay = ColorRect.new()
	overlay.position = Vector2(0, 0)
	overlay.size = Vector2(COLS * CELL_SIZE, ROWS * CELL_SIZE)
	overlay.color = Color(0, 0, 0, 0.6)
	add_child(overlay)

	var label = Label.new()
	match reason:
		"checkmate", "no_legal_moves":
			label.text = "CHECKMATE\n" + winner.to_upper() + " WINS!"
		"40move":
			label.text = "DRAW!\n(40 moves without capture)"
		"insufficient":
			label.text = "DRAW!\n(Insufficient material)"
		_:
			label.text = "GAME OVER"

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color("#fbbf24"))
	label.add_theme_color_override("font_shadow_color", Color("#000000"))

	var text_size = label.get_theme_font("font").get_string_size(label.text, label.horizontal_alignment, -1, 42)
	label.position = Vector2(
		(COLS * CELL_SIZE) / 2 - text_size.x / 2,
		(ROWS * CELL_SIZE) / 2 - text_size.y / 2
	)
	add_child(label)

func _create_highlight(r: int, c: int, color: Color, alpha: float = 0.3):
	var rect = ColorRect.new()
	rect.position = Vector2(c * CELL_SIZE + 2, r * CELL_SIZE + 2)
	rect.size = Vector2(CELL_SIZE - 4, CELL_SIZE - 4)
	rect.color = color
	rect.modulate = Color(1, 1, 1, alpha)
	return rect

func _create_legal_dot(r: int, c: int):
	var dot = ColorRect.new()
	var size = 12
	dot.position = Vector2(c * CELL_SIZE + CELL_SIZE/2 - size/2, r * CELL_SIZE + CELL_SIZE/2 - size/2)
	dot.size = Vector2(size, size)
	dot.color = legal_dot_color
	return dot

func _create_capture_marker(r: int, c: int):
	var panel = Panel.new()
	panel.position = Vector2(c * CELL_SIZE + 4, r * CELL_SIZE + 4)
	panel.size = Vector2(CELL_SIZE - 8, CELL_SIZE - 8)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = capture_color
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _create_piece(r: int, c: int, code: String):
	var image_name = piece_image_names.get(code, "")
	if image_name == "":
		return Label.new()

	var is_white = code.begins_with("w")
	var token_color = white_token_color if is_white else black_token_color

	var container = Node2D.new()
	var center = Vector2(c * CELL_SIZE + CELL_SIZE / 2, r * CELL_SIZE + CELL_SIZE / 2)
	container.position = center

	var token = Panel.new()
	var token_size = 56
	token.position = Vector2(-token_size / 2, -token_size / 2)
	token.size = Vector2(token_size, token_size)
	var token_style = StyleBoxFlat.new()
	token_style.bg_color = token_color
	token_style.corner_radius_top_left = token_size / 2
	token_style.corner_radius_top_right = token_size / 2
	token_style.corner_radius_bottom_left = token_size / 2
	token_style.corner_radius_bottom_right = token_size / 2
	token.add_theme_stylebox_override("panel", token_style)
	container.add_child(token)

	var texture = _get_texture(image_name)
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2(1.5, 1.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	container.add_child(sprite)

	return container

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
