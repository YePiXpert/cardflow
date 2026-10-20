#!/usr/bin/env bash
# 简报 F-1 的验收证据（evidence/f1/）：工具原文 tee；过滤见 filt.sh。用法：gen_evidence.sh [local|probes|ci|git]
set -uo pipefail
export PATH=/opt/flutter-sdk/bin:$PATH
R=/projects/cardflow
E=$R/evidence/f1
S=$E/scripts
F=$S/filt.sh
H=$S/hdr.sh
run() { echo "\$ $*"; ( eval "$@" ) 2>&1; echo "[exit=$?]"; echo; }
A="cd $R/apps/mobile"
D="cd $R/apps/mobile/packages/cardflow_domain"
part="${1:-all}"

if [ "$part" = all ] || [ "$part" = local ]; then
{
  $H format.txt "格式检查（App 与领域包）"
  run "$A && dart format --output=none --set-exit-if-changed ."
  run "$D && dart format --output=none --set-exit-if-changed ."
} 2>&1 | $F > $E/format.txt
{
  $H analyze.txt "静态分析（App 与领域包，--fatal-infos）"
  run "$A && flutter analyze --fatal-infos"
  run "$D && dart analyze --fatal-infos"
} 2>&1 | $F > $E/analyze.txt
{
  $H test.txt "App 全部测试（真实 sqlite3mc；--reporter expanded）与领域包全部测试"
  run "$A && flutter test --reporter expanded"
  run "$D && dart test --reporter expanded"
} 2>&1 | $F > $E/test.txt
{
  $H build-web.txt "Web 编译烟雾测试（含 off_main_isolate 的条件导入：Web 不引入 dart:isolate）"
  run "$A && flutter build web --release"
} 2>&1 | $F > $E/build-web.txt
fi

if [ "$part" = all ] || [ "$part" = probes ]; then
{
  $H review-probes.txt "I-1 阶段末审查探针改写的正式测试（断言修正后的期望值），逐个运行的输出"
  echo "# 对应：P1/P1b → ledger_test 的 F-30 已出账消费转分期两例（R-01）；P3/P3b/P4、冲正、M1–M4、Q-3、F-33 → review_probes_test（R-02/R-03/R-06/R-07/R-08）；"
  echo "#   有效状态表驱动 → statement_standing_test（R-03/R-06）；R-04 计时 → installment_cost_test；演示退出 → workspace_switch_test（R-15）；"
  echo "#   撤销入口 → ledger_actions_test（R-16、Q-3）；逐屏滚动 → accessibility_test 的文字放大与自检（R-12）。"
  echo "# 审查时的探针输出（错误行为）见 evidence/i1/review-i1/ledger-probe.txt、reversal-probe.txt、misc-probe.txt、demo-exit-probe.txt、perf-probe.txt、textscale-scroll.txt。"
  echo
  run "$A && flutter test test/data/repositories/ledger_test.dart --plain-name 已出账消费转分期 --reporter expanded"
  run "$A && flutter test test/data/repositories/ledger_test.dart --plain-name 同一时刻 --reporter expanded"
  run "$A && flutter test test/data/repositories/review_probes_test.dart --reporter expanded"
  run "$A && flutter test test/data/repositories/statement_standing_test.dart --reporter expanded"
  run "$A && flutter test test/features/statements/installment_cost_test.dart --reporter expanded"
  run "$A && flutter test test/app/workspace_switch_test.dart --reporter expanded"
  run "$A && flutter test test/features/statements/ledger_actions_test.dart --reporter expanded"
  run "$A && flutter test test/app/accessibility_test.dart --plain-name 文字放大 --reporter expanded"
  run "$A && flutter test test/app/accessibility_test.dart --plain-name 自检 --reporter expanded"
} 2>&1 | $F > $E/review-probes.txt
fi

