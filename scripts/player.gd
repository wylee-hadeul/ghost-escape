extends Node2D
## 주인공(플레이어 한 명). 멀티플레이에선 여러 명이 생긴다.
## is_local이면 직접 조작, 아니면 네트워크로 받은 위치로 부드럽게 따라간다.
## 각자 손전등(원뿔)과 주변광을 갖고, 벽이 그림자를 만든다.

const WALK := 150.0
const RUN := 245.0
const R := 14.0
const CONE := 0.62        # 손전등 반각(라디안)
const CONE_RANGE := 400.0
const COLORS := [Color("3d5aa8"), Color("b8443a"), Color("3a9a5a"), Color("a67c2a")]

var run
var net_id := "local"
var slot := 0
var nick := "나"
var is_local := true
var pos := Vector2.ZERO
var target := Vector2.ZERO   # 원격 플레이어 보간 목표
var vel := Vector2.ZERO
var face := 1.0
var aim := Vector2.UP
var hearts := 3
var max_hearts := 3
var stamina := 100.0
var battery := 100.0
var light_on := true
var talismans := 0
var in_locker := false
var locker := Vector2.ZERO
var invuln := 0.0
var hurt_t := 0.0
var anim := 0.0
var running := false
var noise := 0.0
var downed := false
var revive := 0.0            # 동료가 살려주는 진행도 0..1
var escaped := false
var amb_light: PointLight2D
var cone_light: PointLight2D


func _ready() -> void:
	amb_light = PointLight2D.new()
	amb_light.texture = run.radial_tex
	amb_light.shadow_enabled = true
	amb_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(amb_light)
	cone_light = PointLight2D.new()
	cone_light.texture = run.cone_tex
	cone_light.texture_scale = CONE_RANGE * 2.0 / run.cone_tex.get_width()
	cone_light.energy = 1.6
	cone_light.shadow_enabled = true
	cone_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(cone_light)


func reset(p: Vector2) -> void:
	pos = p
	target = p
	vel = Vector2.ZERO
	hearts = max_hearts
	stamina = 100.0
	battery = 100.0
	light_on = true
	talismans = 0
	in_locker = false
	invuln = 2.0
	downed = false
	revive = 0.0
	escaped = false
	aim = Vector2.UP


func alive() -> bool:
	return not downed and not escaped


## 귀신이 노릴 수 있는 상태
func targetable() -> bool:
	return alive() and not in_locker


# ------------------------------------------------------------------ 갱신

func update(delta: float, input: Vector2, want_run: bool) -> void:
	invuln -= delta
	hurt_t -= delta
	if not is_local:
		pos = pos.lerp(target, min(1.0, delta * 12.0))
		_update_lights(delta)
		queue_redraw()
		return
	if light_on:
		battery = max(battery - 2.2 * delta, 0.0)
		if battery <= 0.0:
			light_on = false
	if downed or escaped or in_locker:
		vel = Vector2.ZERO
		noise = 0.0
		if in_locker:
			stamina = min(stamina + 25.0 * delta, 100.0)
		_update_lights(delta)
		queue_redraw()
		return
	running = want_run and stamina > 1.0 and input.length() > 0.2
	if running:
		stamina = max(stamina - 32.0 * delta, 0.0)
	else:
		stamina = min(stamina + 18.0 * delta, 100.0)
	vel = input.limit_length(1.0) * (RUN if running else WALK)
	noise = 260.0 if running else 0.0
	if input.length() > 0.1:
		aim = aim.slerp(input.normalized(), min(1.0, delta * 10.0)).normalized()
		if abs(input.x) > 0.1:
			face = sign(input.x)
		anim += delta * (14.0 if running else 9.0)
	_move(vel * delta)
	_update_lights(delta)
	queue_redraw()


func _update_lights(_delta: float) -> void:
	var col: Color = run.level.theme.light
	amb_light.position = pos
	amb_light.color = col
	var amb_r := 110.0 if light_on else 80.0
	if downed:
		amb_r = 60.0
	amb_light.texture_scale = amb_r * 2.0 / run.radial_tex.get_width()
	amb_light.energy = 0.0 if (in_locker or escaped) else (0.9 if light_on else 0.55)
	cone_light.position = pos + aim * 6.0
	cone_light.rotation = aim.angle()
	cone_light.color = col
	cone_light.enabled = light_on and not in_locker and not downed and not escaped
	# 배터리가 적으면 깜빡인다
	if light_on and battery < 15.0:
		cone_light.energy = 1.6 if randf() > 0.08 else 0.2
	else:
		cone_light.energy = 1.6


