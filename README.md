# 视频下载 skill

把视频链接丢给 AI，自动下载最高画质版本。

这个仓库是给**别人的 AI 读的**。你把链接发给 AI 时，它读 `SKILL.md` 就知道该怎么调 `ttdl.sh`。

## 给 AI 的入口

👉 **[SKILL.md](SKILL.md)**

如果你的 AI 支持 skill 目录（如 OpenClaw、Claude Code），把整个仓库放进 skills 目录即可。
如果只是普通对话，把 `SKILL.md` 的内容贴给它，或者直接让它读这个 GitHub 页面。

## 给人看的部分

### 你需要装什么

```bash
# macOS
brew install yt-dlp ffmpeg

# Ubuntu / Debian
pipx install yt-dlp && sudo apt install ffmpeg

# Windows（PowerShell）
winget install yt-dlp.yt-dlp ffmpeg
```

至少要有 `yt-dlp`，`ffmpeg` 可选。

### 怎么用

```bash
bash ttdl.sh "https://www.tiktok.com/@someone/video/123456"
```

一次多条：

```bash
bash ttdl.sh "链接1" "链接2" "链接3"
```

自定义保存位置：

```bash
TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"
```

走代理（TikTok 在部分地区需要）：

```bash
TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"
```

### 下载到哪

默认 `~/Videos/搬运/`，文件名是 `作者_视频ID.mp4`，同时维护一份 `素材表.csv` 记录时间、作者、分辨率。

## 三个容易踩的坑（脚本里已经处理了）

**1. 画质差不是下载的问题**
很多下载工具的默认档位只有 540p。这个脚本用 `yt-dlp -S res,br` 直接选最高档，TikTok 通常能拿到 1080p。

但如果作者上传时自己就压成了 540p，任何工具都提不上来。用 `yt-dlp -F "链接"` 看全部档位就知道了。

**2. CDN 会中途断流**
`[SSL: UNEXPECTED_EOF_WHILE_READING]` 很常见。yt-dlp 自带的 `--retries` 都在同一条坏连接上重试，没用。脚本外层包了 3 轮完整重下。

**3. 文件已存在会静默跳过**
yt-dlp 不报错，直接用旧的。脚本下载前先删。

## 边界

- 不绕平台原创检测、不改视频指纹
- 只处理你明确给的链接，不批量爬账号
- 版权归原作者，商用需授权

## License

MIT
