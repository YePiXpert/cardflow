# 90 · 项目说明视频（宣传片）

`cardflow-promo.mp4`：1 分 46 秒，1920×1080，30 fps，H.264 + AAC，中文字幕与配乐。内容：为什么做 → 卡包与账期 → 现金与资金日历 → 账单、分期、还款 → 消费规划（I-2，开发中）→ 隐私与可信 → 片尾。视频中的界面为示意图（按 ui-spec 的页面与色彩 token 用 HTML 画的），数据为演示数据；分期成本的数字（每期费率 0.6%，名义年化 7.2%、实际年化约 13.8%）来自引擎 `money.py` 的 `irr_monthly`/`annualize` 实测。

## 怎么重新生成

- `promo.html`：全部画面与时间轴。页面暴露 `window.TOTAL_MS`、`window.SCENE_STARTS`、`window.seek(ms)`，所有动画都是 `seek(t)` 的确定性函数，逐帧截图可复现。
- `render.py`：用 Playwright 驱动系统 Chromium（`/usr/bin/chromium`）逐帧截图，经管道送入 ffmpeg（`imageio-ffmpeg` 自带的静态 ffmpeg，含 libx264）编码；`--preview 1500,9000` 只出关键帧 PNG 到 `preview/`。
- `music.py`：numpy 合成的环境配乐（暖垫 + 低音 + 稀疏拨弦，每个场景开头一声铃），确定性种子，1 s 淡入、4 s 淡出。

```bash
uv venv .venv && uv pip install --python .venv/bin/python playwright numpy imageio-ffmpeg
.venv/bin/python render.py --preview 2500,16000,32000    # 关键帧检查
.venv/bin/python render.py --out cardflow-promo.mp4        # 完整渲染（约 2.5 分钟）
```

需要中文字体（本机用文泉驿微米黑；缺字体时 Chromium 会显示方块）。改文案只改 `promo.html`；改时长改 `SCENES` 表与各元素的 `data-in` 毫秒值。
