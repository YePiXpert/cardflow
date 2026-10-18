/// 规则协议 v1 适配层：PlanInput 文档 ⇄ 领域对象（Python `engine/protocol.py`）。
///
/// 不依赖 JSON Schema 库：适配层自己重新检查它依赖的每一条规则（类型、范围、pattern、未知成员，
/// 以及 JSON Schema 表达不了的交叉引用规则，README"字段约定"），因此无论调用方是否先做过 schema
/// 校验，领域层都不会收到会被误读的值。整数字段拒绝布尔与一切浮点（含 `1.0`）；金额是整数最小单位，
/// 利率与系数是规范写法的十进制字符串。违规抛 [ProtocolError]（带 JSON Pointer，不回显原值）。
///
/// 成员的读取顺序与 Python 相同，因此同一份非法文档报告同一个路径。
library;

import '../allocation.dart';
import '../billing.dart';
import '../cash.dart';
import '../money.dart';
import '../pytext.dart';
import '../rational.dart';
import '../time.dart';
import 'errors.dart';
import 'json.dart';
import 'pointer.dart';

/// 协议版本。
const String protocolVersion = '1';

/// 引擎为计划还款保留的事件 ID 前缀。
const String reservedEventPrefix = 'plan_repay_';

/// 输入金额的绝对值上限 10^13（引擎变量上界 BIG；README"支持的数值范围"）。
const int moneyLimit = 10000000000000;

/// int32 上限。
const int int32Max = 2147483647;

/// 卡数上限。
const int maxCardCount = 200;

/// 现金账户数上限。
const int maxCashAccountCount = 100;

/// 事件数上限。
const int maxEventCount = 10000;

/// 文本长度上限（Unicode 码点）。
const int textMaxLength = 1000;

/// `time_limit_s` 上限（秒）。
const int timeLimitMaxSeconds = 3600;

/// 画像。
const List<String> profiles = <String>[
  'cash_safety',
  'verified_benefit',
  'fewer_cards',
];

/// 事件分类。
const List<String> eventCategories = <String>[
  'income',
  'bill',
  'living',
  'repayment',
  'transfer_in',
  'transfer_out',
  'fee',
  'other',
];

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
final RegExp _channelPattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');
const String _year = '(19[7-9][0-9]|2[0-9]{3})'; // 1970..2999
const String _monthDay = '-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])';
final RegExp _datePattern = RegExp('^$_year$_monthDay\$');
// 时 00–23、分秒 00–59（不接受闰秒）、偏移至多 23:59（R3E-20）
final RegExp _timestampPattern = RegExp(
  '^$_year$_monthDay'
  r'T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,6})?'
  r'(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$',
);
// 只接受规范写法：无多余尾零、无多余前导零（同一值一种写法、一个 input_hash，R3E-11）
final RegExp _ratePattern = RegExp(r'^(0|1|0\.[0-9]{0,4}[1-9])$');
final RegExp _scalePattern = RegExp(r'^(10|[0-9]|[0-9]\.[0-9]{0,9}[1-9])$');

typedef _Conv<T> = T Function(Object? value, String path);

/// PlanInput.options（`global_reserve_floor_minor` 在 [ModelInputs] 中）。
final class PlanOptions {
  /// 选项。
  const PlanOptions({
    required this.profile,
    required this.decisionScenario,
    required this.timeLimitS,
    required this.workers,
    required this.seed,
    required this.staleAfterDays,
  });

  /// 画像。
  final String profile;

  /// 决策情景 ID。
  final String decisionScenario;

  /// 整次运行的时间预算（JSON 数字原值：`int` 或 [JsonFloat]；Dart 端不求解，只回写）。
  final Object timeLimitS;

  /// CP-SAT num_workers（只回写）。
  final int workers;

  /// CP-SAT random_seed（只回写）。
  final int seed;

  /// 快照过期天数。
  final int staleAfterDays;
}

/// 一份 PlanInput 读出的领域对象。
final class ParsedPlanInput {
  /// 读取结果。
  const ParsedPlanInput(this.inputs, this.scenarios, this.options);

  /// 数据。
  final ModelInputs inputs;

  /// 情景（输入顺序）。
  final Map<String, Scenario> scenarios;

  /// 选项。
  final PlanOptions options;
}

/// 严格读取一个 JSON 对象：未知成员是错误。
final class _Obj {
  _Obj(Object? value, this.path, List<String> allowed)
    : value = _asObject(value, path) {
    final unknown = [
      for (final key in this.value.keys)
        if (!allowed.contains(key)) key,
    ]..sort(compareCodePoints);
    if (unknown.isNotEmpty) {
      throw ProtocolError(
        childPointer(path, unknown.first),
        'unknown member (not in protocol v1)',
      );
    }
  }

