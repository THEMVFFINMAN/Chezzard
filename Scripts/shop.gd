extends Control

# Between-floor shop. Deckbuilder-style: buy a generic upgrade card, THEN
# immediately pick which of your army's pieces to drop it on.
#
# Two completely different UIs depending on RunState.test_mode:
#   - Real run (test_mode false): the original flow below (_roll_offers /
#     _render_offers / _render_target_picker) -- 3 random cards + 1 relic,
#     text buttons, costs real gold, untouched by any of this.
#   - Test Shop (test_mode true): _render_queue_builder lets you pick HOW
#     MANy of each card to test, then _start_board_test shows your actual
#     army as real piece sprites on a real board. Click a piece, confirm
#     yes/no, it applies for free (no gold check -- the whole point is to
#     test every purchase without friction) and moves to the next queued
#     card, until the queue's empty.

const MIN_SQUARE = 28.0
const MAX_SQUARE = 72.0  # piece.tscn's actual clickable area is 64x64 (32x32 shape * 2x scale) -- square must exceed that or adjacent squares overlap and steal clicks
const HUD_HEIGHT = 150.0  # fixed strip at the top reserved for status text, so it can never overlap the board below it
const TestBoardStub = preload("res://Scripts/test_board_stub.gd")

@onready var center_container: CenterContainer = $CenterContainer
@onready var gold_label: Label = $CenterContainer/Panel/Margin/VBox/GoldLabel
@onready var floor_label: Label = $CenterContainer/Panel/Margin/VBox/FloorLabel
@onready var offers_box: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Offers
@onready var test_hotseat_btn: Button = $CenterContainer/Panel/Margin/VBox/TestHotseat
@onready var piece_scene = preload("res://Scenes/piece.tscn")

# Cards offered this visit. "value" is the material/modifier name, or the
# movement key ("knight"/"bishop"/"rook") for movement cards, or unused for
# "big". "cost" is flat and paid once, at purchase -- placement never costs
# extra, regardless of which piece (or how valuable a piece) it lands on.
const CARD_OFFERS = [
	{"kind": "material", "value": "silver",  "cost": 30,  "desc": "[Material] Silver (+50% gold)"},
	{"kind": "material", "value": "gold",    "cost": 50,  "desc": "[Material] Gold (+100% gold)"},
	{"kind": "material", "value": "diamond", "cost": 90,  "desc": "[Material] Diamond (+150% gold, no downside)"},
	{"kind": "material", "value": "glass",   "cost": 45,  "desc": "[Material] Glass (4x gold, 25% break chance)"},
	{"kind": "material", "value": "blood",   "cost": 70,  "desc": "[Material] Blood (5x gold, lost for good if it dies)"},
	{"kind": "material", "value": "iron",    "cost": 65,  "desc": "[Material] Iron (uncapturable)"},
	{"kind": "modifier", "value": "double",  "cost": 200, "desc": "[Modifier] Double (move twice)"},
	{"kind": "modifier", "value": "zombie", "cost": 120, "desc": "[Modifier] Zombie (demotes a rung instead of dying, if captured)"},
	{"kind": "movement", "value": "knight",  "cost": 80,  "desc": "[Movement] Knight (add a knight's leap)"},
	{"kind": "movement", "value": "bishop",  "cost": 80,  "desc": "[Movement] Bishop (add diagonal sliding)"},
	{"kind": "movement", "value": "rook",    "cost": 80,  "desc": "[Movement] Rook (add orthogonal sliding)"},
	{"kind": "movement", "value": "king",    "cost": 60,  "desc": "[Movement] King (add a one-step royal stride)"},
	{"kind": "movement", "value": "queen",   "cost": 150, "desc": "[Movement] Queen (add full diagonal+orthogonal sliding)"},
	{"kind": "big",      "value": "",        "cost": 50,  "desc": "[Transform] Big (remove the \"short\" restriction)"},
	# Unlike every other card, this one's valid targets are LOST slots
	# (RunState.lost_slots()), not occupied army_slots() -- see _slots_for().
	{"kind": "add_pawn", "value": "",       "cost": 40, "desc": "[Piece] Refill Pawn (replace a slot you've lost a piece from)"},
	# Grows the army PAST the starting 16 -- lands on a blank square in
	# RunState.growth_slots() (one rank ahead of the pawn row), not a lost one.
	{"kind": "grow_pawn", "value": "short", "cost": 50, "desc": "[Piece] Grow Short Pawn (add a brand new pawn, one rank ahead)"},
	{"kind": "grow_pawn", "value": "full",  "cost": 90, "desc": "[Piece] Grow Pawn (add a brand new full pawn, one rank ahead)"},
]

