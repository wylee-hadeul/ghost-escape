extends Node2D
## 메뉴 화면: 타이틀, 메인(혼자/방 만들기/코드로 참가), 스테이지 선택, 코드 입력(숫자 키패드), 방(대기실), 결과.

const Data = preload("res://scripts/data.gd")

const GREEN := Color("2e7d32")
const GREY := Color("455a64")
const RED := Color("b71c1c")
const BLUE := Color("1565c0")
const PURPLE := Color("6a1b9a")

var main
var font: Font
var box := StyleBoxFlat.new()
var open_t := 0.0
var toast_text := ""
var toast_t := 0.0
var code_input := ""


func _ready() -> void:
	font = ThemeDB.fallback_font
	box.set_corner_radius_all(18)
	box.set_border_width_all(4)
	box.shadow_size = 10
	box.shadow_color = Color(0, 0, 0, 0.5)


func open() -> void:
	open_t = 0.0


func toast(s: String) -> void:
	toast_text = s
	toast_t = 2.6


func active() -> bool:
	return main.state in [main.State.TITLE, main.State.MAIN, main.State.STAGES, main.State.JOIN, main.State.ROOM, main.State.RESULT]


func _process(delta: float) -> void:
	open_t += delta
	toast_t -= delta
	queue_redraw()


# ------------------------------------------------------------------ 레이아웃

func layout() -> Array:
	var v: Vector2 = main.view
	var cx := v.x * 0.5
	var out: Array = []
	var S = main.State
	match main.state:
		S.MAIN:
			var web: bool = main.net.available
			out.append({"id": "solo", "rect": Rect2(cx - 240, 620, 480, 116), "label": "혼자 하기", "col": GREEN, "enabled": true})
			out.append({"id": "create", "rect": Rect2(cx - 240, 760, 480, 116), "label": "방 만들기", "col": BLUE, "enabled": web})
			out.append({"id": "join", "rect": Rect2(cx - 240, 900, 480, 116), "label": "코드로 참가", "col": PURPLE, "enabled": web})
			out.append({"id": "voice", "rect": Rect2(cx - 140, 1050, 280, 80), "label": "음성 켜짐" if main.voice.tts_enabled else "음성 꺼짐", "col": GREY, "size": 28, "enabled": true})
		S.STAGES:
			out.append({"id": "back", "rect": Rect2(24, 40, 150, 72), "label": "뒤로", "col": GREY, "enabled": true})
			var cols := 3
			var bw: float = min(200.0, (v.x - 80.0) / cols - 16.0)
			var n: int = max(main.unlocked, 1) + 1
			for i in n:
				var s := i + 1
				var r := Rect2(cx - (cols * bw + (cols - 1) * 16.0) * 0.5 + (i % cols) * (bw + 16.0), 260.0 + (i / cols) * 150.0, bw, 130)
				out.append({"id": "stage:%d" % s, "rect": r, "kind": "stage", "s": s, "enabled": s <= main.unlocked})
		S.JOIN:
			out.append({"id": "back", "rect": Rect2(24, 40, 150, 72), "label": "뒤로", "col": GREY, "enabled": true})
			var kw := 150.0
			var kh := 110.0
			var x0 := cx - (kw * 3 + 32) * 0.5
			var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "지우기", "0", "참가"]
			for i in keys.size():
				var k: String = keys[i]
				var col := GREY
				if k == "참가":
					col = GREEN
				elif k == "지우기":
					col = RED
				var en := true
				if k == "참가":
					en = code_input.length() == 4 and main.net.status != "connecting"
				out.append({"id": "key:" + k, "rect": Rect2(x0 + (i % 3) * (kw + 16), 520.0 + (i / 3) * (kh + 16), kw, kh), "label": k, "col": col, "size": 40 if k.length() == 1 else 30, "enabled": en})
		S.ROOM:
			out.append({"id": "leave", "rect": Rect2(24, 40, 170, 72), "label": "나가기", "col": RED, "enabled": true})
			if main.net.is_host:
				out.append({"id": "rs_prev", "rect": Rect2(cx - 250, 850, 90, 90), "label": "<", "col": GREY, "size": 44, "enabled": main.room_stage > 1})
				out.append({"id": "rs_next", "rect": Rect2(cx + 160, 850, 90, 90), "label": ">", "col": GREY, "size": 44, "enabled": main.room_stage < main.unlocked})
				out.append({"id": "start", "rect": Rect2(cx - 240, 990, 480, 120), "label": "시작!", "col": GREEN, "size": 50, "enabled": main.net.status == "hosting"})
		S.RESULT:
			var r: Dictionary = main.result
			var multi: bool = r.mode != "solo"
			if not multi or main.net.is_host:
				out.append({"id": "next" if r.cleared else "retry", "rect": Rect2(cx - 230, v.y * 0.5 + 220, 460, 110), "label": "다음 스테이지" if r.cleared else "다시 도전", "col": GREEN, "enabled": open_t > 1.0})
				out.append({"id": "to_menu", "rect": Rect2(cx - 230, v.y * 0.5 + 350, 460, 100), "label": "대기실로" if multi else "메뉴로", "col": GREY, "enabled": open_t > 1.0})
	return out


