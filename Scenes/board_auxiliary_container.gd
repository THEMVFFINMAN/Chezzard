extends CanvasLayer

@onready var undo_button: Button = $HBoxContainer/Undo
@onready var redo_button: Button = $HBoxContainer/Redo

var board


func _ready() -> void:
	board = get_parent().get_node("BoardContainer/Board")
	board.nav_buttons_enabled.connect(_on_nav_buttons_enabled)


func _on_nav_buttons_enabled(enabled: bool) -> void:
	undo_button.disabled = not enabled
	redo_button.disabled = not enabled


func _on_undo_button_down() -> void:
	board.undo()


func _on_redo_button_down() -> void:
	board.redo()
