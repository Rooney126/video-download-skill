---
name: video-download
description: Download TikTok / YouTube videos at the highest available quality, with a simple ledger. Requires a working proxy in mainland China (direct connections return 000). Use when the user sends a video link and wants it saved, re-uploaded, archived, or reposted (搬运/下载/存下来).
---

# video-download

给一个视频链接，下载最高画质版本并按 `作者_视频ID.mp4` 命名，同时记一行到素材表。

## 读完这个文件，先跟用户说这几句（别直接默默跑）

用户把仓库丢给你，通常还不知道它具体能做什么。**先用一两句说清楚，再动手：**

> 这个工具能把 TikTok / YouTube 的视频下到本地，自动选最高画质，按「作者_视频ID.mp4」命名，并记一份素材表。
> **前提：需要一个可用的代理（中国大陆直连这两个平台都不通）。** 没有代理的话下载会失败。
> 我需要先检查并装好依赖（约 1 分钟），之后你把链接发我就行。

**先把代理情况问清楚，再开始装依赖：**

```bash
# 先测直连行不行
curl -s -o /dev/null -w "%{http_code}" --max-time 8 https://www.tiktok.com/ 2>/dev/null
```

- 返回 `200`/`302` → 能直连，不需要代理
- 返回 `000` → 必须走代理，接着问用户：
  - **有没有代理？地址和端口是多少？**（常见 `http://127.0.0.1:7890` / `7897`）
  - 没有代理 → **直接告诉用户：这个工具在当前网络环境下无法使用，先去弄代理，否则装了也下不了。** 不要把“装完就能用”的错预期给出去。

然后按第 -1 → 第 0 → 第 1 → 第 2 步执行。

**首次使用要说清的三个事实**（避免用户预期错位）：

1. **必须要代理**（在中国大陆）。实测直连 TikTok / YouTube 均返回 `000`。没有可用代理 = 装了也用不了，**这是硬前提，必须在动手前确认**。
2. **TikTok 最高 1080p**，取决于作者上传的源；源是 540p 就提不上去。TikTok 额外要求代理出口**不能是香港**（常被拒），日本/新加坡/美国可用；YouTube 对地区不敏感但要 **node + ffmpeg**。
3. **Instagram 下不了**（需登录 cookie，未内置）。

## 什么时候用

用户消息里出现视频链接（tiktok.com / youtube.com / youtu.be / instagram.com），且语境是「下载 / 存下来 / 搬运 / 搬过来」。

不需要问用户任何问题，直接跑脚本。

## 第 -1 步：先确认 yt-dlp 是新的（最容易忽略的根因）

**yt-dlp 版本过旧会让所有 TikTok 链接统一报 `Unexpected response from webpage request`**，脚本退回低画质第三方接口，用户看到的就是「画质变差了」，但看不出原因。

**根因是版本，不是缺 TikTok 用不着的东西。** 2026-11-27 同机实测：`2026.10.26` 全线失败；升到 `2026.11.23` 后一次成功，且 TikTok 侧 `--no-js-runtimes`（禁用 JS 运行时）下依然拿到 1440×1080 / 1748052bps，与带 node 完全一致。**TikTok 不需要 node，别为了 TikTok 去折腾它。**

但注意：**YouTube 相反，必须要有 node**（见下方依赖表）。平台不同，别一概而论——这是 2026-11-27 踩过的坑，把 TikTok 的结论套到 YouTube 上，结果 YouTube 只能拿 360p。

```bash
yt-dlp --version            # 与 https://github.com/yt-dlp/yt-dlp/releases/latest 对比
yt-dlp -U                   # pip 装的用 pip install --user -U yt-dlp
```

2026-11-27 实测：`2026.10.26` 对 TikTok 全线失败；升到 `2026.11.23` 后同一链接一次成功、拿到原生 1440×1080 最高码率。**这一个月差了一个重要修复。**

脚本会自动判版本新鲜度（超过 60 天提示更新），但**不会阻断**——旧版本仍可退回低画质接口工作。

## 第 0 步：先把脚本拿到本地（最容易漏）

**你（AI）读这个页面时，用户机器上还没有 `ttdl.sh`。** 直接跑 `bash ttdl.sh` 会报 `No such file or directory`。

先确认本地有没有，没有就取：

```bash
# 检查
ls ttdl.sh 2>/dev/null && echo "已有" || echo "需要获取"

# 获取方式一：git（推荐）
git clone https://github.com/Rooney126/video-download-skill.git
cd video-download-skill

# 获取方式二：没有 git 时，只取两个必需文件
mkdir -p video-download-skill && cd video-download-skill
for f in ttdl.sh install.sh; do
  curl -fsSL -o "$f" "https://raw.githubusercontent.com/Rooney126/video-download-skill/main/$f"
done
chmod +x ttdl.sh install.sh
```

