extends CanvasLayer

# Emitted when the player starts a game: which opponent + which game mode id.
signal mode_chosen(vs_computer, mode_id)

@onready var mode_option = $CenterContainer/Panel/VBox/ModeOption


func _ready() -> void:
	# Populate the mode dropdown from the GameModes table (order = insertion).
	var i = 0
	for id in GameModes.MODES:
		mode_option.add_item(GameModes.MODES[id]["name"])
		mode_option.set_item_metadata(i, id)
		i += 1


func _selected_mode() -> String:
	return mode_option.get_item_metadata(mode_option.selected)


func _on_human_pressed() -> void:
	mode_chosen.emit(false, _selected_mode())


func _on_computer_pressed() -> void:
	mode_chosen.emit(true, _selected_mode())
