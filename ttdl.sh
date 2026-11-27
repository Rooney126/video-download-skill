#!/usr/bin/env bash
# ttdl — 一键下载 TikTok / YouTube / Instagram 视频（最高画质）
#
# 用法:
#   bash ttdl.sh "链接1" "链接2"
#   TTDL_DIR=~/Movies/搬运 bash ttdl.sh "链接"
#   TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh "链接"
#
# 依赖说明（详见 README）:
#   必需 - yt-dlp（版本要新！旧版本会让 TikTok 全线失败并退回低画质）
#   推荐 - ffmpeg    : 用于显示分辨率、合流高画质音视频
#   可选 - jq 或 python3 : 解析回退接口的 JSON；都没有也能跑（内置 grep 兜底）
#   不需要 node —— 2026-11-27 实测 --no-js-runtimes 与带 node 结果完全一致

set -uo pipefail

DIR="${TTDL_DIR:-$HOME/Videos/搬运}"
CSV="$DIR/素材表.csv"
PROXY="${TTDL_PROXY:-}"
MAX_RES="${TTDL_MAX_RES:-1080}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

mkdir -p "$DIR"
[ -f "$CSV" ] || echo "时间,平台,作者,视频ID,文件,备注" > "$CSV"

FALLBACK_COUNT=0
FAIL_COUNT=0

die() { echo "错误: $*" >&2; exit 1; }

# ---------- 环境探测 ----------
HAS_FFPROBE=0; command -v ffprobe >/dev/null 2>&1 && HAS_FFPROBE=1
HAS_NODE=0;    command -v node    >/dev/null 2>&1 && HAS_NODE=1
HAS_FFMPEG=0;  command -v ffmpeg  >/dev/null 2>&1 && HAS_FFMPEG=1

# yt-dlp 版本过旧会让 TikTok 报 Unexpected response，静默退回低码率接口。
# 这里只做提示不做阻断：拿不到版本号或解析失败都不影响下载。
check_ytdlp_age() {
  local v datepart
  v=$(yt-dlp --version 2>/dev/null | head -1)
  command -v date >/dev/null 2>&1 || return 0
  datepart=$(printf '%s' "$v" | grep -oE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}')
  [ -z "$datepart" ] && return 0
  local vsec nowsec
  vsec=$(date -d "$(printf '%s' "$datepart" | tr '.' '-')" +%s 2>/dev/null) || return 0
  nowsec=$(date +%s)
  local days=$(( (nowsec - vsec) / 86400 ))
  if [ "$days" -gt 60 ]; then
    echo "提示: yt-dlp 是 $v（约 ${days} 天前）。版本过旧时 TikTok 会拒绝请求，"
    echo "      表现为退回低画质接口。建议先更新: yt-dlp -U  或  pip install --user -U yt-dlp"
  fi
}

command -v yt-dlp >/dev/null 2>&1 || die "没装 yt-dlp（必需）：
  macOS:   brew install yt-dlp
  Linux:   pipx install yt-dlp   或  pip install --user -U yt-dlp
  Windows: winget install yt-dlp.yt-dlp
装完再跑。想顺手装 ffmpeg（显示分辨率用）：
  macOS: brew install yt-dlp ffmpeg
  Linux: sudo apt install ffmpeg && pipx install yt-dlp"

check_ytdlp_age
case "${*:-}" in
  *youtube.com*|*youtu.be*)
    [ "$HAS_NODE" -eq 0 ] && echo "提示: YouTube 需要 node 才能拿到高清档（当前缺 node，可能只有低清）"
    [ "$HAS_FFMPEG" -eq 0 ] && echo "提示: YouTube 高清需要 ffmpeg 合流（当前缺 ffmpeg，可能只有低清）"
    ;;
esac

if [ "$HAS_FFPROBE" -eq 0 ]; then
  echo "提示: 未检测到 ffprobe，跳过分辨率显示。装 ffmpeg 即可。"
fi

# ---------- 工具函数 ----------
# yt-dlp 调用：数组传参，避免代理参数缺失时留下空字符串参数
ytdlp() {
  local -a a=(yt-dlp --socket-timeout 20 --retries 3)
  # node 是条件依赖：TikTok 不需要，YouTube 必须有（否则拿不到高清档）
  [ "$HAS_NODE" -eq 1 ] && a+=(--js-runtimes node)
  [ -n "$PROXY" ] && a+=(--proxy "$PROXY")
  "${a[@]}" "$@"
}

# 平台相关的 format 选择器。YouTube 高清档全是 video-only，必须 bv+ba 合流，
# 用裸 "b" 只能拿到 360p 成品流（2026-11-27 实测踩到）。
format_selector() {
  case "$1" in
    *tiktok.com*)
      # TikTok 是单文件流，直接选最高，不需要合流
      printf '%s' "b[format_id!='download']/b"
      ;;
    *)
      # 其他平台：分离流合流，分辨率上限由 TTDL_MAX_RES 控制
      printf '%s' "bv*[height<=${MAX_RES}]+ba/b[height<=${MAX_RES}]/bv*+ba/b"
      ;;
  esac
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