var _offers := []   # rolled offers this visit (cards + at most one relic) -- real-run flow only
var _picking := -1  # index into _offers awaiting a target pick, or -1 for the main list -- real-run flow only

# --- Test-mode queue/board state ---
var _queue_spins := {}      # CARD_OFFERS index -> SpinBox, queue-builder screen
var _queue := []            # flattened list of card dicts to test, in order
var _queue_pos := 0
var _board_root: Node2D = null
var _board_bg: Control = null
var _board_pieces := []     # instantiated piece nodes this test-board render, for cleanup
var _test_hud: VBoxContainer = null  # status text during active board-testing -- NOT inside
                                      # center_container, so it can never overlap the board


func _ready() -> void:
	floor_label.text = "Floor %d of %d cleared" % [RunState.floor - 1, RunState.FLOOR_COUNT]
	test_hotseat_btn.visible = RunState.test_mode
	if RunState.test_mode:
		_render_queue_builder()
	else:
		_roll_offers()


func _exit_tree() -> void:
	_clear_board_visual()
	if _test_hud != null:
		_test_hud.queue_free()
		_test_hud = null


# Debug/testing: play the next floor as human-vs-human instead of vs the AI,
# so you can freely move the upgraded piece around (and its opponent's
# pieces, to get them out of the way) without fighting the engine's play.
func _on_test_hotseat_pressed() -> void:
	RunState.test_hotseat = true
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


func _on_next_floor_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


# =====================================================================
# TEST MODE: queue builder -> real board, one card at a time
# =====================================================================

# "How many of each do you want to test?" -- a quantity per card type.
func _render_queue_builder() -> void:
	_awaiting_click = false
	_clear_board_visual()
	if _test_hud != null:
		_test_hud.queue_free()
		_test_hud = null
	center_container.visible = true
	for c in offers_box.get_children():
		c.queue_free()
	_queue_spins.clear()
	offers_box.visible = true
	gold_label.text = "Gold: %d (ignored in test mode)" % RunState.gold

	var title = Label.new()
	title.text = "How many of each do you want to test?"
	offers_box.add_child(title)

	for i in CARD_OFFERS.size():
		var card = CARD_OFFERS[i]
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = card["desc"]
		lbl.custom_minimum_size = Vector2(300, 0)
		row.add_child(lbl)
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 10
		spin.value = 0
		row.add_child(spin)
		offers_box.add_child(row)
		_queue_spins[i] = spin

	var start_btn = Button.new()
	start_btn.text = "Start Testing"
	start_btn.pressed.connect(_on_start_testing_pressed)
	offers_box.add_child(start_btn)


func _on_start_testing_pressed() -> void:
	_queue.clear()
	for i in _queue_spins:
		var count = int(_queue_spins[i].value)
		for n in count:
			_queue.append(CARD_OFFERS[i])
	if _queue.is_empty():
		return
	_queue_pos = 0
	_start_board_test()


func _start_board_test() -> void:
	center_container.visible = false  # the shop panel would otherwise sit centered ON TOP of the board
	_ensure_test_hud()
	_build_board_visual()
	_show_current_queue_item()


# Square size + board origin, computed from the actual viewport every time so
# the board always fits below the fixed HUD strip instead of overflowing or
# overlapping it.
func _board_metrics() -> Dictionary:
	var vp = get_viewport().get_visible_rect().size
	var avail_w = vp.x - 40.0
	var avail_h = vp.y - HUD_HEIGHT - 20.0
	var sq = clamp(min(avail_w, avail_h) / 8.0, MIN_SQUARE, MAX_SQUARE)
	var board_px = sq * 8.0
	var origin = Vector2((vp.x - board_px) / 2.0, HUD_HEIGHT)
	return {"square": sq, "origin": origin}


