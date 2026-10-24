# puzzle_page.gd
# Puzzle list (puzzles.gd), grouped by theme. Each tile is a mini board;
# picking one emits `chosen(id)`.
extends Control

signal chosen(id: String)
signal closed


func _ready():
	z_index = 200
	var shell := UITheme.page_shell(self, "Puzzles",
		"%d of %d solved. Every puzzle comes from a real computer game and was checked by the engine." % [Puzzles.solved_count(), Puzzles.LIST.size()])
	shell.back.pressed.connect(func(): closed.emit())
	var cont := UITheme.button("Continue  ›", "primary", 15, 40)
	cont.custom_minimum_size.x = 150
	cont.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next_id := Puzzles.next_unsolved()
	cont.disabled = next_id == ""
	cont.tooltip_text = "Next puzzle you haven't solved"
	cont.pressed.connect(func(): chosen.emit(next_id))
	shell.head.add_child(cont)
	shell.head.move_child(cont, 1)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.body.add_child(scroll)
	var list := UITheme.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(_random_card())
	list.add_child(_closeout_card())
	list.add_child(UITheme.spacer(false))

	for th in Puzzles.THEMES:
		var items := Puzzles.in_theme(th.id)
		if items.is_empty():
			continue
		var hrow := UITheme.hbox(12)
		list.add_child(hrow)
		hrow.add_child(UITheme.label(th.name, 20, UITheme.TEXT, UITheme.display(700)))
		var d := UITheme.label("%s   %d / %d solved" % [th.desc, Puzzles.solved_count(th.id), items.size()], 13, UITheme.TEXT_FAINT, UITheme.ui(500))
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow.add_child(d)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for i in items.size():
			grid.add_child(_tile(items[i], i + 1))
		list.add_child(UITheme.spacer(false))


# Endless random puzzles (puzzle_gen.gd)
func _random_card() -> Control:
	var card := UITheme.panel(UITheme.card(18))
	var row := UITheme.hbox(24)
	card.add_child(row)
	var info := UITheme.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UITheme.label("Random puzzle", 22, UITheme.GOLD_LIGHT, UITheme.display(700)))
	var d := UITheme.label("A brand-new forced mate every time, found live in a fresh engine game. It never runs out.", 14, UITheme.TEXT_DIM, UITheme.ui(500))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	info.add_child(UITheme.label("%d solved  ·  mate in 2: %d  ·  in 3: %d  ·  in 4: %d  ·  best streak %d" % [
		Puzzles.random_solved_total(), Puzzles.random_stat("m2"), Puzzles.random_stat("m3"),
		Puzzles.random_stat("m4"), Puzzles.random_stat("best_streak")], 13, UITheme.TEXT_FAINT, UITheme.ui(600)))
	var pg := PuzzleGen.get_instance(get_tree())
	var btns := UITheme.hbox(8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(btns)
	if not pg.ok:
		btns.add_child(UITheme.label("Needs Fairy-Stockfish", 14, UITheme.RUBY, UITheme.ui(600)))
		return card
	var all_buttons := []
	for spec in [[2, "Mate in 2"], [3, "Mate in 3"], [4, "Mate in 4"], [0, "Surprise me"]]:
		var b := UITheme.button(spec[1], "primary" if spec[0] == 0 else "secondary", 14, 44)
		b.custom_minimum_size.x = 112
		btns.add_child(b)
		all_buttons.append(b)
		b.pressed.connect(func():
			for x in all_buttons:
				x.disabled = true
			b.text = "Finding…"
			pg.generated.connect(_on_random_ready, CONNECT_ONE_SHOT)
			pg.request(spec[0]))
	return card


func _on_random_ready(_p: Dictionary):
	chosen.emit("random")


func _on_closeout_ready(_p: Dictionary):
	chosen.emit("closeout")


# "Closing it out": convert a winning position as Black against the King
func _closeout_card() -> Control:
	var card := UITheme.panel(UITheme.card(18))
	var row := UITheme.hbox(24)
	card.add_child(row)
	var info := UITheme.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UITheme.label("Closing it out", 22, UITheme.GOLD_LIGHT, UITheme.display(700)))
	var d := UITheme.label("You play Black from a random position the engine rates at +9 or better for you. The King defends with everything it has. Just win.", 14, UITheme.TEXT_DIM, UITheme.ui(500))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	var played := Puzzles.random_stat("co_played")
	info.add_child(UITheme.label("%d of %d converted  ·  current streak %d  ·  best streak %d" % [
		Puzzles.random_stat("co_won"), played, Puzzles.random_stat("co_streak"), Puzzles.random_stat("co_best_streak")],
		13, UITheme.TEXT_FAINT, UITheme.ui(600)))
	var pg := PuzzleGen.get_instance(get_tree())
	if not pg.ok:
		row.add_child(UITheme.label("Needs Fairy-Stockfish", 14, UITheme.RUBY, UITheme.ui(600)))
		return card
	var b := UITheme.button("Play a winning position", "primary", 14, 44)
	b.custom_minimum_size.x = 220
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		b.disabled = true
		b.text = "Finding…"
		pg.generated.connect(_on_closeout_ready, CONNECT_ONE_SHOT)
		pg.request(PuzzleGen.CLOSEOUT))
	row.add_child(b)
	return card


func _tile(p: Dictionary, n: int) -> Button:
	var st := Puzzles.status(p.id)
	var done := st in ["solved", "clean"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(128, 150)
	var border := UITheme.EMERALD if done else (UITheme.GOLD_DARK if st == "revealed" else UITheme.BORDER_SOFT)
	b.add_theme_stylebox_override("normal", UITheme.box(UITheme.SURFACE, 12, border, 2 if done else 1))
	b.add_theme_stylebox_override("hover", UITheme.box(UITheme.SURFACE_HI, 12, UITheme.GOLD, 2))
	b.add_theme_stylebox_override("pressed", UITheme.box(UITheme.SURFACE_HI, 12, UITheme.GOLD, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var start := Puzzles.fen_to_start(p.fen)
	b.tooltip_text = "%s to move" % start.turn.capitalize()
	b.pressed.connect(func(): chosen.emit(p.id))

	var v := UITheme.vbox(6)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var mb = preload("res://scenario_page.gd").MiniBoard.new()
	mb.board = start.board
	mb.cell = 15.0
	mb.white_bottom = start.turn == "white"
	mb.custom_minimum_size = Vector2(105, 105)
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mb)
	var row := UITheme.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var dot := UITheme.label("●", 11, UITheme.IVORY if start.turn == "white" else Color("#7d89a8"), UITheme.ui(700))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.tooltip_text = ""
	row.add_child(dot)
	var nm := UITheme.label("#%d" % n, 13, UITheme.TEXT, UITheme.ui(650))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var sp := UITheme.spacer()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var tag := ""
	var tcol := UITheme.TEXT_FAINT
	match st:
		"clean": tag = "Solved"; tcol = UITheme.EMERALD
		"solved": tag = "Solved"; tcol = UITheme.EMERALD
		"revealed": tag = "Seen"; tcol = UITheme.GOLD
	var tl := UITheme.label(tag, 12, tcol, UITheme.ui(650))
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tl)
	return b