  static Map<String, Object?> _asObject(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw ProtocolError(path, 'expected an object, got ${jsonKind(value)}');
    }
    return value;
  }

  final Map<String, Object?> value;
  final String path;

  T req<T>(String key, _Conv<T> conv) {
    if (!value.containsKey(key)) {
      throw ProtocolError(path, 'missing required member ${pyRepr(key)}');
    }
    return conv(value[key], childPointer(path, key));
  }

  T? opt<T>(String key, _Conv<T> conv) =>
      value.containsKey(key) ? conv(value[key], childPointer(path, key)) : null;
}

_Conv<int> _int(int lo, int hi) => (Object? value, String path) {
  if (!isJsonInteger(value)) {
    throw ProtocolError(path, 'expected an integer, got ${jsonKind(value)}');
  }
  if (value is! int || value < lo || value > hi) {
    // 不回显值（可能是金额）
    throw ProtocolError(path, 'must be an integer in [$lo, $hi]');
  }
  return value;
};

final _Conv<int> _minor = _int(-moneyLimit, moneyLimit);
final _Conv<int> _nonNegativeMinor = _int(0, moneyLimit);
final _Conv<int> _positiveMinor = _int(1, moneyLimit);
final _Conv<int> _days = _int(0, 366);

bool _bool(Object? value, String path) {
  if (value is! bool) {
    throw ProtocolError(path, 'expected a boolean, got ${jsonKind(value)}');
  }
  return value;
}

String _string(Object? value, String path) {
  if (value is! String) {
    throw ProtocolError(path, 'expected a string, got ${jsonKind(value)}');
  }
  return value;
}

_Conv<String> _matching(RegExp pattern, String what) =>
    (Object? value, String path) {
      final text = _string(value, path);
      if (!pattern.hasMatch(text)) {
        throw ProtocolError(path, 'not a valid $what'); // 从不回显值（R3E-12）
      }
      return text;
    };

final _Conv<String> _id = _matching(
  _idPattern,
  'id (ASCII letters, digits and . _ : -, at most 128)',
);
final _Conv<String> _currency = _matching(
  _currencyPattern,
  'ISO 4217 currency code (3 capital letters)',
);
final _Conv<String> _channel = _matching(
  _channelPattern,
  'channel (lowercase letters, digits and _)',
);

String _eventId(Object? value, String path) {
  final text = _id(value, path);
  if (text.startsWith(reservedEventPrefix)) {
    throw ProtocolError(
      path,
      'event ids starting with ${pyRepr(reservedEventPrefix)} are reserved',
    );
  }
  return text;
}

String _text(Object? value, String path) {
  final text = _string(value, path);
  if (text.runes.length > textMaxLength) {
    // 按码点计数（R3E-21）
    throw ProtocolError(path, 'longer than $textMaxLength characters');
  }
  if (hasLoneSurrogate(text)) {
    throw ProtocolError(path, 'string contains a lone surrogate');
  }
  return text;
}

LocalDate _date(Object? value, String path) {
  final text = _string(value, path);
  if (!_datePattern.hasMatch(text)) {
    throw ProtocolError(path, 'not a YYYY-MM-DD date in 1970..2999');
  }
  try {
    return LocalDate.parse(text);
  } on FormatException {
    throw ProtocolError(path, 'not a valid calendar date');
  }
}

Timestamp _timestamp(Object? value, String path) {
  final text = _string(value, path);
  if (!_timestampPattern.hasMatch(text)) {
    throw ProtocolError(
      path,
      'not an RFC 3339 timestamp with an offset in 1970..2999',
    );
  }
  try {
    return Timestamp.parse(text);
  } on FormatException {
    throw ProtocolError(path, 'not a valid calendar date and time');
  }
}

_Conv<Rational> _decimalIn(RegExp pattern, String what) =>
    (Object? value, String path) {
      if (isJsonInteger(value) || value is JsonFloat) {
        throw ProtocolError(
          path,
          'rates and factors are decimal strings, not JSON numbers',
        );
      }
      final text = _string(value, path);
      if (!pattern.hasMatch(text)) {
        throw ProtocolError(path, 'not a $what');
      }
      return Rational.parseDecimal(text);
    };

final _Conv<Rational> _rate = _decimalIn(
  _ratePattern,
  'rate (canonical decimal string 0..1, at most 5 decimals, no trailing zeros)',
);
final _Conv<Rational> _scale = _decimalIn(
  _scalePattern,
  'scale factor (canonical decimal string 0..10, at most 10 decimals, no trailing zeros)',
);

