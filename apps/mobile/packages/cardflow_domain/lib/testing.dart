/// 测试辅助（领域包与 App 的测试共用，产品代码不引用）：
///
/// * 按 Python 测试的写法构造协议 v1 文档：`protocolCard`、`protocolScenario`、`protocolEvent`、
///   `protocolDocument`、`protocolAllocation`、`deepCopyJson`；
/// * 带固定种子的随机小型文档：`TestRandom`、`randomPlanInput`、`randomAllocations`
///   （移植自 Python 差分测试的生成器，用于性质测试与跨语言一致性检查）。
library;

export 'src/testing/documents.dart';
export 'src/testing/random_documents.dart';
