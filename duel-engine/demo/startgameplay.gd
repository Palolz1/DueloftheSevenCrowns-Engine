#StartGameplay.gd
extends Node2D

@onready var board_renderer = $BoardRenderer
@onready var input_handler = $InputHandler
@onready var game_state = $GameState
@onready var ui_controller = $UIcontroller
@onready var piece_animator = $BoardRenderer/PieceAnimator

const BOT_TYPES := ["beginner", "novice", "easy", "medium", "hard", "expert", "impossible",
	"roulette", "cautious", "shepherd", "random", "berserker", "pacifist", "mirror", "stampede", "wanderer"]
# Multiplies every bot's think time (calibration tests run bots faster).
var bot_time_scale := 1.0

# Top-left of the squares in the 1280x800 design viewport (UIcontroller lays
# the player bars and sidebar out around this).
const BOARD_ORIGIN := Vector2(138, 116)

# Board orientation. false: White's back rank at the top (the classic view of
# this game); true: rotated 180 degrees so White is at the bottom.
var flipped := false

var white_player = "human"
var black_player = "human"
var game_type = "untimed"
var player_setup = null
var _bot_scheduled := false
var _game_over_reason: String = ""
var _winner: String = ""
var _hovered_square: Array = []
var _is_animating: bool = false
# Position of the finished game being reviewed (index into
# GameState.snapshots), or -1 while playing.
var review_ply := -1

# Puzzle mode (see puzzles.gd)
var puzzle_active := false
var puzzle: Dictionary = {}
var puzzle_step := 0          # index into puzzle.line of the next move
var puzzle_color := "white"   # the side the player solves for
var puzzle_clean := true      # no mistakes and no hint so far
var _puzzle_busy := false     # scripted moves / take-back in progress
var _puzzle_done := false

# Records: each finished game is counted once (keyed by GameState.game_gen).
var _recorded_gen := -1
var _record_note := ""
var _settings_page: Control = null

func _ready():
	get_tree().root.theme = UITheme.make_theme()
	Settings.apply_window()
	board_renderer.position = BOARD_ORIGIN
	await get_tree().process_frame  # wait one frame so CanvasLayer children are ready
	ui_controller.align_drawer_to_board(board_renderer.global_position)
	game_state.board_changed.connect(_on_board_changed)
	input_handler.square_clicked.connect(_on_square_clicked)
	input_handler.square_hovered.connect(_on_square_hovered)
	game_state.turn_changed.connect(_on_turn_changed)
	game_state.game_ended.connect(_on_game_ended)
	_show_player_setup()

func _process(delta: float) -> void:
	# Only tick the clock while a move is actually pending, never during
	# animations, and never in untimed games.
	if game_state.game_over or _is_animating:
		return
	game_state.tick_clock(delta)
	if game_state.clock_enabled:
		ui_controller.update_clocks(game_state.white_time_remaining, game_state.black_time_remaining)
		ui_controller.update_grace(game_state.turn, game_state.turn_grace_remaining, game_state.TURN_GRACE_PERIOD)

func _input(event):
	if _settings_page != null:
		return   # settings page open: no board shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			var info = get_node_or_null("Info")
			if info != null:
				info.toggle()
		elif event.keycode == KEY_F and board_renderer.visible:
			toggle_flip()
		elif event.keycode == KEY_E and board_renderer.visible and not puzzle_active:
			ui_controller.toggle_eval()
		elif event.keycode == KEY_Z and (event.ctrl_pressed or event.meta_pressed) and board_renderer.visible:
			undo_move()
		elif game_state.game_over and board_renderer.visible and not game_state.snapshots.is_empty():
			var last: int = game_state.snapshots.size() - 1
			var cur: int = review_ply if review_ply >= 0 else last
			match event.keycode:
				KEY_LEFT: set_review_ply(cur - 1)
				KEY_RIGHT: set_review_ply(cur + 1)
				KEY_HOME: set_review_ply(0)
				KEY_END: set_review_ply(last)

# Jump the review to position `ply` (0 = start). Only after the game is over.
func set_review_ply(ply: int):
	if not game_state.game_over or game_state.snapshots.is_empty():
		return
	review_ply = clampi(ply, 0, game_state.snapshots.size() - 1)
	_hovered_square = []
	update_review_hint()
	_on_board_changed()

