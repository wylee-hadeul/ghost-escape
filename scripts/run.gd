extends Node2D
## 한 층(스테이지) 진행. 혼자 하기 / 방장(host) / 참가자(guest) 세 가지 모드.
## 방장과 혼자 하기는 귀신·아이템·피해를 계산하고, 참가자는 자기 이동만 계산해서 보낸다.

const Data = preload("res://scripts/data.gd")
const LevelScript = preload("res://scripts/level.gd")
const WallsScript = preload("res://scripts/walls.gd")
const ItemsScript = preload("res://scripts/items.gd")
const GhostScript = preload("res://scripts/ghosts.gd")
const PlayerScript = preload("res://scripts/player.gd")
const OverlayScript = preload("res://scripts/overlay.gd")

const SYNC_RATE := 1.0 / 15.0

var main
var net
var sfx
var voice
var level
var walls
var items
var ghosts
var overlay
var modulate_node: CanvasModulate
var camera: Camera2D
var radial_tex: ImageTexture
var cone_tex: ImageTexture

var mode := "solo"   # solo / host / guest
var stage := 1
var seed_v := 0
var players: Array = []
var local
var t := 0.0
var active := false
var finished := false
var god := false
var sync_t := 0.0
var heart_t := 0.0
var shake := 0.0
var explored := PackedByteArray()
var explore_t := 0.0
var last_hidden := {}
var events: Array = []    # 참가자에게 보낼 사건


func _ready() -> void:
	radial_tex = _make_radial(256)
	cone_tex = _make_cone(512)
	modulate_node = CanvasModulate.new()
	modulate_node.color = Color.WHITE
	add_child(modulate_node)
	level = LevelScript.new()
	level.run = self
	walls = WallsScript.new()
	walls.level = level
	level.walls_node = walls
	items = ItemsScript.new()
	items.run = self
	ghosts = GhostScript.new()
	ghosts.run = self
	overlay = OverlayScript.new()
	overlay.run = self
	add_child(level)
	add_child(walls)
	add_child(items)
	add_child(ghosts)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()


func dlog(s: String) -> void:
	main.dlog(s)


