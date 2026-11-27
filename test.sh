# ===== 测试：另一个人的机器上能不能跑通 =====
# 关键：不能依赖本仓库外的任何文件、路径、代理端口

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== 1. 语法 ==="
bash -n "$REPO/ttdl.sh" && ok "ttdl.sh 语法正确" || bad "ttdl.sh 语法错误"

echo "=== 2. 没有硬编码路径 ==="
if grep -nE '/mnt/c/|[A-Z]:\\\\\\\\Users|127\.0\.0\.1:7897|powershell\.exe' "$REPO/ttdl.sh" >/dev/null 2>&1; then
  bad "发现硬编码路径/端口，别人机器会挂："
  grep -nE '/mnt/c/|[A-Z]:\\\\\\\\Users|127\.0\.0\.1:7897|powershell\.exe' "$REPO/ttdl.sh"
else
  ok "无硬编码路径、无固定代理端口"
fi

echo "=== 3. 依赖检查行为 ==="
if command -v yt-dlp >/dev/null 2>&1; then
  ok "yt-dlp 已安装"
else
  echo "  ⚠️  本机没装 yt-dlp，跳过实际下载测试"
fi

echo "=== 4. 参数化：保存目录可改 ==="
if grep -q 'TTDL_DIR' "$REPO/ttdl.sh"; then ok "TTDL_DIR 可配置"; else bad "缺 TTDL_DIR"; fi
if grep -q 'TTDL_PROXY' "$REPO/ttdl.sh"; then ok "TTDL_PROXY 可配置"; else bad "缺 TTDL_PROXY"; fi

echo "=== 5. 最高画质选择逻辑 ==="
grep -q 'S "res,br"' "$REPO/ttdl.sh" && ok "用 -S res,br 选最高档" || bad "没选最高档"
grep -q "hdplay" "$REPO/ttdl.sh" && ok "回退优先 hdplay（不是 play）" || bad "回退用了 play（只有 540p）"

echo "=== 6. 已知坑的防护 ==="
grep -q 'rm -f "\$out"' "$REPO/ttdl.sh" && ok "下载前删除同名文件" || bad "没删同名文件（会静默跳过）"
grep -q 'for attempt in 1 2 3' "$REPO/ttdl.sh" && ok "脚本层重试（应对 SSL 断流）" || bad "缺脚本层重试"
grep -q 'force-overwrites' "$REPO/ttdl.sh" && ok "force-overwrites 已开" || bad "缺 force-overwrites"

echo "=== 7. 空参数不炸 ==="
out=$(bash "$REPO/ttdl.sh" 2>&1)
echo "$out" | grep -q "完成" && ok "空参数正常退出" || bad "空参数行为异常: $out"

echo
echo "结果: $PASS 通过 / $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
