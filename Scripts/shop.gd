extends Control

# Between-floor shop. Spends RunState.gold on army upgrades (materials, modifiers,
# piece transformations) and run-wide relics, then continues to the next floor.

@onready var gold_label: Label = $CenterContainer/Panel/Margin/VBox/GoldLabel
@onready var floor_label: Label = $CenterContainer/Panel/Margin/VBox/FloorLabel
@onready var offers_box: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Offers

# Per-piece material/modifier upgrades. The %s placeholders are (piece name, square).
const MATERIAL_OFFERS = [
	{"kind": "material", "value": "silver", "cost": 25, "verb": "Plate %s (%s) in silver  (+50%% gold)"},
	{"kind": "material", "value": "gold",   "cost": 45, "verb": "Plate %s (%s) in gold  (+100%% gold)"},
	{"kind": "material", "value": "glass",  "cost": 40, "verb": "Forge %s (%s) in glass  (4x gold, 25%% break)"},
	{"kind": "material", "value": "blood",  "cost": 70, "verb": "Bind %s (%s) in blood  (5x gold, lost if it dies)"},
	{"kind": "material", "value": "iron",   "cost": 60, "verb": "Cast %s (%s) in iron  (uncapturable)"},
]
const MODIFIER_OFFERS = [
	{"kind": "modifier", "value": "double", "cost": 50, "verb": "Give %s (%s) Double (move twice)"},
	{"kind": "modifier", "value": "time1",  "cost": 20, "verb": "Give %s (%s) Time1 (1-turn cooldown)"},
]

var _offers := []  # rolled offers (see _roll_offers for the dict shape)


func _ready() -> void:
	floor_label.text = "Floor %d of %d cleared" % [RunState.floor - 1, RunState.FLOOR_COUNT]
	_roll_offers()
	_refresh_gold()


func _refresh_gold() -> void:
	gold_label.text = "Gold: %d" % RunState.gold
	for i in _offers.size():
		var btn = offers_box.get_node_or_null("Offer%d" % i)
		if btn and not btn.disabled:
			btn.disabled = RunState.gold < _offers[i]["cost"]


func _roll_offers() -> void:
	for c in offers_box.get_children():
		c.queue_free()
	_offers.clear()

	# One relic offer (a random one you don't already own), then three piece upgrades.
	var relic = _roll_relic()
	if relic != null:
		_offers.append(relic)
	_offers.append_array(_roll_piece_offers(3))

	if _offers.is_empty():
		var none = Label.new()
		none.text = "Nothing left to buy."
		offers_box.add_child(none)
		return

	for i in _offers.size():
		var offer = _offers[i]
		var btn = Button.new()
		btn.name = "Offer%d" % i
		btn.text = "%s   —   %d g" % [offer["label"], offer["cost"]]
		btn.pressed.connect(_buy.bind(i))
		offers_box.add_child(btn)


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
		"label": "RELIC — %s: %s" % [r["name"], r["desc"]],
	}


# Up to `count` upgrade offers (material / modifier / transform) on random pieces.
func _roll_piece_offers(count):
	var slots = RunState.army_slots()
	var offers = []
	if slots.is_empty():
		return offers
	var pool = MATERIAL_OFFERS + MODIFIER_OFFERS
	pool.shuffle()
	var pi = 0
	for n in count:
		var slot = slots[randi() % slots.size()]
		var pname = Globals.give_piece_name_from_piece_type(slot["piece"])
		var sq = _square(slot["rank"], slot["file"])
		# Sometimes offer a transformation if this piece has an upgrade path.
		var target = Globals.piece_upgrade(slot["piece"])
		if target != null and randi() % 2 == 0:
			offers.append({
				"kind": "transform",
				"slot": slot,
				"value": target,
				"cost": Globals.upgrade_cost(slot["piece"]),
				"label": "Transform %s (%s) -> %s" % [pname, sq, Globals.give_piece_name_from_piece_type(target)],
			})
		else:
			var u = pool[pi % pool.size()]
			pi += 1
			offers.append({
				"kind": u["kind"],
				"slot": slot,
				"value": u["value"],
				"cost": u["cost"],
				"label": u["verb"] % [pname, sq],
			})
	return offers


func _buy(i: int) -> void:
	var offer = _offers[i]
	var btn = offers_box.get_node_or_null("Offer%d" % i)
	if btn == null or btn.disabled or RunState.gold < offer["cost"]:
		return
	RunState.add_gold(-offer["cost"], "shop")
	match offer["kind"]:
		"relic":
			RunState.add_relic(offer["relic_id"])
		"material":
			RunState.set_material(offer["slot"]["rank"], offer["slot"]["file"], offer["value"])
		"modifier":
			RunState.add_modifier(offer["slot"]["rank"], offer["slot"]["file"], offer["value"])
		"transform":
			RunState.transform(offer["slot"]["rank"], offer["slot"]["file"], offer["value"])
	btn.disabled = true
	btn.text += "   ✓"
	_refresh_gold()


func _square(rank, file) -> String:
	return "%s%d" % [String.chr(97 + file), rank]


func _on_next_floor_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")
