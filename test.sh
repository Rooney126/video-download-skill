# ===== 可移植性 + 依赖降级 自检 =====
# 目标：在别人的干净机器上也能跑通，缺依赖时给出可读的提示而不是崩

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. 语法 ==="
bash -n "$REPO/ttdl.sh"    && ok "ttdl.sh 语法正确"   || bad "ttdl.sh 语法错误"
bash -n "$REPO/install.sh" && ok "install.sh 语法正确" || bad "install.sh 语法错误"

echo "=== 2. 没有硬编码路径/端口 ==="
if grep -nE '/mnt/c/|[A-Z]:\\\\Users|127\.0\.0\.1:7897|powershell\.exe' "$REPO/ttdl.sh" >/dev/null 2>&1; then
  bad "发现硬编码路径/端口，别人机器会挂："
  grep -nE '/mnt/c/|[A-Z]:\\\\Users|127\.0\.0\.1:7897|powershell\.exe' "$REPO/ttdl.sh"
else
  ok "无硬编码路径、无固定代理端口"
fi

echo "=== 3. 必需依赖检查 ==="
command -v yt-dlp >/dev/null 2>&1 && ok "本机 yt-dlp 已装（可跑真下载）" || echo "  ⚠️  本机没装 yt-dlp，跳过实际下载"

echo "=== 4. 参数化 ==="
grep -q 'TTDL_DIR'   "$REPO/ttdl.sh" && ok "TTDL_DIR 可配置"   || bad "缺 TTDL_DIR"
grep -q 'TTDL_PROXY' "$REPO/ttdl.sh" && ok "TTDL_PROXY 可配置" || bad "缺 TTDL_PROXY"

echo "=== 5. 最高画质逻辑 ==="
grep -q 'S "res,br"' "$REPO/ttdl.sh" && ok "用 -S res,br 选最高档"        || bad "没选最高档"
grep -q "hdplay"     "$REPO/ttdl.sh" && ok "回退优先 hdplay（不是 play）"  || bad "回退用了 play（只有 540p）"

echo "=== 6. 已知坑的防护 ==="
grep -q 'rm -f "\$out"'        "$REPO/ttdl.sh" && ok "下载前删除同名文件"           || bad "没删同名文件（会静默跳过）"
grep -q 'for attempt in 1 2 3' "$REPO/ttdl.sh" && ok "脚本层重试（应对 SSL 断流）"   || bad "缺脚本层重试"
grep -q 'force-overwrites'     "$REPO/ttdl.sh" && ok "force-overwrites 已开"        || bad "缺 force-overwrites"

echo "=== 7a. 平台感知的 format 选择器 ==="
grep -q 'format_selector' "$REPO/ttdl.sh" && ok "有 format_selector 分平台处理" || bad "缺分平台格式选择"
# YouTube 高清档是 video-only，必须 bv+ba 合流；裸 b 只能 360p
grep -q 'bv\*\[height' "$REPO/ttdl.sh" && ok "非 TikTok 用 bv+ba 合流（否则只有 360p）" || bad "缺 bv+ba 合流"
grep -q 'TTDL_MAX_RES' "$REPO/ttdl.sh" && ok "分辨率上限可配（TTDL_MAX_RES）" || bad "分辨率写死"
# YouTube 需要 node，TikTok 不需要——必须条件传
grep -q 'HAS_NODE' "$REPO/ttdl.sh" && ok "node 条件传入（YouTube 要，TikTok 不强求）" || bad "node 处理有误"
grep -q 'HAS_FFMPEG' "$REPO/ttdl.sh" && ok "检测 ffmpeg（YouTube 合流需要）" || bad "没检测 ffmpeg"

echo "=== 7. 可选依赖必须优雅降级 ==="
# node 不需要：新版 yt-dlp 无 JS 运行时也能拿最高档（2026-11-27 实测）
# node 是条件依赖：TikTok 不需要、YouTube 需要。硬写或不写都是错的
if grep -qE '^\s*[^#]*js-runtimes' "$REPO/ttdl.sh"; then
  grep -q 'HAS_NODE' "$REPO/ttdl.sh" && ok "js-runtimes 受 HAS_NODE 条件控制" || bad "硬传 --js-runtimes"
