extends Node2D

var has_mouse = false
var clicked = false
var piece_type

@onready var Board = get_tree().get_first_node_in_group("board")


func delete_self():
	queue_free()


func _process(_delta: float) -> void:
	if has_mouse and Input.is_action_pressed("left_click") and not clicked:
		clicked = true
		Board.complete_promotion(get_node("piece").piece_type)
	if clicked and not Input.is_action_pressed("left_click"):
		clicked = false


func _on_mouse_entered() -> void:
	has_mouse = true


func _on_mouse_exited() -> void:
	has_mouse = false
