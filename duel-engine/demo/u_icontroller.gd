#u_icontroller.gd
# In-game interface: a player bar above and below the board (name, level,
# captured pieces, clock), and a sidebar with the evaluation, move list and
# controls. Layout is in logical pixels of the 1280x800 design viewport; the
# window's stretch mode scales it to any window size.
extends CanvasLayer

# ---------------------------------------------------------------------------
# Layout (must match StartGameplay.BOARD_ORIGIN)
# ---------------------------------------------------------------------------
const BOARD_ORIGIN := Vector2(138, 116)
const BOARD_PX := 560
const FRAME := 26
const BAR_H := 56
const SIDEBAR_RECT := Rect2(748, 24, 420, 744)

const CLOCK_WARN_SECONDS := 60.0
const CLOCK_DANGER_SECONDS := 30.0

# Graph is in pawns (engine centipawns / 100). Mates are pinned to +/-CAP.
const EVAL_GRAPH_CAP := 20.0
const EVAL_GRAPH_MIN_BOUND := 2.0

const START_COUNTS := {"K": 1, "N": 2, "C": 1, "P": 1, "W": 1, "M": 1, "D": 7}
const PIECE_ORDER := ["M", "C", "P", "W", "L", "N", "D"]


# ---------------------------------------------------------------------------
# Small custom-drawn widgets
# ---------------------------------------------------------------------------
# Radial "pie" that unfills clockwise while the per-turn grace period drains.
class GraceRing:
	extends Control
	var fraction: float = 1.0
	var ring_color: Color = Color("#5b8df0")

	func _draw():
		var r = min(size.x, size.y) / 2.0 - 2.0
		if r <= 0.0:
			return
		var center = size / 2.0
		draw_arc(center, r, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 3.0, true)
		if fraction > 0.001:
			draw_arc(center, r, -PI / 2.0, -PI / 2.0 + TAU * fraction, 32, ring_color, 3.0, true)

	func set_fraction(f: float):
		fraction = clampf(f, 0.0, 1.0)
		queue_redraw()


# Horizontal White-vs-Black balance bar.
class EvalBar:
	extends Control
	var value := 0.0  # White-relative pawns (mates come in as +/-CAP)

	func _draw():
		var w := size.x
		var h := size.y
		var share := 0.5 + 0.5 * tanh(value / 4.0)   # 0 = Black winning, 1 = White
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.SLATE
		bg.set_corner_radius_all(int(h / 2))
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var fill := StyleBoxFlat.new()
		fill.bg_color = UITheme.IVORY
		fill.set_corner_radius_all(int(h / 2))
		if share > 0.02:
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(max(h, w * share), h)))
		draw_line(Vector2(w / 2.0, 1), Vector2(w / 2.0, h - 1), Color(UITheme.GOLD, 0.7), 2.0)