# Runs (or stops) "Show best move" for the position being reviewed.
func update_review_hint():
	if review_ply < 0 or not game_state.game_over:
		return
	if ui_controller.hint_toggle.button_pressed:
		game_state.start_review_hint(review_ply)
	else:
		game_state.stop_review_hint()

func toggle_flip():
	flipped = not flipped
	_apply_orientation()

func _apply_orientation():
	board_renderer.flipped = flipped
	ui_controller.set_orientation(flipped)
	_on_board_changed()

func _show_player_setup():
	board_renderer.visible = false
	ui_controller.visible = false
	player_setup = preload("res://PlayerSetup.tscn").instantiate()
	player_setup.players_selected.connect(_on_players_selected)
	player_setup.puzzle_selected.connect(start_puzzle)
	get_tree().root.add_child(player_setup)  # Add to viewport root
	player_setup.set_anchors_preset(Control.PRESET_FULL_RECT)

func _on_players_selected(w_type: String, b_type: String, g_type: String, standard_seconds: float, armageddon_white_seconds: float, armageddon_black_seconds: float, scenario_id: String = "classic"):
	_leave_puzzle_mode()
	white_player = w_type
	black_player = b_type
	game_type = g_type
	# Set up the chosen starting position (Shuffled Court draws a new one).
	game_state.scenario_id = scenario_id
	game_state.reset_game()
	ui_controller.set_mode_name("" if scenario_id == "classic" else Scenarios.get_info(scenario_id).name)
	ui_controller.reset_for_new_game()
	ui_controller.set_player_labels(white_player, black_player)

	# Human vs bot: the human's pieces start at the bottom of the screen.
	# Otherwise keep the classic view (White at the top).
	var white_human: bool = white_player == "human"
	var black_human: bool = black_player == "human"
	if white_human != black_human:
		flipped = white_human
	else:
		flipped = false
	_apply_orientation()

	match game_type:
		"untimed":
			game_state.setup_clock("untimed", 0.0, 0.0)
		"standard":
			game_state.setup_clock("standard", standard_seconds, standard_seconds)
		"armageddon":
			game_state.setup_clock("armageddon", armageddon_white_seconds, armageddon_black_seconds)

	ui_controller.set_clocks_visible(game_type != "untimed")
	if game_type != "untimed":
		ui_controller.update_clocks(game_state.white_time_remaining, game_state.black_time_remaining)

	board_renderer.visible = true
	ui_controller.visible = true
	_game_over_reason = ""
	_winner = ""
	_hovered_square = []
	_on_board_changed()
	ui_controller.update_turn(game_state.turn, false)
	_start_turn()
	SFXhandler.play("newgame")

func _on_board_changed():
	if _is_animating:
		return
	if review_ply >= 0 and game_state.game_over and review_ply < game_state.snapshots.size():
		var snap: Dictionary = game_state.snapshots[review_ply]
		var arrow = game_state.review_hint_arrow if ui_controller.hint_toggle.button_pressed else null
		board_renderer.render(snap.board, [], [], snap.last_move, snap.in_check, snap.turn,
			arrow, [], "", "", [], [])
		ui_controller.show_review(review_ply, snap, game_state.snapshots.size())
		return
	var hover = _get_hover_moves()
	board_renderer.render(
		game_state.board,
		game_state.selected_square,
		game_state.legal_moves,
		game_state.last_move,
		game_state.engine.is_in_check(game_state.turn),
		game_state.turn,
		game_state.hint_arrow,
		hover,
		_game_over_reason,
		_winner,
		_hovered_square
	)
	ui_controller.update_eval(game_state.current_eval_score, false, game_state.current_eval_mate)

func _get_hover_moves() -> Array:
	if _hovered_square.is_empty() or not Settings.get_value("hover_preview"):
		return []
	var r = _hovered_square[0]
	var c = _hovered_square[1]
	var piece = game_state.get_piece_at(r, c)
	if piece == "":
		return []
	return game_state.engine.get_piece_attack_squares(r, c)