> `raw.githubusercontent.com` 在部分地区被墙。若 curl 失败，改用 GitHub API（**已实测，取回文件与仓库字节一致**）：
> ```bash
> for f in ttdl.sh install.sh; do
>   curl -fsSL "https://api.github.com/repos/Rooney126/video-download-skill/contents/$f" \
>     | python3 -c "import json,sys,base64;sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)['content']))" > "$f"
> done
> chmod +x ttdl.sh install.sh
> ```
> 注意：不要用 `grep + base64 -d`，GitHub 返回的 base64 带换行，会解出截断文件（实测踩过）。

获取后 `cd` 进那个目录再继续。

## 第 1 步：检查依赖（别跳过）

```bash
command -v yt-dlp >/dev/null && echo "yt-dlp $(yt-dlp --version)" || echo "缺 yt-dlp"
```

**依赖分三档，缺了行为不同：**

| 依赖 | 必需性 | 缺了会怎样 | 装上能多拿到什么 |
|---|---|---|---|
| **yt-dlp** | **必需** | 脚本直接退出 | — |
| yt-dlp **版本够新** | **必需** | 全部 TikTok 链接失败并退回低画质 | 原生最高档（实测 1748kbps vs 回退 872kbps） |
| node | **TikTok 不需要 / YouTube 必须** | YouTube 拿不到高清档（只有 360p 成品流） | YouTube 高清（1080p+） |
| ffmpeg | **TikTok 不需要 / YouTube 必须** | YouTube 分离流无法合流，退回低清 | YouTube 高画质合流 |
| ffmpeg/ffprobe | 推荐 | 不显示分辨率，高画质合流可能失败 | 分辨率显示 + 音视频合流 |
| jq **或** python3 | 可选 | 用内置 grep 兜底解析 | 解析更稳 |

**缺必需的 yt-dlp 时，不要试图让用户手敲安装命令——直接跑安装脚本：**

```bash
bash install.sh --yes     # AI 无人值守用这个：自动装，不问
bash install.sh           # 人在终端：装前会问 [y/N]
```

它会自动识别系统（macOS / Linux / WSL / Windows），列出缺什么、给出对应安装命令，装完自动跑自检。

**`--yes` 的边界（重要）**：只在**能确定包管理器**时才会真的执行（brew / apt / winget）。识别不出系统时它只打印建议文字，不会乱跑——因为「建议」和「命令」是分开的（`SUGGEST_IS_CMD`）。AI 看到 `上面只是建议文字` 就该转人工，不要硬试。

**装不了的典型情况**：需要 sudo 但无免密、公司机器限制安装、非标准发行版。这时让用户手动装 `yt-dlp`，其余照常。

## 第 2 步：跑下载

```bash
bash ttdl.sh "链接1" "链接2"
```

可选环境变量：

```bash
TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"           # 自定义保存目录（默认 ~/Videos/搬运）
TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"  # 走代理（默认不走）
```

## 代理出口地区也会导致失败

TikTok 对部分地区出口 IP 会直接拒绝，症状与「版本旧」完全一样：`Unexpected response from webpage request`。

**诊断顺序（先便宜后贵）：**

1. 看脚本打印的 `当前代理出口: XX`（回退时自动输出）
2. `HK` → 香港节点常被拒，换日本 / 新加坡 / 美国
3. `CN` → 大陆出口必须走代理
4. 出口正常（如 `JP`/`US`）仍失败 → 才怀疑 yt-dlp 版本，跑 `yt-dlp -U`

**2026-11-27 实测**：同一台机器、同一链接，日本节点（`loc=JP`，Amazon Tokyo）直连成功拿到 1440×1080 / 1748kbps；此前版本旧（2026.10.26）时代所有节点都失败。

两者的区分方法：**换节点能好 = 地域问题；换节点也不行且版本旧 = 版本问题**。

## 退出码约定（给调用方看的）

| 退出码 | 含义 |
|---|---|
| `0` | 全部成功（含走回退但拿到文件） |
| `1` | 至少一条彻底失败 |

**别用「输出里有没有 OK」判断成败**——脚本自己管退出码，`$?` 就是答案。

## 必须如实汇报画质路径

下载结束后脚本会打印并写入素材表：

- `[native]` — yt-dlp 直连 TikTok，拿到原始流
- `[fallback]` — yt-dlp 失败，走第三方接口，**画质可能低于原片**

**看到 `[fallback]` 必须主动告诉用户，不能只说「下载成功」。** 用户以为拿到了最高画质，实际可能低一档——知情权在他这边。

回退时脚本会打印：

```
⚠ yt-dlp 直连失败，回退第三方接口（画质可能低于原片）
  原因见 /tmp/ttdl_last.log；可先试 yt-dlp -U 更新
```

先试 `yt-dlp -U` 更新；更新后仍失败，就是 TikTok 侧拒绝（服务端风控），只能等或换代理节点，**不要反复重试到用户失去耐心**。

## 输出长什么样

```
→ 下载 kudaranai4 / 7701567116046011680
  OK: ~/Videos/搬运/kudaranai4_7701567116046011680.mp4 (2596KB, 1440x1080)
=== 完成，素材表: ~/Videos/搬运/素材表.csv ===
```

