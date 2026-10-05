"""OS 级真实输入的游戏实测编排器。
用法: python gui_play_test.py <step>
每步前后各取一次状态快照，输出对比结果到 tests/gui_play_log.txt。
"""
import json, subprocess, sys, time

STATE = r"E:\godot\magic\tests\gui_state.txt"
DRIVER = r"E:\godot\magic\downloads\post_driver.ps1"
CLIENT_OX, CLIENT_OY = 366, 113
# 窗口 client ≈ 731x555 显示 1280x960 内容
SX, SY = 1280.0 / 731.0, 960.0 / 555.0
LOG = r"E:\godot\magic\tests\gui_play_log.txt"


def read_state():
    for _ in range(20):
        try:
            with open(STATE, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            time.sleep(0.2)
    return None


def log(msg):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(msg + "\n")
    print(msg)


def drive(mode, **kw):
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", DRIVER, "-Mode", mode]
    for k, v in kw.items():
        cmd += ["-" + {"x": "CX", "y": "CY", "x2": "CX2", "y2": "CY2", "key": "Key"}.get(k, k.upper()), str(v)]
    r = subprocess.run(cmd, capture_output=True, timeout=60, text=True)
    if r.returncode != 0 or "not found" in (r.stderr or ""):
        print("[driver-error]", (r.stderr or r.stdout or "")[:200])


def to_screen(gx, gy):
    # PostMessage 用客户区坐标
    return int(gx / SX), int(gy / SY)


def main():
    step = sys.argv[1]
    if step == "click_near_enemy":
        s = read_state()
        ens = s.get("enemies", [])
        if not ens:
            log("[FAIL] 无敌人可瞄")
            return
        # 只选画面内的敌人（边缘刚生成的换算后会点到窗口外）
        visible = [e for e in ens if 30 < e["x"] < 1250 and 30 < e["y"] < 930]
        if not visible:
            log("[FAIL] 无画面内敌人")
            return
        e = visible[0]
        sx, sy = to_screen(e["x"], e["y"])
        before = read_state()
        drive("click", x=sx, y=sy)
        time.sleep(1.2)
        after = read_state()
        log(f"[click] 目标敌人@({e['x']},{e['y']}) 屏({sx},{sy})")
        log(f"  before: kills={before['kills']} mana={before['mana']} casts={before['casts_total']} 敌数={len(before['enemies'])}")
        log(f"  after : kills={after['kills']} mana={after['mana']} casts={after['casts_total']} 敌数={len(after['enemies'])}")
    elif step == "snapshot":
        s = read_state()
        log(f"[snap] t={s['elapsed']}s score={s['score']} kills={s['kills']} hp={s['ward_hp']} mana={s['mana']} "
            f"casts={s['casts_total']} fizzle={s['fizzle']} 敌数={len(s['enemies'])} over={s['is_over']} 敌人={s['enemies']}")
    elif step == "slash_drag":
        # 对角拖拽 → 斜线符 → 风刃（从底部中射向锚点方向）
        s = read_state()
        before = s
        x1, y1 = to_screen(300, 700)
        x2, y2 = to_screen(900, 250)
        drive("drag", x=x1, y=y1, x2=x2, y2=y2)
        time.sleep(1.5)
        after = read_state()
        log(f"[slash_drag] 屏({x1},{y1})->({x2},{y2})")
        log(f"  before: casts={before['casts_total']} fizzle={before['fizzle']} kills={before['kills']}")
        log(f"  after : casts={after['casts_total']} fizzle={after['fizzle']} kills={after['kills']} fsm={after['fsm']}")
    elif step == "key":
        k = sys.argv[2]
        drive("key", key=k)
        time.sleep(0.8)
        s = read_state()
        log(f"[key {k}] t={s['elapsed']}s score={s['score']} hp={s['ward_hp']} over={s['is_over']} 敌数={len(s['enemies'])}")
    elif step == "wait":
        secs = float(sys.argv[2])
        time.sleep(secs)
        s = read_state()
        log(f"[wait {secs}s] t={s['elapsed']}s hp={s['ward_hp']} score={s['score']} 敌数={len(s['enemies'])} over={s['is_over']}")


if __name__ == "__main__":
    main()