func _on_square_clicked(r: int, c: int):
	if game_state.game_over or _bot_scheduled or _is_animating or _puzzle_busy:
		return
	var current_player = white_player if game_state.turn == "white" else black_player
	if current_player != "human":
		return

	# Nothing selected yet — just select
	if game_state.selected_square.is_empty():
		game_state.select_square(r, c)
		return

	# Something is selected — try to move there
	var move = game_state.try_move(r, c)
	if move.is_empty():
		return  # try_move already handled reselect / deselect / board_changed

	_is_animating = true
	var piece = game_state.get_piece_at(move.from_r, move.from_c)
	var captured = game_state.get_piece_at(move.to_r, move.to_c)

	_render_with_skip([[move.from_r, move.from_c]])

	if captured != "":
		piece_animator.animate_capture(move.from_r, move.from_c, move.to_r, move.to_c, piece, captured)
		await piece_animator.capture_finished
	else:
		piece_animator.animate_move(move.from_r, move.from_c, move.to_r, move.to_c, piece)
		await piece_animator.move_finished

	_is_animating = false
	game_state.execute_move(move.from_r, move.from_c, move.to_r, move.to_c)
	if puzzle_active:
		_puzzle_after_move()

func _on_square_hovered(r: int, c: int):
	if _is_animating:
		return
	if r == -1 and c == -1:
		_hovered_square = []
	else:
		_hovered_square = [r, c]
	_on_board_changed()

func _on_turn_changed(new_turn: String):
	_update_undo_button()
	if not _bot_scheduled:
		_start_turn()

func _on_game_ended(reason: String, winner: String):
	_update_undo_button()
	if puzzle_active:
		game_state.stop_hint_search()
		return   # handled by _puzzle_after_move / the solution playback
	_bot_scheduled = false
	_game_over_reason = reason
	_winner = winner
	game_state.stop_hint_search()
	# Start the review at the final position (deferred so the last eval point
	# has been recorded first).
	call_deferred("set_review_ply", game_state.snapshots.size() - 1)
	_on_board_changed()  # (UIcontroller shows the result card itself)

func _start_turn():
	_update_undo_button()
	if game_state.game_over or puzzle_active:
		return
	var current_player = white_player if game_state.turn == "white" else black_player
	_update_hint_state()
	if current_player in BOT_TYPES:
		_schedule_bot_move(current_player)
	else:
		input_handler.set_process_input(true)

func _update_hint_state():
	if game_state.game_over:
		game_state.stop_hint_search()
		return
	
	game_state.start_hint_search()
	game_state.hint_enabled = ui_controller.hint_toggle.button_pressed
	if not game_state.hint_enabled:
		game_state.hint_arrow = null
		game_state.board_changed.emit()

func _schedule_bot_move(player_type: String):
	if _bot_scheduled:
		return
	_bot_scheduled = true
	game_state.stop_hint_search()
	input_handler.set_process_input(false)

	var time_limit: float
	match player_type:
		"beginner":   time_limit = 0.85
		"novice":     time_limit = 1.0
		"easy":       time_limit = 1.25
		"medium":     time_limit = 3.0
		"hard":       time_limit = 5.0
		"expert":     time_limit = 1.5
		"impossible": time_limit = 12.0
		"roulette":   time_limit = 4.0
		"cautious":   time_limit = 6.0
		"shepherd":   time_limit = 4.0
		_:            time_limit = 1.0  # personalities that only rank moves

	time_limit *= bot_time_scale

	# In timed games, don't let a bot think longer than half of what it
	# has left on the clock, so it can never flag itself on a slow move.
	if game_state.clock_enabled:
		var remaining: float = game_state.white_time_remaining if game_state.turn == "white" else game_state.black_time_remaining
		if remaining > 0.0:
			time_limit = min(time_limit, max(0.1, remaining * 0.4))

	var gen: int = game_state.game_gen
	await get_tree().create_timer(0.05).timeout
	if gen != game_state.game_gen:
		return   # New game was pressed; that game schedules its own bots
	await _do_bot_move(player_type, time_limit)
	if gen != game_state.game_gen:
		return
	_bot_scheduled = false
	input_handler.set_process_input(true)
	_start_turn()

func _do_bot_move(player_type: String, time_limit: float):
	if game_state.game_over:
		return
	var gen: int = game_state.game_gen
	var result = await game_state.request_bot_move(player_type, time_limit)
	if result.is_empty() or gen != game_state.game_gen:
		return

	await _animate_and_play(result.from_row, result.from_col, result.to_row, result.to_col)

