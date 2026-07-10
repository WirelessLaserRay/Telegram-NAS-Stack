# Telegram NAS Stack (TgNAS 一键化开源部署方案)

## 📖 项目简介
基于 [tgnas](https://github.com/aahl/tgnas) 的全功能增强一键化部署栈。本项目彻底打通了 Telegram 官方 Local Bot API 与代理网络，并修复了基于 WebDAV/S3 挂载协议下读取 2GB 大文件无法进行流式 Range 跳转、下载报 `unexpected EOF`、上传分片异常等各类底层痛点。它能够将你的 Telegram 变成一个真正的本地无限制、无限容量的虚拟网盘（映射为 Z盘）。

## ✨ 核心特性
- ☁️ **无限容量**：基于 Telegram 的无限云存储能力。
- 🚀 **超大文件支持**：解锁 2000MB (2GB) 以内的单文件无损、无分片直传（如果挂载的机器人账号有 Premium 可达 4GB）。
- 🎬 **真正的流式媒体播放**：内嵌 Nginx 直连文件代理流，完美解决 Rclone/WebDAV 挂载大视频文件拖拽导致的本地缓存卡死和 `404/EOF` 断流问题。
- 🌐 **网络隔离与透明代理**：内建基于 Mihomo (Clash) 的网络共享容器，解决国内网络无法连接 Telegram 服务器，以及代理回环死锁问题。
- 📱 **移动端无缝同步**：搭载 `tgnas-sync` 旁路监听脚本，手机向指定的 Telegram 群聊发送文件，挂载盘瞬间同步可见。
- 🪟 **Windows 无感挂载**：提供预设了最佳缓存参数的 `rclone` 挂载脚本，实现原生体验。

## 🏗️ 核心架构
本项目包含两个主要的 Docker 栈集群：
1. `telegram-bot-api` 集群：
   - **Clash (Mihomo)**: 提供底层透明网络代理。
   - **Local Bot API**: Telegram 官方本地网关容器（解锁 50MB/20MB 收发限制）。
   - **Nginx**: 文件流网关。将原本 TgNAS 触发的 HTTP 请求强制劫持重定向至宿主机映射的数据卷本地文件，解决大文件下载报 404 的问题。
2. `tgnas` 集群：
   - **TgNAS 服务端**: 处理文件分片逻辑、提供 S3 / WebDAV API。
   - **TgNAS Sync**: Python 旁路脚本，轮询拉取聊天记录并向 SQLite 数据库中写入元数据，实现移动端直传。

## 📂 项目文件目录说明
```text
📦 TgNAS-OpenSource-Stack
 ┣ 📂 telegram-bot-api/             # Bot API 代理集群目录
 ┃ ┣ 📜 docker-compose.yml        # 启动 Local Bot API、Clash 与 Nginx 的编排文件
 ┃ ┗ 📜 clash-proxy.yaml          # 透明代理配置文件（按需修改节点）
 ┣ 📂 tgnas/                        # TgNAS 核心服务集群目录
 ┃ ┣ 📂 repo/                       # TgNAS 核心后端代码 (⭐基于开源项目 aahl/tgnas 深度修改编译)
 ┃ ┣ 📜 docker-compose.yml        # 启动 TgNAS 与同步脚本的编排文件
 ┃ ┣ 📜 sync_mobile.py            # 移动端消息旁路同步的 Python 脚本
 ┃ ┣ 📜 start_mount.bat           # (推荐) S3 协议强制不分片一键挂载脚本
 ┃ ┣ 📜 mount-z.bat               # WebDAV 协议备用挂载脚本
 ┃ ┣ 📜 tgnas_mount.vbs           # Windows 后台静默执行挂载的 VBS 脚本
 ┃ ┗ 📜 .env.example              # 环境变量模板文件
 ┣ 📂 web-ui/                       # 可视化部署向导的 Web 前端与本地服务脚本
 ┣ 📜 一键自动化部署.bat            # Windows 桌面一键安装部署入口 (⭐Beta / 待测试)
 ┣ 📜 Troubleshooting.md            # 项目原理解析与常见报错排障指南
 ┗ 📜 README.md                     # 本说明文档
```

---

## 🚀 部署指南

### 1. 前置准备
- 操作系统安装了 **Docker Desktop** (支持 WSL2)。
- 安装了 **Rclone** 并且已配置到系统环境变量 (`PATH`) 中。
- 安装了 **WinFsp** (Windows File System Proxy)，Rclone 挂载必备。
- 准备好一个 Telegram Bot 的 `Token`、你的 Telegram `API ID` 与 `API HASH`、以及作为存储后端的群组或频道的 `Chat ID`。

### 2. 自动化安装向导 (⭐推荐, Beta待测试)
如果你使用的是 Windows 环境，我们提供了一个无缝的图形化配置前端：
1. 请先修改 `telegram-bot-api/clash-proxy.yaml`，填入你自己可用的节点/订阅信息。
2. 双击运行项目根目录下的 **`一键自动化部署.bat`**。
3. 按照弹出的 Web UI 向导填入你的 API ID、密钥和代理信息，点击“一键部署”即可自动拉起所有服务！

### 3. 手动部署流程
如果你不使用 Windows 或者更倾向于极客风格的手动配置，请按以下步骤启动：

首先启动底层支持服务（Bot API + 代理）：
```bash
cd telegram-bot-api
```
- 请修改 `clash-proxy.yaml`，填入你自己可用的节点/订阅信息。
- 如果不使用 Web UI，请在当前目录创建 `.env` 文件并填入：
  - `TELEGRAM_API_ID`
  - `TELEGRAM_API_HASH`
```bash
docker-compose up -d
cd ..
```

### 3. 配置与启动 TgNAS 服务栈
接下来启动核心存储服务：
```bash
cd tgnas
cp .env.example .env
```
- 打开 `.env` 文件，填入你的 `TGNAS_SECRET_KEY` (自定义一个 S3 密钥)、`TGNAS_TELEGRAM_BOT_TOKEN` 和 `TGNAS_TELEGRAM_CHAT_ID`。
- **注意代理设置**：`docker-compose.yml` 中 `tgnas` 与 `tgnas-sync` 服务目前默认指向宿主机 `http://host.docker.internal:7890` 的系统代理（如你在宿主机运行了 Clash for Windows）。请根据你宿主机的真实代理端口进行修改。

```bash
docker-compose up -d --build
```

### 4. Rclone 配置与一键挂载 (Windows)
在运行挂载脚本前，你需要确保在你的 Rclone 配置（`rclone config`）中添加了名为 `TG_NAS_S3` 的 Remote。你可以手动编辑 `%APPDATA%\rclone\rclone.conf`，追加以下内容：

```ini
[TG_NAS_S3]
type = s3
provider = Other
access_key_id = admin
secret_access_key = your_secure_s3_secret_here  # 对应你在 .env 中设置的 TGNAS_SECRET_KEY
endpoint = http://127.0.0.1:9000
```

配置完毕后，我们提供了两种挂载方式的测试脚本：
1. `mount-z.bat`：基于 WebDAV 协议测试挂载（需手动修改文件内的密码）。
2. `start_mount.bat`：基于 S3 协议进行优化的正式挂载方案（推荐默认使用）。

> **💡 重要设计说明：为什么默认使用 S3 并禁用分片上传？**
> 本项目在 `start_mount.bat` 中通过 `--s3-upload-cutoff 2000M` 参数特意**禁用了大文件分片**。此举是为了**绝对保证存储在 Telegram 群组中文件的原生完整性**，使你能在手机上直接预览、播放或转发。
> 但请注意，**这并非网络传输性能的最优设置**。关闭分片后，如果上传 1GB 文件时网络断开，该文件不支持断点续传，将触发重试机制从 0% 重新上传。

右键管理员运行 `start_mount.bat` 后，你的系统中将出现 `Z:` 盘！如果希望开机静默运行无黑框，可使用 `tgnas_mount.vbs` 脚本并将其放入系统启动文件夹。

---

## ⚠️ 隐私与安全须知
- **数据透明性**：所有上传到挂载盘的文件，最终都会作为实体文件以消息的形式发送至你配置的 Telegram Chat 中。**这些文件并没有端到端加密**（除非你自己挂载时套了一层 Rclone Crypt 协议），Telegram 官方以及群组管理员均可查看。
- **凭据保护**：妥善保管你的 `Bot Token` 和 `API ID`。
- **敏感字符**：如果含有日文或 `~` 等特殊字符的文件无法上传或消失，请参考 [TgNAS 构建与排障指南](./Troubleshooting.md)。

## 📚 详细技术原理与排障
如果你在部署中遇到了 500、502、或者 `unexpected EOF` 等网络与代理错误，请务必仔细阅读根目录下的 [Troubleshooting.md](./Troubleshooting.md)。这篇文档记录了所有底层改造的原理和避坑指南。

---

## 🙏 鸣谢与开源组件引用
本项目的成功搭建与核心功能实现，深度依赖并参考了以下优秀的开源项目与组件，特此鸣谢：

1. **[aahl/tgnas](https://github.com/aahl/tgnas)**
   - **用途**：本项目中 `tgnas/repo` 核心后端代码的根源项目。它提供了将 Telegram API 接口映射为标准 S3 / WebDAV 协议的绝佳基础思路。
2. **[telegram-bot-api](https://github.com/tdlib/telegram-bot-api)**
   - **用途**：Telegram 官方提供的开源本地 Bot API 服务器（本项目采用 `aiogram` 维护的 Docker 镜像版）。是突破公有云 Bot API 上传下载体积限制的核心底层依赖。
3. **[Mihomo (原 Clash.Meta)](https://github.com/MetaCubeX/mihomo)**
   - **用途**：作为透明代理容器，负责接管本地网络环境至 Telegram 服务器的数据出海和底层路由。
4. **[Nginx](https://github.com/nginx/nginx)**
   - **用途**：高性能的 Web 反向代理服务器，本项目将其作为网关流代理，巧妙地劫持并处理了大文件的本地流式下载，根除了 404 及 EOF 错误。
5. **[Rclone](https://github.com/rclone/rclone)**
   - **用途**：用于 Windows 一键挂载 S3 / WebDAV 节点的命令行挂载工具，并借用了其优秀的 VFS（虚拟文件系统）缓存机制。
6. **[WinFsp](https://github.com/winfsp/winfsp)**
   - **用途**：Windows 下的开源文件系统代理组件，是 Rclone 实现将云盘模拟为原生 Windows Z盘的必要内核支持。

---

## 📄 协议与声明 (License)
本项目的主体架构代码（包括 Docker 编排、Python 同步脚本、Windows 挂载脚本等）基于 **[MIT License](./LICENSE)** 协议开源。

**⚠️ 特别版权声明**：
本项目中 `tgnas/repo` 目录下的后端核心源代码，是基于原作者 `aahl` 的 [aahl/tgnas](https://github.com/aahl/tgnas) 进行的深度修改与重新编译。该部分代码的底层版权及最终解释权归原作者所有，本项目仅为提供完整部署方案而一并包含。
