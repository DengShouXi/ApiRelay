#!/bin/bash
# ApiRelay 项目自检
#
# 用法：bash ApiRelay/scripts/selfcheck.sh
# 退出码：0 = 无红线问题；1 = 有红线问题
#
# 只做「能数出来」的检查，结论 100% 可信，不做任何需要判断的事。
# 需要判断的（这个设计有没有坑、提示用户看不看得懂）交给人或贵模型。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ ! -d "$ROOT/ApiRelay.xcodeproj" ]; then
    echo "✗ 定位失败：$ROOT 下没有 ApiRelay.xcodeproj"
    echo "  本脚本必须放在 <仓库根>/ApiRelay/scripts/selfcheck.sh"
    exit 1
fi
cd "$ROOT" || exit 1

SRC="ApiRelay"
TESTS="ApiRelayTests"
LINE_LIMIT=400
FAIL=0

echo "════════════════════════════════════════════════════"
echo " ApiRelay 项目自检    $(date '+%Y-%m-%d %H:%M')"
echo " 目录：$ROOT"
echo "════════════════════════════════════════════════════"

# ─────────────────────────────────────────────
# 红线 1：测试不得绕过 KeychainStore.makeForTests()
# ─────────────────────────────────────────────
echo ""
echo "【红线 1】测试是否绕过 KeychainStore.makeForTests()"
HITS=$(grep -rn "KeychainStore(" "$TESTS" --include="*.swift" 2>/dev/null \
        | grep -v "Support/KeychainStore+Tests.swift" \
        | grep -v "自检豁免" || true)
if [ -n "$HITS" ]; then
    echo "  ✗ 失败"
    echo "$HITS" | sed 's/^/     /'
    echo ""
    echo "     测试 bundle 由 ApiRelay.app 宿主加载，进程带的是 App 的 entitlements，"
    echo "     而 keychain-access-groups 只有一个组——直接构造会落进 App 自己那个组，"
    echo "     setUp/tearDown 的清理会删掉用户本机真实的主密码与密钥明文。"
    echo "     改用 KeychainStore.makeForTests()。"
    echo "     确有必要读生产条目时，在该行加注释：// 自检豁免: <理由>"
    FAIL=1
else
    echo "  ✓ 通过"
fi

# ─────────────────────────────────────────────
# 报告 1：过大的源文件
# ─────────────────────────────────────────────
echo ""
echo "【报告 1】超过 ${LINE_LIMIT} 行的生产源文件（越靠前越该拆）"
BIG=$(find "$SRC" -name "*.swift" -type f -exec wc -l {} + 2>/dev/null \
        | grep -v " total$" \
        | awk -v lim="$LINE_LIMIT" '$1 > lim {printf "     %6d  %s\n", $1, $2}' \
        | sort -rn)
if [ -n "$BIG" ]; then
    echo "$BIG"
    COUNT=$(echo "$BIG" | wc -l | tr -d ' ')
    echo "     —— 共 $COUNT 个。改到哪个就顺手拆哪个，不要专门开大重构。"
else
    echo "     （无）"
fi

# ─────────────────────────────────────────────
# 报告 2：被吞掉的错误
# ─────────────────────────────────────────────
echo ""
echo "【报告 2】生产代码 try? 分布（每一处都在说「这个失败可以忽略」）"
TRYQ=$(grep -rc "try?" "$SRC" --include="*.swift" 2>/dev/null \
        | awk -F: '$2 > 0 {printf "     %4d  %s\n", $2, $1}' \
        | sort -rn)
if [ -n "$TRYQ" ]; then
    echo "$TRYQ"
    TOTAL=$(echo "$TRYQ" | awk '{s+=$1} END {print s+0}')
    echo "     —— 合计 $TOTAL 处。写不出「为什么这个失败可以忽略」的，就该改成显式处理。"
else
    echo "     （无）"
fi

# ─────────────────────────────────────────────
# 报告 3：接缝有没有用起来
# ─────────────────────────────────────────────
echo ""
echo "【报告 3】每个协议的生产实现数 / 测试替身数"
echo "     替身数为 0 = 这个接缝定了但没用起来，相关测试只能用真零件"
printf "     %-30s %8s %8s\n" "协议" "生产实现" "测试替身"
for p in $(grep -rho "^protocol [A-Za-z]*" "$SRC" --include="*.swift" 2>/dev/null \
            | awk '{print $2}' | sort -u); do
    prod=$(grep -rl ":[[:space:]]*$p\b\|,[[:space:]]*$p\b" "$SRC" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
    fake=$(grep -rl ":[[:space:]]*$p\b\|,[[:space:]]*$p\b" "$TESTS" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
    mark=""
    [ "$fake" -eq 0 ] && mark="  ← 无替身"
    printf "     %-30s %8s %8s%s\n" "$p" "$prod" "$fake" "$mark"
done

# ─────────────────────────────────────────────
# 报告 4：运行环境判断散落处
# ─────────────────────────────────────────────
echo ""
echo "【报告 4】「现在是不是在跑测试」判断了几次（应当只有一处权威）"
ENVJ=$(grep -rn "XCTestConfigurationFilePath" "$SRC" --include="*.swift" 2>/dev/null || true)
if [ -n "$ENVJ" ]; then
    echo "$ENVJ" | sed 's/^/     /'
    N=$(echo "$ENVJ" | wc -l | tr -d ' ')
    echo "     —— 共 $N 处。多于 1 处就意味着每处各自决定测试时怎么变，迟早不一致。"
else
    echo "     （无）"
fi

# ─────────────────────────────────────────────
# 报告 5：各层代码量
# ─────────────────────────────────────────────
echo ""
echo "【报告 5】各层代码量"
for d in App UI Business Data Shared; do
    if [ -d "$SRC/$d" ]; then
        n=$(find "$SRC/$d" -name "*.swift" | wc -l | tr -d ' ')
        l=$(find "$SRC/$d" -name "*.swift" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
        printf "     %-10s %3s 个文件  %6s 行\n" "$d" "$n" "$l"
    fi
done
tn=$(find "$TESTS" -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
tl=$(find "$TESTS" -name "*.swift" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
tc=$(grep -rc "func test" "$TESTS" --include="*.swift" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
printf "     %-10s %3s 个文件  %6s 行  %s 个用例\n" "测试" "$tn" "$tl" "$tc"

# ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
    echo " 红线检查：全部通过"
else
    echo " 红线检查：有失败项，见上方 ✗"
fi
echo "════════════════════════════════════════════════════"
exit "$FAIL"
