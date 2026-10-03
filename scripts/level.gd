extends Node2D
## 층(스테이지) 생성: 2칸 폭 복도 미로 + 순환 통로 + 교실, 열쇠/사물함/아이템/귀신 위치, A* 길찾기, 벽 그림자.

const Data = preload("res://scripts/data.gd")
const T := Data.T

var run
var w := 0          # 타일 수
var h := 0
var grid := PackedByteArray()   # 1 = 벽
var astar := AStarGrid2D.new()
var theme: Dictionary
var start_tile := Vector2i.ZERO
var exit_tile := Vector2i.ZERO
var key_tiles: Array = []
var locker_tiles: Array = []
var battery_tiles: Array = []
var talisman_tiles: Array = []
var ghost_tiles: Array = []
var decor: Array = []           # {tile, kind}
var occluders: Array = []
var rng := RandomNumberGenerator.new()
var walls_node: Node2D


# ------------------------------------------------------------------ 생성

func generate(stage: int, seed_v: int) -> void:
	rng.seed = seed_v
	theme = Data.theme(stage)
	var ms := Data.maze_size(stage)
	w = ms.x * 3 + 1
	h = ms.y * 3 + 1
	grid = PackedByteArray()
	grid.resize(w * h)
	grid.fill(1)
	# 칸 내부(2x2) 바닥
	for cy in ms.y:
		for cx in ms.x:
			_carve_cell(cx, cy)
	# 미로 (재귀 백트래킹)
	var visited := {}
	var stack: Array = [Vector2i(0, ms.y - 1)]
	visited[stack[0]] = true
	while not stack.is_empty():
		var c: Vector2i = stack[-1]
		var nbrs: Array = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < ms.x and n.y < ms.y and not visited.has(n):
				nbrs.append(n)
		if nbrs.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = nbrs[rng.randi() % nbrs.size()]
		_carve_between(c, n)
		visited[n] = true
		stack.append(n)
	# 순환 통로: 막다른 길만 있으면 귀신을 피할 수 없다
	for cy in ms.y:
		for cx in ms.x:
			if cx + 1 < ms.x and rng.randf() < 0.16:
				_carve_between(Vector2i(cx, cy), Vector2i(cx + 1, cy))
			if cy + 1 < ms.y and rng.randf() < 0.16:
				_carve_between(Vector2i(cx, cy), Vector2i(cx, cy + 1))
	# 교실 (2x2 칸을 하나로)
	var rooms: Array = []
	for i in 2 + stage / 3:
		var rc := Vector2i(rng.randi_range(0, ms.x - 2), rng.randi_range(0, ms.y - 2))
		for dx in 2:
			for dy in 2:
				var a := rc + Vector2i(dx, dy)
				if dx == 0:
					_carve_between(a, a + Vector2i(1, 0))
				if dy == 0:
					_carve_between(a, a + Vector2i(0, 1))
		var center := _cell_tile(rc) + Vector2i(2, 2)
		grid[center.y * w + center.x] = 0
		rooms.append(rc)
	# 거리 계산 (시작점 기준 BFS, 칸 단위)
	var start_cell := Vector2i(0, ms.y - 1)
	start_tile = _cell_tile(start_cell)
	var dist := _bfs(start_tile)
	var cells: Array = []
	for cy in ms.y:
		for cx in ms.x:
			var tt := _cell_tile(Vector2i(cx, cy))
			cells.append({"c": Vector2i(cx, cy), "t": tt, "d": dist.get(tt, 0), "dead": _is_dead_end(Vector2i(cx, cy))})
	cells.sort_custom(func(a, b): return a.d > b.d or (a.d == b.d and (a.c.y * 100 + a.c.x) < (b.c.y * 100 + b.c.x)))
	var maxd: int = cells[0].d
	exit_tile = cells[0].t
	var used := {cells[0].c: true, start_cell: true}
	# 열쇠: 멀고 막다른 곳 위주로 고르게 흩어 놓는다
	key_tiles.clear()
	var want := Data.key_count(stage)
	var cand: Array = cells.filter(func(e): return e.d > maxd * 0.3)
	_shuffle(cand)
	cand.sort_custom(func(a, b): return int(a.dead) > int(b.dead))
	for e in cand:
		if key_tiles.size() >= want:
			break
		var ok := true
		for k in key_tiles:
			if (k as Vector2i).distance_to(e.t) < 6.0:
				ok = false
		if ok and not used.has(e.c):
			key_tiles.append(e.t + Vector2i(rng.randi_range(0, 1), rng.randi_range(0, 1)))
			used[e.c] = true
	for e in cand:
		if key_tiles.size() >= want:
			break
		if not used.has(e.c):
			key_tiles.append(e.t)
			used[e.c] = true
	# 아이템/사물함/귀신
	battery_tiles.clear()
	talisman_tiles.clear()
	locker_tiles.clear()
	ghost_tiles.clear()
	var rest: Array = cells.filter(func(e): return not used.has(e.c))
	_shuffle(rest)
	var nb := 2 + stage / 2
	var nt := 1 + stage / 3
	for e in rest:
		if battery_tiles.size() < nb:
			battery_tiles.append(e.t + Vector2i(1, 0))
		elif talisman_tiles.size() < nt:
			talisman_tiles.append(e.t + Vector2i(0, 1))
	for e in rest:
		if rng.randf() < 0.35:
			var lt := _locker_spot(e.t)
			if lt.x >= 0:
				locker_tiles.append(lt)
	var far: Array = cells.filter(func(e): return e.d > maxd * 0.45)
	_shuffle(far)
	for e in far:
		ghost_tiles.append(e.t + Vector2i(1, 1))
	# 장식 (교실 책상 등, 충돌 없음)
	decor.clear()
	for rc in rooms:
		var t0 := _cell_tile(rc)
		for dx in [0, 2, 3]:
			for dy in [0, 3]:
				if rng.randf() < 0.7:
					decor.append({"tile": t0 + Vector2i(dx, dy), "kind": rng.randi() % 3})
	_build_astar()
	_build_occluders()
	queue_redraw()
	walls_node.queue_redraw()