# 探测代理出口地区。TikTok 对部分地区的出口 IP 会直接拒绝，
# 表现为 yt-dlp 报 Unexpected response —— 这和版本无关，换节点就好。
egress_region() {
  local loc=""
  if [ -n "$PROXY" ]; then
    loc=$(curl -s --max-time 10 -x "$PROXY" "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null \
          | sed -n 's/^loc=//p' | head -1)
  else
    loc=$(curl -s --max-time 10 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null \
          | sed -n 's/^loc=//p' | head -1)
  fi
  printf '%s' "${loc:-unknown}"
}

# 已知会拒 TikTok 直连的地区（依据：实测 + 社区反馈，非穷举）
region_tiktok_note() {
  case "$1" in
    HK) echo "香港出口常被 TikTok 拒绝，换日本/新加坡/美国节点重试" ;;
    CN) echo "中国大陆出口无法直连 TikTok，必须走代理" ;;
    unknown) echo "出口地区探测失败，无法判断是否地域限制" ;;
    *) echo "" ;;
  esac
}


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
if [ "$#" -eq 0 ]; then
  echo "用法: bash ttdl.sh \"链接1\" [\"链接2\" ...]"
  echo ""
  echo "环境变量:"
  echo "  TTDL_DIR=~/Movies/搬运     保存目录（默认 ~/Videos/搬运）"
  echo "  TTDL_PROXY=http://127.0.0.1:7890  代理地址（大陆必需！）"
  echo "  TTDL_MAX_RES=2160          分辨率上限（默认 1080）"
  echo ""
  echo "注意: 大陆直连 TikTok/YouTube 均不通，必须配代理。"
  exit 0
fi

# 没配代理 + 直连不通 = 确定失败。直接退出，不让用户干等 5 分钟。
if [ -z "$PROXY" ]; then
  _direct=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 https://www.tiktok.com/ 2>/dev/null)
  if [ "${_direct:-000}" = "000" ]; then
    case "$*" in
      *tiktok.com*)
        echo "❌ 无法下载：没有配置代理，且直连 TikTok 不通（000）。"
        echo ""
        echo "   中国大陆访问 TikTok 必须走代理。两种做法："
        echo "   1. 先开代理，再指定："
        echo "      TTDL_PROXY=http://127.0.0.1:7890 bash ttdl.sh \"链接\""
        echo "   2. 把代理地址告诉我，我帮你跑。"
        echo ""
        echo "   （为避免白等 5 分钟重试，此处直接退出）"
        exit 1
        ;;
      *)
        echo "⚠ 未配置代理，直连 TikTok 不通（000）。YouTube 有时可直连，继续尝试…"
        ;;
    esac
  fi
fi

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
    _fmt=$(format_selector "$url")
    ytdlp -f "$_fmt" -S "res,br" --merge-output-format mp4 \
          --force-overwrites -o "$out" "$url" >/tmp/ttdl_last.log 2>&1
    size=$(filesize "$out")
    [ "$size" -gt 20000 ] && break
    [ "$attempt" -lt 3 ] && { echo "  第${attempt}轮没成，重试…"; sleep 2; }
  done

  # 记录走的哪条路径：native = yt-dlp 直连（最高画质）；fallback = 第三方回退（画质可能更低）
  QUALITY_PATH="native"
  QUALITY_NOTE=""
  if [ "$(filesize "$out")" -lt 20000 ]; then
    echo "  ⚠ yt-dlp 直连失败，回退第三方接口（画质可能低于原片）"
    echo "    原因见 /tmp/ttdl_last.log；可先试 yt-dlp -U 更新"
    _rg=$(egress_region)
    _rn=$(region_tiktok_note "$_rg")
    echo "    当前代理出口: ${_rg}"
    [ -n "$_rn" ] && echo "    → ${_rn}"
    QUALITY_PATH="fallback"
    QUALITY_NOTE="画质可能低于原片"
    case "$url" in
      *tiktok.com*) tikwm_fallback "$url" "$out" ;;
    esac
  fi
  size=$(filesize "$out")

  if [ "$size" -gt 20000 ]; then
    res=$(probe_res "$out")
    br=$(ffprobe -v error -show_entries format=bit_rate -of csv=p=0 "$out" 2>/dev/null)
    [ -n "${br:-}" ] && br="$((br/1000))kbps"
    desc=$(ytdlp --print "%(title)s" --skip-download "$url" 2>/dev/null | head -1 | tr ',' '，' | cut -c1-40)
    echo "$(date '+%m-%d %H:%M'),TikTok,$author,$id,$out,$desc ${res:-} ${br:-} [$QUALITY_PATH]" >> "$CSV"
    echo "  OK: $out ($((size/1024))KB${res:+, $res}${br:+, $br})"
    if [ "$QUALITY_PATH" = "fallback" ]; then
      echo "  ⚠ 本条走的是回退路径，码率可能低于原片。要最高画质需 yt-dlp 直连可用。"
      FALLBACK_COUNT=$((FALLBACK_COUNT+1))
    fi
  else
    rm -f "$out"
    echo "  失败: $url"
    echo "        诊断: 日志见 /tmp/ttdl_last.log"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
done

# 首次成功下载后写就绪标记，让 AI 下次不再重复解说工具用途
if [ "${FAIL_COUNT:-0}" -eq 0 ]; then
  mkdir -p "$HOME/.config/ttdl" 2>/dev/null && : > "$HOME/.config/ttdl/ready" 2>/dev/null
fi

echo "=== 完成，素材表: $CSV ==="
if [ "${FALLBACK_COUNT:-0}" -gt 0 ]; then
  echo ""
  echo "注意: 有 ${FALLBACK_COUNT} 条走的是回退路径（画质可能低于原片）。"
  echo "      想让 yt-dlp 直连恢复：yt-dlp -U 更新；仍不行就是 TikTok 侧拒绝，只能等。"
fi
# 退出码必须准确：末尾裸 `[ ... ] && echo` 在条件为假时会让整个脚本返回 1，
# 成功下载也被外部判为失败（2026-11-27 实测踩到）
if [ "${FAIL_COUNT:-0}" -gt 0 ]; then
  echo "有 ${FAIL_COUNT} 条下载失败。"
  exit 1
fi
exit 0