# Rebuilds the on-screen board (checkered squares + piece sprites) from
# RunState.army -- called once at the start, and again after every applied
# upgrade (a piece's type/sprite may have changed).
func _build_board_visual() -> void:
	_clear_board_visual()
	var metrics = _board_metrics()
	var sq = metrics["square"]
	var origin = metrics["origin"]

	_board_bg = Control.new()
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never steal clicks meant for a piece
	add_child(_board_bg)
	for rank in range(1, 9):
		for file in range(8):
			var r = ColorRect.new()
			r.position = origin + Vector2(file, 8 - rank) * sq
			r.size = Vector2(sq, sq)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.color = Color(0.82, 0.74, 0.60) if (rank + file) % 2 == 0 else Color(0.40, 0.30, 0.22)
			_board_bg.add_child(r)

	_board_root = TestBoardStub.new()
	add_child(_board_root)
	for rank in range(1, 9):
		var row = RunState.army.get(rank, [])
		for file in range(8):
			var cell = row[file] if file < row.size() else null
			if cell == null:
				continue
			_spawn_piece(cell, rank, file, origin, sq)

	# Blank growth-row squares have no piece to click -- give them a ghost
	# marker so Grow Pawn/Grow Short Pawn actually have something clickable.
	for slot in RunState.growth_slots():
		_spawn_ghost(slot["rank"], slot["file"], origin, sq)


func _spawn_piece(cell, rank: int, file: int, origin: Vector2, sq: float) -> void:
	var piece_type = cell["piece"] if cell is Dictionary else cell
	var sprite_name = "white_" + Globals.give_piece_name_from_piece_type(piece_type)
	var p = piece_scene.instantiate()
	var pos = origin + Vector2(file, 8 - rank) * sq + Vector2(sq, sq) / 2.0
	_board_root.add_child(p)
	# Pure display + click-target: legal_moves stays empty forever, so
	# piece.gd's own pickup/drag _process() logic never triggers. Clicking is
	# detected by OUR _process() below polling p.has_mouse (set by piece.gd's
	# own mouse_entered/mouse_exited, which fire regardless of legal_moves)
	# -- the same hover+poll pattern piece.gd itself uses, not the
	# CollisionObject2D.input_event signal, which nothing else in this
	# project actually relies on and turned out not to fire here.
	p.initialize(true, sprite_name, _square(rank, file), piece_type, pos)
	# piece.tscn's art is drawn at a fixed pixel size (2x the 16px atlas tiles
	# = 32px) regardless of our square size, so scale it to actually fill a
	# differently-sized square instead of floating at a mismatched scale.
	p.scale = Vector2.ONE * (sq / 32.0)
	if cell is Dictionary and cell.get("material", "") != "":
		p.apply_material(cell["material"])
	if cell is Dictionary and cell.get("modifiers", []).size() > 0:
		p.apply_modifiers(cell["modifiers"])
	_board_pieces.append({"node": p, "rank": rank, "file": file, "piece_type": piece_type})


func _spawn_ghost(rank: int, file: int, origin: Vector2, sq: float) -> void:
	var g = GhostMarker.new()
	g.position = origin + Vector2(file, 8 - rank) * sq + Vector2(sq, sq) / 2.0
	g.size = sq * 0.25
	_board_root.add_child(g)
	_board_pieces.append({"node": g, "rank": rank, "file": file, "piece_type": null})


func _clear_board_visual() -> void:
	if _board_root != null:
		_board_root.queue_free()
		_board_root = null
	if _board_bg != null:
		_board_bg.queue_free()
		_board_bg = null
	_board_pieces.clear()


func _ensure_test_hud() -> VBoxContainer:
	if _test_hud == null:
		_test_hud = VBoxContainer.new()
		_test_hud.position = Vector2(20, 16)
		_test_hud.custom_minimum_size = Vector2(500, 0)
		add_child(_test_hud)
	return _test_hud


func _clear_test_hud() -> void:
	if _test_hud != null:
		for c in _test_hud.get_children():
			c.queue_free()