_Conv<String> _enum(List<String> values) => (Object? value, String path) {
  if (value is! String || !values.contains(value)) {
    throw ProtocolError(path, 'must be one of ${pyListRepr(values)}');
  }
  return value;
};

_Conv<List<T>> _array<T>(
  _Conv<T> item, {
  int minItems = 0,
  int? maxItems,
}) => (Object? value, String path) {
  if (value is! List<Object?>) {
    throw ProtocolError(path, 'expected an array, got ${jsonKind(value)}');
  }
  if (value.length < minItems) {
    throw ProtocolError(path, 'needs at least $minItems item(s)');
  }
  if (maxItems != null && value.length > maxItems) {
    throw ProtocolError(path, 'more than $maxItems items (supported range)');
  }
  return [for (var i = 0; i < value.length; i++) item(value[i], '$path/$i')];
};

Object _timeLimit(Object? value, String path) {
  final (Object number, Rational exact) = switch (value) {
    int() => (value, Rational.fromInt(value)),
    BigInt() => (value, Rational(value)),
    JsonFloat() => (value, value.binary64.value),
    _ => throw ProtocolError(path, 'expected a number, got ${jsonKind(value)}'),
  };
  if (exact <= Rational.zero || exact > Rational.fromInt(timeLimitMaxSeconds)) {
    throw ProtocolError(path, 'must be in (0, $timeLimitMaxSeconds]');
  }
  return number;
}

String _protocolVersion(Object? value, String path) {
  if (value is! String || value != protocolVersion) {
    throw ProtocolError(
      path,
      'unsupported protocol_version (expected ${pyRepr(protocolVersion)})',
    );
  }
  return value;
}

const List<String> _requestMembers = <String>[
  'amount_minor',
  'currency',
  'txn_date',
  'allow_split',
  'max_cards',
  'min_split_minor',
  'payment_lead_days',
  'channel',
];
const List<String> _ruleMembers = <String>[
  'rule_id',
  'statement_day',
  'statement_day_inclusive',
  'due',
  'holiday_rollover',
  'effective_from',
  'effective_to',
  'source',
  'verified_on',
  'status',
];
const List<String> _cardMembers = <String>[
  'card_id',
  'credit_account_id',
  'name',
  'raw_available_minor',
  'holds_uncounted_minor',
  'reservations_minor',
  'pool_id',
  'per_txn_cap_minor',
  'min_split_minor',
  'billing_rule',
  'repay_from_cash_account_id',
  'channel_ok',
  'currency_ok',
  'status_ok',
  'fee_rate',
  'fee_fixed_minor',
  'verified_benefit_rate',
  'verified_benefit_cap_minor',
  'potential_benefit_rate',
  'posting_delay_min_days',
  'posting_delay_max_days',
];
const List<String> _accountMembers = <String>[
  'cash_account_id',
  'name',
  'currency',
  'reserve_floor_minor',
  'usable_for_repayment',
];
const List<String> _snapshotMembers = <String>[
  'cash_account_id',
  'balance_minor',
  'as_of',
  'observed_at',
  'includes_event_ids',
];
const List<String> _eventMembers = <String>[
  'event_id',
  'cash_account_id',
  'on',
  'at',
  'amount_minor',
  'cls',
  'category',
  'label',
];
const List<String> _scenarioMembers = <String>[
  'scenario_id',
  'include_expected',
  'income_delay_days',
  'income_scale',
  'expense_scale',
  'event_overrides',
  'same_day_order',
  'description',
];
const List<String> _optionMembers = <String>[
  'profile',
  'decision_scenario',
  'time_limit_s',
  'workers',
  'seed',
  'stale_after_days',
  'global_reserve_floor_minor',
];
const List<String> _planInputMembers = <String>[
  'protocol_version',
  'request',
  'cards',
  'pools',
  'cash_accounts',
  'snapshots',
  'events',
  'scenarios',
  'horizon_end',
  'options',
];

PlanRequest _request(Object? value, String path) {
  final o = _Obj(value, path, _requestMembers);
  return PlanRequest(
    amount: o.req('amount_minor', _positiveMinor),
    currency: o.req('currency', _currency),
    txnDate: o.req('txn_date', _date),
    allowSplit: o.req('allow_split', _bool),
    maxCards: o.req('max_cards', _int(1, int32Max)),
    minSplit: o.req('min_split_minor', _positiveMinor),
    paymentLeadDays: o.req('payment_lead_days', _days),
    channel: o.req('channel', _channel),
  );
}

