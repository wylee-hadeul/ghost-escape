extends Node2D
## 게임 흐름: 타이틀 → 메인(혼자/방 만들기/코드로 참가) → 대기실 → 플레이 → 결과. 네트워크 메시지 처리와 저장.

const Data = preload("res://scripts/data.gd")
const RunScript = preload("res://scripts/run.gd")
const HudScript = preload("res://scripts/hud.gd")
const MenuScript = preload("res://scripts/menu.gd")
const JoystickScript = preload("res://scripts/joystick.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const VoiceScript = preload("res://scripts/voice.gd")
const NetScript = preload("res://scripts/net.gd")
const AutoplayScript = preload("res://scripts/autoplay.gd")

enum State { TITLE, MAIN, STAGES, JOIN, ROOM, PLAYING, PAUSE, RESULT }

var save_path := "user://save.cfg"
var state := State.TITLE
var view := Vector2(720, 1280)
var time := 0.0

var run
var hud
var menu
var joystick
var sfx
var voice
var net
var autoplay

var unlocked := 1
var best := {}
var roster: Array = []      # [{id, nick}] 첫 번째가 방장
var room_stage := 1
var host_id := ""
var result := {}


func _ready() -> void:
	ThemeDB.fallback_font = load("res://fonts/Jua-Regular.ttf")
	randomize()
	_setup_input()
	var ap_args = _autoplay_args()
	if ap_args != null:
		save_path = "user://save_autoplay.cfg"
		if ap_args.has("--fresh"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	sfx = SfxScript.new()
	add_child(sfx)
	voice = VoiceScript.new()
	add_child(voice)
	net = NetScript.new()
	add_child(net)
	net.joined.connect(_on_net_joined)
	net.left.connect(_on_net_left)
	net.received.connect(_on_net_msg)
	_load()
	view = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): view = get_viewport_rect().size)
	run = RunScript.new()
	run.main = self
	run.net = net
	run.sfx = sfx
	run.voice = voice
	add_child(run)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.main = self
	layer.add_child(hud)
	joystick = JoystickScript.new()
	joystick.main = self
	layer.add_child(joystick)
	menu = MenuScript.new()
	menu.main = self
	layer.add_child(menu)
	# 메뉴 배경용으로 1스테이지를 미리 깔아둔다
	run.level.generate(1, 7)
	run.modulate_node.color = Color(0.25, 0.25, 0.35)
	if ap_args != null:
		autoplay = AutoplayScript.new()
		autoplay.main = self
		add_child(autoplay)
		autoplay.configure(ap_args)
	set_state(State.TITLE)


func _autoplay_args():
	var args := OS.get_cmdline_user_args()
	var on := args.has("--autoplay")
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if typeof(q) == TYPE_STRING and q.contains("autoplay"):
			on = true
			for part in q.trim_prefix("?").split("&"):
				if part != "autoplay" and part != "":
					args.append("--" + part)
	return args if on else null


func dlog(msg: String) -> void:
	var t: float = run.t if run else 0.0
	print("[%7.2f|%6.1f] %s" % [time, t, msg])


func _setup_input() -> void:
	var map := {"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "up": [KEY_UP, KEY_W], "down": [KEY_DOWN, KEY_S]}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


func try_fullscreen(is_touch: bool) -> void:
	if is_touch and OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){var d=document.documentElement;if(d.requestFullscreen){d.requestFullscreen().catch(function(){});}})();", true)


func set_state(s: State) -> void:
	state = s
	menu.open()


func my_id() -> String:
	return net.my_id if net.active() else "local"


# ------------------------------------------------------------------ 혼자 하기

func start_solo(s: int) -> void:
	_start_run(s, randi() % 1000000, "solo", [{"id": "local", "nick": "나"}], "local")


func _start_run(s: int, sd: int, mode: String, rs: Array, me: String) -> void:
	run.god = autoplay != null and autoplay.god
	run.start(s, sd, mode, rs, me)
	joystick.reset()
	hud.run_finger = -1
	set_state(State.PLAYING)
	hud.toast("열쇠 %d개를 찾아 탈출하라!" % run.level.key_tiles.size())


# ------------------------------------------------------------------ 같이 하기

func create_room() -> void:
	var code := "%04d" % (randi() % 10000)
	if autoplay and autoplay.room_code != "":
		code = autoplay.room_code
	net.host(code)
	roster = []
	room_stage = unlocked
	set_state(State.ROOM)
	dlog("create room %s" % code)


func join_room(code: String) -> void:
	net.join(code)
	roster = []
	dlog("join room %s" % code)


func leave_room() -> void:
	net.leave()
	run.stop()
	roster = []
	set_state(State.MAIN)


func set_room_stage(s: int) -> void:
	room_stage = clampi(s, 1, unlocked)
	_broadcast_roster()