## 가운데가 밝은 원형 빛
func _make_radial(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## 오른쪽으로 퍼지는 손전등 원뿔 (텍스처 중심이 손전등 위치)
func _make_cone(n: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n * 0.5
	var half := 0.62
	for y in n:
		for x in n:
			var v := Vector2(x - c, y - c)
			var d: float = v.length() / c
			var a := 0.0
			if v.x > 0.0 and d <= 1.0:
				var ang: float = abs(atan2(v.y, v.x))
				var edge: float = clamp((half - ang) / 0.18, 0.0, 1.0)
				a = edge * pow(1.0 - d, 0.8)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ 시작

## roster: [{id, nick}] (첫 번째가 방장). my_id: 나의 id
func start(s: int, sd: int, m: String, roster: Array, my_id: String) -> void:
	stage = s
	seed_v = sd
	mode = m
	t = 0.0
	finished = false
	active = true
	events.clear()
	last_hidden.clear()
	level.generate(s, sd)
	modulate_node.color = level.theme.dark
	for p in players:
		p.queue_free()
	players.clear()
	var spawn: Vector2 = level.center(level.start_tile) + Vector2(level.T * 0.5, level.T * 0.5)
	for i in roster.size():
		var pl = PlayerScript.new()
		pl.run = self
		pl.net_id = roster[i].id
		pl.nick = roster[i].nick
		pl.slot = i
		pl.is_local = roster[i].id == my_id
		add_child(pl)
		pl.reset(spawn + Vector2((i % 2) * 30 - 15, (i / 2) * 30 - 15))
		players.append(pl)
		if pl.is_local:
			local = pl
	if overlay.get_parent() == null:
		add_child(overlay)
	move_child(overlay, get_child_count() - 1)  # 이름표/귀신 눈은 맨 위에
	items.setup(level)
	ghosts.clear()
	ghosts.simulate = mode != "guest"
	var counts := Data.ghost_counts(s)
	var gi := 0
	for kind in ["maiden", "egg", "reaper"]:
		for k in counts[kind]:
			var gt: Vector2i = level.ghost_tiles[gi % max(level.ghost_tiles.size(), 1)] if not level.ghost_tiles.is_empty() else level.exit_tile
			ghosts.spawn(kind, level.center(gt))
			gi += 1
	explored = PackedByteArray()
	explored.resize(level.w * level.h)
	camera.position = local.pos
	camera.reset_smoothing()
	voice.reset()
	voice.say("start", true)
	if counts.reaper > 0:
		voice.say("reaper", true)
	dlog("run start stage=%d mode=%s players=%d map=%dx%d keys=%d ghosts=%s" % [s, mode, players.size(), level.w, level.h, level.key_tiles.size(), counts])


func stop() -> void:
	active = false
	for p in players:
		p.queue_free()
	players.clear()
	ghosts.clear()
	local = null


func player_by_id(id: String):
	for p in players:
		if p.net_id == id:
			return p
	return null


func remove_player(id: String) -> void:
	var p = player_by_id(id)
	if p and not p.is_local:
		players.erase(p)
		p.queue_free()


# ------------------------------------------------------------------ 갱신

func update(delta: float, input: Vector2, want_run: bool) -> void:
	if not active:
		return
	t += delta
	for p in players:
		if p.is_local:
			p.update(delta, input, want_run)
		else:
			p.update(delta, Vector2.ZERO, false)
	ghosts.update(delta)
	if mode != "guest":
		items.update(delta)
		_team_rules(delta)
	else:
		items.update_visual(delta)
	_explore(delta)
	_heartbeat(delta)
	voice.update(delta, true)
	# 동기화
	sync_t -= delta
	if sync_t <= 0.0 and mode != "solo":
		sync_t = SYNC_RATE
		if mode == "host":
			net.send("*", _snapshot())
		else:
			net.send("*", _input_msg())
	# 카메라
	var z: float = max(1.0, min(main.view.x, main.view.y) / 720.0)
	camera.zoom = Vector2(z, z)
	camera.position = camera.position.lerp(local.pos, min(1.0, delta * 8.0))
	shake = max(shake * exp(-8.0 * delta) - delta, 0.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake


## 방장/혼자: 부활, 탈출, 실패 판정
func _team_rules(delta: float) -> void:
	if finished:
		return
	var alive := 0
	for p in players:
		if p.alive():
			alive += 1
	for p in players:
		if not p.downed:
			continue
		var helper := false
		for q in players:
			if q != p and q.alive() and not q.in_locker and q.pos.distance_to(p.pos) < 64.0:
				helper = true
		p.revive = clamp(p.revive + (delta / 2.0 if helper else -delta), 0.0, 1.0)
		if p.revive >= 1.0:
			p.downed = false
			p.hearts = 1
			p.invuln = 2.5
			p.revive = 0.0
			_event({"k": "revive", "who": p.net_id})
	if items.exit_open:
		for p in players:
			if p.alive() and p.pos.distance_to(items.exit_pos()) < 52.0:
				_finish(true)
				return
	if alive == 0:
		_finish(false)


func _finish(cleared: bool) -> void:
	if finished:
		return
	finished = true
	_event({"k": "end", "cleared": cleared, "time": t})


## 사건: 내 화면에 적용하고, 방장이면 참가자들에게도 보낸다
func _event(e: Dictionary) -> void:
	apply_event(e)
	if mode == "host":
		net.send("*", {"t": "ev", "e": e})


func apply_event(e: Dictionary) -> void:
	var who = player_by_id(str(e.get("who", "")))
	var mine: bool = who != null and who.is_local
	match e.k:
		"pickup":
			items.mark_taken(int(e.idx))
			match e.kind:
				"key":
					sfx.play("coin", -4.0)
					var left: int = items.keys_left()
					main.hud.toast("열쇠 %d개 남음" % left if left > 0 else "모든 열쇠를 찾았다! 출구로!")
					if mine:
						voice.say("key")
				"battery":
					sfx.play("pickup", -6.0)
					if mine:
						local.battery = 100.0
						local.light_on = true
						voice.say("battery")
				"talisman":
					sfx.play("levelup", -6.0)
					if mine:
						voice.say("talisman", true)
		"exit":
			items.open_exit()
			sfx.play("levelup", -2.0, 0.8)
			voice.say("allkeys", true)
		"hurt":
			sfx.play("scream", -2.0)
			if mine:
				shake = 14.0
				main.hud.flash()
				voice.say("hurt", true)
		"down":
			sfx.play("roar", -6.0, 1.4)
			main.hud.toast(("%s 기절! 옆에 서서 살려주세요" % who.nick) if who and not mine else "기절했다... 동료가 살려줄 때까지 기다려!")
		"revive":
			sfx.play("levelup", -6.0, 1.3)
			main.hud.toast("%s 부활!" % (who.nick if who else ""))
		"blocked":
			sfx.play("zap", -4.0)
			if mine:
				voice.say("blocked", true)
				shake = 6.0
		"found":
			if mine:
				local.in_locker = false
				local.pos = local.locker + Vector2(0, 30)
		"spotted":
			if mine:
				voice.say("spotted")
		"end":
			finished = true
			main.on_run_finished(bool(e.cleared), float(e.time))


# ------------------------------------------------------------------ 게임 규칙 (방장/혼자)

func on_pickup(kind: String, idx: int, p) -> void:
	_event({"k": "pickup", "kind": kind, "idx": idx, "who": p.net_id})
	if kind == "talisman":
		p.talismans += 1
	if kind == "key" and items.keys_left() == 0:
		_event({"k": "exit"})
	dlog("pickup %s by %s (keys left %d)" % [kind, p.nick, items.keys_left()])


func on_hide(p) -> void:
	# 쫓던 처녀귀신이 가까이서 봤다면 사물함까지 찾아온다
	if mode == "guest":
		return
	for g in ghosts.list:
		if g.kind == "maiden" and g.state == "chase" and g.pos.distance_to(p.pos) < 150.0 and level.los(g.pos, p.pos):
			g.hunting_hidden = p
	if p.is_local:
		voice.say("hide")


func on_found_hiding(p, g) -> void:
	p.in_locker = false
	p.pos = p.locker + Vector2(0, 30)
	_event({"k": "found", "who": p.net_id})
	on_ghost_touch(p, g)


func on_spotted(p, _g) -> void:
	if p.is_local:
		voice.say("spotted")
	elif mode == "host":
		net.send(p.net_id, {"t": "ev", "e": {"k": "spotted", "who": p.net_id}})


func on_ghost_touch(p, g) -> void:
	if p.invuln > 0.0 or p.downed:
		return
	if p.talismans > 0:
		p.talismans -= 1
		p.invuln = 1.5
		ghosts.banish(g, 4.0)
		_event({"k": "blocked", "who": p.net_id})
		dlog("talisman blocked %s for %s" % [g.kind, p.nick])
		return
	if god:
		p.invuln = 1.0
		return
	p.hearts -= 1
	p.invuln = 2.0
	p.hurt_t = 0.4
	ghosts.banish(g, 2.5)
	_event({"k": "hurt", "who": p.net_id})
	dlog("%s hit by %s hearts=%d" % [p.nick, g.kind, p.hearts])
	if p.hearts <= 0:
		p.downed = true
		p.in_locker = false
		_event({"k": "down", "who": p.net_id})


# ------------------------------------------------------------------ 동기화

func _snapshot() -> Dictionary:
	var ps: Array = []
	for p in players:
		ps.append([p.net_id, int(p.pos.x), int(p.pos.y), snappedf(p.aim.x, 0.01), snappedf(p.aim.y, 0.01), int(p.light_on), int(p.in_locker),
			p.hearts, int(p.downed), p.talismans, snappedf(p.revive, 0.01), int(p.face), int(p.escaped)])
	var gs: Array = []
	for g in ghosts.list:
		gs.append([int(g.pos.x), int(g.pos.y), int(g.frozen), int(g.face)])
	return {"t": "s", "p": ps, "g": gs, "it": items.taken_mask(), "e": int(items.exit_open)}


func apply_snapshot(d: Dictionary) -> void:
	if not active:
		return
	for row in d.p:
		var p = player_by_id(str(row[0]))
		if p == null:
			continue
		p.hearts = int(row[7])
		p.downed = bool(row[8])
		p.talismans = int(row[9])
		p.revive = float(row[10])
		p.escaped = bool(row[12])
		if not p.is_local:
			p.target = Vector2(row[1], row[2])
			p.aim = Vector2(row[3], row[4])
			p.light_on = bool(row[5])
			p.in_locker = bool(row[6])
			p.face = float(row[11])
	for i in min(d.g.size(), ghosts.list.size()):
		var g = ghosts.list[i]
		var row: Array = d.g[i]
		g.target = Vector2(row[0], row[1])
		g.frozen = bool(row[2])
		g.face = float(row[3])
	items.apply_mask(str(d.it))
	if bool(d.e) and not items.exit_open:
		items.open_exit()


func _input_msg() -> Dictionary:
	var p = local
	return {"t": "i", "x": int(p.pos.x), "y": int(p.pos.y), "ax": snappedf(p.aim.x, 0.01), "ay": snappedf(p.aim.y, 0.01),
		"l": int(p.light_on), "h": int(p.in_locker), "lx": int(p.locker.x), "ly": int(p.locker.y), "n": int(p.noise), "f": int(p.face)}


## 방장: 참가자 입력 반영
func apply_input(from: String, d: Dictionary) -> void:
	var p = player_by_id(from)
	if p == null or p.is_local:
		return
	if not p.downed:
		p.target = Vector2(d.x, d.y)
	p.aim = Vector2(d.ax, d.ay)
	p.light_on = bool(d.l)
	var was: bool = p.in_locker
	p.in_locker = bool(d.h)
	p.locker = Vector2(d.lx, d.ly)
	p.noise = float(d.n)
	p.face = float(d.f)
	if p.in_locker and not was:
		on_hide(p)


# ------------------------------------------------------------------ 탐험/심장박동

func _explore(delta: float) -> void:
	explore_t -= delta
	if explore_t > 0.0:
		return
	explore_t = 0.2
	var c: Vector2i = level.tile_of(local.pos)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var tt := c + Vector2i(dx, dy)
			if tt.x >= 0 and tt.y >= 0 and tt.x < level.w and tt.y < level.h:
				explored[tt.y * level.w + tt.x] = 1


func _heartbeat(delta: float) -> void:
	var nearest := INF
	for g in ghosts.list:
		nearest = min(nearest, g.pos.distance_to(local.pos))
	heart_t -= delta
	if nearest < 420.0 and heart_t <= 0.0 and not local.downed:
		var k: float = clamp(1.0 - nearest / 420.0, 0.0, 1.0)
		heart_t = lerp(1.1, 0.32, k)
		sfx.play("heart", lerp(-16.0, -2.0, k))
	main.hud.danger = clamp(1.0 - nearest / 420.0, 0.0, 1.0)
