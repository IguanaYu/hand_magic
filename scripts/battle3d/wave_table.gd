class_name WaveTable
extends Object
## M1.4 波次数值表：M1 唯一的难度曲线定义处，调平衡只改这里。
## 第 N 波：3+2N 枪兵；第 3 波起混 ⌈(N-2)/2⌉ 掠夺者；生成间隔渐密；波间 5s。


static func wave(n: int) -> Dictionary:
	var marines := 3 + 2 * n
	var marauders := 0
	if n >= 3:
		marauders = ceili(float(n - 2) / 2.0)
	return {
		"marines": marines,
		"marauders": marauders,
		"spawn_interval": maxf(0.8, 2.6 - n * 0.15),
		"intermission": 5.0,
	}
