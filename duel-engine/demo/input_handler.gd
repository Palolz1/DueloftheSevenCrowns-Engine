#InputHandler.gd
# Turns mouse input over the board into board squares (via BoardRenderer, so
# it follows the board orientation).
extends Node2D

signal square_clicked(row: int, col: int)
signal square_hovered(row: int, col: int)

var _last_hover := Vector2i(-2, -2)

func _input(event):
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var board_renderer = get_parent().get_node("BoardRenderer")
	if not board_renderer.visible:
		return
	var info = get_parent().get_node_or_null("Info")
	if info != null and info.visible:
		return  # the Pieces overlay is open
	var sq: Vector2i = board_renderer.local_to_board(board_renderer.get_local_mouse_position())
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and sq.x >= 0:
			square_clicked.emit(sq.x, sq.y)
	elif sq != _last_hover:
		_last_hover = sq
		square_hovered.emit(sq.x, sq.y)