func host_start(s: int) -> void:
	if roster.is_empty():
		roster = [{"id": net.my_id, "nick": "플레이어 1"}]
	room_stage = s
	var sd := randi() % 1000000
	net.send("*", {"t": "start", "s": s, "seed": sd, "roster": roster})
	_start_run(s, sd, "host", roster, net.my_id)


func _broadcast_roster() -> void:
	if net.is_host:
		net.send("*", {"t": "roster", "list": roster, "stage": room_stage})


func net_error_text() -> String:
	match net.error:
		"unavailable-id":
			return "이미 사용 중인 코드예요. 다시 만들어 주세요"
		"peer-unavailable":
			return "방을 찾을 수 없어요. 코드를 확인하세요"
		"timeout":
			return "연결 시간이 초과됐어요"
		"no-peerjs":
			return "네트워크를 불러오지 못했어요"
		"network", "server-error", "socket-error":
			return "중계 서버에 연결할 수 없어요"
	return "연결 오류 (%s)" % net.error


func _process(delta: float) -> void:
	delta = min(delta, 0.05)
	time += delta
	# 방장: 방을 연 직후 자기 자신을 목록에 넣는다
	if net.is_host and net.status == "hosting" and roster.is_empty():
		roster = [{"id": net.my_id, "nick": "플레이어 1"}]
	match state:
		State.PLAYING:
			run.update(delta, joystick.direction(), hud.want_run())
		State.PAUSE:
			if run.mode != "solo":
				run.update(delta, Vector2.ZERO, false)  # 같이 할 땐 멈추지 않는다


func _on_net_joined(from: String) -> void:
	if net.is_host:
		dlog("peer connected %s" % from)
	else:
		host_id = from
		net.send(from, {"t": "hello"})
		set_state(State.ROOM)
		dlog("connected to host")


func _on_net_left(from: String) -> void:
	if net.is_host:
		for i in range(roster.size() - 1, -1, -1):
			if roster[i].id == from:
				menu.toast("%s 님이 나갔어요" % roster[i].nick)
				roster.remove_at(i)
		run.remove_player(from)
		_broadcast_roster()
	elif from == host_id:
		leave_room()
		menu.toast("방장과 연결이 끊어졌어요")


func _on_net_msg(from: String, d: Dictionary) -> void:
	var t: String = str(d.get("t", ""))
	if net.is_host:
		match t:
			"hello":
				if roster.size() < 4 and state == State.ROOM:
					roster.append({"id": from, "nick": "플레이어 %d" % (roster.size() + 1)})
					_broadcast_roster()
					sfx.play("levelup", -8.0)
			"i":
				run.apply_input(from, d)
		return
	match t:
		"roster":
			roster = d.list
			room_stage = int(d.stage)
		"start":
			roster = d.roster
			_start_run(int(d.s), int(d.seed), "guest", roster, net.my_id)
		"s":
			run.apply_snapshot(d)
		"ev":
			run.apply_event(d.e)
		"room":
			run.stop()
			set_state(State.ROOM)
		"full":
			menu.toast("방이 가득 찼어요 (최대 4명)")
			leave_room()


# ------------------------------------------------------------------ 결과/일시정지

func on_run_finished(cleared: bool, t: float) -> void:
	var s: int = run.stage
	var unlock := false
	if cleared:
		unlock = s + 1 > unlocked
		unlocked = max(unlocked, s + 1)
		best[str(s)] = min(float(best.get(str(s), 99999.0)), t)
		voice.say("clear", true)
		sfx.play("levelup", 0.0, 0.7)
	result = {"cleared": cleared, "stage": s, "time": t, "mode": run.mode, "players": run.players.size(), "unlock": unlock}
	save_game()
	set_state(State.RESULT)
	dlog("RESULT cleared=%s stage=%d time=%.1f mode=%s players=%d" % [cleared, s, t, run.mode, run.players.size()])


func continue_after(s: int) -> void:
	if result.mode == "solo":
		start_solo(clampi(s, 1, unlocked))
	else:
		host_start(clampi(s, 1, unlocked))


func back_from_result() -> void:
	run.stop()
	if result.mode == "solo":
		set_state(State.STAGES)
	else:
		net.send("*", {"t": "room"})
		set_state(State.ROOM)


func pause_action(id: String) -> void:
	if id == "resume":
		state = State.PLAYING
	elif run.mode == "solo":
		run.stop()
		set_state(State.STAGES)
	else:
		leave_room()


# ------------------------------------------------------------------ 저장

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		unlocked = int(cfg.get_value("save", "unlocked", 1))
		best = cfg.get_value("save", "best", {})
		voice.tts_enabled = bool(cfg.get_value("save", "voice", true))
	room_stage = unlocked


func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "unlocked", unlocked)
	cfg.set_value("save", "best", best)
	cfg.set_value("save", "voice", voice.tts_enabled)
	cfg.save(save_path)
