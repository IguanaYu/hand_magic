"""假 rpicam-vid：往 8899 端口循环推 MJPEG 帧，用于在 Windows 上本地复现/联调
rpicam 识别路径（无需树莓派）。用法：python fake_mjpeg_server.py [帧间隔ms]"""
import socket
import threading
import time
import sys
import os

PORT = 8899
FRAME = os.path.join(os.environ.get("TEMP", "/tmp"), "fake_frame.jpg")
INTERVAL = float(sys.argv[1]) / 1000.0 if len(sys.argv) > 1 else 0.033

with open(FRAME, "rb") as f:
    jpeg = f.read()
print(f"[fake-mjpeg] {FRAME} ({len(jpeg)}B) -> tcp://127.0.0.1:{PORT} @{1000*INTERVAL:.0f}ms")

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(2)
print("[fake-mjpeg] listening")


def serve(conn, addr):
    print(f"[fake-mjpeg] client {addr} connected")
    n = 0
    try:
        while True:
            conn.sendall(jpeg)
            n += 1
            if n % 300 == 0:
                print(f"[fake-mjpeg] sent {n} frames")
            time.sleep(INTERVAL)
    except OSError:
        pass
    print(f"[fake-mjpeg] client {addr} gone after {n} frames")


while True:
    conn, addr = srv.accept()
    threading.Thread(target=serve, args=(conn, addr), daemon=True).start()
