extends Node

# Run-wide state. For now just gold; the army, relics, and floor progression come
# with the run loop later. Persists across battles (autoload).
signal gold_changed(total)

var gold := 0
var floor := 0  # current floor (0 until the run loop sets it)
var lost_origins := []  # army slots (start squares) permanently lost — e.g. blood deaths

func add_gold(amount, reason = ""):
	gold += amount
	gold_changed.emit(gold)
	print("[gold] +%d (%s) -> %d total" % [amount, reason, gold])

# A piece permanently removed from the run army (e.g. a blood piece that died).
# The next battle's army rebuild should skip these origin squares.
func lose_piece(origin):
	if origin != "" and origin not in lost_origins:
		lost_origins.append(origin)
		print("[run] permanently lost the piece from %s" % origin)
