# TgNAS 项目排障指南

本文档记录了在搭建与使用 TgNAS 架构期间遇到的各类异常问题及其解决方案。

## 问题记录与解决方案

### 问题一：上传大文件时报 `502 Bad Gateway`
- **现象**：通过 rclone copy 复制文件到云端时，TgNAS 报错 502。
- **根本原因**：`telegram-bot-api` 运行在 Docker 内，因为国内网络环境问题，无法直接连通 Telegram 官方服务器。
- **解决方案**：在 `telegram-bot-api` 的 `docker-compose.yml` 中引入了一个基于 `mihomo` (Clash) 的透明代理容器 (Sidecar)。利用 `network_mode: "service:clash"` 让 Bot API 共享代理容器的网络命名空间，实现了该模块对墙外网络的无缝访问。

### 问题二：连接本地 API 被代理劫持 (路由死循环)
- **现象**：当 TgNAS 尝试请求 `http://host.docker.internal:8081` 时卡死或报错。
- **根本原因**：TgNAS 继承了系统的代理环境变量，导致本来应当发往宿主机的内网请求被错误地路由到了 Windows 主机的代理端口，引发了回环死锁。
- **解决方案**：在 `tgnas` 的环境变量中强行覆盖 `NO_PROXY: "127.0.0.0/8,localhost,host.docker.internal"`，确保内网访问直连。

### 问题三：Rclone 下载文件时瞬间报错 `unexpected EOF` 
- **现象**：上传正常，查看列表正常，但只要尝试下载或打开文件，立刻报错 `unexpected EOF` 或显示“没速度”。
- **根本原因**：在 `--local` 模式下，Bot API 并不会通过 HTTP 提供文件下载，而是直接将文件下载到宿主机数据卷中，并期望客户端通过访问本地文件系统来读取。但 TgNAS 被硬编码为“发送 HTTP GET 请求”去获取文件。因此 TgNAS 发送 HTTP 请求时遇到了 `404 Not Found`，导致数据流中途断开，rclone 报 EOF。
- **解决方案**：在 Bot API 所在的 `docker-compose.yml` 中新增了一个 `nginx` 容器作为文件辅助服务器：
  - 将 `telegram-bot-api-data` 数据卷同样挂载给 nginx。
  - 通过正则匹配拦截 TgNAS 发来的 `/file/bot<token>/...` 下载请求，并映射到本地硬盘文件直接返回。
  - 将其它请求通过代理转发给本地 Bot API。
  - 在 TgNAS 侧将 `api_base_url` 从原先的 `8081` 更改为 nginx 监听的 `8082` 端口，完美打通下载链路。

### 问题四：大体积多媒体文件下载失败 (开启真·本地模式与 Nginx 绝对路径冲突)
- **现象**：虽然之前通过 Nginx 解决了小文件下载问题，但在尝试下载大于 20MB 的媒体文件（如 70MB 的 .wav 音频）时，再次报错 `unexpected EOF`。查阅日志发现 Bot API 抛出 `Bad Request: file is too big` 异常。
- **根本原因**：
  - `aiogram/telegram-bot-api` Docker 容器的启动脚本完全忽略了我们在 `docker-compose.yml` 中注入的 `command: ["--local"]` 参数。由于缺失 `--local` 标志，Bot API 一直以受限的“云端模式”运行。云端模式下，强制限制单次 `getFile` 接口可获取的文件最大不能超过 20MB。
  - 当我们修正为使用容器专用的环境变量 `TELEGRAM_LOCAL: "1"` 开启真·本地模式后，Bot API 成功解锁了 2000MB 的大文件限制。但开启真本地模式后，Bot API 返回的 `file_path` 格式发生了改变——从相对路径变成了以 `/var/lib/...` 开头的绝对路径。
  - 绝对路径与我们之前的 Nginx 正则匹配规则 (`location ~ ^/file/bot([^/]+)/(.*)$`) 发生重叠，导致被解析成 `/var/lib/telegram-bot-api/<token>/var/lib/...` 的错误死循环路径，再次引发 404。
- **解决方案**：
  - 将 `telegram-bot-api` 的 `docker-compose.yml` 中的配置项从 `command` 变更为 `environment: TELEGRAM_LOCAL: "1"`。
  - 针对真·本地模式修改 Nginx 规则，新增 `location ~ ^/file/bot([^/]+)/var/lib/telegram-bot-api/(.*)$`，以专门捕获并妥善剥离绝对路径前缀，打通大文件代理。

