#StartGameplay.gd
extends Node2D

@onready var board_renderer = $BoardRenderer
@onready var input_handler = $InputHandler
@onready var game_state = $GameState
@onready var ui_controller = $UIcontroller
@onready var piece_animator = $BoardRenderer/PieceAnimator

var white_player = "human"
var black_player = "human"
var game_type = "untimed"
var player_setup = null
var _bot_scheduled := false
var _game_over_reason: String = ""
var _winner: String = ""
var _hovered_square: Array = []
var _is_animating: bool = false

func _ready():
	# Center board on the left side, leaving room for the side panel
	board_renderer.position = Vector2(80, 60)
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		var info = get_node_or_null("Info")
		if info != null:
			info.toggle()

func _show_player_setup():
	board_renderer.visible = false
	ui_controller.visible = false
	player_setup = preload("res://PlayerSetup.tscn").instantiate()
	player_setup.players_selected.connect(_on_players_selected)
	get_tree().root.add_child(player_setup)  # Add to viewport root
	player_setup.set_anchors_preset(Control.PRESET_FULL_RECT)

func _on_players_selected(w_type: String, b_type: String, g_type: String, standard_seconds: float, armageddon_white_seconds: float, armageddon_black_seconds: float):
	white_player = w_type
	black_player = b_type
	game_type = g_type
	ui_controller.set_player_labels(white_player, black_player)

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
	_start_turn()
	SFXhandler.play("newgame")

func _on_board_changed():
	if _is_animating:
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
	ui_controller.update_eval(game_state.current_eval_score, false)

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
	ui_controller.show_game_over(reason, winner)
	_on_board_changed()

func _start_turn():
	if game_state.game_over:
		return
	var current_player = white_player if game_state.turn == "white" else black_player
	_update_hint_state()
	if current_player in ["beginner", "easy", "medium", "hard", "impossible", "roulette", "cautious", "shepherd"]:
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
		"easy":       time_limit = 1.25
		"medium":     time_limit = 3.0
		"hard":       time_limit = 5.0
		"impossible": time_limit = 15.0
		"roulette":   time_limit = 4.0
		"cautious":   time_limit = 6.0
		"shepherd":   time_limit = 4.0

	# In timed games, don't let a bot think longer than half of what it
	# has left on the clock, so it can never flag itself on a slow move.
	if game_state.clock_enabled:
		var remaining: float = game_state.white_time_remaining if game_state.turn == "white" else game_state.black_time_remaining
		if remaining > 0.0:
			time_limit = min(time_limit, max(0.1, remaining * 0.5))

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
