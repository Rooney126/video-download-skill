#!/usr/bin/env bash
# install.sh — 一条命令把依赖装齐
# 设计原则：先检测再动手；装任何东西之前都问；不静默改系统配置。

set -uo pipefail
cd "$(dirname "$0")" || exit 1

ok()   { printf '  ✅ %s\n' "$1"; }
miss() { printf '  ❌ %s\n' "$1"; }
info() { printf '     %s\n' "$1"; }

has() { command -v "$1" >/dev/null 2>&1; }

echo "=== 环境检测 ==="
OS="unknown"
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac
# WSL 归到 linux
if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  OS="wsl"
fi
echo "  系统: $OS"

NEED_YTDLP=0; NEED_FFMPEG=0; NEED_UPDATE=0

if has yt-dlp; then
  ok "yt-dlp $(yt-dlp --version 2>/dev/null | head -1)"
else
  miss "yt-dlp（必需）"; NEED_YTDLP=1
fi

if has node; then
  ok "node $(node -v 2>/dev/null)（非必需，实测不影响画质）"
else
  info "node 未安装 —— 不需要，新版 yt-dlp 无 JS 运行时也能拿最高档"
fi

# yt-dlp 版本过旧才是 TikTok 失败的真正原因（2026-11-27 实测）
if has yt-dlp; then
  vv=$(yt-dlp --version 2>/dev/null | head -1)
  vd=$(printf '%s' "$vv" | grep -oE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}')
  if [ -n "$vd" ] && has date; then
    vs=$(date -d "$(printf '%s' "$vd" | tr '.' '-')" +%s 2>/dev/null)
    if [ -n "$vs" ]; then
      days=$(( ( $(date +%s) - vs ) / 86400 ))
      if [ "$days" -gt 60 ]; then
        miss "yt-dlp $vv 已 ${days} 天（旧版本会退回低画质）"
        info "更新: yt-dlp -U   或   pip install --user -U yt-dlp"
        NEED_UPDATE=1
      else
        ok "yt-dlp $vv（${days} 天内，够新）"
      fi
    fi
  fi
fi

if has ffprobe; then
  ok "ffmpeg"
else
  miss "ffmpeg（推荐，显示分辨率/合流用）"; NEED_FFMPEG=1
fi

if has jq; then ok "jq"
elif has python3; then ok "python3（代替 jq 解析 JSON）"
else info "jq 和 python3 都没有，回退 JSON 会用 grep 兜底"; fi

# ---------- 组装安装命令 ----------
SUGGEST=""
if [ "$NEED_YTDLP" -eq 1 ] || [ "$NEED_FFMPEG" -eq 1 ] || [ "$NEED_UPDATE" -eq 1 ]; then
  case "$OS" in
    macos)
      pkgs=""
      [ "$NEED_YTDLP"  -eq 1 ] && pkgs="$pkgs yt-dlp"
      [ "$NEED_FFMPEG" -eq 1 ] && pkgs="$pkgs ffmpeg"
      if has brew; then
        SUGGEST="brew install$pkgs"
      else
        SUGGEST="先装 Homebrew：/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        info "没检测到 Homebrew"
      fi
      ;;
    linux|wsl)
      if has apt-get; then
        arch=""
        [ "$NEED_FFMPEG" -eq 1 ] && arch="$arch ffmpeg"
        if [ -n "$arch" ]; then
          SUGGEST="sudo apt update && sudo apt install -y$arch"
        fi
        if [ "$NEED_YTDLP" -eq 1 ]; then
          if [ -n "$SUGGEST" ]; then
            SUGGEST="$SUGGEST && pipx install yt-dlp"
          else
            SUGGEST="pipx install yt-dlp"
          fi
          has pipx || info "还需要 pipx：sudo apt install -y pipx && pipx ensurepath"
        fi
      else
        SUGGEST="用你的包管理器装：yt-dlp node ffmpeg"
      fi
      ;;
    windows)
      pkgs=""
      [ "$NEED_YTDLP"  -eq 1 ] && pkgs="$pkgs yt-dlp.yt-dlp"
      [ "$NEED_FFMPEG" -eq 1 ] && pkgs="$pkgs Gyan.FFmpeg"
      if has winget; then
        SUGGEST="winget install$pkgs"
      else
        SUGGEST="先装 winget，或用 scoop/choco 装：yt-dlp node ffmpeg"
      fi
      ;;
    *)
      SUGGEST="请手动安装：yt-dlp（必需）、node、ffmpeg"
      ;;
  esac
fi

echo
if [ -z "$SUGGEST" ]; then
  echo "=== 依赖齐全，直接可用 ==="
else
  echo "=== 需要安装 ==="
  echo
  echo "    $SUGGEST"
  echo
  # 只在用户明确同意时才代为执行
  if [ -t 0 ]; then
    printf "要我直接替你执行这条命令吗？[y/N] "
    read -r ans
    case "$ans" in
      y|Y|yes|YES)
        echo "→ 执行中…"
        if bash -c "$SUGGEST"; then
          echo "  ✅ 安装命令执行完毕"
        else
          echo "  ❌ 安装失败，请手动执行上面的命令"
        fi
        ;;
      *) echo "  已跳过。你可以复制上面那条命令自己跑。" ;;
    esac
  else
    info "非交互环境，跳过自动安装。请手动执行上面的命令。"
  fi
fi

echo
echo "=== 自检 ==="
if [ -f test.sh ]; then
  bash test.sh
else
  echo "  找不到 test.sh"
fi

echo
if has yt-dlp; then
  echo "=== 就绪 ==="
  echo "  用法: bash ttdl.sh \"视频链接\""
  echo "  让 AI 读: SKILL.md"
else
  echo "=== 还不能用：yt-dlp 未安装 ==="
  exit 1
fi
