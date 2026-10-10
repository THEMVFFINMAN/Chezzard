extends CanvasLayer

# Generic end-of-game popup: shows the result ("You Win" / "You Lose" / "Draw",
# or "White Wins" / "Black Wins" in hot-seat) and a Main Menu button. Reloading
# main.tscn lands back on mode select in every case that reaches this popup --
# RunState.in_run is already false by the time a run-ending result gets here
# (board_container._finish_game sets it before showing the popup), and a
# mode-select game never set it true in the first place.

func _ready():
	$CenterContainer/Panel/Margin/VBox/PlayAgainButton.pressed.connect(_on_play_again)

func set_result(text):
	$CenterContainer/Panel/Margin/VBox/ResultLabel.text = text

func _on_play_again():
	get_tree().reload_current_scene()
