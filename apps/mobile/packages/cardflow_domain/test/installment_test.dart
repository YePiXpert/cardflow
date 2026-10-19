// installment 模块（简报 I1-c §6 第 1 条）：与 Python `services/api/cardflow/planner/engine/money.py` 的
// split_installments、installment_cash_flows、irr_monthly、annualize 逐条同义。
//
// - 性质：移植 Python `tests/engine/test_properties.py::test_installment_split_conserves_principal`
//   （随机本金/期数守恒、除尾差那一期外各期相等），200 例，固定种子；
// - F-36（12 期拆分守恒、尾差在末期）、F-37（月费率 1.5%：名义 18% 与复利年化、IRR 并列，IRR 不等于名义值）；
// - Python 对照：下面 [_pythonSamples] 的期望值是在本机用
//   `cd services/api && uv run --offline python -c "$(cat installment_parity.py)"` 调用上述 4 个 Python 函数
//   的原文输出（命令与输出见 evidence/i1/I1-c/installment-parity.txt）：拆分与各期费用逐期相等、月 IRR 相差
//   < 10^-9、名义与复利年化相等到 10 位小数。
import 'package:cardflow_domain/cardflow_domain.dart';
import 'package:cardflow_domain/testing.dart' show TestRandom;
import 'package:test/test.dart';

Rational r(String text) => Rational.parseDecimal(text);

/// 四舍五入到 [places] 位小数后的整数（比较"相等到 10 位小数"用）。
BigInt scaled(Rational value, int places) =>
    (value * Rational(BigInt.from(10).pow(places))).round(RoundingMode.halfUp);

final class _PySample {
  const _PySample({
    required this.name,
    required this.principal,
    required this.periods,
    required this.rate,
    required this.remainder,
    required this.split,
    required this.flows,
    required this.irr,
    required this.rateNominalX12,
    required this.rateEffectiveCompound,
    required this.irrNominalX12,
    required this.irrEffectiveCompound,
  });

  final String name;
  final int principal;
  final int periods;
  final String rate;
  final RemainderTo remainder;
  final List<int> split;

  /// Python 的 `(期号, 本金, 费用)`。
  final List<(int, int, int)> flows;
  final String irr;
  final String rateNominalX12;
  final String rateEffectiveCompound;
  final String irrNominalX12;
  final String irrEffectiveCompound;
}

