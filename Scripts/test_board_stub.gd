extends Node2D

# Minimal stand-in "board" for shop.gd's test-queue piece display. piece.gd
# sets board = get_parent() and unconditionally reads board.moves.size() (for
# the cooldown badge) and, if a piece has the "racist" modifier,
# board._square_color() -- both normally real board.gd members. These pieces
# are pure display/click-targets (legal_moves stays empty, so piece.gd's own
# pickup/_process logic never triggers), so this just needs to not crash.

var moves = []


func _square_color(_chess_position):
	return 0
