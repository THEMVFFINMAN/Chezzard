extends Node
class_name EngineBridge

# Single point of contact with Fairy-Stockfish, via the FairyEngine GDExtension
# (works on Windows/Android/iOS/etc). There is intentionally NO stockfish.exe
# subprocess fallback: if the extension isn't compiled, this errors loudly
# instead of silently using a desktop-only path.
#
# Build the extension first (see native/README.md). Until then the game can't
# talk to the engine.
#
# Emits `line_received` once per UCI output line, on the main thread.

signal line_received(line: String)

var _native: Node = null


func start() -> void:
	if not ClassDB.class_exists("FairyEngine"):
		push_error("[EngineBridge] FairyEngine extension not found. Build it first (see native/README.md). The engine will not run.")
		return
	_native = ClassDB.instantiate("FairyEngine")
	add_child(_native)
	_native.output_received.connect(_on_native_line)
	_native.start()
	print("[EngineBridge] using native FairyEngine extension")


func send(command: String) -> void:
	if _native:
		_native.send_command(command)


func stop() -> void:
	if _native:
		_native.stop()


func is_ready() -> bool:
	return _native != null


func _on_native_line(line: String) -> void:
	line_received.emit(line)
