# 视频下载 skill

把视频链接丢给 AI，自动下载最高画质版本。

这个仓库是给**别人的 AI 读的**。你把链接发给 AI 时，它读 [`SKILL.md`](SKILL.md) 就知道该怎么调 `ttdl.sh`。

## 一键安装（推荐）

```bash
git clone https://github.com/Rooney126/video-download-skill.git
cd video-download-skill
bash install.sh
```

`install.sh` 会做三件事：检测已装了什么 → 缺的按你的系统自动装（会先问你）→ 跑一遍自检确认能用。

**不想跑脚本？** 手动版在下面。

## 手动安装

### 第 1 步：装 yt-dlp（必需）

| 系统 | 命令 |
|---|---|
| macOS | `brew install yt-dlp` |
| Ubuntu / Debian | `pipx install yt-dlp` |
| Windows | `winget install yt-dlp.yt-dlp` |
| 任意系统（有 Python） | `pip install --user -U yt-dlp` |

没装 `pipx`？先 `brew install pipx` 或 `sudo apt install pipx && pipx ensurepath`。

### 第 2 步：装 node（强烈推荐）

**不装 node 会怎样**：能下，但画质可能不是最高。

原因：TikTok 网页有一套 JS 挑战，yt-dlp 需要 JS 运行时解开它，才能直接取到 TikTok 的原始流。没有 node 时 yt-dlp 会报 `Unexpected response from webpage request`，只能退回第三方解析接口——回退通常也能拿到 1080p，但**码率是否低于原片、低多少，我没能稳定测出来**。装 node 的作用是让 yt-dlp 走通原生路径。

```bash
macOS:   brew install node
Ubuntu:  sudo apt install nodejs
Windows: winget install OpenJS.NodeJS.LTS
```

### 第 3 步：装 ffmpeg（推荐）

用于显示下载后的分辨率，以及把高画质音视频流合流。

```bash
macOS:   brew install ffmpeg
Ubuntu:  sudo apt install ffmpeg
Windows: winget install Gyan.FFmpeg
```

### 第 4 步：验证

```bash
bash test.sh        # 11 项自检
bash ttdl.sh "https://www.tiktok.com/@someone/video/123456"
```

## 依赖清单速查

| 依赖 | 必需性 | 缺了会怎样 |
|---|---|---|
| **yt-dlp** | ⚠️ **必需** | 脚本直接退出并提示安装 |
| node | 推荐 | TikTok 走回退接口，画质/码率可能不最优 |
| ffmpeg / ffprobe | 推荐 | 不显示分辨率；高画质合流可能受影响 |
| jq 或 python3 | 可选 | 二者都缺时用内置 grep 兜底解析回退 JSON |

## 用法

```bash
bash ttdl.sh "链接"
bash ttdl.sh "链接1" "链接2" "链接3"        # 批量
TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"   # 自定义目录
TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"  # 走代理
```

默认存到 `~/Videos/搬运/`，文件名 `作者_视频ID.mp4`，同时维护 `素材表.csv`。

## 三个容易踩的坑（脚本已处理）

**1. 画质差多半不是下载的问题**
很多工具默认只取 540p。这个脚本用 `yt-dlp -S res,br` 直接选最高档。但如果作者上传时就压成 540p，任何工具都提不上来 —— 用 `yt-dlp -F "链接"` 能看到全部档位。

**2. CDN 会中途断流**
`[SSL: UNEXPECTED_EOF_WHILE_READING]` 很常见。yt-dlp 自带的 `--retries` 全挂在同一条坏连接上重试，没用。脚本外层包了 3 轮完整重下。

**3. 文件已存在会静默跳过**
yt-dlp 不报错，直接用旧的。脚本下载前先删。

## 边界

- 不绕平台原创检测、不改视频指纹
- 只处理你明确给的链接，不批量爬账号
- 版权归原作者，商用需授权

## License

MIT
