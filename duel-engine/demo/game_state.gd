#GameState.gd
extends Node2D

var engine: DuelEngine
var hint_engine: DuelEngine
# Fairy-Stockfish does all the searching when it's available (bots, hints,
# eval bar). DuelEngine still handles legal moves / check detection, and is
# the automatic fallback if Fairy-Stockfish can't be started.
var fairy: FairyEngine = null       # bots + eval
var fairy_hint: FairyEngine = null  # background hint/eval search
var use_fairy := false
# Every move of the game so far in UCI notation (what Fairy-Stockfish needs,
# including for repetition and the 40-move rule).
var uci_moves: Array = []
# How long each slice of the background hint search runs. Short slices keep
# the UI responsive when a move is made; the engine's hash table carries the
# work over, so the depth still climbs from slice to slice.
const HINT_SLICE_MS := 300
const HINT_SLICES := 40
var hint_thread: Thread = null
var hint_mutex: Mutex = Mutex.new()
var hint_stop := false
var hint_enabled := false
var hint_gen := 0
var hint_arrow = null
var hint_score: float = 0.0
var hint_mate: String = ""
var bot_thread: Thread = null
var _bot_result: Dictionary = {}
var _bot_done: bool = false
var _bot_mutex: Mutex = Mutex.new()


var board: Array = []
var turn: String = "white"
var selected_square: Array = []
var legal_moves: Array = []
var last_move = null
var halfmove_clock: int = 0
var move_history: Array = []
# Engine position keys (side to move included) for every position since the
# last capture/promotion, oldest first, current position last. Positions from
# before an irreversible move can never recur, so the list is cleared then.
# Used for threefold repetition and handed to the engines so their searches
# know which positions would repeat.
var position_keys: Array = []
var game_over: bool = false
var current_eval_score: float = 0.0
# White-relative mate string from the engine ("M3" = White mates in 3,
# "-M2" = Black mates in 2, "" = no forced mate known). When set, it
# overrides current_eval_score for display.
var current_eval_mate: String = ""
# Search depth behind the current eval. Within one position a result only
# replaces the displayed eval if it searched at least as deep, so a stray
# depth-1 hint result can't overwrite the bot's depth-8 verdict.
var current_eval_depth: int = -1
# Large sentinel used for decided positions (game already over).
const EVAL_DECIDED := 1000000.0
# How long the instant post-move evaluation search runs. This replaces the
# old static evaluate_position() call, which could not see any tactics and
# routinely showed numbers like +2000 for positions that were really mates
# (or really nothing). The hint/bot searches refine it afterwards.
const QUICK_EVAL_TIME := 0.12

# ------------------------------------------------------------------
# CLOCK STATE — untimed / standard / armageddon
# ------------------------------------------------------------------
var game_type: String = "untimed"
var clock_enabled: bool = false
var white_time_remaining: float = 0.0
var black_time_remaining: float = 0.0

# Couch-versus buffer: the clock doesn't start counting down for
# whichever side is on move until this many seconds of their turn
# have passed, giving time to hand the mouse/keyboard over.
const TURN_GRACE_PERIOD := 15.0
var turn_grace_remaining: float = 0.0

# Search thread count, scaled to the machine instead of hardcoded.
# Queried once from the engine (cheap call, but no reason to repeat it
# every move) and reused everywhere find_best_move is called.
# Hint search runs continuously in the background while a human is
# deciding, so it gets a smaller slice to avoid saturating every core
# during ordinary play.
var search_threads: int = 1
var hint_threads: int = 1

signal hint_updated
signal board_changed
signal turn_changed(new_turn: String)
signal game_ended(reason: String, winner: String)
signal thinking_started
signal thinking_finished
@onready var bot_diff = $BotDiff
func _ready():
	engine = DuelEngine.new()
	hint_engine = DuelEngine.new()
	search_threads = engine.get_recommended_threads()
	# Hints run continuously in the background, so they get roughly half
	# the threads (min 1), leaving headroom for the rest of the game/OS.
	hint_threads = max(1, search_threads / 2)
	_start_fairy()
	reset_game()
	# _run_perft_table() 
	#only uncomment if you need to use it

