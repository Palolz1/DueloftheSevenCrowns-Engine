#InputHandler.gd
extends Node2D

const CELL_SIZE = 80

signal square_clicked(row: int, col: int)
signal square_hovered(row: int, col: int)

func _input(event):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var board_renderer = get_parent().get_node("BoardRenderer")
			var mouse_pos = get_global_mouse_position() - board_renderer.global_position
			var c = int(mouse_pos.x / CELL_SIZE)
			var r = int(mouse_pos.y / CELL_SIZE)
			
			if r >= 0 and r < 7 and c >= 0 and c < 7:
				square_clicked.emit(r, c)
	
	elif event is InputEventMouseMotion:
		var board_renderer = get_parent().get_node("BoardRenderer")
		var mouse_pos = get_global_mouse_position() - board_renderer.global_position
		var c = int(mouse_pos.x / CELL_SIZE)
		var r = int(mouse_pos.y / CELL_SIZE)
		
		if r >= 0 and r < 7 and c >= 0 and c < 7:
			square_hovered.emit(r, c)
		else:
			square_hovered.emit(-1, -1)
