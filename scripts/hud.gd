extends Node2D
## 게임 중 화면: 생명/열쇠/배터리/스태미나/부적, 미니맵, 동료 상태, 버튼(손전등/달리기/숨기/일시정지),
## 위험 경고(붉은 테두리), 피격 섬광, 알림, 말풍선, 일시정지 메뉴.

const Data = preload("res://scripts/data.gd")

var main
var font: Font
var box := StyleBoxFlat.new()
var danger := 0.0
var flash_t := 0.0
var toast_text := ""
var toast_t := 0.0
var run_finger := -1
var run_key := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	box.set_corner_radius_all(18)
	box.set_border_width_all(4)


func toast(s: String) -> void:
	toast_text = s
	toast_t = 2.4


func flash() -> void:
	flash_t = 0.35


func want_run() -> bool:
	return run_finger != -1 or Input.is_key_pressed(KEY_SHIFT) or run_key


func _process(delta: float) -> void:
	flash_t -= delta
	toast_t -= delta
	queue_redraw()


# ------------------------------------------------------------------ 버튼

func _buttons() -> Dictionary:
	var v: Vector2 = main.view
	return {
		"run": {"c": Vector2(v.x - 112, v.y - 180), "r": 78.0},
		"light": {"c": Vector2(v.x - 96, v.y - 360), "r": 56.0},
		"hide": {"c": Vector2(v.x - 290, v.y - 140), "r": 62.0},
		"pause": {"c": Vector2(52, 186), "r": 32.0},
	}


func button_at(p: Vector2) -> String:
	if main.state != main.State.PLAYING:
		return ""
	for k in _buttons():
		var b: Dictionary = _buttons()[k]
		if k == "hide" and not _hide_visible():
			continue
		if p.distance_to(b.c) < b.r * 1.15:
			return k
	return ""


func _hide_visible() -> bool:
	var pl = main.run.local
	return pl != null and (pl.in_locker or pl.near_locker() != Vector2.INF) and not pl.downed


func pause_buttons() -> Array:
	var v: Vector2 = main.view
	var multi: bool = main.run.mode != "solo"
	return [
		{"id": "resume", "rect": Rect2(v.x * 0.5 - 200, v.y * 0.5 - 40, 400, 110), "label": "계속하기", "col": Color("43a047")},
		{"id": "quit", "rect": Rect2(v.x * 0.5 - 200, v.y * 0.5 + 100, 400, 110), "label": "나가기" if multi else "포기하기", "col": Color("c62828")},
	]


func _input(event: InputEvent) -> void:
	if main.state == main.State.PLAYING:
		if event is InputEventScreenTouch:
			if event.pressed:
				match button_at(event.position):
					"run":
						run_finger = event.index
						get_viewport().set_input_as_handled()
					"light":
						main.run.local.toggle_light()
						main.sfx.play("pickup", -10.0, 0.6)
						get_viewport().set_input_as_handled()
					"hide":
						main.run.local.toggle_hide()
						get_viewport().set_input_as_handled()
					"pause":
						main.state = main.State.PAUSE
						get_viewport().set_input_as_handled()
			elif event.index == run_finger:
				run_finger = -1
		elif event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_F, KEY_L:
					main.run.local.toggle_light()
				KEY_E, KEY_H:
					main.run.local.toggle_hide()
				KEY_ESCAPE, KEY_P:
					main.state = main.State.PAUSE
	elif main.state == main.State.PAUSE:
		if event is InputEventScreenTouch and event.pressed:
			for b in pause_buttons():
				if b.rect.has_point(event.position):
					main.pause_action(b.id)
					get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			main.pause_action("resume")


# ------------------------------------------------------------------ 그리기

func text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, outline := 7) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= w
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func heart(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.5, 0), r * 0.55, col)
	draw_circle(c + Vector2(r * 0.5, 0), r * 0.55, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, r * 0.15), c + Vector2(r * 1.02, r * 0.15), c + Vector2(0, r * 1.2)]), col)


