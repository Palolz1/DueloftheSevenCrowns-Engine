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

func _ready():
	get_tree().root.theme = UITheme.make_theme()
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			var info = get_node_or_null("Info")
			if info != null:
				info.toggle()
		elif event.keycode == KEY_F and board_renderer.visible:
			toggle_flip()
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
	get_tree().root.add_child(player_setup)  # Add to viewport root
	player_setup.set_anchors_preset(Control.PRESET_FULL_RECT)

func _on_players_selected(w_type: String, b_type: String, g_type: String, standard_seconds: float, armageddon_white_seconds: float, armageddon_black_seconds: float, scenario_id: String = "classic"):
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
	if _hovered_square.is_empty():
		return []
	var r = _hovered_square[0]
	var c = _hovered_square[1]
	var piece = game_state.get_piece_at(r, c)
	if piece == "":
		return []
	return game_state.engine.get_piece_attack_squares(r, c)

func _on_square_clicked(r: int, c: int):
	if game_state.game_over or _bot_scheduled or _is_animating:
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

func _on_square_hovered(r: int, c: int):
	if _is_animating:
		return
	if r == -1 and c == -1:
		_hovered_square = []
	else:
		_hovered_square = [r, c]
	_on_board_changed()

func _on_turn_changed(new_turn: String):
	if not _bot_scheduled:
		_start_turn()

func _on_game_ended(reason: String, winner: String):
	_bot_scheduled = false
	_game_over_reason = reason
	_winner = winner
	game_state.stop_hint_search()
	# Start the review at the final position (deferred so the last eval point
	# has been recorded first).
	call_deferred("set_review_ply", game_state.snapshots.size() - 1)
	_on_board_changed()  # (UIcontroller shows the result card itself)

func _start_turn():
	if game_state.game_over:
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

	await get_tree().create_timer(0.05).timeout
	await _do_bot_move(player_type, time_limit)
	_bot_scheduled = false
	input_handler.set_process_input(true)
	_start_turn()

func _do_bot_move(player_type: String, time_limit: float):
	if game_state.game_over:
		return
	var result = await game_state.request_bot_move(player_type, time_limit)
	if result.is_empty():
		return

	_is_animating = true
	var piece = game_state.get_piece_at(result.from_row, result.from_col)
	var captured = game_state.get_piece_at(result.to_row, result.to_col)

	_render_with_skip([[result.from_row, result.from_col]])

	if captured != "":
		piece_animator.animate_capture(result.from_row, result.from_col, result.to_row, result.to_col, piece, captured)
		await piece_animator.capture_finished
	else:
		piece_animator.animate_move(result.from_row, result.from_col, result.to_row, result.to_col, piece)
		await piece_animator.move_finished

	_is_animating = false
	game_state.execute_move(result.from_row, result.from_col, result.to_row, result.to_col)

func new_game():
	review_ply = -1
	game_state.review_hint_arrow = null
	_bot_scheduled = false
	_is_animating = false
	_game_over_reason = ""
	_winner = ""
	_hovered_square = []
	game_state.reset_game()
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
