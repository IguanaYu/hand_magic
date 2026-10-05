class_name WaveTable
extends Object
## M1.6 波次数值表：难度曲线唯一定义处，调平衡只改这里。
## 地面：第 N 波 3+2N 枪兵；第 3 波起混 ⌈(N-2)/2⌉ 掠夺者。
## 空军：第 2 波起医疗船空投（第 6 波起 2 趟）；第 4 波起维京（3 波 +1，封顶 3）。


static func wave(n: int) -> Dictionary:
	var marines := 3 + 2 * n
	var marauders := 0
	if n >= 3:
		marauders = ceili(float(n - 2) / 2.0)
	var vikings := 0
	if n >= 4:
		vikings = mini(1 + (n - 4) / 3, 3)
	var medivacs := 0
	if n >= 2:
		medivacs = 1 + (1 if n >= 6 else 0)
	# 每趟空投枪兵数：4 → 封顶 7
	var drops := mini(4 + n / 4, 7)
	return {
		"marines": marines,
		"marauders": marauders,
		"vikings": vikings,
		"medivacs": medivacs,
		"drops": drops,
		"spawn_interval": maxf(0.8, 2.6 - n * 0.15),
		"intermission": 5.0,
	}