func _draw() -> void:
	if not main.state in [main.State.PLAYING, main.State.PAUSE]:
		return
	var run = main.run
	var pl = run.local
	if pl == null:
		return
	var v: Vector2 = main.view
	# 위험 경고: 화면 가장자리가 붉어진다
	if danger > 0.05:
		var a: float = danger * (0.35 + 0.15 * sin(main.time * 8.0))
		for i in 6:
			var w := 18.0 + i * 14.0
			var c := Color(0.6, 0.0, 0.0, a * (1.0 - i / 6.0) * 0.5)
			draw_rect(Rect2(0, 0, v.x, w), c)
			draw_rect(Rect2(0, v.y - w, v.x, w), c)
			draw_rect(Rect2(0, 0, w, v.y), c)
			draw_rect(Rect2(v.x - w, 0, w, v.y), c)
	if flash_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, v), Color(0.8, 0.0, 0.0, flash_t * 1.4))
	# 생명/부적
	for i in pl.max_hearts:
		heart(Vector2(36 + i * 46, 50), 16.0, Color("e53935") if i < pl.hearts else Color(0.25, 0.25, 0.28))
	if pl.talismans > 0:
		draw_rect(Rect2(36 + pl.max_hearts * 46, 32, 18, 32), Color("ffd54f"))
		text(Vector2(62 + pl.max_hearts * 46, 62), "x%d" % pl.talismans, 26, Color("ffd54f"), HORIZONTAL_ALIGNMENT_LEFT, 5)
	# 배터리/스태미나
	_bar(Rect2(20, 86, 190, 14), pl.battery / 100.0, Color("ffee58") if pl.battery > 15.0 else Color("ff7043"), "손전등")
	_bar(Rect2(20, 118, 190, 14), pl.stamina / 100.0, Color("4fc3f7"), "체력")
	# 열쇠
	var total: int = run.items.list.filter(func(it): return it.kind == "key").size()
	var got: int = total - run.items.keys_left()
	text(Vector2(v.x * 0.5, 54), Data.floor_name(run.stage), 24, Color(1, 1, 1, 0.8))
	var ktxt := "열쇠 %d / %d" % [got, total] if not run.items.exit_open else "출구로 탈출하라!"
	text(Vector2(v.x * 0.5, 96), ktxt, 36, Color("ffd54f") if not run.items.exit_open else Color("69f0ae"))
	_minimap(run, v)
	# 동료
	var ty := 290.0
	for p in run.players:
		if p.is_local:
			continue
		var st := "기절!" if p.downed else ("탈출" if p.escaped else str(p.hearts))
		var col: Color = p.COLORS[p.slot % 4]
		draw_circle(Vector2(v.x - 200, ty - 8), 9.0, col)
		text(Vector2(v.x - 184, ty), p.nick, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 4)
		if p.downed:
			text(Vector2(v.x - 24, ty), st, 20, Color("ff8a80"), HORIZONTAL_ALIGNMENT_RIGHT, 4)
		else:
			for i in p.hearts:
				heart(Vector2(v.x - 30 - i * 22, ty - 8), 7.0, Color("e53935"))
		ty += 30.0
	# 말풍선
	var voice = main.voice
	if voice.bubble_t > 0.0:
		var sp: Vector2 = get_viewport().canvas_transform * (pl.pos + Vector2(0, -50))
		var fs := 24
		var tw := font.get_string_size(voice.bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var r := Rect2(sp.x - tw * 0.5 - 14, sp.y - 48, tw + 28, 42)
		r.position.x = clamp(r.position.x, 8.0, v.x - r.size.x - 8.0)
		var a: float = clamp(voice.bubble_t * 2.0, 0.0, 1.0)
		box.bg_color = Color(1, 1, 1, 0.92 * a)
		box.border_color = Color(0.1, 0.1, 0.1, a)
		box.draw(get_canvas_item(), r)
		draw_string(font, Vector2(r.position.x + 14, r.position.y + 30), voice.bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.1, a))
	# 버튼
	var bs := _buttons()
	var rb: Dictionary = bs.run
	draw_circle(rb.c, rb.r, Color(1, 1, 1, 0.28 if want_run() else 0.13))
	draw_arc(rb.c, rb.r, -PI * 0.5, -PI * 0.5 + TAU * pl.stamina / 100.0, 40, Color("4fc3f7"), 6.0)
	text(rb.c + Vector2(0, 12), "달리기", 30, Color.WHITE)
	var lb: Dictionary = bs.light
	draw_circle(lb.c, lb.r, Color(1, 0.95, 0.5, 0.3) if pl.light_on else Color(1, 1, 1, 0.1))
	draw_arc(lb.c, lb.r, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 3.0)
	text(lb.c + Vector2(0, 10), "손전등", 22, Color.WHITE if pl.light_on else Color(1, 1, 1, 0.6))
	if _hide_visible():
		var hb: Dictionary = bs.hide
		draw_circle(hb.c, hb.r, Color(0.4, 0.7, 1.0, 0.35 + 0.1 * sin(main.time * 6.0)))
		text(hb.c + Vector2(0, 10), "나오기" if pl.in_locker else "숨기", 28, Color.WHITE)
	var pb: Dictionary = bs.pause
	draw_circle(pb.c, pb.r, Color(0, 0, 0, 0.4))
	draw_rect(Rect2(pb.c + Vector2(-11, -13), Vector2(7, 26)), Color.WHITE)
	draw_rect(Rect2(pb.c + Vector2(4, -13), Vector2(7, 26)), Color.WHITE)
	if pl.in_locker:
		text(Vector2(v.x * 0.5, v.y * 0.62), "사물함에 숨어 있다... 숨죽여!", 30, Color(0.7, 0.85, 1.0))
	if pl.downed:
		text(Vector2(v.x * 0.5, v.y * 0.62), "기절! 동료가 옆에 오면 살아난다", 30, Color("ff8a80"))
	if toast_t > 0.0:
		text(Vector2(v.x * 0.5, v.y * 0.3), toast_text, 34, Color(1, 1, 0.8, clamp(toast_t * 2.0, 0.0, 1.0)))
	if main.state == main.State.PAUSE:
		draw_rect(Rect2(Vector2.ZERO, v), Color(0, 0, 0, 0.6))
		text(Vector2(v.x * 0.5, v.y * 0.5 - 120), "일시 정지" if run.mode == "solo" else "메뉴 (게임은 계속됩니다)", 48, Color.WHITE)
		for b in pause_buttons():
			box.bg_color = b.col
			box.border_color = b.col.darkened(0.3)
			box.draw(get_canvas_item(), b.rect)
			text(b.rect.get_center() + Vector2(0, 14), b.label, 38, Color.WHITE)


