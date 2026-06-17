extends CanvasLayer

# Emitted when the player picks an opponent. vs_computer = true -> play the AI.
signal mode_chosen(vs_computer)


func _on_human_pressed() -> void:
	mode_chosen.emit(false)


func _on_computer_pressed() -> void:
	mode_chosen.emit(true)
