#!/usr/bin/env bash
# ttdl — 一键下载 TikTok / YouTube 视频（便携版，不依赖任何固定路径）
#
# 用法:
#   bash ttdl.sh "链接1" "链接2"
#   TTDL_DIR=~/Downloads/videos bash ttdl.sh "链接"
#   TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"   # 你的代理地址
#
# 依赖: yt-dlp（必需）、ffmpeg/ffprobe（可选，用于显示分辨率）、curl（可选，回退用）
# 说明: 优先 yt-dlp 取最高画质；失败才回退 tikwm。两者都不需要代理也能跑，只是慢。

set -uo pipefail

DIR="${TTDL_DIR:-$HOME/Videos/搬运}"
CSV="$DIR/素材表.csv"
PROXY="${TTDL_PROXY:-}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

mkdir -p "$DIR"
[ -f "$CSV" ] || echo "时间,平台,作者,视频ID,文件,备注" > "$CSV"

proxy_args() {
  if [ -n "$PROXY" ]; then
    printf '%s\0%s\0' "--proxy" "$PROXY"
  fi
}

die() { echo "错误: $*" >&2; exit 1; }

command -v yt-dlp >/dev/null 2>&1 || die "没装 yt-dlp。装法：
  macOS:   brew install yt-dlp ffmpeg
  Linux:   pipx install yt-dlp  或  sudo apt install yt-dlp ffmpeg
  Windows: winget install yt-dlp.yt-dlp ffmpeg"

probe_res() {
  if command -v ffprobe >/dev/null 2>&1 && [ -s "$1" ]; then
    ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
      -of csv=p=0:s=x "$1" 2>/dev/null
  fi
}

# yt-dlp 调用（数组传参，避免代理参数缺失时留下空参数）
ytdlp() {
  local -a a=(yt-dlp --js-runtimes node --socket-timeout 20 --retries 3)
  [ -n "$PROXY" ] && a+=(--proxy "$PROXY")
  "${a[@]}" "$@"
}

# 回退：tikwm 解析（仅 TikTok，优先 hdplay，不是 play——play 固定 540p）
tikwm_fallback() {
  local url="$1" author="$2" id="$3" out="$4"
  local -a c=(curl -s --max-time 25)
  [ -n "$PROXY" ] && c+=(-x "$PROXY")
  local json link
  json=$("${c[@]}" "https://tikwm.com/api/?url=$url&hd=1" -H "User-Agent: $UA")
  link=$(printf '%s' "$json" | python3 -c \
    "import json,sys;d=json.load(sys.stdin)['data'];print(d.get('hdplay') or d.get('play') or '')" 2>/dev/null)
  [ -z "$link" ] && return 1

  local -a d=(curl -s --max-time 180 -L)
  [ -n "$PROXY" ] && d+=(-x "$PROXY")
  rm -f "$out"
  "${d[@]}" -o "$out" "$link" -H "User-Agent: $UA" -H "Referer: https://www.tiktok.com/"
  [ -s "$out" ] && [ "$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)" -gt 20000 ]
}

for url in "$@"; do
  case "$url" in
    *tiktok.com*|*youtube.com*|*youtu.be*|*instagram.com*) ;;
    *) echo "跳过(不支持的链接): $url"; continue ;;
  esac

  # 一次调用拿两个字段：yt-dlp 支持多个 --print，每行一个，比拼接分隔符稳
  meta=$(ytdlp --print "%(uploader)s" --print "%(id)s" --skip-download "$url" 2>/dev/null)
  author=$(printf '%s\n' "$meta" | sed -n '1p' | tr -d '/\\:*?"<>|')
  id=$(printf '%s\n' "$meta" | sed -n '2p')
  # 偶发瞬时失败：补一次
  if [ -z "${id:-}" ]; then
    id=$(printf '%s' "$url" | grep -oE '/video/[0-9]+' | grep -oE '[0-9]+')
  fi
  [ -z "${author:-}" ] && author=$(ytdlp --print "%(uploader)s" --skip-download "$url" 2>/dev/null | head -1 | tr -d '/\\:*?"<>|')
  # 最后一道：直接从 URL 的 @handle 抓（元数据请求失败时的兼底，避免得到 unknown 文件名）
  if [ -z "${author:-}" ]; then
    author=$(printf '%s' "$url" | sed -n 's#.*/\(@[^/]*\)/.*#\1#p' | sed 's/^@//' | tr -d '/\\:*?"<>|')
  fi
  [ -z "${id:-}" ] && { echo "跳过(解析不到ID): $url"; continue; }
  [ -z "${author:-}" ] && author="unknown"

  out="$DIR/${author}_${id}.mp4"
  rm -f "$out"   # 必须删：yt-dlp 发现同名文件会静默跳过，留下的是旧的低清版

  echo "→ 下载 $author / $id"
  # 重试 3 轮：CDN 侧 SSL EOF / 断流是常态，yt-dlp 自带的 3 次重试都捆在单次连接上，
  # 整条连接挂了它不会重新握手，所以必须在脚本层再包一层
  for attempt in 1 2 3; do
    rm -f "$out"
    ytdlp -f "b[format_id!='download']/b" -S "res,br" --merge-output-format mp4 \
          --force-overwrites -o "$out" "$url" >/tmp/ttdl_last.log 2>&1
    size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)
    [ "$size" -gt 20000 ] && break
    [ $attempt -lt 3 ] && { echo "  第${attempt}轮没成，重试…"; sleep 2; }
  done
  if [ "$size" -lt 20000 ]; then
    echo "  yt-dlp 没拿到，回退 tikwm"
    case "$url" in
      *tiktok.com*) tikwm_fallback "$url" "$author" "$id" "$out" ;;
    esac
    size=$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out" 2>/dev/null || echo 0)
  fi

  if [ "$size" -gt 20000 ]; then
    res=$(probe_res "$out")
    desc=$(ytdlp --print "%(title)s" --skip-download "$url" 2>/dev/null | head -1 | tr ',' '，' | cut -c1-40)
    echo "$(date '+%m-%d %H:%M'),TikTok,$author,$id,$out,$desc ${res:-}" >> "$CSV"
    echo "  OK: $out ($((size/1024))KB${res:+, $res})"
  else
    rm -f "$out"
    echo "  失败: $url"
  fi
done

echo "=== 完成，素材表: $CSV ==="
