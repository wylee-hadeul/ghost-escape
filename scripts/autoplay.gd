extends Node
## 테스트용 오토플레이 봇 + 스크린샷/로그.
## 실행: godot --path . -- --autoplay [옵션]   웹: index.html?autoplay&host=1234 / &join=1234
##   --shots=DIR --shot-every=SEC --duration=SEC --speed=N --stage=N --god --fresh
##   --host=CODE  방을 만들고 다른 플레이어를 기다렸다가 시작 (웹)
##   --join=CODE  코드로 참가 (웹)
##   --wait=SEC   방장이 참가자를 기다리는 시간 (기본 25초)

const Data = preload("res://scripts/data.gd")

var main
var shots_dir := ""
var duration := 120.0
var shot_every := 10.0
var elapsed := 0.0
var next_shot := 1.5
var next_log := 0.0
var shot_n := 0
var wait_t := 0.0
var god := false
var stage := 1
var room_code := ""
var join_code := ""
var room_wait := 25.0
var shot_keys := {}
var path := PackedVector2Array()
var path_i := 0
var repath := 0.0
var goal := Vector2.ZERO
var flee_t := 0.0
var hide_t := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var runs := 0


func configure(args: PackedStringArray) -> void:
	process_priority = -10
	for a in args:
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--duration="):
			duration = float(a.substr(11))
		elif a.begins_with("--shot-every="):
			shot_every = float(a.substr(13))
		elif a.begins_with("--speed="):
			Engine.time_scale = float(a.substr(8))
		elif a.begins_with("--stage="):
			stage = int(a.substr(8))
			main.unlocked = max(main.unlocked, stage)
		elif a.begins_with("--host="):
			room_code = a.substr(7)
		elif a.begins_with("--join="):
			join_code = a.substr(7)
		elif a.begins_with("--wait="):
			room_wait = float(a.substr(7))
		elif a == "--god":
			god = true
	main.voice.tts_enabled = false
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	main.dlog("autoplay: stage=%d god=%s host=%s join=%s" % [stage, god, room_code, join_code])


func _process(delta: float) -> void:
	var real: float = delta / max(Engine.time_scale, 0.01)
	elapsed += real
	wait_t += real
	var S = main.State
	main.joystick.bot_dir = null
	main.hud.run_key = false
	match main.state:
		S.TITLE:
			if wait_t > 0.8:
				_shot("title")
				main.set_state(S.MAIN)
				wait_t = 0.0
		S.MAIN:
			_shot("main")
			if wait_t > 0.8:
				wait_t = 0.0
				if room_code != "":
					main.menu.activate("create")
				elif join_code != "":
					main.menu.activate("join")
				else:
					main.menu.activate("solo")
		S.STAGES:
			_shot("stages")
			if wait_t > 0.6:
				main.menu.activate("stage:%d" % min(stage, main.unlocked))
				wait_t = 0.0
		S.JOIN:
			if wait_t > 0.4 and main.menu.code_input.length() < 4:
				main.menu.activate("key:" + join_code[main.menu.code_input.length()])
				wait_t = 0.0
			elif main.menu.code_input.length() == 4 and main.net.status == "idle":
				_shot("join")
				main.menu.activate("key:참가")
			elif main.net.status == "error" and wait_t > 3.0:
				main.dlog("join error: " + main.net.error)
				main.net.leave()
				main.menu.code_input = ""
				wait_t = 0.0
		S.ROOM:
			if wait_t > 1.5:
				_shot("room_%s" % ("host" if main.net.is_host else "guest"))
			if main.net.is_host and main.net.status == "hosting" and (main.roster.size() >= 2 and wait_t > 3.0 or wait_t > room_wait):
				main.menu.activate("start")
				wait_t = 0.0
		S.PLAYING:
			wait_t = 0.0
			_play(real)
		S.RESULT:
			_shot("result_%s" % ("clear" if main.result.cleared else "fail"))
			if wait_t > 2.5 and (main.result.mode == "solo" or main.net.is_host):
				runs += 1
				main.menu.activate("next" if main.result.cleared else "retry")
				wait_t = 0.0
	if elapsed >= next_log:
		next_log += 2.0
		var r = main.run
		if r.active and r.local:
			var p = r.local
			var near := INF
			for g in r.ghosts.list:
				near = min(near, g.pos.distance_to(p.pos))
			main.dlog("state=%s stage=%d mode=%s hearts=%d keys_left=%d exit=%s bat=%.0f sta=%.0f hidden=%s downed=%s players=%d ghost_near=%.0f fps=%d net=%s" % [
				S.keys()[main.state], r.stage, r.mode, p.hearts, r.items.keys_left(), r.items.exit_open, p.battery, p.stamina, p.in_locker, p.downed,
				r.players.size(), near, Engine.get_frames_per_second(), main.net.status])
		else:
			main.dlog("state=%s net=%s roster=%d" % [S.keys()[main.state], main.net.status, main.roster.size()])
	if shots_dir != "" and elapsed >= next_shot:
		next_shot += shot_every
		_screenshot("")
	if elapsed >= duration:
		main.dlog("autoplay done: unlocked=%d runs=%d" % [main.unlocked, runs])
		get_tree().quit()