func _start_fairy():
	fairy = FairyEngine.new()
	if fairy.start(search_threads):
		fairy_hint = FairyEngine.new()
		if not fairy_hint.start(hint_threads):
			push_warning("Fairy-Stockfish hint engine failed: " + fairy_hint.last_error)
			fairy_hint = null
		use_fairy = true
		print("[GameState] Using Fairy-Stockfish (", FairyEngine.binary_name(), ")")
	else:
		push_warning("Fairy-Stockfish unavailable, using DuelEngine: " + fairy.last_error)
		fairy = null
		use_fairy = false

func _exit_tree():
	_stop_hint_thread()
	if bot_thread != null and bot_thread.is_started():
		bot_thread.wait_to_finish()
	if fairy != null:
		fairy.shutdown()
	if fairy_hint != null:
		fairy_hint.shutdown()

# ------------------------------------------------------------------
# SEARCH FACADE -- everything that wants an engine search goes through
# here, so Fairy-Stockfish / DuelEngine is decided in one place.
# Same result shape as DuelEngine.find_best_move().
# ------------------------------------------------------------------
# skill: Fairy-Stockfish Skill Level 0-20 (ignored by DuelEngine).
func search_best(max_depth: int, time_limit: float, skill: int = 20) -> Dictionary:
	if use_fairy and fairy != null and fairy.ok:
		var r = fairy.go(uci_moves, int(time_limit * 1000.0), max_depth, turn == "white", skill)
		if not r.is_empty():
			return r
	return engine.find_best_move(max_depth if max_depth > 0 else 64, time_limit, halfmove_clock, search_threads)

# Scores every legal move for the side to move (bots use this to pick
# human-like alternatives). duel_depth / fairy_depth: search depth for each
# engine (Fairy-Stockfish's depths are "cheaper", so it gets a deeper one).
func score_all_moves(duel_depth: int, fairy_depth: int, time_limit: float) -> Array:
	if use_fairy and fairy != null and fairy.ok:
		var r = fairy.score_all(uci_moves, fairy_depth, int(time_limit * 1000.0))
		if not r.is_empty():
			return r
	return engine.score_moves(duel_depth, time_limit, halfmove_clock)

func _run_perft_table():
	var test_engine = DuelEngine.new()
	test_engine.set_board(_create_starting_board(), "white")

	print("=== Perft Table (starting position) ===")
	print("%-6s %-12s %-10s %-12s" % ["Depth", "Nodes", "Time(s)", "Nodes/sec"])

	for depth in range(1, 5):
		var start_ms = Time.get_ticks_msec()
		var nodes = test_engine.perft(depth)
		var elapsed = (Time.get_ticks_msec() - start_ms) / 1000.0
		var nps = int(nodes / elapsed) if elapsed > 0.0 else nodes
		print("%-6d %-12d %-10.3f %-12d" % [depth, nodes, elapsed, nps])

func start_hint_search():
	hint_enabled = true
	_restart_hint_search()

func stop_hint_search():
	hint_enabled = false
	_stop_hint_thread()
	# Invalidate results the worker already queued with call_deferred;
	# otherwise they land after we stopped and clobber the eval.
	hint_gen += 1
	hint_arrow = null
	board_changed.emit()

func _stop_hint_thread():
	hint_mutex.lock()
	hint_stop = true
	hint_mutex.unlock()
	if hint_thread != null and hint_thread.is_started():
		hint_thread.wait_to_finish()
	hint_thread = null

func _restart_hint_search():
	if game_over:
		return
	_stop_hint_thread()

	hint_gen += 1
	var gen = hint_gen
	hint_mutex.lock()
	hint_stop = false
	hint_mutex.unlock()

	hint_engine.set_board(board, turn)
	hint_engine.set_repetition_history(_previous_position_keys())
	var hm = halfmove_clock

	hint_thread = Thread.new()
	if fairy_hint != null and fairy_hint.ok:
		hint_thread.start(_fairy_hint_worker.bind(gen, uci_moves.duplicate(), turn == "white"))
	else:
		hint_thread.start(_hint_worker.bind(gen, hm))