func _bar(r: Rect2, k: float, col: Color, label: String) -> void:
	draw_rect(r.grow(2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clamp(k, 0.0, 1.0), r.size.y)), col)
	text(Vector2(r.end.x + 8, r.end.y + 2), label, 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 4)


func _minimap(run, v: Vector2) -> void:
	var lv = run.level
	var maxw := 190.0
	var maxh := 220.0
	var s: float = min(maxw / lv.w, maxh / lv.h)
	var o := Vector2(v.x - 20 - lv.w * s, 20)
	draw_rect(Rect2(o - Vector2(4, 4), Vector2(lv.w * s, lv.h * s) + Vector2(8, 8)), Color(0, 0, 0, 0.55))
	for y in lv.h:
		for x in lv.w:
			if run.explored[y * lv.w + x] == 1 and lv.grid[y * lv.w + x] == 0:
				draw_rect(Rect2(o + Vector2(x, y) * s, Vector2(s, s)), Color(0.55, 0.6, 0.7, 0.55))
	for it in run.items.list:
		if it.kind == "key" and not it.taken and it.seen:
			draw_circle(o + it.pos / lv.T * s, 3.5, Color("ffd54f"))
	if run.items.exit_open:
		draw_circle(o + run.items.exit_pos() / lv.T * s, 5.0 + sin(main.time * 5.0), Color("69f0ae"))
	for p in run.players:
		draw_circle(o + p.pos / lv.T * s, 4.0 if p.is_local else 3.0, Color.WHITE if p.is_local else p.COLORS[p.slot % 4])
