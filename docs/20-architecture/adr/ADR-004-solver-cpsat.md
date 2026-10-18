# ADR-004 求解器：服务端 OR-Tools CP-SAT，本地验证器 + 有限搜索

状态：已接受 · 2026-10-16

背景：任务书要求精确整数求解、状态语义、超时不等于无解；Flutter 无 CP-SAT。
决策：服务端 `planner.engine`（纯 Python，与 PoC 同源）用 CP-SAT 9.15，分层目标逐层求解，`num_workers=8`、固定 seed、`max_time_in_seconds` 按层分配；独立验证器复核每个解；Dart 端移植验证器与有限搜索（K≤3、候选切点枚举、≤2 s），只报告"本地未找到（非证明）"。
备选：MILP（HiGHS/CBC：分层目标与整数同样可行，但 CP-SAT 对整数/布尔组合与超时语义更贴合）；纯穷举（放弃：不精确）。
后果：双端协议与 golden fixtures 是硬性 CI 门槛；性能目标需实测（M2）。
