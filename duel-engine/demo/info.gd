#Info.gd
extends CanvasLayer

var _piece_codes = ["wK", "wN", "wC", "wP", "wM", "wD", "wL", "wW"]
var _piece_names = {
	"wK": "King", "wN": "Knight", "wC": "Cardinal", "wP": "Paladin",
	"wM": "Marshal", "wD": "Donkey", "wL": "Lancer", "wW": "Warden"
}
var _piece_descriptions = {
	"wK": "Moves 1 tile in any direction.",
	"wN": "Standard knight (2+1 L-shape).",
	"wC": "Bishop that can also move 1 tile in any direcion.",
	"wP": "Stronger knight (3+1) plus 1-step left/right/up/down.",
	"wM": "Moves like a Rook plus knight.",
	"wD": "Moves diagonally forward 1 (empty) or straight forward 1 to capture. Promotes to Lancer on back rank.",
	"wL": "Moves to any tile exactly 2 away (King distance of 2).",
	"wW": "Moves to any tile within 2 tiles (like a short-range queen)."
}

var _panel: Panel
var _grid_container: GridContainer
var _preview_board: Node2D
var _description_label: Label
var _title_label: Label
var _hovered_piece: String = ""

var _cell_size = 60
var _board_offset = Vector2(400, 80)

var _texture_cache = {}

# Reused across hovers instead of constructing a new DuelEngine (and its
# 64MB SharedTT) on every mouse_entered — this panel only ever needs
# get_piece_attack_squares() on a single-piece board, never a search,
# so one cached instance is all that's required.
var _preview_engine: DuelEngine = null

func _get_preview_engine() -> DuelEngine:
	if _preview_engine == null:
		_preview_engine = DuelEngine.new()
	return _preview_engine

func _ready():
	visible = false
	_create_ui()

func _create_ui():
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.97)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	
	_title_label = Label.new()
	_title_label.text = "Piece Reference — Press I to close"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color("#e94560"))
	_title_label.position = Vector2(50, 30)
	add_child(_title_label)
	
	_grid_container = GridContainer.new()
	_grid_container.columns = 2
	_grid_container.position = Vector2(50, 100)
	_grid_container.size = Vector2(300, 500)
	add_child(_grid_container)
	
	for code in _piece_codes:
		var btn = Button.new()
		btn.text = _piece_names[code]
		btn.custom_minimum_size = Vector2(140, 50)
		btn.add_theme_font_size_override("font_size", 16)
		btn.mouse_entered.connect(func(): _on_piece_hover(code))
		btn.mouse_exited.connect(func(): _on_piece_unhover())
		_grid_container.add_child(btn)
	
	_preview_board = Node2D.new()
	_preview_board.position = _board_offset
	add_child(_preview_board)
	
	_description_label = Label.new()
	_description_label.text = "Hover over a piece to see its moves."
	_description_label.add_theme_font_size_override("font_size", 16)
	_description_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	_description_label.position = Vector2(400, 500)
	_description_label.size = Vector2(400, 100)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_description_label)

func _on_piece_hover(code: String):
	_hovered_piece = code
	_description_label.text = _piece_names[code] + "\n" + _piece_descriptions[code]
	_draw_preview_board(code)

func _on_piece_unhover():
	_hovered_piece = ""
	_description_label.text = "Hover over a piece to see its moves."
	for child in _preview_board.get_children():
		child.queue_free()

func _draw_preview_board(code: String):
	for child in _preview_board.get_children():
		child.queue_free()
	
	for r in range(7):
		for c in range(7):
			var rect = ColorRect.new()
			rect.position = Vector2(c * _cell_size, r * _cell_size)
			rect.size = Vector2(_cell_size, _cell_size)
			rect.color = Color("#e8d5b5") if (r + c) % 2 == 0 else Color("#b58863")
			_preview_board.add_child(rect)
	
	var center_r = 3
	var center_c = 3
	var piece = _create_piece_sprite(center_r, center_c, code)
	_preview_board.add_child(piece)
	
	var engine = _get_preview_engine()
	var board = _make_single_piece_board(code, center_r, center_c)
	engine.set_board(board, "white")
	var moves = engine.get_piece_attack_squares(center_r, center_c)
	
	for m in moves:
		var target_r = m["to_row"]
		var target_c = m["to_col"]
		var highlight = ColorRect.new()
		highlight.position = Vector2(target_c * _cell_size, target_r * _cell_size)
		highlight.size = Vector2(_cell_size, _cell_size)
		
		if m.get("capture", false):
			if m.get("is_friendly", false):
				highlight.color = Color("#3b82f6")
			else:
				highlight.color = Color("#e879f9")
		else:
			highlight.color = Color("#4ade80")
		
		highlight.modulate = Color(1, 1, 1, 0.4)
		_preview_board.add_child(highlight)

func _make_single_piece_board(code: String, r: int, c: int) -> Array:
	var b = []
	for row in range(7):
		var arr = []
		for col in range(7):
			arr.append("")
		b.append(arr)
	b[r][c] = code
	return b

func _create_piece_sprite(r: int, c: int, code: String) -> Node2D:
	var image_name = _get_image_name(code)
	var container = Node2D.new()
	var center = Vector2(c * _cell_size + _cell_size / 2, r * _cell_size + _cell_size / 2)
	container.position = center
	
	var token = Panel.new()
	var token_size = 44
	token.position = Vector2(-token_size / 2, -token_size / 2)
	token.size = Vector2(token_size, token_size)
	var token_style = StyleBoxFlat.new()
	token_style.bg_color = Color("#e2e8f0") if code.begins_with("w") else Color("#1e293b")
	token_style.corner_radius_top_left = token_size / 2
	token_style.corner_radius_top_right = token_size / 2
	token_style.corner_radius_bottom_left = token_size / 2
	token_style.corner_radius_bottom_right = token_size / 2
	token.add_theme_stylebox_override("panel", token_style)
	container.add_child(token)
	
	var texture = _get_texture(image_name)
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2(1.2, 1.2)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.add_child(sprite)
	
	return container

func _get_image_name(code: String) -> String:
	match code:
		"wK", "bK": return "king"
		"wN", "bN": return "knight"
		"wC", "bC": return "cardinal"
		"wP", "bP": return "paladin"
		"wM", "bM": return "marshal"
		"wD", "bD": return "donkey"
		"wL", "bL": return "lancer"
		"wW", "bW": return "warden"
	return ""

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

func toggle():
	visible = not visible
	if not visible:
		_hovered_piece = ""
		_description_label.text = "Hover over a piece to see its moves."
		for child in _preview_board.get_children():
			child.queue_free()