DueRule _dueRule(Object? value, String path) {
  final kind = value is Map<String, Object?> ? value['kind'] : null;
  if (kind == 'fixed_day') {
    final o = _Obj(value, path, const <String>['kind', 'day', 'month_offset']);
    return DueRule.fixedDay(
      day: o.req('day', _int(1, 31)),
      monthOffset: o.req('month_offset', _int(0, 2)),
    );
  }
  if (kind == 'days_after_statement') {
    final o = _Obj(value, path, const <String>['kind', 'days', 'day_kind']);
    final days = o.req('days', _int(1, 60));
    final dayKind = o.req(
      'day_kind',
      _enum(const <String>['calendar', 'business']),
    );
    return DueRule.daysAfterStatement(
      days: days,
      dayKind: dayKind == 'business' ? DayKind.business : DayKind.calendar,
    );
  }
  final o = _Obj(value, path, const <String>[
    'kind',
    'day',
    'month_offset',
    'days',
    'day_kind',
  ]);
  o.req('kind', _enum(const <String>['fixed_day', 'days_after_statement']));
  throw ProtocolError(path, 'unreachable'); // req() 已经抛出
}

BillingRule _billingRule(Object? value, String path) {
  final o = _Obj(value, path, _ruleMembers);
  final ruleId = o.req('rule_id', _id);
  final statementDay = o.req('statement_day', _int(1, 31));
  final due = o.req('due', _dueRule);
  final inclusive = o.req('statement_day_inclusive', _bool);
  final rollover = o.req(
    'holiday_rollover',
    _enum(const <String>['none', 'next_business_day']),
  );
  final effectiveFrom = o.opt('effective_from', _date);
  final effectiveTo = o.opt('effective_to', _date);
  final source = o.opt('source', _text) ?? '';
  final verifiedOn = o.opt('verified_on', _date);
  final status =
      o.opt(
        'status',
        _enum(const <String>['draft', 'verified', 'user_declared']),
      ) ??
      'user_declared';
  return BillingRule(
    ruleId: ruleId,
    statementDay: statementDay,
    due: due,
    statementDayInclusive: inclusive,
    holidayRollover: rollover == 'next_business_day'
        ? HolidayRollover.nextBusinessDay
        : HolidayRollover.none,
    effectiveFrom: effectiveFrom,
    effectiveTo: effectiveTo,
    source: source,
    verifiedOn: verifiedOn,
    status: RuleStatus.values.firstWhere((s) => s.code == status),
  );
}

CardOption _card(Object? value, String path) {
  final o = _Obj(value, path, _cardMembers);
  final cardId = o.req('card_id', _id);
  final delayMin = o.req('posting_delay_min_days', _days);
  final delayMax = o.req('posting_delay_max_days', _days);
  if (delayMin > delayMax) {
    throw ProtocolError(
      childPointer(path, 'posting_delay_max_days'),
      'must be >= posting_delay_min_days',
    );
  }
  final accountId = o.req('credit_account_id', _id);
  final name = o.opt('name', _text) ?? cardId;
  final raw = o.req('raw_available_minor', _minor);
  final rule = o.req('billing_rule', _billingRule);
  final repayFrom = o.req('repay_from_cash_account_id', _id);
  final holds = o.req('holds_uncounted_minor', _nonNegativeMinor);
  final reservations = o.req('reservations_minor', _nonNegativeMinor);
  final poolId = o.opt('pool_id', _id);
  final perTxnCap = o.opt('per_txn_cap_minor', _nonNegativeMinor);
  final minSplit = o.opt('min_split_minor', _positiveMinor);
  final channelOk = o.req('channel_ok', _bool);
  final currencyOk = o.req('currency_ok', _bool);
  final statusOk = o.req('status_ok', _bool);
  final feeRate = o.req('fee_rate', _rate);
  final feeFixed = o.req('fee_fixed_minor', _nonNegativeMinor);
  final benefitRate = o.req('verified_benefit_rate', _rate);
  final benefitCap = o.opt('verified_benefit_cap_minor', _nonNegativeMinor);
  final potentialRate = o.req('potential_benefit_rate', _rate);
  return CardOption(
    id: cardId,
    accountId: accountId,
    name: name,
    rawAvailable: raw,
    billingRule: rule,
    repayFrom: repayFrom,
    uncountedHolds: holds,
    planReservations: reservations,
    poolId: poolId,
    perTxnCap: perTxnCap,
    minSplit: minSplit,
    channelOk: channelOk,
    currencyOk: currencyOk,
    statusOk: statusOk,
    feeRate: feeRate,
    feeFixed: feeFixed,
    verifiedBenefitRate: benefitRate,
    verifiedBenefitCap: benefitCap,
    potentialBenefitRate: potentialRate,
    postingDelayMin: delayMin,
    postingDelayMax: delayMax,
  );
}

