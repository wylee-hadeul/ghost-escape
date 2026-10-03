extends RefCounted
## 게임 데이터: 테마, 스테이지 구성, 귀신, 대사.

const T := 48.0  # 타일 크기(px)

## 테마: 3스테이지마다 바뀐다
const THEMES := [
	{"name": "폐교", "floor": Color("6b4f36"), "floor2": Color("5e452f"), "wall": Color("2a2733"), "wall_top": Color("3d3948"),
		"dark": Color(0.07, 0.07, 0.1), "light": Color(1.0, 0.92, 0.75)},
	{"name": "폐병원", "floor": Color("8a9a92"), "floor2": Color("7b8b83"), "wall": Color("26302e"), "wall_top": Color("3a4744"),
		"dark": Color(0.05, 0.08, 0.08), "light": Color(0.85, 1.0, 0.95)},
	{"name": "흉가", "floor": Color("4e3b2c"), "floor2": Color("433326"), "wall": Color("231a16"), "wall_top": Color("3a2c24"),
		"dark": Color(0.08, 0.05, 0.05), "light": Color(1.0, 0.8, 0.6)},
]

static func theme(s: int) -> Dictionary:
	return THEMES[((s - 1) / 3) % THEMES.size()]


## 미로 크기(칸 수). 한 칸 = 3타일(바닥 2 + 벽 1)
static func maze_size(s: int) -> Vector2i:
	return Vector2i(min(6 + s, 13), min(9 + s, 19))


static func key_count(s: int) -> int:
	return min(3 + (s - 1) / 2, 6)


## 스테이지별 귀신 수
static func ghost_counts(s: int) -> Dictionary:
	return {
		"maiden": min(1 + s / 2, 5),
		"egg": 0 if s < 2 else min(1 + (s - 2) / 3, 3),
		"reaper": 0 if s < 3 else min(1 + (s - 3) / 3, 3),
	}


static func floor_name(s: int) -> String:
	return "스테이지 %d  %s" % [s, theme(s).name]


const GHOSTS := {
	"maiden": {"name": "처녀귀신", "desc": "복도를 떠돌다 눈이 마주치면 쫓아온다.\n시야에서 벗어나면 마지막 위치를 찾는다."},
	"egg": {"name": "달걀귀신", "desc": "얼굴 없는 귀신. 느리지만\n벽을 통과해서 계속 다가온다."},
	"reaper": {"name": "저승사자", "desc": "아주 빠르다. 하지만\n손전등 빛을 비추면 얼어붙는다."},
}

const LINES := {
	"start": ["여기 어디야... 빨리 나가야 해!", "으, 너무 어두워...", "열쇠를 찾아서 탈출하자!"],
	"key": ["열쇠다!", "하나 찾았다!", "좋아, 열쇠!"],
	"allkeys": ["문이 열렸어! 출구로 가자!", "열쇠를 다 모았어! 계단으로!"],
	"spotted": ["귀, 귀신이다!", "들켰어! 도망쳐!", "으악, 따라온다!"],
	"hurt": ["으아악!", "살려줘!", "아파!"],
	"hide": ["숨어야 해...", "제발 지나가라..."],
	"talisman": ["부적이다! 이걸로 막을 수 있어!"],
	"blocked": ["부적이 막아줬어!"],
	"reaper": ["저승사자...! 빛을 비추면 멈춰!"],
	"battery": ["배터리다!"],
	"lowbat": ["손전등이 꺼지려고 해..."],
	"idle": ["무슨 소리지...?", "누가 있어요...?", "조심조심...", "등골이 오싹해..."],
	"clear": ["탈출 성공!"],
}
