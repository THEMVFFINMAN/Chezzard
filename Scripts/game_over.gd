extends CanvasLayer

# Generic end-of-game popup: shows the result ("You Win" / "You Lose" / "Draw",
# or "White Wins" / "Black Wins" in hot-seat) and a Play Again button that
# restarts the scene. Animations/polish come later.

func _ready():
	$CenterContainer/Panel/Margin/VBox/PlayAgainButton.pressed.connect(_on_play_again)

func set_result(text):
	$CenterContainer/Panel/Margin/VBox/ResultLabel.text = text

func _on_play_again():
	get_tree().reload_current_scene()