(String, int) _pool(Object? value, String path) {
  final o = _Obj(value, path, const <String>['pool_id', 'available_minor']);
  final poolId = o.req('pool_id', _id);
  return (poolId, o.req('available_minor', _minor));
}

CashAccount _account(Object? value, String path) {
  final o = _Obj(value, path, _accountMembers);
  final accountId = o.req('cash_account_id', _id);
  final name = o.opt('name', _text) ?? accountId;
  return CashAccount(
    id: accountId,
    name: name,
    currency: o.req('currency', _currency),
    reserveFloor: o.req('reserve_floor_minor', _nonNegativeMinor),
    usableForRepayment: o.req('usable_for_repayment', _bool),
  );
}

List<String> _includes(Object? value, String path) {
  final ids = _array(_eventId)(value, path);
  for (var i = 0; i < ids.length; i++) {
    if (ids.sublist(0, i).contains(ids[i])) {
      throw ProtocolError('$path/$i', 'duplicate event id');
    }
  }
  return ids;
}

(Snapshot, List<String>) _snapshot(Object? value, String path) {
  final o = _Obj(value, path, _snapshotMembers);
  final account = o.req('cash_account_id', _id);
  final balance = o.req('balance_minor', _minor);
  final asOf = o.req('as_of', _date);
  final observedAt = o.opt('observed_at', _timestamp);
  final includes = o.req('includes_event_ids', _includes);
  return (
    Snapshot(
      account: account,
      balance: balance,
      asOf: asOf,
      observedAt: observedAt,
      includesEventIds: Set<String>.of(includes),
    ),
    includes,
  );
}

CashEvent _event(Object? value, String path) {
  final o = _Obj(value, path, _eventMembers);
  final id = o.req('event_id', _eventId);
  final account = o.req('cash_account_id', _id);
  final on = o.req('on', _date);
  final amount = o.req('amount_minor', _minor);
  final cls = o.req(
    'cls',
    _enum(const <String>['confirmed', 'expected', 'planned']),
  );
  final category = o.req('category', _enum(eventCategories));
  final label = o.opt('label', _text) ?? '';
  final at = o.opt('at', _timestamp);
  return CashEvent(
    id: id,
    account: account,
    on: on,
    amount: amount,
    cls: EventClass.values.firstWhere((c) => c.code == cls),
    category: category,
    label: label,
    at: at,
  );
}

(String, EventOverride) _override(Object? value, String path) {
  final o = _Obj(value, path, const <String>['event_id', 'on', 'amount_minor']);
  final eventId = o.req('event_id', _eventId);
  final on = o.value.containsKey('on') ? o.req('on', _date) : null;
  final amount = o.value.containsKey('amount_minor')
      ? o.req('amount_minor', _minor)
      : null;
  if (on == null && amount == null) {
    throw ProtocolError(path, "an override needs 'on' and/or 'amount_minor'");
  }
  return (eventId, EventOverride(on: on, amount: amount));
}

(Scenario, List<String>) _scenario(Object? value, String path) {
  final o = _Obj(value, path, _scenarioMembers);
  final scenarioId = o.req('scenario_id', _id);
  final overrides = o.req('event_overrides', _array(_override));
  final ordered = [for (final (eventId, _) in overrides) eventId];
  for (var i = 0; i < ordered.length; i++) {
    if (ordered.sublist(0, i).contains(ordered[i])) {
      throw ProtocolError(
        '$path/event_overrides/$i/event_id',
        'event overridden twice',
      );
    }
  }
  final includeExpected = o.req('include_expected', _bool);
  final delay = o.req('income_delay_days', _days);
  final incomeScale = o.req('income_scale', _scale);
  final expenseScale = o.req('expense_scale', _scale);
  final order = o.req(
    'same_day_order',
    _enum(const <String>['conservative', 'timestamp']),
  );
  final description = o.opt('description', _text) ?? '';
  return (
    Scenario(
      id: scenarioId,
      includeExpected: includeExpected,
      incomeDelayDays: delay,
      incomeScale: incomeScale,
      expenseScale: expenseScale,
      eventOverrides: <String, EventOverride>{
        for (final (eventId, change) in overrides) eventId: change,
      },
      sameDayOrder: order == 'timestamp'
          ? SameDayOrder.timestamp
          : SameDayOrder.conservative,
      description: description,
    ),
    ordered,
  );
}