## 시드 rng로 섞기 (Array.shuffle은 전역 랜덤이라 기기마다 결과가 달라진다)
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _cell_tile(c: Vector2i) -> Vector2i:
	return Vector2i(1 + c.x * 3, 1 + c.y * 3)


func _carve_cell(cx: int, cy: int) -> void:
	var t := _cell_tile(Vector2i(cx, cy))
	for dx in 2:
		for dy in 2:
			grid[(t.y + dy) * w + t.x + dx] = 0


func _carve_between(a: Vector2i, b: Vector2i) -> void:
	var ta := _cell_tile(a)
	if b.x > a.x:
		grid[ta.y * w + ta.x + 2] = 0
		grid[(ta.y + 1) * w + ta.x + 2] = 0
	elif b.x < a.x:
		grid[ta.y * w + ta.x - 1] = 0
		grid[(ta.y + 1) * w + ta.x - 1] = 0
	elif b.y > a.y:
		grid[(ta.y + 2) * w + ta.x] = 0
		grid[(ta.y + 2) * w + ta.x + 1] = 0
	else:
		grid[(ta.y - 1) * w + ta.x] = 0
		grid[(ta.y - 1) * w + ta.x + 1] = 0


func _is_dead_end(c: Vector2i) -> bool:
	var t := _cell_tile(c)
	var open := 0
	if not is_wall(t + Vector2i(2, 0)):
		open += 1
	if not is_wall(t + Vector2i(-1, 0)):
		open += 1
	if not is_wall(t + Vector2i(0, 2)):
		open += 1
	if not is_wall(t + Vector2i(0, -1)):
		open += 1
	return open <= 1


## 벽에 붙은 바닥 타일 (사물함 자리)
func _locker_spot(t: Vector2i) -> Vector2i:
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var p: Vector2i = t + o
		if is_wall(p + Vector2i(0, -1)) and not locker_tiles.has(p):
			return p
	return Vector2i(-1, -1)


