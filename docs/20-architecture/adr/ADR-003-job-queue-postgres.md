# ADR-003 任务队列：基于 PostgreSQL 的 jobs 表，不引入 Redis

状态：已接受 · 2026-10-16

背景：任务类型有限（解析、求解、通知投递、活动抓取、备份、同步压缩），需要持久化、重试、超时、死信、后台可见；个人自用规模（每日数十到数百任务）。
决策：自建 `jobs` 表 + `FOR UPDATE SKIP LOCKED` 领取 + 心跳/租约 + 指数退避 + 死信；周期任务用 apscheduler 3.x 在 worker 内触发入队。任务与业务数据同库同事务（入队与业务写入原子）。
备选：procrastinate 3.10（PG 队列，功能完整但 README 招募维护者）、celery/dramatiq（需 broker）、arq（Redis，维护模式）。
后果：需自行实现约 300 行队列代码与测试；规模增长到每分钟千级任务时再评估 procrastinate。
