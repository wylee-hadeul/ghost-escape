extends Node2D
## 플로팅 조이스틱: 화면 아무 곳이나 누르면 그 자리에 생기고 끌어서 이동한다.
## 마우스도 터치로 에뮬레이트된다. 키보드는 WASD/방향키.

const RADIUS := 80.0

var main
var finger := -1
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var touch_dir := Vector2.ZERO
var bot_dir = null   # 오토플레이가 덮어쓰는 방향


func reset() -> void:
	finger = -1
	touch_dir = Vector2.ZERO


func direction() -> Vector2:
	if bot_dir != null:
		return bot_dir
	var k := Input.get_vector("left", "right", "up", "down")
	if k.length() > 0.1:
		return k
	return touch_dir


func _input(event: InputEvent) -> void:
	if main.state != main.State.PLAYING:
		if finger != -1:
			reset()
		return
	if event is InputEventScreenTouch:
		if event.pressed and finger == -1:
			if main.hud.button_at(event.position) != "":
				return
			finger = event.index
			origin = event.position
			knob = origin
			touch_dir = Vector2.ZERO
		elif not event.pressed and event.index == finger:
			reset()
	elif event is InputEventScreenDrag and event.index == finger:
		var off: Vector2 = event.position - origin
		if off.length() > RADIUS:
			origin += off - off.normalized() * RADIUS  # 손가락을 따라 조이스틱이 끌려온다
			off = off.normalized() * RADIUS
		knob = origin + off
		var v := off / RADIUS
		touch_dir = v if v.length() > 0.15 else Vector2.ZERO


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if finger == -1 or main.state != main.State.PLAYING:
		return
	draw_circle(origin, RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(origin, RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.4), 3.0)
	draw_circle(knob, 34.0, Color(1, 1, 1, 0.45))
