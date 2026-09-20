#BotDiff.gd
extends Node

@onready var game_state = get_parent()

const MIN_THINK_TIME := .95

# ──────────────────────────────────────────────────────────────────
# Human-likeness tuning. Each difficulty has:
#
#   depth                  : real search depth ceiling.
#   blunder_prob           : chance of playing a blunder this move.
#   blunder_band           : [min, max] percentage into the ranked move list.
#                            0.0 = worst move, 1.0 = best move.
#                            Easy: bottom 0-25% (catastrophic)
#                            Medium: 10-35% (bad but not always losing)
#                            Hard: 20-45% (mediocre, "I didn't see that")
#
#   plausible_prob         : chance of playing a plausible move —
#                            ranks 2-3, within eval loss cap.
#   plausible_max_loss_cp  : eval loss cap for plausible band.
#
#   slip_prob              : chance of a minor slip — ranks 4-6.
#   slip_max_loss_cp       : eval loss cap for slip band.
#
#   forcing_gap_cp         : tactical-commitment threshold.
# ──────────────────────────────────────────────────────────────────
const HUMAN_PROFILES := {
	"easy": {
		"depth": 3,
		"blunder_prob": 0.20,
		"blunder_band": [0.0, 0.25],
		"plausible_prob": 0.50,
		"plausible_max_loss_cp": 80.0,
		"slip_prob": 0.20,
		"slip_max_loss_cp": 200.0,
		"forcing_gap_cp": 220.0,
	},
	"medium": {
		"depth": 8,
		"blunder_prob": 0.14,
		"blunder_band": [0.10, 0.35],
		"plausible_prob": 0.38,
		"plausible_max_loss_cp": 50.0,
		"slip_prob": 0.16,
		"slip_max_loss_cp": 130.0,
		"forcing_gap_cp": 160.0,
	},
	"hard": {
		"depth": 13,
		"blunder_prob": 0.06,
		"blunder_band": [0.20, 0.45],
		"plausible_prob": 0.28,
		"plausible_max_loss_cp": 25.0,
		"slip_prob": 0.12,
		"slip_max_loss_cp": 70.0,
		"forcing_gap_cp": 90.0,
		"avoid_en_prise": true,
	},
	"cautious": {
		"depth": 8,
		"blunder_prob": 0.0,
		"blunder_band": [0.0, 0.1],
		"plausible_prob": 0.45,
		"plausible_max_loss_cp": 40.0,
		"slip_prob": 0.12,
		"slip_max_loss_cp": 80.0,
		"forcing_gap_cp": 125.0,
		"avoid_en_prise": true,
	},
}

const MOOD_PERSISTENCE := 0.8
var _mood := {"white": 0.0, "black": 0.0}
var _eval_engine: DuelEngine = null


func request_bot_move(difficulty: String, time_limit: float) -> Dictionary:
	_check_new_game()

	var start_time = Time.get_ticks_msec()
	var result := {}

	match difficulty:
		"beginner":
			result = _beginner_bot_move(time_limit)
		"easy":
			result = _easy_bot_move(time_limit)
		"medium":
			result = _medium_bot_move(time_limit)
		"hard":
			result = _hard_bot_move(time_limit)
		"cautious":
			result = _cautious_bot_move(time_limit)
		"shepherd":
			result = _shepherd_bot_move(time_limit)
		"impossible":
			result = _impossible_bot_move(time_limit)
		"roulette":
			result = _roulette_bot_move(time_limit)

	var elapsed_ms = Time.get_ticks_msec() - start_time
	var remaining_ms = int(MIN_THINK_TIME * 1000) - elapsed_ms
	if remaining_ms > 0:
		OS.delay_msec(remaining_ms)
	return result

func _check_new_game() -> void:
	if game_state.move_history.is_empty():
		_mood = {"white": 0.0, "black": 0.0}

func _advance_mood(color: String) -> void:
	var prev = _mood.get(color, 0.0)
	var next_mood = prev * MOOD_PERSISTENCE + randf_range(-1.0, 1.0) * (1.0 - MOOD_PERSISTENCE)
	_mood[color] = clamp(next_mood, -1.0, 1.0)

func _get_eval_engine() -> DuelEngine:
	if _eval_engine == null:
		_eval_engine = DuelEngine.new()
	return _eval_engine

func _apply_move_to_board(m: Dictionary, board: Array) -> Array:
	var temp_board = []
	for row in board:
		temp_board.append(row.duplicate())

	var piece = temp_board[m.from_row][m.from_col]
	temp_board[m.to_row][m.to_col] = piece
	temp_board[m.from_row][m.from_col] = ""

	if piece.ends_with("D"):
		var back_rank = 6 if piece.begins_with("w") else 0
		if m.to_row == back_rank:
			temp_board[m.to_row][m.to_col] = piece[0] + "L"

	return temp_board

