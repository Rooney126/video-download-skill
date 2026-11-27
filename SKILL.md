---
name: video-download
description: Download TikTok / YouTube / Instagram videos at the highest available quality, with a simple ledger. Use when the user sends a video link and wants it saved, re-uploaded, archived, or reposted (搬运/下载/存下来).
---

# video-download

给一个视频链接，下载最高画质版本并按 `作者_视频ID.mp4` 命名，同时记一行到素材表。

## 什么时候用

用户消息里出现视频链接（tiktok.com / youtube.com / youtu.be / instagram.com），且语境是「下载 / 存下来 / 搬运 / 搬过来」。

不需要问用户任何问题，直接跑脚本。

## 第一步：检查依赖（别跳过）

```bash
command -v yt-dlp >/dev/null && echo "yt-dlp OK" || echo "缺 yt-dlp"
command -v node   >/dev/null && echo "node OK"   || echo "缺 node（可选）"
```

**依赖分三档，缺了行为不同：**

| 依赖 | 必需性 | 缺了会怎样 | 装上能多拿到什么 |
|---|---|---|---|
| **yt-dlp** | **必需** | 脚本直接退出 | — |
| node | 推荐 | yt-dlp 解不开 TikTok 的 JS 挑战，会直接报错并退回第三方接口 | 让 yt-dlp 直连 TikTok 取原始流（**具体码率增益未经稳定实测**） |
| ffmpeg/ffprobe | 推荐 | 不显示分辨率，高画质合流可能失败 | 分辨率显示 + 音视频合流 |
| jq **或** python3 | 可选 | 用内置 grep 兜底解析 | 解析更稳 |

**缺必需的 yt-dlp 时，不要试图让用户手敲安装命令——直接跑安装脚本：**

```bash
bash install.sh
```

它会自动识别系统（macOS / Linux / WSL / Windows），列出缺什么、给出对应安装命令，**问过用户才执行**，最后自动跑一遍自检。

## 第二步：跑下载

```bash
bash ttdl.sh "链接1" "链接2"
```

可选环境变量：

```bash
TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"           # 自定义保存目录（默认 ~/Videos/搬运）
TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"  # 走代理（默认不走）
```

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

4. **`--js-runtimes node` 不能硬写**。
   没装 node 的机器上，硬传这个参数会让 yt-dlp 直接报 `Unexpected response from webpage request`，连回退机会都没有。必须先 `command -v node` 检测，存在才传。

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

有无 node 理论上影响能否拿到 TikTok 原始流，但**具体差多少我没能稳定测出来**（见下方「未验证项」）。建议用户装 node，理由是让 yt-dlp 走通原生路径，不是「一定高 25%」。

## 未验证项（如实记录，别当结论用）

- **有无 node 的码率差**：我一度写「高 25%（2048KB vs 2596KB）」，但这个结论站不住 —— 那两次测试的节点、时刻、TikTok 服务端状态都不同，不是受控对比。
  后续补充数据（2026-11-27 17:57，同一视频、时长均 12.167s 完整）：回退路径 872kbps，此前原生路径 1748kbps。**方向是回退更低，但仍是跨时刻比较，单样本不足以定倍数。** 结论：node 影响能否走通原生路径；原生路径通常码率更高，具体倍数取决于当时服务端下发。
- **回退接口的稳定性**：2026-11-27 下午 tikwm 一度返回 403 / 超时，yt-dlp 侧对所有 TikTok 链接统一报 `Unexpected response from webpage request`。这说明外部依赖随时可能整体失效，脚本的失败提示要让用户看懂「是外部拒绝，不是你操作错」。

## 平台限制

- **TikTok**：最高一般 1080p，`bytevc1`（H.265）比 `h264` 码率更高画质更好
- **YouTube**：`-S res,br` 会选到 1080p 内最高；4K 需要 ffmpeg 合流
- **Instagram**：需要登录 cookie，脚本未内置，会失败

## 不做什么

- 不绕平台的原创检测，不修改视频指纹
- 不批量爬账号（只处理用户明确给出的链接）
- 下载的内容版权归原作者，商用需授权
