@echo off
rem 手势识别服务（PC 端启动器）。连接游戏端（树莓派/本机）的 WebSocket 服务端。
rem 用法: run_tracker_server.bat [游戏端WS地址] [手数]
rem   默认 ws://192.168.0.116:9870 单手；例: run_tracker_server.bat ws://192.168.0.116:9870 2
setlocal
set GODOT=E:\godot\tools\godot461\Godot_v4.6.1-stable_win64_console.exe
if not exist "%GODOT%" (
  echo 找不到 Godot: %GODOT%
  echo 改本文件里的 GODOT 路径，或从 godot-builds 4.6.1-stable 下载 win64 版解压到该目录
  exit /b 1
)
set URL=%1
if "%URL%"=="" set URL=ws://192.168.0.116:9870
set HANDS=%2
if "%HANDS%"=="" set HANDS=1
"%GODOT%" --headless --path "%~dp0." -s tools/tracker_service.gd -- --url=%URL% --max-hands=%HANDS%
