#!/usr/bin/env bash
# 简报 U-1 的验收证据（evidence/u1/）：工具原文 tee；过滤见 filt.sh。用法：gen_evidence.sh [local|screens|ci|git]
set -uo pipefail
export PATH=/opt/flutter-sdk/bin:$PATH
R=/projects/cardflow
E=$R/evidence/u1
S=$E/scripts
F=$S/filt.sh
H=$S/hdr.sh
BASE=715a8c2   # U-1 开始前 main 的最后一个提交（主会话的文档提交）
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
  echo "# 说明：两项跳过的是截图工具 test/tool/screenshots_test.dart（只在 CARDFLOW_SCREENSHOTS=1 时运行，见 screenshots.txt）。"
  echo
  run "$A && flutter test --reporter expanded"
  run "$D && dart test --reporter expanded"
} 2>&1 | $F > $E/test.txt
{
  $H build-web.txt "Web 编译烟雾测试"
  run "$A && flutter build web --release"
} 2>&1 | $F > $E/build-web.txt
fi

if [ "$part" = all ] || [ "$part" = screens ]; then
{
  $H screenshots.txt "截图工具的运行输出与截图清单（演示空间，固定\"今天\" 2026-10-16；深色与浅色）"
  echo "# 截图从 apps/mobile/build/screenshots/ 复制到 evidence/u1/screens/（PNG，1179×2556，即 393×852 的 3 倍）。"
  echo
  run "$A && rm -rf build/screenshots && CARDFLOW_SCREENSHOTS=1 flutter test test/tool/screenshots_test.dart --reporter expanded"
  run "rm -f $E/screens/*.png && cp $R/apps/mobile/build/screenshots/*.png $E/screens/ && ls $E/screens | wc -l"
  run "python3 -I $S/png_size.py $E/screens"
} 2>&1 | $F > $E/screenshots.txt
fi

if [ "$part" = all ] || [ "$part" = ci ]; then
{
  $H ci-dart-run.txt "CI（.github/workflows/mobile.yml）在 U-1 期间的 push 运行，与最后一次代码提交的运行详情（各 job 与步骤的结论）"
  echo "# 范围：U-1 第 1 步 0b24705 起（#66–#81，共 16 次 push 运行）。两次失败都已在下一个提交修正："
  echo "#   #71（c63a294）：一个测试文件改动后没有重新 dart format，格式检查失败 → f47f026 重排后通过；"
  echo "#   #78（9d59ba7）：诊断日志测试断言报告行里不含\"1234\"，而行首时间戳精确到微秒、那次碰巧含有\"1234\" → 36df86b 改为只检查时间戳之后的部分。"
  echo "# 只改 evidence/ 的提交（先前的证据提交 e08ca76 与本次证据提交）不触发本工作流。步骤结论由 gh run view --json 取得（不含日志正文与 runner 镜像信息）。"
  echo
  run "cd $R && gh run list --workflow mobile.yml --event push --limit 20 --json databaseId,number,headSha,displayTitle,status,conclusion,createdAt --jq '.[] | select(.createdAt >= \"2026-10-20T02:06:00Z\") | \"\\(.databaseId) #\\(.number) \\(.headSha[0:7]) \\(.status) \\(.conclusion) \\(.createdAt)\\n    \\(.displayTitle)\"'"
  last="$(cd $R && gh run list --workflow mobile.yml --event push --limit 1 --json databaseId --jq '.[0].databaseId')"
  run "cd $R && gh run view $last --json databaseId,number,headSha,event,headBranch,status,conclusion --jq '\"\\(.databaseId) #\\(.number) \\(.event) \\(.headBranch) \\(.headSha[0:7]) \\(.status) \\(.conclusion)\"'"
  run "cd $R && gh run view $last --json jobs --jq '.jobs[] | \"== \\(.name)：\\(.conclusion)\", (.steps[] | \"   \\(.number). \\(.name)：\\(.conclusion)\")'"
  echo "# dart job 的测试汇总行（grep；行首是日志时间戳）。"
  job="$(cd $R && gh run view $last --json jobs --jq '.jobs[] | select(.name|startswith("dart")) | .databaseId')"
  run "cd $R && gh api repos/YePiXpert/cardflow/actions/jobs/$job/logs | grep -E 'tests passed|All tests passed|Some tests failed|No issues found|Formatted [0-9]+ files|Built build/web'"
} 2>&1 | $F > $E/ci-dart-run.txt
fi

if [ "$part" = all ] || [ "$part" = git ]; then
{
  echo "# git-log.txt：U-1 的提交（$BASE 之后，均已推送到 origin/main），及署名扫描与不得改动目录的核对"
  echo "# 生成时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)；本地 HEAD：$(git -C $R rev-parse --short HEAD)（本文件随后的证据提交不在列表中；e08ca76 是先前的一次证据提交，本次证据重新生成后替换它的文件）"
  echo "# 过滤：无；以下为 git 原文。扫描用的正则把模型/厂商名里的一个字母写成字符类，避免证据里出现这些名字本身。"
  echo "# 说明：脚本开了 pipefail，grep 没有匹配时管道的退出码是 1（计数为 0 即没有署名字样）。"
  echo
  run "cd $R && git log --date=iso-strict --format='%h %ad %an <%ae>%n    %s%n    trailers:[%(trailers:only,separator=; )]' $BASE..HEAD"
  run "cd $R && git rev-parse HEAD origin/main"
  run "cd $R && git log $BASE..HEAD --format='%an <%ae> | %cn <%ce>' | sort | uniq -c"
  run "cd $R && git log $BASE..HEAD --format='%B' | grep -ciE 'cl[a]ude|anthr[o]pic|co-auth[o]red-by|generat[e]d with'"
  run "cd $R && grep -rniE 'cl[a]ude|anthr[o]pic|generat[e]d with' --exclude=git-log.txt apps/mobile/lib apps/mobile/test apps/mobile/README.md README.md evidence/u1 | wc -l"
  run "cd $R && git diff --stat $BASE HEAD -- apps/mobile/lib/data/db apps/mobile/packages packages services docs .github && echo '（本地库结构与触发器、领域包、协议包、服务端、docs、.github 均未改动）'"
  run "cd $R && git diff --stat $BASE HEAD -- apps/mobile/pubspec.yaml apps/mobile/pubspec.lock && git diff $BASE HEAD -- apps/mobile/pubspec.yaml"
  run "cd $R && git status --short"
} > $E/git-log.txt 2>&1
fi
