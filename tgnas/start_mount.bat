@echo off
set HTTP_PROXY=
set HTTPS_PROXY=
set CACHE_DIR=%USERPROFILE%\.tgnas-cache
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

REM 注意：需要在 rclone config 中提前配置好名为 TG_NAS_S3 的 Remote
rclone mount TG_NAS_S3:tgnas Z: --network-mode --volname "TgNAS Cloud" --cache-dir "%CACHE_DIR%" --vfs-cache-mode full --vfs-cache-max-age 1h --dir-cache-time 5m --vfs-read-chunk-size 16M --vfs-read-chunk-size-limit 1G --s3-upload-cutoff 2000M --s3-chunk-size 2000M --no-modtime --no-console
