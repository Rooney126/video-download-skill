#!/usr/bin/env bash
# ttdl — 一键下载 TikTok / YouTube / Instagram 视频（最高画质）
#
# 用法:
#   bash ttdl.sh "链接1" "链接2"
#   TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"
#   TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"
#
# 依赖说明（详见 README）:
#   必需 - yt-dlp
#   推荐 - node      : 让 yt-dlp 解开 TikTok 的 JS 挑战，直接拿到原始最高码率
#   推荐 - ffmpeg    : 用于显示分辨率、合流高画质音视频
#   可选 - jq 或 python3 : 解析回退接口的 JSON；都没有也能跑（内置 grep 兜底）

set -uo pipefail

DIR="${TTDL_DIR:-$HOME/Videos/搬运}"
CSV="$DIR/素材表.csv"
PROXY="${TTDL_PROXY:-}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

mkdir -p "$DIR"
[ -f "$CSV" ] || echo "时间,平台,作者,视频ID,文件,备注" > "$CSV"

die() { echo "错误: $*" >&2; exit 1; }

# ---------- 环境探测 ----------
HAS_NODE=0;    command -v node    >/dev/null 2>&1 && HAS_NODE=1
HAS_FFPROBE=0; command -v ffprobe >/dev/null 2>&1 && HAS_FFPROBE=1

command -v yt-dlp >/dev/null 2>&1 || die "没装 yt-dlp（必需）：
  macOS:   brew install yt-dlp
  Linux:   pipx install yt-dlp   或  pip install --user -U yt-dlp
  Windows: winget install yt-dlp.yt-dlp
装完再跑。还想顺手解决 node/ffmpeg 就一起装：
  macOS: brew install yt-dlp node ffmpeg
  Linux: sudo apt install ffmpeg nodejs && pipx install yt-dlp"

if [ "$HAS_NODE" -eq 0 ]; then
  echo "提示: 未检测到 node。yt-dlp 解不开 TikTok 的 JS 挑战，画质可能不是最高。"
  echo "      想要最高画质请装 node；不装也能下，只是会走回退接口。"
fi
if [ "$HAS_FFPROBE" -eq 0 ]; then
  echo "提示: 未检测到 ffprobe，跳过分辨率显示。装 ffmpeg 即可。"
fi

# ---------- 工具函数 ----------
# yt-dlp 调用：只有装了 node 才传 --js-runtimes，硬写会在没 node 的机器上直接报错
ytdlp() {
  local -a a=(yt-dlp --socket-timeout 20 --retries 3)
  [ "$HAS_NODE" -eq 1 ] && a+=(--js-runtimes node)
  [ -n "$PROXY" ] && a+=(--proxy "$PROXY")
  "${a[@]}" "$@"
}

# 从 tikwm 的 JSON 里取字段，优先 jq → python3 → grep 兜底（不强制装解释器）
json_get() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".data.$key // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys
try:
    d=json.load(sys.stdin).get('data') or {}
    v=d.get('$key')
    print(v if v is not None else '')
except Exception:
    print('')" 2>/dev/null
  else
    grep -oE "\"${key}\":\"[^\"]*\"" | head -1 | sed -E "s/.*:\"([^\"]*)\"/\1/"
  fi
}

probe_res() {
  [ "$HAS_FFPROBE" -eq 1 ] && [ -s "$1" ] && ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height -of csv=p=0:s=x "$1" 2>/dev/null
}

filesize() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null || echo 0; }

# 回退：tikwm 解析（仅 TikTok）。必须优先 hdplay，play 固定 540p。
tikwm_fallback() {
  local url="$1" out="$2"
  local -a c=(curl -s --max-time 25)
  [ -n "$PROXY" ] && c+=(-x "$PROXY")
  local json link
  json=$("${c[@]}" "https://tikwm.com/api/?url=$url&hd=1" -H "User-Agent: $UA")
  link=$(printf '%s' "$json" | json_get hdplay)
  [ -z "$link" ] && link=$(printf '%s' "$json" | json_get play)
  [ -z "$link" ] && return 1

  local -a d=(curl -s --max-time 180 -L)
  [ -n "$PROXY" ] && d+=(-x "$PROXY")
  rm -f "$out"
  "${d[@]}" -o "$out" "$link" -H "User-Agent: $UA" -H "Referer: https://www.tiktok.com/"
  [ "$(filesize "$out")" -gt 20000 ]
}

# ---------- 主循环 ----------
for url in "$@"; do
  case "$url" in
    *tiktok.com*|*youtube.com*|*youtu.be*|*instagram.com*) ;;
    *) echo "跳过(不支持的链接): $url"; continue ;;
  esac

  # 一次调用取两个字段：多个 --print 各占一行，比拼分隔符可靠
  meta=$(ytdlp --print "%(uploader)s" --print "%(id)s" --skip-download "$url" 2>/dev/null)
  author=$(printf '%s\n' "$meta" | sed -n '1p' | tr -d '/\\:*?"<>|')
  id=$(printf '%s\n' "$meta" | sed -n '2p')

  # 元数据拿不到时的两级兜底：URL 里的 @handle → 视频ID → unknown
  if [ -z "${author:-}" ]; then
    author=$(printf '%s' "$url" | sed -n 's#.*/\(@[^/]*\)/.*#\1#p' | sed 's/^@//' | tr -d '/\\:*?"<>|')
  fi
  if [ -z "${id:-}" ]; then
    id=$(printf '%s' "$url" | grep -oE '/video/[0-9]+' | grep -oE '[0-9]+')
  fi
  [ -z "${id:-}" ] && { echo "跳过(解析不到ID): $url"; continue; }
  [ -z "${author:-}" ] && author="unknown"

  out="$DIR/${author}_${id}.mp4"
  # 必须删：yt-dlp 发现同名文件会静默跳过，留下的是旧的低清版
  rm -f "$out"

  echo "→ 下载 $author / $id"
  # 脚本层重试 3 轮：CDN 侧 SSL EOF/断流是常态，yt-dlp 自带 --retries 全挂在同一条坏连接上
  for attempt in 1 2 3; do
    rm -f "$out"
    ytdlp -f "b[format_id!='download']/b" -S "res,br" --merge-output-format mp4 \
          --force-overwrites -o "$out" "$url" >/tmp/ttdl_last.log 2>&1
    size=$(filesize "$out")
    [ "$size" -gt 20000 ] && break
    [ "$attempt" -lt 3 ] && { echo "  第${attempt}轮没成，重试…"; sleep 2; }
  done

  if [ "$(filesize "$out")" -lt 20000 ]; then
    echo "  yt-dlp 没拿到，回退 tikwm"
    case "$url" in
      *tiktok.com*) tikwm_fallback "$url" "$out" ;;
    esac
  fi
  size=$(filesize "$out")

  if [ "$size" -gt 20000 ]; then
    res=$(probe_res "$out")
    desc=$(ytdlp --print "%(title)s" --skip-download "$url" 2>/dev/null | head -1 | tr ',' '，' | cut -c1-40)
    echo "$(date '+%m-%d %H:%M'),TikTok,$author,$id,$out,$desc ${res:-}" >> "$CSV"
    echo "  OK: $out ($((size/1024))KB${res:+, $res})"
  else
    rm -f "$out"
    echo "  失败: $url"
    echo "        诊断: 日志见 /tmp/ttdl_last.log"
  fi
done

echo "=== 完成，素材表: $CSV ==="