func _show_current_queue_item() -> void:
	var hud = _ensure_test_hud()
	_clear_test_hud()
	if _queue_pos >= _queue.size():
		_awaiting_click = false
		_show_queue_complete()
		return
	_awaiting_click = true
	var card = _queue[_queue_pos]
	var title = Label.new()
	title.text = "Testing %d/%d: %s" % [_queue_pos + 1, _queue.size(), card["desc"]]
	hud.add_child(title)
	var hint = Label.new()
	hint.text = "Click a valid piece on the board below: %s" % _valid_target_hint(card)
	hud.add_child(hint)
	var skip_btn = Button.new()
	skip_btn.text = "Skip this one"
	skip_btn.pressed.connect(_advance_queue)
	hud.add_child(skip_btn)
	_update_piece_validity_visuals(card)


# Greys out + X-marks every board piece that ISN'T a legal target for the
# given card, so it's obvious at a glance what you can/can't click instead
# of finding out by trial and error.
func _update_piece_validity_visuals(card) -> void:
	for entry in _board_pieces:
		var p = entry["node"]
		if not is_instance_valid(p):
			continue
		for c in p.get_children():
			if c is XMark:
				c.queue_free()
		if _target_ok(card, entry["piece_type"], entry["rank"], entry["file"]):
			p.modulate = Color.WHITE
		else:
			p.modulate = Color(0.55, 0.55, 0.55, 1.0)
			p.add_child(XMark.new())


# Human-readable list of which pieces a card can currently land on, for the
# on-screen hint (materials/modifiers take anything, so just say so).
func _valid_target_hint(card) -> String:
	if card["kind"] == "modifier" and card["value"] == "zombie":
		return "any non-royal piece"
	if card["kind"] == "material" or card["kind"] == "modifier":
		return "any piece"
	if card["kind"] == "add_pawn":
		return "an empty slot where you've lost a piece this run"
	if card["kind"] == "grow_pawn":
		return "a blank square one rank ahead of your pawn row"
	var table = Globals.BIG_UPGRADES if card["kind"] == "big" else Globals.MOVEMENT_UPGRADES.get(card["value"], {})
	var names = []
	for pt in table:
		var n = Globals.give_piece_name_from_piece_type(pt).capitalize()
		if n not in names:
			names.append(n)
	return ", ".join(names) if not names.is_empty() else "(nothing in your current army yet)"


# Polls for a click on the board every frame -- deliberately NOT using
# physics picking (CollisionObject2D.input_event, or piece.gd's own
# has_mouse/mouse_entered) at all, since two different attempts at that both
# silently failed to fire for these dynamically-spawned pieces and I can't
# confirm why. This instead does plain geometry against the exact same
# origin/sq this frame's board was actually drawn with -- no physics
# subsystem involved, so it can't have the same failure mode.
# Only live while actually waiting on a pick (_awaiting_click), so a click
# during e.g. the Yes/No confirm doesn't double-fire.
var _awaiting_click := false

func _process(_delta: float) -> void:
	if not _awaiting_click or _board_pieces.is_empty():
		return
	if not Input.is_action_just_pressed("left_click"):
		return
	var metrics = _board_metrics()
	var origin = metrics["origin"]
	var sq = metrics["square"]
	var rel = get_viewport().get_mouse_position() - origin
	if rel.x < 0.0 or rel.y < 0.0 or rel.x >= sq * 8.0 or rel.y >= sq * 8.0:
		return
	var file = int(rel.x / sq)
	var rank = 8 - int(rel.y / sq)
	for entry in _board_pieces:
		if entry["rank"] == rank and entry["file"] == file:
			_on_board_piece_clicked(rank, file, entry["piece_type"])
			return


func _on_board_piece_clicked(rank: int, file: int, piece_type) -> void:
	if _queue_pos >= _queue.size():
		return
	var card = _queue[_queue_pos]
	if not _target_ok(card, piece_type, rank, file):
		return  # not a legal target for the card currently being tested
	_awaiting_click = false
	_show_confirm(card, {"rank": rank, "file": file, "piece": piece_type})