# Evaluation history line chart.
class EvalGraph:
	extends Control
	var points: Array = []   # pawns, White-relative, one per position
	var marker := -1         # position being reviewed (-1 = none)
	var cap := 20.0
	var min_bound := 2.0

	func _draw():
		var bg := StyleBoxFlat.new()
		bg.bg_color = UITheme.SURFACE_LO
		bg.set_corner_radius_all(10)
		bg.border_color = UITheme.BORDER_SOFT
		bg.set_border_width_all(1)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var m := 10.0
		var w := size.x - 2 * m
		var h := size.y - 2 * m
		var cy := m + h / 2.0
		draw_line(Vector2(m, cy), Vector2(m + w, cy), Color(UITheme.BORDER, 0.9), 1.0)

		var bound := min_bound
		for p in points:
			bound = maxf(bound, absf(clampf(p, -cap, cap)))
		var font := UITheme.ui(600)
		draw_string(font, Vector2(m + 2, m + 10), "+%d" % int(round(bound)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_FAINT)
		draw_string(font, Vector2(m + 2, m + h - 1), "-%d" % int(round(bound)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.TEXT_FAINT)
		if points.size() < 2:
			return

		var pts := PackedVector2Array()
		var n := points.size()
		for i in n:
			var x := m + w * float(i) / float(n - 1)
			var y := cy - clampf(points[i] / bound, -1.0, 1.0) * (h / 2.0)
			pts.append(Vector2(x, y))
		# shaded areas: ivory above the centre line, slate below
		for i in n - 1:
			var a := pts[i]
			var b := pts[i + 1]
			if (a.y - cy) * (b.y - cy) < 0.0:
				# the line crosses zero inside this segment: split it there, otherwise
				# the quad folds into a self-intersecting "bow tie"
				var x := a.x + (b.x - a.x) * (cy - a.y) / (b.y - a.y)
				_shade(PackedVector2Array([a, Vector2(x, cy), Vector2(a.x, cy)]), a.y < cy)
				_shade(PackedVector2Array([Vector2(x, cy), b, Vector2(b.x, cy)]), b.y < cy)
			else:
				_shade(PackedVector2Array([a, b, Vector2(b.x, cy), Vector2(a.x, cy)]), (a.y + b.y) / 2.0 < cy)
		draw_polyline(pts, UITheme.GOLD, 2.0, true)
		if marker >= 0 and marker < n:
			draw_line(Vector2(pts[marker].x, m), Vector2(pts[marker].x, m + h), Color(UITheme.GOLD_LIGHT, 0.45), 1.5)
			draw_circle(pts[marker], 5.0, UITheme.GOLD_LIGHT)
		else:
			draw_circle(pts[n - 1], 4.0, UITheme.GOLD_LIGHT)

	# Fills one shaded piece, skipping slivers with (almost) no area -- Godot
	# can't triangulate those and logs "Invalid polygon data".
	func _shade(raw: PackedVector2Array, above: bool):
		var poly := PackedVector2Array()
		for p in raw:  # drop repeated corners (a point lying exactly on zero)
			if poly.is_empty() or not p.is_equal_approx(poly[poly.size() - 1]):
				poly.append(p)
		if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			return
		var area := 0.0
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			area += p.x * q.y - q.x * p.y
		if absf(area) < 1.0:
			return
		draw_colored_polygon(poly, Color(UITheme.IVORY, 0.16) if above else Color(0.35, 0.42, 0.62, 0.22))


# A player's strip above or below the board.
class PlayerBar:
	extends PanelContainer
	var color := "white"
	var token_holder: Control
	var name_label: Label
	var sub_label: Label
	var captured_box: HBoxContainer
	var thinking_label: Label
	var clock_panel: PanelContainer
	var clock_label: Label
	var grace: GraceRing
	var _active := false
	var _dots := 0.0

	func build(c: String):
		color = c
		custom_minimum_size = Vector2(0, 56)
		var row := UITheme.hbox(12)
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		add_child(row)
		token_holder = UITheme.piece_token(("w" if c == "white" else "b") + "K", 38)
		token_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(token_holder)
		var names := UITheme.vbox(0)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(names)
		name_label = UITheme.label(c.capitalize(), 17, UITheme.TEXT, UITheme.ui(650))
		names.add_child(name_label)
		sub_label = UITheme.label("", 12, UITheme.TEXT_DIM, UITheme.ui(500))
		names.add_child(sub_label)
		captured_box = UITheme.hbox(1)
		captured_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(captured_box)
		row.add_child(UITheme.spacer())
		thinking_label = UITheme.label("", 13, UITheme.GOLD_LIGHT, UITheme.ui(600))
		thinking_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(thinking_label)
		clock_panel = UITheme.panel(UITheme.box(UITheme.SURFACE_LO, 9, UITheme.BORDER, 1, 0))
		clock_panel.custom_minimum_size = Vector2(124, 40)
		clock_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(clock_panel)
		var crow := UITheme.hbox(8)
		crow.alignment = BoxContainer.ALIGNMENT_CENTER
		clock_panel.add_child(crow)
		grace = GraceRing.new()
		grace.custom_minimum_size = Vector2(18, 18)
		grace.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grace.visible = false
		crow.add_child(grace)
		clock_label = UITheme.label("--:--", 22, UITheme.TEXT, UITheme.ui(700))
		crow.add_child(clock_label)
		set_active(false)

	func set_active(a: bool):
		_active = a
		var st := UITheme.box(UITheme.SURFACE if a else UITheme.INK_2, 12,
			UITheme.GOLD if a else UITheme.BORDER_SOFT, 2 if a else 1, 0)
		st.content_margin_left = 12
		st.content_margin_right = 8
		add_theme_stylebox_override("panel", st)
		var cst := UITheme.box(UITheme.GOLD if a else UITheme.SURFACE_LO, 9, UITheme.GOLD if a else UITheme.BORDER, 1, 0)
		clock_panel.add_theme_stylebox_override("panel", cst)
		clock_label.add_theme_color_override("font_color", Color("#1b1406") if a else UITheme.TEXT_DIM)

	func set_thinking(on: bool):
		thinking_label.visible = on
		_dots = 0.0
		set_process(on)

	func _process(delta):
		_dots += delta * 3.0
		thinking_label.text = "thinking" + ".".repeat(int(_dots) % 4)

	func set_captured(codes: Array):
		for ch in captured_box.get_children():
			ch.queue_free()
		for code in codes:
			var t := TextureRect.new()
			t.texture = load("res://piecepng/%s.png" % code)
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			t.custom_minimum_size = Vector2(20, 20)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.modulate = Color(1, 1, 1, 0.9)
			captured_box.add_child(t)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var turn_label: Label          # "White to move"
var turn_counter_label: Label  # "Turn 3"
var eval_label: Label
var status_label: Label
var hint_toggle: CheckButton
var new_game_btn: Button
var flip_btn: Button
var info_btn: Button
var clear_drawings_btn: Button
var board_drawer: Node = null   # brddrwr.gd (arrows and square marks)

var top_bar: PlayerBar
var bottom_bar: PlayerBar
var _bars := {}            # "white"/"black" -> PlayerBar
var _eval_bar: EvalBar
var _eval_graph: EvalGraph
var _eval_box: VBoxContainer     # bar + graph, hidden when the eval is turned off
var _eval_hidden_label: Label
var _eval_toggle_btn: Button
var _eval_head: HBoxContainer
var undo_btn: Button
var settings_btn: Button
# Puzzle mode panel (replaces the evaluation while solving)
var _puzzle_box: VBoxContainer
var _puzzle_title: Label
var _puzzle_prompt: Label
var _puzzle_feedback: Label
var _puzzle_hint_btn: Button
var _puzzle_solution_btn: Button
var _puzzle_next_btn: Button
var _puzzle_mode := false
var eval_visible := true         # mirrors Settings "show_eval"
var _moves_grid: GridContainer
var _moves_scroll: ScrollContainer
var _game_over_layer: Control = null
var _mode_label: Label   # starting-position name (hidden for Classic)
var _review_bar: HBoxContainer
var _review_label: Label
var _review_btns := {}
var _review_ply := -1   # -1 = showing the live / final position

var turn_number: int = 1
var eval_history = []
var last_logged_eval = 999999.0
var last_logged_label := ""

var _clocks_visible := false
var _flipped := false
var _player_types := {"white": "human", "black": "human"}


func _ready():
	layer = 1
	_create_ui()
	_create_board_drawer()
	var game_state = get_parent().get_node("GameState")
	game_state.turn_changed.connect(_on_turn_changed)
	game_state.game_ended.connect(_on_game_ended)
	game_state.thinking_started.connect(_on_thinking)
	game_state.thinking_finished.connect(_on_thinking_done)


func _create_board_drawer():
	var drawer = preload("res://brddrwr.gd").new()
	drawer.name = "brddrwr"
	add_child(drawer)
	board_drawer = drawer

func align_drawer_to_board(board_global_pos: Vector2):
	if board_drawer != null:
		board_drawer.align_to_board(board_global_pos)


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------
func _create_ui():
	var frame_x := BOARD_ORIGIN.x - FRAME
	var frame_w := BOARD_PX + FRAME * 2

	top_bar = PlayerBar.new()
	top_bar.build("white")
	top_bar.position = Vector2(frame_x, BOARD_ORIGIN.y - FRAME - 10 - BAR_H)
	top_bar.size = Vector2(frame_w, BAR_H)
	add_child(top_bar)

	bottom_bar = PlayerBar.new()
	bottom_bar.build("black")
	bottom_bar.position = Vector2(frame_x, BOARD_ORIGIN.y + BOARD_PX + FRAME + 10)
	bottom_bar.size = Vector2(frame_w, BAR_H)
	add_child(bottom_bar)
	_assign_bars()

	var side := UITheme.panel(UITheme.card(18))
	side.position = SIDEBAR_RECT.position
	side.size = SIDEBAR_RECT.size
	add_child(side)
	var col := UITheme.vbox(14)
	side.add_child(col)

	# Header
	var header := UITheme.hbox(12)
	col.add_child(header)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)
	var titles := UITheme.vbox(0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.custom_minimum_size.x = 1   # long status text clips instead of widening the sidebar
	header.add_child(titles)
	titles.add_child(UITheme.label("Duel of the Seven Crowns", 19, UITheme.GOLD_LIGHT, UITheme.display(700)))
	var turn_row := UITheme.hbox(8)
	titles.add_child(turn_row)
	turn_counter_label = UITheme.label("Turn 1", 13, UITheme.TEXT_DIM, UITheme.ui(600))
	turn_row.add_child(turn_counter_label)
	turn_row.add_child(UITheme.label("•", 13, UITheme.TEXT_FAINT))
	turn_label = UITheme.label("White to move", 13, UITheme.TEXT, UITheme.ui(600))
	turn_label.clip_text = true
	turn_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_row.add_child(turn_label)
	_mode_label = UITheme.label("", 13, UITheme.GOLD, UITheme.ui(650))
	_mode_label.visible = false
	turn_row.add_child(_mode_label)

	# Status line (check, game over, ...)
	status_label = UITheme.label("", 14, UITheme.GOLD_LIGHT, UITheme.ui(600))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.visible = false
	col.add_child(status_label)

	# Puzzle panel (only in puzzle mode)
	_puzzle_box = UITheme.vbox(8)
	_puzzle_box.visible = false
	col.add_child(_puzzle_box)
	_puzzle_box.add_child(UITheme.heading("Puzzle"))
	_puzzle_title = UITheme.label("", 22, UITheme.GOLD_LIGHT, UITheme.display(700))
	_puzzle_box.add_child(_puzzle_title)
	_puzzle_prompt = UITheme.label("", 14, UITheme.TEXT, UITheme.ui(550))
	_puzzle_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_puzzle_box.add_child(_puzzle_prompt)
	_puzzle_feedback = UITheme.label("", 14, UITheme.TEXT_DIM, UITheme.ui(600))
	_puzzle_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_puzzle_box.add_child(_puzzle_feedback)
	var prow := UITheme.hbox(8)
	_puzzle_box.add_child(prow)
	_puzzle_hint_btn = UITheme.button("Hint", "secondary", 14, 36)
	_puzzle_hint_btn.tooltip_text = "Highlight the piece to move"
	_puzzle_hint_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_puzzle_hint_btn.pressed.connect(func(): get_parent().puzzle_hint())
	prow.add_child(_puzzle_hint_btn)
	_puzzle_solution_btn = UITheme.button("Solution", "secondary", 14, 36)
	_puzzle_solution_btn.tooltip_text = "Play the answer on the board"
	_puzzle_solution_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_puzzle_solution_btn.pressed.connect(func(): get_parent().puzzle_show_solution())
	prow.add_child(_puzzle_solution_btn)
	_puzzle_next_btn = UITheme.button("Next puzzle  ›", "secondary", 14, 36)
	_puzzle_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_puzzle_next_btn.pressed.connect(func(): get_parent().next_puzzle())
	prow.add_child(_puzzle_next_btn)

	# Evaluation (can be hidden so a game isn't spoiled by the engine)
	var eval_head := UITheme.hbox(8)
	_eval_head = eval_head
	col.add_child(eval_head)
	var eh := UITheme.heading("Evaluation")
	eh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eval_head.add_child(eh)
	_eval_hidden_label = UITheme.label("hidden", 12, UITheme.TEXT_FAINT, UITheme.ui(500))
	_eval_hidden_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eval_head.add_child(_eval_hidden_label)
	eval_head.add_child(UITheme.spacer())
	_eval_toggle_btn = UITheme.button("Hide", "ghost", 12, 24)
	_eval_toggle_btn.custom_minimum_size.x = 58
	_eval_toggle_btn.tooltip_text = "Show or hide the evaluation bar and graph (E)"
	_eval_toggle_btn.pressed.connect(toggle_eval)
	eval_head.add_child(_eval_toggle_btn)
	_eval_box = UITheme.vbox(10)
	col.add_child(_eval_box)
	var eval_row := UITheme.hbox(12)
	_eval_box.add_child(eval_row)
	_eval_bar = EvalBar.new()
	_eval_bar.custom_minimum_size = Vector2(0, 14)
	_eval_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eval_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	eval_row.add_child(_eval_bar)
	eval_label = UITheme.label("+0.00", 22, UITheme.TEXT, UITheme.ui(700))
	eval_label.custom_minimum_size = Vector2(86, 0)
	eval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	eval_row.add_child(eval_label)
	_eval_graph = EvalGraph.new()
	_eval_graph.custom_minimum_size = Vector2(0, 104)
	_eval_graph.cap = EVAL_GRAPH_CAP
	_eval_graph.min_bound = EVAL_GRAPH_MIN_BOUND
	_eval_box.add_child(_eval_graph)
	_load_settings()
	_apply_eval_visible()

	# Moves
	col.add_child(UITheme.heading("Moves"))
	var well := UITheme.panel(UITheme.box(UITheme.SURFACE_LO, 10, UITheme.BORDER_SOFT, 1, 10))
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(well)
	_moves_scroll = ScrollContainer.new()
	_moves_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	well.add_child(_moves_scroll)
	_moves_grid = GridContainer.new()
	_moves_grid.columns = 3
	_moves_grid.add_theme_constant_override("h_separation", 14)
	_moves_grid.add_theme_constant_override("v_separation", 4)
	_moves_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves_scroll.add_child(_moves_grid)

	# Review controls (only after the game is over)
	_review_bar = UITheme.hbox(6)
	_review_bar.visible = false
	col.add_child(_review_bar)
	for spec in [["first", "«", "First position (Home)"], ["prev", "‹", "Previous move (Left arrow)"],
			["next", "›", "Next move (Right arrow)"], ["last", "»", "Final position (End)"]]:
		var b := UITheme.button(spec[1], "secondary", 20, 36)
		b.custom_minimum_size.x = 48
		b.tooltip_text = spec[2]
		b.pressed.connect(_on_review_button.bind(spec[0]))
		_review_bar.add_child(b)
		_review_btns[spec[0]] = b
	_review_bar.add_child(UITheme.spacer())
	_review_label = UITheme.label("", 14, UITheme.TEXT_DIM, UITheme.ui(600))
	_review_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_review_bar.add_child(_review_label)

	# Hint toggle
	hint_toggle = CheckButton.new()
	hint_toggle.text = "Show best move"
	hint_toggle.focus_mode = Control.FOCUS_NONE
	hint_toggle.add_theme_font_override("font", UITheme.ui(600))
	hint_toggle.add_theme_font_size_override("font_size", 14)
	hint_toggle.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint_toggle.add_theme_color_override("font_hover_color", UITheme.TEXT)
	hint_toggle.add_theme_color_override("font_pressed_color", UITheme.TEXT)
	hint_toggle.add_theme_color_override("font_hover_pressed_color", UITheme.TEXT)
	hint_toggle.toggled.connect(_on_hint_toggled)
	col.add_child(hint_toggle)

	# Buttons
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	col.add_child(grid)
	undo_btn = UITheme.button("Undo", "secondary", 14, 38)
	undo_btn.tooltip_text = "Take back your last move (Ctrl+Z)"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.pressed.connect(func(): get_parent().undo_move())
	undo_btn.disabled = true
	grid.add_child(undo_btn)
	flip_btn = UITheme.button("Flip", "secondary", 14, 38)
	flip_btn.tooltip_text = "Turn the board around (F)"
	flip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flip_btn.pressed.connect(_on_flip_pressed)
	grid.add_child(flip_btn)
	clear_drawings_btn = UITheme.button("Clear", "secondary", 14, 38)
	clear_drawings_btn.tooltip_text = "Remove arrows and marked squares (C)"
	clear_drawings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_drawings_btn.pressed.connect(_on_clear_drawings_pressed)
	grid.add_child(clear_drawings_btn)
	info_btn = UITheme.button("Pieces", "secondary", 14, 38)
	info_btn.tooltip_text = "How every piece moves (I)"
	info_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_btn.pressed.connect(_on_info_pressed)
	grid.add_child(info_btn)
	var bottom_row := UITheme.hbox(8)
	col.add_child(bottom_row)
	settings_btn = UITheme.button("Settings", "secondary", 14, 44)
	settings_btn.custom_minimum_size.x = 110
	settings_btn.tooltip_text = "Board, sound and display options"
	settings_btn.pressed.connect(func(): get_parent().open_settings())
	bottom_row.add_child(settings_btn)
	new_game_btn = UITheme.button("New game", "primary", 16, 44)
	new_game_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_game_btn.pressed.connect(_on_new_game)
	bottom_row.add_child(new_game_btn)


# ---- Undo / puzzle mode -----------------------------------------------------
func set_undo_enabled(on: bool):
	if undo_btn != null:
		undo_btn.disabled = not on

# Called after GameState.undo_plies(): drop the eval points of the moves
# that were taken back and redraw the sidebar for the restored position.
func on_undo():
	var game_state = get_parent().get_node("GameState")
	var n: int = game_state.snapshots.size()
	if eval_history.size() > n:
		eval_history.resize(n)
	var plies: int = n - 1
	var black_first: bool = game_state.snapshots[0].turn == "black"
	turn_number = (plies + (1 if black_first else 0)) / 2 + 1
	turn_counter_label.text = "Turn %d" % turn_number
	_hide_game_over_card()
	update_turn(game_state.turn, false)

func set_puzzle_mode(on: bool, title: String = "", prompt: String = ""):
	_puzzle_mode = on
	_puzzle_box.visible = on
	_eval_head.visible = not on
	_apply_eval_visible()
	hint_toggle.visible = not on
	undo_btn.visible = not on
	clear_drawings_btn.get_parent().columns = 3 if on else 4
	new_game_btn.text = "All puzzles" if on else "New game"
	if on:
		_puzzle_title.text = title
		_puzzle_prompt.text = prompt
		set_puzzle_feedback("", UITheme.TEXT_DIM)
		set_puzzle_buttons(true)

# "Closing it out": a normal game against the computer from a winning
# position, so only the controls that would make it trivial are hidden.
var idle_status := ""   # status line shown when nothing else is (closeout goal)

func set_closeout_mode(on: bool):
	if not on:
		idle_status = ""
	hint_toggle.visible = not on
	undo_btn.visible = not on
	clear_drawings_btn.get_parent().columns = 3 if on else 4
	new_game_btn.text = "All puzzles" if on else "New game"

func set_puzzle_feedback(text: String, color: Color):
	_puzzle_feedback.text = text
	_puzzle_feedback.add_theme_color_override("font_color", color)
	_puzzle_feedback.visible = text != ""

# solving: Hint/Solution active; otherwise only Next.
func set_puzzle_buttons(solving: bool):
	_puzzle_hint_btn.disabled = not solving
	_puzzle_solution_btn.disabled = not solving
	_style_next(not solving)

func _style_next(highlight: bool):
	UITheme.style_button(_puzzle_next_btn, "primary" if highlight else "secondary")


# ---- Evaluation on/off -------------------------------------------------
# Hiding only affects what is drawn: the engine keeps evaluating, so the
# graph is complete if the player turns it back on (e.g. in review).
func toggle_eval():
	set_eval_visible(not eval_visible)

func set_eval_visible(on: bool):
	eval_visible = on
	_apply_eval_visible()
	Settings.set_value("show_eval", on)

func _apply_eval_visible():
	if _eval_box == null:
		return
	_eval_box.visible = eval_visible and not _puzzle_mode
	_eval_hidden_label.visible = not eval_visible
	_eval_toggle_btn.text = "Hide" if eval_visible else "Show"

func _load_settings():
	eval_visible = bool(Settings.get_value("show_eval"))

# Re-read everything the settings page can change.
func refresh_settings():
	_load_settings()
	_apply_eval_visible()


# Shows the starting-position name in the header ("" for Classic).
func set_mode_name(n: String):
	_mode_label.text = "·  " + n if n != "" else ""
	_mode_label.visible = n != ""

# Which bar shows which colour: the side at the bottom of the board gets the
# bottom bar. Unflipped, White's back rank is drawn at the top.
func _assign_bars():
	var bottom_color := "white" if _flipped else "black"
	var top_color := "black" if _flipped else "white"
	_bars = {bottom_color: bottom_bar, top_color: top_bar}
	for c in ["white", "black"]:
		var bar: PlayerBar = _bars[c]
		bar.color = c
		var tok := UITheme.piece_token(("w" if c == "white" else "b") + "K", 38)
		tok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var row = bar.token_holder.get_parent()
		var idx = bar.token_holder.get_index()
		bar.token_holder.queue_free()
		row.add_child(tok)
		row.move_child(tok, idx)
		bar.token_holder = tok
	_refresh_bar_texts()


func set_orientation(flipped: bool):
	_flipped = flipped
	if board_drawer != null:
		board_drawer.set_flipped(flipped)
	_assign_bars()
	_refresh_dynamic()


# ---------------------------------------------------------------------------
# Players / clocks
# ---------------------------------------------------------------------------
const LEVELS := UITheme.LEVEL_IDS

func _bot_label(type: String) -> String:
	if type == "human":
		return "Human"
	if type == "puzzle":
		return "Defender"
	var lvl := LEVELS.find(type)
	if lvl >= 0:
		return "The " + UITheme.LEVEL_TITLES[lvl]
	return type.capitalize() + " Bot"

func _bot_sub(type: String) -> String:
	if type == "human":
		return "Human player"
	if type == "puzzle":
		return "Puzzle  ·  plays the best defence"
	var lvl := LEVELS.find(type)
	if lvl >= 0:
		return "Computer  ·  Level %d of 7  ·  %s" % [lvl + 1, UITheme.LEVEL_DIFFICULTY[lvl]]
	return "Computer  ·  Personality"

func set_player_labels(white: String, black: String):
	_player_types = {"white": white, "black": black}
	_refresh_bar_texts()

func _refresh_bar_texts():
	for c in ["white", "black"]:
		var bar: PlayerBar = _bars[c]
		var t: String = _player_types[c]
		var human_count := int(_player_types.white == "human") + int(_player_types.black == "human")
		var nm := _bot_label(t)
		if t == "human" and human_count == 1:
			nm = "You"
		elif t == "human":
			nm = c.capitalize()
		bar.name_label.text = nm
		var lvl := LEVELS.find(t)
		bar.sub_label.text = _bot_sub(t)
		bar.sub_label.add_theme_color_override("font_color", UITheme.LEVEL_COLORS[lvl] if lvl >= 0 else UITheme.TEXT_DIM)
		bar.clock_panel.visible = _clocks_visible
		bar.set_thinking(false)

func set_clocks_visible(vis: bool):
	_clocks_visible = vis
	for bar in [top_bar, bottom_bar]:
		bar.clock_panel.visible = vis
		if not vis:
			bar.grace.visible = false

func update_clocks(white_seconds: float, black_seconds: float):
	_set_clock(_bars["white"], white_seconds)
	_set_clock(_bars["black"], black_seconds)

func _set_clock(bar: PlayerBar, seconds: float):
	bar.clock_label.text = _format_clock(seconds)
	if seconds <= CLOCK_DANGER_SECONDS:
		bar.clock_label.add_theme_color_override("font_color", UITheme.RUBY if not bar._active else Color("#5c0a18"))
	elif seconds <= CLOCK_WARN_SECONDS:
		bar.clock_label.add_theme_color_override("font_color", UITheme.AMBER if not bar._active else Color("#5a3300"))

# Per-turn grace buffer ring, shown only on the side to move.
func update_grace(active_side: String, remaining: float, total: float):
	if not _clocks_visible:
		return
	var frac = 0.0 if total <= 0.0 else remaining / total
	for c in ["white", "black"]:
		var bar: PlayerBar = _bars[c]
		bar.grace.visible = (c == active_side) and remaining > 0.0
		if c == active_side:
			bar.grace.set_fraction(frac)

func _format_clock(seconds: float) -> String:
	var s = max(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------------------
# Turn / eval / moves
# ---------------------------------------------------------------------------
# new_position: true when a move was just played (adds a point to the eval
# history); false when only refreshing, e.g. at the start of a game -- the
# start position's point is already there, and a second one would shift
# every later eval by one move.
func update_turn(turn: String, new_position: bool = true):
	turn_label.text = turn.capitalize() + " to move"
	for c in ["white", "black"]:
		_bars[c].set_active(c == turn)
	var game_state = get_parent().get_node("GameState")
	if game_state.clock_enabled:
		update_clocks(game_state.white_time_remaining, game_state.black_time_remaining)
	update_eval(game_state.current_eval_score, new_position, game_state.current_eval_mate)
	_refresh_dynamic()

func _refresh_dynamic():
	var game_state = get_parent().get_node_or_null("GameState")
	if game_state == null:
		return
	for c in ["white", "black"]:
		_bars[c].set_active(c == game_state.turn and not game_state.game_over)
	_refresh_moves(game_state.move_history)
	_refresh_captured(game_state.board)
	if game_state.engine != null and not game_state.game_over and game_state.engine.is_in_check(game_state.turn):
		_set_status("%s is in check" % game_state.turn.capitalize(), UITheme.RUBY)
	elif not game_state.game_over:
		_set_status(idle_status, UITheme.GOLD_LIGHT)

func _set_status(text: String, color: Color):
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	status_label.visible = text != ""

# eval_score: White-relative centipawns from the engine.
# mate: White-relative mate string from the engine ("M3", "-M2", "M0" for a
#       finished game), or "" when there is no forced mate.
func update_eval(eval_score, is_new_move: bool = false, mate: String = ""):
	var numeric_score: float
	var text: String
	if mate != "":
		var black_mates = mate.begins_with("-")
		numeric_score = -EVAL_GRAPH_CAP if black_mates else EVAL_GRAPH_CAP
		if mate.ends_with("M0"):
			text = "0-1" if black_mates else "1-0"
		else:
			text = mate
	else:
		numeric_score = float(eval_score) / 100.0
		text = "%+.2f" % numeric_score

	eval_label.text = text
	eval_label.add_theme_color_override("font_color", UITheme.GOLD_LIGHT if mate != "" else UITheme.TEXT)

	if is_new_move or eval_history.is_empty():
		eval_history.append([eval_history.size(), numeric_score, text])
	else:
		eval_history[eval_history.size() - 1][1] = numeric_score
		eval_history[eval_history.size() - 1][2] = text
	last_logged_eval = numeric_score
	last_logged_label = text

	_eval_bar.value = numeric_score
	_eval_bar.queue_redraw()
	var pts: Array = []
	for e in eval_history:
		pts.append(float(e[1]))
	_eval_graph.points = pts
	_eval_graph.queue_redraw()

# selected: index of the move to highlight (-1 = the latest move, -2 = none,
# i.e. the start position is shown). After the
# game is over every move is a button that jumps the board to that position.
func _refresh_moves(history: Array, selected: int = -1):
	for ch in _moves_grid.get_children():
		ch.queue_free()
	var game_over: bool = get_parent().get_node("GameState").game_over
	if selected == -1:
		selected = history.size() - 1
	var selected_ctl: Control = null
	# Positions with Black to move first (puzzles) leave White's first cell
	# as "…" so the columns stay White | Black.
	var gs = get_parent().get_node("GameState")
	var offset := 1 if not gs.snapshots.is_empty() and gs.snapshots[0].turn == "black" else 0
	var i := 0
	while i < history.size() + offset:
		var num := UITheme.label("%d." % (i / 2 + 1), 13, UITheme.TEXT_FAINT, UITheme.ui(600))
		num.custom_minimum_size = Vector2(30, 0)
		_moves_grid.add_child(num)
		for k in 2:
			var idx := i + k - offset
			var txt: String = history[idx] if idx >= 0 and idx < history.size() else ("…" if idx < 0 else "")
			var is_sel := idx == selected
			var b := Button.new()
			b.text = txt
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(130, 24)
			b.add_theme_font_size_override("font_size", 14)
			b.add_theme_font_override("font", UITheme.ui(650 if is_sel else 500))
			var fg := UITheme.GOLD_LIGHT if is_sel else UITheme.TEXT
			for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
				b.add_theme_color_override(st, fg)
			var sel_box := UITheme.box(Color(UITheme.GOLD, 0.16), 6, Color(0, 0, 0, 0), 0, 4) if is_sel else UITheme.box(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0, 4)
			b.add_theme_stylebox_override("normal", sel_box)
			b.add_theme_stylebox_override("disabled", sel_box)
			b.add_theme_stylebox_override("pressed", sel_box)
			b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 6, Color(0, 0, 0, 0), 0, 4) if game_over else sel_box)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			if txt == "" or idx < 0 or not game_over:
				b.disabled = true
			else:
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				b.pressed.connect(func(): get_parent().set_review_ply(idx + 1))
			_moves_grid.add_child(b)
			if is_sel:
				selected_ctl = b
		i += 2
	await get_tree().process_frame
	if _review_ply < 0 or selected_ctl == null:
		_moves_scroll.scroll_vertical = int(_moves_scroll.get_v_scroll_bar().max_value)
	else:
		_moves_scroll.ensure_control_visible(selected_ctl)

# ---------------------------------------------------------------------------
# Reviewing a finished game
# ---------------------------------------------------------------------------
# Shows position `ply` (0 = start) of the finished game in the sidebar.
# StartGameplay draws the board; ply == total-1 is the final position.
func show_review(ply: int, snapshot: Dictionary, total: int):
	_review_ply = ply
	_review_bar.visible = true
	var last := total - 1
	_review_btns.first.disabled = ply <= 0
	_review_btns.prev.disabled = ply <= 0
	_review_btns.next.disabled = ply >= last
	_review_btns.last.disabled = ply >= last
	if ply == 0:
		_review_label.text = "Start position"
	else:
		_review_label.text = "Move %d of %d" % [ply, last]
	turn_label.text = ("Reviewing  ·  " if ply < last else "Final position  ·  ") + snapshot.turn.capitalize() + " to move"
	# eval as it was at that point in the game
	if ply < eval_history.size():
		var e: Array = eval_history[ply]
		eval_label.text = e[2] if e.size() > 2 else "%+.2f" % float(e[1])
		_eval_bar.value = float(e[1])
		_eval_bar.queue_redraw()
	_eval_graph.marker = ply
	_eval_graph.queue_redraw()
	var game_state = get_parent().get_node("GameState")
	_refresh_moves(game_state.move_history, ply - 1 if ply > 0 else -2)
	_refresh_captured(snapshot.board)

func _on_review_button(which: String):
	var root = get_parent()
	var total: int = root.get_node("GameState").snapshots.size()
	var cur: int = _review_ply if _review_ply >= 0 else total - 1
	match which:
		"first": root.set_review_ply(0)
		"prev": root.set_review_ply(cur - 1)
		"next": root.set_review_ply(cur + 1)
		"last": root.set_review_ply(total - 1)

func is_result_card_visible() -> bool:
	return _game_over_layer != null

# Pieces each side has captured (shown on the capturer's bar).
# Compared with the game's own starting position, so it also works for the
# alternative setups on the Starting Positions page.
func _refresh_captured(board: Array):
	var counts := _count_pieces(board)
	var game_state = get_parent().get_node_or_null("GameState")
	var start_counts := _count_pieces(game_state.snapshots[0].board) if game_state != null and not game_state.snapshots.is_empty() else {}
	for side in ["w", "b"]:
		var lost: Array = []
		var have: Dictionary = counts[side]
		var start_have: Dictionary = start_counts.get(side, {}) if not start_counts.is_empty() else {}
		for t in PIECE_ORDER:
			var start: int = start_have.get(t, 0) if not start_counts.is_empty() else START_COUNTS.get(t, 0)
			var now: int = have.get(t, 0)
			var missing := start - now
			if t == "L":
				# Lancers beyond the starting ones came from promotions; only count
				# Lancers that existed at the start and are now gone.
				missing = max(0, start - now)
			elif t == "D":
				# a promoted donkey isn't captured: count it via the extra Lancers
				var extra_lancers: int = max(0, have.get("L", 0) - (start_have.get("L", 0) if not start_counts.is_empty() else 0))
				missing = start - now - extra_lancers
			for k in max(0, missing):
				lost.append(_png_name(t))
		var capturer := "black" if side == "w" else "white"
		_bars[capturer].set_captured(lost)

func _count_pieces(board: Array) -> Dictionary:
	var counts := {"w": {}, "b": {}}
	for r in board:
		for p in r:
			if p != "":
				counts[p[0]][p[1]] = counts[p[0]].get(p[1], 0) + 1
	return counts

func _png_name(t: String) -> String:
	return {"K": "king", "N": "knight", "C": "cardinal", "P": "paladin", "M": "marshal", "D": "donkey", "L": "lancer", "W": "warden"}[t]


# ---------------------------------------------------------------------------
# Game over card (drawn over the board)
# ---------------------------------------------------------------------------
func show_game_over(reason: String, winner: String):
	var title := "Game over"
	var sub := ""
	match reason:
		"checkmate":
			title = "Checkmate"
			sub = winner + " wins"
		"no_legal_moves":
			title = winner + " wins"
			sub = "No legal moves left"
		"time":
			title = winner + " wins"
			sub = "on time"
		"40move":
			title = "Draw"
			sub = "40 moves without a capture"
		"repetition":
			title = "Draw"
			sub = "Threefold repetition"
		"insufficient":
			title = "Draw"
			sub = "Insufficient material"
	if reason in ["40move", "repetition", "insufficient"] and winner != "":
		sub += "\n" + winner + " wins on Armageddon rules"
	_set_status(title + (" — " + sub.replace("\n", " · ") if sub != "" else ""), UITheme.GOLD_LIGHT)
	for c in ["white", "black"]:
		_bars[c].set_active(false)
		_bars[c].set_thinking(false)
	var note: String = get_parent().record_game_result(winner)
	_show_game_over_card(title, sub, winner, note)

func _show_game_over_card(title: String, sub: String, winner: String, note: String = ""):
	_hide_game_over_card()
	var layer_ctl := Control.new()
	layer_ctl.position = BOARD_ORIGIN
	layer_ctl.size = Vector2(BOARD_PX, BOARD_PX)
	layer_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer_ctl)
	_game_over_layer = layer_ctl
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_ctl.add_child(center)
	var st := UITheme.box(Color(UITheme.SURFACE, 0.97), 16, UITheme.GOLD, 2, 26)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 24
	var card := UITheme.panel(st)
	card.custom_minimum_size = Vector2(340, 0)
	center.add_child(card)
	var v := UITheme.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	if winner != "":
		var tok := UITheme.piece_token(("w" if winner == "White" else "b") + "K", 56)
		tok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tok)
	var t := UITheme.label(title, 34, UITheme.GOLD_LIGHT, UITheme.display(700))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UITheme.label(sub, 16, UITheme.TEXT_DIM, UITheme.ui(500))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	if note != "":
		var n := UITheme.label(note, 13, UITheme.GOLD, UITheme.ui(600))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	var row := UITheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var view := UITheme.button("Review game", "ghost", 14, 40)
	view.custom_minimum_size.x = 130
	view.pressed.connect(func():
		_hide_game_over_card()
		get_parent().set_review_ply(get_parent().get_node("GameState").snapshots.size() - 1))
	row.add_child(view)
	if get_parent().closeout_active:
		var more := UITheme.button("Another position", "primary", 15, 40)
		more.custom_minimum_size.x = 160
		more.pressed.connect(func():
			more.disabled = true
			more.text = "Finding…"
			get_parent().next_closeout())
		row.add_child(more)
	else:
		var again := UITheme.button("New game", "primary", 15, 40)
		again.custom_minimum_size.x = 130
		again.pressed.connect(_on_new_game)
		row.add_child(again)