### 问题五：大文件上传报错 500 Internal Error (Nginx 限制了请求体大小)
- **现象**：开启 Nginx 代理后，通过 rclone 拖入大于 1MB 的大文件时报错 `StatusCode: 500`。
- **根本原因**：我们将 TgNAS 的接口目标从 `8081` (Bot API) 切换到了 `8082` (Nginx) 后，由于 Nginx 默认有非常严格的上传限制（`client_max_body_size` 默认 1MB）。当 TgNAS 尝试 POST 一个大文件给 Nginx 时，还没等转发到后端的 Bot API，Nginx 就直接拦下并返回了 HTTP 413 Payload Too Large。TgNAS 接收到 413 后崩溃，继而向 rclone 返回 500。
- **解决方案**：在 Nginx 的配置文件 `default.conf` 的 `server` 块中加入 `client_max_body_size 0;` 以关闭上传体积限制，让大体积请求顺利抵达后台的 Bot API。

### 问题六：Rclone 开机自动挂载与黑框隐藏
- **现象**：直接运行 `rclone mount` 会始终占用一个黑色命令行窗口。
- **解决方案**：编写了专用的挂载脚本 `start_mount.bat`，内含针对大文件读取优化的高级缓存参数（`--vfs-cache-mode full --vfs-read-chunk-size 16M`）。随后利用 VBS 脚本 `tgnas_mount.vbs` 放入 Windows 的“启动”文件夹（Startup Folder）中，实现开机后完全无感知的后台静默挂载。

### 问题七：大文件上传时被错误地切碎为 5MB 的小片段
- **现象**：如果使用 S3 协议挂载盘的方案时向 Z 盘拖入大文件，文件会被自动切割成数十个 5MB 的碎片进行上传。
- **根本原因**：`rclone` 在默认处理 S3 协议的大文件时，为了适应普通的 S3 后端限制，默认启用了分片上传（Multipart Upload），并将默认分片大小（`chunk_size`）硬编码设定为 5MB。这导致原本可以一口气发给本地 Telegram Bot API 的文件被 rclone 在源头就切碎了。
- **设计决策与解决方案**：本方案**默认使用 S3 协议，并明确禁用了 S3 的分片上传功能**。我们修改了挂载脚本 `start_mount.bat`，在参数中加入了 `--s3-upload-cutoff 2000M --s3-chunk-size 2000M`。
  - **为何这么做（完整性优先）**：强制一律完整传输，是为了**保证群组内文件的原生完整性**，确保文件进入 Telegram 后仍然是个完整的媒体实体，供你在移动端直接原画播放或无损转发给他人。
  - **副作用警告（非最优设置）**：必须指出，这种“不分片”策略**并非传输层面的最优设置**。由于超大文件需要一口气跑完，如果上传过程中遇到网络闪断，底层将无法进行断点续传，只能从 0% 重新传起。

### 问题八：大文件上传时无限循环重发，无法停止
- **现象**：上传大文件时，文件被完整上传，但在结束后它不会停下，而是会永远在后台一遍遍重新发送相同的文件。
- **根本原因**：由于是百兆大文件，本地 Bot API 上传至 Telegram 服务器的过程极其耗时（通常超过 1 分钟）。
  - `TgNAS` 默认硬编码了 30秒 的 Telegram API 调用超时时间。
  - `Nginx` 代理层默认的代理读写超时（`proxy_read_timeout`）是 60秒。
    这导致上传耗时一长，网关和代理就会掐断连接并报错。当 `rclone` 收到前端传来的错误后，便会忠实地开启“错误重试”流程，重新上传一遍文件；而后台其实并未停止上传，导致触发了无限套娃的重复上传。
- **解决方案**：
  - 在 `./tgnas/data/config.yaml` 中新增了 `timeout: 3600s` 强制将 TgNAS 调用超时时间延长至 1 小时。
  - 在 Nginx 的 `default.conf` 中追加了 `proxy_read_timeout 3600; proxy_send_timeout 3600; proxy_connect_timeout 3600;` 允许超长持久连接。
  - 在 TgNAS 的配置文件中将 `type_size_limits`（各类文件大小限制）统一写死到 2000MB，防止后端自作主张发起分片干预。

