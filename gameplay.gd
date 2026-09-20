extends Node

func _ready():
	var engine = DuelEngine.new()
	print(engine.get_engine_info())
	
	# Set up starting board
	var board = _create_starting_board()
	engine.set_board(board, "white")
	
	# Evaluate position
	var eval = engine.evaluate_position(0)
	print("Evaluation: ", eval)
	
	# Find best move
	var result = engine.find_best_move(10, 2.0, 0)
	print("Best move: ", result)

func _create_starting_board() -> Array:
	var board = []
	for r in range(7):
		var row = []
		for c in range(7):
			row.append("")
		board.append(row)
	
	# White pieces (row 0)
	board[0][0] = "wC"
	board[0][1] = "wN"
	board[0][2] = "wP"
	board[0][3] = "wK"
	board[0][4] = "wW"
	board[0][5] = "wN"
	board[0][6] = "wM"
	
	# White Donkeys (row 1)
	for c in range(7):
		board[1][c] = "wD"
	
	# Black pieces (row 6)
	board[6][0] = "bC"
	board[6][1] = "bN"
	board[6][2] = "bP"
	board[6][3] = "bK"
	board[6][4] = "bW"
	board[6][5] = "bN"
	board[6][6] = "bM"
	
	# Black Donkeys (row 5)
	for c in range(7):
		board[5][c] = "bD"
	
	return board
