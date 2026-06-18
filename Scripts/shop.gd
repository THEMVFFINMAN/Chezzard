extends Control

# Between-floor shop. Spends RunState.gold to upgrade the persistent army
# (materials / modifiers / transforms), then continues to the next floor.

@onready var gold_label: Label = $CenterContainer/Panel/Margin/VBox/GoldLabel
@onready var floor_label: Label = $CenterContainer/Panel/Margin/VBox/FloorLabel
@onready var offers_box: VBoxContainer = $CenterContainer/Panel/Margin/VBox/Offers

# Upgrade catalogue: a label, a cost, and how it mutates a chosen army slot.
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

var _offers := []  # rolled offers: {label, cost, slot, kind, value}


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

	var slots = RunState.army_slots()
	if slots.is_empty():
		var none = Label.new()
		none.text = "No pieces left to upgrade."
		offers_box.add_child(none)
		return

	# Roll three distinct upgrade offers across random pieces.
	var pool = MATERIAL_OFFERS + MODIFIER_OFFERS
	pool.shuffle()
	for i in min(3, pool.size()):
		var u = pool[i]
		var slot = slots[randi() % slots.size()]
		var pname = Globals.give_piece_name_from_piece_type(slot["piece"])
		var sq = _square(slot["rank"], slot["file"])
		_offers.append({
			"label": u["verb"] % [pname, sq],
			"cost": u["cost"],
			"slot": slot,
			"kind": u["kind"],
			"value": u["value"],
		})

	for i in _offers.size():
		var offer = _offers[i]
		var btn = Button.new()
		btn.name = "Offer%d" % i
		btn.text = "%s   —   %d g" % [offer["label"], offer["cost"]]
		btn.pressed.connect(_buy.bind(i))
		offers_box.add_child(btn)


func _buy(i: int) -> void:
	var offer = _offers[i]
	var btn = offers_box.get_node_or_null("Offer%d" % i)
	if btn == null or btn.disabled:
		return
	if RunState.gold < offer["cost"]:
		return
	RunState.add_gold(-offer["cost"], "shop")
	var slot = offer["slot"]
	match offer["kind"]:
		"material":
			RunState.set_material(slot["rank"], slot["file"], offer["value"])
		"modifier":
			RunState.add_modifier(slot["rank"], slot["file"], offer["value"])
	btn.disabled = true
	btn.text += "   ✓"
	_refresh_gold()


func _square(rank, file) -> String:
	return "%s%d" % [String.chr(97 + file), rank]


func _on_next_floor_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")
