extends Node2D
## 벽: 조명과 무관하게 아주 어둡게 항상 보여서 미로 구조는 알 수 있다 (UNSHADED).

var level


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m


func _draw() -> void:
	if level == null or level.w == 0:
		return
	var T: float = level.T
	var wall: Color = level.theme.wall
	var top: Color = level.theme.wall_top
	for y in level.h:
		for x in level.w:
			if level.grid[y * level.w + x] == 1:
				var r := Rect2(x * T, y * T, T, T)
				draw_rect(r, wall)
				# 아래쪽이 바닥이면 벽 윗면 테두리를 밝게 (입체감)
				if y + 1 < level.h and level.grid[(y + 1) * level.w + x] == 0:
					draw_rect(Rect2(r.position.x, r.end.y - 8, T, 8), top)
	# 사물함 (숨을 수 있는 곳)
	for t in level.locker_tiles:
		var p: Vector2 = level.center(t)
		var lr := Rect2(p - Vector2(16, 22), Vector2(32, 40))
		draw_rect(lr, Color("3e5566"))
		draw_rect(lr, Color("8fb3c9"), false, 2.0)
		for i in 3:
			draw_line(lr.position + Vector2(8, 8 + i * 5), lr.position + Vector2(24, 8 + i * 5), Color("8fb3c9"), 1.5)