func _move(d: Vector2) -> void:
	var lv = run.level
	var nx := pos + Vector2(d.x, 0)
	if not lv.circle_hits(nx, R):
		pos = nx
	var ny := pos + Vector2(0, d.y)
	if not lv.circle_hits(ny, R):
		pos = ny


func toggle_light() -> void:
	if battery <= 0.0:
		light_on = false
		return
	light_on = not light_on


func near_locker() -> Vector2:
	for t in run.level.locker_tiles:
		var c: Vector2 = run.level.center(t)
		if c.distance_to(pos) < 56.0:
			return c
	return Vector2.INF


func toggle_hide() -> void:
	if downed or escaped:
		return
	if in_locker:
		in_locker = false
		pos = locker + Vector2(0, 30)
		return
	var c := near_locker()
	if c == Vector2.INF:
		return
	in_locker = true
	locker = c
	pos = c
	run.on_hide(self)


## 손전등 원뿔 안에 p가 있는지 (벽 가림 포함)
func lights_up(p: Vector2) -> bool:
	if not light_on or in_locker or downed or escaped:
		return false
	var d := p - pos
	if d.length() > CONE_RANGE or d.length() < 1.0:
		return d.length() < 1.0
	if abs(aim.angle_to(d)) > CONE:
		return false
	return run.level.los(pos, p)


# ------------------------------------------------------------------ 그리기 (조명을 받는다)

func _draw() -> void:
	if in_locker or escaped:
		return
	var p := pos
	var col: Color = COLORS[slot % COLORS.size()]
	if downed:
		draw_set_transform(p, PI * 0.5, Vector2.ONE)
		draw_rect(Rect2(-10, -12, 20, 18), col.darkened(0.3))
		draw_circle(Vector2(0, -20), 11.0, Color(0.85, 0.7, 0.6))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if revive > 0.0:
			draw_arc(p, 28.0, -PI * 0.5, -PI * 0.5 + TAU * revive, 32, Color(0.4, 1, 0.5), 5.0)
		return
	var bob: float = abs(sin(anim)) * 3.0 if vel.length() > 1.0 or (not is_local and pos.distance_to(target) > 2.0) else 0.0
	var a := 0.5 if invuln > 0.0 and int(invuln * 12.0) % 2 == 0 else 1.0
	draw_set_transform(p + Vector2(0, -bob), 0.0, Vector2(face, 1.0))
	draw_circle(Vector2(0, 14 + bob), 13.0, Color(0, 0, 0, 0.3))
	var s := sin(anim) * 5.0 if vel.length() > 1.0 else 0.0
	draw_line(Vector2(-4, 4), Vector2(-4 - s, 14), Color(0.15, 0.15, 0.22, a), 5.0)
	draw_line(Vector2(4, 4), Vector2(4 + s, 14), Color(0.15, 0.15, 0.22, a), 5.0)
	draw_rect(Rect2(-10, -12, 20, 18), Color(col, a))
	draw_rect(Rect2(-2, -12, 4, 8), Color(0.92, 0.92, 0.95, a))
	draw_line(Vector2(6, -6), Vector2(16, -2), Color(0.96, 0.8, 0.66, a), 4.0)
	draw_rect(Rect2(14, -5, 9, 6), Color(0.3, 0.3, 0.32, a))
	draw_circle(Vector2(0, -20), 11.0, Color(0.96, 0.8, 0.66, a))
	draw_arc(Vector2(0, -22), 11.0, PI * 1.05, TAU * 0.98, 12, Color(0.12, 0.08, 0.06, a), 7.0)
	draw_circle(Vector2(5, -19), 1.8, Color(0, 0, 0, a))
	if hurt_t > 0.0:
		draw_circle(Vector2(5, -14), 2.5, Color(0, 0, 0, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
