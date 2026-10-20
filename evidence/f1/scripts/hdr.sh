#!/usr/bin/env bash
# 用法：hdr.sh <文件名> <标题>  打印证据文件头（生成时间、源码提交、过滤说明）。
echo "# $1：$2"
echo "# 生成时间：$(date -u +%Y-%m-%dT%H:%M:%SZ)；源码提交：$(git -C /projects/cardflow rev-parse --short HEAD)（= origin/main：$(git -C /projects/cardflow rev-parse --short origin/main)）"
echo "# 过滤：工具打印的宿主运行环境提示（固定 4 行），grep -Ev，脚本见 evidence/f1/scripts/filt.sh；其余为工具原文，未删节。"
echo
