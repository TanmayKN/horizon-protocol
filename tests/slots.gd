extends SceneTree
var game
var n := 0
func _initialize() -> void:
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
func _process(_d: float) -> bool:
	n += 1
	var w = game.player.weapon
	if n == 10:
		w.take_gun("ak", 30)
		w.take_gun("dmr", 10)
		print("full: ", w.slots.map(func(x): return x["id"]), " current=", w.current)
		w.switch_to(0)
		w.drop_current()
		print("after drop: ", w.slots.map(func(x): return x["id"]), " current=", w.current, " drops=", game.weapon_drops.size())
		w.take_gun("carbine", 20)
		print("picked back: ", w.slots.map(func(x): return x["id"]), " current=", w.current)
		w.switch_to(1)
		game.weapon_drops.clear()
		w.take_gun("carbine", 5)
		print("same gun -> ammo 5.56=", w.reserves["5.56"])
		quit()
	return false