func _fairy_hint_worker(gen: int, moves: Array, white_to_move: bool):
	for i in HINT_SLICES:
		hint_mutex.lock()
		var stop = hint_stop
		hint_mutex.unlock()
		if stop or gen != hint_gen:
			return
		var result = fairy_hint.go(moves, HINT_SLICE_MS, 0, white_to_move)
		hint_mutex.lock()
		stop = hint_stop
		hint_mutex.unlock()
		if stop or gen != hint_gen or result.is_empty():
			return
		call_deferred("_on_hint_result", result, gen)

func _hint_worker(gen: int, hm: int):
	for d in range(1, 26):
		hint_mutex.lock()
		var stop = hint_stop
		hint_mutex.unlock()
		if stop or gen != hint_gen:
			return

		var result = hint_engine.find_best_move(d, 1.0, hm, hint_threads)

		hint_mutex.lock()
		stop = hint_stop
		hint_mutex.unlock()
		if stop or gen != hint_gen:
			return

		if result.has("from_row"):
			call_deferred("_on_hint_result", result, gen)

func _on_hint_result(result: Dictionary, gen: int):
	if gen != hint_gen:
		return
	
	if hint_enabled:
		hint_arrow = [result.from_row, result.from_col, result.to_row, result.to_col]
	else:
		hint_arrow = null
	
	if result.has("score"):
		_set_eval_from_search(result, turn)
		hint_score = current_eval_score
		hint_mate = current_eval_mate
	
	hint_updated.emit()
	board_changed.emit()

func reset_game():
	if bot_thread != null and bot_thread.is_started():
		bot_thread.wait_to_finish()
	bot_thread = null
	_stop_hint_thread()
	hint_arrow = null
	hint_gen += 1
	board = _create_starting_board()
	turn = "white"
	selected_square = []
	legal_moves = []
	last_move = null
	halfmove_clock = 0
	move_history.clear()
	uci_moves.clear()
	if fairy != null:
		fairy.new_game()
	if fairy_hint != null:
		fairy_hint.new_game()
	game_over = false
	current_eval_score = 0.0
	current_eval_mate = ""
	current_eval_depth = -1
	# Clocks are re-armed by setup_clock() once the next game's type is
	# chosen in PlayerSetup; until then leave them inert.
	clock_enabled = false
	engine.set_board(board, turn)
	position_keys = [engine.get_position_key()]
	engine.set_repetition_history([])
	board_changed.emit()

# ------------------------------------------------------------------
# CLOCK API
# ------------------------------------------------------------------
func setup_clock(g_type: String, white_seconds: float, black_seconds: float):
	game_type = g_type
	clock_enabled = g_type != "untimed"
	white_time_remaining = white_seconds
	black_time_remaining = black_seconds
	turn_grace_remaining = TURN_GRACE_PERIOD if clock_enabled else 0.0

func tick_clock(delta: float):
	if not clock_enabled or game_over:
		return
	if turn_grace_remaining > 0.0:
		turn_grace_remaining = max(0.0, turn_grace_remaining - delta)
		return
	if turn == "white":
		white_time_remaining = max(0.0, white_time_remaining - delta)
		if white_time_remaining <= 0.0:
			_handle_time_expired("white")
	else:
		black_time_remaining = max(0.0, black_time_remaining - delta)
		if black_time_remaining <= 0.0:
			_handle_time_expired("black")

func _handle_time_expired(color: String):
	if game_over:
		return
	game_over = true
	# Flag-fall is always a loss for the side whose clock hit zero,
	# in every game type including Armageddon — the draw-odds rule
	# only ever applies to actual drawn results, never to timeouts.
	var winner = "Black" if color == "white" else "White"
	game_ended.emit("time", winner)

