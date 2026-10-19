#!/usr/bin/env bash
# 用法：hdr.sh <标题>  打印证据文件头
echo "# $1"
echo "# 生成时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)；仓库 HEAD $(git -C /projects/cardflow rev-parse --short HEAD)；审查 R-I1"
echo "# 过滤：flutter/dart 工具打印的宿主运行环境提示（固定 4 行）、含发行版/内核/代理状态字样的行（grep -Ev，脚本见 scripts/filt.sh）；其余为工具原文"
echo
