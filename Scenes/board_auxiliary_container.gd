extends CanvasLayer

var boardcontainer
var board

func _ready() -> void:
	boardcontainer = get_parent().get_node("BoardContainer")
	board = boardcontainer.get_node("Board")


func _on_undo_button_down() -> void:
	board.undo()


func _on_redo_button_down() -> void:
	board.redo()
