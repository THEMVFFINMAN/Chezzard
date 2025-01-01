extends Node2D

var boardcontainer 
var board 
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	boardcontainer = get_parent().get_node("BoardContainer")
	board = boardcontainer.get_node("Board")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_undo_button_down() -> void:
	board.undo()


func _on_redo_button_down() -> void:
	board.redo()