else
  bad "完全没传 --js-runtimes，YouTube 会拿不到高清档"
fi
# 旧版 yt-dlp 才是真根因，脚本必须提示版本
grep -q 'check_ytdlp_age' "$REPO/ttdl.sh" && ok "检测 yt-dlp 版本新鲜度" || bad "缺版本新鲜度检查"
# ffprobe 缺失不能影响下载
grep -q 'HAS_FFPROBE' "$REPO/ttdl.sh" && ok "ffprobe 缺失时降级（不显示分辨率）" || bad "ffprobe 是硬依赖"
# JSON 解析不能强依赖 python3
if grep -q 'json_get' "$REPO/ttdl.sh"; then
  grep -q 'jq' "$REPO/ttdl.sh" && ok "JSON 解析有 jq → python3 → grep 三级兜底" || bad "JSON 解析无兜底"
else
  bad "缺 JSON 解析兜底"
fi

echo "=== 7b. 代理前提必须写到位 ==="
grep -q "TTDL_PROXY" "$REPO/README.md" && ok "README 说明代理用法" || bad "README 没写代理"
grep -q "必须.*代理\|必须要代理" "$REPO/README.md" && ok "README 明示代理是硬前提" || bad "README 没强调必须代理"
sed -n '1,20p' "$REPO/README.md" | grep -q "代理" && ok "代理警告在 README 前 20 行（陌生人能看到）" || bad "代理警告埋在文档深处"
sed -n '1,60p' "$REPO/SKILL.md" | grep -q "代理" && ok "SKILL.md 首次话术含代理" || bad "AI 首次说话不会提代理"
grep -q "_direct" "$REPO/ttdl.sh" && ok "没配代理时预检直连" || bad "缺直连预检"
# 只查预检段（第 168 行附近）有没拿代理去 curl；egress_region 探出口地区是正当用途
if sed -n '/未配置代理/,/仍会尝试下载/p' "$REPO/ttdl.sh" | grep -q '\-x "\$PROXY"'; then
  bad "预检段拿代理探活，会误报（实测同一代理时而000时而200）"
else
  ok "预检段不用代理探活，避免误报"
fi
sed -n '1,80p' "$REPO/SKILL.md" | grep -q 'ALREADY_SETUP' && ok "SKILL 有首次/后续分流（不重复解说）" || bad "每次都重复解说，会烦人"
grep -q 'ttdl/ready' "$REPO/ttdl.sh" && ok "成功下载后写就绪标记" || bad "缺就绪标记"

echo "=== 8. 空参数与退出码 ==="
out=$(bash "$REPO/ttdl.sh" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "空参数退出码 0" || bad "空参数退出码 $rc（应为 0）"
echo "$out" | grep -q "用法" && ok "空参数打印用法" || bad "空参数没给用法提示"
# 末尾裸 [ ] && echo 会让成功也返回 1，这是已踩过的坑
if tail -5 "$REPO/ttdl.sh" | grep -qE '^\s*\[ .*\] && echo'; then
  bad "末尾有裸 [ ] && echo，成功也会返回非 0"
else
  ok "结尾显式 exit，成功路径返回 0"
fi
grep -q 'exit 0' "$REPO/ttdl.sh" && grep -q 'exit 1' "$REPO/ttdl.sh" && ok "成功/失败退出码分别显式声明" || bad "缺显式退出码"

echo "=== 9. install.sh 覆盖依赖检测 ==="
for dep in yt-dlp ffprobe; do
  grep -q "has $dep" "$REPO/install.sh" && ok "install.sh 检测 $dep" || bad "install.sh 没检测 $dep"
done
grep -q 'read -r ans' "$REPO/install.sh" && ok "默认装前询问（不静默改系统）" || bad "缺交互确认"
grep -q -- '--yes' "$REPO/install.sh" && ok "支持 --yes 让 AI 无人值守安装" || bad "缺 --yes"
# 关键：建议文字不能被当成命令执行
grep -q 'SUGGEST_IS_CMD' "$REPO/install.sh" && ok "区分「可执行命令」与「建议文字」" || bad "会把建议文字当命令跑"

echo
echo "结果: $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
