@echo off
REM 等待 TgNAS 启动完毕后，自动将 WebDAV 映射为 Z: 盘

echo Waiting for TgNAS...
:wait
timeout /t 5 /nobreak >nul
REM 请注意替换下方的 admin:password 为你自己的真实 WebDAV 账户密码（如果不使用 WebDAV 则无需理会）
curl -s -o NUL -w "%%{http_code}" -u admin:password http://127.0.0.1:9000/dav/ | findstr "207" >nul
if errorlevel 1 goto wait

echo TgNAS ready, mounting Z:...
set CACHE_DIR=%USERPROFILE%\.tgnas-cache
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

REM 注意：需要在 rclone config 中提前配置好名为 TG_NAS 的 Remote
rclone mount TG_NAS: Z: --vfs-cache-mode full --cache-dir "%CACHE_DIR%" --dir-cache-time 1h --poll-interval 30s --log-level INFO
