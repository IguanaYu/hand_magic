class_name MarioWaveTable
extends Object
## M2 马里奥换皮波次数值表：难度唯一定义处，调平衡只改这里（GDD §5）。
## 固定 4 波：1 栗宝宝热场 / 2 加龟 / 3 混战 / 4 大部队 + 库巴压轴，杀库巴通关。
## 幽灵 Boo 不进波次表：常驻补充制（boo_cap，死后 4s 场外飘回）。


static func wave(n: int) -> Dictionary:
	var t := {1: [6, 0], 2: [6, 2], 3: [8, 3], 4: [12, 4]}
	var gk: Array = t.get(clampi(n, 1, LAST_WAVE), [12, 4])
	return {
		"goombas": gk[0],
		"koopas": gk[1],
		"bowser": 1 if n >= LAST_WAVE else 0,
		"spawn_interval": maxf(0.8, 2.4 - n * 0.3),
		"intermission": 4.0,
		"boo_cap": 2 if n < 3 else 3,
	}


static func last_wave() -> int:
	return LAST_WAVE


const LAST_WAVE := 4