# ──────────────────────────────────────────────────────────────────
# Shared driver for easy / medium / hard.
# ──────────────────────────────────────────────────────────────────
func _human_like_move(time_limit: float, profile: Dictionary, bot_name: String, perfect_piece_type: String = "") -> Dictionary:
	var hm = game_state.halfmove_clock
	var color = game_state.turn

	var mood = _mood.get(color, 0.0)
	_advance_mood(color)

	var depth_delta = 0
	if mood > 0.5:
		depth_delta = 1
	elif mood < -0.5:
		depth_delta = -1
	var depth = max(1, int(profile.depth) + depth_delta)

	var best = game_state.engine.find_best_move(depth, time_limit, hm, game_state.search_threads)
	if not best.has("from_row"):
		print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(), " | NO LEGAL MOVES")
		return _random_legal_move()

	if perfect_piece_type != "":
		var moved_piece = game_state.board[best.from_row][best.from_col]
		if moved_piece.ends_with(perfect_piece_type):
			print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(),
				" | PERFECT (", perfect_piece_type, " move) | Eval: ", snapped(best.score, 0.1))
			return best

	var all_moves = _get_all_legal_moves()
	if all_moves.size() <= 1:
		print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(), " | Only 1 move, playing it")
		return best

	var ranked = _static_rank_moves(all_moves, hm, color)
	var is_forcing = _is_forcing(best, ranked, color, profile.forcing_gap_cp)

	print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(),
		" | Mood: ", snapped(mood, 0.01), " | Depth: ", depth,
		" | Forcing: ", is_forcing)

	if is_forcing:
		print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(),
			" | FORCED POSITION — playing best move | Best eval: ", snapped(best.score, 0.1))
		return best

	var mood_mult = lerp(1.6, 0.4, (mood + 1.0) / 2.0)

	var blunder_prob = clamp(profile.blunder_prob * mood_mult, 0.0, 0.80)
	var slip_prob = clamp(profile.slip_prob * mood_mult, 0.0, 0.60)
	var plausible_prob = clamp(profile.plausible_prob * mood_mult, 0.0, 0.95 - blunder_prob - slip_prob)

	var total_human = blunder_prob + slip_prob + plausible_prob
	if total_human > 0.95:
		var scale = 0.95 / total_human
		blunder_prob *= scale
		slip_prob *= scale
		plausible_prob *= scale

	var roll = randf()
	var band_name := "best"
	var picked: Dictionary = best

	if roll < blunder_prob:
		band_name = "blunder"
		picked = _pick_blunder_move(ranked, profile.blunder_band)
	elif roll < blunder_prob + slip_prob:
		band_name = "slip"
		picked = _pick_from_band(ranked, [4, 6], best, profile.slip_max_loss_cp, profile.forcing_gap_cp, color, profile)
		if picked.is_empty():
			picked = best
			band_name = "best (slip filtered)"
	elif roll < blunder_prob + slip_prob + plausible_prob:
		band_name = "plausible"
		picked = _pick_from_band(ranked, [2, 3], best, profile.plausible_max_loss_cp, profile.forcing_gap_cp, color, profile)
		if picked.is_empty():
			picked = best
			band_name = "best (plausible filtered)"

	var loss = best.score - picked.score

	print("[", bot_name, "] ", color, " | Move ", game_state.move_history.size(),
		" | Band: ", band_name,
		" | Best eval: ", snapped(best.score, 0.1),
		" | Played eval: ", snapped(picked.score, 0.1),
		" | Loss: ", snapped(loss, 0.1), " cp",
		" | Rank: ", ranked.find(picked) + 1, "/", ranked.size(),
		" | Probs: B=", snapped(blunder_prob * 100, 0.1),
		"% S=", snapped(slip_prob * 100, 0.1),
		"% P=", snapped(plausible_prob * 100, 0.1), "%")

	return picked

func _static_rank_moves(moves: Array, hm: int, color: String) -> Array:
	var eval_engine = _get_eval_engine()
	var next_turn = "black" if color == "white" else "white"
	var ranked: Array = []

	for m in moves:
		var piece = game_state.board[m.from_row][m.from_col]
		var captured = game_state.board[m.to_row][m.to_col]
		var temp_board = _apply_move_to_board(m, game_state.board)

		eval_engine.set_board(temp_board, next_turn)
		var new_hm = 0 if (captured != "" or piece.ends_with("D")) else hm + 1
		var white_score = eval_engine.evaluate_position(new_hm)
		var mover_score = white_score if color == "white" else -white_score

		var entry = m.duplicate()
		entry["score"] = mover_score
		ranked.append(entry)

	ranked.sort_custom(func(a, b): return a["score"] < b["score"])
	return ranked

