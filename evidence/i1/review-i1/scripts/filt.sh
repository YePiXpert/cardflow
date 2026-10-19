#!/usr/bin/env bash
# 过滤宿主信息：flutter/dart 工具打印的宿主运行环境提示（固定 4 行）、发行版/内核/代理状态行。
grep -aEv 'Woah! You appear|We strongly recommend running the flutter tool|^  /$|^📎$|Debian|Linux 6\.|deb13|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|proxy'
