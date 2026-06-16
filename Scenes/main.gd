extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func initiate_board_auxiliary():
	# The Back/Forward buttons are now positioned by the CanvasLayer anchors in
	# board_auxiliary_container.tscn (pinned to the top-right of the screen).
	# The old board_size-based global_position pushed them off-screen, so it's
	# intentionally removed.
	pass