素材表 CSV 每行：时间、平台、作者、视频ID、文件路径、备注（标题 + 分辨率）。

## 关键实现约定（改脚本前必读）

这几条都是踩过坑换来的，别简化掉：

1. **取最高画质靠 yt-dlp 的 `-S res,br`**，不是 tikwm 的 `play` 字段。
   `play` 名义上跟着 `&hd=1` 走，实际固定返回 540p 兼容流（768×576）。真高清在 `hdplay`，而 `hdplay` 有时干脆不存在。

2. **下载前必须 `rm` 同名文件**。
   yt-dlp 发现目标已存在会静默跳过，不报错，留下的是旧的低清版。配合 `--force-overwrites` 一起用。

3. **重试要在脚本层包，不能只靠 `--retries`**。
   CDN 侧常见 `[SSL: UNEXPECTED_EOF_WHILE_READING]`。yt-dlp 自带的 `--retries N` 都挂在**同一条连接**上重试，连接彻底断了它不会重新握手，N 次全废。脚本外层再包 3 轮完整重下才救得回来。

4. **平台不同，依赖不同**。
   - **TikTok**：不需要 node。实测 `--no-js-runtimes` 与带 node 输出完全一致（1440×1080 / 1748052bps）。
   - **YouTube**：**必须要 node**。没有 JS 运行时 yt-dlp 拿不到高清档，只剩 360p 成品流（实测日志：`No supported JavaScript runtime could be found...some formats may be missing`）。
   - 所以 `--js-runtimes node` 要**按 `command -v node` 条件传**，硬写或完全不写都是错的。

5. **YouTube 的高清档全是 video-only，必须合流**。
   裸 `-f "b"` 是「同时含音视频的成品流」，YouTube 上最高只有 360p。实测对比：`b` → 640×360 / 444kbps；`bv*[height<=1080]+ba` → 1920×1080 / 3170kbps + 合并。
   平台选择器必须是：
   ```
   TikTok   → b[format_id!='download']/b          （单文件流，不需合流）
   其他平台  → bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b   （分离流合流）
   ```
   分辨率上限用 `TTDL_MAX_RES` 可调，默认 1080。

5. **元数据一次调用拿多个字段**：
   `yt-dlp --print "%(uploader)s" --print "%(id)s"` 输出多行，比拼分隔符可靠（`\t` 分隔在某些 shell 里会被 `tr` 吃掉）。

6. **`uploader` 才是账号名，`uploader_id` 是数字 UID**。
   用 `uploader_id` 命名会得到 `7174046275980002305_7701567116046011680.mp4` 这种鬼东西。

7. **JSON 解析不能强依赖 python3**。
   回退接口返回 JSON，用 `jq → python3 → grep` 三级降级，任何一个都缺也能跑。

8. **tikwm 回退只在 yt-dlp 彻底失败时用**，且必须优先 `hdplay`：
   ```python
   d.get('hdplay') or d.get('play')
   ```

## 画质天花板的事实

如果用户抱怨画质差，先查源。`yt-dlp -F "链接"` 能看到全部档位：

```
h264_540p   mp4 576x1024
bytevc1_720p  mp4 720x1280
bytevc1_1080p mp4 1080x1920   ← 通常最高
```

**源只有 540p 的作者，任何工具都提不上来**——那是他上传时压的。这种情况直接告诉用户「这就是源码率上限」，不要继续折腾。

画质的决定因素按顺序是：**① yt-dlp 版本够新 ② 作者上传时的源档位 ③ 是否被迫走回退接口**。跟 node 无关。

## 未验证项（如实记录，别当结论用）

- ~~node 影响画质~~ → **已证伪**。2026-11-27 实测 `--no-js-runtimes` 与带 node 输出完全相同（1440×1080 / 1748052bps / 2658571 字节）。此前「没 node 画质差」的观察，实际是**旧版 yt-dlp** 造成的混淆。
- **回退路径的码率**：同一视频、均 12.167s 完整文件，回退 872kbps vs 原生 1748kbps。方向明确（回退更低），但跨时刻单样本，倍数不可外推。
- **回退接口的稳定性**：2026-11-27 下午 tikwm 一度返回 403 / 超时，yt-dlp 侧对所有 TikTok 链接统一报 `Unexpected response from webpage request`。这说明外部依赖随时可能整体失效，脚本的失败提示要让用户看懂「是外部拒绝，不是你操作错」。

## 平台限制

- **TikTok**：最高一般 1080p，`bytevc1`（H.265）比 `h264` 码率更高画质更好
- **YouTube**：`-S res,br` 会选到 1080p 内最高；4K 需要 ffmpeg 合流
- **Instagram**：需要登录 cookie，脚本未内置，会失败

## 不做什么

- 不绕平台的原创检测，不修改视频指纹
- 不批量爬账号（只处理用户明确给出的链接）
- 下载的内容版权归原作者，商用需授权
