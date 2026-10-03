extends Node2D
## 귀신 3종. 방장(또는 혼자 하기)만 AI를 계산하고, 참가자는 받은 위치를 그대로 그린다.
##  - 처녀귀신: 순찰 → 보이면 추격 → 놓치면 마지막 위치 수색. 발소리도 듣는다.
##  - 달걀귀신: 느리지만 벽을 통과해 가장 가까운 사람에게 다가온다.
##  - 저승사자: 빠르게 추격하지만 손전등 빛을 받으면 얼어붙는다.

const Data = preload("res://scripts/data.gd")


class G:
	var kind := "maiden"
	var pos := Vector2.ZERO
	var target := Vector2.ZERO   # 참가자 화면 보간용
	var vel := Vector2.ZERO
	var state := "patrol"        # patrol / chase / search
	var goal := Vector2.ZERO
	var path := PackedVector2Array()
	var path_i := 0
	var repath := 0.0
	var lost := 0.0
	var frozen := false
	var stun := 0.0
	var t := 0.0
	var face := 1.0
	var chase_id := ""           # 쫓는 플레이어 net_id
	var hunting_hidden = null    # 숨는 걸 본 플레이어


var run
var list: Array = []
var simulate := true


func clear() -> void:
	list.clear()


func spawn(kind: String, p: Vector2) -> void:
	var g := G.new()
	g.kind = kind
	g.pos = p
	g.target = p
	g.goal = p
	g.t = randf() * 10.0
	list.append(g)


func speed_of(g: G) -> float:
	var s: int = run.stage
	match g.kind:
		"maiden":
			return (128.0 + s * 3.0) if g.state == "chase" else 70.0
		"egg":
			return 46.0 + s * 2.0
		_:
			return 150.0 + s * 3.0  # 달리기(245)로 따돌릴 수 있고, 손전등으로 멈출 수 있다


## 플레이어 p를 볼 수 있는지 (손전등을 켜면 멀리서도 들킨다)
func can_see(g: G, p) -> bool:
	if not p.targetable():
		return false
	var rng := 300.0 if p.light_on else 170.0
	var d: float = g.pos.distance_to(p.pos)
	return d < rng and run.level.los(g.pos, p.pos)


func update(delta: float) -> void:
	for g in list:
		g.t += delta
		if not simulate:
			g.pos = g.pos.lerp(g.target, min(1.0, delta * 10.0))
			continue
		g.stun -= delta
		if g.stun > 0.0:
			continue
		match g.kind:
			"maiden":
				_maiden(g, delta)
			"egg":
				_egg(g, delta)
			_:
				_reaper(g, delta)
		if abs(g.vel.x) > 3.0:
			g.face = sign(g.vel.x)
		_check_hit(g)
	queue_redraw()


func _nearest(g: G, need_target := true):
	var best = null
	var bd := INF
	for p in run.players:
		if need_target and not p.targetable():
			continue
		var d: float = g.pos.distance_to(p.pos)
		if d < bd:
			bd = d
			best = p
	return best


func _follow(g: G, delta: float, spd: float) -> void:
	g.repath -= delta
	if g.repath <= 0.0 or g.path_i >= g.path.size():
		g.repath = 0.45
		g.path = run.level.path(g.pos, g.goal)
		g.path_i = 1 if g.path.size() > 1 else 0
	if g.path_i < g.path.size():
		var wp: Vector2 = g.path[g.path_i]
		var d := wp - g.pos
		if d.length() < 8.0:
			g.path_i += 1
		g.vel = d.normalized() * spd
	else:
		g.vel = (g.goal - g.pos).limit_length(spd)
	g.pos += g.vel * delta


func _maiden(g: G, delta: float) -> void:
	var seen = null
	for p in run.players:
		if can_see(g, p):
			if seen == null or g.pos.distance_to(p.pos) < g.pos.distance_to(seen.pos):
				seen = p
	if seen:
		if g.state != "chase":
			run.on_spotted(seen, g)
		g.state = "chase"
		g.chase_id = seen.net_id
		g.goal = seen.pos
		g.lost = 0.0
	elif g.state == "chase":
		g.lost += delta
		if g.lost > 3.0:
			g.state = "search"  # 마지막으로 본 곳으로 간다
	# 숨는 걸 본 경우 사물함까지 찾아온다
	if g.hunting_hidden != null:
		var hp = g.hunting_hidden
		if not hp.in_locker:
			g.hunting_hidden = null
		else:
			g.state = "chase"
			g.goal = hp.locker
			if g.pos.distance_to(hp.locker) < 34.0:
				run.on_found_hiding(hp, g)
				g.hunting_hidden = null
	# 발소리
	if g.state == "patrol":
		for p in run.players:
			if p.noise > 0.0 and p.targetable() and g.pos.distance_to(p.pos) < p.noise:
				g.state = "search"
				g.goal = p.pos
	if g.state == "search" and g.pos.distance_to(g.goal) < 20.0:
		g.state = "patrol"
		g.goal = run.level.random_floor_far(g.pos, 300.0)
	if g.state == "patrol" and (g.pos.distance_to(g.goal) < 20.0 or g.goal == g.pos):
		g.goal = run.level.random_floor_far(g.pos, 300.0)
	_follow(g, delta, speed_of(g))


