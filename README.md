# 视频下载 skill

把视频链接丢给 AI，自动下载最高画质版本。

## ⚠️ 先看这个：必须要代理

**在中国大陆直连 TikTok / YouTube 都返回 `000`，走不通。** 实测（2026-11-27）：

```
tiktok_direct=000
youtube_direct=000
```

所以用这个工具的前提是：**你有一个能用的代理**。没代理的话装完了也下不了，先别浪费时间。

代理要求：

- **地址**：常见 `http://127.0.0.1:7890`（Clash）/ `7897`（Clash Verge）
- **TikTok 出口不能是香港**——香港 IP 常被 TikTok 拒绝，换日本 / 新加坡 / 美国
- YouTube 对地区不敏感

用法：`TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"`

自测代理是否可用：

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 8 -x http://127.0.0.1:7890 https://www.tiktok.com/
# 200/302 = 能用， 000 = 不通
```

---

这个仓库是给**别人的 AI 读的**。你把链接发给 AI 时，它读 [`SKILL.md`](SKILL.md) 就知道该怎么调 `ttdl.sh`。

## 一键安装（推荐）

```bash
git clone https://github.com/Rooney126/video-download-skill.git
cd video-download-skill
bash install.sh
```

`install.sh` 做三件事：检测已装了什么 → 缺的按你的系统装（终端里会先问你）→ 跑一遍自检。

**让 AI 装就不用问**，加 `--yes`：

```bash
bash install.sh --yes
```

它只在能识别包管理器（brew / apt / winget）时才执行；识别不出系统时只打印建议，不会乱跑命令。

**需要 sudo 但没免密、或公司机器禁止安装**时，让 AI 转人工装 yt-dlp，其余照常。

**不想跑脚本？** 手动版在下面。

## 手动安装

### 第 1 步：装 yt-dlp（必需）

| 系统 | 命令 | 要管理员权限吗 |
|---|---|---|
| Windows | `winget install yt-dlp.yt-dlp` | **不用**，装到用户目录 |
| macOS | `brew install yt-dlp` | 不用（但有首次编译耗时） |
| Ubuntu / Debian | `pipx install yt-dlp` | 装 pipx 那步要 sudo |
| 任意系统（有 Python） | `pip install --user -U yt-dlp` | **不用** |

**装完一定要确认版本够新：**

```bash
yt-dlp --version
```

和 https://github.com/yt-dlp/yt-dlp/releases/latest 比一下。**版本旧会让 TikTok 全线失败**，症状是 `Unexpected response from webpage request`，然后脚本退回低画质接口——你只会看到「画质变差」，看不出原因。

更新：`yt-dlp -U`（pip 装的用 `pip install --user -U yt-dlp`）。

<details><summary>Windows 上 winget 可能遇到的两个坑（实测）</summary>

**① `winget` 命令找不到**
Windows 10 常见。用全路径调用：
```powershell
& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install yt-dlp.yt-dlp
```
在 WSL 里通过 cmd 调会因中文路径乱码失败，直接开 PowerShell 跑就行。

**② 本机可能已有 Python 版 yt-dlp**
如果之前用 pip 装过，`yt-dlp` 可能指向 `AppData\Local\Programs\Python\Python310\Scripts\yt-dlp.exe`，和 winget 装的是两份。先用 `Get-Command yt-dlp` 看清楚指向哪，别装重复了还以为是新的。

</details>

没装 `pipx`？先 `brew install pipx` 或 `sudo apt install pipx && pipx ensurepath`。

### 第 2 步：装 node（下 YouTube 必须装）

**分平台看**：

| 平台 | 要 node 吗 | 要 ffmpeg 吗 |
|---|---|---|
| TikTok | 不需要 | 不需要 |
| YouTube | **必须** | **必须** |

不装的话 YouTube 只能拿到 360p 成品流（日志会说 `No supported JavaScript runtime could be found`）。TikTok 不受影响。

**为什么**：

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

## 各平台能力

| 平台 | 最高分辨率 | 需要代理 | 需要 node+ffmpeg | 备注 |
|---|---|---|---|---|
| TikTok | 1080p（`bytevc1` H.265 码率更高） | ✅ 要，且出口非香港 | 不需要 | 单文件流，无需合流 |
| YouTube | **1080p 默认，可开到 4K** | ✅ 要 | **需要** | `TTDL_MAX_RES=2160` 开 4K |
| Instagram | 下不了 | — | — | 需登录 cookie，未内置 |

**代理出口实测（2026-11-27）**：`loc=JP` 可正常下载；香港节点常被 TikTok 拒绝。直连（无代理）时 TikTok 与 YouTube 均返回 `000`，走不通。

`TTDL_MAX_RES` 控制分辨率上限，默认 `1080`：

```bash
TTDL_MAX_RES=2160 bash ttdl.sh "https://www.youtube.com/watch?v=xxx"   # 4K
```

## 用法

```bash
bash ttdl.sh "链接"
bash ttdl.sh "链接1" "链接2" "链接3"        # 批量
TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"   # 自定义目录
TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"  # 走代理
```

默认存到 `~/Videos/搬运/`，文件名 `作者_视频ID.mp4`，同时维护 `素材表.csv`。

## 代理选哪个地区

TikTok 对部分地区出口 IP 会直接拒绝，症状是 `Unexpected response from webpage request`。

| 出口 | 结果 |
|---|---|
| 日本 | ✅ 实测可直连（2026-11-27，`loc=JP`） |
| 新加坡 / 美国 | 一般可用 |
| 香港 | ⚠️ 常被拒，优先换 |
| 中国大陆 | ❌ 必须走代理 |

脚本在下载失败时会打印当前出口地区，例如：

```
当前代理出口: HK
→ 香港出口常被 TikTok 拒绝，换日本/新加坡/美国节点重试
```

**区分地域问题和版本问题**：换个节点能好 → 地域；换节点也不行且 `yt-dlp --version` 偏旧 → 版本。

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
