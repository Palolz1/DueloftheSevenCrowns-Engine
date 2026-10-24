# records_page.gd
# Your record against each of the seven nobles (records.gd).
extends Control

signal closed
signal play_against(level_id: String)


func _ready():
	z_index = 200
	var shell := UITheme.page_shell(self, "Records", "Your games against the seven nobles. Counted when you play one of them in a fair starting position.")
	shell.back.pressed.connect(func(): closed.emit())
	var body: VBoxContainer = shell.body

	# Summary line
	var best := Records.highest_beaten()
	var total_w := 0
	var total_l := 0
	var total_d := 0
	for id in UITheme.LEVEL_IDS:
		var r := Records.get_record(id)
		total_w += r.w
		total_l += r.l
		total_d += r.d
	var summary := UITheme.panel(UITheme.card(16))
	body.add_child(summary)
	var srow := UITheme.hbox(28)
	summary.add_child(srow)
	srow.add_child(_stat("Highest noble defeated", "None yet" if best < 0 else "The " + UITheme.LEVEL_TITLES[best], UITheme.LEVEL_COLORS[best] if best >= 0 else UITheme.TEXT_DIM))
	srow.add_child(_stat("Games", str(total_w + total_l + total_d), UITheme.TEXT))
	srow.add_child(_stat("Won", str(total_w), UITheme.EMERALD))
	srow.add_child(_stat("Lost", str(total_l), UITheme.RUBY))
	srow.add_child(_stat("Drawn", str(total_d), UITheme.TEXT_DIM))
	if best < UITheme.LEVEL_IDS.size() - 1:
		srow.add_child(UITheme.spacer())
		var next_id: String = UITheme.LEVEL_IDS[best + 1]
		var nb := UITheme.button("Challenge the %s  ›" % UITheme.LEVEL_TITLES[best + 1], "primary", 15, 44)
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nb.pressed.connect(func(): play_against.emit(next_id))
		srow.add_child(nb)

	# One row per noble
	var table := UITheme.panel(UITheme.card(14))
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(table)
	var rows := UITheme.vbox(4)
	table.add_child(rows)
	var head := _row(rows, true)
	for t in ["Noble", "Won", "Lost", "Drawn", "Score", "", "Wins as White", "Wins as Black", "Best streak", "First win"]:
		head.add_child(_cell(t, 12, UITheme.TEXT_FAINT, UITheme.ui(650)))
	for i in UITheme.LEVEL_IDS.size():
		var id: String = UITheme.LEVEL_IDS[i]
		var r := Records.get_record(id)
		var games: int = r.w + r.l + r.d
		var row := _row(rows, false)
		var accent: Color = UITheme.LEVEL_COLORS[i]
		var name_box := UITheme.vbox(0)
		name_box.custom_minimum_size.x = 0
		name_box.add_child(UITheme.label("The " + UITheme.LEVEL_TITLES[i], 17, accent if games > 0 else UITheme.TEXT, UITheme.display(700)))
		name_box.add_child(UITheme.label("Level %d · %s" % [i + 1, UITheme.LEVEL_DIFFICULTY[i]], 12, UITheme.TEXT_FAINT, UITheme.ui(500)))
		row.add_child(name_box)
		row.add_child(_cell(str(r.w), 16, UITheme.EMERALD if r.w > 0 else UITheme.TEXT_FAINT, UITheme.ui(700)))
		row.add_child(_cell(str(r.l), 16, UITheme.RUBY if r.l > 0 else UITheme.TEXT_FAINT, UITheme.ui(700)))
		row.add_child(_cell(str(r.d), 16, UITheme.TEXT if r.d > 0 else UITheme.TEXT_FAINT, UITheme.ui(700)))
		var pct: float = (float(r.w) + 0.5 * r.d) / games if games > 0 else -1.0
		row.add_child(_cell("–" if pct < 0 else "%d%%" % roundi(pct * 100.0), 15, UITheme.TEXT, UITheme.ui(650)))
		var bar := ScoreBar.new()
		bar.fraction = pct
		bar.color = accent
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(_cell(str(r.w_white), 14, UITheme.TEXT_DIM, UITheme.ui(500)))
		row.add_child(_cell(str(r.w_black), 14, UITheme.TEXT_DIM, UITheme.ui(500)))
		row.add_child(_cell(str(r.best_streak) if r.best_streak > 0 else "–", 14, UITheme.TEXT_DIM, UITheme.ui(500)))
		row.add_child(_cell(r.first_win if r.first_win != "" else "–", 14, UITheme.TEXT_DIM, UITheme.ui(500)))


const COL_W := [210, 56, 56, 62, 62, 150, 100, 100, 92, 100]

func _row(parent: Control, header: bool) -> HBoxContainer:
	var wrap := UITheme.panel(UITheme.box(Color(0, 0, 0, 0) if header else UITheme.SURFACE_LO, 10, Color(0, 0, 0, 0), 0, 8))
	parent.add_child(wrap)
	var h := UITheme.hbox(10)
	wrap.add_child(h)
	h.child_entered_tree.connect(func(n):
		var i: int = n.get_index()
		if i < COL_W.size() and n is Control:
			n.custom_minimum_size.x = COL_W[i]
			n.size_flags_vertical = Control.SIZE_SHRINK_CENTER)
	return h


func _cell(t: String, fs: int, col: Color, font: Font) -> Label:
	return UITheme.label(t, fs, col, font)


func _stat(title: String, value: String, col: Color) -> VBoxContainer:
	var v := UITheme.vbox(2)
	v.add_child(UITheme.heading(title, 11))
	v.add_child(UITheme.label(value, 22, col, UITheme.display(700)))
	return v


class ScoreBar:
	extends Control
	var fraction := -1.0
	var color := Color.WHITE

	func _draw():
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.07))
		if fraction > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fraction, size.y)), color)