func _egg(g: G, delta: float) -> void:
	var p = _nearest(g)
	if p and g.pos.distance_to(p.pos) < 700.0:
		g.vel = (p.pos - g.pos).normalized() * speed_of(g)
	else:
		g.vel = g.vel.lerp(Vector2.RIGHT.rotated(g.t * 0.3) * 30.0, delta)
	g.pos += g.vel * delta
	g.pos = g.pos.clamp(Vector2(40, 40), Vector2(run.level.w, run.level.h) * Data.T - Vector2(40, 40))


func _reaper(g: G, delta: float) -> void:
	g.frozen = false
	for p in run.players:
		if p.lights_up(g.pos):
			g.frozen = true
	if g.frozen:
		g.vel = Vector2.ZERO
		return
	var p = _nearest(g)
	if p:
		g.goal = p.pos
		g.state = "chase"
	else:
		if g.pos.distance_to(g.goal) < 20.0:
			g.goal = run.level.random_floor_far(g.pos, 300.0)
		g.state = "patrol"
	_follow(g, delta, speed_of(g) if g.state == "chase" else 80.0)


func _check_hit(g: G) -> void:
	for p in run.players:
		if p.targetable() and g.pos.distance_to(p.pos) < 26.0:
			run.on_ghost_touch(p, g)


## 공격 후 멀리 사라졌다가 다시 나타난다
func banish(g: G, stun: float) -> void:
	g.pos = run.level.random_floor_far(g.pos, 600.0)
	g.target = g.pos
	g.state = "patrol"
	g.goal = g.pos
	g.path = PackedVector2Array()
	g.stun = stun


# ------------------------------------------------------------------ 그리기 (몸체: 빛을 받아야 보인다)

func _draw() -> void:
	for g in list:
		var p: Vector2 = g.pos + Vector2(0, sin(g.t * 2.5) * 4.0)
		var shake := Vector2(randf_range(-2, 2), 0) if g.frozen else Vector2.ZERO
		p += shake
		draw_set_transform(p, 0.0, Vector2(g.face, 1.0))
		match g.kind:
			"maiden":
				_draw_maiden()
			"egg":
				_draw_egg()
			_:
				_draw_reaper(g.frozen)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_maiden() -> void:
	# 소복 (물결치는 아랫단)
	var pts := PackedVector2Array([Vector2(-14, -10), Vector2(14, -10), Vector2(18, 20)])
	for i in 6:
		pts.append(Vector2(18 - i * 7.2, 20 + (6 if i % 2 == 0 else 0)))
	pts.append(Vector2(-18, 20))
	draw_colored_polygon(pts, Color(0.95, 0.95, 0.98, 0.92))
	# 얼굴 + 긴 검은 머리
	draw_circle(Vector2(0, -20), 12.0, Color(0.9, 0.92, 0.95))
	draw_colored_polygon(PackedVector2Array([Vector2(-15, -26), Vector2(-12, -34), Vector2(0, -36), Vector2(12, -34), Vector2(15, -26), Vector2(16, 6), Vector2(8, 4), Vector2(8, -18), Vector2(-8, -18), Vector2(-8, 4), Vector2(-16, 6)]), Color(0.05, 0.04, 0.05))
	draw_line(Vector2(-12, -10), Vector2(-22, 2), Color(0.95, 0.95, 0.98, 0.9), 5.0)


func _draw_egg() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(16, 22), Vector2(-16, 22)]), Color(0.3, 0.3, 0.35, 0.9))
	var egg := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var ry := 18.0 if sin(a) < 0 else 13.0
		egg.append(Vector2(cos(a) * 13.0, -14 + sin(a) * ry))
	draw_colored_polygon(egg, Color(0.97, 0.95, 0.9))


func _draw_reaper(frozen: bool) -> void:
	var robe := Color(0.08, 0.08, 0.1)
	draw_colored_polygon(PackedVector2Array([Vector2(-12, -12), Vector2(12, -12), Vector2(20, 22), Vector2(-20, 22)]), robe)
	draw_circle(Vector2(0, -20), 10.0, Color(0.85, 0.85, 0.9))
	# 갓
	draw_rect(Rect2(-24, -30, 48, 4), robe)
	draw_rect(Rect2(-9, -42, 18, 13), robe)
	if frozen:
		draw_arc(Vector2(0, -6), 30.0, 0.0, TAU, 24, Color(0.6, 0.9, 1.0, 0.7), 3.0)
