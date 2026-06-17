extends Node

# Talks to Fairy-Stockfish through EngineBridge, which transparently uses the
# native GDExtension on mobile (and desktop, once compiled) or falls back to the
# stockfish.exe subprocess on desktop while the extension isn't built yet.

const MODE_SELECT_SCENE = preload("res://Scenes/mode_select.tscn")

var engine: EngineBridge

var board

var promotion = false

var is_running: bool = false

var set_custom_variant_string: String = "setoption name UCI_Variant value custom"
var start_position_string: String = "position start"
var start_game_string: String = "ucinewgame"
var go_depth_string: String = "go depth 10"

var regex = RegEx.new()
var regex_moves_pattern = r"^[a-zA-Z]\d{1,2}[a-zA-Z]\d{1,2}[qrbn]?: 1$"

var legal_moves = []

var thread_timer

var board_size = Vector2.ZERO

var computer_opponent = false
var player_white = true


func _ready():
	thread_timer = $thread_timer

	regex.compile(regex_moves_pattern)

	board = get_node("Board")

	engine = EngineBridge.new()
	engine.name = "EngineBridge"
	add_child(engine)
	engine.line_received.connect(_on_engine_line)
	engine.start()

	get_tree().set_auto_accept_quit(false)

	# Ask who the opponent is before booting the game.
	_show_mode_select()


func _show_mode_select():
	var popup = MODE_SELECT_SCENE.instantiate()
	add_child(popup)
	popup.mode_chosen.connect(_on_mode_chosen.bind(popup))


func _on_mode_chosen(vs_computer, popup):
	# You always start as white. Human = you control both colours; Computer = AI plays black.
	computer_opponent = vs_computer
	player_white = true
	board.computer_opponent = vs_computer
	board.player_white = true
	popup.queue_free()
	_init_engine()


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_stockfish()
		get_tree().quit() # default behavior


# Configure the engine once it's up.
func _init_engine():
	is_running = true
	send_to_stockfish("setoption name Debug Log File value debug.log")
	send_to_stockfish("setoption name VariantPath value " + _variants_path())
	if board.three_check:
		send_to_stockfish("setoption name UCI_Variant value custom3check")
	else:
		send_to_stockfish(set_custom_variant_string)

	if board.generated_fen_string.length() > 0:
		send_to_stockfish("position startpos")
		send_to_stockfish("position fen " + board.generated_fen_string)
	else:
		send_to_stockfish(start_position_string)
	send_to_stockfish(start_game_string)

	var timer = Timer.new()
	timer.wait_time = .2
	timer.one_shot = true
	timer.timeout.connect(perft)
	add_child(timer)
	timer.start()


# Copy the bundled variants.ini to a real filesystem path so the native engine
# (which can't read res:// inside an .apk/.ipa) can open it. The globalized
# user:// path is absolute, so it also works for the desktop subprocess.
func _variants_path() -> String:
	var dst := "user://variants.ini"
	var src := "res://Engine/variants.ini"
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin:
		var text := fin.get_as_text()
		fin.close()
		var fout := FileAccess.open(dst, FileAccess.WRITE)
		if fout:
			fout.store_string(text)
			fout.close()
	else:
		push_error("[board_container] could not read " + src + " (make sure *.ini is included in export)")
	return ProjectSettings.globalize_path(dst)


# Per-line handler. Both engine backends deliver one UCI line at a time.
func _on_engine_line(line: String) -> void:
	if line.begins_with("C:\\Users"):
		print("CRASHED")
		return

	# 3-check: the engine's eval prints "(in check)" for the side to move, so
	# whoever just moved delivered a check.
	if board.three_check and "(in check)" in line:
		board.register_check(not board.white_to_move)

	if "checkmate" in line or line == "Nodes searched: 0":
		print("\n\n\nCHECKMATE\n\n\n")

	if line.begins_with("bestmove"):
		if computer_opponent and board.is_computer_turn():
			thread_timer.start()
			await thread_timer.timeout

			var computer_move = board.get_array_of_individual_moves_from_fen_string(line.split(" ")[1])
			board.call_deferred("move", computer_move[0], computer_move[1])
		return

	# Legal-move line from "go perft 1", e.g. "e2e4: 1".
	if regex.search(line):
		if line not in legal_moves:
			legal_moves.append(line)
		return

	# End of the perft listing -> publish the collected legal moves.
	if line.begins_with("Nodes searched"):
		if not promotion:
			board.call_deferred("add_legal_moves_to_pieces", legal_moves.duplicate())
		legal_moves.clear()
		return


func perft():
	send_to_stockfish("go perft 1")


# Send a command to the engine. Kept under this name so board.gd is unchanged.
func send_to_stockfish(command: String):
	if is_running and engine:
		engine.send(command)


# Stop the engine.
func stop_stockfish():
	is_running = false
	if engine:
		engine.stop()
	print("Engine stopped.")
