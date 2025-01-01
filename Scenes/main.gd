extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func initiate_board_auxiliary():
	var board_size = get_node("BoardContainer").board_size
	get_node("BoardAuxiliaryContainer/HBoxContainer").global_position = Vector2(board_size.x/2 - 50, board_size.y + 50)