func get_piece_at(r: int, c: int) -> String:
	if r < 0 or r >= 7 or c < 0 or c >= 7:
		return ""
	return board[r][c]

func is_own_piece(r: int, c: int) -> bool:
	var piece = get_piece_at(r, c)
	return piece != "" and piece.begins_with(turn[0])

func select_square(r: int, c: int):
	if not is_own_piece(r, c):
		return
	selected_square = [r, c]
	legal_moves = engine.get_legal_moves(r, c)
	board_changed.emit()

func try_move(to_r: int, to_c: int) -> Dictionary:
	if selected_square.is_empty():
		return {}

	var sr = selected_square[0]
	var sc = selected_square[1]

	for move in legal_moves:
		if move["to_row"] == to_r and move["to_col"] == to_c:
			return {"from_r": sr, "from_c": sc, "to_r": to_r, "to_c": to_c}

	if is_own_piece(to_r, to_c):
		select_square(to_r, to_c)
		return {}

	selected_square = []
	legal_moves = []
	board_changed.emit()
	return {}

func execute_move(from_r: int, from_c: int, to_r: int, to_c: int):
	var piece = board[from_r][from_c]
	var captured = board[to_r][to_c]
	var is_capture = captured != ""
	var was_donkey = piece.ends_with("D")
	board[to_r][to_c] = piece
	board[from_r][from_c] = ""
	var promotion = false
	if was_donkey:
		var back_rank = 6 if piece.begins_with("w") else 0
		if to_r == back_rank:
			board[to_r][to_c] = piece[0] + "L"
			promotion = true
			SFXhandler.play("promotion")
	if is_capture or promotion:
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	move_history.append(_format_move(piece, from_r, from_c, to_r, to_c, is_capture, promotion))
	uci_moves.append(FairyEngine.move_to_uci(from_r, from_c, to_r, to_c, promotion))
	last_move = [[from_r, from_c], [to_r, to_c]]
	selected_square = []
	legal_moves = []
	turn = "black" if turn == "white" else "white"
	turn_grace_remaining = TURN_GRACE_PERIOD if clock_enabled else 0.0
	engine.set_board(board, turn)
	if is_capture or promotion:
		position_keys.clear()
	position_keys.append(engine.get_position_key())
	engine.set_repetition_history(_previous_position_keys())
	_check_game_end()
	if not game_over and engine.is_in_check(turn):
		SFXhandler.play("check")
	_update_eval()
	turn_changed.emit(turn)
	board_changed.emit()


func _update_eval():
	current_eval_mate = ""
	current_eval_depth = -1  # new position: any search result is welcome
	if game_over:
		_set_decided_eval()
		return
	# Short real search instead of the static eval (see QUICK_EVAL_TIME).
	var r = search_best(0, QUICK_EVAL_TIME)
	if r.has("score"):
		_set_eval_from_search(r, turn)
	else:
		_set_decided_eval()

# Stores a find_best_move() result as the displayed eval. `side` is the
# colour that was to move in the searched position (the engine's score is
# relative to that side; its "mate" string is already White-relative).
func _set_eval_from_search(result: Dictionary, side: String):
	var d := int(result.get("depth", 0))
	if d < current_eval_depth:
		return
	current_eval_depth = d
	var s := float(result.score)
	current_eval_score = s if side == "white" else -s
	current_eval_mate = result.get("mate", "")

func _set_decided_eval():
	# No legal moves for the side to move = loss (no stalemate in this game).
	if engine.is_insufficient_material() or halfmove_clock >= 40 or is_threefold_repetition():
		current_eval_score = 0.0
		current_eval_mate = ""
		return
	var has_moves := false
	for r in range(7):
		for c in range(7):
			if is_own_piece(r, c) and not engine.get_legal_moves(r, c).is_empty():
				has_moves = true
	if has_moves:
		return
	current_eval_score = -EVAL_DECIDED if turn == "white" else EVAL_DECIDED
	current_eval_mate = "-M0" if turn == "white" else "M0"