# ------------------------------------------------------------------ 입력

func _input(event: InputEvent) -> void:
	if not active() or open_t < 0.25:
		return
	if main.state == main.State.TITLE:
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed and not event.echo):
			main.try_fullscreen(event is InputEventScreenTouch)
			main.set_state(main.State.MAIN)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.pressed:
		for b in layout():
			if b.enabled and b.rect.has_point(event.position):
				activate(b.id)
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and event.pressed and not event.echo and main.state == main.State.JOIN:
		var k: int = event.physical_keycode
		if k >= KEY_0 and k <= KEY_9:
			activate("key:%d" % (k - KEY_0))
		elif k == KEY_BACKSPACE:
			activate("key:지우기")
		elif k == KEY_ENTER:
			activate("key:참가")


func activate(id: String) -> void:
	main.dlog("menu: " + id)
	main.sfx.play("pickup", -8.0, 0.7)
	match id:
		"solo":
			main.set_state(main.State.STAGES)
		"create":
			main.create_room()
		"join":
			code_input = ""
			main.set_state(main.State.JOIN)
		"voice":
			main.voice.tts_enabled = not main.voice.tts_enabled
			main.save_game()
		"back":
			main.set_state(main.State.MAIN)
		"leave":
			main.leave_room()
		"rs_prev":
			main.set_room_stage(main.room_stage - 1)
		"rs_next":
			main.set_room_stage(main.room_stage + 1)
		"start":
			main.host_start(main.room_stage)
		"next":
			main.continue_after(main.result.stage + 1)
		"retry":
			main.continue_after(main.result.stage)
		"to_menu":
			main.back_from_result()
		_:
			if id.begins_with("stage:"):
				main.start_solo(int(id.substr(6)))
			elif id.begins_with("key:"):
				var k := id.substr(4)
				if k == "지우기":
					code_input = code_input.substr(0, max(code_input.length() - 1, 0))
				elif k == "참가":
					main.join_room(code_input)
				elif code_input.length() < 4:
					code_input += k


# ------------------------------------------------------------------ 그리기

func _t(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 8) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2, border: Color, bg: Color) -> void:
	box.bg_color = bg
	box.border_color = border
	box.draw(get_canvas_item(), r)


func _draw() -> void:
	if not active():
		return
	var v: Vector2 = main.view
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.02, 0.02, 0.05, 0.75 if main.state != main.State.RESULT else 0.6))
	match main.state:
		main.State.TITLE:
			_draw_title(v)
		main.State.MAIN:
			_draw_logo(v, 300)
			if not main.net.available:
				_t(Vector2(v.x * 0.5, 1180), "같이 하기는 웹(브라우저)에서만 가능합니다", 22, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 0)
		main.State.STAGES:
			_t(Vector2(v.x * 0.5, 170), "스테이지 선택", 54, Color("e0e0ff"), HORIZONTAL_ALIGNMENT_CENTER, 10)
		main.State.JOIN:
			_draw_join(v)
		main.State.ROOM:
			_draw_room(v)
		main.State.RESULT:
			_draw_result(v)
	for b in layout():
		if b.get("kind", "") == "stage":
			_stage_btn(b)
		else:
			_button(b)
	if toast_t > 0.0:
		_t(Vector2(v.x * 0.5, v.y - 60), toast_text, 30, Color(1, 0.9, 0.6, clamp(toast_t * 2.0, 0.0, 1.0)))