(PlanOptions, int) _options(Object? value, String path) {
  final o = _Obj(value, path, _optionMembers);
  final options = PlanOptions(
    profile: o.req('profile', _enum(profiles)),
    decisionScenario: o.req('decision_scenario', _id),
    timeLimitS: o.req('time_limit_s', _timeLimit),
    workers: o.req('workers', _int(1, 64)),
    seed: o.req('seed', _int(0, int32Max)),
    staleAfterDays: o.req('stale_after_days', _days),
  );
  return (options, o.req('global_reserve_floor_minor', _nonNegativeMinor));
}

void _unique(List<String> ids, String path, String member) {
  final seen = <String>{};
  for (var i = 0; i < ids.length; i++) {
    if (!seen.add(ids[i])) {
      throw ProtocolError('$path/$i/$member', 'duplicate $member');
    }
  }
}

/// 校验 PlanInput 文档并构造领域对象；任何违规（含 PlanInput.schema.json 所列的交叉引用规则）
/// 抛 [ProtocolError]。可省略成员：省略的可选项为"无"（null）；省略的显示文本为 ID（名称）或空串
/// （标签、说明、规则来源）；省略的规则状态为 `user_declared`。
ParsedPlanInput inputsFromProtocol(Object? document) {
  final o = _Obj(document, '', _planInputMembers);
  o.req('protocol_version', _protocolVersion);
  final request = o.req('request', _request);
  final cards = o.req(
    'cards',
    _array(_card, minItems: 1, maxItems: maxCardCount),
  );
  final pools = o.req('pools', _array(_pool));
  final accounts = o.req(
    'cash_accounts',
    _array(_account, minItems: 1, maxItems: maxCashAccountCount),
  );
  final snapshots = o.req('snapshots', _array(_snapshot));
  final events = o.req('events', _array(_event, maxItems: maxEventCount));
  final scenarios = o.req('scenarios', _array(_scenario, minItems: 1));
  final horizonEnd = o.req('horizon_end', _date);
  final (options, globalFloor) = o.req('options', _options);

  _unique([for (final c in cards) c.id], '/cards', 'card_id');
  _unique([for (final (p, _) in pools) p], '/pools', 'pool_id');
  _unique(
    [for (final a in accounts) a.id],
    '/cash_accounts',
    'cash_account_id',
  );
  _unique(
    [for (final (s, _) in snapshots) s.account],
    '/snapshots',
    'cash_account_id',
  );
  _unique([for (final e in events) e.id], '/events', 'event_id');
  _unique([for (final (s, _) in scenarios) s.id], '/scenarios', 'scenario_id');
  final accountIds = {for (final a in accounts) a.id};
  for (var i = 0; i < accounts.length; i++) {
    if (accounts[i].currency != request.currency) {
      throw ProtocolError(
        '/cash_accounts/$i/currency',
        'differs from the request currency (protocol v1 plans are single-currency)',
      );
    }
  }
  final firstOfAccount = <String, CardOption>{};
  for (var i = 0; i < cards.length; i++) {
    final c = cards[i];
    if (!accountIds.contains(c.repayFrom)) {
      throw ProtocolError(
        '/cards/$i/repay_from_cash_account_id',
        'unknown cash account',
      );
    }
    // 同一信用账户的卡共享账户可用额（engine-spec §12.3）：报告同一个值、属于同一个池（R3E-04）。
    final host = firstOfAccount.putIfAbsent(c.accountId, () => c);
    if (c.rawAvailable != host.rawAvailable) {
      throw ProtocolError(
        '/cards/$i/raw_available_minor',
        'differs from another card of the same credit account '
            "(the account's available credit is one value)",
      );
    }
    if (c.poolId != host.poolId) {
      throw ProtocolError(
        '/cards/$i/pool_id',
        'differs from another card of the same credit account',
      );
    }
  }
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    if (!accountIds.contains(e.account)) {
      throw ProtocolError('/events/$i/cash_account_id', 'unknown cash account');
    }
    final at = e.at;
    if (at != null && at.date != e.on) {
      // R3E-14：按时间戳自身的偏移取日期
      throw ProtocolError(
        '/events/$i/at',
        "its date (in its own offset) is not 'on'",
      );
    }
  }
  final eventOf = {for (final e in events) e.id: e};
  for (var i = 0; i < snapshots.length; i++) {
    final (s, includes) = snapshots[i];
    if (!accountIds.contains(s.account)) {
      throw ProtocolError(
        '/snapshots/$i/cash_account_id',
        'unknown cash account',
      );
    }
    for (var j = 0; j < includes.length; j++) {
      final event = eventOf[includes[j]];
      if (event == null || event.account != s.account) {
        throw ProtocolError(
          '/snapshots/$i/includes_event_ids/$j',
          "not an event of this snapshot's cash account",
        );
      }
      if (event.on > s.asOf) {
        // 余额不可能已包含之后的事件（R3E-14）
        throw ProtocolError(
          '/snapshots/$i/includes_event_ids/$j',
          'lists an event dated after as_of',
        );
      }
    }
  }
  for (var i = 0; i < scenarios.length; i++) {
    final (_, overridden) = scenarios[i];
    for (var j = 0; j < overridden.length; j++) {
      if (!eventOf.containsKey(overridden[j])) {
        throw ProtocolError(
          '/scenarios/$i/event_overrides/$j/event_id',
          'unknown event',
        );
      }
    }
  }
  final inputs = ModelInputs(
    request: request,
    cards: cards,
    pools: {for (final (poolId, available) in pools) poolId: available},
    accounts: accounts,
    snapshots: {for (final (s, _) in snapshots) s.account: s},
    events: events,
    horizonEnd: horizonEnd,
    globalReserveFloor: globalFloor,
  );
  return ParsedPlanInput(inputs, {
    for (final (s, _) in scenarios) s.id: s,
  }, options);
}