# Called (deferred, from the bot thread) with the bot's own search of the
# position it is about to move in -- far better than any static number.
func report_search_eval(result: Dictionary, side: String, ply: int):
	if ply != move_history.size() or side != turn or not result.has("score"):
		return  # stale (position has changed since the search started)
	_set_eval_from_search(result, side)
	board_changed.emit()

# True when the current position (same pieces, same side to move) has now
# occurred three times.
func is_threefold_repetition() -> bool:
	return not position_keys.is_empty() and position_keys.count(position_keys.back()) >= 3

# Every tracked position except the current one (what the engines want).
func _previous_position_keys() -> Array:
	return position_keys.slice(0, max(0, position_keys.size() - 1))

func _check_game_end():
	if engine.is_checkmate():
		game_over = true
		var winner = "Black" if turn == "white" else "White"
		SFXhandler.play("checkmate") 
		game_ended.emit("checkmate", winner)
		return

	var has_moves = false
	for r in range(7):
		for c in range(7):
			var piece = board[r][c]
			if piece != "" and piece.begins_with(turn[0]):
				if not engine.get_legal_moves(r, c).is_empty():
					has_moves = true
					break
		if has_moves:
			break

	if not has_moves:
		game_over = true
		var winner = "Black" if turn == "white" else "White"
		game_ended.emit("no_legal_moves", winner)
		return

	if is_threefold_repetition():
		_end_game_draw("repetition")
		return

	if halfmove_clock >= 40:
		_end_game_draw("40move")
		return

	if engine.is_insufficient_material():
		_end_game_draw("insufficient")
		return

# A drawn result normally has no winner, except under Armageddon rules,
# where White had the time (and often move-order) advantage and Black
# is compensated by winning any drawn game.
func _end_game_draw(reason: String):
	game_over = true
	var winner = "Black" if game_type == "armageddon" else ""
	game_ended.emit(reason, winner)

func request_bot_move(difficulty: String, time_limit: float) -> Dictionary:
	if game_over:
		return {}
	thinking_started.emit()

	_bot_result = {}
	_bot_done = false

	bot_thread = Thread.new()
	bot_thread.start(_bot_worker.bind(difficulty, time_limit))

	while true:
		_bot_mutex.lock()
		var done = _bot_done
		_bot_mutex.unlock()
		if done:
			break
		await get_tree().process_frame

	bot_thread.wait_to_finish()
	bot_thread = null

	thinking_finished.emit()
	var result = _bot_result
	return result if result != null and result.has("from_row") else {}

func _bot_worker(difficulty: String, time_limit: float):
	var result = bot_diff.request_bot_move(difficulty, time_limit)
	_bot_mutex.lock()
	_bot_result = result
	_bot_done = true
	_bot_mutex.unlock()

func _format_move(piece: String, fr: int, fc: int, to_r: int, to_c: int, capture: bool, promotion: bool) -> String:
	var files = "abcdefg"
	var ranks = "7654321"
	var ptype = piece[1]
	var cap = "x" if capture else ""
	var promo = "=L" if promotion else ""
	return ptype + files[fc] + ranks[fr] + cap + files[to_c] + ranks[to_r] + promo

func _create_starting_board() -> Array:
	var b = []
	for r in range(7):
		var row = []
		for c in range(7):
			row.append("")
		b.append(row)

	b[0][0] = "wC"; b[0][1] = "wN"; b[0][2] = "wP"
	b[0][3] = "wK"; b[0][4] = "wW"; b[0][5] = "wN"; b[0][6] = "wM"
	for c in range(7): b[1][c] = "wD"

	b[6][0] = "bC"; b[6][1] = "bN"; b[6][2] = "bP"
	b[6][3] = "bK"; b[6][4] = "bW"; b[6][5] = "bN"; b[6][6] = "bM"
	for c in range(7): b[5][c] = "bD"

	return b
