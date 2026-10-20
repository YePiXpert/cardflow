#!/usr/bin/env bash
# 本机模拟 Required Reason 扫描的结论与"缺登记即失败"（结论循环原样取自 workflow）。参数：hits.tsv、隐私清单。
set -euo pipefail
hits="$1"; manifest="$2"
out="$(mktemp -d /tmp/f1-ci/sim/out.XXXX)"
mkdir -p ios/Runner && cp "$manifest" ios/Runner/PrivacyInfo.xcprivacy
categories="UserDefaults FileTimestamp SystemBootTime DiskSpace"
{
echo "== 结论：主二进制或没有自带清单的 framework 命中的类别留在 ios/Runner/PrivacyInfo.xcprivacy，其余删除（理由码不变）"
for c in $categories; do
  need="$(awk -F '\t' -v c="$c" '$3 == c && ($2 == "main" || $2 == "no") {printf "%s ", $1}' "$hits")"
  covered="$(awk -F '\t' -v c="$c" '$3 == c && $2 == "yes" {printf "%s ", $1}' "$hits")"
  if grep -q "NSPrivacyAccessedAPICategory$c<" ios/Runner/PrivacyInfo.xcprivacy; then declared=已登记; else declared=未登记; fi
  if [ -n "$need" ]; then verdict=保留; else verdict=删除; fi
  if [ -n "$need" ] && [ "$declared" = 未登记 ]; then
    verdict="缺登记（失败）"
    echo "$c" >> "$out/missing.txt"
  fi
  echo "  $c：App 清单$declared；须由 App 清单承担的命中：${need:-无}；自带清单的 framework 命中：${covered:-无} → $verdict"
done
} | tee "$out/required-reason-scan.txt"
if [ -s "$out/missing.txt" ]; then
  echo "::error::Required Reason API categories hit by the main binary or a framework without its own privacy manifest, but not declared in ios/Runner/PrivacyInfo.xcprivacy: $(tr '\n' ' ' < "$out/missing.txt")"
  missing_scan=1
fi
if [ "${missing_scan:-0}" = 1 ]; then
  exit 1
fi