if [ "$part" = all ] || [ "$part" = ci ]; then
{
  $H ci-dart-run.txt "CI（.github/workflows/mobile.yml）在 F-1 期间的 push 运行，与最后一次代码提交的运行详情（各 job 与步骤的结论）"
  echo "# 范围：F-1 第 1 步 7071101 起；只改 evidence/ 的提交不触发本工作流。步骤结论由 gh run view --json 取得（不含日志正文与 runner 镜像信息）。"
  echo
  run "cd $R && gh run list --workflow mobile.yml --event push --limit 10 --json databaseId,number,headSha,displayTitle,status,conclusion,createdAt --jq '.[] | select(.createdAt >= \"2026-10-19T16:00:00Z\") | \"\\(.databaseId) #\\(.number) \\(.headSha[0:7]) \\(.status) \\(.conclusion) \\(.createdAt)\\n    \\(.displayTitle)\"'"
  last="$(cd $R && gh run list --workflow mobile.yml --event push --limit 1 --json databaseId --jq '.[0].databaseId')"
  run "cd $R && gh run view $last --json number,headSha,event,headBranch,status,conclusion --jq '\"#\\(.number) \\(.event) \\(.headBranch) \\(.headSha[0:7]) \\(.status) \\(.conclusion)\"'"
  run "cd $R && gh run view $last --json jobs --jq '.jobs[] | \"== \\(.name)：\\(.conclusion)\", (.steps[] | \"   \\(.number). \\(.name)：\\(.conclusion)\")'"
  echo "# 缓存（审查 R-11）：dart job 日志里与 action 下载、actions/cache 的执行与命中有关的行（grep；行首是日志时间戳）。"
  job="$(cd $R && gh run view $last --json jobs --jq '.jobs[] | select(.name|startswith("dart")) | .databaseId')"
  run "cd $R && gh api repos/YePiXpert/cardflow/actions/jobs/$job/logs | grep -E \"Download action repository|Run actions/cache|Run subosito/flutter-action|Cache restored from key|Cache hit for|Cache not found|Cache saved|not saving cache\""
} 2>&1 | $F > $E/ci-dart-run.txt
fi

if [ "$part" = all ] || [ "$part" = git ]; then
{
  echo "# git-log.txt：F-1 的提交（9a44df1 之后，均已推送到 origin/main），及署名扫描"
  echo "# 生成时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)；本地 HEAD：$(git -C $R rev-parse --short HEAD)（本文件随后的证据提交不在列表中）"
  echo "# 过滤：无；以下为 git 原文。扫描用的正则把模型/厂商名里的一个字母写成字符类，避免证据里出现这些名字本身。"
  echo "# 说明：脚本开了 pipefail，grep 没有匹配时管道的退出码是 1（计数为 0 即没有署名字样）。"
  echo
  run "cd $R && git log --date=iso-strict --format='%h %ad %an <%ae>%n    %s%n    trailers:[%(trailers:only,separator=; )]' 9a44df1..HEAD"
  run "cd $R && git rev-parse HEAD origin/main"
  run "cd $R && git log 9a44df1..HEAD --format='%an <%ae> | %cn <%ce>' | sort | uniq -c"
  run "cd $R && git log 9a44df1..HEAD --format='%B' | grep -ciE 'cl[a]ude|anthr[o]pic|co-auth[o]red-by|generat[e]d with'"
  run "cd $R && grep -rniE 'cl[a]ude|anthr[o]pic|generat[e]d with' --exclude=git-log.txt apps/mobile/lib apps/mobile/test apps/mobile/README.md .github/workflows/mobile.yml evidence/f1 | wc -l"
  run "cd $R && git diff --stat 9a44df1 HEAD -- apps/mobile/lib/data/db apps/mobile/packages packages services docs && echo '（本地库结构与触发器、领域包、协议包、服务端、docs 均未改动）'"
  run "cd $R && git status --short"
} > $E/git-log.txt 2>&1
fi