# Animates a move, then plays it (unless the game was reset or a move was
# taken back meanwhile). Used for bot moves and scripted puzzle moves.
func _animate_and_play(fr: int, fc: int, tr: int, tc: int) -> bool:
	var gen: int = game_state.game_gen
	_is_animating = true
	var piece = game_state.get_piece_at(fr, fc)
	var captured = game_state.get_piece_at(tr, tc)

	_render_with_skip([[fr, fc]])

	if captured != "":
		piece_animator.animate_capture(fr, fc, tr, tc, piece, captured)
		await piece_animator.capture_finished
	else:
		piece_animator.animate_move(fr, fc, tr, tc, piece)
		await piece_animator.move_finished

	if gen != game_state.game_gen:
		return false   # board was reset during the animation
	_is_animating = false
	game_state.execute_move(fr, fc, tr, tc)
	return true

func new_game():
	if puzzle_active:
		preload("res://PlayerSetup.gd").open_puzzles_next = true   # back to the puzzle list
	_leave_puzzle_mode()
	review_ply = -1
	game_state.review_hint_arrow = null
	_bot_scheduled = false
	_is_animating = false
	_game_over_reason = ""
	_winner = ""
	_hovered_square = []
	game_state.reset_game()
	input_handler.set_process_input(true)   # a cancelled bot move may have left it off
	ui_controller.hint_toggle.button_pressed = false
	_show_player_setup()

func _render_with_skip(skip_squares: Array):
	var hover = _get_hover_moves()
	board_renderer.render(
		game_state.board,
		game_state.selected_square,
		game_state.legal_moves,
		game_state.last_move,
		game_state.engine.is_in_check(game_state.turn),
		game_state.turn,
		game_state.hint_arrow,
		hover,
		_game_over_reason,
		_winner,
		_hovered_square,
		skip_squares
	)


# ---------------------------------------------------------------------------
# Undo
# ---------------------------------------------------------------------------
# Plies to take back so it is a person's turn again, or 0 if undo isn't
# allowed right now (timed games, bot vs bot, puzzles, finished games).
func _undo_plies_needed() -> int:
	if puzzle_active or game_state.game_over or game_type != "untimed":
		return 0
	var plies: int = game_state.snapshots.size() - 1
	if plies <= 0:
		return 0
	var white_h: bool = white_player == "human"
	var black_h: bool = black_player == "human"
	if white_h and black_h:
		return 1
	if not white_h and not black_h:
		return 0
	var human := "white" if white_h else "black"
	# Bot to move (thinking, or about to): take back just your move.
	# Your move: take back the bot's reply and your move before it.
	var n := 1 if game_state.turn != human else 2
	return n if plies >= n else 0

func _update_undo_button():
	ui_controller.set_undo_enabled(_undo_plies_needed() > 0)

func undo_move():
	var n := _undo_plies_needed()
	if n <= 0:
		return
	if not game_state.undo_plies(n):
		return
	# a bot that was thinking/animating has been cancelled by undo_plies()
	_bot_scheduled = false
	_is_animating = false
	piece_animator._kill_active()
	_hovered_square = []
	input_handler.set_process_input(true)
	ui_controller.on_undo()
	_on_board_changed()
	_start_turn()


# ---------------------------------------------------------------------------
# Records against the seven nobles
# ---------------------------------------------------------------------------
# Called by the UI when a game ends; returns a line for the result card
# ("Record vs The Duke: 3–1–0") or "" when the game doesn't count.
func record_game_result(winner: String) -> String:
	if puzzle_active:
		return ""
	if _recorded_gen == game_state.game_gen:
		return _record_note
	_recorded_gen = game_state.game_gen
	_record_note = ""
	if not Records.counts_for_record(white_player, black_player, game_state.scenario_id):
		return ""
	var human := "white" if white_player == "human" else "black"
	var bot: String = black_player if human == "white" else white_player
	var result := "draw"
	if winner != "":
		result = "win" if winner.to_lower() == human else "loss"
	Records.add_result(bot, result, human)
	var lvl := UITheme.LEVEL_IDS.find(bot)
	_record_note = "Record vs The %s: %s" % [UITheme.LEVEL_TITLES[lvl], Records.short_text(bot)]
	return _record_note


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
func open_settings():
	if _settings_page != null:
		return
	# The in-game sidebar is a CanvasLayer (layer 1), so the page needs a
	# higher layer of its own to cover it; z_index doesn't cross layers.
	var holder := CanvasLayer.new()
	holder.layer = 20
	get_tree().root.add_child(holder)
	_settings_page = preload("res://settings_page.gd").new()
	_settings_page.changed.connect(_on_settings_changed)
	_settings_page.closed.connect(func():
		holder.queue_free()
		_settings_page = null
		input_handler.set_process_input(not _bot_scheduled)
		if ui_controller.board_drawer != null:
			ui_controller.board_drawer.set_process_input(true))
	holder.add_child(_settings_page)
	# no clicks or right-click arrows reach the board underneath
	input_handler.set_process_input(false)
	if ui_controller.board_drawer != null:
		ui_controller.board_drawer.set_process_input(false)

