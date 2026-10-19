// 账单有效状态的表驱动测试（PRD §6.2 的 2026-10-19 裁决段，简报 F-1 主会话裁决第 3 条）：剩余应还 =
// 新增账单 − 账单日之后银行入账的还款 + 转分期调整；> 0 → 未过到期日"待还"/"已还一部分"，过了"已逾期"；
// ≤ 0 → 转分期本身就结清了为"已转分期"，有入账还款时只按银行确认的也结清为"已还清"、否则"已入账（待银行
// 确认）"，没有要还的为"无需还款"（< 0 另显示贷方余额）。纯函数 `effectiveStatusOf`，不碰数据库。
import 'package:cardflow/data/mapping/ledger_mapping.dart';
import 'package:cardflow/data/repositories/ledger_models.dart';
import 'package:cardflow_domain/cardflow_domain.dart' show LocalDate;
import 'package:flutter_test/flutter_test.dart';

/// 一行：说明、新增账单、账单日之后入账的还款、其中银行确认的、转分期调整、今天、期望。到期日一律 10-28。
typedef _Row = (
  String,
  int basis,
  int paidAfter,
  int confirmed,
  int adjustment,
  LocalDate today,
  EffectiveStatementStatus expected,
);

final LocalDate _due = LocalDate(2026, 10, 28);
final LocalDate _before = LocalDate(2026, 10, 18);
final LocalDate _onDue = LocalDate(2026, 10, 28);
final LocalDate _after = LocalDate(2026, 10, 29);

final List<_Row> _rows = <_Row>[
  ('没有还款、未到期', 100000, 0, 0, 0, _before, EffectiveStatementStatus.due),
  ('到期日当天仍是待还（过了才逾期）', 100000, 0, 0, 0, _onDue, EffectiveStatementStatus.due),
  (
    '入账一部分、未到期',
    100000,
    40000,
    0,
    0,
    _before,
    EffectiveStatementStatus.partiallyPaid,
  ),
  (
    '入账一部分且已确认、未到期',
    100000,
    40000,
    40000,
    0,
    _before,
    EffectiveStatementStatus.partiallyPaid,
  ),
  ('没有还款、过了到期日', 100000, 0, 0, 0, _after, EffectiveStatementStatus.overdue),
  (
    '还了一部分、过了到期日',
    100000,
    40000,
    40000,
    0,
    _after,
    EffectiveStatementStatus.overdue,
  ),
  ('银行确认足额', 100000, 100000, 100000, 0, _before, EffectiveStatementStatus.paid),
  (
    '银行确认足额、过了到期日也不算逾期',
    100000,
    100000,
    100000,
    0,
    _after,
    EffectiveStatementStatus.paid,
  ),
  (
    '多还（贷方余额 200）且银行确认',
    100000,
    120000,
    120000,
    0,
    _before,
    EffectiveStatementStatus.paid,
  ),
  (
    '足额但只有入账、没有银行确认',
    100000,
    100000,
    0,
    0,
    _before,
    EffectiveStatementStatus.postedAwaitingBank,
  ),
  (
    '足额，其中银行确认的只够一部分',
    100000,
    100000,
    60000,
    0,
    _after,
    EffectiveStatementStatus.postedAwaitingBank,
  ),
  (
    '已出账消费整笔转分期、首期在下一期',
    1200000,
    0,
    0,
    -1200000,
    _before,
    EffectiveStatementStatus.converted,
  ),
  (
    '转分期后多出来的还款仍是"已转分期"（贷方余额）',
    1200000,
    50000,
    50000,
    -1200000,
    _before,
    EffectiveStatementStatus.converted,
  ),
  (
    '首期就在这一期：还剩首期本金与手续费',
    1200000,
    0,
    0,
    -1092800,
    _before,
    EffectiveStatementStatus.due,
  ),
  (
    '转分期后其余部分由银行确认的还款结清',
    1300000,
    100000,
    100000,
    -1200000,
    _before,
    EffectiveStatementStatus.paid,
  ),
  ('新增账单为 0、没有还款', 0, 0, 0, 0, _before, EffectiveStatementStatus.nothingDue),
  (
    '溢缴（新增账单为负）、没有还款',
    -50000,
    0,
    0,
    0,
    _after,
    EffectiveStatementStatus.nothingDue,
  ),
  (
    '溢缴后又入账一笔、银行确认',
    -50000,
    10000,
    10000,
    0,
    _before,
    EffectiveStatementStatus.paid,
  ),
];

void main() {
  for (final (name, basis, paid, confirmed, adjustment, today, expected)
      in _rows) {
    test('$name → ${expected.label}', () {
      expect(
        effectiveStatusOf(
          basis: basis,
          paidAfter: paid,
          paidAfterConfirmed: confirmed,
          adjustment: adjustment,
          dueDate: _due,
          today: today,
        ),
        expected,
      );
    });
  }

  test('还欠着的只有"待还""已还一部分""已逾期"（近期到期与负债只看它们）', () {
    expect(
      <EffectiveStatementStatus>{
        for (final s in EffectiveStatementStatus.values)
          if (s.owes) s,
      },
      <EffectiveStatementStatus>{
        EffectiveStatementStatus.due,
        EffectiveStatementStatus.partiallyPaid,
        EffectiveStatementStatus.overdue,
      },
    );
  });

  test('有效状态覆盖了表里的每一种（已并入下一期另在 review_probes_test 的 P3 里经读模型测）', () {
    expect(
      <EffectiveStatementStatus>{for (final row in _rows) row.$7},
      EffectiveStatementStatus.values.toSet()
        ..remove(EffectiveStatementStatus.merged),
    );
  });
}
