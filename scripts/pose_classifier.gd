class_name PoseClassifier
extends RefCounted
## 关键点几何 → 手部姿势（GDD §3.3），带确认帧去抖。
## 阈值基于"指尖-腕距 / 掌长"的比值，与画面缩放无关。


enum Pose { NONE, FIST, PALM, DRAWING }

const WRIST := 0
const PALM_REF := 9  # 中指掌指关节
const INDEX_TIP := 8
const FINGER_TIPS := [8, 12, 16, 20]  # 拇指不参与判定

const FIST_RATIO := 1.28       # 四指平均弯曲阈值
const PALM_RATIO := 1.62       # 四指全部伸直阈值
const DRAW_INDEX_RATIO := 1.6  # 食指伸直
const DRAW_FOLDED_RATIO := 1.38  # 其余三指弯曲

var confirm_frames := 5
var _history: Array[int] = []
var _stable_pose: int = Pose.NONE


## landmarks: 21 个归一化坐标（已镜像）
func classify(landmarks: Array) -> int:
	if landmarks.size() < 21:
		return Pose.NONE
	var palm_size: float = (landmarks[WRIST] - landmarks[PALM_REF]).length()
	if palm_size < 1e-5:
		return Pose.NONE

	var ratios: Array[float] = []
	for tip in FINGER_TIPS:
		ratios.append((landmarks[tip] - landmarks[WRIST]).length() / palm_size)

	# 握拳 = 四指全部弯曲（逐指判断）。
	# 不能用平均值：伸食指的手（2.0/1.2/0.7/1.0）平均≈1.2 会被误判成拳
	var all_folded := true
	for r in ratios:
		if r >= FIST_RATIO:
			all_folded = false
			break
	if all_folded:
		return _debounce(Pose.FIST)
	if _all_above(ratios, PALM_RATIO):
		return _debounce(Pose.PALM)
	# 画符姿：食指伸直、中/无名/小指弯曲
	if ratios[0] > DRAW_INDEX_RATIO and ratios[1] < DRAW_FOLDED_RATIO and ratios[2] < DRAW_FOLDED_RATIO and ratios[3] < DRAW_FOLDED_RATIO:
		return _debounce(Pose.DRAWING)
	return _debounce(Pose.NONE)


func _all_above(ratios: Array[float], threshold: float) -> bool:
	for r in ratios:
		if r <= threshold:
			return false
	return true


func _debounce(raw_pose: int) -> int:
	_history.append(raw_pose)
	if _history.size() > confirm_frames:
		_history.pop_front()
	# 最近 confirm_frames 帧全部一致才切换
	var consistent := true
	for p in _history:
		if p != raw_pose:
			consistent = false
			break
	if consistent and _history.size() >= confirm_frames:
		_stable_pose = raw_pose
	return _stable_pose


func stable_pose() -> int:
	return _stable_pose


func reset() -> void:
	_history.clear()
	_stable_pose = Pose.NONE


static func pose_name(pose: int) -> String:
	match pose:
		Pose.FIST: return "握拳"
		Pose.PALM: return "张掌"
		Pose.DRAWING: return "画符"
		_: return "无"
