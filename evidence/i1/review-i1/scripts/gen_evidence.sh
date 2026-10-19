#!/usr/bin/env bash
# 审查 R-I1：重新生成 evidence/i1/review-i1/*.txt（工具原文 tee；过滤见 scripts/filt.sh）。
set -uo pipefail
export PATH=/opt/flutter-sdk/bin:$PATH
R=/projects/cardflow
E=$R/evidence/i1/review-i1
S=$E/scripts
F=$S/filt.sh
H=$S/hdr.sh
run() { echo "\$ $*"; ( eval "$@" ) 2>&1; echo "[exit=$?]"; echo; }
quiet_pub() { grep -aEv 'available\)$|^Resolving dependencies|^Downloading packages|^Got dependencies|newer versions incompatible|flutter pub outdated'; }

part="${1:-all}"

if [ "$part" = all ] || [ "$part" = baseline ]; then
{
  $H "App 基线：format / analyze / test（apps/mobile，真实 sqlite3mc，--reporter expanded）"
  run "cd $R/apps/mobile && dart format --output=none --set-exit-if-changed ."
  run "cd $R/apps/mobile && flutter analyze --fatal-infos"
  run "cd $R/apps/mobile && flutter test --reporter expanded"
} 2>&1 | $F > $E/app-baseline.txt
{
  $H "领域包基线：format / analyze / test（apps/mobile/packages/cardflow_domain）"
  run "cd $R/apps/mobile/packages/cardflow_domain && dart format --output=none --set-exit-if-changed ."
  run "cd $R/apps/mobile/packages/cardflow_domain && dart analyze --fatal-infos"
  run "cd $R/apps/mobile/packages/cardflow_domain && dart test --reporter expanded"
} 2>&1 | $F > $E/domain-baseline.txt
fi

probe() { # probe <证据名> <标题> <脚本> [额外参数]
  local out="$1" title="$2" script="$3"; shift 3
  {
    $H "$title"
    run "cd $R/apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/$script --reporter expanded $*"
  } 2>&1 | $F | quiet_pub > "$E/$out"
}

if [ "$part" = all ] || [ "$part" = probes ]; then
probe ledger-probe.txt "负债四分法与跨期分配探针（R-01、R-02）：P1/P1b 已出账消费转分期；P3/P3b 迟付与旧账单；P4 早于账单日的还款；P2 追加只读（R-05）" ledger_probe_test.dart
probe append-only-probe.txt "账单版本追加只读的数据库兜底探针（R-05）：DELETE+同 id 重插、INSERT OR REPLACE" append_only_probe_test.dart
probe reversal-probe.txt "冲正探针（R-03，BL-29）：银行确认 → 冲正之后的状态、剩余应还、近期到期与逾期" reversal_probe_test.dart
probe misc-probe.txt "其他探针（R-06 修正后状态、R-07 删除交易后的差异项、R-08 删除有交易的子账户）" misc_probe_test.dart
probe date-props.txt "日期边界性质探针：周期事项展开、业务日期、截止时点、时刻写法" date_props_probe_test.dart
probe textscale-scroll.txt "2.0x/3.0x 字号逐屏滚到底（演示空间 46 个页面），收集布局溢出等框架错误" textscale_scroll_probe_test.dart
probe demo-exit-probe.txt "演示空间里打开全屏表单 → 横幅「退出演示」→ 保存：写进了哪个空间（R-15）" demo_exit_form_probe_test.dart
probe perf-probe.txt "大数据量计算耗时（flutter test，JIT/调试模式，真实加密库）" perf_probe_test.dart
fi