func _show_confirm(card, slot) -> void:
	var hud = _ensure_test_hud()
	_clear_test_hud()
	var pname = "the empty slot" if card["kind"] in ["add_pawn", "grow_pawn"] else Globals.give_piece_name_from_piece_type(slot["piece"]).capitalize()
	var sq = _square(slot["rank"], slot["file"])
	var title = Label.new()
	title.text = "Apply %s to %s (%s)?" % [card["desc"], pname, sq]
	hud.add_child(title)
	var row = HBoxContainer.new()
	var yes_btn = Button.new()
	yes_btn.text = "Yes"
	yes_btn.pressed.connect(_confirm_queue_apply.bind(slot))
	row.add_child(yes_btn)
	var no_btn = Button.new()
	no_btn.text = "No"
	no_btn.pressed.connect(_show_current_queue_item)
	row.add_child(no_btn)
	hud.add_child(row)


func _confirm_queue_apply(slot) -> void:
	var card = _queue[_queue_pos]
	_apply_card(card, slot)
	_advance_queue()


func _advance_queue() -> void:
	_queue_pos += 1
	_build_board_visual()  # a piece's type may have changed -- re-render from RunState.army
	_show_current_queue_item()


func _show_queue_complete() -> void:
	_clear_board_visual()
	if _test_hud != null:
		_test_hud.queue_free()
		_test_hud = null
	center_container.visible = true
	for c in offers_box.get_children():
		c.queue_free()
	offers_box.visible = true
	var title = Label.new()
	title.text = "Queue complete. Build another, or test a battle below."
	offers_box.add_child(title)
	var again_btn = Button.new()
	again_btn.text = "Queue More"
	again_btn.pressed.connect(_render_queue_builder)
	offers_box.add_child(again_btn)


# Shared by both the test queue and the real shop flow below.
func _apply_card(card, slot) -> void:
	match card["kind"]:
		"material":
			RunState.set_material(slot["rank"], slot["file"], card["value"])
		"modifier":
			RunState.add_modifier(slot["rank"], slot["file"], card["value"])
		"movement":
			RunState.transform(slot["rank"], slot["file"], Globals.MOVEMENT_UPGRADES[card["value"]][slot["piece"]])
		"big":
			RunState.transform(slot["rank"], slot["file"], Globals.BIG_UPGRADES[slot["piece"]])
		"add_pawn":
			RunState.add_pawn(slot["rank"], slot["file"])
		"grow_pawn":
			RunState.grow_pawn(slot["file"], card["value"] == "short")


# =====================================================================
# REAL RUN: original roll/buy flow, untouched
# =====================================================================

func _roll_offers() -> void:
	_offers.clear()
	_picking = -1

	var relic = _roll_relic()
	if relic != null:
		_offers.append(relic)

	var pool = CARD_OFFERS.duplicate()
	pool.shuffle()
	var added = 0
	for card in pool:
		if added >= 3:
			break
		if _card_is_offerable(card):
			_offers.append(card)
			added += 1

	_render_offers()


# False if this card has zero legal targets right now -- e.g. Big with no
# short piece left, Refill Pawn with no lost slot, Grow Pawn with the growth
# row already full. Any card-sampling path (this roll, and eventually pack
# contents) must gate on this so a dead option can never actually be offered.
func _card_is_offerable(card) -> bool:
	return not _valid_targets(card, _slots_for(card)).is_empty()


# A relic offer for a random unowned relic (null if you own them all).
func _roll_relic():
	var available = []
	for id in Globals.RELICS:
		if not RunState.has_relic(id):
			available.append(id)
	if available.is_empty():
		return null
	var id = available[randi() % available.size()]
	var r = Globals.RELICS[id]
	return {
		"kind": "relic",
		"relic_id": id,
		"cost": r["cost"],
		"desc": "RELIC — %s: %s" % [r["name"], r["desc"]],
	}


# Refill Pawn's valid targets are LOST slots; Grow Pawn's are blank GROWTH
# slots -- neither is occupied army_slots() like every other card -- route to
# the right source.
func _slots_for(card):
	match card["kind"]:
		"add_pawn":
			return RunState.lost_slots()
		"grow_pawn":
			return RunState.growth_slots()
		_:
			return RunState.army_slots()


