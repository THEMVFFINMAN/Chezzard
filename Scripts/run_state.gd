extends Node

# Run-wide state: a persistent army, gold, and a 10-floor climb. Drives the
# roguelike loop — board_container reads current_battle(); the shop edits army.
signal gold_changed(total)

const FLOOR_COUNT = 10

var gold := 0
var floor := 0
var in_run := false
var lost_origins := []     # army start-squares lost permanently (e.g. blood deaths)
var army := {}             # persistent white layout { rank: [cells] }


func start_run():
	in_run = true
	floor = 1
	gold = 0
	lost_origins = []
	army = _default_army()
	gold_changed.emit(gold)


func advance():
	floor += 1


func is_complete():
	return floor > FLOOR_COUNT


func add_gold(amount, reason = ""):
	gold += amount
	gold_changed.emit(gold)
	print("[gold] +%d (%s) -> %d total" % [amount, reason, gold])


# A piece permanently removed from the run army (e.g. a blood piece that died).
func lose_piece(origin):
	if origin != "" and origin not in lost_origins:
		lost_origins.append(origin)
		print("[run] permanently lost the piece from %s" % origin)


# Battle config for the current floor: your army vs the floor's enemy.
func current_battle():
	var f = _floor_config(floor)
	return {
		"generated": true,
		"layout": {"white": _army_layout(), "black": f["enemy"]},
		"rules": f.get("rules", []),
		"royal_count": f.get("royal_count", 1),
		"head_of_snake": f.get("head_of_snake", false),
		"unroyal": f.get("unroyal", false),
		"three_check": f.get("three_check", false),
		"name": f.get("name", "Floor %d" % floor),
	}


# The army as a layout, with permanently-lost slots emptied.
func _army_layout():
	var out := {}
	for rank in army:
		out[rank] = army[rank].duplicate()
	for origin in lost_origins:
		var file = origin.unicode_at(0) - "a".unicode_at(0)
		var rnk = int(origin.substr(1))
		if out.has(rnk) and file >= 0 and file < out[rnk].size():
			out[rnk][file] = null
	return out


# Start small ("half everything"): the royal prince, a couple of pieces, and four
# pawns. The shop builds you up from here.
func _default_army():
	var E = Globals.Piece_Type_ENUMs
	return {
		1: [E.SHORTROOK, E.MULE, E.SHORTBISHOP, E.PRINCE, null, null, null, null],
		2: [E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, E.SHORTPAWN, null, null, null, null],
	}


# Escalating enemy per floor; floor 10 is the Wizard (a head-of-snake boss).
func _floor_config(f):
	var E = Globals.Piece_Type_ENUMs
	var cfg := {"name": "Floor %d" % f}
	if f >= FLOOR_COUNT:
		cfg["name"] = "The Wizard"
		cfg["head_of_snake"] = true
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, E.ARCHBISHOP, E.QUEEN, E.KING, E.ARCHBISHOP, E.KNIGHT, E.ROOK], 7: E.PAWN}
	elif f >= 7:
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, E.BISHOP, E.QUEEN, E.KING, E.BISHOP, E.KNIGHT, E.ROOK], 7: E.PAWN}
	elif f >= 4:
		cfg["enemy"] = {8: [E.ROOK, E.KNIGHT, null, E.QUEEN, E.KING, null, E.KNIGHT, E.ROOK], 7: E.PAWN}
	else:
		# Early floors: a weak "dwarf" army — king, queen, two bishops, four pawns.
		cfg["enemy"] = {
			8: [null, E.BISHOP, null, E.QUEEN, E.KING, E.BISHOP, null, null],
			7: [null, E.PAWN, null, E.PAWN, E.PAWN, E.PAWN, null, null],
		}
	return cfg


# --- Shop helpers (mutate the army) ---
# Non-empty slots, excluding the royal prince (you can't sell/transform your king).
func army_slots():
	var E = Globals.Piece_Type_ENUMs
	var slots := []
	for rank in army:
		for file in army[rank].size():
			var cell = army[rank][file]
			if cell == null:
				continue
			var piece = cell["piece"] if cell is Dictionary else cell
			if piece == E.PRINCE or piece == E.KING:
				continue
			slots.append({"rank": rank, "file": file, "piece": piece})
	return slots


func _cell_dict(rank, file):
	var cell = army[rank][file]
	return cell.duplicate() if cell is Dictionary else {"piece": cell}


func set_material(rank, file, material):
	var d = _cell_dict(rank, file)
	d["material"] = material
	army[rank][file] = d


func add_modifier(rank, file, modifier):
	var d = _cell_dict(rank, file)
	var mods = d.get("modifiers", []).duplicate()
	if modifier not in mods:
		mods.append(modifier)
	d["modifiers"] = mods
	army[rank][file] = d


func transform(rank, file, new_piece):
	var d = _cell_dict(rank, file)
	d["piece"] = new_piece
	army[rank][file] = d
