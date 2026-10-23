class_name PoseClassifier
extends RefCounted
## 关键点几何 → 手部姿势（GDD §3.3），带多数表决去抖与滞回。
## 阈值基于"指尖-腕距 / 掌长"的比值，与画面缩放无关。
## 去抖为多数表决（非全一致）：旧"连续 N 帧全一致"在输入闪烁时永不切换
## （画符卡住的根源之一），现在窗口内攒够票数即切换，零星跳变帧进不了多数。
## 拳/掌/捏合判定带滞回：进入用严阈值、维持用松阈值，消除阈值边缘反复横跳。


enum Pose { NONE, FIST, PALM, DRAWING, PINCH, VICTORY, THUMB_UP, ILOVEYOU }

const WRIST := 0
const PALM_REF := 9  # 中指掌指关节
const THUMB_TIP := 4
const INDEX_TIP := 8
const FINGER_TIPS := [8, 12, 16, 20]  # 四指比值判定不用拇指（捏合单独判）

const FIST_RATIO := 1.28        # 进入握拳：四指全部弯曲（逐指，不能用平均值）
const FIST_EXIT_RATIO := 1.38   # 退出握拳：握拳中任一比值超过此值才算松开（滞回）
const PALM_RATIO := 1.62        # 进入张掌：四指全部伸直
const PALM_EXIT_RATIO := 1.52   # 退出张掌（滞回：进入严、维持松）
const DRAW_INDEX_RATIO := 1.45  # 食指伸直
const DRAW_FOLDED_RATIO := 1.55  # 其余三指弯曲（真人挥手时三指收不到 1.38 以内，放宽否则姿势抖动）
const PINCH_RATIO := 0.35       # 进入捏合：拇指尖-食指尖距离/掌长 低于此值（真机标定项）
const PINCH_EXIT_RATIO := 0.60  # 退出捏合（滞回：进入严、维持松）
const PINCH_INDEX_MIN := 1.15   # 防握拳误判：捏合时食指尖伸出去够拇指（比值高），
                                # 握拳时指尖收进掌心（比值≈0.7~1.05），低于此不算捏合
const PINCH_EXIT_VOTES := 3     # 离开捏合所需票数（进入仍需 confirm_frames）。
                                # 捏合是瞬态"点击"姿势：松开时手在运动，原始姿势在
                                # 张掌/画符/无 间闪烁，5 票全一致凑不齐 → 稳定姿势
                                # 冻结在'捏合'（真机事故：卡死 24s + latch 静默封锁）
const THUMB_EXT_RATIO := 1.8    # 点赞（扩展）：拇指尖-小指根距离/掌长 超此值=拇指明显
                                # 伸直（合成手标定：拳内收 1.3~1.4，竖拇 ~2.3；真机待标定）

## 去抖票数：窗口 = confirm_frames + 2 帧内同一姿势攒够 confirm_frames 票才切换。
## 设为 1 表示完全去掉抖动（单测用）。
var confirm_frames := 5

## 扩展静态手形开关（GestureFSM.EXTENDED_GESTURES 的镜像，main._ready 同步）：
## 关闭（默认）时 classify() 与旧行为逐字节等价；开启后比耶/点赞/我爱你参与
## 判定（见 classify 内扩展块），FSM 不消费这些姿势、照旧当 NONE。
var extended_poses := false

var last_raw_pose: int = Pose.NONE   # 当帧未经去抖的原始判定（HUD 调试用）
var last_ratios: Array[float] = []   # 最近一次四指比值（HUD 调试用）
var last_pinch_dist: float = -1.0    # 最近一次捏距（拇指尖-食指尖/掌长，HUD 标定用）

var _history: Array[int] = []
var _stable_pose: int = Pose.NONE


