extends CanvasLayer

# Emitted when the player starts a game: which opponent + which game mode id.
signal mode_chosen(vs_computer, mode_id)
# Emitted when the player starts the roguelike run (army + 10-floor climb).
signal start_run
# Debug/testing: jump straight to the shop (see RunState.start_test_shop()).
signal test_shop

@onready var mode_option = $CenterContainer/Panel/VBox/ModeOption
@onready var kings_row = $CenterContainer/Panel/VBox/KingsRow
@onready var white_kings_spin = $CenterContainer/Panel/VBox/KingsRow/WhiteKings
@onready var black_kings_spin = $CenterContainer/Panel/VBox/KingsRow/BlackKings
@onready var snake_row = $CenterContainer/Panel/VBox/SnakeRow
@onready var white_snake_check = $CenterContainer/Panel/VBox/SnakeRow/WhiteSnake
@onready var black_snake_check = $CenterContainer/Panel/VBox/SnakeRow/BlackSnake


func _ready() -> void:
	# Populate the mode dropdown from the GameModes table (order = insertion).
	var ms = GameModes.modes()
	var i = 0
	for id in ms:
		mode_option.add_item(ms[id]["name"])
		mode_option.set_item_metadata(i, id)
		i += 1
	mode_option.item_selected.connect(_on_mode_option_item_selected)
	white_kings_spin.value_changed.connect(_on_white_kings_changed)
	black_kings_spin.value_changed.connect(_on_black_kings_changed)
	white_kings_spin.value = GameModes.lopsided_white_count
	black_kings_spin.value = GameModes.lopsided_black_count
	white_snake_check.toggled.connect(_on_white_snake_toggled)
	black_snake_check.toggled.connect(_on_black_snake_toggled)
	white_snake_check.button_pressed = GameModes.snake_white_enabled
	black_snake_check.button_pressed = GameModes.snake_black_enabled
	_on_mode_option_item_selected(max(mode_option.selected, 0))


# "Lopsided Kings" needs the White/Black Kings spinboxes; "Head of Snake"
# needs the per-side enable checkboxes -- each hidden for every other mode.
func _on_mode_option_item_selected(index: int) -> void:
	var mode_id = mode_option.get_item_metadata(index)
	kings_row.visible = (mode_id == "lopsided_kings")
	snake_row.visible = (mode_id == "head_of_snake")


func _on_white_kings_changed(value: float) -> void:
	GameModes.lopsided_white_count = int(value)


func _on_black_kings_changed(value: float) -> void:
	GameModes.lopsided_black_count = int(value)


func _on_white_snake_toggled(pressed: bool) -> void:
	GameModes.snake_white_enabled = pressed


func _on_black_snake_toggled(pressed: bool) -> void:
	GameModes.snake_black_enabled = pressed


func _selected_mode() -> String:
	return mode_option.get_item_metadata(mode_option.selected)


func _on_human_pressed() -> void:
	mode_chosen.emit(false, _selected_mode())


func _on_computer_pressed() -> void:
	mode_chosen.emit(true, _selected_mode())


func _on_start_run_pressed() -> void:
	start_run.emit()


func _on_test_shop_pressed() -> void:
	test_shop.emit()
