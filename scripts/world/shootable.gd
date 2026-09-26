extends StaticBody3D
## Something that reacts to being shot (lamps, glass, etc.). Emits `shot` once.

signal shot(pos: Vector3)

var broken := false


func on_shot(pos: Vector3) -> void:
	if broken:
		return
	broken = true
	shot.emit(pos)
