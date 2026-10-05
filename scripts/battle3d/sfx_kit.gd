class_name SfxKit
extends Object
## M1.6 程序化音效：不依赖音频素材，首次请求时合成 16bit PCM（22050Hz 单声道）并缓存。
## 取流用 SfxKit.stream("boom")；播放走 Battlefield3D.play_sfx（3D 空间声 + 限频）。

const MIX_RATE := 22050

static var _cache: Dictionary = {}


static func stream(key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var raw := _build(key)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(raw.size() * 2)
	for i in raw.size():
		# tanh 软限幅，避免多声源叠加爆音
		var v: float = tanh(raw[i] * 1.15)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	wav.data = bytes
	_cache[key] = wav
	return wav


# ---------- 合成配方 ----------

static func _build(key: String) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match key:
		"shoot":        # 步枪哒哒
			return _mix(_noise(0.06, 0.5, 70.0, rng), _tone(520.0, 320.0, 0.05, 0.22, "sine", 40.0))
		"shoot_big":    # 掠夺者/维京导弹
			return _mix(_noise(0.14, 0.55, 24.0, rng, true), _tone(170.0, 85.0, 0.12, 0.5, "sine", 18.0))
		"hit":          # 命中反馈 tick
			return _mix(_tone(1300.0, 720.0, 0.05, 0.45, "square", 40.0), _noise(0.02, 0.22, 60.0, rng))
		"boom":         # 地面单位死亡爆炸
			return _mix(_noise(0.55, 0.75, 5.5, rng, true), _tone(110.0, 42.0, 0.5, 0.9, "sine", 4.0))
		"boom_big":     # 空中大爆炸/残骸坠地
			return _mix(_noise(0.9, 0.8, 3.2, rng, true), _tone(72.0, 30.0, 0.85, 1.0, "sine", 2.5))
		"zap":          # 链电
			return _mix(_tone(1750.0, 130.0, 0.18, 0.5, "saw", 12.0), _noise(0.1, 0.18, 30.0, rng))
		"bolt":         # 奥术快射
			return _mix(_tone(950.0, 1500.0, 0.09, 0.3, "sine", 20.0), _noise(0.05, 0.15, 40.0, rng))
		"cast_fire":    # 火球施放
			return _mix(_noise(0.28, 0.35, 0.0, rng, false, true), _tone(240.0, 760.0, 0.28, 0.3, "sine", 4.0))
		"cast_ice":     # 冰域施放
			return _mix(_mix(_noise(0.5, 0.28, 1.5, rng, false, true), _tone(2600.0, 2350.0, 0.5, 0.1, "sine", 3.0)), _tone(3400.0, 3100.0, 0.42, 0.07, "sine", 3.0))
		"cast_wind":    # 风刃施放
			return _mix(_noise(0.38, 0.45, 0.0, rng, false, true), _tone(380.0, 980.0, 0.35, 0.14, "sine", 3.0))
		"thump":        # 空投落地/玩家受击闷响
			return _tone(150.0, 52.0, 0.18, 0.95, "sine", 16.0)
		"shield":       # 护盾格挡
			return _mix(_tone(950.0, 700.0, 0.12, 0.32, "sine", 10.0), _tone(1420.0, 1050.0, 0.12, 0.18, "sine", 10.0))
		"flyby":        # 空军进场低鸣
			return _mix(_noise(0.8, 0.4, 0.0, rng, true, true), _tone(95.0, 72.0, 0.8, 0.35, "sine", 1.5))
		"chime":        # 开波提示
			return _seq([_tone(660.0, 660.0, 0.16, 0.4, "sine", 4.0), _tone(880.0, 880.0, 0.3, 0.4, "sine", 3.0)], 0.03)
		"lose":         # 阵亡
			return _seq([_tone(392.0, 392.0, 0.25, 0.4, "sine", 3.0), _tone(311.0, 311.0, 0.25, 0.4, "sine", 3.0), _tone(233.0, 220.0, 0.4, 0.4, "sine", 2.0)], 0.02)
	return PackedFloat32Array()


# ---------- 合成原语 ----------

## 扫频音：f0→f1，kind = sine/square/saw，decay 为指数衰减系数（0=不衰减）
static func _tone(f0: float, f1: float, dur: float, vol: float, kind: String, decay: float) -> PackedFloat32Array:
	var n := maxi(1, int(dur * MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f: float = lerpf(f0, f1, t / dur)
		phase += TAU * f / MIX_RATE
		var v := 0.0
		match kind:
			"sine":
				v = sin(phase)
			"square":
				v = 1.0 if fmod(phase, TAU) < PI else -1.0
			"saw":
				v = fmod(phase, TAU) / TAU * 2.0 - 1.0
		var env := 1.0
		if decay > 0.0:
			env *= exp(-t * decay)
		if t < 0.002:
			env *= t / 0.002
		out[i] = v * vol * env
	return out


## 白噪声：muffle=低通闷化，swell=中间响两头轻（引擎/风类），decay=指数衰减
static func _noise(dur: float, vol: float, decay: float, rng: RandomNumberGenerator, muffle := false, swell := false) -> PackedFloat32Array:
	var n := maxi(1, int(dur * MIX_RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var v: float = rng.randf_range(-1.0, 1.0)
		if muffle:
			v = lerpf(prev, v, 0.3)
			prev = v
		var env := 1.0
		if decay > 0.0:
			env *= exp(-t * decay)
		if swell:
			env *= sin(PI * t / dur)
		if t < 0.002:
			env *= t / 0.002
		out[i] = v * vol * env
	return out


## 逐样本相加（短的一方补零）
static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var va: float = a[i] if i < a.size() else 0.0
		var vb: float = b[i] if i < b.size() else 0.0
		out[i] = va + vb
	return out


## 顺序拼接（段间补 gap 秒静音）
static func _seq(parts: Array, gap: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var gap_n := int(gap * MIX_RATE)
	for i in parts.size():
		if i > 0:
			out.append_array(PackedFloat32Array())
			out.resize(out.size() + gap_n)
		out.append_array(parts[i])
	return out