/// `[{card_id, amount_minor}, ...]` → `{card_id: amount}`（卡 ID 唯一、金额为正整数，按给定顺序）。
Map<String, int> allocationFromProtocol(
  Object? items, {
  String path = '/allocation',
}) {
  (String, int) item(Object? value, String itemPath) {
    final o = _Obj(value, itemPath, const <String>['card_id', 'amount_minor']);
    final cardId = o.req('card_id', _id);
    return (cardId, o.req('amount_minor', _positiveMinor));
  }

  final pairs = _array(item, minItems: 1)(items, path);
  _unique([for (final (cardId, _) in pairs) cardId], path, 'card_id');
  return {for (final (cardId, amount) in pairs) cardId: amount};
}

/// 读取并校验决策情景 ID。
String scenarioIdFromProtocol(Object? value, String path) => _id(value, path);

String _decimalTextIn(Rational value, String path, RegExp pattern) {
  final String text;
  try {
    text = decimalText(value);
  } on ArgumentError {
    throw ProtocolError(path, 'not a finite decimal');
  }
  if (!pattern.hasMatch(text)) {
    throw ProtocolError(path, 'outside the v1 range for this field');
  }
  return text;
}

/// 领域对象 → PlanInput 文档（本地数据库映射到协议输入的出口；Python `inputs_to_protocol`）。
///
/// 利率与系数写成规范文本（数据库的 `NUMERIC(20,10)` 如 0.0060000000 写成 `"0.006"`，R3E-11）；
/// 值为 null 的可选成员省略，显示文本总是写出。结果会重新校验，v1 表示不了的值抛 [ProtocolError]
/// （绝不取整）。
Map<String, Object?> inputsToProtocol(
  ModelInputs inputs,
  Map<String, Scenario> scenarios,
  PlanOptions options,
) {
  final req = inputs.request;
  Map<String, Object?> card(CardOption c, String path) {
    final rule = c.billingRule;
    final due = rule.due;
    final Map<String, Object?> dueDoc = due.kind == DueKind.fixedDay
        ? <String, Object?>{
            'kind': 'fixed_day',
            'day': due.day,
            'month_offset': due.monthOffset,
          }
        : <String, Object?>{
            'kind': due.kind.code,
            'days': due.days,
            'day_kind': due.dayKind.code,
          };
    final ruleDoc = <String, Object?>{
      'rule_id': rule.ruleId,
      'statement_day': rule.statementDay,
      'statement_day_inclusive': rule.statementDayInclusive,
      'due': dueDoc,
      'holiday_rollover': rule.holidayRollover.code,
      'source': rule.source,
      'status': rule.status.code,
      if (rule.effectiveFrom != null) 'effective_from': '${rule.effectiveFrom}',
      if (rule.effectiveTo != null) 'effective_to': '${rule.effectiveTo}',
      if (rule.verifiedOn != null) 'verified_on': '${rule.verifiedOn}',
    };
    return <String, Object?>{
      'card_id': c.id,
      'credit_account_id': c.accountId,
      'name': c.name,
      'raw_available_minor': c.rawAvailable,
      'holds_uncounted_minor': c.uncountedHolds,
      'reservations_minor': c.planReservations,
      'billing_rule': ruleDoc,
      'repay_from_cash_account_id': c.repayFrom,
      'channel_ok': c.channelOk,
      'currency_ok': c.currencyOk,
      'status_ok': c.statusOk,
      'fee_rate': _decimalTextIn(c.feeRate, '$path/fee_rate', _ratePattern),
      'fee_fixed_minor': c.feeFixed,
      'verified_benefit_rate': _decimalTextIn(
        c.verifiedBenefitRate,
        '$path/verified_benefit_rate',
        _ratePattern,
      ),
      'potential_benefit_rate': _decimalTextIn(
        c.potentialBenefitRate,
        '$path/potential_benefit_rate',
        _ratePattern,
      ),
      'posting_delay_min_days': c.postingDelayMin,
      'posting_delay_max_days': c.postingDelayMax,
      if (c.poolId != null) 'pool_id': c.poolId,
      if (c.perTxnCap != null) 'per_txn_cap_minor': c.perTxnCap,
      if (c.minSplit != null) 'min_split_minor': c.minSplit,
      if (c.verifiedBenefitCap != null)
        'verified_benefit_cap_minor': c.verifiedBenefitCap,
    };
  }

  Map<String, Object?> scenario(Scenario s, String path) => <String, Object?>{
    'scenario_id': s.id,
    'include_expected': s.includeExpected,
    'income_delay_days': s.incomeDelayDays,
    'income_scale': _decimalTextIn(
      s.incomeScale,
      '$path/income_scale',
      _scalePattern,
    ),
    'expense_scale': _decimalTextIn(
      s.expenseScale,
      '$path/expense_scale',
      _scalePattern,
    ),
    'event_overrides': <Object?>[
      for (final MapEntry(key: eventId, value: change)
          in s.eventOverrides.entries)
        <String, Object?>{
          'event_id': eventId,
          if (change.on != null) 'on': '${change.on}',
          if (change.amount != null) 'amount_minor': change.amount,
        },
    ],
    'same_day_order': s.sameDayOrder.code,
    'description': s.description,
  };

  final doc = <String, Object?>{
    'protocol_version': protocolVersion,
    'request': <String, Object?>{
      'amount_minor': req.amount,
      'currency': req.currency,
      'txn_date': '${req.txnDate}',
      'allow_split': req.allowSplit,
      'max_cards': req.maxCards,
      'min_split_minor': req.minSplit,
      'payment_lead_days': req.paymentLeadDays,
      'channel': req.channel,
    },
    'cards': <Object?>[
      for (var i = 0; i < inputs.cards.length; i++)
        card(inputs.cards[i], '/cards/$i'),
    ],
    'pools': <Object?>[
      for (final MapEntry(:key, :value) in inputs.pools.entries)
        <String, Object?>{'pool_id': key, 'available_minor': value},
    ],
    'cash_accounts': <Object?>[
      for (final a in inputs.accounts)
        <String, Object?>{
          'cash_account_id': a.id,
          'name': a.name,
          'currency': a.currency,
          'reserve_floor_minor': a.reserveFloor,
          'usable_for_repayment': a.usableForRepayment,
        },
    ],
    'snapshots': <Object?>[
      for (final s in inputs.snapshots.values)
        <String, Object?>{
          'cash_account_id': s.account,
          'balance_minor': s.balance,
          'as_of': '${s.asOf}',
          'includes_event_ids': <Object?>[
            ...(s.includesEventIds.toList()..sort(compareCodePoints)),
          ],
          if (s.observedAt != null) 'observed_at': s.observedAt!.isoformat(),
        },
    ],
    'events': <Object?>[
      for (final e in inputs.events)
        <String, Object?>{
          'event_id': e.id,
          'cash_account_id': e.account,
          'on': '${e.on}',
          'amount_minor': e.amount,
          'cls': e.cls.code,
          'category': e.category,
          'label': e.label,
          if (e.at != null) 'at': e.at!.isoformat(),
        },
    ],
    'scenarios': <Object?>[
      for (final (i, s) in scenarios.values.indexed)
        scenario(s, '/scenarios/$i'),
    ],
    'horizon_end': '${inputs.horizonEnd}',
    'options': <String, Object?>{
      'profile': options.profile,
      'decision_scenario': options.decisionScenario,
      'time_limit_s': options.timeLimitS,
      'workers': options.workers,
      'seed': options.seed,
      'stale_after_days': options.staleAfterDays,
      'global_reserve_floor_minor': inputs.globalReserveFloor,
    },
  };
  inputsFromProtocol(doc); // 写出的必须是合法的 v1 文档
  return doc;
}