func _on_settings_changed():
	ui_controller.refresh_settings()
	_on_board_changed()


# ---------------------------------------------------------------------------
# Puzzles
# ---------------------------------------------------------------------------
func start_puzzle(id: String):
	var p: Dictionary = PuzzleGen.get_instance(get_tree()).current if id == "random" else Puzzles.get_puzzle(id)
	if p.is_empty():
		return
	if player_setup != null and is_instance_valid(player_setup):
		player_setup.queue_free()
		player_setup = null
	var start := Puzzles.fen_to_start(p.fen)
	board_renderer.set_hint_square([])
	puzzle = p
	puzzle_active = true
	puzzle_step = 0
	puzzle_color = start.turn
	puzzle_clean = true
	_puzzle_busy = false
	_puzzle_done = false
	review_ply = -1
	_bot_scheduled = false
	_is_animating = false
	_game_over_reason = ""
	_winner = ""
	_hovered_square = []
	white_player = "human" if puzzle_color == "white" else "puzzle"
	black_player = "human" if puzzle_color == "black" else "puzzle"
	game_type = "untimed"
	game_state.custom_start = start
	game_state.scenario_id = "classic"
	game_state.reset_game()
	game_state.setup_clock("untimed", 0.0, 0.0)
	ui_controller.reset_for_new_game()
	ui_controller.set_mode_name("Random puzzle" if p.get("random", false) else "Puzzle " + p.id.to_upper())
	ui_controller.set_player_labels(white_player, black_player)
	ui_controller.set_clocks_visible(false)
	ui_controller.hint_toggle.button_pressed = false
	_random_moves_left = int(p.get("n", 0))
	var moves_to_find: int = p.n if p.get("random", false) else (p.line.size() + 1) / 2
	var prompt := "%s to move. " % puzzle_color.capitalize()
	match p.theme:
		"win": prompt += "One move wins material. Find it."
		"mate1": prompt += "Checkmate in one move."
		_: prompt += "Force checkmate in %d moves." % moves_to_find
	var solved: bool = Puzzles.status(p.id) in ["solved", "clean"] and not p.get("random", false)
	ui_controller.set_puzzle_mode(true, Puzzles.theme_name(p.theme), prompt)
	if p.get("random", false):
		var streak := Puzzles.random_stat("streak")
		if streak > 1:
			ui_controller.set_puzzle_feedback("Streak: %d solved in a row" % streak, UITheme.TEXT_FAINT)
		PuzzleGen.get_instance(get_tree()).prefetch(int(p.target))
	if solved:
		ui_controller.set_puzzle_feedback("Already solved. Play it again?", UITheme.TEXT_FAINT)
	flipped = puzzle_color == "white"   # your side at the bottom
	_apply_orientation()
	board_renderer.visible = true
	ui_controller.visible = true
	_on_board_changed()
	ui_controller.update_turn(game_state.turn, false)
	input_handler.set_process_input(true)
	SFXhandler.play("newgame")

func _leave_puzzle_mode():
	board_renderer.set_hint_square([])
	if not puzzle_active:
		return
	puzzle_active = false
	puzzle = {}
	_puzzle_busy = false
	game_state.custom_start = {}
	ui_controller.set_puzzle_mode(false)