# Which slots a card can legally land on.
func _valid_targets(card, slots):
	var valid = []
	for slot in slots:
		if _target_ok(card, slot.get("piece"), slot["rank"], slot["file"]):
			valid.append(slot)
	return valid


func _target_ok(card, piece_type, rank: int = -9999, file: int = -9999) -> bool:
	match card["kind"]:
		"add_pawn":
			for slot in RunState.lost_slots():
				if slot["rank"] == rank and slot["file"] == file:
					return true
			return false
		"grow_pawn":
			for slot in RunState.growth_slots():
				if slot["rank"] == rank and slot["file"] == file:
					return true
			return false
	# Every other card needs an actual piece to land on -- rules out the
	# blank ghost-marker squares rendered for the two slot kinds above.
	if piece_type == null:
		return false
	match card["kind"]:
		"material":
			return true
		"modifier":
			# A respawning royal would break checkmate/extinction detection
			# outright -- never a legal target for this one modifier.
			if card["value"] == "zombie" and Globals.PIECE_REGISTRY.get(piece_type, {}).get("royal", false):
				return false
			return true
		"movement":
			return Globals.MOVEMENT_UPGRADES.get(card["value"], {}).has(piece_type)
		"big":
			return Globals.BIG_UPGRADES.has(piece_type)
	return false


# Deckbuilder-style: you pay once to OWN the card, then placement is free --
# the price never depends on which piece you land it on.
func _card_cost(offer) -> int:
	return offer["cost"]


func _render_offers() -> void:
	for c in offers_box.get_children():
		c.queue_free()
	gold_label.text = "Gold: %d" % RunState.gold
	if _offers.is_empty():
		var none = Label.new()
		none.text = "Nothing left to buy."
		offers_box.add_child(none)
		return
	for i in _offers.size():
		var offer = _offers[i]
		var btn = Button.new()
		btn.name = "Offer%d" % i
		btn.text = offer["desc"] if offer["kind"] == "relic" else "%s   —   %d g   —   pick a piece" % [offer["desc"], _card_cost(offer)]
		btn.disabled = RunState.gold < _card_cost(offer)
		btn.pressed.connect(_on_offer_pressed.bind(i))
		offers_box.add_child(btn)


func _on_offer_pressed(i: int) -> void:
	var offer = _offers[i]
	if offer["kind"] == "relic":
		_buy_relic(i)
		return
	_picking = i
	_render_target_picker()


func _render_target_picker() -> void:
	for c in offers_box.get_children():
		c.queue_free()
	var offer = _offers[_picking]
	var slots = _valid_targets(offer, _slots_for(offer))
	var cost = _card_cost(offer)

	var title = Label.new()
	title.text = "Apply %s (%d g) to:" % [offer["desc"], cost]
	offers_box.add_child(title)

	for slot in slots:
		var sq = _square(slot["rank"], slot["file"])
		var label = "Empty slot (%s)" % sq if offer["kind"] in ["add_pawn", "grow_pawn"] else "%s (%s)" % [Globals.give_piece_name_from_piece_type(slot["piece"]), sq]
		var btn = Button.new()
		btn.text = label
		btn.disabled = RunState.gold < cost
		btn.pressed.connect(_confirm_purchase.bind(slot))
		offers_box.add_child(btn)

	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_cancel_picking)
	offers_box.add_child(cancel)


func _cancel_picking() -> void:
	_picking = -1
	_render_offers()


func _confirm_purchase(slot) -> void:
	var offer = _offers[_picking]
	var cost = _card_cost(offer)
	if RunState.gold < cost:
		return
	RunState.add_gold(-cost, "shop")
	_apply_card(offer, slot)
	_offers.remove_at(_picking)
	_picking = -1
	_render_offers()


func _buy_relic(i: int) -> void:
	var offer = _offers[i]
	if RunState.gold < offer["cost"]:
		return
	RunState.add_gold(-offer["cost"], "shop")
	RunState.add_relic(offer["relic_id"])
	_offers.remove_at(i)
	_render_offers()


func _square(rank, file) -> String:
	return "%s%d" % [String.chr(97 + file), rank]
