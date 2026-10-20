#!/usr/bin/env bash
# 证据过滤（审查 R-13 的写法）：去掉 flutter/dart 工具打印的宿主运行环境提示（固定 4 行），其余原样保留。
grep -aEv 'Woah! You appear|We strongly recommend running the flutter tool|^  /$|^📎$'