func _puzzle_after_move():
	board_renderer.set_hint_square([])
	if puzzle.get("random", false):
		_random_after_move()
		return
	var gen: int = game_state.game_gen
	var played: String = game_state.uci_moves.back()
	var expected: String = puzzle.line[puzzle_step]
	var won: bool = game_state.game_over and _winner_is_solver()
	if played == expected or won:
		puzzle_step += 1
		if won or puzzle_step >= puzzle.line.size():
			_puzzle_solved()
			return
		ui_controller.set_puzzle_feedback("Good move! Keep going.", UITheme.EMERALD)
		_puzzle_busy = true
		await get_tree().create_timer(0.45).timeout
		if gen != game_state.game_gen or not puzzle_active:
			return
		await _play_puzzle_reply()
		_puzzle_busy = false
	else:
		puzzle_clean = false
		ui_controller.set_puzzle_feedback("Not the right move. Try again.", UITheme.RUBY)
		_puzzle_busy = true
		await get_tree().create_timer(0.7).timeout
		if gen != game_state.game_gen or not puzzle_active:
			return
		game_state.undo_plies(1)
		ui_controller.on_undo()
		_puzzle_busy = false
		_on_board_changed()

func _winner_is_solver() -> bool:
	# no legal moves / checkmate for the side to move = the solver just won
	return game_state.game_over and game_state.turn != puzzle_color and not game_state.is_threefold_repetition() and game_state.halfmove_clock < 40 and not game_state.engine.is_insufficient_material()

# The computer's scripted defence (next move in the line).
func _play_puzzle_reply():
	if puzzle_step >= puzzle.line.size():
		return
	var m := Puzzles.uci_to_move(puzzle.line[puzzle_step])
	puzzle_step += 1
	await _animate_and_play(m.from_row, m.from_col, m.to_row, m.to_col)

func _puzzle_solved():
	_puzzle_done = true
	game_state.game_over = true
	game_state.stop_hint_search()
	var msg := "Solved!" if puzzle_clean else "Solved, after a little help."
	if puzzle.get("random", false):
		Puzzles.add_random_result(int(puzzle.n), true, puzzle_clean)
		var streak := Puzzles.random_stat("streak")
		var total := Puzzles.random_solved_total()
		ui_controller.set_puzzle_feedback("%s  %d random puzzle%s solved%s." % [msg, total, "" if total == 1 else "s",
			(", streak %d" % streak) if streak > 1 else ""], UITheme.EMERALD)
	else:
		Puzzles.set_status(puzzle.id, "clean" if puzzle_clean else "solved")
		ui_controller.set_puzzle_feedback("%s  %d of %d puzzles done." % [msg, Puzzles.solved_count(), Puzzles.LIST.size()], UITheme.EMERALD)
	ui_controller.set_puzzle_buttons(false)
	_update_undo_button()
	_on_board_changed()
	SFXhandler.play("checkmate" if puzzle.theme != "win" else "promotion")

func puzzle_hint():
	if not puzzle_active or _puzzle_done or _puzzle_busy or game_state.turn != puzzle_color:
		return
	puzzle_clean = false
	var mv: String
	if puzzle.get("random", false):
		_puzzle_busy = true
		var r := await _engine_lines(1, 13)
		_puzzle_busy = false
		if r.is_empty() or not puzzle_active:
			return
		mv = r[0].move
	else:
		mv = puzzle.line[puzzle_step]
	var m := Puzzles.uci_to_move(mv)
	# Blink the piece itself (no move dots or capture rings: those would give
	# away more than the hint says and look like extra highlights).
	game_state.selected_square = []
	game_state.legal_moves = []
	board_renderer.set_hint_square([m.from_row, m.from_col])
	_on_board_changed()
	ui_controller.set_puzzle_feedback("Hint: move the blinking piece.", UITheme.GOLD_LIGHT)

