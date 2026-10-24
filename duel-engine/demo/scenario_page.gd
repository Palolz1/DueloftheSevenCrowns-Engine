# scenario_page.gd
# "Starting Positions" page, opened from the setup screen. Shows every
# scenario from scenarios.gd as a card with a mini board, description and
# engine verdict. Picking one emits `chosen(id)`.
extends Control

signal chosen(id: String)
signal closed

var selected_id := "classic"
var _cards := {}


# Small 7x7 board preview, White at the bottom.
class MiniBoard:
	extends Control
	var board: Array = []
	var cell := 20.0
	var question := false   # Shuffled Court: back ranks change every game
	var white_bottom := true  # false: rotated 180 degrees (Black's view)

	func _draw():
		var cols := Settings.board_colors()
		var light: Color = cols[0]
		var dark: Color = cols[1]
		var names := {"K": "king", "N": "knight", "C": "cardinal", "P": "paladin", "M": "marshal", "D": "donkey", "L": "lancer", "W": "warden"}
		for r in 7:
			for c in 7:
				var vr := (6 - r) if white_bottom else r
				var vc := c if white_bottom else 6 - c
				var rect := Rect2(vc * cell, vr * cell, cell, cell)
				draw_rect(rect, light if (r + c) % 2 == 0 else dark)
				if board.is_empty():
					continue
				var p: String = board[r][c]
				if p == "":
					continue
				var ctr := rect.get_center()
				var white := p.begins_with("w")
				draw_circle(ctr, cell * 0.46, UITheme.IVORY if white else UITheme.SLATE)
				draw_arc(ctr, cell * 0.46, 0, TAU, 20, UITheme.GOLD_DARK if white else Color("#59647f"), 1.0, true)
				var tex: Texture2D = load("res://piecepng/%s.png" % names[p.substr(1, 1)])
				var s := cell * 0.8
				draw_texture_rect(tex, Rect2(ctr - Vector2(s, s) / 2.0, Vector2(s, s)), false)
				if question and (r == 0 or r == 6) and p.substr(1, 1) != "K":
					draw_circle(ctr, cell * 0.46, Color(0.06, 0.08, 0.14, 0.72))
					var f := UITheme.ui(800)
					var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
					draw_string(f, ctr + Vector2(-w / 2.0, 5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD_LIGHT)
		draw_rect(Rect2(Vector2.ZERO, Vector2(cell * 7, cell * 7)), Color(UITheme.GOLD, 0.8), false, 1.5)


func _ready():
	# anchors AND offsets, so the page really covers the whole setup screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build():
	var bg := ColorRect.new()
	bg.color = UITheme.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var main := UITheme.vbox(14)
	margin.add_child(main)

	var head := UITheme.hbox(16)
	main.add_child(head)
	var titles := UITheme.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UITheme.label("Starting Positions", 34, UITheme.GOLD_LIGHT, UITheme.display(700)))
	titles.add_child(UITheme.label("Alternative armies and drills. Pick one, then choose players and a clock as usual.", 15, UITheme.TEXT_DIM, UITheme.ui(500)))
	var back := UITheme.button("Back", "secondary", 15, 40)
	back.custom_minimum_size.x = 110
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): closed.emit())
	head.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	var list := UITheme.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var group := ButtonGroup.new()
	for cat in Scenarios.CATEGORIES:
		var hrow := UITheme.hbox(12)
		list.add_child(hrow)
		hrow.add_child(UITheme.label(cat.title, 20, UITheme.TEXT, UITheme.display(700)))
		var cd := UITheme.label(cat.desc, 13, UITheme.TEXT_FAINT, UITheme.ui(500))
		cd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow.add_child(cd)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		list.add_child(grid)
		for s in Scenarios.LIST:
			if s.category == cat.id:
				var card := _card(s)
				card.button_group = group
				grid.add_child(card)
		list.add_child(UITheme.spacer(false))


func _card(s: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(370, 168)
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE, 14, UITheme.BORDER_SOFT, 1))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 14, UITheme.BORDER, 1))
	var sel := UITheme.box(Color(UITheme.GOLD, 0.10), 14, UITheme.GOLD, 2)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.button_pressed = s.id == selected_id
	b.pressed.connect(func():
		selected_id = s.id
		chosen.emit(s.id))

	var row := UITheme.hbox(14)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_top = 14
	row.offset_right = -14
	row.offset_bottom = -14
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)

	var mb := MiniBoard.new()
	mb.board = Scenarios.rows_to_board(s.rows)
	mb.question = s.id == "shuffle"
	mb.custom_minimum_size = Vector2(140, 140)
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mb)

	var col := UITheme.vbox(5)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nm := UITheme.label(s.name, 18, UITheme.GOLD_LIGHT, UITheme.display(700))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var d := UITheme.label(s.desc, 12, UITheme.TEXT_DIM, UITheme.ui(500))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(178, 0)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(d)
	var sp := UITheme.spacer(false)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sp)
	var tone_col: Color = UITheme.EMERALD if s.tone == "even" else (UITheme.IVORY if s.tone == "white" else Color("#9fb0d8"))
	var chip := UITheme.panel(UITheme.box(Color(tone_col, 0.14), 7, Color(tone_col, 0.6), 1, 5))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := UITheme.label("Engine: " + s.verdict, 11, tone_col, UITheme.ui(650))
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(cl)
	col.add_child(chip)
	_cards[s.id] = b
	return b
