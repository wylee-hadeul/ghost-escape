extends Node
## 주인공의 한국어 대사: 말풍선 + 음성 합성(TTS).
## 웹에서는 브라우저 Web Speech API(ko-KR), 데스크톱에서는 Godot TTS를 쓴다.

const Data = preload("res://scripts/data.gd")

var tts_enabled := true
var gender := "m"  # "m" 철수 / "f" 영희 — 성별에 맞는 음성을 고르고, 없으면 높이로 구분
var bubble := ""
var bubble_t := 0.0
var cool := 0.0       # 말풍선 간격
var tts_cool := 0.0   # 음성 간격
var idle_t := 12.0


func reset() -> void:
	bubble = ""
	bubble_t = 0.0
	cool = 0.0
	tts_cool = 0.0
	idle_t = 12.0


func update(delta: float, playing: bool) -> void:
	bubble_t -= delta
	cool -= delta
	tts_cool -= delta
	if playing:
		idle_t -= delta
		if idle_t <= 0.0:
			idle_t = randf_range(14.0, 22.0)
			say("idle")


## key: Data.LINES의 키 또는 직접 문장. force면 쿨타임을 무시한다.
func say(key: String, force := false) -> void:
	if not force and cool > 0.0:
		return
	var text := key
	if Data.LINES.has(key):
		var arr: Array = Data.LINES[key]
		text = arr[randi() % arr.size()]
	bubble = text
	bubble_t = 2.6
	cool = 4.0
	if tts_enabled and (force or tts_cool <= 0.0):
		tts_cool = 3.0
		speak(text)


## 남/여 음성 구분용 이름 패턴 (Windows: InJoon/SunHi, Android: ko-kr-x-koc/kod 남성, koa/kob 여성,
## Apple: 유나/소라 여성, Chrome: "Google 한국의" 여성). 이름이 한글로 나오는 기기도 있다.
const MALE_RE := "injoon|minsu|jinho|인준|민수|진호|male|남성|-koc|-kod"
const FEMALE_RE := "sunhi|yuna|sora|heami|jimin|선희|유나|소라|혜미|지민|google|female|여성|-koa|-kob"


func speak(text: String) -> void:
	if OS.has_feature("web"):
		var js := """
			(function(t,g){try{var s=window.speechSynthesis;if(!s)return;
			var vs=s.getVoices().filter(function(v){return v.lang&&v.lang.toLowerCase().replace('_','-').indexOf('ko')==0;});
			var male=new RegExp('%s','i'),female=new RegExp('%s','i');
			var pick=null;
			for(var i=0;i<vs.length;i++){var id=vs[i].name+' '+vs[i].voiceURI;
				if(g=='m'&&male.test(id)&&!female.test(id)){pick=vs[i];break;}
				if(g=='f'&&female.test(id)){pick=vs[i];break;}}
			var u=new SpeechSynthesisUtterance(t);u.lang='ko-KR';u.rate=1.05;
			if(pick){u.voice=pick;u.pitch=(g=='m')?0.95:1.15;}
			else{if(vs.length){u.voice=vs[0];}u.pitch=(g=='m')?0.5:1.2;}
			s.cancel();s.speak(u);}catch(e){}})(%s,'%s');
		""" % [MALE_RE, FEMALE_RE, JSON.stringify(text), gender]
		JavaScriptBridge.eval(js, true)
		return
	var list := DisplayServer.tts_get_voices()
	var male := RegEx.create_from_string("(?i)" + MALE_RE)
	var female := RegEx.create_from_string("(?i)" + FEMALE_RE)
	var fallback := ""
	var pick := ""
	for v in list:
		if not str(v.get("language", "")).to_lower().begins_with("ko"):
			continue
		var id: String = str(v.get("name", "")) + " " + str(v.get("id", ""))
		if fallback == "":
			fallback = v.id
		if gender == "m" and male.search(id) and not female.search(id):
			pick = v.id
			break
		if gender == "f" and female.search(id):
			pick = v.id
			break
	var p := 1.0
	if pick == "":
		if fallback == "":
			return
		pick = fallback
		p = 0.5 if gender == "m" else 1.2
	else:
		p = 0.95 if gender == "m" else 1.15
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(text, pick, 80, p, 1.05)