func puzzle_show_solution():
	if not puzzle_active or _puzzle_done or _puzzle_busy:
		return
	puzzle_clean = false
	_puzzle_busy = true
	var gen: int = game_state.game_gen
	board_renderer.set_hint_square([])
	ui_controller.set_puzzle_feedback("Here is the solution.", UITheme.GOLD_LIGHT)
	game_state.selected_square = []
	game_state.legal_moves = []
	if puzzle.get("random", false):
		Puzzles.add_random_result(int(puzzle.n), false, false)
		# play the engine's line (both sides) until the mate
		while not game_state.game_over:
			await get_tree().create_timer(0.55).timeout
			if gen != game_state.game_gen or not puzzle_active:
				return
			var r := await _engine_lines(1, 13)
			if r.is_empty() or gen != game_state.game_gen or not puzzle_active:
				break
			var mm := Puzzles.uci_to_move(r[0].move)
			if not await _animate_and_play(mm.from_row, mm.from_col, mm.to_row, mm.to_col):
				return
		_puzzle_busy = false
		_puzzle_done = true
		game_state.game_over = true
		ui_controller.set_puzzle_buttons(false)
		_on_board_changed()
		return
	Puzzles.set_status(puzzle.id, "revealed")
	while puzzle_step < puzzle.line.size():
		await get_tree().create_timer(0.55).timeout
		if gen != game_state.game_gen or not puzzle_active:
			return
		var m := Puzzles.uci_to_move(puzzle.line[puzzle_step])
		puzzle_step += 1
		var ok: bool = await _animate_and_play(m.from_row, m.from_col, m.to_row, m.to_col)
		if not ok:
			return
	_puzzle_busy = false
	_puzzle_done = true
	game_state.game_over = true
	ui_controller.set_puzzle_buttons(false)
	_on_board_changed()

func next_puzzle():
	if _puzzle_busy and not _puzzle_done:
		return
	if puzzle.get("random", false):
		if not _puzzle_done:
			Puzzles.add_random_result(int(puzzle.n), false, false)   # skipped: streak ends
		_next_random(int(puzzle.target))
		return
	var nid := Puzzles.next_unsolved(puzzle.get("id", ""))
	if nid == "":
		# everything solved: just go to the next one in the list
		var idx := 0
		for i in Puzzles.LIST.size():
			if Puzzles.LIST[i].id == puzzle.get("id", ""):
				idx = (i + 1) % Puzzles.LIST.size()
		nid = Puzzles.LIST[idx].id
	start_puzzle(nid)


# ---------------------------------------------------------------------------
# Random puzzles (puzzle_gen.gd): checked live by the engine
# ---------------------------------------------------------------------------
var _random_moves_left := 0   # your moves left to deliver mate

# Engine lines for the current puzzle position, without blocking the UI.
func _engine_lines(multipv: int, depth: int) -> Array:
	var holder := {"done": false, "r": []}
	PuzzleGen.get_instance(get_tree()).analyse_async(game_state.uci_moves.duplicate(), multipv, depth,
		func(r):
			holder.r = r
			holder.done = true)
	while not holder.done:
		await get_tree().process_frame
	return holder.r

func _random_after_move():
	var gen: int = game_state.game_gen
	if game_state.game_over and _winner_is_solver():
		_puzzle_solved()
		return
	_puzzle_busy = true
	ui_controller.set_puzzle_feedback("Checking…", UITheme.TEXT_FAINT)
	var left := _random_moves_left - 1
	var good := false
	var reply := ""
	if left > 0 and not game_state.game_over:
		var r := await _engine_lines(1, 14)
		if gen != game_state.game_gen or not puzzle_active:
			return
		# the defender (to move) must be getting mated within `left` moves
		if not r.is_empty() and r[0].mate < 0 and -int(r[0].mate) <= left:
			good = true
			reply = r[0].move
	if good:
		_random_moves_left = left
		ui_controller.set_puzzle_feedback("Good move! Keep going.", UITheme.EMERALD)
		await get_tree().create_timer(0.35).timeout
		if gen != game_state.game_gen or not puzzle_active:
			return
		var m := Puzzles.uci_to_move(reply)
		await _animate_and_play(m.from_row, m.from_col, m.to_row, m.to_col)
		_puzzle_busy = false
	else:
		puzzle_clean = false
		ui_controller.set_puzzle_feedback("That lets them escape. Try again.", UITheme.RUBY)
		await get_tree().create_timer(0.7).timeout
		if gen != game_state.game_gen or not puzzle_active:
			return
		game_state.undo_plies(1)
		ui_controller.on_undo()
		_puzzle_busy = false
		_on_board_changed()

# Finds (or takes the prefetched) next random puzzle and starts it.
func _next_random(target: int):
	var pg := PuzzleGen.get_instance(get_tree())
	if not pg.ok:
		return
	_puzzle_busy = true
	ui_controller.set_puzzle_feedback("Finding a new puzzle…", UITheme.TEXT_FAINT)
	pg.request(target)
	await pg.generated
	if puzzle_active:   # still in puzzle mode (not back at the menu)
		start_puzzle("random")
