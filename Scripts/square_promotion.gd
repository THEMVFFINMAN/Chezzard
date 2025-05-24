extends Node2D

var white = true
var center = Vector2.ZERO
var has_mouse
var clicked = false
var piece_type

@onready var Board = get_parent().get_parent().get_parent().get_parent()

func delete_self():
	queue_free()

func get_center():
	return Vector2(global_position.x + get_node("CollisionShape2D").shape.extents.x/2, global_position.y + get_node("CollisionShape2D").shape.extents.y/2)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:	
	if has_mouse and Input.is_action_pressed("left_click"):
		if !clicked:
			var promoted_piece_type = str(get_node("piece").piece_type)
			
			print("PIECE TYPE   " + promoted_piece_type)
			print("LAST HELD PIECE   ", Board.last_held_piece)
			
			var promoted_piece = Board.last_held_piece
			promoted_piece.piece_type = promoted_piece_type
			
			var animation_string = "white_"
			animation_string += Globals.give_piece_name_from_piece_type(int(promoted_piece_type))
			promoted_piece.get_node("Sprite2D").play(animation_string)
			Board.get_parent().promotion = false
			clicked = true
			
			get_parent().hide()
			
	if clicked and !Input.is_action_pressed("left_click"):
		clicked = false


func _on_mouse_entered() -> void:
	has_mouse = true


func _on_mouse_exited() -> void:
	has_mouse = false
