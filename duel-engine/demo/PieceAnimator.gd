#PieceAnimator.gd
extends Node2D

signal move_finished
signal capture_finished

const CELL_SIZE = 80

var _tween: Tween
var _active_piece: Node2D = null
var _is_animating: bool = false

func _ready():
	position = Vector2.ZERO
	z_index = 10

func is_animating() -> bool:
	return _is_animating

func animate_move(from_row: int, from_col: int, to_row: int, to_col: int, piece_code: String) -> void:
	"""
	Slides a piece from one square to another.
	Call this BEFORE mutating the board array.
	"""
	_kill_active()

	_is_animating = true
	_active_piece = _build_piece_visual(piece_code)
	_active_piece.position = _cell_center(from_row, from_col)
	_active_piece.z_index = 20
	add_child(_active_piece)

	var target_pos = _cell_center(to_row, to_col)

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_active_piece, "position", target_pos, 0.18)
	_tween.tween_callback(_finish_move)


func animate_capture(from_row: int, from_col: int, to_row: int, to_col: int, 
					 piece_code: String, captured_code: String) -> void:
	"""
	Slides the attacker to the target, flashes the captured square, then finishes.
	"""
	_kill_active()

	_is_animating = true
	_active_piece = _build_piece_visual(piece_code)
	_active_piece.position = _cell_center(from_row, from_col)
	_active_piece.z_index = 20
	add_child(_active_piece)

	var target_pos = _cell_center(to_row, to_col)

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_active_piece, "position", target_pos, 0.20)

	# Brief impact pause on arrival
	_tween.tween_interval(0.06)
	_tween.tween_callback(_flash_square.bind(to_row, to_col))
	_tween.tween_interval(0.10)
	_tween.tween_callback(_finish_capture)


func animate_illegal_wiggle(row: int, col: int, piece_code: String) -> void:
	"""
	Shows the piece wiggling and returning to its origin.
	Useful when a player selects an invalid destination.
	"""
	_kill_active()

	_is_animating = true
	var origin = _cell_center(row, col)
	_active_piece = _build_piece_visual(piece_code)
	_active_piece.position = origin
	_active_piece.z_index = 20
	add_child(_active_piece)

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)

	# Small left-right wiggle
	_tween.tween_property(_active_piece, "position:x", origin.x - 6, 0.08)
	_tween.tween_property(_active_piece, "position:x", origin.x + 6, 0.08)
	_tween.tween_property(_active_piece, "position:x", origin.x, 0.08)
	_tween.tween_callback(_finish_move)

func _build_piece_visual(code: String) -> Node2D:
	# Same visual as the static pieces (built by BoardRenderer).
	return get_parent().make_piece_visual(code)

func _flash_square(row: int, col: int) -> void:
	var flash = ColorRect.new()
	flash.position = get_parent().cell_pos(row, col)
	flash.size = Vector2(CELL_SIZE, CELL_SIZE)
	flash.color = Color("#ef4444")
	flash.modulate = Color(1, 1, 1, 0.5)
	flash.z_index = 15
	add_child(flash)

	var t = create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.25)
	t.tween_callback(flash.queue_free)


func _cell_center(row: int, col: int) -> Vector2:
	return get_parent().cell_center(row, col)  # follows board flipping


func _kill_active() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _active_piece:
		_active_piece.queue_free()
		_active_piece = null
	_is_animating = false


func _finish_move() -> void:
	_kill_active()
	move_finished.emit()


func _finish_capture() -> void:
	_kill_active()
	capture_finished.emit()
