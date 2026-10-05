extends SceneTree
## 独立性能探针：只跑 $1 识别基准，排除场景与 HandTracker 干扰
func _init() -> void:
	var rec := DollarRecognizer.new()
	var pts: Array = []
	var c := Vector2(0.5, 0.4)
	for i in range(40):
		var a: float = TAU * i / 40.0
		pts.append(c + Vector2(cos(a), sin(a)) * 0.12)
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		rec.recognize(pts)
	var avg_ms := (Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	var f := FileAccess.open("res://tests/perf_probe.txt", FileAccess.WRITE)
	f.store_string("avg_ms=%.2f\n" % avg_ms)
	f.flush()
	quit(0)
