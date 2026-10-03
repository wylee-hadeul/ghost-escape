extends Node
## 멀티플레이 연결 (웹 전용). web/net.js의 GNet을 JavaScriptBridge로 호출한다.
## 방장이 게임을 계산하고, 참가자는 입력을 보내고 상태를 받는다.

signal joined(from: String)
signal left(from: String)
signal received(from: String, data: Dictionary)

var available := OS.has_feature("web")
var status := "idle"   # idle / connecting / hosting / joined / error
var my_id := ""
var error := ""
var is_host := false
var code := ""


func active() -> bool:
	return status == "hosting" or status == "joined"


func host(c: String) -> void:
	code = c
	is_host = true
	status = "connecting"
	if available:
		JavaScriptBridge.eval("GNet.host('%s')" % c, true)


func join(c: String) -> void:
	code = c
	is_host = false
	status = "connecting"
	if available:
		JavaScriptBridge.eval("GNet.join('%s')" % c, true)


func leave() -> void:
	status = "idle"
	is_host = false
	if available:
		JavaScriptBridge.eval("GNet.reset()", true)


## to: 상대 id 또는 "*"(전체)
func send(to: String, d: Dictionary) -> void:
	if available and active():
		JavaScriptBridge.eval("GNet.send(%s, %s)" % [JSON.stringify(to), JSON.stringify(d)], true)


func _process(_delta: float) -> void:
	if not available or status == "idle":
		return
	var raw = JavaScriptBridge.eval("GNet.poll()", true)
	if typeof(raw) != TYPE_STRING:
		return
	var info = JSON.parse_string(raw)
	if typeof(info) != TYPE_DICTIONARY:
		return
	status = info.status
	my_id = info.id
	error = info.err
	for m in info.msgs:
		match m.t:
			"_join":
				joined.emit(m.from)
			"_leave":
				left.emit(m.from)
			"_data":
				if typeof(m.d) == TYPE_DICTIONARY:
					received.emit(m.from, m.d)
