extends Node
## 효과음을 런타임에 합성한다 (외부 오디오 파일 없음).

const RATE := 22050

var streams := {}
var players: Array = []
var idx := 0
var last := {}  # 같은 소리가 한꺼번에 겹치지 않게 마지막 재생 시각
var muted := false


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams["boom"] = _boom(1.0, 1.0)
	streams["small_boom"] = _boom(0.45, 0.7)
	streams["shoot"] = _shoot()
	streams["bite"] = _bite()
	streams["crunch"] = _crunch()
	streams["roar"] = _roar()
	streams["hurt"] = _sweep(0.3, 620.0, 180.0, 0.5, true)
	streams["jump"] = _sweep(0.14, 260.0, 620.0, 0.35, false)
	streams["stomp"] = _stomp()
	streams["shotgun"] = _boom(0.25, 0.8)
	streams["pickup"] = _sweep(0.06, 1100.0, 1500.0, 0.25, false)
	streams["coin"] = _sweep(0.12, 1400.0, 2100.0, 0.25, true)
	streams["levelup"] = _arp()
	streams["heart"] = _heart()
	streams["scream"] = _scream()
	streams["zap"] = _crunch()
	streams["laser"] = _sweep(0.3, 1600.0, 300.0, 0.3, true)


func play(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if muted or not streams.has(sname):
		return
	var now := Time.get_ticks_msec()
	if now - int(last.get(sname, -1000)) < 45:
		return
	last[sname] = now
	var p: AudioStreamPlayer = players[idx]
	idx = (idx + 1) % players.size()
	p.stream = streams[sname]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


func _boom(dur: float, amp: float) -> AudioStreamWAV:
	var b := _buf(dur)
	var y := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		var a: float = lerp(0.35, 0.02, k)
		y += a * (randf_range(-1, 1) - y)
		ph += lerp(70.0, 28.0, k) / RATE
		var thump := sin(ph * TAU) * exp(-t * 9.0)
		b[i] = (y * 2.2 * exp(-k * 4.0) + thump * 0.9) * amp
	return _to_stream(b)


func _shoot() -> AudioStreamWAV:
	var b := _buf(0.28)
	var y := 0.0
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		y += 0.45 * (randf_range(-1, 1) - y)
		ph += lerp(160.0, 50.0, t / 0.28) / RATE
		b[i] = y * exp(-t * 22.0) * 1.2 + sin(ph * TAU) * exp(-t * 14.0) * 0.8
	return _to_stream(b)


func _bite() -> AudioStreamWAV:
	var b := _buf(0.16)
	var prev := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := randf_range(-1, 1)
		var hp := n - prev
		prev = n
		var env := exp(-t * 90.0) + exp(-absf(t - 0.09) * 120.0) * 0.8
		b[i] = hp * env * 0.6
	return _to_stream(b)


func _crunch() -> AudioStreamWAV:
	var b := _buf(0.25)
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		if i % 40 == 0:
			y = randf_range(-1, 1)
		b[i] = (y * 0.6 + randf_range(-0.4, 0.4)) * exp(-t * 16.0)
	return _to_stream(b)


func _roar() -> AudioStreamWAV:
	var dur := 1.1
	var b := _buf(dur)
	var ph1 := 0.0
	var ph2 := 0.0
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env: float = min(t / 0.08, 1.0) * clamp((dur - t) / 0.5, 0.0, 1.0)
		var f := 85.0 + sin(t * 28.0) * 12.0 + t * 25.0
		ph1 += f / RATE
		ph2 += f * 1.51 / RATE
		var saw := fmod(ph1, 1.0) * 2.0 - 1.0
		var saw2 := fmod(ph2, 1.0) * 2.0 - 1.0
		y += 0.15 * (randf_range(-1, 1) - y)
		var x := saw * 0.6 + saw2 * 0.35 + y * 1.5
		b[i] = tanh(x * 2.2) * env * 0.75
	return _to_stream(b)


func _stomp() -> AudioStreamWAV:
	var b := _buf(0.35)
	var ph := 0.0
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += lerp(110.0, 35.0, t / 0.35) / RATE
		y += 0.2 * (randf_range(-1, 1) - y)
		b[i] = sin(ph * TAU) * exp(-t * 10.0) + y * exp(-t * 18.0) * 1.5
	return _to_stream(b)


func _sweep(dur: float, f0: float, f1: float, amp: float, square: bool) -> AudioStreamWAV:
	var b := _buf(dur)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := t / dur
		ph += lerp(f0, f1, k) / RATE
		var s := sin(ph * TAU)
		if square:
			s = 1.0 if s > 0.0 else -1.0
		b[i] = s * amp * (1.0 - k) * min(t * 200.0, 1.0)
	return _to_stream(b)


func _arp() -> AudioStreamWAV:
	var b := _buf(0.36)
	var notes := [523.0, 659.0, 784.0, 1047.0]
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n: int = min(int(t / 0.09), 3)
		ph += notes[n] / RATE
		var local := t - n * 0.09
		b[i] = (1.0 if fmod(ph, 1.0) < 0.5 else -1.0) * 0.22 * exp(-local * 10.0)
	return _to_stream(b)


## 심장 박동 (쿵-쿵)
func _heart() -> AudioStreamWAV:
	var b := _buf(0.42)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var e := exp(-t * 28.0) + 0.7 * exp(-max(t - 0.18, 0.0) * 28.0) * float(t > 0.18)
		ph += lerp(70.0, 40.0, t / 0.42) / RATE
		b[i] = sin(ph * TAU) * e * 0.9
	return _to_stream(b)


## 비명 같은 소음 (피격)
func _scream() -> AudioStreamWAV:
	var dur := 0.6
	var b := _buf(dur)
	var ph := 0.0
	var y := 0.0
	for i in b.size():
		var t := float(i) / RATE
		ph += (900.0 + sin(t * 40.0) * 120.0 - t * 600.0) / RATE
		y += 0.4 * (randf_range(-1, 1) - y)
		var env: float = min(t / 0.03, 1.0) * clamp((dur - t) / 0.3, 0.0, 1.0)
		b[i] = (sin(ph * TAU) * 0.5 + y * 0.5) * env * 0.6
	return _to_stream(b)