/// Python 的原文输出（见文件头）。
const List<_PySample> _pythonSamples = <_PySample>[
  _PySample(
    name: 'F-36',
    principal: 1000000,
    periods: 12,
    rate: '0.006',
    remainder: RemainderTo.last,
    split: <int>[
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83333,
      83337,
    ],
    flows: <(int, int, int)>[
      (1, 83333, 6000),
      (2, 83333, 6000),
      (3, 83333, 6000),
      (4, 83333, 6000),
      (5, 83333, 6000),
      (6, 83333, 6000),
      (7, 83333, 6000),
      (8, 83333, 6000),
      (9, 83333, 6000),
      (10, 83333, 6000),
      (11, 83333, 6000),
      (12, 83337, 6000),
    ],
    irr: '0.01086181902837779489345848560',
    rateNominalX12: '0.072',
    rateEffectiveCompound: '0.074424167721924686943008243',
    irrNominalX12: '0.1303418283405335387215018272',
    irrEffectiveCompound: '0.138417383893314980008194717',
  ),
  _PySample(
    name: 'F-37',
    principal: 100000,
    periods: 12,
    rate: '0.015',
    remainder: RemainderTo.last,
    split: <int>[
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8333,
      8337,
    ],
    flows: <(int, int, int)>[
      (1, 8333, 1500),
      (2, 8333, 1500),
      (3, 8333, 1500),
      (4, 8333, 1500),
      (5, 8333, 1500),
      (6, 8333, 1500),
      (7, 8333, 1500),
      (8, 8333, 1500),
      (9, 8333, 1500),
      (10, 8333, 1500),
      (11, 8333, 1500),
      (12, 8337, 1500),
    ],
    irr: '0.02642954649809325928799808026',
    rateNominalX12: '0.180',
    rateEffectiveCompound: '0.195618171461535251561290098',
    irrNominalX12: '0.3171545579771191114559769631',
    irrEffectiveCompound: '0.367570551074909809392344426',
  ),
  _PySample(
    name: 'remainder_first',
    principal: 1000000,
    periods: 7,
    rate: '0.0075',
    remainder: RemainderTo.first,
    split: <int>[142858, 142857, 142857, 142857, 142857, 142857, 142857],
    flows: <(int, int, int)>[
      (1, 142858, 7500),
      (2, 142857, 7500),
      (3, 142857, 7500),
      (4, 142857, 7500),
      (5, 142857, 7500),
      (6, 142857, 7500),
      (7, 142857, 7500),
    ],
    irr: '0.01295819657161700888536870480',
    rateNominalX12: '0.0900',
    rateEffectiveCompound: '0.093806897670983062965455549',
    irrNominalX12: '0.1554983588594041066244244576',
    irrEffectiveCompound: '0.167073682249124266689761507',
  ),
  _PySample(
    name: 'single_period',
    principal: 12345,
    periods: 1,
    rate: '0.02',
    remainder: RemainderTo.last,
    split: <int>[12345],
    flows: <(int, int, int)>[(1, 12345, 247)],
    irr: '0.02000810044546597055159509182',
    rateNominalX12: '0.24',
    rateEffectiveCompound: '0.268241794562545318301696',
    irrNominalX12: '0.2400972053455916466191411018',
    irrEffectiveCompound: '0.268362662471175737936194786',
  ),
  _PySample(
    name: 'random_1',
    principal: 632318231,
    periods: 22,
    rate: '0.0186',
    remainder: RemainderTo.last,
    split: <int>[
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741738,
      28741733,
    ],
    flows: <(int, int, int)>[
      (1, 28741738, 11761119),
      (2, 28741738, 11761119),
      (3, 28741738, 11761119),
      (4, 28741738, 11761119),
      (5, 28741738, 11761119),
      (6, 28741738, 11761119),
      (7, 28741738, 11761119),
      (8, 28741738, 11761119),
      (9, 28741738, 11761119),
      (10, 28741738, 11761119),
      (11, 28741738, 11761119),
      (12, 28741738, 11761119),
      (13, 28741738, 11761119),
      (14, 28741738, 11761119),
      (15, 28741738, 11761119),
      (16, 28741738, 11761119),
      (17, 28741738, 11761119),
      (18, 28741738, 11761119),
      (19, 28741738, 11761119),
      (20, 28741738, 11761119),
      (21, 28741738, 11761119),
      (22, 28741733, 11761119),
    ],
    irr: '0.03206806092066472047008574008',
    rateNominalX12: '0.2232',
    rateEffectiveCompound: '0.247510076069336884946148903',
    irrNominalX12: '0.3848167310479766456410288810',
    irrEffectiveCompound: '0.460494949344681955178530830',
  ),
  _PySample(
    name: 'random_2',
    principal: 227575824,
    periods: 32,
    rate: '0.0139',
    remainder: RemainderTo.first,
    split: <int>[
      7111729,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
      7111745,
    ],
    flows: <(int, int, int)>[
      (1, 7111729, 3163304),
      (2, 7111745, 3163304),
      (3, 7111745, 3163304),
      (4, 7111745, 3163304),
      (5, 7111745, 3163304),
      (6, 7111745, 3163304),
      (7, 7111745, 3163304),
      (8, 7111745, 3163304),
      (9, 7111745, 3163304),
      (10, 7111745, 3163304),
      (11, 7111745, 3163304),
      (12, 7111745, 3163304),
      (13, 7111745, 3163304),
      (14, 7111745, 3163304),
      (15, 7111745, 3163304),
      (16, 7111745, 3163304),
      (17, 7111745, 3163304),
      (18, 7111745, 3163304),
      (19, 7111745, 3163304),
      (20, 7111745, 3163304),
      (21, 7111745, 3163304),
      (22, 7111745, 3163304),
      (23, 7111745, 3163304),
      (24, 7111745, 3163304),
      (25, 7111745, 3163304),
      (26, 7111745, 3163304),
      (27, 7111745, 3163304),
      (28, 7111745, 3163304),
      (29, 7111745, 3163304),
      (30, 7111745, 3163304),
      (31, 7111745, 3163304),
      (32, 7111745, 3163304),
    ],
    irr: '0.02403599143917745095677673816',
    rateNominalX12: '0.1668',
    rateEffectiveCompound: '0.180161592285670767723358656',
    irrNominalX12: '0.2884318972701294114813208579',
    irrEffectiveCompound: '0.329788738885538647040424689',
  ),
  _PySample(
    name: 'random_3',
    principal: 286486519,
    periods: 3,
    rate: '0.009',
    remainder: RemainderTo.last,
    split: <int>[95495506, 95495506, 95495507],
    flows: <(int, int, int)>[
      (1, 95495506, 2578379),
      (2, 95495506, 2578379),
      (3, 95495507, 2578379),
    ],
    irr: '0.01344019160615061991848051548',
    rateNominalX12: '0.108',
    rateEffectiveCompound: '0.113509674956668989037907206',
    irrNominalX12: '0.1612822992738074390217661858',
    irrEffectiveCompound: '0.173755081947654890855739540',
  ),
];

