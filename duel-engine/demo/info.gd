#Info.gd
# "Pieces" reference overlay: pick a piece to see where it moves.
extends CanvasLayer

var _piece_codes = ["wK", "wN", "wC", "wP", "wM", "wD", "wL", "wW"]
var _piece_names = {
	"wK": "King", "wN": "Knight", "wC": "Cardinal", "wP": "Paladin",
	"wM": "Marshal", "wD": "Donkey", "wL": "Lancer", "wW": "Warden"
}
var _piece_descriptions = {
	"wK": "Moves 1 square in any direction.",
	"wN": "Standard knight: an L-shaped jump (2 + 1).",
	"wC": "Slides diagonally like a bishop, and can also step 1 square straight.",
	"wP": "A longer knight jump (3 + 1), plus a 1-square step left, right, up or down.",
	"wM": "Slides straight like a rook, and also jumps like a knight.",
	"wD": "Moves 1 square diagonally forward onto an empty square, captures 1 square straight ahead. Promotes to a Lancer on the far rank.",
	"wL": "Jumps to any square exactly 2 away (straight, diagonal or knight-shaped).",
	"wW": "Moves to any square within 2 steps: 1 in any direction, or 2 straight.",
}

const CELL := 58
const BOARD_POS := Vector2(640, 150)

var _root: Control
var _preview: Control
var _name_label: Label
var _description_label: Label
var _buttons := {}
var _selected := ""

# Reused instead of building a DuelEngine (and its 64MB table) per click;
# only get_piece_attack_squares() on a single-piece board is ever needed.
var _preview_engine: DuelEngine = null


class Preview:
	extends Control
	var code := ""
	var targets: Array = []
	var cell := 58

	func _draw():
		var light := Color("#e8dcc2")
		var dark := Color("#a27d58")
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("#1a1f33")
		bg.set_corner_radius_all(12)
		draw_style_box(bg, Rect2(Vector2(-14, -14), Vector2(cell * 7 + 28, cell * 7 + 28)))
		for r in 7:
			for c in 7:
				draw_rect(Rect2(c * cell, r * cell, cell, cell), light if (r + c) % 2 == 0 else dark)
		draw_rect(Rect2(-3, -3, cell * 7 + 6, cell * 7 + 6), Color("#e2b65a"), false, 2.0)
		for t in targets:
			var ctr := Vector2(t.y * cell + cell / 2.0, t.x * cell + cell / 2.0)
			draw_rect(Rect2(t.y * cell, t.x * cell, cell, cell), Color("#3cc08d", 0.35))
			draw_circle(ctr, cell * 0.14, Color("#0d1323", 0.55))


func _get_preview_engine() -> DuelEngine:
	if _preview_engine == null:
		_preview_engine = DuelEngine.new()
	return _preview_engine


func _ready():
	layer = 5
	visible = false
	_create_ui()


func _create_ui():
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title := UITheme.label("The Pieces", 36, UITheme.GOLD_LIGHT, UITheme.display(700))
	title.position = Vector2(110, 52)
	_root.add_child(title)
	var sub := UITheme.label("Pick a piece to see where it can move from the centre of the board.", 15, UITheme.TEXT_DIM, UITheme.ui(500))
	sub.position = Vector2(112, 104)
	_root.add_child(sub)

	var close := UITheme.button("Close  (I)", "secondary", 15, 40)
	close.position = Vector2(1050, 52)
	close.size = Vector2(130, 40)
	close.pressed.connect(toggle)
	_root.add_child(close)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.position = Vector2(110, 160)
	_root.add_child(grid)
	var group := ButtonGroup.new()
	for code in _piece_codes:
		var b := UITheme.pill("", UITheme.GOLD, 16, 64)
		b.custom_minimum_size = Vector2(220, 64)
		b.button_group = group
		var row := UITheme.hbox(12)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var tok := UITheme.piece_token(code, 42)
		tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tok)
		var nm := UITheme.label(_piece_names[code], 17, UITheme.TEXT, UITheme.ui(600))
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(nm)
		b.toggled.connect(func(on): if on: _show_piece(code))
		b.mouse_entered.connect(func(): _show_piece(code))
		grid.add_child(b)
		_buttons[code] = b

	_preview = Preview.new()
	_preview.cell = CELL
	_preview.position = BOARD_POS
	_preview.size = Vector2(CELL * 7, CELL * 7)
	_root.add_child(_preview)

	_name_label = UITheme.label("", 24, UITheme.GOLD_LIGHT, UITheme.display(700))
	_name_label.position = Vector2(110, 480)
	_root.add_child(_name_label)
	_description_label = UITheme.label("", 16, UITheme.TEXT, UITheme.ui(500))
	_description_label.position = Vector2(110, 520)
	_description_label.size = Vector2(450, 140)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_description_label)

	_buttons["wK"].button_pressed = true


func _show_piece(code: String):
	_selected = code
	_name_label.text = _piece_names[code]
	_description_label.text = _piece_descriptions[code]
	for ch in _preview.get_children():
		ch.queue_free()
	var engine = _get_preview_engine()
	engine.set_board(_make_single_piece_board(code, 3, 3), "white")
	var targets: Array = []
	for m in engine.get_piece_attack_squares(3, 3):
		targets.append(Vector2i(m["to_row"], m["to_col"]))
	_preview.targets = targets
	_preview.queue_redraw()
	var tok := UITheme.piece_token(code, 50)
	tok.position = Vector2(3 * CELL + (CELL - 50) / 2.0, 3 * CELL + (CELL - 50) / 2.0)
	_preview.add_child(tok)


func _make_single_piece_board(code: String, r: int, c: int) -> Array:
	var b = []
	for row in range(7):
		var arr = []
		for col in range(7):
			arr.append("")
		b.append(arr)
	b[r][c] = code
	return b


func toggle():
	visible = not visible
	if visible and _selected != "":
		_show_piece(_selected)