func _button(b: Dictionary) -> void:
	var col: Color = b.col if b.enabled else Color(0.25, 0.25, 0.28)
	_panel(b.rect, col.lightened(0.25) if b.enabled else Color(0.3, 0.3, 0.3), col)
	var size: int = b.get("size", 42)
	_t(b.rect.get_center() + Vector2(0, size * 0.36), b.label, size, Color(1, 1, 1, 1.0 if b.enabled else 0.4), HORIZONTAL_ALIGNMENT_CENTER, 6)


func _stage_btn(b: Dictionary) -> void:
	var s: int = b.s
	var r: Rect2 = b.rect
	var th := Data.theme(s)
	_panel(r, Color("b39ddb") if b.enabled else Color(0.3, 0.3, 0.3), Color(0.1, 0.1, 0.16, 0.95) if b.enabled else Color(0.08, 0.08, 0.1, 0.9))
	_t(r.get_center() + Vector2(0, -8), "%d" % s, 48, Color.WHITE if b.enabled else Color(0.4, 0.4, 0.4))
	_t(r.get_center() + Vector2(0, 34), th.name if b.enabled else "잠김", 22, Color(0.8, 0.8, 0.95) if b.enabled else Color(0.4, 0.4, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 0)
	var best = main.best.get(str(s), null)
	if best != null and b.enabled:
		_t(Vector2(r.end.x - 12, r.position.y + 28), "클리어", 18, Color("69f0ae"), HORIZONTAL_ALIGNMENT_RIGHT, 0)


func _ghost_icon(c: Vector2, s: float, a: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var ang := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * 40.0 * s)
	for i in 7:
		pts.append(c + Vector2(40.0 * s - i * 80.0 * s / 6.0, 60.0 * s + (10.0 * s if i % 2 == 0 else 0.0)))
	draw_colored_polygon(pts, Color(0.95, 0.96, 1.0, a))
	draw_circle(c + Vector2(-14, -4) * s, 7.0 * s, Color(0.05, 0.05, 0.1, a))
	draw_circle(c + Vector2(14, -4) * s, 7.0 * s, Color(0.05, 0.05, 0.1, a))
	draw_circle(c + Vector2(0, 18) * s, 6.0 * s, Color(0.05, 0.05, 0.1, a))


func _draw_logo(v: Vector2, y: float) -> void:
	var bob := sin(main.time * 2.0) * 10.0
	_ghost_icon(Vector2(v.x * 0.5, y - 130 + bob), 1.4, 0.92)
	_t(Vector2(v.x * 0.5, y + 40), "귀신 학교", 96, Color("e8e8ff"), HORIZONTAL_ALIGNMENT_CENTER, 14)
	_t(Vector2(v.x * 0.5, y + 130), "탈출", 110, Color("ff5252"), HORIZONTAL_ALIGNMENT_CENTER, 14)


func _draw_title(v: Vector2) -> void:
	_draw_logo(v, v.y * 0.36)
	var blink := 0.5 + 0.5 * sin(main.time * 4.0)
	_t(Vector2(v.x * 0.5, v.y * 0.72), "화면을 터치해서 시작", 40, Color(1, 1, 1, blink))
	_t(Vector2(v.x * 0.5, v.y * 0.78), "열쇠를 모아 귀신을 피해 탈출하라!", 28, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, 5)
	_t(Vector2(v.x * 0.5, v.y * 0.82), "친구와 코드로 같이 할 수 있어요", 24, Color(0.75, 0.85, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 5)


func _draw_join(v: Vector2) -> void:
	_t(Vector2(v.x * 0.5, 180), "방 코드 입력", 54, Color("e0e0ff"), HORIZONTAL_ALIGNMENT_CENTER, 10)
	_t(Vector2(v.x * 0.5, 230), "친구에게 받은 4자리 숫자를 입력하세요", 24, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 0)
	for i in 4:
		var r := Rect2(v.x * 0.5 - 220 + i * 115, 300, 95, 130)
		_panel(r, Color("b39ddb"), Color(0.1, 0.1, 0.16))
		if i < code_input.length():
			_t(r.get_center() + Vector2(0, 26), code_input[i], 72, Color.WHITE)
	var st: String = main.net.status
	if st == "connecting":
		_t(Vector2(v.x * 0.5, 480), "연결 중...", 30, Color(1, 1, 0.7))
	elif st == "error":
		_t(Vector2(v.x * 0.5, 480), main.net_error_text(), 26, Color("ff8a80"))


func _draw_room(v: Vector2) -> void:
	var host: bool = main.net.is_host
	_t(Vector2(v.x * 0.5, 180), "대기실", 50, Color("e0e0ff"), HORIZONTAL_ALIGNMENT_CENTER, 10)
	_panel(Rect2(v.x * 0.5 - 250, 220, 500, 170), Color("ffd54f"), Color(0.12, 0.1, 0.05, 0.95))
	_t(Vector2(v.x * 0.5, 272), "방 코드", 28, Color(1, 1, 1, 0.75))
	_t(Vector2(v.x * 0.5, 360), main.net.code, 96, Color("ffd54f"), HORIZONTAL_ALIGNMENT_CENTER, 10)
	var st: String = main.net.status
	if st == "connecting":
		_t(Vector2(v.x * 0.5, 430), "방을 여는 중...", 26, Color(1, 1, 0.7))
	elif st == "error":
		_t(Vector2(v.x * 0.5, 430), main.net_error_text(), 24, Color("ff8a80"))
	elif host:
		_t(Vector2(v.x * 0.5, 430), "친구에게 코드를 알려주세요 (최대 4명)", 24, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0)
	# 참가자 목록
	for i in 4:
		var r := Rect2(v.x * 0.5 - 250, 470 + i * 86, 500, 74)
		var has: bool = i < main.roster.size()
		_panel(r, Color(0.4, 0.4, 0.5) if has else Color(0.2, 0.2, 0.24), Color(0.1, 0.1, 0.14, 0.9))
		if has:
			var e: Dictionary = main.roster[i]
			var col: Color = [Color("3d5aa8"), Color("b8443a"), Color("3a9a5a"), Color("a67c2a")][i]
			draw_circle(r.position + Vector2(44, 37), 18.0, col)
			var me: bool = e.id == main.my_id()
			_t(Vector2(r.position.x + 80, r.position.y + 48), e.nick + (" (나)" if me else "") + ("  방장" if i == 0 else ""), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 4)
		else:
			_t(Vector2(r.position.x + 80, r.position.y + 48), "빈 자리", 26, Color(0.5, 0.5, 0.55), HORIZONTAL_ALIGNMENT_LEFT, 0)
	if host:
		_t(Vector2(v.x * 0.5, 912), "스테이지 %d  %s" % [main.room_stage, Data.theme(main.room_stage).name], 34, Color.WHITE)
	else:
		var dots := ".".repeat(int(main.time * 2.0) % 4)
		_t(Vector2(v.x * 0.5, 920), "방장이 시작하기를 기다리는 중" + dots, 30, Color(1, 1, 1, 0.8))


func _draw_result(v: Vector2) -> void:
	var r: Dictionary = main.result
	var p := Rect2(v.x * 0.5 - 300, v.y * 0.5 - 360, 600, 540)
	_panel(p, Color("69f0ae") if r.cleared else Color("ff5252"), Color(0.06, 0.06, 0.1, 0.95))
	var cx := p.get_center().x
	if r.cleared:
		_t(Vector2(cx, p.position.y + 110), "탈출 성공!", 76, Color("69f0ae"), HORIZONTAL_ALIGNMENT_CENTER, 12)
	else:
		_ghost_icon(Vector2(cx, p.position.y + 110), 0.9, 0.9)
		_t(Vector2(cx, p.position.y + 240), "붙잡혔다...", 64, Color("ff5252"), HORIZONTAL_ALIGNMENT_CENTER, 12)
	_t(Vector2(cx, p.position.y + 310), Data.floor_name(r.stage), 32, Color.WHITE)
	_t(Vector2(cx, p.position.y + 370), "걸린 시간 %02d:%02d" % [int(r.time) / 60, int(r.time) % 60], 34, Color(1, 1, 1, 0.9))
	if r.mode != "solo":
		_t(Vector2(cx, p.position.y + 430), "함께한 인원 %d명" % r.players, 28, Color(0.8, 0.9, 1.0))
		if not main.net.is_host:
			_t(Vector2(cx, p.end.y + 70), "방장의 선택을 기다리는 중...", 28, Color(1, 1, 1, 0.8))
	if r.cleared and r.get("unlock", false):
		_t(Vector2(cx, p.position.y + 480), "다음 스테이지가 열렸다!", 28, Color("ffd54f"))