func _is_forcing(best: Dictionary, ranked: Array, color: String, gap_threshold: float) -> bool:
	if game_state.engine.is_in_check(color):
		return true
	if best.has("mate") and best.mate != "":
		return true
	if ranked.size() < 2:
		return true
	var top_score = ranked[ranked.size() - 1]["score"]
	var second_score = ranked[ranked.size() - 2]["score"]
	return (top_score - second_score) > gap_threshold

# NEW: Sliding blunder band. [0.0, 0.25] = bottom 25% (worst moves).
# [0.20, 0.45] = 20-45% from the bottom (mediocre, not catastrophic).
func _pick_blunder_move(ranked: Array, band: Array) -> Dictionary:
	var n = ranked.size()
	var min_idx = int(floor(n * band[0]))
	var max_idx = int(ceil(n * band[1]))

	min_idx = clampi(min_idx, 0, n - 1)
	max_idx = clampi(max_idx, min_idx, n - 1)

	var pool_size = max_idx - min_idx + 1
	var idx = min_idx + (randi() % pool_size)
	return ranked[idx]

func _pick_from_band(ranked: Array, band: Array, best: Dictionary, max_loss: float, forcing_gap: float, mover_color: String, profile: Dictionary) -> Dictionary:
	var n = ranked.size()
	if n < 2:
		return {}

	var best_score = best.score
	var min_rank = band[0]
	var max_rank = band[1]

	var pool: Array = []

	for rank in range(min_rank, max_rank + 1):
		if rank > n:
			break
		var idx = n - rank
		if idx < 0:
			continue
		var candidate = ranked[idx]
		var loss = best_score - candidate["score"]

		if loss > max_loss or loss > forcing_gap:
			continue

		var weight: int
		match rank:
			2: weight = 4
			3: weight = 2
			_: weight = 1

		if profile.get("avoid_en_prise", false) and _leaves_piece_en_prise(candidate, mover_color):
			continue

		for w in range(weight):
			pool.append(candidate)

	if pool.is_empty():
		return {}

	return pool[randi() % pool.size()]

func _leaves_piece_en_prise(m: Dictionary, mover_color: String) -> bool:
	var temp_board = _apply_move_to_board(m, game_state.board)
	var eval_engine = _get_eval_engine()
	var mover_prefix = mover_color[0]
	var opp_prefix = "b" if mover_color == "white" else "w"

	eval_engine.set_board(temp_board, mover_color)

	var attacked_by_opp := {}
	var defended_by_mover := {}

	for r in range(7):
		for c in range(7):
			var piece = temp_board[r][c]
			if piece == "":
				continue
			var is_opp = piece.begins_with(opp_prefix)
			var is_mover = piece.begins_with(mover_prefix)
			if not is_opp and not is_mover:
				continue

			var attacks = eval_engine.get_piece_attack_squares(r, c)
			for a in attacks:
				var key = str(a["to_row"]) + "," + str(a["to_col"])
				if is_opp:
					attacked_by_opp[key] = true
				else:
					defended_by_mover[key] = true

	for r in range(7):
		for c in range(7):
			var piece = temp_board[r][c]
			if piece == "" or not piece.begins_with(mover_prefix):
				continue
			if piece[1] == "K":
				continue
			var key = str(r) + "," + str(c)
			if attacked_by_opp.has(key) and not defended_by_mover.has(key):
				return true

	return false

# ──────────────────────────────────────────────────────────────────
# Difficulty entry points
# ──────────────────────────────────────────────────────────────────
func _piece_count() -> int:
	var count = 0
	for r in range(7):
		for c in range(7):
			if game_state.board[r][c] != "":
				count += 1
	return count

func _roulette_bot_move(time_limit: float) -> Dictionary:
	var best = game_state.engine.find_best_move(12, time_limit, game_state.halfmove_clock, game_state.search_threads)
	if not best.has("from_row"):
		print("[Roulette] ", game_state.turn, " | Move ", game_state.move_history.size(), " | No legal moves")
		return _random_legal_move()

	var all_moves = _get_all_legal_moves()
	if all_moves.size() <= 1:
		print("[Roulette] ", game_state.turn, " | Move ", game_state.move_history.size(), " | Only 1 move")
		return best

	var ranked = _static_rank_moves(all_moves, game_state.halfmove_clock, game_state.turn)
	var worst_move = ranked[0]
	var worst_eval = worst_move.score
	var best_eval = ranked[ranked.size() - 1].score

	if randf() < 0.5:
		print("[Roulette] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Playing BEST move | Eval: ", snapped(best_eval, 0.1))
		return best
	else:
		print("[Roulette] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Playing WORST move | Eval: ", snapped(worst_eval, 0.1),
			" | Best was: ", snapped(best_eval, 0.1), " | Loss: ", snapped(best_eval - worst_eval, 0.1), " cp")
		return worst_move