func _hide_game_over_card():
	if _game_over_layer != null:
		_game_over_layer.queue_free()
		_game_over_layer = null


# ---------------------------------------------------------------------------
# Signals / buttons
# ---------------------------------------------------------------------------
func _on_turn_changed(new_turn: String):
	# new_turn == "white" means Black just moved, i.e. a new full turn starts.
	if new_turn == "white":
		turn_number += 1
	turn_counter_label.text = "Turn %d" % turn_number
	update_turn(new_turn)

func _on_game_ended(reason: String, winner: String):
	if get_parent().puzzle_active:
		return   # StartGameplay shows the puzzle result instead
	show_game_over(reason, winner)

func _on_thinking():
	var game_state = get_parent().get_node("GameState")
	_bars[game_state.turn].set_thinking(true)

func _on_thinking_done():
	for c in ["white", "black"]:
		_bars[c].set_thinking(false)

func _on_hint_toggled(enabled: bool):
	var root = get_parent()
	var game_state = root.get_node("GameState")
	if game_state.game_over:
		root.update_review_hint()  # analyse the position being reviewed
		return
	if enabled:
		var current_player = root.white_player if game_state.turn == "white" else root.black_player
		if current_player == "human" and not game_state.game_over:
			game_state.start_hint_search()
	else:
		game_state.stop_hint_search()

func _on_flip_pressed():
	get_parent().toggle_flip()

func _on_info_pressed():
	var info = get_parent().get_node_or_null("Info")
	if info != null:
		info.toggle()

func _on_clear_drawings_pressed():
	if board_drawer != null:
		board_drawer.clear_arrows()

# Called by StartGameplay when a game starts.
func reset_for_new_game():
	turn_number = 1
	turn_counter_label.text = "Turn 1"
	turn_label.text = "White to move"
	_set_status("", UITheme.TEXT)
	eval_history.clear()
	last_logged_eval = 999999.0
	last_logged_label = ""
	_hide_game_over_card()
	_review_ply = -1
	_review_bar.visible = false
	_eval_graph.marker = -1
	if board_drawer != null:
		board_drawer.clear_arrows()
	_refresh_dynamic()

func _on_new_game():
	reset_for_new_game()
	set_clocks_visible(false)
	get_parent().new_game()
