extends Node2D
## 줍는 아이템(열쇠/배터리/부적)과 출구. 어둠 속에서도 반짝임이 보이게 UNSHADED로 그린다.

class Item:
	var kind := "key"
	var pos := Vector2.ZERO
	var taken := false
	var seen := false


var run
var list: Array = []
var t := 0.0
var exit_open := false
var exit_light: PointLight2D


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m


func setup(level) -> void:
	list.clear()
	exit_open = false
	for kt in level.key_tiles:
		_add("key", level.center(kt))
	for bt in level.battery_tiles:
		_add("battery", level.center(bt))
	for tt in level.talisman_tiles:
		_add("talisman", level.center(tt))
	if exit_light:
		exit_light.queue_free()
	exit_light = PointLight2D.new()
	exit_light.texture = run.radial_tex
	exit_light.texture_scale = 2.4
	exit_light.color = Color(0.3, 1.0, 0.5)
	exit_light.energy = 0.0
	exit_light.position = exit_pos()
	add_child(exit_light)


func _add(kind: String, p: Vector2) -> void:
	var it := Item.new()
	it.kind = kind
	it.pos = p
	list.append(it)


func exit_pos() -> Vector2:
	var lv = run.level
	return lv.center(lv.exit_tile) + Vector2(lv.T * 0.5, lv.T * 0.5)


func keys_left() -> int:
	var n := 0
	for it in list:
		if it.kind == "key" and not it.taken:
			n += 1
	return n


func open_exit() -> void:
	exit_open = true
	exit_light.energy = 1.0


## 방장/혼자: 모든 플레이어의 줍기를 판정한다
func update(delta: float) -> void:
	update_visual(delta)
	for i in list.size():
		var it: Item = list[i]
		if it.taken:
			continue
		for p in run.players:
			if p.alive() and not p.in_locker and it.pos.distance_to(p.pos) < 30.0:
				it.taken = true
				run.on_pickup(it.kind, i, p)
				break


## 참가자: 그리기/발견 표시만
func update_visual(delta: float) -> void:
	t += delta
	var pl = run.local
	for it in list:
		if not it.taken and not it.seen and it.pos.distance_to(pl.pos) < 260.0 and run.level.los(pl.pos, it.pos):
			it.seen = true  # 미니맵에 표시
	if exit_open:
		exit_light.energy = 0.8 + sin(t * 4.0) * 0.25
	queue_redraw()


func mark_taken(idx: int) -> void:
	if idx >= 0 and idx < list.size():
		list[idx].taken = true


func taken_mask() -> String:
	var s := ""
	for it in list:
		s += "1" if it.taken else "0"
	return s


func apply_mask(m: String) -> void:
	for i in min(m.length(), list.size()):
		if m[i] == "1":
			list[i].taken = true


func _draw() -> void:
	var pl = run.local
	if pl == null:
		return
	for it in list:
		if it.taken:
			continue
		var bob := sin(t * 3.0 + it.pos.x) * 3.0
		var p: Vector2 = it.pos + Vector2(0, bob)
		var near: float = clamp(1.0 - it.pos.distance_to(pl.pos) / 420.0, 0.15, 1.0)
		var tw: float = 0.5 + 0.5 * sin(t * 6.0 + it.pos.y)
		draw_circle(p, 16.0 + tw * 4.0, Color(1, 0.95, 0.6, 0.12 * near + 0.06))
		match it.kind:
			"key":
				var c := Color(1, 0.84, 0.25, near)
				draw_circle(p + Vector2(-7, 0), 7.0, c)
				draw_circle(p + Vector2(-7, 0), 3.0, Color(0, 0, 0, near))
				draw_rect(Rect2(p + Vector2(-1, -2), Vector2(14, 4)), c)
				draw_rect(Rect2(p + Vector2(8, 2), Vector2(3, 5)), c)
				draw_rect(Rect2(p + Vector2(3, 2), Vector2(3, 4)), c)
			"battery":
				var c := Color(0.5, 1, 0.5, near)
				draw_rect(Rect2(p - Vector2(7, 11), Vector2(14, 22)), c)
				draw_rect(Rect2(p - Vector2(3, 14), Vector2(6, 3)), c)
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 2)), Color(0, 0, 0, near * 0.7))
			"talisman":
				var c := Color(1, 0.9, 0.4, near)
				draw_rect(Rect2(p - Vector2(8, 14), Vector2(16, 28)), c)
				draw_line(p + Vector2(-4, -8), p + Vector2(4, -2), Color(0.8, 0.1, 0.1, near), 2.0)
				draw_line(p + Vector2(4, -8), p + Vector2(-4, 4), Color(0.8, 0.1, 0.1, near), 2.0)
				draw_line(p + Vector2(-4, 8), p + Vector2(4, 8), Color(0.8, 0.1, 0.1, near), 2.0)
	# 출구 표시
	var e := exit_pos()
	if exit_open:
		var a: float = 0.6 + 0.4 * sin(t * 4.0)
		draw_arc(e, 54.0, 0.0, TAU, 40, Color(0.4, 1, 0.5, a), 4.0)
		draw_string(ThemeDB.fallback_font, e + Vector2(-34, -62), "출구", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.5, 1, 0.6, a))
	else:
		draw_arc(e, 50.0, 0.0, TAU, 40, Color(1, 0.3, 0.3, 0.35), 3.0)
