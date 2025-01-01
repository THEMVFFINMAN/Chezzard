extends Node

var stockfish_stdio : FileAccess = null
var stockfish_stderr : FileAccess = null
var stockfish_thread : Thread = Thread.new()
var pid : int
var stock_fish_string = ""

var board

# Commands and response buffer
var response_buffer : String = ""
var is_running : bool = false

var load_variants_string : String = "setoption name VariantPath value C:\\Users\\JJ\\Documents\\Github\\Chezzard\\Engine\\variants.ini"
var set_custom_variant_string : String = "setoption name UCI_Variant value custom"
var start_position_string : String = "position start"
var start_game_string : String = "ucinewgame"
var go_depth_string : String = "go depth 10"

var regex = RegEx.new()
var regex_moves_pattern = r"^[a-zA-Z]\d{1,2}[a-zA-Z]\d{1,2}: 1$"

var legal_moves = []

var thread_timer

var board_size = Vector2.ZERO

var computer_opponent = false
var player_white = true


# Called when the node enters the scene tree for the first time
func _ready():
	
	thread_timer = $thread_timer
	
	regex.compile(regex_moves_pattern)
	
	board = get_node("Board")
	# Start the Stockfish process
	start_stockfish_thread()
	get_tree().set_auto_accept_quit(false)
	
	#get_tree().connect("tree_exiting", stop_stockfish)
	
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_stockfish()
		get_tree().quit() # default behavior

# Start the Stockfish thread
func start_stockfish_thread():
	# Start the Stockfish process in a new thread
	stockfish_thread.start(_run_stockfish)  # No need for 'self', just the function name
	

# This function runs in a separate thread
func _run_stockfish():
	var command = "cmd"   # Command to execute Stockfish
	var args = ["/K", "C:\\Users\\JJ\\Documents\\Github\\Chezzard\\Engine\\stockfish.exe"]  # No arguments passed in this example
	
	# Execute Stockfish with pipes for stdio and stderr
	var result = OS.execute_with_pipe(command, args)
	
	if result == null:
		print("Error starting Stockfish process.")
		return
	
	stockfish_stdio = result["stdio"]
	stockfish_stderr = result["stderr"]
	pid = result["pid"]
	
	is_running = true
	print("Stockfish started and running.")
	send_to_stockfish("setoption name Debug Log File value debug.log")
	send_to_stockfish(load_variants_string)
	send_to_stockfish(set_custom_variant_string)
	
	if board.generated_fen_string.length() > 0:
		send_to_stockfish("position startpos")
		send_to_stockfish("position fen " + board.generated_fen_string)
	else:
		send_to_stockfish(start_position_string)
	send_to_stockfish(start_game_string)
	
	var timer = Timer.new()
	call_deferred("add_child", timer)
	timer.wait_time = .2
	timer.one_shot = true
	timer.timeout.connect(perft)
	timer.autostart = true
	
	
	while(true):
		read_stockfish()

func read_stockfish():
	if stockfish_stdio.is_open() and stockfish_stderr.get_error() == OK:
		var chunk = stockfish_stdio.get_buffer(2048)	
		var output = str(chunk.get_string_from_utf8())
	
		call_deferred("go_outside_thread_read", output)
		
func go_outside_error_read(error_output):
	print("test")
	print(error_output)
	
func go_outside_thread_read(output):
	if "check" in output and "Nodes searched: 0" not in output:
		print("\n\n\nCHECK\n\n\n")
		
	if "Nodes searched: 0" in output:
		print(board.white_to_move)
		print("\n\n\nCHECKMATE\n\n\n")
	
	if "info" not in output and ": 1" not in output and "Winnable" not in output:
		print("output    ", output)
	
	if "bestmove" in output:
		if computer_opponent and board.is_computer_turn():
			
			thread_timer.start()
			await thread_timer.timeout
			
			var computer_move = board.get_array_of_individual_moves_from_fen_string(output.split(" ")[1])
			board.call_deferred("move", computer_move[0], computer_move[1])
		
	if ": 1" in output:
		
		#print(output)
		var multilines = output.split("\n")
		for line in multilines:
			line = line.replace("\r", "")
		
			if regex.search(line):
				if line not in legal_moves:
					legal_moves.append(line)

				
	if legal_moves.size() > 0:
		board.call_deferred("add_legal_moves_to_pieces", legal_moves)
	legal_moves = []
			
			
func perft():
	send_to_stockfish("go perft 1")
		

func _add_char(c):
	if c.to_utf8_buffer()[0] == 10:
		print(stock_fish_string)
		stock_fish_string = ""
	else:
		stock_fish_string += c

# Send a command to Stockfish
func send_to_stockfish(command: String):
	if is_running:
		var cmd = command + "\n"
		var buffer = cmd.to_utf8_buffer()
		#var err=pipe.get_error()
		stockfish_stdio.store_buffer(buffer)
		
		print("Sent command: ", command)

# Stop the Stockfish process
func stop_stockfish():
	is_running = false
	if stockfish_stdio and stockfish_stderr:
		stockfish_stdio.close()
		stockfish_stderr.close()
	print("Stockfish stopped.")