if [ "$part" = all ] || [ "$part" = migration ]; then
{
  $H "迁移与外键核对：新建 vs 从 v1/v2/v3 升级的结构（复现 I1-c schema-diff 的哈希）、冻结 SQL 未改、各 IPA 之间库代码未变、外键生效"
  rm -rf /tmp/rv1/schema && mkdir -p /tmp/rv1/schema
  run "cd $R/apps/mobile && CARDFLOW_SCHEMA_DUMP_DIR=/tmp/rv1/schema flutter test test/data/db/schema_test.dart --reporter expanded"
  run "cd /tmp/rv1/schema && sha256sum fresh-v4.txt upgraded-from-v1.txt upgraded-from-v2.txt upgraded-from-v3.txt"
  run "cd /tmp/rv1/schema && diff fresh-v4.txt upgraded-from-v1.txt && diff fresh-v4.txt upgraded-from-v2.txt && diff fresh-v4.txt upgraded-from-v3.txt && echo IDENTICAL"
  run "grep -n 'b41dbeb012d6995af193aa0dace37203869aa0eae6d2182ca27546b1246da501' $R/evidence/i1/I1-c/schema-diff.txt | head -1"
  run "cd $R && for c in f0cc636 201c8da 4c77d44 HEAD; do echo \"== \$c SchemaV2 / SchemaV3 冻结段的 sha256\"; git show \$c:apps/mobile/lib/data/db/schema.dart | awk '/^abstract final class SchemaV2/,/^}/' | sha256sum; git show \$c:apps/mobile/lib/data/db/schema.dart | awk '/^abstract final class SchemaV3/,/^}/' | sha256sum; done"
  run "cd $R && git log --format='%h %ad' --date=short -- apps/mobile/lib/data/db/schema.dart"
  run "cd $R && gh run list --workflow mobile.yml --limit 100 --json databaseId,headSha,event,headBranch,conclusion --jq '.[] | select(.event==\"workflow_dispatch\" or (.headBranch|startswith(\"ios-v\"))) | \"\\(.databaseId) \\(.headSha[0:7]) \\(.event) \\(.headBranch) \\(.conclusion)\"'"
  run "cd $R && git diff --stat 6547054 83be815 -- apps/mobile/lib/data/db/ && echo '（6547054..83be815 之间 lib/data/db 无改动）'"
  run "cd $R && git diff --stat 83be815 13d72c0 -- apps .github packages services && echo '（发版标签之后代码无改动）'"
  run "cd $R && git show 4d720c9:apps/mobile/lib/data/db/schema.dart | sed -n '/^Future<void> createSchema/,/^}\$/p'"
  run "cd $R && git diff 4d720c9 HEAD --stat -- apps/mobile/lib/data/db/database_key.dart apps/mobile/lib/data/db/encryption.dart"
  run "cd $R/apps/mobile && flutter test ../../evidence/i1/review-i1/scripts/migration_fk_probe_test.dart --reporter expanded"
} 2>&1 | $F | quiet_pub > $E/migration-check.txt
fi

if [ "$part" = all ] || [ "$part" = parity ]; then
{
  $H "分期模块与 Python money.py 的随机/边界对照（278 例：拆分、费用、月 IRR、复利年化、名义、界面百分数文本）与 IRR 耗时（AOT）"
  rm -rf /tmp/rv1/dart2 && mkdir -p /tmp/rv1/dart2 && cp -r $S/dart/. /tmp/rv1/dart2/
  run "cd $R/services/api && uv run --offline python -I $S/py/installment_cases.py /tmp/rv1/parity/installment_cases.json"
  run "sha256sum /tmp/rv1/parity/installment_cases.json"
  run "cd /tmp/rv1/dart2 && dart pub get --offline > /dev/null && dart compile exe bin/installment_parity.dart -o /tmp/rv1/dart2/installment_parity > /dev/null && /tmp/rv1/dart2/installment_parity /tmp/rv1/parity/installment_cases.json"
  run "cd /tmp/rv1/dart2 && dart compile exe bin/irr_timing.dart -o /tmp/rv1/dart2/irr_timing > /dev/null && /tmp/rv1/dart2/irr_timing && /tmp/rv1/dart2/irr_timing"
} 2>&1 | $F | quiet_pub > $E/installment-parity.txt
fi