func _bfs(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array = [from]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not is_wall(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist


func _build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(T, T)
	astar.offset = Vector2(T * 0.5, T * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in h:
		for x in w:
			if grid[y * w + x] == 1:
				astar.set_point_solid(Vector2i(x, y), true)


## 벽을 큰 직사각형으로 합쳐서 그림자용 차폐물을 만든다
func _build_occluders() -> void:
	for o in occluders:
		o.queue_free()
	occluders.clear()
	var done := PackedByteArray()
	done.resize(w * h)
	for y in h:
		var x := 0
		while x < w:
			if grid[y * w + x] == 1 and done[y * w + x] == 0:
				var x2 := x
				while x2 + 1 < w and grid[y * w + x2 + 1] == 1 and done[y * w + x2 + 1] == 0:
					x2 += 1
				var y2 := y
				var can := true
				while can and y2 + 1 < h:
					for xx in range(x, x2 + 1):
						if grid[(y2 + 1) * w + xx] == 0 or done[(y2 + 1) * w + xx] == 1:
							can = false
							break
					if can:
						y2 += 1
				for yy in range(y, y2 + 1):
					for xx in range(x, x2 + 1):
						done[yy * w + xx] = 1
				var occ := LightOccluder2D.new()
				var poly := OccluderPolygon2D.new()
				var r := Rect2(x * T, y * T, (x2 - x + 1) * T, (y2 - y + 1) * T)
				poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
				occ.occluder = poly
				add_child(occ)
				occluders.append(occ)
				x = x2 + 1
			else:
				x += 1


# ------------------------------------------------------------------ 질의

func is_wall(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return true
	return grid[t.y * w + t.x] == 1


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func center(t: Vector2i) -> Vector2:
	return Vector2(t.x * T + T * 0.5, t.y * T + T * 0.5)


func wall_at(p: Vector2) -> bool:
	return is_wall(tile_of(p))


## 원이 벽과 겹치는지
func circle_hits(p: Vector2, r: float) -> bool:
	var t0 := tile_of(p - Vector2(r, r))
	var t1 := tile_of(p + Vector2(r, r))
	for ty in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			if is_wall(Vector2i(tx, ty)):
				var rect := Rect2(tx * T, ty * T, T, T)
				var q := Vector2(clamp(p.x, rect.position.x, rect.end.x), clamp(p.y, rect.position.y, rect.end.y))
				if q.distance_squared_to(p) < r * r:
					return true
	return false


## 벽에 막히지 않고 보이는지
func los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var n := int(d.length() / 12.0) + 1
	for i in range(1, n):
		if wall_at(a + d * (float(i) / n)):
			return false
	return true


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := tile_of(from)
	var b := tile_of(to)
	if is_wall(a) or is_wall(b):
		return PackedVector2Array()
	return astar.get_point_path(a, b)


func random_floor_far(from: Vector2, min_d: float) -> Vector2:
	for i in 60:
		var t := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(1, h - 2))
		if not is_wall(t) and center(t).distance_to(from) > min_d:
			return center(t)
	return center(exit_tile)


# ------------------------------------------------------------------ 그리기 (바닥: 조명을 받는다)

func _draw() -> void:
	var f1: Color = theme.floor
	var f2: Color = theme.floor2
	for y in h:
		for x in w:
			if grid[y * w + x] == 0:
				var r := Rect2(x * T, y * T, T, T)
				draw_rect(r, f1 if (x + y) % 2 == 0 else f2)
				draw_line(r.position, Vector2(r.end.x, r.position.y), f2.darkened(0.2), 1.0)
	for d in decor:
		var p := center(d.tile)
		match d.kind:
			0:  # 책상
				draw_rect(Rect2(p - Vector2(18, 12), Vector2(36, 22)), Color("8d6e4a"))
				draw_rect(Rect2(p - Vector2(18, 12), Vector2(36, 5)), Color("a6845c"))
			1:  # 의자
				draw_rect(Rect2(p - Vector2(10, 8), Vector2(20, 16)), Color("6d5236"))
			_:  # 흩어진 종이
				draw_rect(Rect2(p - Vector2(10, 6), Vector2(14, 10)), Color(0.9, 0.9, 0.85, 0.8))
				draw_rect(Rect2(p + Vector2(4, 2), Vector2(10, 8)), Color(0.85, 0.85, 0.8, 0.7))
	# 출구 계단
	var e := center(exit_tile) + Vector2(T * 0.5, T * 0.5)
	for i in 4:
		draw_rect(Rect2(e - Vector2(40, 40) + Vector2(0, i * 20), Vector2(80, 20)), Color("5b5b66").lightened(i * 0.08))
	draw_rect(Rect2(e - Vector2(40, 40), Vector2(80, 80)), Color(0, 0, 0, 0.3), false, 3.0)