## landmarks: 21 个归一化坐标（已镜像，建议为平滑后数据）
func classify(landmarks: Array) -> int:
	if landmarks.size() < 21:
		return _debounce(Pose.NONE)
	var palm_size: float = (landmarks[WRIST] - landmarks[PALM_REF]).length()
	if palm_size < 1e-5:
		return _debounce(Pose.NONE)

	var ratios: Array[float] = []
	for tip in FINGER_TIPS:
		ratios.append((landmarks[tip] - landmarks[WRIST]).length() / palm_size)
	last_ratios = ratios

	# 滞回阈值取决于当前稳定姿势：拳/掌/捏合维持期改用退出阈值（进入严、维持宽）
	var fist_threshold := FIST_EXIT_RATIO if _stable_pose == Pose.FIST else FIST_RATIO
	var palm_threshold := PALM_EXIT_RATIO if _stable_pose == Pose.PALM else PALM_RATIO

	# 捏合 = 拇指尖碰食指尖（落笔显式声明）。必须最先判：捏合手其余三指全弯，
	# 若先判拳会被误吞。guard：食指尖须伸出去够拇指，排除"拳里拇指蹭到指尖"的假捏合
	var pinch_dist: float = (landmarks[THUMB_TIP] - landmarks[INDEX_TIP]).length() / palm_size
	last_pinch_dist = pinch_dist
	var pinch_threshold := PINCH_EXIT_RATIO if _stable_pose == Pose.PINCH else PINCH_RATIO
	if pinch_dist < pinch_threshold and ratios[0] > PINCH_INDEX_MIN:
		return _debounce(Pose.PINCH)

	# 握拳 = 四指全部弯曲（逐指判断）。
	# 不能用平均值：伸食指的手（2.0/1.2/0.7/1.0）平均≈1.2 会被误判成拳
	var all_folded := true
	for r in ratios:
		if r >= fist_threshold:
			all_folded = false
			break
	# 扩展静态手形（2026-10 调研 §1.1 跨平台词表，默认关闭）：
	# 伸直判据复用张掌进入阈值 PALM_RATIO、弯曲判据复用画符三指阈值 DRAW_FOLDED_RATIO
	# ——与捏合/拳/掌几何上互斥（比耶/我爱你有弯指进不了张掌，伸指进不了拳），
	# 在旧管线里这些手本来判 NONE，开启后是纯增量。点赞是拳的拇指伸直亚型
	#（四指全卷+拇指明显伸出）：开启后点赞手不再判 FIST、不再触发聚气，预期语义。
	# 顺序必须在拳/掌判定之前，否则会被它们吞掉。
	if extended_poses:
		if ratios[0] > PALM_RATIO and ratios[1] > PALM_RATIO \
				and ratios[2] < DRAW_FOLDED_RATIO and ratios[3] < DRAW_FOLDED_RATIO:
			return _debounce(Pose.VICTORY)
		if ratios[0] > PALM_RATIO and ratios[3] > PALM_RATIO \
				and ratios[1] < DRAW_FOLDED_RATIO and ratios[2] < DRAW_FOLDED_RATIO:
			return _debounce(Pose.ILOVEYOU)
		var thumb_ext: float = (landmarks[THUMB_TIP] - landmarks[17]).length() / palm_size
		if all_folded and thumb_ext > THUMB_EXT_RATIO:
			return _debounce(Pose.THUMB_UP)
	if all_folded:
		return _debounce(Pose.FIST)
	if _all_above(ratios, palm_threshold):
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
	last_raw_pose = raw_pose
	if confirm_frames <= 1:
		_history.clear()
		_stable_pose = raw_pose
		return _stable_pose
	_history.append(raw_pose)
	var window := confirm_frames + 2
	while _history.size() > window:
		_history.pop_front()
	var votes := 0
	for p in _history:
		if p == raw_pose:
			votes += 1
	# 切换所需票数：一般姿势进出都要 confirm_frames 票；唯独离开捏合降为
	# PINCH_EXIT_VOTES——捏合是瞬态姿势，松开必须能快速被识别（防稳定姿势卡'捏合'）
	var need := confirm_frames
	if _stable_pose == Pose.PINCH and raw_pose != Pose.PINCH:
		need = PINCH_EXIT_VOTES
	if votes >= need and raw_pose != _stable_pose:
		_stable_pose = raw_pose
	return _stable_pose


func stable_pose() -> int:
	return _stable_pose


func reset() -> void:
	_history.clear()
	_stable_pose = Pose.NONE
	last_raw_pose = Pose.NONE
	last_ratios = []
	last_pinch_dist = -1.0


static func pose_name(pose: int) -> String:
	match pose:
		Pose.FIST: return "握拳"
		Pose.PALM: return "张掌"
		Pose.DRAWING: return "画符"
		Pose.PINCH: return "捏合"
		Pose.VICTORY: return "比耶"
		Pose.THUMB_UP: return "点赞"
		Pose.ILOVEYOU: return "我爱你"
		_: return "无"
