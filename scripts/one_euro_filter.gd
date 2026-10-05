class_name OneEuroFilter
extends RefCounted
## One Euro Filter（GDD §3.3）：低速时平稳、高速时跟手。
## Casiez et al. CHI 2012 的经典实现，参数暴露给调参。

var min_cutoff: float = 1.2
var beta: float = 0.05
var d_cutoff: float = 1.0

var _x_prev := Vector2.ZERO
var _dx_prev := 0.0
var _initialized := false
var _last_time_ms := -1


func _init(p_min_cutoff := 1.2, p_beta := 0.05) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta


static func _alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)


func filter(value: Vector2, time_ms: int) -> Vector2:
	if not _initialized:
		_initialized = true
		_x_prev = value
		_last_time_ms = time_ms
		return value
	var dt := maxf(float(time_ms - _last_time_ms) / 1000.0, 0.001)
	_last_time_ms = time_ms

	var dx := (value - _x_prev).length() / dt
	var a_d := _alpha(d_cutoff, dt)
	var dx_hat := _dx_prev + a_d * (dx - _dx_prev)
	_dx_prev = dx_hat

	var cutoff := min_cutoff + beta * absf(dx_hat)
	var a := _alpha(cutoff, dt)
	_x_prev = _x_prev + (value - _x_prev) * a
	return _x_prev


func reset() -> void:
	_initialized = false
	_dx_prev = 0.0
