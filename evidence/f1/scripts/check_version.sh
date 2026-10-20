#!/usr/bin/env bash
# 本机模拟 Verify IPA 的版本断言（与 workflow 里同样的语句）；参数：pubspec 文件、IPA 版本、IPA 构建号。
set -euo pipefail
pubspec="$1"; version="$2"; build="$3"
pubspec_version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+).*$/\1/p' "$pubspec")"
test -n "$pubspec_version" || { echo "::error::cannot read the version name from pubspec.yaml"; exit 1; }
test "$version" = "$pubspec_version" || { echo "::error::CFBundleShortVersionString is $version, expected $pubspec_version (pubspec.yaml)"; exit 1; }
version_checked="pubspec.yaml $pubspec_version"
if [[ "$GITHUB_REF" == refs/tags/ios-v* ]]; then
  tag_version="${GITHUB_REF#refs/tags/ios-v}"
  test "$version" = "$tag_version" || { echo "::error::CFBundleShortVersionString is $version, expected $tag_version (tag ios-v$tag_version)"; exit 1; }
  version_checked="$version_checked, tag ios-v$tag_version"
fi
test "$build" = "$RUN_NUMBER" || { echo "::error::CFBundleVersion is $build, expected $RUN_NUMBER (github.run_number)"; exit 1; }
echo "CFBundleShortVersionString $version matches $version_checked; CFBundleVersion $build matches run number $RUN_NUMBER"
