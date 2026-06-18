extends Node

# Talks to Fairy-Stockfish through EngineBridge, which transparently uses the
# native GDExtension on mobile (and desktop, once compiled) or falls back to the
# stockfish.exe subprocess on desktop while the extension isn't built yet.

const MODE_SELECT_SCENE = preload("res://Scenes/mode_select.tscn")
const GAME_OVER_SCENE = preload("res://Scenes/game_over.tscn")

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
var side_in_check = false  # from the engine's eval; tells checkmate from stalemate

var thread_timer

var board_size = Vector2.ZERO

var computer_opponent = false
var player_white = true
var current_variant = "custom"
var _variant_path_override = ""  # set when a mode uses a generated variants.ini


func _ready():
	thread_timer = $thread_timer

	regex.compile(regex_moves_pattern)

	board = get_node("Board")
	board.game_over.connect(_show_game_over)
	board.three_check_won.connect(_on_three_check_won)

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


func _show_game_over(text):
	var popup = GAME_OVER_SCENE.instantiate()
	add_child(popup)
	popup.set_result(text)


func _on_three_check_won(white_won):
	if computer_opponent:
		_show_game_over("You Win" if white_won else "You Lose")
	else:
		_show_game_over("White Wins" if white_won else "Black Wins")


func _on_mode_chosen(vs_computer, mode_id, popup):
	# You always start as white. Human = you control both colours; Computer = AI plays black.
	computer_opponent = vs_computer
	player_white = true
	board.computer_opponent = vs_computer
	board.player_white = true
	current_variant = GameModes.apply(board, mode_id)  # configure the board, get the variant
	var m = GameModes.modes().get(mode_id, {})
	# Resolve the starting placements first, so the roster can be derived from them.
	var pl
	if m.has("placements"):
		pl = m["placements"]
	else:
		pl = VariantBuilder.layout_to_placements(m.get("layout", GameModes.default_layout()), board.width)
	var enum_to_char
	if m.get("generated", false):
		# Build a fresh variants.ini from the roster (explicit, else just the pieces
		# in play + promotion targets — never the whole registry, which would blow
		# the 26-letter limit). Its letter map is shared with parsing/placements.
		var roster = m.get("roster", VariantBuilder.roster_for_placements(pl))
		var build = VariantBuilder.build(roster, board.length, "generated", m.get("rules", []), m.get("royal_count", 1))
		_variant_path_override = VariantBuilder.write_variant_file(build["text"])
		current_variant = build["variant"]
		Globals.set_active_char_map(build["char_to_enum"], build["enum_to_char"])
		enum_to_char = build["enum_to_char"]
	else:
		_variant_path_override = ""
		Globals.reset_char_map()
		enum_to_char = Globals.default_enum_to_char()
	# Position always comes from the layout/placements — never a hardcoded FEN.
	board.generated_fen_string = VariantBuilder.placements_to_fen(pl, enum_to_char, board.width, board.length)
	board.test_materials = VariantBuilder.placements_materials(pl)
	board.test_modifiers = VariantBuilder.placements_modifiers(pl)
	board.build_board()
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
	var vpath = _variant_path_override if _variant_path_override != "" else _variants_path()
	send_to_stockfish("setoption name VariantPath value " + vpath)
	send_to_stockfish("setoption name UCI_Variant value " + current_variant)

	if board.generated_fen_string.length() > 0:
		send_to_stockfish("position startpos")
		# Use the generated FEN (stones become "*" wall squares the engine respects).
		send_to_stockfish("position fen " + board.generate_fen_string())
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

	# Track whether the side to move is in check (from the eval), so a perft of 0
	# can be told apart as checkmate vs. stalemate.
	if line.begins_with("Final evaluation"):
		side_in_check = "in check" in line

	if line.begins_with("bestmove"):
		if computer_opponent and board.is_computer_turn():
			if line.split(" ")[1] == "(none)":
				return  # no legal move (mate/stalemate) — game-over/cascade handles it
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
			board.call_deferred("add_wall_piece_moves")
			board.call_deferred("apply_modifier_filters")
			if line == "Nodes searched: 0":
				# No engine moves; re-check after wall moves are added, then end.
				board.call_deferred("check_game_over", side_in_check)
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