### 问题九：特定格式文件（如 MP3）上传时报错 500 (telegram upload response missing document)
- **现象**：大部分文件都能正常上传，但当上传 `.mp3` 或部分特定格式文件时，rclone 报错 `StatusCode: 500, api error InternalError: We encountered an internal error.`
- **根本原因**：
  - Telegram Bot API 拥有自动的媒体识别机制。当 TgNAS 通过 `sendDocument` 接口发送 MP3 等媒体文件时，Telegram 服务器会识别其格式，并在返回的 JSON 响应中将其强制放在 `audio` （或 `video`）字段中，而不是预期的 `document` 字段。
  - 之前的 `tgnas` 核心代码严格期望返回 `document` 字段。一旦找不到，就会抛出 `telegram upload response missing document`，最终引发 500 错误。
  - 虽然本地仓库（`repo/telegram/client.go`）已经被修改，加入了针对 Telegram 转换文档格式的 Fallback 兼容逻辑，且镜像已经重新 `docker build`，**但由于未执行 `docker-compose up -d`，旧的容器并未被替换**。
- **解决方案**：
  在 `./tgnas` 目录下执行 `docker-compose up -d` 重新创建 `tgnas` 容器。这不仅应用了修复 `mp3` 上传的 Fallback 补丁，同时也应用了针对超大文件上传的流式内存优化（`io.TeeReader`）。

### 问题十：含有日文等特殊字符的文件上传时报 403 SignatureDoesNotMatch
- **现象**：大部分英文文件上传正常，但在上传带有特殊字符或非英文字符的文件时，rclone 会在重试 3 次后彻底报错 `403 SignatureDoesNotMatch`。
- **根本原因**：
  在 `tgnas` 内置的 S3 兼容 API 中计算 AWS v4 鉴权签名（SigV4）时，代码错误地读取了已经过 URL 编码的 `u.EscapedPath()`，并再次将其送入自建的 `sigV4Encode` 函数。这导致形如 `%E3` 的已被编码过的字符中的 `%` 号，被第二次编码成了 `%25E3`。
  因为 rclone 客户端计算签名时使用的是正确的单次编码 URI，而 `tgnas` 服务端计算签名时由于“双重编码”得出了错误的 URI，两端的签名 Hash 就对不上了，最终鉴权失败返回 403。
- **解决方案**：
  修改了 `./tgnas/repo/internal/s3api/sigv4.go` 中的 `canonicalURI` 函数，将读取路径的方式从 `u.EscapedPath()` 更改为未编码的 `u.Path`。随后重新执行 `docker build -t tgnas:local .` 并 `docker-compose up -d` 重启容器。此后特殊字符文件均可顺利通过签名验证并上传。

### 问题十一：挂载盘中移动/重命名文件报错 `deserialization failed, received empty response payload`
- **现象**：在挂载盘中重命名或移动文件（特别是 `MobileUploads` 文件夹下的文件）时，出现 `Dir.Rename error: operation error S3: CopyObject... deserialization failed, received empty response payload` 错误。文件移动失败。
- **根本原因**：Rclone (S3 客户端) 移动文件依赖 S3 的 `CopyObject` API。当客户端发起携带 `x-amz-copy-source` 的 PUT 请求时，旧版的 TgNAS 没有处理该 header，而是将其当成了 0 字节的普通文件上传，返回 HTTP 200 及空内容。这导致 Rclone 无法解析出预期的 XML `CopyObjectResult` 从而报错拦截了移动。
- **解决方案**：在 `internal/s3api/server.go` 的 `putObject` 函数中，拦截提取 `X-Amz-Copy-Source` 请求头，并手动执行底层的 `store.CopyObject()`。最后按照标准 S3 API 构造并返回了 `CopyObjectResultXML`。

### 附录：含有 `~` 或特殊日文字符的文件显示异常/消失
- **现象**：当文件名内存在 `~` 符号，或包含日文全角空格时，文件可能在 Z 盘不可见，或者其中的空格被显示成了 `u3000`。
- **根本原因**：这是 Windows 系统的祖传规范与 WinFsp (rclone 虚拟驱动) 的互相妥协。Windows 严禁文件名以空格结尾，且有时会将包含 `~` 的长文件名误认为是 DOS 时代的 8.3 短文件格式（如 `PROGRA~1`）。WinFsp 为了防止 Windows 崩溃，会自动将非法尾随空格转换为全角的 Unicode 占位符 `\u3000`，而遇到 `~` 无法解析时，Windows 资源管理器会出于安全考虑直接把文件隐藏。
- **解决方案**：属于虚拟磁盘机制和操作系统的设计限制。只需要避免文件末尾带空格或避免滥用特殊控制符，即可和平共处。
