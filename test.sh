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

echo "=== 7. 可选依赖必须优雅降级 ==="
# node 不需要：新版 yt-dlp 无 JS 运行时也能拿最高档（2026-11-27 实测）
if grep -qE '^\s*[^#]*js-runtimes' "$REPO/ttdl.sh"; then
  bad "仍在传 --js-runtimes，但实测不需要（会误导用户装 node）"
else
  ok "不依赖 node / js-runtimes"
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
grep -q 'read -r ans' "$REPO/install.sh" && ok "install.sh 装前询问，不静默改系统" || bad "install.sh 会静默安装"

echo
echo "结果: $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