func _threat(r, p):
	var worst = null
	var wd := INF
	for g in r.ghosts.list:
		var d: float = g.pos.distance_to(p.pos)
		var danger := false
		match g.kind:
			"maiden":
				danger = d < 240.0 and (g.state == "chase" or d < 140.0)
			"egg":
				danger = d < 170.0
			_:
				danger = d < 260.0 and not g.frozen
		if danger and d < wd:
			wd = d
			worst = g
	return worst


func _play(dt: float) -> void:
	var r = main.run
	var p = r.local
	if p == null or p.downed:
		return
	if r.items.exit_open:
		_shot("exit_open")
	for g in r.ghosts.list:
		if g.pos.distance_to(p.pos) < 220.0:
			_shot("ghost_" + g.kind)
	# 숨어 있으면 잠시 뒤 나온다
	if p.in_locker:
		hide_t -= dt
		_shot("hiding")
		if hide_t <= 0.0 and _threat(r, p) == null:
			p.toggle_hide()
		return
	var th = _threat(r, p)
	flee_t -= dt
	repath -= dt
	if th:
		_shot("chased")
		# 저승사자는 손전등으로 비춰 멈춘다
		if th.kind == "reaper" and p.battery > 5.0:
			p.light_on = true
			p.aim = (th.pos - p.pos).normalized()
		# 사물함이 가까우면 숨는다
		if th.kind == "maiden" and p.near_locker() != Vector2.INF and randf() < 0.5:
			p.toggle_hide()
			hide_t = 3.0
			return
		if flee_t <= 0.0:
			flee_t = 1.2
			goal = r.level.random_floor_far(th.pos, 420.0)
			repath = 0.0
		main.hud.run_key = true
	elif flee_t <= 0.0:
		goal = _objective(r, p)
	# 배터리 관리
	if th == null:
		p.light_on = p.battery > 25.0 or (p.battery > 0.0 and r.items.exit_open)
	# 길 따라가기
	if repath <= 0.0 or path_i >= path.size():
		repath = 0.6
		path = r.level.path(p.pos, goal)
		path_i = 1 if path.size() > 1 else 0
	var dir := Vector2.ZERO
	if path_i < path.size():
		var wp: Vector2 = path[path_i]
		if wp.distance_to(p.pos) < 14.0:
			path_i += 1
		dir = (wp - p.pos).normalized()
	elif goal.distance_to(p.pos) > 6.0:
		dir = (goal - p.pos).normalized()
	# 끼임 방지
	if p.pos.distance_to(last_pos) < 0.5 and dir != Vector2.ZERO:
		stuck_t += dt
		if stuck_t > 0.6:
			dir = dir.rotated(randf_range(-1.5, 1.5))
			repath = 0.0
	else:
		stuck_t = 0.0
	last_pos = p.pos
	main.joystick.bot_dir = dir


func _objective(r, p) -> Vector2:
	# 기절한 동료 살리기 > 출구 > 가장 가까운 열쇠 > 배터리
	for q in r.players:
		if q != p and q.downed:
			return q.pos
	if r.items.exit_open:
		return r.items.exit_pos()
	var best := Vector2.INF
	var bd := INF
	for it in r.items.list:
		if it.taken:
			continue
		var w := 1.0 if it.kind == "key" else (2.5 if it.kind == "battery" and p.battery < 40.0 else 99.0)
		var d: float = it.pos.distance_to(p.pos) * w
		if d < bd:
			bd = d
			best = it.pos
	return best if best != Vector2.INF else r.items.exit_pos()


func _shot(key: String) -> void:
	if shots_dir == "" or shot_keys.has(key):
		return
	shot_keys[key] = true
	_screenshot(key)


func _screenshot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	shot_n += 1
	if tag == "":
		tag = main.State.keys()[main.state].to_lower()
	var path_s := "%s/shot_%03d_s%d_%s.png" % [shots_dir, shot_n, main.run.stage, tag]
	img.save_png(path_s)
	main.dlog("screenshot " + path_s.get_file())
