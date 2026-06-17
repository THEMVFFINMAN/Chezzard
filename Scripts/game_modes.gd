class_name GameModes
extends RefCounted

# A game mode = an engine variant (defined in Engine/variants.ini) plus optional
# overrides for the starting position, board size, and rule flags.
#
# Modes that only change the win condition (same 8x8 army) just name a variant.
# Modes with a different setup add "fen" / "width" / "length". Purely game-side
# rules (e.g. Head of Snake) will add a "hook" id handled in board.gd later.
const MODES = {
	"standard": {
		"name": "Standard",
		"variant": "custom",
	},
	"three_check": {
		"name": "Three Check",
		"variant": "custom3check",
		"three_check": true,
	},
	"atomic": {
		"name": "Atomic",
		"variant": "customatomic",
	},
	"koth": {
		"name": "King of the Hill",
		"variant": "customkoth",
	},
}

# Configure the board for a mode and return the engine variant name to select.
# Only keys the mode specifies are overridden, so a mode with no "fen" keeps the
# board's default army (and the user's edited starting FEN).
static func apply(board, mode_id):
	var m = MODES.get(mode_id, MODES["standard"])
	if m.has("fen") and m["fen"] != "":
		board.generated_fen_string = m["fen"]
	board.width = m.get("width", board.width)
	board.length = m.get("length", board.length)
	board.three_check = m.get("three_check", false)
	return m["variant"]