if [ "$part" = all ] || [ "$part" = ci ]; then
{
  $H "CI 与发布核对：mobile.yml 的 action 固定、失败掩盖、产出数断言、发版构建的 Required Reason 扫描结论"
  run "cd $R && ls .github/workflows/"
  run "cd $R && grep -n 'uses:' .github/workflows/mobile.yml"
  run "cd $R && for spec in 'actions/checkout v7.0.1' 'subosito/flutter-action v2.23.0' 'astral-sh/setup-uv v10.3.0' 'actions/upload-artifact v7.0.2'; do set -- \$spec; r=\$(gh api repos/\$1/git/ref/tags/\$2 --jq '.object.type + \" \" + .object.sha'); t=\${r%% *}; s=\${r##* }; if [ \"\$t\" = tag ]; then s=\$(gh api repos/\$1/git/tags/\$s --jq '.object.sha'); fi; echo \"\$1 \$2 -> \$s (\$t)\"; done"
  run "gh api 'repos/subosito/flutter-action/contents/action.yaml?ref=1a449444c387b1966244ae4d4f8c696479add0b2' --jq '.content' | base64 -d | grep -n 'uses:'"
  run "cd $R && grep -n 'continue-on-error\\||| true\\|if: always\\|if: failure' .github/workflows/mobile.yml"
  run "cd $R && grep -n 'EXPECTED_\\|test \"\\\$n\"\\|test \"\\\$m\"\\|checked != expected\\|diff -r' .github/workflows/mobile.yml"
  run "cd $R && grep -n 'read_key\\|test \"\\\$bundle_id\\|test \"\\\$min_os\\|test \"\\\$icon_name\\|version=\\|build=' .github/workflows/mobile.yml | head -20"
  run "rm -rf /tmp/rv1/scan55 && mkdir -p /tmp/rv1/scan55 && gh run download 39268709025 -R YePiXpert/cardflow -n required-reason-scan -D /tmp/rv1/scan55 && sed -n '1,30p;/^== 结论/,\$p' /tmp/rv1/scan55/required-reason-scan.txt"
  run "cd $R && gh run view 39268709025 --json number,event,headBranch,headSha,conclusion --jq '\"\\(.number) \\(.event) \\(.headBranch) \\(.headSha[0:7]) \\(.conclusion)\"'"
} 2>&1 | $F > $E/ci-check.txt
fi

if [ "$part" = all ] || [ "$part" = hygiene ]; then
{
  $H "公开仓库卫生与隔离扫描：邮箱/令牌/IP/端口/宿主信息/Luhn 卡号形态（不回显数字）；提交身份与署名；数据层查询的工作空间过滤"
  run "python3 -I $S/py/hygiene.py $R apps/mobile evidence/i1 .github | grep -v 'users.noreply.github.com\\|@[123]x.png'"
  run "cd $R && git log --format='%an <%ae> | %cn <%ce>' | sort | uniq -c"
  run "cd $R && git log --format='%B' | grep -i -c 'claude\\|co-authored\\|anthropic\\|generated with' ; true"
  run "cd $R && git grep -n -i 'claude\\|anthropic' -- apps/mobile evidence/i1 .github README.md | grep -v 'git-log.txt' ; true"
  run "cd $R && git grep -n 'opt/flutter-sdk\\|/root/\\|5432\\|HTTP_PROXY' -- evidence/i1 apps/mobile .github ; true"
  run "python3 -I $S/py/scan_queries.py $R/apps/mobile/lib/data"
} 2>&1 | $F > $E/hygiene-scan.txt
fi

if [ "$part" = all ] || [ "$part" = ui ]; then
{
  $H "界面入口核对（R-16）：仓库已有的交易删除/补入账日、分期作废方法，在界面里有没有入口"
  run "cd $R/apps/mobile && grep -n 'Future<void> delete(String id)\\|Future<void> markPosted(String id\\|Future<void> cancel(String planId)' lib/data/repositories/transaction_repository.dart lib/data/repositories/installment_repository.dart"
  run "cd $R/apps/mobile && grep -rn 'transactionRepositoryProvider\\|installmentRepositoryProvider' lib/features"
  run "cd $R/apps/mobile && grep -rn '\\.cancel(\\|markPosted(' lib/features ; true"
  run "cd $R/apps/mobile && grep -n 'static String newTransaction\\|static String newInstallment\\|transactions/' lib/app/routes.dart"
  run "cd $R/apps/mobile && grep -rn '\\.delete(' lib/features"
} 2>&1 | $F > $E/ui-entry-check.txt
fi
