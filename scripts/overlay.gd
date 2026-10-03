extends Node2D
## 어둠 속에서도 보이는 것들 (UNSHADED): 귀신의 빛나는 눈, 희미한 달걀귀신, 동료 이름표/기절 표시.

var run


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if run == null or not run.active:
		return
	var font := ThemeDB.fallback_font
	for g in run.ghosts.list:
		var p: Vector2 = g.pos + Vector2(0, sin(g.t * 2.5) * 4.0)
		var flick: float = 0.6 + 0.4 * sin(g.t * 7.0)
		match g.kind:
			"maiden":
				for ex in [-4.0, 4.0]:
					var e: Vector2 = p + Vector2(ex * g.face, -20)
					draw_circle(e, 4.5, Color(1, 0.1, 0.1, 0.25 * flick))
					draw_circle(e, 1.8, Color(1, 0.3, 0.3, 0.9 * flick))
			"egg":
				# 벽을 통과하는 귀신은 희미하게 항상 보인다
				draw_circle(p + Vector2(0, -12), 20.0, Color(1, 1, 1, 0.07))
				draw_circle(p + Vector2(0, -12), 12.0, Color(1, 1, 0.95, 0.12 * flick))
			_:
				for ex in [-4.0, 4.0]:
					var e: Vector2 = p + Vector2(ex * g.face, -20)
					var col := Color(0.5, 0.85, 1.0) if g.frozen else Color(1, 0.15, 0.1)
					draw_circle(e, 5.0, Color(col, 0.3 * flick))
					draw_circle(e, 2.0, Color(col, 0.95))
	# 동료 표시
	for p in run.players:
		if p.is_local or p.escaped:
			continue
		var pos: Vector2 = p.pos
		var name: String = p.nick
		if p.downed:
			name += " (기절!)"
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string_outline(font, pos + Vector2(-w * 0.5, -40), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.8))
		draw_string(font, pos + Vector2(-w * 0.5, -40), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.6, 0.5) if p.downed else Color(0.85, 0.95, 1.0))
		if p.downed:
			draw_arc(pos, 24.0 + sin(run.t * 6.0) * 4.0, 0.0, TAU, 24, Color(1, 0.4, 0.3, 0.7), 3.0)