void main() {
  group('splitInstallments', () {
    test('性质：随机本金/期数守恒，除尾差那一期外各期相等（Python test_installment_split_conserves_principal，200 例）', () {
      final random = TestRandom(20261019);
      for (var i = 0; i < 200; i++) {
        final principal = random.randint(1, 1000000000);
        final periods = random.randint(1, 36);
        final last = splitInstallments(principal, periods);
        final first = splitInstallments(principal, periods, RemainderTo.first);
        for (final (parts, remainder) in <(List<int>, RemainderTo)>[
          (last, RemainderTo.last),
          (first, RemainderTo.first),
        ]) {
          final reason = '$principal / $periods ($remainder)';
          expect(parts, hasLength(periods), reason: reason);
          expect(
            parts.fold<int>(0, (a, b) => a + b),
            principal,
            reason: reason,
          );
          final rest = remainder == RemainderTo.last
              ? parts.sublist(0, periods - 1)
              : parts.sublist(1);
          expect(rest.toSet().length, lessThanOrEqualTo(1), reason: reason);
          // 每期 = HALF_UP(本金 / 期数)。
          final base = Rational.fromInt(
            principal,
            periods,
          ).roundToInt(RoundingMode.halfUp);
          expect(rest.every((p) => p == base), isTrue, reason: reason);
        }
      }
    });

    test('F-36：12 期拆分守恒，尾差在末期；尾差可为负（加到首期时首期变小）', () {
      final parts = splitInstallments(1000000, 12);
      expect(parts.sublist(0, 11), List<int>.filled(11, 83333));
      expect(parts.last, 83337);
      expect(parts.fold<int>(0, (a, b) => a + b), 1000000);
      // 7 期：1000000 / 7 = 142857.14… → 142857，尾差 +1。
      expect(splitInstallments(1000000, 7, RemainderTo.first), <int>[
        142858,
        ...List<int>.filled(6, 142857),
      ]);
      // 5 / 2 = 2.5 → 3（HALF_UP），尾差 −1。
      expect(splitInstallments(5, 2), <int>[3, 2]);
      expect(splitInstallments(5, 2, RemainderTo.first), <int>[2, 3]);
      expect(splitInstallments(0, 3), <int>[0, 0, 0]);
    });

    test('期数 ≤ 0 抛错（Python：periods must be >= 1）', () {
      for (final periods in <int>[0, -1]) {
        expect(
          () => splitInstallments(100, periods),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'periods must be >= 1',
            ),
          ),
        );
      }
    });
  });

  group('installmentCashFlows', () {
    test('每期费用 = applyRate(本金总额, 每期费率, HALF_UP)，每期相同（建行口径）', () {
      final flows = installmentCashFlows(1000000, 12, r('0.006'));
      expect(flows, hasLength(12));
      expect(
        flows.map((f) => f.periodNo),
        List<int>.generate(12, (i) => i + 1),
      );
      expect(flows.map((f) => f.fee).toSet(), <int>{6000});
      expect(flows.last.principal, 83337);
      // 取整：1001 × 0.0035 = 3.5035 → 4（HALF_UP）；显式 DOWN → 3。
      expect(installmentCashFlows(1001, 3, r('0.0035')).first.fee, 4);
      expect(
        installmentCashFlows(
          1001,
          3,
          r('0.0035'),
          rateRounding: RoundingMode.down,
        ).first.fee,
        3,
      );
      expect(
        installmentCashFlows(
          1000000,
          7,
          r('0.0075'),
          remainderTo: RemainderTo.first,
        ).first.principal,
        142858,
      );
    });
  });

  group('irrMonthly 与 annualize', () {
    test('F-37：月费率 1.5%、12 期——名义 18%（月费率 × 12）、复利年化与现金流 IRR 并列；IRR 不等于名义值', () {
      const principal = 100000;
      final rate = r('0.015');
      final flows = installmentCashFlows(principal, 12, rate);
      final irr = irrMonthly(installmentIrrFlows(principal, flows));
      final byRate = annualize(rate);
      final byIrr = annualize(irr);
      expect(byRate.nominalX12, r('0.18'));
      expect(decimalText(byRate.nominalX12), '0.18');
      // (1.015)^12 − 1 的精确值（36 位小数）。
      expect(
        decimalText(byRate.effectiveCompound),
        '0.195618171461535251561290097900390625',
      );
      expect(
        (irr - r('0.02642954649809325928799808026')).abs(),
        lessThan(r('1e-9')),
      );
      expect(irr, isNot(rate), reason: '各期费用按本金总额计，实际月成本高于名义月费率');
      expect(byIrr.nominalX12, isNot(byRate.nominalX12));
      expect(byIrr.effectiveCompound > byIrr.nominalX12, isTrue);
      expect(scaled(byIrr.nominalX12, 4), BigInt.from(3172));
      expect(scaled(byIrr.effectiveCompound, 4), BigInt.from(3676));
    });

    test(
      '符号约定以 Python 代码为准：月 0 放款为负、各期还款为正；反过来（Python docstring 的写法）抛"无正 IRR"',
      () {
        const principal = 100000;
        final flows = installmentIrrFlows(
          principal,
          installmentCashFlows(principal, 12, r('0.015')),
        );
        expect(flows.first, (month: 0, amount: -principal));
        expect(flows.skip(1).every((f) => f.amount > 0), isTrue);
        final docstringSigns = <MonthlyFlow>[
          for (final f in flows) (month: f.month, amount: -f.amount),
        ];
        expect(
          () => irrMonthly(docstringSigns),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              'no positive IRR: payments do not exceed principal',
            ),
          ),
        );
        // 零费率：IRR 收敛到 0（二分下界）。
        final free = irrMonthly(
          installmentIrrFlows(
            principal,
            installmentCashFlows(principal, 12, Rational.zero),
          ),
        );
        expect(free < r('1e-12'), isTrue);
        expect(free.isNegative, isFalse);
      },
    );

    test('有理数二分：结果是精确的二进分数，精度到 tol', () {
      final flows = installmentIrrFlows(
        1000000,
        installmentCashFlows(1000000, 12, r('0.006')),
      );
      final irr = irrMonthly(flows);
      final denominator = irr.denominator;
      expect(denominator & (denominator - BigInt.one), BigInt.zero);
      final coarse = irrMonthly(flows, tol: r('0.0001'));
      expect((coarse - irr).abs() < r('0.0001'), isTrue);
      // 在 IRR 两侧 1e-9 处净现值异号。
      expect(monthlyNpv(flows, irr - r('1e-9')) > Rational.zero, isTrue);
      expect(monthlyNpv(flows, irr + r('1e-9')).isNegative, isTrue);
    });
  });

  group('Python 对照（money.py 的实际输出，见文件头）', () {
    for (final sample in _pythonSamples) {
      test(
        '${sample.name}：本金 ${sample.principal}、${sample.periods} 期、每期费率 ${sample.rate}、尾差 ${sample.remainder.code}',
        () {
          final rate = r(sample.rate);
          expect(
            splitInstallments(
              sample.principal,
              sample.periods,
              sample.remainder,
            ),
            sample.split,
          );
          final flows = installmentCashFlows(
            sample.principal,
            sample.periods,
            rate,
            remainderTo: sample.remainder,
          );
          expect(
            flows.map((f) => (f.periodNo, f.principal, f.fee)).toList(),
            sample.flows,
          );
          final irr = irrMonthly(installmentIrrFlows(sample.principal, flows));
          expect(
            (irr - r(sample.irr)).abs() < r('1e-9'),
            isTrue,
            reason: 'IRR',
          );
          final byRate = annualize(rate);
          final byIrr = annualize(irr);
          for (final (dart, python, what) in <(Rational, String, String)>[
            (byRate.nominalX12, sample.rateNominalX12, '名义（每期费率）'),
            (
              byRate.effectiveCompound,
              sample.rateEffectiveCompound,
              '复利（每期费率）',
            ),
            (byIrr.nominalX12, sample.irrNominalX12, '名义（IRR）'),
            (byIrr.effectiveCompound, sample.irrEffectiveCompound, '复利（IRR）'),
          ]) {
            expect(scaled(dart, 10), scaled(r(python), 10), reason: what);
          }
        },
      );
    }
  });
}