func _beginner_bot_move(time_limit: float) -> Dictionary:
	var all_moves = _get_all_legal_moves()
	if all_moves.size() == 0:
		print("[Beginner] ", game_state.turn, " | Move ", game_state.move_history.size(), " | No legal moves")
		return {}

	# Always use static eval — no engine search, ever.
	var ranked = _static_rank_moves(all_moves, game_state.halfmove_clock, game_state.turn)
	var n = ranked.size()

	var captures = []
	for m in all_moves:
		var to_r = m["to_row"]
		var tc = m["to_col"]
		if game_state.board[to_r][tc] != "":
			captures.append(m)

	# 50% chance to make a random capture (beginners love capturing)
	if captures.size() > 0 and randf() < 0.50:
		var cap = captures[randi() % captures.size()]
		print("[Beginner] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Playing random CAPTURE | ", len(captures), " captures available")
		return cap

	# 30% chance to make a random forward move (beginners push pawns)
	var forward_moves = []
	var is_white = game_state.turn == "white"
	for m in all_moves:
		var fr = m["from_row"]
		var to_r = m["to_row"]
		if is_white and to_r > fr:
			forward_moves.append(m)
		elif not is_white and to_r < fr:
			forward_moves.append(m)

	if forward_moves.size() > 0 and randf() < 0.30:
		var fw = forward_moves[randi() % forward_moves.size()]
		print("[Beginner] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Playing random FORWARD move")
		return fw

	# 20% chance to pick from the better half (still not great, but not worst)
	if randf() < 0.20:
		var pool_start = int(n / 2)
		var idx = pool_start + (randi() % max(1, n - pool_start))
		var picked = ranked[idx]
		var best_eval = ranked[n - 1].score
		print("[Beginner] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Playing from BETTER HALF (static eval) | Eval: ", snapped(picked.score, 0.1),
			" | Best was: ", snapped(best_eval, 0.1))
		return picked

	# Default: random move from the bottom half (worst moves, very beginner-like)
	var pool_end = int(n / 2)
	var idx = randi() % max(1, pool_end + 1)
	var picked = ranked[idx]
	print("[Beginner] ", game_state.turn, " | Move ", game_state.move_history.size(),
		" | Playing RANDOM move (bottom half) | Eval: ", snapped(picked.score, 0.1),
		" | Best was: ", snapped(ranked[n - 1].score, 0.1))
	return picked

func _easy_bot_move(time_limit: float) -> Dictionary:
	return _human_like_move(time_limit, HUMAN_PROFILES["easy"], "Easy")

func _medium_bot_move(time_limit: float) -> Dictionary:
	return _human_like_move(time_limit, HUMAN_PROFILES["medium"], "Medium")

func _hard_bot_move(time_limit: float) -> Dictionary:
	return _human_like_move(time_limit, HUMAN_PROFILES["hard"], "Hard")

func _cautious_bot_move(time_limit: float) -> Dictionary:
	return _human_like_move(time_limit, HUMAN_PROFILES["cautious"], "Cautious")

func _shepherd_bot_move(time_limit: float) -> Dictionary:
	return _human_like_move(time_limit, HUMAN_PROFILES["medium"], "Shepherd", "D")

func _impossible_bot_move(time_limit: float) -> Dictionary:
	var result = game_state.engine.find_best_move(40, time_limit, game_state.halfmove_clock, game_state.search_threads)
	if result.has("from_row"):
		print("[Impossible] ", game_state.turn, " | Move ", game_state.move_history.size(),
			" | Depth reached: ", result.get("depth", "?"), " | Eval: ", snapped(result.score, 0.1),
			" | Nodes: ", result.get("nodes", "?"), " | Time: ", snapped(result.get("time_ms", 0), 0.1), "ms")
	else:
		print("[Impossible] ", game_state.turn, " | Move ", game_state.move_history.size(), " | No legal moves")
	return result

func _random_legal_move() -> Dictionary:
	var all_moves = _get_all_legal_moves()
	if all_moves.size() == 0:
		return {}
	return all_moves[randi() % all_moves.size()]

func _get_all_legal_moves() -> Array:
	var all_moves = []
	for r in range(7):
		for c in range(7):
			var piece = game_state.board[r][c]
			if piece != "" and piece.begins_with(game_state.turn[0]):
				var moves = game_state.engine.get_legal_moves(r, c)
				for m in moves:
					all_moves.append({
						"from_row": r,
						"from_col": c,
						"to_row": m["to_row"],
						"to_col": m["to_col"]
					})
	return all_moves
