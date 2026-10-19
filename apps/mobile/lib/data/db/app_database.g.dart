// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WorkspacesTable extends Workspaces
    with TableInfo<$WorkspacesTable, WorkspaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, kind, name, createdAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkspaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $WorkspacesTable createAlias(String alias) {
    return $WorkspacesTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class WorkspaceRow extends DataClass implements Insertable<WorkspaceRow> {
  final String id;

  /// `real` / `demo`。
  final String kind;
  final String name;

  /// RFC 3339。
  final String createdAt;
  final String? deletedAt;
  const WorkspaceRow({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<String>(createdAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  WorkspacesCompanion toCompanion(bool nullToAbsent) {
    return WorkspacesCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      createdAt: Value(createdAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory WorkspaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<String>(createdAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  WorkspaceRow copyWith({
    String? id,
    String? kind,
    String? name,
    String? createdAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => WorkspaceRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  WorkspaceRow copyWithCompanion(WorkspacesCompanion data) {
    return WorkspaceRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, kind, name, createdAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.deletedAt == this.deletedAt);
}

class WorkspacesCompanion extends UpdateCompanion<WorkspaceRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<String> createdAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const WorkspacesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkspacesCompanion.insert({
    required String id,
    required String kind,
    required String name,
    required String createdAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<WorkspaceRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? createdAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkspacesCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<String>? createdAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return WorkspacesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspacesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class AppSettingRow extends DataClass implements Insertable<AppSettingRow> {
  final String key;
  final String value;
  const AppSettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSettingRow copyWith({String? key, String? value}) =>
      AppSettingRow(key: key ?? this.key, value: value ?? this.value);
  AppSettingRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BanksTable extends Banks with TableInfo<$BanksTable, BankRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BanksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countryMeta = const VerificationMeta(
    'country',
  );
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
    'country',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('CN'),
  );
  static const VerificationMeta _businessTzDefaultMeta = const VerificationMeta(
    'businessTzDefault',
  );
  @override
  late final GeneratedColumn<String> businessTzDefault =
      GeneratedColumn<String>(
        'business_tz_default',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('Asia/Shanghai'),
      );
  static const VerificationMeta _isBuiltinMeta = const VerificationMeta(
    'isBuiltin',
  );
  @override
  late final GeneratedColumn<bool> isBuiltin = GeneratedColumn<bool>(
    'is_builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    country,
    businessTzDefault,
    isBuiltin,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'banks';
  @override
  VerificationContext validateIntegrity(
    Insertable<BankRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('country')) {
      context.handle(
        _countryMeta,
        country.isAcceptableOrUnknown(data['country']!, _countryMeta),
      );
    }
    if (data.containsKey('business_tz_default')) {
      context.handle(
        _businessTzDefaultMeta,
        businessTzDefault.isAcceptableOrUnknown(
          data['business_tz_default']!,
          _businessTzDefaultMeta,
        ),
      );
    }
    if (data.containsKey('is_builtin')) {
      context.handle(
        _isBuiltinMeta,
        isBuiltin.isAcceptableOrUnknown(data['is_builtin']!, _isBuiltinMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, name},
  ];
  @override
  BankRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BankRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      country: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country'],
      )!,
      businessTzDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_tz_default'],
      )!,
      isBuiltin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_builtin'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BanksTable createAlias(String alias) {
    return $BanksTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class BankRow extends DataClass implements Insertable<BankRow> {
  final String id;
  final String workspaceId;
  final String name;
  final String country;
  final String businessTzDefault;
  final bool isBuiltin;
  final String createdAt;
  const BankRow({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.country,
    required this.businessTzDefault,
    required this.isBuiltin,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    map['country'] = Variable<String>(country);
    map['business_tz_default'] = Variable<String>(businessTzDefault);
    map['is_builtin'] = Variable<bool>(isBuiltin);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  BanksCompanion toCompanion(bool nullToAbsent) {
    return BanksCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      country: Value(country),
      businessTzDefault: Value(businessTzDefault),
      isBuiltin: Value(isBuiltin),
      createdAt: Value(createdAt),
    );
  }

  factory BankRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BankRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      country: serializer.fromJson<String>(json['country']),
      businessTzDefault: serializer.fromJson<String>(json['businessTzDefault']),
      isBuiltin: serializer.fromJson<bool>(json['isBuiltin']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'country': serializer.toJson<String>(country),
      'businessTzDefault': serializer.toJson<String>(businessTzDefault),
      'isBuiltin': serializer.toJson<bool>(isBuiltin),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  BankRow copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? country,
    String? businessTzDefault,
    bool? isBuiltin,
    String? createdAt,
  }) => BankRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    country: country ?? this.country,
    businessTzDefault: businessTzDefault ?? this.businessTzDefault,
    isBuiltin: isBuiltin ?? this.isBuiltin,
    createdAt: createdAt ?? this.createdAt,
  );
  BankRow copyWithCompanion(BanksCompanion data) {
    return BankRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      country: data.country.present ? data.country.value : this.country,
      businessTzDefault: data.businessTzDefault.present
          ? data.businessTzDefault.value
          : this.businessTzDefault,
      isBuiltin: data.isBuiltin.present ? data.isBuiltin.value : this.isBuiltin,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BankRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('country: $country, ')
          ..write('businessTzDefault: $businessTzDefault, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    country,
    businessTzDefault,
    isBuiltin,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BankRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.country == this.country &&
          other.businessTzDefault == this.businessTzDefault &&
          other.isBuiltin == this.isBuiltin &&
          other.createdAt == this.createdAt);
}

class BanksCompanion extends UpdateCompanion<BankRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String> country;
  final Value<String> businessTzDefault;
  final Value<bool> isBuiltin;
  final Value<String> createdAt;
  final Value<int> rowid;
  const BanksCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.country = const Value.absent(),
    this.businessTzDefault = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BanksCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    this.country = const Value.absent(),
    this.businessTzDefault = const Value.absent(),
    this.isBuiltin = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<BankRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? country,
    Expression<String>? businessTzDefault,
    Expression<bool>? isBuiltin,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (country != null) 'country': country,
      if (businessTzDefault != null) 'business_tz_default': businessTzDefault,
      if (isBuiltin != null) 'is_builtin': isBuiltin,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BanksCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String>? country,
    Value<String>? businessTzDefault,
    Value<bool>? isBuiltin,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return BanksCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      country: country ?? this.country,
      businessTzDefault: businessTzDefault ?? this.businessTzDefault,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (businessTzDefault.present) {
      map['business_tz_default'] = Variable<String>(businessTzDefault.value);
    }
    if (isBuiltin.present) {
      map['is_builtin'] = Variable<bool>(isBuiltin.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BanksCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('country: $country, ')
          ..write('businessTzDefault: $businessTzDefault, ')
          ..write('isBuiltin: $isBuiltin, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CreditPoolsTable extends CreditPools
    with TableInfo<$CreditPoolsTable, CreditPoolRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CreditPoolsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bankIdMeta = const VerificationMeta('bankId');
  @override
  late final GeneratedColumn<String> bankId = GeneratedColumn<String>(
    'bank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentPoolIdMeta = const VerificationMeta(
    'parentPoolId',
  );
  @override
  late final GeneratedColumn<String> parentPoolId = GeneratedColumn<String>(
    'parent_pool_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sharedLimitMinorMeta = const VerificationMeta(
    'sharedLimitMinor',
  );
  @override
  late final GeneratedColumn<int> sharedLimitMinor = GeneratedColumn<int>(
    'shared_limit_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    bankId,
    name,
    parentPoolId,
    sharedLimitMinor,
    currency,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credit_pools';
  @override
  VerificationContext validateIntegrity(
    Insertable<CreditPoolRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('bank_id')) {
      context.handle(
        _bankIdMeta,
        bankId.isAcceptableOrUnknown(data['bank_id']!, _bankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bankIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_pool_id')) {
      context.handle(
        _parentPoolIdMeta,
        parentPoolId.isAcceptableOrUnknown(
          data['parent_pool_id']!,
          _parentPoolIdMeta,
        ),
      );
    }
    if (data.containsKey('shared_limit_minor')) {
      context.handle(
        _sharedLimitMinorMeta,
        sharedLimitMinor.isAcceptableOrUnknown(
          data['shared_limit_minor']!,
          _sharedLimitMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sharedLimitMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, bankId, name},
  ];
  @override
  CreditPoolRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CreditPoolRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      bankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bank_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      parentPoolId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_pool_id'],
      ),
      sharedLimitMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}shared_limit_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CreditPoolsTable createAlias(String alias) {
    return $CreditPoolsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CreditPoolRow extends DataClass implements Insertable<CreditPoolRow> {
  final String id;
  final String workspaceId;
  final String bankId;
  final String name;
  final String? parentPoolId;
  final int sharedLimitMinor;
  final String currency;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const CreditPoolRow({
    required this.id,
    required this.workspaceId,
    required this.bankId,
    required this.name,
    this.parentPoolId,
    required this.sharedLimitMinor,
    required this.currency,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['bank_id'] = Variable<String>(bankId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentPoolId != null) {
      map['parent_pool_id'] = Variable<String>(parentPoolId);
    }
    map['shared_limit_minor'] = Variable<int>(sharedLimitMinor);
    map['currency'] = Variable<String>(currency);
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  CreditPoolsCompanion toCompanion(bool nullToAbsent) {
    return CreditPoolsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      bankId: Value(bankId),
      name: Value(name),
      parentPoolId: parentPoolId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentPoolId),
      sharedLimitMinor: Value(sharedLimitMinor),
      currency: Value(currency),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CreditPoolRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CreditPoolRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      bankId: serializer.fromJson<String>(json['bankId']),
      name: serializer.fromJson<String>(json['name']),
      parentPoolId: serializer.fromJson<String?>(json['parentPoolId']),
      sharedLimitMinor: serializer.fromJson<int>(json['sharedLimitMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'bankId': serializer.toJson<String>(bankId),
      'name': serializer.toJson<String>(name),
      'parentPoolId': serializer.toJson<String?>(parentPoolId),
      'sharedLimitMinor': serializer.toJson<int>(sharedLimitMinor),
      'currency': serializer.toJson<String>(currency),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  CreditPoolRow copyWith({
    String? id,
    String? workspaceId,
    String? bankId,
    String? name,
    Value<String?> parentPoolId = const Value.absent(),
    int? sharedLimitMinor,
    String? currency,
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => CreditPoolRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    bankId: bankId ?? this.bankId,
    name: name ?? this.name,
    parentPoolId: parentPoolId.present ? parentPoolId.value : this.parentPoolId,
    sharedLimitMinor: sharedLimitMinor ?? this.sharedLimitMinor,
    currency: currency ?? this.currency,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CreditPoolRow copyWithCompanion(CreditPoolsCompanion data) {
    return CreditPoolRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      bankId: data.bankId.present ? data.bankId.value : this.bankId,
      name: data.name.present ? data.name.value : this.name,
      parentPoolId: data.parentPoolId.present
          ? data.parentPoolId.value
          : this.parentPoolId,
      sharedLimitMinor: data.sharedLimitMinor.present
          ? data.sharedLimitMinor.value
          : this.sharedLimitMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CreditPoolRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('bankId: $bankId, ')
          ..write('name: $name, ')
          ..write('parentPoolId: $parentPoolId, ')
          ..write('sharedLimitMinor: $sharedLimitMinor, ')
          ..write('currency: $currency, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    bankId,
    name,
    parentPoolId,
    sharedLimitMinor,
    currency,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CreditPoolRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.bankId == this.bankId &&
          other.name == this.name &&
          other.parentPoolId == this.parentPoolId &&
          other.sharedLimitMinor == this.sharedLimitMinor &&
          other.currency == this.currency &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CreditPoolsCompanion extends UpdateCompanion<CreditPoolRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> bankId;
  final Value<String> name;
  final Value<String?> parentPoolId;
  final Value<int> sharedLimitMinor;
  final Value<String> currency;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const CreditPoolsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.bankId = const Value.absent(),
    this.name = const Value.absent(),
    this.parentPoolId = const Value.absent(),
    this.sharedLimitMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CreditPoolsCompanion.insert({
    required String id,
    required String workspaceId,
    required String bankId,
    required String name,
    this.parentPoolId = const Value.absent(),
    required int sharedLimitMinor,
    required String currency,
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       bankId = Value(bankId),
       name = Value(name),
       sharedLimitMinor = Value(sharedLimitMinor),
       currency = Value(currency),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CreditPoolRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? bankId,
    Expression<String>? name,
    Expression<String>? parentPoolId,
    Expression<int>? sharedLimitMinor,
    Expression<String>? currency,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (bankId != null) 'bank_id': bankId,
      if (name != null) 'name': name,
      if (parentPoolId != null) 'parent_pool_id': parentPoolId,
      if (sharedLimitMinor != null) 'shared_limit_minor': sharedLimitMinor,
      if (currency != null) 'currency': currency,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CreditPoolsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? bankId,
    Value<String>? name,
    Value<String?>? parentPoolId,
    Value<int>? sharedLimitMinor,
    Value<String>? currency,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return CreditPoolsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      bankId: bankId ?? this.bankId,
      name: name ?? this.name,
      parentPoolId: parentPoolId ?? this.parentPoolId,
      sharedLimitMinor: sharedLimitMinor ?? this.sharedLimitMinor,
      currency: currency ?? this.currency,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (bankId.present) {
      map['bank_id'] = Variable<String>(bankId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentPoolId.present) {
      map['parent_pool_id'] = Variable<String>(parentPoolId.value);
    }
    if (sharedLimitMinor.present) {
      map['shared_limit_minor'] = Variable<int>(sharedLimitMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CreditPoolsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('bankId: $bankId, ')
          ..write('name: $name, ')
          ..write('parentPoolId: $parentPoolId, ')
          ..write('sharedLimitMinor: $sharedLimitMinor, ')
          ..write('currency: $currency, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CreditAccountsTable extends CreditAccounts
    with TableInfo<$CreditAccountsTable, CreditAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CreditAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bankIdMeta = const VerificationMeta('bankId');
  @override
  late final GeneratedColumn<String> bankId = GeneratedColumn<String>(
    'bank_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productNameMeta = const VerificationMeta(
    'productName',
  );
  @override
  late final GeneratedColumn<String> productName = GeneratedColumn<String>(
    'product_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _holderAliasMeta = const VerificationMeta(
    'holderAlias',
  );
  @override
  late final GeneratedColumn<String> holderAlias = GeneratedColumn<String>(
    'holder_alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessTzMeta = const VerificationMeta(
    'businessTz',
  );
  @override
  late final GeneratedColumn<String> businessTz = GeneratedColumn<String>(
    'business_tz',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Asia/Shanghai'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _openedOnMeta = const VerificationMeta(
    'openedOn',
  );
  @override
  late final GeneratedColumn<String> openedOn = GeneratedColumn<String>(
    'opened_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedOnMeta = const VerificationMeta(
    'closedOn',
  );
  @override
  late final GeneratedColumn<String> closedOn = GeneratedColumn<String>(
    'closed_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _poolIdMeta = const VerificationMeta('poolId');
  @override
  late final GeneratedColumn<String> poolId = GeneratedColumn<String>(
    'pool_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    bankId,
    productName,
    holderAlias,
    businessTz,
    status,
    openedOn,
    closedOn,
    poolId,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credit_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CreditAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('bank_id')) {
      context.handle(
        _bankIdMeta,
        bankId.isAcceptableOrUnknown(data['bank_id']!, _bankIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bankIdMeta);
    }
    if (data.containsKey('product_name')) {
      context.handle(
        _productNameMeta,
        productName.isAcceptableOrUnknown(
          data['product_name']!,
          _productNameMeta,
        ),
      );
    }
    if (data.containsKey('holder_alias')) {
      context.handle(
        _holderAliasMeta,
        holderAlias.isAcceptableOrUnknown(
          data['holder_alias']!,
          _holderAliasMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_holderAliasMeta);
    }
    if (data.containsKey('business_tz')) {
      context.handle(
        _businessTzMeta,
        businessTz.isAcceptableOrUnknown(data['business_tz']!, _businessTzMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('opened_on')) {
      context.handle(
        _openedOnMeta,
        openedOn.isAcceptableOrUnknown(data['opened_on']!, _openedOnMeta),
      );
    }
    if (data.containsKey('closed_on')) {
      context.handle(
        _closedOnMeta,
        closedOn.isAcceptableOrUnknown(data['closed_on']!, _closedOnMeta),
      );
    }
    if (data.containsKey('pool_id')) {
      context.handle(
        _poolIdMeta,
        poolId.isAcceptableOrUnknown(data['pool_id']!, _poolIdMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
  ];
  @override
  CreditAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CreditAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      bankId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bank_id'],
      )!,
      productName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_name'],
      ),
      holderAlias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}holder_alias'],
      )!,
      businessTz: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}business_tz'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      openedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opened_on'],
      ),
      closedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}closed_on'],
      ),
      poolId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pool_id'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CreditAccountsTable createAlias(String alias) {
    return $CreditAccountsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CreditAccountRow extends DataClass
    implements Insertable<CreditAccountRow> {
  final String id;
  final String workspaceId;
  final String bankId;
  final String? productName;
  final String holderAlias;
  final String businessTz;

  /// `active` / `frozen` / `closed`。
  final String status;
  final String? openedOn;
  final String? closedOn;
  final String? poolId;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  const CreditAccountRow({
    required this.id,
    required this.workspaceId,
    required this.bankId,
    this.productName,
    required this.holderAlias,
    required this.businessTz,
    required this.status,
    this.openedOn,
    this.closedOn,
    this.poolId,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['bank_id'] = Variable<String>(bankId);
    if (!nullToAbsent || productName != null) {
      map['product_name'] = Variable<String>(productName);
    }
    map['holder_alias'] = Variable<String>(holderAlias);
    map['business_tz'] = Variable<String>(businessTz);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || openedOn != null) {
      map['opened_on'] = Variable<String>(openedOn);
    }
    if (!nullToAbsent || closedOn != null) {
      map['closed_on'] = Variable<String>(closedOn);
    }
    if (!nullToAbsent || poolId != null) {
      map['pool_id'] = Variable<String>(poolId);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  CreditAccountsCompanion toCompanion(bool nullToAbsent) {
    return CreditAccountsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      bankId: Value(bankId),
      productName: productName == null && nullToAbsent
          ? const Value.absent()
          : Value(productName),
      holderAlias: Value(holderAlias),
      businessTz: Value(businessTz),
      status: Value(status),
      openedOn: openedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(openedOn),
      closedOn: closedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(closedOn),
      poolId: poolId == null && nullToAbsent
          ? const Value.absent()
          : Value(poolId),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CreditAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CreditAccountRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      bankId: serializer.fromJson<String>(json['bankId']),
      productName: serializer.fromJson<String?>(json['productName']),
      holderAlias: serializer.fromJson<String>(json['holderAlias']),
      businessTz: serializer.fromJson<String>(json['businessTz']),
      status: serializer.fromJson<String>(json['status']),
      openedOn: serializer.fromJson<String?>(json['openedOn']),
      closedOn: serializer.fromJson<String?>(json['closedOn']),
      poolId: serializer.fromJson<String?>(json['poolId']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'bankId': serializer.toJson<String>(bankId),
      'productName': serializer.toJson<String?>(productName),
      'holderAlias': serializer.toJson<String>(holderAlias),
      'businessTz': serializer.toJson<String>(businessTz),
      'status': serializer.toJson<String>(status),
      'openedOn': serializer.toJson<String?>(openedOn),
      'closedOn': serializer.toJson<String?>(closedOn),
      'poolId': serializer.toJson<String?>(poolId),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  CreditAccountRow copyWith({
    String? id,
    String? workspaceId,
    String? bankId,
    Value<String?> productName = const Value.absent(),
    String? holderAlias,
    String? businessTz,
    String? status,
    Value<String?> openedOn = const Value.absent(),
    Value<String?> closedOn = const Value.absent(),
    Value<String?> poolId = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => CreditAccountRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    bankId: bankId ?? this.bankId,
    productName: productName.present ? productName.value : this.productName,
    holderAlias: holderAlias ?? this.holderAlias,
    businessTz: businessTz ?? this.businessTz,
    status: status ?? this.status,
    openedOn: openedOn.present ? openedOn.value : this.openedOn,
    closedOn: closedOn.present ? closedOn.value : this.closedOn,
    poolId: poolId.present ? poolId.value : this.poolId,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CreditAccountRow copyWithCompanion(CreditAccountsCompanion data) {
    return CreditAccountRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      bankId: data.bankId.present ? data.bankId.value : this.bankId,
      productName: data.productName.present
          ? data.productName.value
          : this.productName,
      holderAlias: data.holderAlias.present
          ? data.holderAlias.value
          : this.holderAlias,
      businessTz: data.businessTz.present
          ? data.businessTz.value
          : this.businessTz,
      status: data.status.present ? data.status.value : this.status,
      openedOn: data.openedOn.present ? data.openedOn.value : this.openedOn,
      closedOn: data.closedOn.present ? data.closedOn.value : this.closedOn,
      poolId: data.poolId.present ? data.poolId.value : this.poolId,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CreditAccountRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('bankId: $bankId, ')
          ..write('productName: $productName, ')
          ..write('holderAlias: $holderAlias, ')
          ..write('businessTz: $businessTz, ')
          ..write('status: $status, ')
          ..write('openedOn: $openedOn, ')
          ..write('closedOn: $closedOn, ')
          ..write('poolId: $poolId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    bankId,
    productName,
    holderAlias,
    businessTz,
    status,
    openedOn,
    closedOn,
    poolId,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CreditAccountRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.bankId == this.bankId &&
          other.productName == this.productName &&
          other.holderAlias == this.holderAlias &&
          other.businessTz == this.businessTz &&
          other.status == this.status &&
          other.openedOn == this.openedOn &&
          other.closedOn == this.closedOn &&
          other.poolId == this.poolId &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CreditAccountsCompanion extends UpdateCompanion<CreditAccountRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> bankId;
  final Value<String?> productName;
  final Value<String> holderAlias;
  final Value<String> businessTz;
  final Value<String> status;
  final Value<String?> openedOn;
  final Value<String?> closedOn;
  final Value<String?> poolId;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const CreditAccountsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.bankId = const Value.absent(),
    this.productName = const Value.absent(),
    this.holderAlias = const Value.absent(),
    this.businessTz = const Value.absent(),
    this.status = const Value.absent(),
    this.openedOn = const Value.absent(),
    this.closedOn = const Value.absent(),
    this.poolId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CreditAccountsCompanion.insert({
    required String id,
    required String workspaceId,
    required String bankId,
    this.productName = const Value.absent(),
    required String holderAlias,
    this.businessTz = const Value.absent(),
    this.status = const Value.absent(),
    this.openedOn = const Value.absent(),
    this.closedOn = const Value.absent(),
    this.poolId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       bankId = Value(bankId),
       holderAlias = Value(holderAlias),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CreditAccountRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? bankId,
    Expression<String>? productName,
    Expression<String>? holderAlias,
    Expression<String>? businessTz,
    Expression<String>? status,
    Expression<String>? openedOn,
    Expression<String>? closedOn,
    Expression<String>? poolId,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (bankId != null) 'bank_id': bankId,
      if (productName != null) 'product_name': productName,
      if (holderAlias != null) 'holder_alias': holderAlias,
      if (businessTz != null) 'business_tz': businessTz,
      if (status != null) 'status': status,
      if (openedOn != null) 'opened_on': openedOn,
      if (closedOn != null) 'closed_on': closedOn,
      if (poolId != null) 'pool_id': poolId,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CreditAccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? bankId,
    Value<String?>? productName,
    Value<String>? holderAlias,
    Value<String>? businessTz,
    Value<String>? status,
    Value<String?>? openedOn,
    Value<String?>? closedOn,
    Value<String?>? poolId,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CreditAccountsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      bankId: bankId ?? this.bankId,
      productName: productName ?? this.productName,
      holderAlias: holderAlias ?? this.holderAlias,
      businessTz: businessTz ?? this.businessTz,
      status: status ?? this.status,
      openedOn: openedOn ?? this.openedOn,
      closedOn: closedOn ?? this.closedOn,
      poolId: poolId ?? this.poolId,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (bankId.present) {
      map['bank_id'] = Variable<String>(bankId.value);
    }
    if (productName.present) {
      map['product_name'] = Variable<String>(productName.value);
    }
    if (holderAlias.present) {
      map['holder_alias'] = Variable<String>(holderAlias.value);
    }
    if (businessTz.present) {
      map['business_tz'] = Variable<String>(businessTz.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (openedOn.present) {
      map['opened_on'] = Variable<String>(openedOn.value);
    }
    if (closedOn.present) {
      map['closed_on'] = Variable<String>(closedOn.value);
    }
    if (poolId.present) {
      map['pool_id'] = Variable<String>(poolId.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CreditAccountsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('bankId: $bankId, ')
          ..write('productName: $productName, ')
          ..write('holderAlias: $holderAlias, ')
          ..write('businessTz: $businessTz, ')
          ..write('status: $status, ')
          ..write('openedOn: $openedOn, ')
          ..write('closedOn: $closedOn, ')
          ..write('poolId: $poolId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CurrencyAccountsTable extends CurrencyAccounts
    with TableInfo<$CurrencyAccountsTable, CurrencyAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CurrencyAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creditAccountIdMeta = const VerificationMeta(
    'creditAccountId',
  );
  @override
  late final GeneratedColumn<String> creditAccountId = GeneratedColumn<String>(
    'credit_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    creditAccountId,
    currency,
    isPrimary,
    rowVersion,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'currency_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CurrencyAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('credit_account_id')) {
      context.handle(
        _creditAccountIdMeta,
        creditAccountId.isAcceptableOrUnknown(
          data['credit_account_id']!,
          _creditAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creditAccountIdMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {creditAccountId, currency},
  ];
  @override
  CurrencyAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CurrencyAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      creditAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credit_account_id'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CurrencyAccountsTable createAlias(String alias) {
    return $CurrencyAccountsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CurrencyAccountRow extends DataClass
    implements Insertable<CurrencyAccountRow> {
  final String id;
  final String workspaceId;
  final String creditAccountId;
  final String currency;
  final bool isPrimary;
  final int rowVersion;
  final String createdAt;
  const CurrencyAccountRow({
    required this.id,
    required this.workspaceId,
    required this.creditAccountId,
    required this.currency,
    required this.isPrimary,
    required this.rowVersion,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['credit_account_id'] = Variable<String>(creditAccountId);
    map['currency'] = Variable<String>(currency);
    map['is_primary'] = Variable<bool>(isPrimary);
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  CurrencyAccountsCompanion toCompanion(bool nullToAbsent) {
    return CurrencyAccountsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      creditAccountId: Value(creditAccountId),
      currency: Value(currency),
      isPrimary: Value(isPrimary),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
    );
  }

  factory CurrencyAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CurrencyAccountRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      creditAccountId: serializer.fromJson<String>(json['creditAccountId']),
      currency: serializer.fromJson<String>(json['currency']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'creditAccountId': serializer.toJson<String>(creditAccountId),
      'currency': serializer.toJson<String>(currency),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  CurrencyAccountRow copyWith({
    String? id,
    String? workspaceId,
    String? creditAccountId,
    String? currency,
    bool? isPrimary,
    int? rowVersion,
    String? createdAt,
  }) => CurrencyAccountRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    creditAccountId: creditAccountId ?? this.creditAccountId,
    currency: currency ?? this.currency,
    isPrimary: isPrimary ?? this.isPrimary,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
  );
  CurrencyAccountRow copyWithCompanion(CurrencyAccountsCompanion data) {
    return CurrencyAccountRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      creditAccountId: data.creditAccountId.present
          ? data.creditAccountId.value
          : this.creditAccountId,
      currency: data.currency.present ? data.currency.value : this.currency,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CurrencyAccountRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('creditAccountId: $creditAccountId, ')
          ..write('currency: $currency, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    creditAccountId,
    currency,
    isPrimary,
    rowVersion,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CurrencyAccountRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.creditAccountId == this.creditAccountId &&
          other.currency == this.currency &&
          other.isPrimary == this.isPrimary &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt);
}

class CurrencyAccountsCompanion extends UpdateCompanion<CurrencyAccountRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> creditAccountId;
  final Value<String> currency;
  final Value<bool> isPrimary;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<int> rowid;
  const CurrencyAccountsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.creditAccountId = const Value.absent(),
    this.currency = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CurrencyAccountsCompanion.insert({
    required String id,
    required String workspaceId,
    required String creditAccountId,
    required String currency,
    this.isPrimary = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       creditAccountId = Value(creditAccountId),
       currency = Value(currency),
       createdAt = Value(createdAt);
  static Insertable<CurrencyAccountRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? creditAccountId,
    Expression<String>? currency,
    Expression<bool>? isPrimary,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (creditAccountId != null) 'credit_account_id': creditAccountId,
      if (currency != null) 'currency': currency,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CurrencyAccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? creditAccountId,
    Value<String>? currency,
    Value<bool>? isPrimary,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return CurrencyAccountsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      creditAccountId: creditAccountId ?? this.creditAccountId,
      currency: currency ?? this.currency,
      isPrimary: isPrimary ?? this.isPrimary,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (creditAccountId.present) {
      map['credit_account_id'] = Variable<String>(creditAccountId.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CurrencyAccountsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('creditAccountId: $creditAccountId, ')
          ..write('currency: $currency, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, CardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creditAccountIdMeta = const VerificationMeta(
    'creditAccountId',
  );
  @override
  late final GeneratedColumn<String> creditAccountId = GeneratedColumn<String>(
    'credit_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _last4Meta = const VerificationMeta('last4');
  @override
  late final GeneratedColumn<String> last4 = GeneratedColumn<String>(
    'last4',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkMeta = const VerificationMeta(
    'network',
  );
  @override
  late final GeneratedColumn<String> network = GeneratedColumn<String>(
    'network',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _holderKindMeta = const VerificationMeta(
    'holderKind',
  );
  @override
  late final GeneratedColumn<String> holderKind = GeneratedColumn<String>(
    'holder_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _primaryCardIdMeta = const VerificationMeta(
    'primaryCardId',
  );
  @override
  late final GeneratedColumn<String> primaryCardId = GeneratedColumn<String>(
    'primary_card_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresYmMeta = const VerificationMeta(
    'expiresYm',
  );
  @override
  late final GeneratedColumn<String> expiresYm = GeneratedColumn<String>(
    'expires_ym',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replacedByCardIdMeta = const VerificationMeta(
    'replacedByCardId',
  );
  @override
  late final GeneratedColumn<String> replacedByCardId = GeneratedColumn<String>(
    'replaced_by_card_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveFromMeta = const VerificationMeta(
    'effectiveFrom',
  );
  @override
  late final GeneratedColumn<String> effectiveFrom = GeneratedColumn<String>(
    'effective_from',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedOnMeta = const VerificationMeta(
    'closedOn',
  );
  @override
  late final GeneratedColumn<String> closedOn = GeneratedColumn<String>(
    'closed_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    creditAccountId,
    last4,
    network,
    holderKind,
    primaryCardId,
    status,
    expiresYm,
    replacedByCardId,
    alias,
    effectiveFrom,
    closedOn,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('credit_account_id')) {
      context.handle(
        _creditAccountIdMeta,
        creditAccountId.isAcceptableOrUnknown(
          data['credit_account_id']!,
          _creditAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creditAccountIdMeta);
    }
    if (data.containsKey('last4')) {
      context.handle(
        _last4Meta,
        last4.isAcceptableOrUnknown(data['last4']!, _last4Meta),
      );
    } else if (isInserting) {
      context.missing(_last4Meta);
    }
    if (data.containsKey('network')) {
      context.handle(
        _networkMeta,
        network.isAcceptableOrUnknown(data['network']!, _networkMeta),
      );
    }
    if (data.containsKey('holder_kind')) {
      context.handle(
        _holderKindMeta,
        holderKind.isAcceptableOrUnknown(data['holder_kind']!, _holderKindMeta),
      );
    } else if (isInserting) {
      context.missing(_holderKindMeta);
    }
    if (data.containsKey('primary_card_id')) {
      context.handle(
        _primaryCardIdMeta,
        primaryCardId.isAcceptableOrUnknown(
          data['primary_card_id']!,
          _primaryCardIdMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('expires_ym')) {
      context.handle(
        _expiresYmMeta,
        expiresYm.isAcceptableOrUnknown(data['expires_ym']!, _expiresYmMeta),
      );
    }
    if (data.containsKey('replaced_by_card_id')) {
      context.handle(
        _replacedByCardIdMeta,
        replacedByCardId.isAcceptableOrUnknown(
          data['replaced_by_card_id']!,
          _replacedByCardIdMeta,
        ),
      );
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    }
    if (data.containsKey('effective_from')) {
      context.handle(
        _effectiveFromMeta,
        effectiveFrom.isAcceptableOrUnknown(
          data['effective_from']!,
          _effectiveFromMeta,
        ),
      );
    }
    if (data.containsKey('closed_on')) {
      context.handle(
        _closedOnMeta,
        closedOn.isAcceptableOrUnknown(data['closed_on']!, _closedOnMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, creditAccountId, id},
  ];
  @override
  CardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      creditAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credit_account_id'],
      )!,
      last4: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last4'],
      )!,
      network: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}network'],
      ),
      holderKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}holder_kind'],
      )!,
      primaryCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}primary_card_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      expiresYm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expires_ym'],
      ),
      replacedByCardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}replaced_by_card_id'],
      ),
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      ),
      effectiveFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_from'],
      ),
      closedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}closed_on'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CardRow extends DataClass implements Insertable<CardRow> {
  final String id;
  final String workspaceId;
  final String creditAccountId;
  final String last4;

  /// `unionpay` / `visa` / `mastercard` / `amex` / `jcb` / `discover` / `other`。
  final String? network;

  /// `primary` / `supplementary`。
  final String holderKind;
  final String? primaryCardId;

  /// `draft` / `active` / `frozen` / `replaced` / `closed`。
  final String status;

  /// `YYYY-MM`。
  final String? expiresYm;
  final String? replacedByCardId;
  final String? alias;

  /// 卡片生效日（换卡/补卡时为新卡的生效日）。
  final String? effectiveFrom;

  /// 销卡日。
  final String? closedOn;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const CardRow({
    required this.id,
    required this.workspaceId,
    required this.creditAccountId,
    required this.last4,
    this.network,
    required this.holderKind,
    this.primaryCardId,
    required this.status,
    this.expiresYm,
    this.replacedByCardId,
    this.alias,
    this.effectiveFrom,
    this.closedOn,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['credit_account_id'] = Variable<String>(creditAccountId);
    map['last4'] = Variable<String>(last4);
    if (!nullToAbsent || network != null) {
      map['network'] = Variable<String>(network);
    }
    map['holder_kind'] = Variable<String>(holderKind);
    if (!nullToAbsent || primaryCardId != null) {
      map['primary_card_id'] = Variable<String>(primaryCardId);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || expiresYm != null) {
      map['expires_ym'] = Variable<String>(expiresYm);
    }
    if (!nullToAbsent || replacedByCardId != null) {
      map['replaced_by_card_id'] = Variable<String>(replacedByCardId);
    }
    if (!nullToAbsent || alias != null) {
      map['alias'] = Variable<String>(alias);
    }
    if (!nullToAbsent || effectiveFrom != null) {
      map['effective_from'] = Variable<String>(effectiveFrom);
    }
    if (!nullToAbsent || closedOn != null) {
      map['closed_on'] = Variable<String>(closedOn);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      creditAccountId: Value(creditAccountId),
      last4: Value(last4),
      network: network == null && nullToAbsent
          ? const Value.absent()
          : Value(network),
      holderKind: Value(holderKind),
      primaryCardId: primaryCardId == null && nullToAbsent
          ? const Value.absent()
          : Value(primaryCardId),
      status: Value(status),
      expiresYm: expiresYm == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresYm),
      replacedByCardId: replacedByCardId == null && nullToAbsent
          ? const Value.absent()
          : Value(replacedByCardId),
      alias: alias == null && nullToAbsent
          ? const Value.absent()
          : Value(alias),
      effectiveFrom: effectiveFrom == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveFrom),
      closedOn: closedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(closedOn),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      creditAccountId: serializer.fromJson<String>(json['creditAccountId']),
      last4: serializer.fromJson<String>(json['last4']),
      network: serializer.fromJson<String?>(json['network']),
      holderKind: serializer.fromJson<String>(json['holderKind']),
      primaryCardId: serializer.fromJson<String?>(json['primaryCardId']),
      status: serializer.fromJson<String>(json['status']),
      expiresYm: serializer.fromJson<String?>(json['expiresYm']),
      replacedByCardId: serializer.fromJson<String?>(json['replacedByCardId']),
      alias: serializer.fromJson<String?>(json['alias']),
      effectiveFrom: serializer.fromJson<String?>(json['effectiveFrom']),
      closedOn: serializer.fromJson<String?>(json['closedOn']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'creditAccountId': serializer.toJson<String>(creditAccountId),
      'last4': serializer.toJson<String>(last4),
      'network': serializer.toJson<String?>(network),
      'holderKind': serializer.toJson<String>(holderKind),
      'primaryCardId': serializer.toJson<String?>(primaryCardId),
      'status': serializer.toJson<String>(status),
      'expiresYm': serializer.toJson<String?>(expiresYm),
      'replacedByCardId': serializer.toJson<String?>(replacedByCardId),
      'alias': serializer.toJson<String?>(alias),
      'effectiveFrom': serializer.toJson<String?>(effectiveFrom),
      'closedOn': serializer.toJson<String?>(closedOn),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  CardRow copyWith({
    String? id,
    String? workspaceId,
    String? creditAccountId,
    String? last4,
    Value<String?> network = const Value.absent(),
    String? holderKind,
    Value<String?> primaryCardId = const Value.absent(),
    String? status,
    Value<String?> expiresYm = const Value.absent(),
    Value<String?> replacedByCardId = const Value.absent(),
    Value<String?> alias = const Value.absent(),
    Value<String?> effectiveFrom = const Value.absent(),
    Value<String?> closedOn = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => CardRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    creditAccountId: creditAccountId ?? this.creditAccountId,
    last4: last4 ?? this.last4,
    network: network.present ? network.value : this.network,
    holderKind: holderKind ?? this.holderKind,
    primaryCardId: primaryCardId.present
        ? primaryCardId.value
        : this.primaryCardId,
    status: status ?? this.status,
    expiresYm: expiresYm.present ? expiresYm.value : this.expiresYm,
    replacedByCardId: replacedByCardId.present
        ? replacedByCardId.value
        : this.replacedByCardId,
    alias: alias.present ? alias.value : this.alias,
    effectiveFrom: effectiveFrom.present
        ? effectiveFrom.value
        : this.effectiveFrom,
    closedOn: closedOn.present ? closedOn.value : this.closedOn,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CardRow copyWithCompanion(CardsCompanion data) {
    return CardRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      creditAccountId: data.creditAccountId.present
          ? data.creditAccountId.value
          : this.creditAccountId,
      last4: data.last4.present ? data.last4.value : this.last4,
      network: data.network.present ? data.network.value : this.network,
      holderKind: data.holderKind.present
          ? data.holderKind.value
          : this.holderKind,
      primaryCardId: data.primaryCardId.present
          ? data.primaryCardId.value
          : this.primaryCardId,
      status: data.status.present ? data.status.value : this.status,
      expiresYm: data.expiresYm.present ? data.expiresYm.value : this.expiresYm,
      replacedByCardId: data.replacedByCardId.present
          ? data.replacedByCardId.value
          : this.replacedByCardId,
      alias: data.alias.present ? data.alias.value : this.alias,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      closedOn: data.closedOn.present ? data.closedOn.value : this.closedOn,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('creditAccountId: $creditAccountId, ')
          ..write('last4: $last4, ')
          ..write('network: $network, ')
          ..write('holderKind: $holderKind, ')
          ..write('primaryCardId: $primaryCardId, ')
          ..write('status: $status, ')
          ..write('expiresYm: $expiresYm, ')
          ..write('replacedByCardId: $replacedByCardId, ')
          ..write('alias: $alias, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('closedOn: $closedOn, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    creditAccountId,
    last4,
    network,
    holderKind,
    primaryCardId,
    status,
    expiresYm,
    replacedByCardId,
    alias,
    effectiveFrom,
    closedOn,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.creditAccountId == this.creditAccountId &&
          other.last4 == this.last4 &&
          other.network == this.network &&
          other.holderKind == this.holderKind &&
          other.primaryCardId == this.primaryCardId &&
          other.status == this.status &&
          other.expiresYm == this.expiresYm &&
          other.replacedByCardId == this.replacedByCardId &&
          other.alias == this.alias &&
          other.effectiveFrom == this.effectiveFrom &&
          other.closedOn == this.closedOn &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CardsCompanion extends UpdateCompanion<CardRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> creditAccountId;
  final Value<String> last4;
  final Value<String?> network;
  final Value<String> holderKind;
  final Value<String?> primaryCardId;
  final Value<String> status;
  final Value<String?> expiresYm;
  final Value<String?> replacedByCardId;
  final Value<String?> alias;
  final Value<String?> effectiveFrom;
  final Value<String?> closedOn;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.creditAccountId = const Value.absent(),
    this.last4 = const Value.absent(),
    this.network = const Value.absent(),
    this.holderKind = const Value.absent(),
    this.primaryCardId = const Value.absent(),
    this.status = const Value.absent(),
    this.expiresYm = const Value.absent(),
    this.replacedByCardId = const Value.absent(),
    this.alias = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.closedOn = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    required String workspaceId,
    required String creditAccountId,
    required String last4,
    this.network = const Value.absent(),
    required String holderKind,
    this.primaryCardId = const Value.absent(),
    required String status,
    this.expiresYm = const Value.absent(),
    this.replacedByCardId = const Value.absent(),
    this.alias = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.closedOn = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       creditAccountId = Value(creditAccountId),
       last4 = Value(last4),
       holderKind = Value(holderKind),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CardRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? creditAccountId,
    Expression<String>? last4,
    Expression<String>? network,
    Expression<String>? holderKind,
    Expression<String>? primaryCardId,
    Expression<String>? status,
    Expression<String>? expiresYm,
    Expression<String>? replacedByCardId,
    Expression<String>? alias,
    Expression<String>? effectiveFrom,
    Expression<String>? closedOn,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (creditAccountId != null) 'credit_account_id': creditAccountId,
      if (last4 != null) 'last4': last4,
      if (network != null) 'network': network,
      if (holderKind != null) 'holder_kind': holderKind,
      if (primaryCardId != null) 'primary_card_id': primaryCardId,
      if (status != null) 'status': status,
      if (expiresYm != null) 'expires_ym': expiresYm,
      if (replacedByCardId != null) 'replaced_by_card_id': replacedByCardId,
      if (alias != null) 'alias': alias,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (closedOn != null) 'closed_on': closedOn,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? creditAccountId,
    Value<String>? last4,
    Value<String?>? network,
    Value<String>? holderKind,
    Value<String?>? primaryCardId,
    Value<String>? status,
    Value<String?>? expiresYm,
    Value<String?>? replacedByCardId,
    Value<String?>? alias,
    Value<String?>? effectiveFrom,
    Value<String?>? closedOn,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      creditAccountId: creditAccountId ?? this.creditAccountId,
      last4: last4 ?? this.last4,
      network: network ?? this.network,
      holderKind: holderKind ?? this.holderKind,
      primaryCardId: primaryCardId ?? this.primaryCardId,
      status: status ?? this.status,
      expiresYm: expiresYm ?? this.expiresYm,
      replacedByCardId: replacedByCardId ?? this.replacedByCardId,
      alias: alias ?? this.alias,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      closedOn: closedOn ?? this.closedOn,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (creditAccountId.present) {
      map['credit_account_id'] = Variable<String>(creditAccountId.value);
    }
    if (last4.present) {
      map['last4'] = Variable<String>(last4.value);
    }
    if (network.present) {
      map['network'] = Variable<String>(network.value);
    }
    if (holderKind.present) {
      map['holder_kind'] = Variable<String>(holderKind.value);
    }
    if (primaryCardId.present) {
      map['primary_card_id'] = Variable<String>(primaryCardId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (expiresYm.present) {
      map['expires_ym'] = Variable<String>(expiresYm.value);
    }
    if (replacedByCardId.present) {
      map['replaced_by_card_id'] = Variable<String>(replacedByCardId.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<String>(effectiveFrom.value);
    }
    if (closedOn.present) {
      map['closed_on'] = Variable<String>(closedOn.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('creditAccountId: $creditAccountId, ')
          ..write('last4: $last4, ')
          ..write('network: $network, ')
          ..write('holderKind: $holderKind, ')
          ..write('primaryCardId: $primaryCardId, ')
          ..write('status: $status, ')
          ..write('expiresYm: $expiresYm, ')
          ..write('replacedByCardId: $replacedByCardId, ')
          ..write('alias: $alias, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('closedOn: $closedOn, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BillingRuleVersionsTable extends BillingRuleVersions
    with TableInfo<$BillingRuleVersionsTable, BillingRuleVersionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BillingRuleVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectKindMeta = const VerificationMeta(
    'subjectKind',
  );
  @override
  late final GeneratedColumn<String> subjectKind = GeneratedColumn<String>(
    'subject_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statementDayMeta = const VerificationMeta(
    'statementDay',
  );
  @override
  late final GeneratedColumn<int> statementDay = GeneratedColumn<int>(
    'statement_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statementDayInclusiveMeta =
      const VerificationMeta('statementDayInclusive');
  @override
  late final GeneratedColumn<bool> statementDayInclusive =
      GeneratedColumn<bool>(
        'statement_day_inclusive',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("statement_day_inclusive" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _dueKindMeta = const VerificationMeta(
    'dueKind',
  );
  @override
  late final GeneratedColumn<String> dueKind = GeneratedColumn<String>(
    'due_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDayMeta = const VerificationMeta('dueDay');
  @override
  late final GeneratedColumn<int> dueDay = GeneratedColumn<int>(
    'due_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueMonthOffsetMeta = const VerificationMeta(
    'dueMonthOffset',
  );
  @override
  late final GeneratedColumn<int> dueMonthOffset = GeneratedColumn<int>(
    'due_month_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _dueDaysMeta = const VerificationMeta(
    'dueDays',
  );
  @override
  late final GeneratedColumn<int> dueDays = GeneratedColumn<int>(
    'due_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDayKindMeta = const VerificationMeta(
    'dueDayKind',
  );
  @override
  late final GeneratedColumn<String> dueDayKind = GeneratedColumn<String>(
    'due_day_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('calendar'),
  );
  static const VerificationMeta _holidayRolloverMeta = const VerificationMeta(
    'holidayRollover',
  );
  @override
  late final GeneratedColumn<String> holidayRollover = GeneratedColumn<String>(
    'holiday_rollover',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _cutoffTimeMeta = const VerificationMeta(
    'cutoffTime',
  );
  @override
  late final GeneratedColumn<String> cutoffTime = GeneratedColumn<String>(
    'cutoff_time',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postingDelayMinDaysMeta =
      const VerificationMeta('postingDelayMinDays');
  @override
  late final GeneratedColumn<int> postingDelayMinDays = GeneratedColumn<int>(
    'posting_delay_min_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _postingDelayMaxDaysMeta =
      const VerificationMeta('postingDelayMaxDays');
  @override
  late final GeneratedColumn<int> postingDelayMaxDays = GeneratedColumn<int>(
    'posting_delay_max_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveFromMeta = const VerificationMeta(
    'effectiveFrom',
  );
  @override
  late final GeneratedColumn<String> effectiveFrom = GeneratedColumn<String>(
    'effective_from',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _effectiveToMeta = const VerificationMeta(
    'effectiveTo',
  );
  @override
  late final GeneratedColumn<String> effectiveTo = GeneratedColumn<String>(
    'effective_to',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _verifiedOnMeta = const VerificationMeta(
    'verifiedOn',
  );
  @override
  late final GeneratedColumn<String> verifiedOn = GeneratedColumn<String>(
    'verified_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewStatusMeta = const VerificationMeta(
    'reviewStatus',
  );
  @override
  late final GeneratedColumn<String> reviewStatus = GeneratedColumn<String>(
    'review_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exceptionsMeta = const VerificationMeta(
    'exceptions',
  );
  @override
  late final GeneratedColumn<String> exceptions = GeneratedColumn<String>(
    'exceptions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    subjectKind,
    subjectId,
    statementDay,
    statementDayInclusive,
    dueKind,
    dueDay,
    dueMonthOffset,
    dueDays,
    dueDayKind,
    holidayRollover,
    cutoffTime,
    postingDelayMinDays,
    postingDelayMaxDays,
    source,
    effectiveFrom,
    effectiveTo,
    verifiedOn,
    version,
    reviewStatus,
    exceptions,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'billing_rule_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<BillingRuleVersionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('subject_kind')) {
      context.handle(
        _subjectKindMeta,
        subjectKind.isAcceptableOrUnknown(
          data['subject_kind']!,
          _subjectKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subjectKindMeta);
    }
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('statement_day')) {
      context.handle(
        _statementDayMeta,
        statementDay.isAcceptableOrUnknown(
          data['statement_day']!,
          _statementDayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementDayMeta);
    }
    if (data.containsKey('statement_day_inclusive')) {
      context.handle(
        _statementDayInclusiveMeta,
        statementDayInclusive.isAcceptableOrUnknown(
          data['statement_day_inclusive']!,
          _statementDayInclusiveMeta,
        ),
      );
    }
    if (data.containsKey('due_kind')) {
      context.handle(
        _dueKindMeta,
        dueKind.isAcceptableOrUnknown(data['due_kind']!, _dueKindMeta),
      );
    } else if (isInserting) {
      context.missing(_dueKindMeta);
    }
    if (data.containsKey('due_day')) {
      context.handle(
        _dueDayMeta,
        dueDay.isAcceptableOrUnknown(data['due_day']!, _dueDayMeta),
      );
    }
    if (data.containsKey('due_month_offset')) {
      context.handle(
        _dueMonthOffsetMeta,
        dueMonthOffset.isAcceptableOrUnknown(
          data['due_month_offset']!,
          _dueMonthOffsetMeta,
        ),
      );
    }
    if (data.containsKey('due_days')) {
      context.handle(
        _dueDaysMeta,
        dueDays.isAcceptableOrUnknown(data['due_days']!, _dueDaysMeta),
      );
    }
    if (data.containsKey('due_day_kind')) {
      context.handle(
        _dueDayKindMeta,
        dueDayKind.isAcceptableOrUnknown(
          data['due_day_kind']!,
          _dueDayKindMeta,
        ),
      );
    }
    if (data.containsKey('holiday_rollover')) {
      context.handle(
        _holidayRolloverMeta,
        holidayRollover.isAcceptableOrUnknown(
          data['holiday_rollover']!,
          _holidayRolloverMeta,
        ),
      );
    }
    if (data.containsKey('cutoff_time')) {
      context.handle(
        _cutoffTimeMeta,
        cutoffTime.isAcceptableOrUnknown(data['cutoff_time']!, _cutoffTimeMeta),
      );
    }
    if (data.containsKey('posting_delay_min_days')) {
      context.handle(
        _postingDelayMinDaysMeta,
        postingDelayMinDays.isAcceptableOrUnknown(
          data['posting_delay_min_days']!,
          _postingDelayMinDaysMeta,
        ),
      );
    }
    if (data.containsKey('posting_delay_max_days')) {
      context.handle(
        _postingDelayMaxDaysMeta,
        postingDelayMaxDays.isAcceptableOrUnknown(
          data['posting_delay_max_days']!,
          _postingDelayMaxDaysMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('effective_from')) {
      context.handle(
        _effectiveFromMeta,
        effectiveFrom.isAcceptableOrUnknown(
          data['effective_from']!,
          _effectiveFromMeta,
        ),
      );
    }
    if (data.containsKey('effective_to')) {
      context.handle(
        _effectiveToMeta,
        effectiveTo.isAcceptableOrUnknown(
          data['effective_to']!,
          _effectiveToMeta,
        ),
      );
    }
    if (data.containsKey('verified_on')) {
      context.handle(
        _verifiedOnMeta,
        verifiedOn.isAcceptableOrUnknown(data['verified_on']!, _verifiedOnMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('review_status')) {
      context.handle(
        _reviewStatusMeta,
        reviewStatus.isAcceptableOrUnknown(
          data['review_status']!,
          _reviewStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reviewStatusMeta);
    }
    if (data.containsKey('exceptions')) {
      context.handle(
        _exceptionsMeta,
        exceptions.isAcceptableOrUnknown(data['exceptions']!, _exceptionsMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, subjectKind, subjectId, version},
  ];
  @override
  BillingRuleVersionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BillingRuleVersionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      subjectKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_kind'],
      )!,
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      statementDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}statement_day'],
      )!,
      statementDayInclusive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}statement_day_inclusive'],
      )!,
      dueKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_kind'],
      )!,
      dueDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_day'],
      ),
      dueMonthOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_month_offset'],
      )!,
      dueDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_days'],
      ),
      dueDayKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_day_kind'],
      )!,
      holidayRollover: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}holiday_rollover'],
      )!,
      cutoffTime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cutoff_time'],
      ),
      postingDelayMinDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}posting_delay_min_days'],
      )!,
      postingDelayMaxDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}posting_delay_max_days'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      effectiveFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_from'],
      ),
      effectiveTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_to'],
      ),
      verifiedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verified_on'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      reviewStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}review_status'],
      )!,
      exceptions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exceptions'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BillingRuleVersionsTable createAlias(String alias) {
    return $BillingRuleVersionsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class BillingRuleVersionRow extends DataClass
    implements Insertable<BillingRuleVersionRow> {
  final String id;
  final String workspaceId;

  /// `credit_account` / `currency_account`。
  final String subjectKind;
  final String subjectId;
  final int statementDay;
  final bool statementDayInclusive;

  /// `fixed_day` / `days_after_statement`。
  final String dueKind;
  final int? dueDay;
  final int dueMonthOffset;
  final int? dueDays;

  /// `calendar` / `business`。
  final String dueDayKind;

  /// `none` / `next_business_day`。
  final String holidayRollover;

  /// 业务时区里的 `HH:MM`；空 = 不按时刻判断入账日。
  final String? cutoffTime;
  final int postingDelayMinDays;
  final int postingDelayMaxDays;

  /// `user_declared` / `official_template`。
  final String source;
  final String? effectiveFrom;
  final String? effectiveTo;
  final String? verifiedOn;
  final int version;

  /// 与服务端同一取值集合；工作空间私有规则不得为 `verified`/`published`（R2-13）。
  final String reviewStatus;
  final String? exceptions;
  final String createdAt;
  const BillingRuleVersionRow({
    required this.id,
    required this.workspaceId,
    required this.subjectKind,
    required this.subjectId,
    required this.statementDay,
    required this.statementDayInclusive,
    required this.dueKind,
    this.dueDay,
    required this.dueMonthOffset,
    this.dueDays,
    required this.dueDayKind,
    required this.holidayRollover,
    this.cutoffTime,
    required this.postingDelayMinDays,
    required this.postingDelayMaxDays,
    required this.source,
    this.effectiveFrom,
    this.effectiveTo,
    this.verifiedOn,
    required this.version,
    required this.reviewStatus,
    this.exceptions,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['subject_kind'] = Variable<String>(subjectKind);
    map['subject_id'] = Variable<String>(subjectId);
    map['statement_day'] = Variable<int>(statementDay);
    map['statement_day_inclusive'] = Variable<bool>(statementDayInclusive);
    map['due_kind'] = Variable<String>(dueKind);
    if (!nullToAbsent || dueDay != null) {
      map['due_day'] = Variable<int>(dueDay);
    }
    map['due_month_offset'] = Variable<int>(dueMonthOffset);
    if (!nullToAbsent || dueDays != null) {
      map['due_days'] = Variable<int>(dueDays);
    }
    map['due_day_kind'] = Variable<String>(dueDayKind);
    map['holiday_rollover'] = Variable<String>(holidayRollover);
    if (!nullToAbsent || cutoffTime != null) {
      map['cutoff_time'] = Variable<String>(cutoffTime);
    }
    map['posting_delay_min_days'] = Variable<int>(postingDelayMinDays);
    map['posting_delay_max_days'] = Variable<int>(postingDelayMaxDays);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || effectiveFrom != null) {
      map['effective_from'] = Variable<String>(effectiveFrom);
    }
    if (!nullToAbsent || effectiveTo != null) {
      map['effective_to'] = Variable<String>(effectiveTo);
    }
    if (!nullToAbsent || verifiedOn != null) {
      map['verified_on'] = Variable<String>(verifiedOn);
    }
    map['version'] = Variable<int>(version);
    map['review_status'] = Variable<String>(reviewStatus);
    if (!nullToAbsent || exceptions != null) {
      map['exceptions'] = Variable<String>(exceptions);
    }
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  BillingRuleVersionsCompanion toCompanion(bool nullToAbsent) {
    return BillingRuleVersionsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      subjectKind: Value(subjectKind),
      subjectId: Value(subjectId),
      statementDay: Value(statementDay),
      statementDayInclusive: Value(statementDayInclusive),
      dueKind: Value(dueKind),
      dueDay: dueDay == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDay),
      dueMonthOffset: Value(dueMonthOffset),
      dueDays: dueDays == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDays),
      dueDayKind: Value(dueDayKind),
      holidayRollover: Value(holidayRollover),
      cutoffTime: cutoffTime == null && nullToAbsent
          ? const Value.absent()
          : Value(cutoffTime),
      postingDelayMinDays: Value(postingDelayMinDays),
      postingDelayMaxDays: Value(postingDelayMaxDays),
      source: Value(source),
      effectiveFrom: effectiveFrom == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveFrom),
      effectiveTo: effectiveTo == null && nullToAbsent
          ? const Value.absent()
          : Value(effectiveTo),
      verifiedOn: verifiedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedOn),
      version: Value(version),
      reviewStatus: Value(reviewStatus),
      exceptions: exceptions == null && nullToAbsent
          ? const Value.absent()
          : Value(exceptions),
      createdAt: Value(createdAt),
    );
  }

  factory BillingRuleVersionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BillingRuleVersionRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      subjectKind: serializer.fromJson<String>(json['subjectKind']),
      subjectId: serializer.fromJson<String>(json['subjectId']),
      statementDay: serializer.fromJson<int>(json['statementDay']),
      statementDayInclusive: serializer.fromJson<bool>(
        json['statementDayInclusive'],
      ),
      dueKind: serializer.fromJson<String>(json['dueKind']),
      dueDay: serializer.fromJson<int?>(json['dueDay']),
      dueMonthOffset: serializer.fromJson<int>(json['dueMonthOffset']),
      dueDays: serializer.fromJson<int?>(json['dueDays']),
      dueDayKind: serializer.fromJson<String>(json['dueDayKind']),
      holidayRollover: serializer.fromJson<String>(json['holidayRollover']),
      cutoffTime: serializer.fromJson<String?>(json['cutoffTime']),
      postingDelayMinDays: serializer.fromJson<int>(
        json['postingDelayMinDays'],
      ),
      postingDelayMaxDays: serializer.fromJson<int>(
        json['postingDelayMaxDays'],
      ),
      source: serializer.fromJson<String>(json['source']),
      effectiveFrom: serializer.fromJson<String?>(json['effectiveFrom']),
      effectiveTo: serializer.fromJson<String?>(json['effectiveTo']),
      verifiedOn: serializer.fromJson<String?>(json['verifiedOn']),
      version: serializer.fromJson<int>(json['version']),
      reviewStatus: serializer.fromJson<String>(json['reviewStatus']),
      exceptions: serializer.fromJson<String?>(json['exceptions']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'subjectKind': serializer.toJson<String>(subjectKind),
      'subjectId': serializer.toJson<String>(subjectId),
      'statementDay': serializer.toJson<int>(statementDay),
      'statementDayInclusive': serializer.toJson<bool>(statementDayInclusive),
      'dueKind': serializer.toJson<String>(dueKind),
      'dueDay': serializer.toJson<int?>(dueDay),
      'dueMonthOffset': serializer.toJson<int>(dueMonthOffset),
      'dueDays': serializer.toJson<int?>(dueDays),
      'dueDayKind': serializer.toJson<String>(dueDayKind),
      'holidayRollover': serializer.toJson<String>(holidayRollover),
      'cutoffTime': serializer.toJson<String?>(cutoffTime),
      'postingDelayMinDays': serializer.toJson<int>(postingDelayMinDays),
      'postingDelayMaxDays': serializer.toJson<int>(postingDelayMaxDays),
      'source': serializer.toJson<String>(source),
      'effectiveFrom': serializer.toJson<String?>(effectiveFrom),
      'effectiveTo': serializer.toJson<String?>(effectiveTo),
      'verifiedOn': serializer.toJson<String?>(verifiedOn),
      'version': serializer.toJson<int>(version),
      'reviewStatus': serializer.toJson<String>(reviewStatus),
      'exceptions': serializer.toJson<String?>(exceptions),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  BillingRuleVersionRow copyWith({
    String? id,
    String? workspaceId,
    String? subjectKind,
    String? subjectId,
    int? statementDay,
    bool? statementDayInclusive,
    String? dueKind,
    Value<int?> dueDay = const Value.absent(),
    int? dueMonthOffset,
    Value<int?> dueDays = const Value.absent(),
    String? dueDayKind,
    String? holidayRollover,
    Value<String?> cutoffTime = const Value.absent(),
    int? postingDelayMinDays,
    int? postingDelayMaxDays,
    String? source,
    Value<String?> effectiveFrom = const Value.absent(),
    Value<String?> effectiveTo = const Value.absent(),
    Value<String?> verifiedOn = const Value.absent(),
    int? version,
    String? reviewStatus,
    Value<String?> exceptions = const Value.absent(),
    String? createdAt,
  }) => BillingRuleVersionRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    subjectKind: subjectKind ?? this.subjectKind,
    subjectId: subjectId ?? this.subjectId,
    statementDay: statementDay ?? this.statementDay,
    statementDayInclusive: statementDayInclusive ?? this.statementDayInclusive,
    dueKind: dueKind ?? this.dueKind,
    dueDay: dueDay.present ? dueDay.value : this.dueDay,
    dueMonthOffset: dueMonthOffset ?? this.dueMonthOffset,
    dueDays: dueDays.present ? dueDays.value : this.dueDays,
    dueDayKind: dueDayKind ?? this.dueDayKind,
    holidayRollover: holidayRollover ?? this.holidayRollover,
    cutoffTime: cutoffTime.present ? cutoffTime.value : this.cutoffTime,
    postingDelayMinDays: postingDelayMinDays ?? this.postingDelayMinDays,
    postingDelayMaxDays: postingDelayMaxDays ?? this.postingDelayMaxDays,
    source: source ?? this.source,
    effectiveFrom: effectiveFrom.present
        ? effectiveFrom.value
        : this.effectiveFrom,
    effectiveTo: effectiveTo.present ? effectiveTo.value : this.effectiveTo,
    verifiedOn: verifiedOn.present ? verifiedOn.value : this.verifiedOn,
    version: version ?? this.version,
    reviewStatus: reviewStatus ?? this.reviewStatus,
    exceptions: exceptions.present ? exceptions.value : this.exceptions,
    createdAt: createdAt ?? this.createdAt,
  );
  BillingRuleVersionRow copyWithCompanion(BillingRuleVersionsCompanion data) {
    return BillingRuleVersionRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      subjectKind: data.subjectKind.present
          ? data.subjectKind.value
          : this.subjectKind,
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      statementDay: data.statementDay.present
          ? data.statementDay.value
          : this.statementDay,
      statementDayInclusive: data.statementDayInclusive.present
          ? data.statementDayInclusive.value
          : this.statementDayInclusive,
      dueKind: data.dueKind.present ? data.dueKind.value : this.dueKind,
      dueDay: data.dueDay.present ? data.dueDay.value : this.dueDay,
      dueMonthOffset: data.dueMonthOffset.present
          ? data.dueMonthOffset.value
          : this.dueMonthOffset,
      dueDays: data.dueDays.present ? data.dueDays.value : this.dueDays,
      dueDayKind: data.dueDayKind.present
          ? data.dueDayKind.value
          : this.dueDayKind,
      holidayRollover: data.holidayRollover.present
          ? data.holidayRollover.value
          : this.holidayRollover,
      cutoffTime: data.cutoffTime.present
          ? data.cutoffTime.value
          : this.cutoffTime,
      postingDelayMinDays: data.postingDelayMinDays.present
          ? data.postingDelayMinDays.value
          : this.postingDelayMinDays,
      postingDelayMaxDays: data.postingDelayMaxDays.present
          ? data.postingDelayMaxDays.value
          : this.postingDelayMaxDays,
      source: data.source.present ? data.source.value : this.source,
      effectiveFrom: data.effectiveFrom.present
          ? data.effectiveFrom.value
          : this.effectiveFrom,
      effectiveTo: data.effectiveTo.present
          ? data.effectiveTo.value
          : this.effectiveTo,
      verifiedOn: data.verifiedOn.present
          ? data.verifiedOn.value
          : this.verifiedOn,
      version: data.version.present ? data.version.value : this.version,
      reviewStatus: data.reviewStatus.present
          ? data.reviewStatus.value
          : this.reviewStatus,
      exceptions: data.exceptions.present
          ? data.exceptions.value
          : this.exceptions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BillingRuleVersionRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('subjectKind: $subjectKind, ')
          ..write('subjectId: $subjectId, ')
          ..write('statementDay: $statementDay, ')
          ..write('statementDayInclusive: $statementDayInclusive, ')
          ..write('dueKind: $dueKind, ')
          ..write('dueDay: $dueDay, ')
          ..write('dueMonthOffset: $dueMonthOffset, ')
          ..write('dueDays: $dueDays, ')
          ..write('dueDayKind: $dueDayKind, ')
          ..write('holidayRollover: $holidayRollover, ')
          ..write('cutoffTime: $cutoffTime, ')
          ..write('postingDelayMinDays: $postingDelayMinDays, ')
          ..write('postingDelayMaxDays: $postingDelayMaxDays, ')
          ..write('source: $source, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('verifiedOn: $verifiedOn, ')
          ..write('version: $version, ')
          ..write('reviewStatus: $reviewStatus, ')
          ..write('exceptions: $exceptions, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workspaceId,
    subjectKind,
    subjectId,
    statementDay,
    statementDayInclusive,
    dueKind,
    dueDay,
    dueMonthOffset,
    dueDays,
    dueDayKind,
    holidayRollover,
    cutoffTime,
    postingDelayMinDays,
    postingDelayMaxDays,
    source,
    effectiveFrom,
    effectiveTo,
    verifiedOn,
    version,
    reviewStatus,
    exceptions,
    createdAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BillingRuleVersionRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.subjectKind == this.subjectKind &&
          other.subjectId == this.subjectId &&
          other.statementDay == this.statementDay &&
          other.statementDayInclusive == this.statementDayInclusive &&
          other.dueKind == this.dueKind &&
          other.dueDay == this.dueDay &&
          other.dueMonthOffset == this.dueMonthOffset &&
          other.dueDays == this.dueDays &&
          other.dueDayKind == this.dueDayKind &&
          other.holidayRollover == this.holidayRollover &&
          other.cutoffTime == this.cutoffTime &&
          other.postingDelayMinDays == this.postingDelayMinDays &&
          other.postingDelayMaxDays == this.postingDelayMaxDays &&
          other.source == this.source &&
          other.effectiveFrom == this.effectiveFrom &&
          other.effectiveTo == this.effectiveTo &&
          other.verifiedOn == this.verifiedOn &&
          other.version == this.version &&
          other.reviewStatus == this.reviewStatus &&
          other.exceptions == this.exceptions &&
          other.createdAt == this.createdAt);
}

class BillingRuleVersionsCompanion
    extends UpdateCompanion<BillingRuleVersionRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> subjectKind;
  final Value<String> subjectId;
  final Value<int> statementDay;
  final Value<bool> statementDayInclusive;
  final Value<String> dueKind;
  final Value<int?> dueDay;
  final Value<int> dueMonthOffset;
  final Value<int?> dueDays;
  final Value<String> dueDayKind;
  final Value<String> holidayRollover;
  final Value<String?> cutoffTime;
  final Value<int> postingDelayMinDays;
  final Value<int> postingDelayMaxDays;
  final Value<String> source;
  final Value<String?> effectiveFrom;
  final Value<String?> effectiveTo;
  final Value<String?> verifiedOn;
  final Value<int> version;
  final Value<String> reviewStatus;
  final Value<String?> exceptions;
  final Value<String> createdAt;
  final Value<int> rowid;
  const BillingRuleVersionsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.subjectKind = const Value.absent(),
    this.subjectId = const Value.absent(),
    this.statementDay = const Value.absent(),
    this.statementDayInclusive = const Value.absent(),
    this.dueKind = const Value.absent(),
    this.dueDay = const Value.absent(),
    this.dueMonthOffset = const Value.absent(),
    this.dueDays = const Value.absent(),
    this.dueDayKind = const Value.absent(),
    this.holidayRollover = const Value.absent(),
    this.cutoffTime = const Value.absent(),
    this.postingDelayMinDays = const Value.absent(),
    this.postingDelayMaxDays = const Value.absent(),
    this.source = const Value.absent(),
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.verifiedOn = const Value.absent(),
    this.version = const Value.absent(),
    this.reviewStatus = const Value.absent(),
    this.exceptions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BillingRuleVersionsCompanion.insert({
    required String id,
    required String workspaceId,
    required String subjectKind,
    required String subjectId,
    required int statementDay,
    this.statementDayInclusive = const Value.absent(),
    required String dueKind,
    this.dueDay = const Value.absent(),
    this.dueMonthOffset = const Value.absent(),
    this.dueDays = const Value.absent(),
    this.dueDayKind = const Value.absent(),
    this.holidayRollover = const Value.absent(),
    this.cutoffTime = const Value.absent(),
    this.postingDelayMinDays = const Value.absent(),
    this.postingDelayMaxDays = const Value.absent(),
    required String source,
    this.effectiveFrom = const Value.absent(),
    this.effectiveTo = const Value.absent(),
    this.verifiedOn = const Value.absent(),
    required int version,
    required String reviewStatus,
    this.exceptions = const Value.absent(),
    required String createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       subjectKind = Value(subjectKind),
       subjectId = Value(subjectId),
       statementDay = Value(statementDay),
       dueKind = Value(dueKind),
       source = Value(source),
       version = Value(version),
       reviewStatus = Value(reviewStatus),
       createdAt = Value(createdAt);
  static Insertable<BillingRuleVersionRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? subjectKind,
    Expression<String>? subjectId,
    Expression<int>? statementDay,
    Expression<bool>? statementDayInclusive,
    Expression<String>? dueKind,
    Expression<int>? dueDay,
    Expression<int>? dueMonthOffset,
    Expression<int>? dueDays,
    Expression<String>? dueDayKind,
    Expression<String>? holidayRollover,
    Expression<String>? cutoffTime,
    Expression<int>? postingDelayMinDays,
    Expression<int>? postingDelayMaxDays,
    Expression<String>? source,
    Expression<String>? effectiveFrom,
    Expression<String>? effectiveTo,
    Expression<String>? verifiedOn,
    Expression<int>? version,
    Expression<String>? reviewStatus,
    Expression<String>? exceptions,
    Expression<String>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (subjectKind != null) 'subject_kind': subjectKind,
      if (subjectId != null) 'subject_id': subjectId,
      if (statementDay != null) 'statement_day': statementDay,
      if (statementDayInclusive != null)
        'statement_day_inclusive': statementDayInclusive,
      if (dueKind != null) 'due_kind': dueKind,
      if (dueDay != null) 'due_day': dueDay,
      if (dueMonthOffset != null) 'due_month_offset': dueMonthOffset,
      if (dueDays != null) 'due_days': dueDays,
      if (dueDayKind != null) 'due_day_kind': dueDayKind,
      if (holidayRollover != null) 'holiday_rollover': holidayRollover,
      if (cutoffTime != null) 'cutoff_time': cutoffTime,
      if (postingDelayMinDays != null)
        'posting_delay_min_days': postingDelayMinDays,
      if (postingDelayMaxDays != null)
        'posting_delay_max_days': postingDelayMaxDays,
      if (source != null) 'source': source,
      if (effectiveFrom != null) 'effective_from': effectiveFrom,
      if (effectiveTo != null) 'effective_to': effectiveTo,
      if (verifiedOn != null) 'verified_on': verifiedOn,
      if (version != null) 'version': version,
      if (reviewStatus != null) 'review_status': reviewStatus,
      if (exceptions != null) 'exceptions': exceptions,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BillingRuleVersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? subjectKind,
    Value<String>? subjectId,
    Value<int>? statementDay,
    Value<bool>? statementDayInclusive,
    Value<String>? dueKind,
    Value<int?>? dueDay,
    Value<int>? dueMonthOffset,
    Value<int?>? dueDays,
    Value<String>? dueDayKind,
    Value<String>? holidayRollover,
    Value<String?>? cutoffTime,
    Value<int>? postingDelayMinDays,
    Value<int>? postingDelayMaxDays,
    Value<String>? source,
    Value<String?>? effectiveFrom,
    Value<String?>? effectiveTo,
    Value<String?>? verifiedOn,
    Value<int>? version,
    Value<String>? reviewStatus,
    Value<String?>? exceptions,
    Value<String>? createdAt,
    Value<int>? rowid,
  }) {
    return BillingRuleVersionsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      subjectKind: subjectKind ?? this.subjectKind,
      subjectId: subjectId ?? this.subjectId,
      statementDay: statementDay ?? this.statementDay,
      statementDayInclusive:
          statementDayInclusive ?? this.statementDayInclusive,
      dueKind: dueKind ?? this.dueKind,
      dueDay: dueDay ?? this.dueDay,
      dueMonthOffset: dueMonthOffset ?? this.dueMonthOffset,
      dueDays: dueDays ?? this.dueDays,
      dueDayKind: dueDayKind ?? this.dueDayKind,
      holidayRollover: holidayRollover ?? this.holidayRollover,
      cutoffTime: cutoffTime ?? this.cutoffTime,
      postingDelayMinDays: postingDelayMinDays ?? this.postingDelayMinDays,
      postingDelayMaxDays: postingDelayMaxDays ?? this.postingDelayMaxDays,
      source: source ?? this.source,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: effectiveTo ?? this.effectiveTo,
      verifiedOn: verifiedOn ?? this.verifiedOn,
      version: version ?? this.version,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      exceptions: exceptions ?? this.exceptions,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (subjectKind.present) {
      map['subject_kind'] = Variable<String>(subjectKind.value);
    }
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (statementDay.present) {
      map['statement_day'] = Variable<int>(statementDay.value);
    }
    if (statementDayInclusive.present) {
      map['statement_day_inclusive'] = Variable<bool>(
        statementDayInclusive.value,
      );
    }
    if (dueKind.present) {
      map['due_kind'] = Variable<String>(dueKind.value);
    }
    if (dueDay.present) {
      map['due_day'] = Variable<int>(dueDay.value);
    }
    if (dueMonthOffset.present) {
      map['due_month_offset'] = Variable<int>(dueMonthOffset.value);
    }
    if (dueDays.present) {
      map['due_days'] = Variable<int>(dueDays.value);
    }
    if (dueDayKind.present) {
      map['due_day_kind'] = Variable<String>(dueDayKind.value);
    }
    if (holidayRollover.present) {
      map['holiday_rollover'] = Variable<String>(holidayRollover.value);
    }
    if (cutoffTime.present) {
      map['cutoff_time'] = Variable<String>(cutoffTime.value);
    }
    if (postingDelayMinDays.present) {
      map['posting_delay_min_days'] = Variable<int>(postingDelayMinDays.value);
    }
    if (postingDelayMaxDays.present) {
      map['posting_delay_max_days'] = Variable<int>(postingDelayMaxDays.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (effectiveFrom.present) {
      map['effective_from'] = Variable<String>(effectiveFrom.value);
    }
    if (effectiveTo.present) {
      map['effective_to'] = Variable<String>(effectiveTo.value);
    }
    if (verifiedOn.present) {
      map['verified_on'] = Variable<String>(verifiedOn.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (reviewStatus.present) {
      map['review_status'] = Variable<String>(reviewStatus.value);
    }
    if (exceptions.present) {
      map['exceptions'] = Variable<String>(exceptions.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BillingRuleVersionsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('subjectKind: $subjectKind, ')
          ..write('subjectId: $subjectId, ')
          ..write('statementDay: $statementDay, ')
          ..write('statementDayInclusive: $statementDayInclusive, ')
          ..write('dueKind: $dueKind, ')
          ..write('dueDay: $dueDay, ')
          ..write('dueMonthOffset: $dueMonthOffset, ')
          ..write('dueDays: $dueDays, ')
          ..write('dueDayKind: $dueDayKind, ')
          ..write('holidayRollover: $holidayRollover, ')
          ..write('cutoffTime: $cutoffTime, ')
          ..write('postingDelayMinDays: $postingDelayMinDays, ')
          ..write('postingDelayMaxDays: $postingDelayMaxDays, ')
          ..write('source: $source, ')
          ..write('effectiveFrom: $effectiveFrom, ')
          ..write('effectiveTo: $effectiveTo, ')
          ..write('verifiedOn: $verifiedOn, ')
          ..write('version: $version, ')
          ..write('reviewStatus: $reviewStatus, ')
          ..write('exceptions: $exceptions, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LimitSnapshotsTable extends LimitSnapshots
    with TableInfo<$LimitSnapshotsTable, LimitSnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LimitSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _fixedMinorMeta = const VerificationMeta(
    'fixedMinor',
  );
  @override
  late final GeneratedColumn<int> fixedMinor = GeneratedColumn<int>(
    'fixed_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tempMinorMeta = const VerificationMeta(
    'tempMinor',
  );
  @override
  late final GeneratedColumn<int> tempMinor = GeneratedColumn<int>(
    'temp_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _tempExpiresOnMeta = const VerificationMeta(
    'tempExpiresOn',
  );
  @override
  late final GeneratedColumn<String> tempExpiresOn = GeneratedColumn<String>(
    'temp_expires_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _specialMinorMeta = const VerificationMeta(
    'specialMinor',
  );
  @override
  late final GeneratedColumn<int> specialMinor = GeneratedColumn<int>(
    'special_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _specialPurposeMeta = const VerificationMeta(
    'specialPurpose',
  );
  @override
  late final GeneratedColumn<String> specialPurpose = GeneratedColumn<String>(
    'special_purpose',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usedMinorMeta = const VerificationMeta(
    'usedMinor',
  );
  @override
  late final GeneratedColumn<int> usedMinor = GeneratedColumn<int>(
    'used_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _availableRawMinorMeta = const VerificationMeta(
    'availableRawMinor',
  );
  @override
  late final GeneratedColumn<int> availableRawMinor = GeneratedColumn<int>(
    'available_raw_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _holdsMinorMeta = const VerificationMeta(
    'holdsMinor',
  );
  @override
  late final GeneratedColumn<int> holdsMinor = GeneratedColumn<int>(
    'holds_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _includesHoldsMeta = const VerificationMeta(
    'includesHolds',
  );
  @override
  late final GeneratedColumn<bool> includesHolds = GeneratedColumn<bool>(
    'includes_holds',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("includes_holds" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceDocumentIdMeta = const VerificationMeta(
    'sourceDocumentId',
  );
  @override
  late final GeneratedColumn<String> sourceDocumentId = GeneratedColumn<String>(
    'source_document_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _balanceAsOfMeta = const VerificationMeta(
    'balanceAsOf',
  );
  @override
  late final GeneratedColumn<String> balanceAsOf = GeneratedColumn<String>(
    'balance_as_of',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<String> observedAt = GeneratedColumn<String>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<String> recordedAt = GeneratedColumn<String>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmationLevelMeta = const VerificationMeta(
    'confirmationLevel',
  );
  @override
  late final GeneratedColumn<String> confirmationLevel =
      GeneratedColumn<String>(
        'confirmation_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    currencyAccountId,
    fixedMinor,
    tempMinor,
    tempExpiresOn,
    specialMinor,
    specialPurpose,
    usedMinor,
    availableRawMinor,
    holdsMinor,
    includesHolds,
    sourceKind,
    sourceDocumentId,
    balanceAsOf,
    observedAt,
    recordedAt,
    confirmationLevel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'limit_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<LimitSnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('fixed_minor')) {
      context.handle(
        _fixedMinorMeta,
        fixedMinor.isAcceptableOrUnknown(data['fixed_minor']!, _fixedMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_fixedMinorMeta);
    }
    if (data.containsKey('temp_minor')) {
      context.handle(
        _tempMinorMeta,
        tempMinor.isAcceptableOrUnknown(data['temp_minor']!, _tempMinorMeta),
      );
    }
    if (data.containsKey('temp_expires_on')) {
      context.handle(
        _tempExpiresOnMeta,
        tempExpiresOn.isAcceptableOrUnknown(
          data['temp_expires_on']!,
          _tempExpiresOnMeta,
        ),
      );
    }
    if (data.containsKey('special_minor')) {
      context.handle(
        _specialMinorMeta,
        specialMinor.isAcceptableOrUnknown(
          data['special_minor']!,
          _specialMinorMeta,
        ),
      );
    }
    if (data.containsKey('special_purpose')) {
      context.handle(
        _specialPurposeMeta,
        specialPurpose.isAcceptableOrUnknown(
          data['special_purpose']!,
          _specialPurposeMeta,
        ),
      );
    }
    if (data.containsKey('used_minor')) {
      context.handle(
        _usedMinorMeta,
        usedMinor.isAcceptableOrUnknown(data['used_minor']!, _usedMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_usedMinorMeta);
    }
    if (data.containsKey('available_raw_minor')) {
      context.handle(
        _availableRawMinorMeta,
        availableRawMinor.isAcceptableOrUnknown(
          data['available_raw_minor']!,
          _availableRawMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_availableRawMinorMeta);
    }
    if (data.containsKey('holds_minor')) {
      context.handle(
        _holdsMinorMeta,
        holdsMinor.isAcceptableOrUnknown(data['holds_minor']!, _holdsMinorMeta),
      );
    }
    if (data.containsKey('includes_holds')) {
      context.handle(
        _includesHoldsMeta,
        includesHolds.isAcceptableOrUnknown(
          data['includes_holds']!,
          _includesHoldsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_includesHoldsMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_document_id')) {
      context.handle(
        _sourceDocumentIdMeta,
        sourceDocumentId.isAcceptableOrUnknown(
          data['source_document_id']!,
          _sourceDocumentIdMeta,
        ),
      );
    }
    if (data.containsKey('balance_as_of')) {
      context.handle(
        _balanceAsOfMeta,
        balanceAsOf.isAcceptableOrUnknown(
          data['balance_as_of']!,
          _balanceAsOfMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balanceAsOfMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('confirmation_level')) {
      context.handle(
        _confirmationLevelMeta,
        confirmationLevel.isAcceptableOrUnknown(
          data['confirmation_level']!,
          _confirmationLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmationLevelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
  ];
  @override
  LimitSnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LimitSnapshotRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      fixedMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fixed_minor'],
      )!,
      tempMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}temp_minor'],
      )!,
      tempExpiresOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temp_expires_on'],
      ),
      specialMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}special_minor'],
      )!,
      specialPurpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}special_purpose'],
      ),
      usedMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}used_minor'],
      )!,
      availableRawMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}available_raw_minor'],
      )!,
      holdsMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}holds_minor'],
      )!,
      includesHolds: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}includes_holds'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceDocumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_document_id'],
      ),
      balanceAsOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}balance_as_of'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observed_at'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_at'],
      )!,
      confirmationLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confirmation_level'],
      )!,
    );
  }

  @override
  $LimitSnapshotsTable createAlias(String alias) {
    return $LimitSnapshotsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class LimitSnapshotRow extends DataClass
    implements Insertable<LimitSnapshotRow> {
  final String id;
  final String workspaceId;
  final String currencyAccountId;
  final int fixedMinor;
  final int tempMinor;
  final String? tempExpiresOn;
  final int specialMinor;
  final String? specialPurpose;
  final int usedMinor;

  /// 银行显示的可用额度原值，可为负（超限原值保留，F-26）。
  final int availableRawMinor;
  final int holdsMinor;
  final bool includesHolds;

  /// `bank_app` / `statement` / `user` / `import`。
  final String sourceKind;
  final String? sourceDocumentId;

  /// 实际余额时点（RFC 3339）。
  final String balanceAsOf;
  final String observedAt;
  final String recordedAt;

  /// `system_estimated` / `user_confirmed` / `bank_confirmed`。
  final String confirmationLevel;
  const LimitSnapshotRow({
    required this.id,
    required this.workspaceId,
    required this.currencyAccountId,
    required this.fixedMinor,
    required this.tempMinor,
    this.tempExpiresOn,
    required this.specialMinor,
    this.specialPurpose,
    required this.usedMinor,
    required this.availableRawMinor,
    required this.holdsMinor,
    required this.includesHolds,
    required this.sourceKind,
    this.sourceDocumentId,
    required this.balanceAsOf,
    required this.observedAt,
    required this.recordedAt,
    required this.confirmationLevel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    map['fixed_minor'] = Variable<int>(fixedMinor);
    map['temp_minor'] = Variable<int>(tempMinor);
    if (!nullToAbsent || tempExpiresOn != null) {
      map['temp_expires_on'] = Variable<String>(tempExpiresOn);
    }
    map['special_minor'] = Variable<int>(specialMinor);
    if (!nullToAbsent || specialPurpose != null) {
      map['special_purpose'] = Variable<String>(specialPurpose);
    }
    map['used_minor'] = Variable<int>(usedMinor);
    map['available_raw_minor'] = Variable<int>(availableRawMinor);
    map['holds_minor'] = Variable<int>(holdsMinor);
    map['includes_holds'] = Variable<bool>(includesHolds);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || sourceDocumentId != null) {
      map['source_document_id'] = Variable<String>(sourceDocumentId);
    }
    map['balance_as_of'] = Variable<String>(balanceAsOf);
    map['observed_at'] = Variable<String>(observedAt);
    map['recorded_at'] = Variable<String>(recordedAt);
    map['confirmation_level'] = Variable<String>(confirmationLevel);
    return map;
  }

  LimitSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return LimitSnapshotsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      fixedMinor: Value(fixedMinor),
      tempMinor: Value(tempMinor),
      tempExpiresOn: tempExpiresOn == null && nullToAbsent
          ? const Value.absent()
          : Value(tempExpiresOn),
      specialMinor: Value(specialMinor),
      specialPurpose: specialPurpose == null && nullToAbsent
          ? const Value.absent()
          : Value(specialPurpose),
      usedMinor: Value(usedMinor),
      availableRawMinor: Value(availableRawMinor),
      holdsMinor: Value(holdsMinor),
      includesHolds: Value(includesHolds),
      sourceKind: Value(sourceKind),
      sourceDocumentId: sourceDocumentId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDocumentId),
      balanceAsOf: Value(balanceAsOf),
      observedAt: Value(observedAt),
      recordedAt: Value(recordedAt),
      confirmationLevel: Value(confirmationLevel),
    );
  }

  factory LimitSnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LimitSnapshotRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      fixedMinor: serializer.fromJson<int>(json['fixedMinor']),
      tempMinor: serializer.fromJson<int>(json['tempMinor']),
      tempExpiresOn: serializer.fromJson<String?>(json['tempExpiresOn']),
      specialMinor: serializer.fromJson<int>(json['specialMinor']),
      specialPurpose: serializer.fromJson<String?>(json['specialPurpose']),
      usedMinor: serializer.fromJson<int>(json['usedMinor']),
      availableRawMinor: serializer.fromJson<int>(json['availableRawMinor']),
      holdsMinor: serializer.fromJson<int>(json['holdsMinor']),
      includesHolds: serializer.fromJson<bool>(json['includesHolds']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceDocumentId: serializer.fromJson<String?>(json['sourceDocumentId']),
      balanceAsOf: serializer.fromJson<String>(json['balanceAsOf']),
      observedAt: serializer.fromJson<String>(json['observedAt']),
      recordedAt: serializer.fromJson<String>(json['recordedAt']),
      confirmationLevel: serializer.fromJson<String>(json['confirmationLevel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'fixedMinor': serializer.toJson<int>(fixedMinor),
      'tempMinor': serializer.toJson<int>(tempMinor),
      'tempExpiresOn': serializer.toJson<String?>(tempExpiresOn),
      'specialMinor': serializer.toJson<int>(specialMinor),
      'specialPurpose': serializer.toJson<String?>(specialPurpose),
      'usedMinor': serializer.toJson<int>(usedMinor),
      'availableRawMinor': serializer.toJson<int>(availableRawMinor),
      'holdsMinor': serializer.toJson<int>(holdsMinor),
      'includesHolds': serializer.toJson<bool>(includesHolds),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceDocumentId': serializer.toJson<String?>(sourceDocumentId),
      'balanceAsOf': serializer.toJson<String>(balanceAsOf),
      'observedAt': serializer.toJson<String>(observedAt),
      'recordedAt': serializer.toJson<String>(recordedAt),
      'confirmationLevel': serializer.toJson<String>(confirmationLevel),
    };
  }

  LimitSnapshotRow copyWith({
    String? id,
    String? workspaceId,
    String? currencyAccountId,
    int? fixedMinor,
    int? tempMinor,
    Value<String?> tempExpiresOn = const Value.absent(),
    int? specialMinor,
    Value<String?> specialPurpose = const Value.absent(),
    int? usedMinor,
    int? availableRawMinor,
    int? holdsMinor,
    bool? includesHolds,
    String? sourceKind,
    Value<String?> sourceDocumentId = const Value.absent(),
    String? balanceAsOf,
    String? observedAt,
    String? recordedAt,
    String? confirmationLevel,
  }) => LimitSnapshotRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    fixedMinor: fixedMinor ?? this.fixedMinor,
    tempMinor: tempMinor ?? this.tempMinor,
    tempExpiresOn: tempExpiresOn.present
        ? tempExpiresOn.value
        : this.tempExpiresOn,
    specialMinor: specialMinor ?? this.specialMinor,
    specialPurpose: specialPurpose.present
        ? specialPurpose.value
        : this.specialPurpose,
    usedMinor: usedMinor ?? this.usedMinor,
    availableRawMinor: availableRawMinor ?? this.availableRawMinor,
    holdsMinor: holdsMinor ?? this.holdsMinor,
    includesHolds: includesHolds ?? this.includesHolds,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceDocumentId: sourceDocumentId.present
        ? sourceDocumentId.value
        : this.sourceDocumentId,
    balanceAsOf: balanceAsOf ?? this.balanceAsOf,
    observedAt: observedAt ?? this.observedAt,
    recordedAt: recordedAt ?? this.recordedAt,
    confirmationLevel: confirmationLevel ?? this.confirmationLevel,
  );
  LimitSnapshotRow copyWithCompanion(LimitSnapshotsCompanion data) {
    return LimitSnapshotRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      fixedMinor: data.fixedMinor.present
          ? data.fixedMinor.value
          : this.fixedMinor,
      tempMinor: data.tempMinor.present ? data.tempMinor.value : this.tempMinor,
      tempExpiresOn: data.tempExpiresOn.present
          ? data.tempExpiresOn.value
          : this.tempExpiresOn,
      specialMinor: data.specialMinor.present
          ? data.specialMinor.value
          : this.specialMinor,
      specialPurpose: data.specialPurpose.present
          ? data.specialPurpose.value
          : this.specialPurpose,
      usedMinor: data.usedMinor.present ? data.usedMinor.value : this.usedMinor,
      availableRawMinor: data.availableRawMinor.present
          ? data.availableRawMinor.value
          : this.availableRawMinor,
      holdsMinor: data.holdsMinor.present
          ? data.holdsMinor.value
          : this.holdsMinor,
      includesHolds: data.includesHolds.present
          ? data.includesHolds.value
          : this.includesHolds,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceDocumentId: data.sourceDocumentId.present
          ? data.sourceDocumentId.value
          : this.sourceDocumentId,
      balanceAsOf: data.balanceAsOf.present
          ? data.balanceAsOf.value
          : this.balanceAsOf,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      confirmationLevel: data.confirmationLevel.present
          ? data.confirmationLevel.value
          : this.confirmationLevel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LimitSnapshotRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('fixedMinor: $fixedMinor, ')
          ..write('tempMinor: $tempMinor, ')
          ..write('tempExpiresOn: $tempExpiresOn, ')
          ..write('specialMinor: $specialMinor, ')
          ..write('specialPurpose: $specialPurpose, ')
          ..write('usedMinor: $usedMinor, ')
          ..write('availableRawMinor: $availableRawMinor, ')
          ..write('holdsMinor: $holdsMinor, ')
          ..write('includesHolds: $includesHolds, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceDocumentId: $sourceDocumentId, ')
          ..write('balanceAsOf: $balanceAsOf, ')
          ..write('observedAt: $observedAt, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('confirmationLevel: $confirmationLevel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    currencyAccountId,
    fixedMinor,
    tempMinor,
    tempExpiresOn,
    specialMinor,
    specialPurpose,
    usedMinor,
    availableRawMinor,
    holdsMinor,
    includesHolds,
    sourceKind,
    sourceDocumentId,
    balanceAsOf,
    observedAt,
    recordedAt,
    confirmationLevel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LimitSnapshotRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.fixedMinor == this.fixedMinor &&
          other.tempMinor == this.tempMinor &&
          other.tempExpiresOn == this.tempExpiresOn &&
          other.specialMinor == this.specialMinor &&
          other.specialPurpose == this.specialPurpose &&
          other.usedMinor == this.usedMinor &&
          other.availableRawMinor == this.availableRawMinor &&
          other.holdsMinor == this.holdsMinor &&
          other.includesHolds == this.includesHolds &&
          other.sourceKind == this.sourceKind &&
          other.sourceDocumentId == this.sourceDocumentId &&
          other.balanceAsOf == this.balanceAsOf &&
          other.observedAt == this.observedAt &&
          other.recordedAt == this.recordedAt &&
          other.confirmationLevel == this.confirmationLevel);
}

class LimitSnapshotsCompanion extends UpdateCompanion<LimitSnapshotRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<int> fixedMinor;
  final Value<int> tempMinor;
  final Value<String?> tempExpiresOn;
  final Value<int> specialMinor;
  final Value<String?> specialPurpose;
  final Value<int> usedMinor;
  final Value<int> availableRawMinor;
  final Value<int> holdsMinor;
  final Value<bool> includesHolds;
  final Value<String> sourceKind;
  final Value<String?> sourceDocumentId;
  final Value<String> balanceAsOf;
  final Value<String> observedAt;
  final Value<String> recordedAt;
  final Value<String> confirmationLevel;
  final Value<int> rowid;
  const LimitSnapshotsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.fixedMinor = const Value.absent(),
    this.tempMinor = const Value.absent(),
    this.tempExpiresOn = const Value.absent(),
    this.specialMinor = const Value.absent(),
    this.specialPurpose = const Value.absent(),
    this.usedMinor = const Value.absent(),
    this.availableRawMinor = const Value.absent(),
    this.holdsMinor = const Value.absent(),
    this.includesHolds = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceDocumentId = const Value.absent(),
    this.balanceAsOf = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.confirmationLevel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LimitSnapshotsCompanion.insert({
    required String id,
    required String workspaceId,
    required String currencyAccountId,
    required int fixedMinor,
    this.tempMinor = const Value.absent(),
    this.tempExpiresOn = const Value.absent(),
    this.specialMinor = const Value.absent(),
    this.specialPurpose = const Value.absent(),
    required int usedMinor,
    required int availableRawMinor,
    this.holdsMinor = const Value.absent(),
    required bool includesHolds,
    required String sourceKind,
    this.sourceDocumentId = const Value.absent(),
    required String balanceAsOf,
    required String observedAt,
    required String recordedAt,
    required String confirmationLevel,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       fixedMinor = Value(fixedMinor),
       usedMinor = Value(usedMinor),
       availableRawMinor = Value(availableRawMinor),
       includesHolds = Value(includesHolds),
       sourceKind = Value(sourceKind),
       balanceAsOf = Value(balanceAsOf),
       observedAt = Value(observedAt),
       recordedAt = Value(recordedAt),
       confirmationLevel = Value(confirmationLevel);
  static Insertable<LimitSnapshotRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<int>? fixedMinor,
    Expression<int>? tempMinor,
    Expression<String>? tempExpiresOn,
    Expression<int>? specialMinor,
    Expression<String>? specialPurpose,
    Expression<int>? usedMinor,
    Expression<int>? availableRawMinor,
    Expression<int>? holdsMinor,
    Expression<bool>? includesHolds,
    Expression<String>? sourceKind,
    Expression<String>? sourceDocumentId,
    Expression<String>? balanceAsOf,
    Expression<String>? observedAt,
    Expression<String>? recordedAt,
    Expression<String>? confirmationLevel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (fixedMinor != null) 'fixed_minor': fixedMinor,
      if (tempMinor != null) 'temp_minor': tempMinor,
      if (tempExpiresOn != null) 'temp_expires_on': tempExpiresOn,
      if (specialMinor != null) 'special_minor': specialMinor,
      if (specialPurpose != null) 'special_purpose': specialPurpose,
      if (usedMinor != null) 'used_minor': usedMinor,
      if (availableRawMinor != null) 'available_raw_minor': availableRawMinor,
      if (holdsMinor != null) 'holds_minor': holdsMinor,
      if (includesHolds != null) 'includes_holds': includesHolds,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
      if (balanceAsOf != null) 'balance_as_of': balanceAsOf,
      if (observedAt != null) 'observed_at': observedAt,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (confirmationLevel != null) 'confirmation_level': confirmationLevel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LimitSnapshotsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<int>? fixedMinor,
    Value<int>? tempMinor,
    Value<String?>? tempExpiresOn,
    Value<int>? specialMinor,
    Value<String?>? specialPurpose,
    Value<int>? usedMinor,
    Value<int>? availableRawMinor,
    Value<int>? holdsMinor,
    Value<bool>? includesHolds,
    Value<String>? sourceKind,
    Value<String?>? sourceDocumentId,
    Value<String>? balanceAsOf,
    Value<String>? observedAt,
    Value<String>? recordedAt,
    Value<String>? confirmationLevel,
    Value<int>? rowid,
  }) {
    return LimitSnapshotsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      fixedMinor: fixedMinor ?? this.fixedMinor,
      tempMinor: tempMinor ?? this.tempMinor,
      tempExpiresOn: tempExpiresOn ?? this.tempExpiresOn,
      specialMinor: specialMinor ?? this.specialMinor,
      specialPurpose: specialPurpose ?? this.specialPurpose,
      usedMinor: usedMinor ?? this.usedMinor,
      availableRawMinor: availableRawMinor ?? this.availableRawMinor,
      holdsMinor: holdsMinor ?? this.holdsMinor,
      includesHolds: includesHolds ?? this.includesHolds,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      balanceAsOf: balanceAsOf ?? this.balanceAsOf,
      observedAt: observedAt ?? this.observedAt,
      recordedAt: recordedAt ?? this.recordedAt,
      confirmationLevel: confirmationLevel ?? this.confirmationLevel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (fixedMinor.present) {
      map['fixed_minor'] = Variable<int>(fixedMinor.value);
    }
    if (tempMinor.present) {
      map['temp_minor'] = Variable<int>(tempMinor.value);
    }
    if (tempExpiresOn.present) {
      map['temp_expires_on'] = Variable<String>(tempExpiresOn.value);
    }
    if (specialMinor.present) {
      map['special_minor'] = Variable<int>(specialMinor.value);
    }
    if (specialPurpose.present) {
      map['special_purpose'] = Variable<String>(specialPurpose.value);
    }
    if (usedMinor.present) {
      map['used_minor'] = Variable<int>(usedMinor.value);
    }
    if (availableRawMinor.present) {
      map['available_raw_minor'] = Variable<int>(availableRawMinor.value);
    }
    if (holdsMinor.present) {
      map['holds_minor'] = Variable<int>(holdsMinor.value);
    }
    if (includesHolds.present) {
      map['includes_holds'] = Variable<bool>(includesHolds.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceDocumentId.present) {
      map['source_document_id'] = Variable<String>(sourceDocumentId.value);
    }
    if (balanceAsOf.present) {
      map['balance_as_of'] = Variable<String>(balanceAsOf.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<String>(observedAt.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<String>(recordedAt.value);
    }
    if (confirmationLevel.present) {
      map['confirmation_level'] = Variable<String>(confirmationLevel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LimitSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('fixedMinor: $fixedMinor, ')
          ..write('tempMinor: $tempMinor, ')
          ..write('tempExpiresOn: $tempExpiresOn, ')
          ..write('specialMinor: $specialMinor, ')
          ..write('specialPurpose: $specialPurpose, ')
          ..write('usedMinor: $usedMinor, ')
          ..write('availableRawMinor: $availableRawMinor, ')
          ..write('holdsMinor: $holdsMinor, ')
          ..write('includesHolds: $includesHolds, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceDocumentId: $sourceDocumentId, ')
          ..write('balanceAsOf: $balanceAsOf, ')
          ..write('observedAt: $observedAt, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('confirmationLevel: $confirmationLevel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CashAccountsTable extends CashAccounts
    with TableInfo<$CashAccountsTable, CashAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usableForRepaymentMeta =
      const VerificationMeta('usableForRepayment');
  @override
  late final GeneratedColumn<bool> usableForRepayment = GeneratedColumn<bool>(
    'usable_for_repayment',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("usable_for_repayment" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _availableFromMeta = const VerificationMeta(
    'availableFrom',
  );
  @override
  late final GeneratedColumn<String> availableFrom = GeneratedColumn<String>(
    'available_from',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reserveFloorMinorMeta = const VerificationMeta(
    'reserveFloorMinor',
  );
  @override
  late final GeneratedColumn<int> reserveFloorMinor = GeneratedColumn<int>(
    'reserve_floor_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    currency,
    kind,
    usableForRepayment,
    availableFrom,
    reserveFloorMinor,
    status,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CashAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('usable_for_repayment')) {
      context.handle(
        _usableForRepaymentMeta,
        usableForRepayment.isAcceptableOrUnknown(
          data['usable_for_repayment']!,
          _usableForRepaymentMeta,
        ),
      );
    }
    if (data.containsKey('available_from')) {
      context.handle(
        _availableFromMeta,
        availableFrom.isAcceptableOrUnknown(
          data['available_from']!,
          _availableFromMeta,
        ),
      );
    }
    if (data.containsKey('reserve_floor_minor')) {
      context.handle(
        _reserveFloorMinorMeta,
        reserveFloorMinor.isAcceptableOrUnknown(
          data['reserve_floor_minor']!,
          _reserveFloorMinorMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
  ];
  @override
  CashAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      usableForRepayment: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}usable_for_repayment'],
      )!,
      availableFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}available_from'],
      ),
      reserveFloorMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reserve_floor_minor'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CashAccountsTable createAlias(String alias) {
    return $CashAccountsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CashAccountRow extends DataClass implements Insertable<CashAccountRow> {
  final String id;
  final String workspaceId;
  final String name;
  final String currency;

  /// `bank` / `wallet` / `wealth` / `restricted`。
  final String kind;
  final bool usableForRepayment;

  /// 理财/受限资金可用于还款的起始日（`YYYY-MM-DD`）；空 = 未设置。
  final String? availableFrom;

  /// 用户最低储备（硬约束，≥0）。
  final int reserveFloorMinor;

  /// `active` / `closed`（已停用：不进入资金日历，历史保留）。
  final String status;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  const CashAccountRow({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.currency,
    required this.kind,
    required this.usableForRepayment,
    this.availableFrom,
    required this.reserveFloorMinor,
    required this.status,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    map['kind'] = Variable<String>(kind);
    map['usable_for_repayment'] = Variable<bool>(usableForRepayment);
    if (!nullToAbsent || availableFrom != null) {
      map['available_from'] = Variable<String>(availableFrom);
    }
    map['reserve_floor_minor'] = Variable<int>(reserveFloorMinor);
    map['status'] = Variable<String>(status);
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  CashAccountsCompanion toCompanion(bool nullToAbsent) {
    return CashAccountsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      currency: Value(currency),
      kind: Value(kind),
      usableForRepayment: Value(usableForRepayment),
      availableFrom: availableFrom == null && nullToAbsent
          ? const Value.absent()
          : Value(availableFrom),
      reserveFloorMinor: Value(reserveFloorMinor),
      status: Value(status),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CashAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashAccountRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      kind: serializer.fromJson<String>(json['kind']),
      usableForRepayment: serializer.fromJson<bool>(json['usableForRepayment']),
      availableFrom: serializer.fromJson<String?>(json['availableFrom']),
      reserveFloorMinor: serializer.fromJson<int>(json['reserveFloorMinor']),
      status: serializer.fromJson<String>(json['status']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'kind': serializer.toJson<String>(kind),
      'usableForRepayment': serializer.toJson<bool>(usableForRepayment),
      'availableFrom': serializer.toJson<String?>(availableFrom),
      'reserveFloorMinor': serializer.toJson<int>(reserveFloorMinor),
      'status': serializer.toJson<String>(status),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  CashAccountRow copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? currency,
    String? kind,
    bool? usableForRepayment,
    Value<String?> availableFrom = const Value.absent(),
    int? reserveFloorMinor,
    String? status,
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => CashAccountRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    kind: kind ?? this.kind,
    usableForRepayment: usableForRepayment ?? this.usableForRepayment,
    availableFrom: availableFrom.present
        ? availableFrom.value
        : this.availableFrom,
    reserveFloorMinor: reserveFloorMinor ?? this.reserveFloorMinor,
    status: status ?? this.status,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CashAccountRow copyWithCompanion(CashAccountsCompanion data) {
    return CashAccountRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      kind: data.kind.present ? data.kind.value : this.kind,
      usableForRepayment: data.usableForRepayment.present
          ? data.usableForRepayment.value
          : this.usableForRepayment,
      availableFrom: data.availableFrom.present
          ? data.availableFrom.value
          : this.availableFrom,
      reserveFloorMinor: data.reserveFloorMinor.present
          ? data.reserveFloorMinor.value
          : this.reserveFloorMinor,
      status: data.status.present ? data.status.value : this.status,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashAccountRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('kind: $kind, ')
          ..write('usableForRepayment: $usableForRepayment, ')
          ..write('availableFrom: $availableFrom, ')
          ..write('reserveFloorMinor: $reserveFloorMinor, ')
          ..write('status: $status, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    currency,
    kind,
    usableForRepayment,
    availableFrom,
    reserveFloorMinor,
    status,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashAccountRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.kind == this.kind &&
          other.usableForRepayment == this.usableForRepayment &&
          other.availableFrom == this.availableFrom &&
          other.reserveFloorMinor == this.reserveFloorMinor &&
          other.status == this.status &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CashAccountsCompanion extends UpdateCompanion<CashAccountRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String> currency;
  final Value<String> kind;
  final Value<bool> usableForRepayment;
  final Value<String?> availableFrom;
  final Value<int> reserveFloorMinor;
  final Value<String> status;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const CashAccountsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.kind = const Value.absent(),
    this.usableForRepayment = const Value.absent(),
    this.availableFrom = const Value.absent(),
    this.reserveFloorMinor = const Value.absent(),
    this.status = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CashAccountsCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    required String currency,
    required String kind,
    this.usableForRepayment = const Value.absent(),
    this.availableFrom = const Value.absent(),
    this.reserveFloorMinor = const Value.absent(),
    this.status = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       currency = Value(currency),
       kind = Value(kind),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CashAccountRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<String>? kind,
    Expression<bool>? usableForRepayment,
    Expression<String>? availableFrom,
    Expression<int>? reserveFloorMinor,
    Expression<String>? status,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (kind != null) 'kind': kind,
      if (usableForRepayment != null)
        'usable_for_repayment': usableForRepayment,
      if (availableFrom != null) 'available_from': availableFrom,
      if (reserveFloorMinor != null) 'reserve_floor_minor': reserveFloorMinor,
      if (status != null) 'status': status,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CashAccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String>? currency,
    Value<String>? kind,
    Value<bool>? usableForRepayment,
    Value<String?>? availableFrom,
    Value<int>? reserveFloorMinor,
    Value<String>? status,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CashAccountsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      kind: kind ?? this.kind,
      usableForRepayment: usableForRepayment ?? this.usableForRepayment,
      availableFrom: availableFrom ?? this.availableFrom,
      reserveFloorMinor: reserveFloorMinor ?? this.reserveFloorMinor,
      status: status ?? this.status,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (usableForRepayment.present) {
      map['usable_for_repayment'] = Variable<bool>(usableForRepayment.value);
    }
    if (availableFrom.present) {
      map['available_from'] = Variable<String>(availableFrom.value);
    }
    if (reserveFloorMinor.present) {
      map['reserve_floor_minor'] = Variable<int>(reserveFloorMinor.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashAccountsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('kind: $kind, ')
          ..write('usableForRepayment: $usableForRepayment, ')
          ..write('availableFrom: $availableFrom, ')
          ..write('reserveFloorMinor: $reserveFloorMinor, ')
          ..write('status: $status, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CashBalanceSnapshotsTable extends CashBalanceSnapshots
    with TableInfo<$CashBalanceSnapshotsTable, CashSnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashBalanceSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashAccountIdMeta = const VerificationMeta(
    'cashAccountId',
  );
  @override
  late final GeneratedColumn<String> cashAccountId = GeneratedColumn<String>(
    'cash_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balanceMinorMeta = const VerificationMeta(
    'balanceMinor',
  );
  @override
  late final GeneratedColumn<int> balanceMinor = GeneratedColumn<int>(
    'balance_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _balanceAsOfMeta = const VerificationMeta(
    'balanceAsOf',
  );
  @override
  late final GeneratedColumn<String> balanceAsOf = GeneratedColumn<String>(
    'balance_as_of',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<String> observedAt = GeneratedColumn<String>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmationLevelMeta = const VerificationMeta(
    'confirmationLevel',
  );
  @override
  late final GeneratedColumn<String> confirmationLevel =
      GeneratedColumn<String>(
        'confirmation_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<String> recordedAt = GeneratedColumn<String>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    cashAccountId,
    balanceMinor,
    balanceAsOf,
    observedAt,
    sourceKind,
    confirmationLevel,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_balance_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CashSnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('cash_account_id')) {
      context.handle(
        _cashAccountIdMeta,
        cashAccountId.isAcceptableOrUnknown(
          data['cash_account_id']!,
          _cashAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cashAccountIdMeta);
    }
    if (data.containsKey('balance_minor')) {
      context.handle(
        _balanceMinorMeta,
        balanceMinor.isAcceptableOrUnknown(
          data['balance_minor']!,
          _balanceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balanceMinorMeta);
    }
    if (data.containsKey('balance_as_of')) {
      context.handle(
        _balanceAsOfMeta,
        balanceAsOf.isAcceptableOrUnknown(
          data['balance_as_of']!,
          _balanceAsOfMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_balanceAsOfMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('confirmation_level')) {
      context.handle(
        _confirmationLevelMeta,
        confirmationLevel.isAcceptableOrUnknown(
          data['confirmation_level']!,
          _confirmationLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmationLevelMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];
  @override
  CashSnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashSnapshotRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      cashAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_account_id'],
      )!,
      balanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_minor'],
      )!,
      balanceAsOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}balance_as_of'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observed_at'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      confirmationLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confirmation_level'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $CashBalanceSnapshotsTable createAlias(String alias) {
    return $CashBalanceSnapshotsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CashSnapshotRow extends DataClass implements Insertable<CashSnapshotRow> {
  final String id;
  final String workspaceId;
  final String cashAccountId;

  /// 余额（最小单位，可为负：透支）。
  final int balanceMinor;

  /// `YYYY-MM-DD`。
  final String balanceAsOf;

  /// RFC 3339。
  final String observedAt;

  /// `bank_app` / `statement` / `user` / `import`。
  final String sourceKind;

  /// `system_estimated` / `user_confirmed` / `bank_confirmed`。
  final String confirmationLevel;
  final String recordedAt;
  const CashSnapshotRow({
    required this.id,
    required this.workspaceId,
    required this.cashAccountId,
    required this.balanceMinor,
    required this.balanceAsOf,
    required this.observedAt,
    required this.sourceKind,
    required this.confirmationLevel,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['cash_account_id'] = Variable<String>(cashAccountId);
    map['balance_minor'] = Variable<int>(balanceMinor);
    map['balance_as_of'] = Variable<String>(balanceAsOf);
    map['observed_at'] = Variable<String>(observedAt);
    map['source_kind'] = Variable<String>(sourceKind);
    map['confirmation_level'] = Variable<String>(confirmationLevel);
    map['recorded_at'] = Variable<String>(recordedAt);
    return map;
  }

  CashBalanceSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return CashBalanceSnapshotsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      cashAccountId: Value(cashAccountId),
      balanceMinor: Value(balanceMinor),
      balanceAsOf: Value(balanceAsOf),
      observedAt: Value(observedAt),
      sourceKind: Value(sourceKind),
      confirmationLevel: Value(confirmationLevel),
      recordedAt: Value(recordedAt),
    );
  }

  factory CashSnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashSnapshotRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      cashAccountId: serializer.fromJson<String>(json['cashAccountId']),
      balanceMinor: serializer.fromJson<int>(json['balanceMinor']),
      balanceAsOf: serializer.fromJson<String>(json['balanceAsOf']),
      observedAt: serializer.fromJson<String>(json['observedAt']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      confirmationLevel: serializer.fromJson<String>(json['confirmationLevel']),
      recordedAt: serializer.fromJson<String>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'cashAccountId': serializer.toJson<String>(cashAccountId),
      'balanceMinor': serializer.toJson<int>(balanceMinor),
      'balanceAsOf': serializer.toJson<String>(balanceAsOf),
      'observedAt': serializer.toJson<String>(observedAt),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'confirmationLevel': serializer.toJson<String>(confirmationLevel),
      'recordedAt': serializer.toJson<String>(recordedAt),
    };
  }

  CashSnapshotRow copyWith({
    String? id,
    String? workspaceId,
    String? cashAccountId,
    int? balanceMinor,
    String? balanceAsOf,
    String? observedAt,
    String? sourceKind,
    String? confirmationLevel,
    String? recordedAt,
  }) => CashSnapshotRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    cashAccountId: cashAccountId ?? this.cashAccountId,
    balanceMinor: balanceMinor ?? this.balanceMinor,
    balanceAsOf: balanceAsOf ?? this.balanceAsOf,
    observedAt: observedAt ?? this.observedAt,
    sourceKind: sourceKind ?? this.sourceKind,
    confirmationLevel: confirmationLevel ?? this.confirmationLevel,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  CashSnapshotRow copyWithCompanion(CashBalanceSnapshotsCompanion data) {
    return CashSnapshotRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      cashAccountId: data.cashAccountId.present
          ? data.cashAccountId.value
          : this.cashAccountId,
      balanceMinor: data.balanceMinor.present
          ? data.balanceMinor.value
          : this.balanceMinor,
      balanceAsOf: data.balanceAsOf.present
          ? data.balanceAsOf.value
          : this.balanceAsOf,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      confirmationLevel: data.confirmationLevel.present
          ? data.confirmationLevel.value
          : this.confirmationLevel,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashSnapshotRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('balanceMinor: $balanceMinor, ')
          ..write('balanceAsOf: $balanceAsOf, ')
          ..write('observedAt: $observedAt, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('confirmationLevel: $confirmationLevel, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    cashAccountId,
    balanceMinor,
    balanceAsOf,
    observedAt,
    sourceKind,
    confirmationLevel,
    recordedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashSnapshotRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.cashAccountId == this.cashAccountId &&
          other.balanceMinor == this.balanceMinor &&
          other.balanceAsOf == this.balanceAsOf &&
          other.observedAt == this.observedAt &&
          other.sourceKind == this.sourceKind &&
          other.confirmationLevel == this.confirmationLevel &&
          other.recordedAt == this.recordedAt);
}

class CashBalanceSnapshotsCompanion extends UpdateCompanion<CashSnapshotRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> cashAccountId;
  final Value<int> balanceMinor;
  final Value<String> balanceAsOf;
  final Value<String> observedAt;
  final Value<String> sourceKind;
  final Value<String> confirmationLevel;
  final Value<String> recordedAt;
  final Value<int> rowid;
  const CashBalanceSnapshotsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.cashAccountId = const Value.absent(),
    this.balanceMinor = const Value.absent(),
    this.balanceAsOf = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.confirmationLevel = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CashBalanceSnapshotsCompanion.insert({
    required String id,
    required String workspaceId,
    required String cashAccountId,
    required int balanceMinor,
    required String balanceAsOf,
    required String observedAt,
    required String sourceKind,
    required String confirmationLevel,
    required String recordedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       cashAccountId = Value(cashAccountId),
       balanceMinor = Value(balanceMinor),
       balanceAsOf = Value(balanceAsOf),
       observedAt = Value(observedAt),
       sourceKind = Value(sourceKind),
       confirmationLevel = Value(confirmationLevel),
       recordedAt = Value(recordedAt);
  static Insertable<CashSnapshotRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? cashAccountId,
    Expression<int>? balanceMinor,
    Expression<String>? balanceAsOf,
    Expression<String>? observedAt,
    Expression<String>? sourceKind,
    Expression<String>? confirmationLevel,
    Expression<String>? recordedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (cashAccountId != null) 'cash_account_id': cashAccountId,
      if (balanceMinor != null) 'balance_minor': balanceMinor,
      if (balanceAsOf != null) 'balance_as_of': balanceAsOf,
      if (observedAt != null) 'observed_at': observedAt,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (confirmationLevel != null) 'confirmation_level': confirmationLevel,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CashBalanceSnapshotsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? cashAccountId,
    Value<int>? balanceMinor,
    Value<String>? balanceAsOf,
    Value<String>? observedAt,
    Value<String>? sourceKind,
    Value<String>? confirmationLevel,
    Value<String>? recordedAt,
    Value<int>? rowid,
  }) {
    return CashBalanceSnapshotsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      balanceMinor: balanceMinor ?? this.balanceMinor,
      balanceAsOf: balanceAsOf ?? this.balanceAsOf,
      observedAt: observedAt ?? this.observedAt,
      sourceKind: sourceKind ?? this.sourceKind,
      confirmationLevel: confirmationLevel ?? this.confirmationLevel,
      recordedAt: recordedAt ?? this.recordedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (cashAccountId.present) {
      map['cash_account_id'] = Variable<String>(cashAccountId.value);
    }
    if (balanceMinor.present) {
      map['balance_minor'] = Variable<int>(balanceMinor.value);
    }
    if (balanceAsOf.present) {
      map['balance_as_of'] = Variable<String>(balanceAsOf.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<String>(observedAt.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (confirmationLevel.present) {
      map['confirmation_level'] = Variable<String>(confirmationLevel.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<String>(recordedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashBalanceSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('balanceMinor: $balanceMinor, ')
          ..write('balanceAsOf: $balanceAsOf, ')
          ..write('observedAt: $observedAt, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('confirmationLevel: $confirmationLevel, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecurringItemsTable extends RecurringItems
    with TableInfo<$RecurringItemsTable, RecurringItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashAccountIdMeta = const VerificationMeta(
    'cashAccountId',
  );
  @override
  late final GeneratedColumn<String> cashAccountId = GeneratedColumn<String>(
    'cash_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clsMeta = const VerificationMeta('cls');
  @override
  late final GeneratedColumn<String> cls = GeneratedColumn<String>(
    'cls',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frequencyMeta = const VerificationMeta(
    'frequency',
  );
  @override
  late final GeneratedColumn<String> frequency = GeneratedColumn<String>(
    'frequency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anchorOnMeta = const VerificationMeta(
    'anchorOn',
  );
  @override
  late final GeneratedColumn<String> anchorOn = GeneratedColumn<String>(
    'anchor_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayRuleMeta = const VerificationMeta(
    'dayRule',
  );
  @override
  late final GeneratedColumn<String> dayRule = GeneratedColumn<String>(
    'day_rule',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('anchor_day'),
  );
  static const VerificationMeta _startOnMeta = const VerificationMeta(
    'startOn',
  );
  @override
  late final GeneratedColumn<String> startOn = GeneratedColumn<String>(
    'start_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endOnMeta = const VerificationMeta('endOn');
  @override
  late final GeneratedColumn<String> endOn = GeneratedColumn<String>(
    'end_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    cashAccountId,
    label,
    amountMinor,
    cls,
    category,
    frequency,
    anchorOn,
    dayRule,
    startOn,
    endOn,
    active,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecurringItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('cash_account_id')) {
      context.handle(
        _cashAccountIdMeta,
        cashAccountId.isAcceptableOrUnknown(
          data['cash_account_id']!,
          _cashAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cashAccountIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('cls')) {
      context.handle(
        _clsMeta,
        cls.isAcceptableOrUnknown(data['cls']!, _clsMeta),
      );
    } else if (isInserting) {
      context.missing(_clsMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('frequency')) {
      context.handle(
        _frequencyMeta,
        frequency.isAcceptableOrUnknown(data['frequency']!, _frequencyMeta),
      );
    } else if (isInserting) {
      context.missing(_frequencyMeta);
    }
    if (data.containsKey('anchor_on')) {
      context.handle(
        _anchorOnMeta,
        anchorOn.isAcceptableOrUnknown(data['anchor_on']!, _anchorOnMeta),
      );
    } else if (isInserting) {
      context.missing(_anchorOnMeta);
    }
    if (data.containsKey('day_rule')) {
      context.handle(
        _dayRuleMeta,
        dayRule.isAcceptableOrUnknown(data['day_rule']!, _dayRuleMeta),
      );
    }
    if (data.containsKey('start_on')) {
      context.handle(
        _startOnMeta,
        startOn.isAcceptableOrUnknown(data['start_on']!, _startOnMeta),
      );
    } else if (isInserting) {
      context.missing(_startOnMeta);
    }
    if (data.containsKey('end_on')) {
      context.handle(
        _endOnMeta,
        endOn.isAcceptableOrUnknown(data['end_on']!, _endOnMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];
  @override
  RecurringItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      cashAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_account_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      cls: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cls'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      frequency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frequency'],
      )!,
      anchorOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor_on'],
      )!,
      dayRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_rule'],
      )!,
      startOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_on'],
      )!,
      endOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_on'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RecurringItemsTable createAlias(String alias) {
    return $RecurringItemsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class RecurringItemRow extends DataClass
    implements Insertable<RecurringItemRow> {
  final String id;
  final String workspaceId;
  final String cashAccountId;
  final String label;
  final int amountMinor;

  /// `confirmed` / `expected` / `planned`。
  final String cls;

  /// `income` / `bill` / `living` / `repayment` / `fee` / `other`。
  final String category;

  /// `monthly` / `weekly` / `biweekly` / `yearly`。
  final String frequency;
  final String anchorOn;

  /// `anchor_day` / `month_end`。
  final String dayRule;
  final String startOn;
  final String? endOn;
  final bool active;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const RecurringItemRow({
    required this.id,
    required this.workspaceId,
    required this.cashAccountId,
    required this.label,
    required this.amountMinor,
    required this.cls,
    required this.category,
    required this.frequency,
    required this.anchorOn,
    required this.dayRule,
    required this.startOn,
    this.endOn,
    required this.active,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['cash_account_id'] = Variable<String>(cashAccountId);
    map['label'] = Variable<String>(label);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['cls'] = Variable<String>(cls);
    map['category'] = Variable<String>(category);
    map['frequency'] = Variable<String>(frequency);
    map['anchor_on'] = Variable<String>(anchorOn);
    map['day_rule'] = Variable<String>(dayRule);
    map['start_on'] = Variable<String>(startOn);
    if (!nullToAbsent || endOn != null) {
      map['end_on'] = Variable<String>(endOn);
    }
    map['active'] = Variable<bool>(active);
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  RecurringItemsCompanion toCompanion(bool nullToAbsent) {
    return RecurringItemsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      cashAccountId: Value(cashAccountId),
      label: Value(label),
      amountMinor: Value(amountMinor),
      cls: Value(cls),
      category: Value(category),
      frequency: Value(frequency),
      anchorOn: Value(anchorOn),
      dayRule: Value(dayRule),
      startOn: Value(startOn),
      endOn: endOn == null && nullToAbsent
          ? const Value.absent()
          : Value(endOn),
      active: Value(active),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecurringItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringItemRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      cashAccountId: serializer.fromJson<String>(json['cashAccountId']),
      label: serializer.fromJson<String>(json['label']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      cls: serializer.fromJson<String>(json['cls']),
      category: serializer.fromJson<String>(json['category']),
      frequency: serializer.fromJson<String>(json['frequency']),
      anchorOn: serializer.fromJson<String>(json['anchorOn']),
      dayRule: serializer.fromJson<String>(json['dayRule']),
      startOn: serializer.fromJson<String>(json['startOn']),
      endOn: serializer.fromJson<String?>(json['endOn']),
      active: serializer.fromJson<bool>(json['active']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'cashAccountId': serializer.toJson<String>(cashAccountId),
      'label': serializer.toJson<String>(label),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'cls': serializer.toJson<String>(cls),
      'category': serializer.toJson<String>(category),
      'frequency': serializer.toJson<String>(frequency),
      'anchorOn': serializer.toJson<String>(anchorOn),
      'dayRule': serializer.toJson<String>(dayRule),
      'startOn': serializer.toJson<String>(startOn),
      'endOn': serializer.toJson<String?>(endOn),
      'active': serializer.toJson<bool>(active),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  RecurringItemRow copyWith({
    String? id,
    String? workspaceId,
    String? cashAccountId,
    String? label,
    int? amountMinor,
    String? cls,
    String? category,
    String? frequency,
    String? anchorOn,
    String? dayRule,
    String? startOn,
    Value<String?> endOn = const Value.absent(),
    bool? active,
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => RecurringItemRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    cashAccountId: cashAccountId ?? this.cashAccountId,
    label: label ?? this.label,
    amountMinor: amountMinor ?? this.amountMinor,
    cls: cls ?? this.cls,
    category: category ?? this.category,
    frequency: frequency ?? this.frequency,
    anchorOn: anchorOn ?? this.anchorOn,
    dayRule: dayRule ?? this.dayRule,
    startOn: startOn ?? this.startOn,
    endOn: endOn.present ? endOn.value : this.endOn,
    active: active ?? this.active,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RecurringItemRow copyWithCompanion(RecurringItemsCompanion data) {
    return RecurringItemRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      cashAccountId: data.cashAccountId.present
          ? data.cashAccountId.value
          : this.cashAccountId,
      label: data.label.present ? data.label.value : this.label,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      cls: data.cls.present ? data.cls.value : this.cls,
      category: data.category.present ? data.category.value : this.category,
      frequency: data.frequency.present ? data.frequency.value : this.frequency,
      anchorOn: data.anchorOn.present ? data.anchorOn.value : this.anchorOn,
      dayRule: data.dayRule.present ? data.dayRule.value : this.dayRule,
      startOn: data.startOn.present ? data.startOn.value : this.startOn,
      endOn: data.endOn.present ? data.endOn.value : this.endOn,
      active: data.active.present ? data.active.value : this.active,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecurringItemRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('label: $label, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('cls: $cls, ')
          ..write('category: $category, ')
          ..write('frequency: $frequency, ')
          ..write('anchorOn: $anchorOn, ')
          ..write('dayRule: $dayRule, ')
          ..write('startOn: $startOn, ')
          ..write('endOn: $endOn, ')
          ..write('active: $active, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    cashAccountId,
    label,
    amountMinor,
    cls,
    category,
    frequency,
    anchorOn,
    dayRule,
    startOn,
    endOn,
    active,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringItemRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.cashAccountId == this.cashAccountId &&
          other.label == this.label &&
          other.amountMinor == this.amountMinor &&
          other.cls == this.cls &&
          other.category == this.category &&
          other.frequency == this.frequency &&
          other.anchorOn == this.anchorOn &&
          other.dayRule == this.dayRule &&
          other.startOn == this.startOn &&
          other.endOn == this.endOn &&
          other.active == this.active &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RecurringItemsCompanion extends UpdateCompanion<RecurringItemRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> cashAccountId;
  final Value<String> label;
  final Value<int> amountMinor;
  final Value<String> cls;
  final Value<String> category;
  final Value<String> frequency;
  final Value<String> anchorOn;
  final Value<String> dayRule;
  final Value<String> startOn;
  final Value<String?> endOn;
  final Value<bool> active;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const RecurringItemsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.cashAccountId = const Value.absent(),
    this.label = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.cls = const Value.absent(),
    this.category = const Value.absent(),
    this.frequency = const Value.absent(),
    this.anchorOn = const Value.absent(),
    this.dayRule = const Value.absent(),
    this.startOn = const Value.absent(),
    this.endOn = const Value.absent(),
    this.active = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecurringItemsCompanion.insert({
    required String id,
    required String workspaceId,
    required String cashAccountId,
    required String label,
    required int amountMinor,
    required String cls,
    required String category,
    required String frequency,
    required String anchorOn,
    this.dayRule = const Value.absent(),
    required String startOn,
    this.endOn = const Value.absent(),
    this.active = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       cashAccountId = Value(cashAccountId),
       label = Value(label),
       amountMinor = Value(amountMinor),
       cls = Value(cls),
       category = Value(category),
       frequency = Value(frequency),
       anchorOn = Value(anchorOn),
       startOn = Value(startOn),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RecurringItemRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? cashAccountId,
    Expression<String>? label,
    Expression<int>? amountMinor,
    Expression<String>? cls,
    Expression<String>? category,
    Expression<String>? frequency,
    Expression<String>? anchorOn,
    Expression<String>? dayRule,
    Expression<String>? startOn,
    Expression<String>? endOn,
    Expression<bool>? active,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (cashAccountId != null) 'cash_account_id': cashAccountId,
      if (label != null) 'label': label,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (cls != null) 'cls': cls,
      if (category != null) 'category': category,
      if (frequency != null) 'frequency': frequency,
      if (anchorOn != null) 'anchor_on': anchorOn,
      if (dayRule != null) 'day_rule': dayRule,
      if (startOn != null) 'start_on': startOn,
      if (endOn != null) 'end_on': endOn,
      if (active != null) 'active': active,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecurringItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? cashAccountId,
    Value<String>? label,
    Value<int>? amountMinor,
    Value<String>? cls,
    Value<String>? category,
    Value<String>? frequency,
    Value<String>? anchorOn,
    Value<String>? dayRule,
    Value<String>? startOn,
    Value<String?>? endOn,
    Value<bool>? active,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return RecurringItemsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      label: label ?? this.label,
      amountMinor: amountMinor ?? this.amountMinor,
      cls: cls ?? this.cls,
      category: category ?? this.category,
      frequency: frequency ?? this.frequency,
      anchorOn: anchorOn ?? this.anchorOn,
      dayRule: dayRule ?? this.dayRule,
      startOn: startOn ?? this.startOn,
      endOn: endOn ?? this.endOn,
      active: active ?? this.active,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (cashAccountId.present) {
      map['cash_account_id'] = Variable<String>(cashAccountId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (cls.present) {
      map['cls'] = Variable<String>(cls.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (frequency.present) {
      map['frequency'] = Variable<String>(frequency.value);
    }
    if (anchorOn.present) {
      map['anchor_on'] = Variable<String>(anchorOn.value);
    }
    if (dayRule.present) {
      map['day_rule'] = Variable<String>(dayRule.value);
    }
    if (startOn.present) {
      map['start_on'] = Variable<String>(startOn.value);
    }
    if (endOn.present) {
      map['end_on'] = Variable<String>(endOn.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringItemsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('label: $label, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('cls: $cls, ')
          ..write('category: $category, ')
          ..write('frequency: $frequency, ')
          ..write('anchorOn: $anchorOn, ')
          ..write('dayRule: $dayRule, ')
          ..write('startOn: $startOn, ')
          ..write('endOn: $endOn, ')
          ..write('active: $active, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CashEventsTable extends CashEvents
    with TableInfo<$CashEventsTable, CashEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashAccountIdMeta = const VerificationMeta(
    'cashAccountId',
  );
  @override
  late final GeneratedColumn<String> cashAccountId = GeneratedColumn<String>(
    'cash_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventOnMeta = const VerificationMeta(
    'eventOn',
  );
  @override
  late final GeneratedColumn<String> eventOn = GeneratedColumn<String>(
    'event_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventAtMeta = const VerificationMeta(
    'eventAt',
  );
  @override
  late final GeneratedColumn<String> eventAt = GeneratedColumn<String>(
    'event_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clsMeta = const VerificationMeta('cls');
  @override
  late final GeneratedColumn<String> cls = GeneratedColumn<String>(
    'cls',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _postingStatusMeta = const VerificationMeta(
    'postingStatus',
  );
  @override
  late final GeneratedColumn<String> postingStatus = GeneratedColumn<String>(
    'posting_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('planned'),
  );
  static const VerificationMeta _recurringItemIdMeta = const VerificationMeta(
    'recurringItemId',
  );
  @override
  late final GeneratedColumn<String> recurringItemId = GeneratedColumn<String>(
    'recurring_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transferGroupIdMeta = const VerificationMeta(
    'transferGroupId',
  );
  @override
  late final GeneratedColumn<String> transferGroupId = GeneratedColumn<String>(
    'transfer_group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkedRepaymentIdMeta = const VerificationMeta(
    'linkedRepaymentId',
  );
  @override
  late final GeneratedColumn<String> linkedRepaymentId =
      GeneratedColumn<String>(
        'linked_repayment_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _linkedPlanRunIdMeta = const VerificationMeta(
    'linkedPlanRunId',
  );
  @override
  late final GeneratedColumn<String> linkedPlanRunId = GeneratedColumn<String>(
    'linked_plan_run_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    cashAccountId,
    eventOn,
    eventAt,
    amountMinor,
    cls,
    category,
    label,
    postingStatus,
    recurringItemId,
    occurrenceKey,
    transferGroupId,
    linkedRepaymentId,
    linkedPlanRunId,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<CashEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('cash_account_id')) {
      context.handle(
        _cashAccountIdMeta,
        cashAccountId.isAcceptableOrUnknown(
          data['cash_account_id']!,
          _cashAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cashAccountIdMeta);
    }
    if (data.containsKey('event_on')) {
      context.handle(
        _eventOnMeta,
        eventOn.isAcceptableOrUnknown(data['event_on']!, _eventOnMeta),
      );
    } else if (isInserting) {
      context.missing(_eventOnMeta);
    }
    if (data.containsKey('event_at')) {
      context.handle(
        _eventAtMeta,
        eventAt.isAcceptableOrUnknown(data['event_at']!, _eventAtMeta),
      );
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('cls')) {
      context.handle(
        _clsMeta,
        cls.isAcceptableOrUnknown(data['cls']!, _clsMeta),
      );
    } else if (isInserting) {
      context.missing(_clsMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('posting_status')) {
      context.handle(
        _postingStatusMeta,
        postingStatus.isAcceptableOrUnknown(
          data['posting_status']!,
          _postingStatusMeta,
        ),
      );
    }
    if (data.containsKey('recurring_item_id')) {
      context.handle(
        _recurringItemIdMeta,
        recurringItemId.isAcceptableOrUnknown(
          data['recurring_item_id']!,
          _recurringItemIdMeta,
        ),
      );
    }
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    }
    if (data.containsKey('transfer_group_id')) {
      context.handle(
        _transferGroupIdMeta,
        transferGroupId.isAcceptableOrUnknown(
          data['transfer_group_id']!,
          _transferGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('linked_repayment_id')) {
      context.handle(
        _linkedRepaymentIdMeta,
        linkedRepaymentId.isAcceptableOrUnknown(
          data['linked_repayment_id']!,
          _linkedRepaymentIdMeta,
        ),
      );
    }
    if (data.containsKey('linked_plan_run_id')) {
      context.handle(
        _linkedPlanRunIdMeta,
        linkedPlanRunId.isAcceptableOrUnknown(
          data['linked_plan_run_id']!,
          _linkedPlanRunIdMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, cashAccountId, id},
  ];
  @override
  CashEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      cashAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_account_id'],
      )!,
      eventOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_on'],
      )!,
      eventAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_at'],
      ),
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      cls: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cls'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      postingStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}posting_status'],
      )!,
      recurringItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurring_item_id'],
      ),
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      ),
      transferGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_group_id'],
      ),
      linkedRepaymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_repayment_id'],
      ),
      linkedPlanRunId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_plan_run_id'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CashEventsTable createAlias(String alias) {
    return $CashEventsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CashEventRow extends DataClass implements Insertable<CashEventRow> {
  final String id;
  final String workspaceId;
  final String cashAccountId;

  /// 业务日期 `YYYY-MM-DD`。
  final String eventOn;

  /// 精确时刻（RFC 3339，按其自身偏移的日期必须等于 `event_on`）；空 = 只知道日期。
  final String? eventAt;
  final int amountMinor;

  /// `confirmed` / `expected` / `planned`。
  final String cls;

  /// `income` / `bill` / `living` / `repayment` / `transfer_in` / `transfer_out` / `fee` / `other`。
  final String category;
  final String? label;

  /// `planned` / `posted`。
  final String postingStatus;
  final String? recurringItemId;

  /// 周期事项的期键：该期的原定日期 `YYYY-MM-DD`。
  final String? occurrenceKey;
  final String? transferGroupId;
  final String? linkedRepaymentId;
  final String? linkedPlanRunId;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  const CashEventRow({
    required this.id,
    required this.workspaceId,
    required this.cashAccountId,
    required this.eventOn,
    this.eventAt,
    required this.amountMinor,
    required this.cls,
    required this.category,
    this.label,
    required this.postingStatus,
    this.recurringItemId,
    this.occurrenceKey,
    this.transferGroupId,
    this.linkedRepaymentId,
    this.linkedPlanRunId,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['cash_account_id'] = Variable<String>(cashAccountId);
    map['event_on'] = Variable<String>(eventOn);
    if (!nullToAbsent || eventAt != null) {
      map['event_at'] = Variable<String>(eventAt);
    }
    map['amount_minor'] = Variable<int>(amountMinor);
    map['cls'] = Variable<String>(cls);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    map['posting_status'] = Variable<String>(postingStatus);
    if (!nullToAbsent || recurringItemId != null) {
      map['recurring_item_id'] = Variable<String>(recurringItemId);
    }
    if (!nullToAbsent || occurrenceKey != null) {
      map['occurrence_key'] = Variable<String>(occurrenceKey);
    }
    if (!nullToAbsent || transferGroupId != null) {
      map['transfer_group_id'] = Variable<String>(transferGroupId);
    }
    if (!nullToAbsent || linkedRepaymentId != null) {
      map['linked_repayment_id'] = Variable<String>(linkedRepaymentId);
    }
    if (!nullToAbsent || linkedPlanRunId != null) {
      map['linked_plan_run_id'] = Variable<String>(linkedPlanRunId);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  CashEventsCompanion toCompanion(bool nullToAbsent) {
    return CashEventsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      cashAccountId: Value(cashAccountId),
      eventOn: Value(eventOn),
      eventAt: eventAt == null && nullToAbsent
          ? const Value.absent()
          : Value(eventAt),
      amountMinor: Value(amountMinor),
      cls: Value(cls),
      category: Value(category),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      postingStatus: Value(postingStatus),
      recurringItemId: recurringItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(recurringItemId),
      occurrenceKey: occurrenceKey == null && nullToAbsent
          ? const Value.absent()
          : Value(occurrenceKey),
      transferGroupId: transferGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(transferGroupId),
      linkedRepaymentId: linkedRepaymentId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedRepaymentId),
      linkedPlanRunId: linkedPlanRunId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedPlanRunId),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CashEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashEventRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      cashAccountId: serializer.fromJson<String>(json['cashAccountId']),
      eventOn: serializer.fromJson<String>(json['eventOn']),
      eventAt: serializer.fromJson<String?>(json['eventAt']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      cls: serializer.fromJson<String>(json['cls']),
      category: serializer.fromJson<String>(json['category']),
      label: serializer.fromJson<String?>(json['label']),
      postingStatus: serializer.fromJson<String>(json['postingStatus']),
      recurringItemId: serializer.fromJson<String?>(json['recurringItemId']),
      occurrenceKey: serializer.fromJson<String?>(json['occurrenceKey']),
      transferGroupId: serializer.fromJson<String?>(json['transferGroupId']),
      linkedRepaymentId: serializer.fromJson<String?>(
        json['linkedRepaymentId'],
      ),
      linkedPlanRunId: serializer.fromJson<String?>(json['linkedPlanRunId']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'cashAccountId': serializer.toJson<String>(cashAccountId),
      'eventOn': serializer.toJson<String>(eventOn),
      'eventAt': serializer.toJson<String?>(eventAt),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'cls': serializer.toJson<String>(cls),
      'category': serializer.toJson<String>(category),
      'label': serializer.toJson<String?>(label),
      'postingStatus': serializer.toJson<String>(postingStatus),
      'recurringItemId': serializer.toJson<String?>(recurringItemId),
      'occurrenceKey': serializer.toJson<String?>(occurrenceKey),
      'transferGroupId': serializer.toJson<String?>(transferGroupId),
      'linkedRepaymentId': serializer.toJson<String?>(linkedRepaymentId),
      'linkedPlanRunId': serializer.toJson<String?>(linkedPlanRunId),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  CashEventRow copyWith({
    String? id,
    String? workspaceId,
    String? cashAccountId,
    String? eventOn,
    Value<String?> eventAt = const Value.absent(),
    int? amountMinor,
    String? cls,
    String? category,
    Value<String?> label = const Value.absent(),
    String? postingStatus,
    Value<String?> recurringItemId = const Value.absent(),
    Value<String?> occurrenceKey = const Value.absent(),
    Value<String?> transferGroupId = const Value.absent(),
    Value<String?> linkedRepaymentId = const Value.absent(),
    Value<String?> linkedPlanRunId = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => CashEventRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    cashAccountId: cashAccountId ?? this.cashAccountId,
    eventOn: eventOn ?? this.eventOn,
    eventAt: eventAt.present ? eventAt.value : this.eventAt,
    amountMinor: amountMinor ?? this.amountMinor,
    cls: cls ?? this.cls,
    category: category ?? this.category,
    label: label.present ? label.value : this.label,
    postingStatus: postingStatus ?? this.postingStatus,
    recurringItemId: recurringItemId.present
        ? recurringItemId.value
        : this.recurringItemId,
    occurrenceKey: occurrenceKey.present
        ? occurrenceKey.value
        : this.occurrenceKey,
    transferGroupId: transferGroupId.present
        ? transferGroupId.value
        : this.transferGroupId,
    linkedRepaymentId: linkedRepaymentId.present
        ? linkedRepaymentId.value
        : this.linkedRepaymentId,
    linkedPlanRunId: linkedPlanRunId.present
        ? linkedPlanRunId.value
        : this.linkedPlanRunId,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CashEventRow copyWithCompanion(CashEventsCompanion data) {
    return CashEventRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      cashAccountId: data.cashAccountId.present
          ? data.cashAccountId.value
          : this.cashAccountId,
      eventOn: data.eventOn.present ? data.eventOn.value : this.eventOn,
      eventAt: data.eventAt.present ? data.eventAt.value : this.eventAt,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      cls: data.cls.present ? data.cls.value : this.cls,
      category: data.category.present ? data.category.value : this.category,
      label: data.label.present ? data.label.value : this.label,
      postingStatus: data.postingStatus.present
          ? data.postingStatus.value
          : this.postingStatus,
      recurringItemId: data.recurringItemId.present
          ? data.recurringItemId.value
          : this.recurringItemId,
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      transferGroupId: data.transferGroupId.present
          ? data.transferGroupId.value
          : this.transferGroupId,
      linkedRepaymentId: data.linkedRepaymentId.present
          ? data.linkedRepaymentId.value
          : this.linkedRepaymentId,
      linkedPlanRunId: data.linkedPlanRunId.present
          ? data.linkedPlanRunId.value
          : this.linkedPlanRunId,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashEventRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('eventOn: $eventOn, ')
          ..write('eventAt: $eventAt, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('cls: $cls, ')
          ..write('category: $category, ')
          ..write('label: $label, ')
          ..write('postingStatus: $postingStatus, ')
          ..write('recurringItemId: $recurringItemId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('transferGroupId: $transferGroupId, ')
          ..write('linkedRepaymentId: $linkedRepaymentId, ')
          ..write('linkedPlanRunId: $linkedPlanRunId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    cashAccountId,
    eventOn,
    eventAt,
    amountMinor,
    cls,
    category,
    label,
    postingStatus,
    recurringItemId,
    occurrenceKey,
    transferGroupId,
    linkedRepaymentId,
    linkedPlanRunId,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashEventRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.cashAccountId == this.cashAccountId &&
          other.eventOn == this.eventOn &&
          other.eventAt == this.eventAt &&
          other.amountMinor == this.amountMinor &&
          other.cls == this.cls &&
          other.category == this.category &&
          other.label == this.label &&
          other.postingStatus == this.postingStatus &&
          other.recurringItemId == this.recurringItemId &&
          other.occurrenceKey == this.occurrenceKey &&
          other.transferGroupId == this.transferGroupId &&
          other.linkedRepaymentId == this.linkedRepaymentId &&
          other.linkedPlanRunId == this.linkedPlanRunId &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CashEventsCompanion extends UpdateCompanion<CashEventRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> cashAccountId;
  final Value<String> eventOn;
  final Value<String?> eventAt;
  final Value<int> amountMinor;
  final Value<String> cls;
  final Value<String> category;
  final Value<String?> label;
  final Value<String> postingStatus;
  final Value<String?> recurringItemId;
  final Value<String?> occurrenceKey;
  final Value<String?> transferGroupId;
  final Value<String?> linkedRepaymentId;
  final Value<String?> linkedPlanRunId;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const CashEventsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.cashAccountId = const Value.absent(),
    this.eventOn = const Value.absent(),
    this.eventAt = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.cls = const Value.absent(),
    this.category = const Value.absent(),
    this.label = const Value.absent(),
    this.postingStatus = const Value.absent(),
    this.recurringItemId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.transferGroupId = const Value.absent(),
    this.linkedRepaymentId = const Value.absent(),
    this.linkedPlanRunId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CashEventsCompanion.insert({
    required String id,
    required String workspaceId,
    required String cashAccountId,
    required String eventOn,
    this.eventAt = const Value.absent(),
    required int amountMinor,
    required String cls,
    required String category,
    this.label = const Value.absent(),
    this.postingStatus = const Value.absent(),
    this.recurringItemId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.transferGroupId = const Value.absent(),
    this.linkedRepaymentId = const Value.absent(),
    this.linkedPlanRunId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       cashAccountId = Value(cashAccountId),
       eventOn = Value(eventOn),
       amountMinor = Value(amountMinor),
       cls = Value(cls),
       category = Value(category),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CashEventRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? cashAccountId,
    Expression<String>? eventOn,
    Expression<String>? eventAt,
    Expression<int>? amountMinor,
    Expression<String>? cls,
    Expression<String>? category,
    Expression<String>? label,
    Expression<String>? postingStatus,
    Expression<String>? recurringItemId,
    Expression<String>? occurrenceKey,
    Expression<String>? transferGroupId,
    Expression<String>? linkedRepaymentId,
    Expression<String>? linkedPlanRunId,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (cashAccountId != null) 'cash_account_id': cashAccountId,
      if (eventOn != null) 'event_on': eventOn,
      if (eventAt != null) 'event_at': eventAt,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (cls != null) 'cls': cls,
      if (category != null) 'category': category,
      if (label != null) 'label': label,
      if (postingStatus != null) 'posting_status': postingStatus,
      if (recurringItemId != null) 'recurring_item_id': recurringItemId,
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (transferGroupId != null) 'transfer_group_id': transferGroupId,
      if (linkedRepaymentId != null) 'linked_repayment_id': linkedRepaymentId,
      if (linkedPlanRunId != null) 'linked_plan_run_id': linkedPlanRunId,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CashEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? cashAccountId,
    Value<String>? eventOn,
    Value<String?>? eventAt,
    Value<int>? amountMinor,
    Value<String>? cls,
    Value<String>? category,
    Value<String?>? label,
    Value<String>? postingStatus,
    Value<String?>? recurringItemId,
    Value<String?>? occurrenceKey,
    Value<String?>? transferGroupId,
    Value<String?>? linkedRepaymentId,
    Value<String?>? linkedPlanRunId,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CashEventsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      eventOn: eventOn ?? this.eventOn,
      eventAt: eventAt ?? this.eventAt,
      amountMinor: amountMinor ?? this.amountMinor,
      cls: cls ?? this.cls,
      category: category ?? this.category,
      label: label ?? this.label,
      postingStatus: postingStatus ?? this.postingStatus,
      recurringItemId: recurringItemId ?? this.recurringItemId,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      linkedRepaymentId: linkedRepaymentId ?? this.linkedRepaymentId,
      linkedPlanRunId: linkedPlanRunId ?? this.linkedPlanRunId,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (cashAccountId.present) {
      map['cash_account_id'] = Variable<String>(cashAccountId.value);
    }
    if (eventOn.present) {
      map['event_on'] = Variable<String>(eventOn.value);
    }
    if (eventAt.present) {
      map['event_at'] = Variable<String>(eventAt.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (cls.present) {
      map['cls'] = Variable<String>(cls.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (postingStatus.present) {
      map['posting_status'] = Variable<String>(postingStatus.value);
    }
    if (recurringItemId.present) {
      map['recurring_item_id'] = Variable<String>(recurringItemId.value);
    }
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (transferGroupId.present) {
      map['transfer_group_id'] = Variable<String>(transferGroupId.value);
    }
    if (linkedRepaymentId.present) {
      map['linked_repayment_id'] = Variable<String>(linkedRepaymentId.value);
    }
    if (linkedPlanRunId.present) {
      map['linked_plan_run_id'] = Variable<String>(linkedPlanRunId.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashEventsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('eventOn: $eventOn, ')
          ..write('eventAt: $eventAt, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('cls: $cls, ')
          ..write('category: $category, ')
          ..write('label: $label, ')
          ..write('postingStatus: $postingStatus, ')
          ..write('recurringItemId: $recurringItemId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('transferGroupId: $transferGroupId, ')
          ..write('linkedRepaymentId: $linkedRepaymentId, ')
          ..write('linkedPlanRunId: $linkedPlanRunId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SnapshotIncludedEventsTable extends SnapshotIncludedEvents
    with TableInfo<$SnapshotIncludedEventsTable, SnapshotIncludedEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnapshotIncludedEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashAccountIdMeta = const VerificationMeta(
    'cashAccountId',
  );
  @override
  late final GeneratedColumn<String> cashAccountId = GeneratedColumn<String>(
    'cash_account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashEventIdMeta = const VerificationMeta(
    'cashEventId',
  );
  @override
  late final GeneratedColumn<String> cashEventId = GeneratedColumn<String>(
    'cash_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    cashAccountId,
    snapshotId,
    cashEventId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snapshot_included_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SnapshotIncludedEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('cash_account_id')) {
      context.handle(
        _cashAccountIdMeta,
        cashAccountId.isAcceptableOrUnknown(
          data['cash_account_id']!,
          _cashAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cashAccountIdMeta);
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('cash_event_id')) {
      context.handle(
        _cashEventIdMeta,
        cashEventId.isAcceptableOrUnknown(
          data['cash_event_id']!,
          _cashEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cashEventIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotId, cashEventId};
  @override
  SnapshotIncludedEventRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SnapshotIncludedEventRow(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      cashAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_account_id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      cashEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_event_id'],
      )!,
    );
  }

  @override
  $SnapshotIncludedEventsTable createAlias(String alias) {
    return $SnapshotIncludedEventsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class SnapshotIncludedEventRow extends DataClass
    implements Insertable<SnapshotIncludedEventRow> {
  final String workspaceId;
  final String cashAccountId;
  final String snapshotId;
  final String cashEventId;
  const SnapshotIncludedEventRow({
    required this.workspaceId,
    required this.cashAccountId,
    required this.snapshotId,
    required this.cashEventId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['cash_account_id'] = Variable<String>(cashAccountId);
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['cash_event_id'] = Variable<String>(cashEventId);
    return map;
  }

  SnapshotIncludedEventsCompanion toCompanion(bool nullToAbsent) {
    return SnapshotIncludedEventsCompanion(
      workspaceId: Value(workspaceId),
      cashAccountId: Value(cashAccountId),
      snapshotId: Value(snapshotId),
      cashEventId: Value(cashEventId),
    );
  }

  factory SnapshotIncludedEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SnapshotIncludedEventRow(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      cashAccountId: serializer.fromJson<String>(json['cashAccountId']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      cashEventId: serializer.fromJson<String>(json['cashEventId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'cashAccountId': serializer.toJson<String>(cashAccountId),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'cashEventId': serializer.toJson<String>(cashEventId),
    };
  }

  SnapshotIncludedEventRow copyWith({
    String? workspaceId,
    String? cashAccountId,
    String? snapshotId,
    String? cashEventId,
  }) => SnapshotIncludedEventRow(
    workspaceId: workspaceId ?? this.workspaceId,
    cashAccountId: cashAccountId ?? this.cashAccountId,
    snapshotId: snapshotId ?? this.snapshotId,
    cashEventId: cashEventId ?? this.cashEventId,
  );
  SnapshotIncludedEventRow copyWithCompanion(
    SnapshotIncludedEventsCompanion data,
  ) {
    return SnapshotIncludedEventRow(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      cashAccountId: data.cashAccountId.present
          ? data.cashAccountId.value
          : this.cashAccountId,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      cashEventId: data.cashEventId.present
          ? data.cashEventId.value
          : this.cashEventId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotIncludedEventRow(')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('cashEventId: $cashEventId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(workspaceId, cashAccountId, snapshotId, cashEventId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SnapshotIncludedEventRow &&
          other.workspaceId == this.workspaceId &&
          other.cashAccountId == this.cashAccountId &&
          other.snapshotId == this.snapshotId &&
          other.cashEventId == this.cashEventId);
}

class SnapshotIncludedEventsCompanion
    extends UpdateCompanion<SnapshotIncludedEventRow> {
  final Value<String> workspaceId;
  final Value<String> cashAccountId;
  final Value<String> snapshotId;
  final Value<String> cashEventId;
  final Value<int> rowid;
  const SnapshotIncludedEventsCompanion({
    this.workspaceId = const Value.absent(),
    this.cashAccountId = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.cashEventId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SnapshotIncludedEventsCompanion.insert({
    required String workspaceId,
    required String cashAccountId,
    required String snapshotId,
    required String cashEventId,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       cashAccountId = Value(cashAccountId),
       snapshotId = Value(snapshotId),
       cashEventId = Value(cashEventId);
  static Insertable<SnapshotIncludedEventRow> custom({
    Expression<String>? workspaceId,
    Expression<String>? cashAccountId,
    Expression<String>? snapshotId,
    Expression<String>? cashEventId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (cashAccountId != null) 'cash_account_id': cashAccountId,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (cashEventId != null) 'cash_event_id': cashEventId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SnapshotIncludedEventsCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? cashAccountId,
    Value<String>? snapshotId,
    Value<String>? cashEventId,
    Value<int>? rowid,
  }) {
    return SnapshotIncludedEventsCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      snapshotId: snapshotId ?? this.snapshotId,
      cashEventId: cashEventId ?? this.cashEventId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (cashAccountId.present) {
      map['cash_account_id'] = Variable<String>(cashAccountId.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (cashEventId.present) {
      map['cash_event_id'] = Variable<String>(cashEventId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnapshotIncludedEventsCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('cashEventId: $cashEventId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecurringOverridesTable extends RecurringOverrides
    with TableInfo<$RecurringOverridesTable, RecurringOverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecurringOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recurringItemIdMeta = const VerificationMeta(
    'recurringItemId',
  );
  @override
  late final GeneratedColumn<String> recurringItemId = GeneratedColumn<String>(
    'recurring_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventOnMeta = const VerificationMeta(
    'eventOn',
  );
  @override
  late final GeneratedColumn<String> eventOn = GeneratedColumn<String>(
    'event_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventAtMeta = const VerificationMeta(
    'eventAt',
  );
  @override
  late final GeneratedColumn<String> eventAt = GeneratedColumn<String>(
    'event_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    recurringItemId,
    occurrenceKey,
    action,
    amountMinor,
    eventOn,
    eventAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recurring_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecurringOverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('recurring_item_id')) {
      context.handle(
        _recurringItemIdMeta,
        recurringItemId.isAcceptableOrUnknown(
          data['recurring_item_id']!,
          _recurringItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recurringItemIdMeta);
    }
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrenceKeyMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    }
    if (data.containsKey('event_on')) {
      context.handle(
        _eventOnMeta,
        eventOn.isAcceptableOrUnknown(data['event_on']!, _eventOnMeta),
      );
    }
    if (data.containsKey('event_at')) {
      context.handle(
        _eventAtMeta,
        eventAt.isAcceptableOrUnknown(data['event_at']!, _eventAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recurringItemId, occurrenceKey};
  @override
  RecurringOverrideRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecurringOverrideRow(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      recurringItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurring_item_id'],
      )!,
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      ),
      eventOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_on'],
      ),
      eventAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RecurringOverridesTable createAlias(String alias) {
    return $RecurringOverridesTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class RecurringOverrideRow extends DataClass
    implements Insertable<RecurringOverrideRow> {
  final String workspaceId;
  final String recurringItemId;

  /// 被覆盖的那一期的原定日期。
  final String occurrenceKey;

  /// `skip` / `override`。
  final String action;
  final int? amountMinor;
  final String? eventOn;
  final String? eventAt;
  final String createdAt;
  final String updatedAt;
  const RecurringOverrideRow({
    required this.workspaceId,
    required this.recurringItemId,
    required this.occurrenceKey,
    required this.action,
    this.amountMinor,
    this.eventOn,
    this.eventAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['recurring_item_id'] = Variable<String>(recurringItemId);
    map['occurrence_key'] = Variable<String>(occurrenceKey);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || amountMinor != null) {
      map['amount_minor'] = Variable<int>(amountMinor);
    }
    if (!nullToAbsent || eventOn != null) {
      map['event_on'] = Variable<String>(eventOn);
    }
    if (!nullToAbsent || eventAt != null) {
      map['event_at'] = Variable<String>(eventAt);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  RecurringOverridesCompanion toCompanion(bool nullToAbsent) {
    return RecurringOverridesCompanion(
      workspaceId: Value(workspaceId),
      recurringItemId: Value(recurringItemId),
      occurrenceKey: Value(occurrenceKey),
      action: Value(action),
      amountMinor: amountMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(amountMinor),
      eventOn: eventOn == null && nullToAbsent
          ? const Value.absent()
          : Value(eventOn),
      eventAt: eventAt == null && nullToAbsent
          ? const Value.absent()
          : Value(eventAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RecurringOverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecurringOverrideRow(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      recurringItemId: serializer.fromJson<String>(json['recurringItemId']),
      occurrenceKey: serializer.fromJson<String>(json['occurrenceKey']),
      action: serializer.fromJson<String>(json['action']),
      amountMinor: serializer.fromJson<int?>(json['amountMinor']),
      eventOn: serializer.fromJson<String?>(json['eventOn']),
      eventAt: serializer.fromJson<String?>(json['eventAt']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'recurringItemId': serializer.toJson<String>(recurringItemId),
      'occurrenceKey': serializer.toJson<String>(occurrenceKey),
      'action': serializer.toJson<String>(action),
      'amountMinor': serializer.toJson<int?>(amountMinor),
      'eventOn': serializer.toJson<String?>(eventOn),
      'eventAt': serializer.toJson<String?>(eventAt),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  RecurringOverrideRow copyWith({
    String? workspaceId,
    String? recurringItemId,
    String? occurrenceKey,
    String? action,
    Value<int?> amountMinor = const Value.absent(),
    Value<String?> eventOn = const Value.absent(),
    Value<String?> eventAt = const Value.absent(),
    String? createdAt,
    String? updatedAt,
  }) => RecurringOverrideRow(
    workspaceId: workspaceId ?? this.workspaceId,
    recurringItemId: recurringItemId ?? this.recurringItemId,
    occurrenceKey: occurrenceKey ?? this.occurrenceKey,
    action: action ?? this.action,
    amountMinor: amountMinor.present ? amountMinor.value : this.amountMinor,
    eventOn: eventOn.present ? eventOn.value : this.eventOn,
    eventAt: eventAt.present ? eventAt.value : this.eventAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RecurringOverrideRow copyWithCompanion(RecurringOverridesCompanion data) {
    return RecurringOverrideRow(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      recurringItemId: data.recurringItemId.present
          ? data.recurringItemId.value
          : this.recurringItemId,
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      action: data.action.present ? data.action.value : this.action,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      eventOn: data.eventOn.present ? data.eventOn.value : this.eventOn,
      eventAt: data.eventAt.present ? data.eventAt.value : this.eventAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecurringOverrideRow(')
          ..write('workspaceId: $workspaceId, ')
          ..write('recurringItemId: $recurringItemId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('action: $action, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('eventOn: $eventOn, ')
          ..write('eventAt: $eventAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    recurringItemId,
    occurrenceKey,
    action,
    amountMinor,
    eventOn,
    eventAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurringOverrideRow &&
          other.workspaceId == this.workspaceId &&
          other.recurringItemId == this.recurringItemId &&
          other.occurrenceKey == this.occurrenceKey &&
          other.action == this.action &&
          other.amountMinor == this.amountMinor &&
          other.eventOn == this.eventOn &&
          other.eventAt == this.eventAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class RecurringOverridesCompanion
    extends UpdateCompanion<RecurringOverrideRow> {
  final Value<String> workspaceId;
  final Value<String> recurringItemId;
  final Value<String> occurrenceKey;
  final Value<String> action;
  final Value<int?> amountMinor;
  final Value<String?> eventOn;
  final Value<String?> eventAt;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const RecurringOverridesCompanion({
    this.workspaceId = const Value.absent(),
    this.recurringItemId = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.action = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.eventOn = const Value.absent(),
    this.eventAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecurringOverridesCompanion.insert({
    required String workspaceId,
    required String recurringItemId,
    required String occurrenceKey,
    required String action,
    this.amountMinor = const Value.absent(),
    this.eventOn = const Value.absent(),
    this.eventAt = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       recurringItemId = Value(recurringItemId),
       occurrenceKey = Value(occurrenceKey),
       action = Value(action),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RecurringOverrideRow> custom({
    Expression<String>? workspaceId,
    Expression<String>? recurringItemId,
    Expression<String>? occurrenceKey,
    Expression<String>? action,
    Expression<int>? amountMinor,
    Expression<String>? eventOn,
    Expression<String>? eventAt,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (recurringItemId != null) 'recurring_item_id': recurringItemId,
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (action != null) 'action': action,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (eventOn != null) 'event_on': eventOn,
      if (eventAt != null) 'event_at': eventAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecurringOverridesCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? recurringItemId,
    Value<String>? occurrenceKey,
    Value<String>? action,
    Value<int?>? amountMinor,
    Value<String?>? eventOn,
    Value<String?>? eventAt,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return RecurringOverridesCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      recurringItemId: recurringItemId ?? this.recurringItemId,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      action: action ?? this.action,
      amountMinor: amountMinor ?? this.amountMinor,
      eventOn: eventOn ?? this.eventOn,
      eventAt: eventAt ?? this.eventAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (recurringItemId.present) {
      map['recurring_item_id'] = Variable<String>(recurringItemId.value);
    }
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (eventOn.present) {
      map['event_on'] = Variable<String>(eventOn.value);
    }
    if (eventAt.present) {
      map['event_at'] = Variable<String>(eventAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecurringOverridesCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('recurringItemId: $recurringItemId, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('action: $action, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('eventOn: $eventOn, ')
          ..write('eventAt: $eventAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScenariosTable extends Scenarios
    with TableInfo<$ScenariosTable, ScenarioRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScenariosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _includeExpectedMeta = const VerificationMeta(
    'includeExpected',
  );
  @override
  late final GeneratedColumn<bool> includeExpected = GeneratedColumn<bool>(
    'include_expected',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_expected" IN (0, 1))',
    ),
  );
  static const VerificationMeta _incomeDelayDaysMeta = const VerificationMeta(
    'incomeDelayDays',
  );
  @override
  late final GeneratedColumn<int> incomeDelayDays = GeneratedColumn<int>(
    'income_delay_days',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _incomeScaleMeta = const VerificationMeta(
    'incomeScale',
  );
  @override
  late final GeneratedColumn<String> incomeScale = GeneratedColumn<String>(
    'income_scale',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('1'),
  );
  static const VerificationMeta _expenseScaleMeta = const VerificationMeta(
    'expenseScale',
  );
  @override
  late final GeneratedColumn<String> expenseScale = GeneratedColumn<String>(
    'expense_scale',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('1'),
  );
  static const VerificationMeta _sameDayOrderMeta = const VerificationMeta(
    'sameDayOrder',
  );
  @override
  late final GeneratedColumn<String> sameDayOrder = GeneratedColumn<String>(
    'same_day_order',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('conservative'),
  );
  static const VerificationMeta _limitChangesMeta = const VerificationMeta(
    'limitChanges',
  );
  @override
  late final GeneratedColumn<String> limitChanges = GeneratedColumn<String>(
    'limit_changes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _eventOverridesMeta = const VerificationMeta(
    'eventOverrides',
  );
  @override
  late final GeneratedColumn<String> eventOverrides = GeneratedColumn<String>(
    'event_overrides',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    name,
    kind,
    includeExpected,
    incomeDelayDays,
    incomeScale,
    expenseScale,
    sameDayOrder,
    limitChanges,
    eventOverrides,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scenarios';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScenarioRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('include_expected')) {
      context.handle(
        _includeExpectedMeta,
        includeExpected.isAcceptableOrUnknown(
          data['include_expected']!,
          _includeExpectedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_includeExpectedMeta);
    }
    if (data.containsKey('income_delay_days')) {
      context.handle(
        _incomeDelayDaysMeta,
        incomeDelayDays.isAcceptableOrUnknown(
          data['income_delay_days']!,
          _incomeDelayDaysMeta,
        ),
      );
    }
    if (data.containsKey('income_scale')) {
      context.handle(
        _incomeScaleMeta,
        incomeScale.isAcceptableOrUnknown(
          data['income_scale']!,
          _incomeScaleMeta,
        ),
      );
    }
    if (data.containsKey('expense_scale')) {
      context.handle(
        _expenseScaleMeta,
        expenseScale.isAcceptableOrUnknown(
          data['expense_scale']!,
          _expenseScaleMeta,
        ),
      );
    }
    if (data.containsKey('same_day_order')) {
      context.handle(
        _sameDayOrderMeta,
        sameDayOrder.isAcceptableOrUnknown(
          data['same_day_order']!,
          _sameDayOrderMeta,
        ),
      );
    }
    if (data.containsKey('limit_changes')) {
      context.handle(
        _limitChangesMeta,
        limitChanges.isAcceptableOrUnknown(
          data['limit_changes']!,
          _limitChangesMeta,
        ),
      );
    }
    if (data.containsKey('event_overrides')) {
      context.handle(
        _eventOverridesMeta,
        eventOverrides.isAcceptableOrUnknown(
          data['event_overrides']!,
          _eventOverridesMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, name},
  ];
  @override
  ScenarioRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScenarioRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      includeExpected: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_expected'],
      )!,
      incomeDelayDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}income_delay_days'],
      )!,
      incomeScale: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}income_scale'],
      )!,
      expenseScale: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_scale'],
      )!,
      sameDayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}same_day_order'],
      )!,
      limitChanges: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}limit_changes'],
      )!,
      eventOverrides: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_overrides'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ScenariosTable createAlias(String alias) {
    return $ScenariosTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class ScenarioRow extends DataClass implements Insertable<ScenarioRow> {
  final String id;
  final String workspaceId;
  final String name;

  /// `builtin_confirmed` / `builtin_baseline` / `user_stress`。
  final String kind;
  final bool includeExpected;
  final int incomeDelayDays;
  final String incomeScale;
  final String expenseScale;

  /// `conservative` / `timestamp`。
  final String sameDayOrder;

  /// `[{"credit_account_id", "on", "change_minor"}]`。
  final String limitChanges;

  /// `[{"event_id", "on"?, "amount_minor"?}]`。
  final String eventOverrides;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const ScenarioRow({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.kind,
    required this.includeExpected,
    required this.incomeDelayDays,
    required this.incomeScale,
    required this.expenseScale,
    required this.sameDayOrder,
    required this.limitChanges,
    required this.eventOverrides,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['include_expected'] = Variable<bool>(includeExpected);
    map['income_delay_days'] = Variable<int>(incomeDelayDays);
    map['income_scale'] = Variable<String>(incomeScale);
    map['expense_scale'] = Variable<String>(expenseScale);
    map['same_day_order'] = Variable<String>(sameDayOrder);
    map['limit_changes'] = Variable<String>(limitChanges);
    map['event_overrides'] = Variable<String>(eventOverrides);
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ScenariosCompanion toCompanion(bool nullToAbsent) {
    return ScenariosCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      name: Value(name),
      kind: Value(kind),
      includeExpected: Value(includeExpected),
      incomeDelayDays: Value(incomeDelayDays),
      incomeScale: Value(incomeScale),
      expenseScale: Value(expenseScale),
      sameDayOrder: Value(sameDayOrder),
      limitChanges: Value(limitChanges),
      eventOverrides: Value(eventOverrides),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScenarioRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScenarioRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      includeExpected: serializer.fromJson<bool>(json['includeExpected']),
      incomeDelayDays: serializer.fromJson<int>(json['incomeDelayDays']),
      incomeScale: serializer.fromJson<String>(json['incomeScale']),
      expenseScale: serializer.fromJson<String>(json['expenseScale']),
      sameDayOrder: serializer.fromJson<String>(json['sameDayOrder']),
      limitChanges: serializer.fromJson<String>(json['limitChanges']),
      eventOverrides: serializer.fromJson<String>(json['eventOverrides']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'includeExpected': serializer.toJson<bool>(includeExpected),
      'incomeDelayDays': serializer.toJson<int>(incomeDelayDays),
      'incomeScale': serializer.toJson<String>(incomeScale),
      'expenseScale': serializer.toJson<String>(expenseScale),
      'sameDayOrder': serializer.toJson<String>(sameDayOrder),
      'limitChanges': serializer.toJson<String>(limitChanges),
      'eventOverrides': serializer.toJson<String>(eventOverrides),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ScenarioRow copyWith({
    String? id,
    String? workspaceId,
    String? name,
    String? kind,
    bool? includeExpected,
    int? incomeDelayDays,
    String? incomeScale,
    String? expenseScale,
    String? sameDayOrder,
    String? limitChanges,
    String? eventOverrides,
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => ScenarioRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    includeExpected: includeExpected ?? this.includeExpected,
    incomeDelayDays: incomeDelayDays ?? this.incomeDelayDays,
    incomeScale: incomeScale ?? this.incomeScale,
    expenseScale: expenseScale ?? this.expenseScale,
    sameDayOrder: sameDayOrder ?? this.sameDayOrder,
    limitChanges: limitChanges ?? this.limitChanges,
    eventOverrides: eventOverrides ?? this.eventOverrides,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScenarioRow copyWithCompanion(ScenariosCompanion data) {
    return ScenarioRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      includeExpected: data.includeExpected.present
          ? data.includeExpected.value
          : this.includeExpected,
      incomeDelayDays: data.incomeDelayDays.present
          ? data.incomeDelayDays.value
          : this.incomeDelayDays,
      incomeScale: data.incomeScale.present
          ? data.incomeScale.value
          : this.incomeScale,
      expenseScale: data.expenseScale.present
          ? data.expenseScale.value
          : this.expenseScale,
      sameDayOrder: data.sameDayOrder.present
          ? data.sameDayOrder.value
          : this.sameDayOrder,
      limitChanges: data.limitChanges.present
          ? data.limitChanges.value
          : this.limitChanges,
      eventOverrides: data.eventOverrides.present
          ? data.eventOverrides.value
          : this.eventOverrides,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScenarioRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('includeExpected: $includeExpected, ')
          ..write('incomeDelayDays: $incomeDelayDays, ')
          ..write('incomeScale: $incomeScale, ')
          ..write('expenseScale: $expenseScale, ')
          ..write('sameDayOrder: $sameDayOrder, ')
          ..write('limitChanges: $limitChanges, ')
          ..write('eventOverrides: $eventOverrides, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    name,
    kind,
    includeExpected,
    incomeDelayDays,
    incomeScale,
    expenseScale,
    sameDayOrder,
    limitChanges,
    eventOverrides,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScenarioRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.includeExpected == this.includeExpected &&
          other.incomeDelayDays == this.incomeDelayDays &&
          other.incomeScale == this.incomeScale &&
          other.expenseScale == this.expenseScale &&
          other.sameDayOrder == this.sameDayOrder &&
          other.limitChanges == this.limitChanges &&
          other.eventOverrides == this.eventOverrides &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ScenariosCompanion extends UpdateCompanion<ScenarioRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> name;
  final Value<String> kind;
  final Value<bool> includeExpected;
  final Value<int> incomeDelayDays;
  final Value<String> incomeScale;
  final Value<String> expenseScale;
  final Value<String> sameDayOrder;
  final Value<String> limitChanges;
  final Value<String> eventOverrides;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ScenariosCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.includeExpected = const Value.absent(),
    this.incomeDelayDays = const Value.absent(),
    this.incomeScale = const Value.absent(),
    this.expenseScale = const Value.absent(),
    this.sameDayOrder = const Value.absent(),
    this.limitChanges = const Value.absent(),
    this.eventOverrides = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScenariosCompanion.insert({
    required String id,
    required String workspaceId,
    required String name,
    required String kind,
    required bool includeExpected,
    this.incomeDelayDays = const Value.absent(),
    this.incomeScale = const Value.absent(),
    this.expenseScale = const Value.absent(),
    this.sameDayOrder = const Value.absent(),
    this.limitChanges = const Value.absent(),
    this.eventOverrides = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       name = Value(name),
       kind = Value(kind),
       includeExpected = Value(includeExpected),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ScenarioRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<bool>? includeExpected,
    Expression<int>? incomeDelayDays,
    Expression<String>? incomeScale,
    Expression<String>? expenseScale,
    Expression<String>? sameDayOrder,
    Expression<String>? limitChanges,
    Expression<String>? eventOverrides,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (includeExpected != null) 'include_expected': includeExpected,
      if (incomeDelayDays != null) 'income_delay_days': incomeDelayDays,
      if (incomeScale != null) 'income_scale': incomeScale,
      if (expenseScale != null) 'expense_scale': expenseScale,
      if (sameDayOrder != null) 'same_day_order': sameDayOrder,
      if (limitChanges != null) 'limit_changes': limitChanges,
      if (eventOverrides != null) 'event_overrides': eventOverrides,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScenariosCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? name,
    Value<String>? kind,
    Value<bool>? includeExpected,
    Value<int>? incomeDelayDays,
    Value<String>? incomeScale,
    Value<String>? expenseScale,
    Value<String>? sameDayOrder,
    Value<String>? limitChanges,
    Value<String>? eventOverrides,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ScenariosCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      includeExpected: includeExpected ?? this.includeExpected,
      incomeDelayDays: incomeDelayDays ?? this.incomeDelayDays,
      incomeScale: incomeScale ?? this.incomeScale,
      expenseScale: expenseScale ?? this.expenseScale,
      sameDayOrder: sameDayOrder ?? this.sameDayOrder,
      limitChanges: limitChanges ?? this.limitChanges,
      eventOverrides: eventOverrides ?? this.eventOverrides,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (includeExpected.present) {
      map['include_expected'] = Variable<bool>(includeExpected.value);
    }
    if (incomeDelayDays.present) {
      map['income_delay_days'] = Variable<int>(incomeDelayDays.value);
    }
    if (incomeScale.present) {
      map['income_scale'] = Variable<String>(incomeScale.value);
    }
    if (expenseScale.present) {
      map['expense_scale'] = Variable<String>(expenseScale.value);
    }
    if (sameDayOrder.present) {
      map['same_day_order'] = Variable<String>(sameDayOrder.value);
    }
    if (limitChanges.present) {
      map['limit_changes'] = Variable<String>(limitChanges.value);
    }
    if (eventOverrides.present) {
      map['event_overrides'] = Variable<String>(eventOverrides.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScenariosCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('includeExpected: $includeExpected, ')
          ..write('incomeDelayDays: $incomeDelayDays, ')
          ..write('incomeScale: $incomeScale, ')
          ..write('expenseScale: $expenseScale, ')
          ..write('sameDayOrder: $sameDayOrder, ')
          ..write('limitChanges: $limitChanges, ')
          ..write('eventOverrides: $eventOverrides, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScenarioRunsTable extends ScenarioRuns
    with TableInfo<$ScenarioRunsTable, ScenarioRunRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScenarioRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scenarioIdMeta = const VerificationMeta(
    'scenarioId',
  );
  @override
  late final GeneratedColumn<String> scenarioId = GeneratedColumn<String>(
    'scenario_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionNoMeta = const VerificationMeta(
    'versionNo',
  );
  @override
  late final GeneratedColumn<int> versionNo = GeneratedColumn<int>(
    'version_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _computedAtMeta = const VerificationMeta(
    'computedAt',
  );
  @override
  late final GeneratedColumn<String> computedAt = GeneratedColumn<String>(
    'computed_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _horizonFromMeta = const VerificationMeta(
    'horizonFrom',
  );
  @override
  late final GeneratedColumn<String> horizonFrom = GeneratedColumn<String>(
    'horizon_from',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _horizonToMeta = const VerificationMeta(
    'horizonTo',
  );
  @override
  late final GeneratedColumn<String> horizonTo = GeneratedColumn<String>(
    'horizon_to',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputsHashMeta = const VerificationMeta(
    'inputsHash',
  );
  @override
  late final GeneratedColumn<String> inputsHash = GeneratedColumn<String>(
    'inputs_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resultMeta = const VerificationMeta('result');
  @override
  late final GeneratedColumn<String> result = GeneratedColumn<String>(
    'result',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    scenarioId,
    versionNo,
    computedAt,
    horizonFrom,
    horizonTo,
    inputsHash,
    result,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scenario_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScenarioRunRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('scenario_id')) {
      context.handle(
        _scenarioIdMeta,
        scenarioId.isAcceptableOrUnknown(data['scenario_id']!, _scenarioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scenarioIdMeta);
    }
    if (data.containsKey('version_no')) {
      context.handle(
        _versionNoMeta,
        versionNo.isAcceptableOrUnknown(data['version_no']!, _versionNoMeta),
      );
    } else if (isInserting) {
      context.missing(_versionNoMeta);
    }
    if (data.containsKey('computed_at')) {
      context.handle(
        _computedAtMeta,
        computedAt.isAcceptableOrUnknown(data['computed_at']!, _computedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_computedAtMeta);
    }
    if (data.containsKey('horizon_from')) {
      context.handle(
        _horizonFromMeta,
        horizonFrom.isAcceptableOrUnknown(
          data['horizon_from']!,
          _horizonFromMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_horizonFromMeta);
    }
    if (data.containsKey('horizon_to')) {
      context.handle(
        _horizonToMeta,
        horizonTo.isAcceptableOrUnknown(data['horizon_to']!, _horizonToMeta),
      );
    } else if (isInserting) {
      context.missing(_horizonToMeta);
    }
    if (data.containsKey('inputs_hash')) {
      context.handle(
        _inputsHashMeta,
        inputsHash.isAcceptableOrUnknown(data['inputs_hash']!, _inputsHashMeta),
      );
    } else if (isInserting) {
      context.missing(_inputsHashMeta);
    }
    if (data.containsKey('result')) {
      context.handle(
        _resultMeta,
        result.isAcceptableOrUnknown(data['result']!, _resultMeta),
      );
    } else if (isInserting) {
      context.missing(_resultMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {scenarioId, versionNo},
  ];
  @override
  ScenarioRunRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScenarioRunRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      scenarioId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scenario_id'],
      )!,
      versionNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_no'],
      )!,
      computedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}computed_at'],
      )!,
      horizonFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}horizon_from'],
      )!,
      horizonTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}horizon_to'],
      )!,
      inputsHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inputs_hash'],
      )!,
      result: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result'],
      )!,
    );
  }

  @override
  $ScenarioRunsTable createAlias(String alias) {
    return $ScenarioRunsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class ScenarioRunRow extends DataClass implements Insertable<ScenarioRunRow> {
  final String id;
  final String workspaceId;
  final String scenarioId;
  final int versionNo;
  final String computedAt;
  final String horizonFrom;
  final String horizonTo;

  /// 输入的 sha256（小写十六进制）：与当前输入不同即"过期"。
  final String inputsHash;
  final String result;
  const ScenarioRunRow({
    required this.id,
    required this.workspaceId,
    required this.scenarioId,
    required this.versionNo,
    required this.computedAt,
    required this.horizonFrom,
    required this.horizonTo,
    required this.inputsHash,
    required this.result,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['scenario_id'] = Variable<String>(scenarioId);
    map['version_no'] = Variable<int>(versionNo);
    map['computed_at'] = Variable<String>(computedAt);
    map['horizon_from'] = Variable<String>(horizonFrom);
    map['horizon_to'] = Variable<String>(horizonTo);
    map['inputs_hash'] = Variable<String>(inputsHash);
    map['result'] = Variable<String>(result);
    return map;
  }

  ScenarioRunsCompanion toCompanion(bool nullToAbsent) {
    return ScenarioRunsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      scenarioId: Value(scenarioId),
      versionNo: Value(versionNo),
      computedAt: Value(computedAt),
      horizonFrom: Value(horizonFrom),
      horizonTo: Value(horizonTo),
      inputsHash: Value(inputsHash),
      result: Value(result),
    );
  }

  factory ScenarioRunRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScenarioRunRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      scenarioId: serializer.fromJson<String>(json['scenarioId']),
      versionNo: serializer.fromJson<int>(json['versionNo']),
      computedAt: serializer.fromJson<String>(json['computedAt']),
      horizonFrom: serializer.fromJson<String>(json['horizonFrom']),
      horizonTo: serializer.fromJson<String>(json['horizonTo']),
      inputsHash: serializer.fromJson<String>(json['inputsHash']),
      result: serializer.fromJson<String>(json['result']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'scenarioId': serializer.toJson<String>(scenarioId),
      'versionNo': serializer.toJson<int>(versionNo),
      'computedAt': serializer.toJson<String>(computedAt),
      'horizonFrom': serializer.toJson<String>(horizonFrom),
      'horizonTo': serializer.toJson<String>(horizonTo),
      'inputsHash': serializer.toJson<String>(inputsHash),
      'result': serializer.toJson<String>(result),
    };
  }

  ScenarioRunRow copyWith({
    String? id,
    String? workspaceId,
    String? scenarioId,
    int? versionNo,
    String? computedAt,
    String? horizonFrom,
    String? horizonTo,
    String? inputsHash,
    String? result,
  }) => ScenarioRunRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    scenarioId: scenarioId ?? this.scenarioId,
    versionNo: versionNo ?? this.versionNo,
    computedAt: computedAt ?? this.computedAt,
    horizonFrom: horizonFrom ?? this.horizonFrom,
    horizonTo: horizonTo ?? this.horizonTo,
    inputsHash: inputsHash ?? this.inputsHash,
    result: result ?? this.result,
  );
  ScenarioRunRow copyWithCompanion(ScenarioRunsCompanion data) {
    return ScenarioRunRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      scenarioId: data.scenarioId.present
          ? data.scenarioId.value
          : this.scenarioId,
      versionNo: data.versionNo.present ? data.versionNo.value : this.versionNo,
      computedAt: data.computedAt.present
          ? data.computedAt.value
          : this.computedAt,
      horizonFrom: data.horizonFrom.present
          ? data.horizonFrom.value
          : this.horizonFrom,
      horizonTo: data.horizonTo.present ? data.horizonTo.value : this.horizonTo,
      inputsHash: data.inputsHash.present
          ? data.inputsHash.value
          : this.inputsHash,
      result: data.result.present ? data.result.value : this.result,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScenarioRunRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('scenarioId: $scenarioId, ')
          ..write('versionNo: $versionNo, ')
          ..write('computedAt: $computedAt, ')
          ..write('horizonFrom: $horizonFrom, ')
          ..write('horizonTo: $horizonTo, ')
          ..write('inputsHash: $inputsHash, ')
          ..write('result: $result')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    scenarioId,
    versionNo,
    computedAt,
    horizonFrom,
    horizonTo,
    inputsHash,
    result,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScenarioRunRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.scenarioId == this.scenarioId &&
          other.versionNo == this.versionNo &&
          other.computedAt == this.computedAt &&
          other.horizonFrom == this.horizonFrom &&
          other.horizonTo == this.horizonTo &&
          other.inputsHash == this.inputsHash &&
          other.result == this.result);
}

class ScenarioRunsCompanion extends UpdateCompanion<ScenarioRunRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> scenarioId;
  final Value<int> versionNo;
  final Value<String> computedAt;
  final Value<String> horizonFrom;
  final Value<String> horizonTo;
  final Value<String> inputsHash;
  final Value<String> result;
  final Value<int> rowid;
  const ScenarioRunsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.scenarioId = const Value.absent(),
    this.versionNo = const Value.absent(),
    this.computedAt = const Value.absent(),
    this.horizonFrom = const Value.absent(),
    this.horizonTo = const Value.absent(),
    this.inputsHash = const Value.absent(),
    this.result = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScenarioRunsCompanion.insert({
    required String id,
    required String workspaceId,
    required String scenarioId,
    required int versionNo,
    required String computedAt,
    required String horizonFrom,
    required String horizonTo,
    required String inputsHash,
    required String result,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       scenarioId = Value(scenarioId),
       versionNo = Value(versionNo),
       computedAt = Value(computedAt),
       horizonFrom = Value(horizonFrom),
       horizonTo = Value(horizonTo),
       inputsHash = Value(inputsHash),
       result = Value(result);
  static Insertable<ScenarioRunRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? scenarioId,
    Expression<int>? versionNo,
    Expression<String>? computedAt,
    Expression<String>? horizonFrom,
    Expression<String>? horizonTo,
    Expression<String>? inputsHash,
    Expression<String>? result,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (scenarioId != null) 'scenario_id': scenarioId,
      if (versionNo != null) 'version_no': versionNo,
      if (computedAt != null) 'computed_at': computedAt,
      if (horizonFrom != null) 'horizon_from': horizonFrom,
      if (horizonTo != null) 'horizon_to': horizonTo,
      if (inputsHash != null) 'inputs_hash': inputsHash,
      if (result != null) 'result': result,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScenarioRunsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? scenarioId,
    Value<int>? versionNo,
    Value<String>? computedAt,
    Value<String>? horizonFrom,
    Value<String>? horizonTo,
    Value<String>? inputsHash,
    Value<String>? result,
    Value<int>? rowid,
  }) {
    return ScenarioRunsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      scenarioId: scenarioId ?? this.scenarioId,
      versionNo: versionNo ?? this.versionNo,
      computedAt: computedAt ?? this.computedAt,
      horizonFrom: horizonFrom ?? this.horizonFrom,
      horizonTo: horizonTo ?? this.horizonTo,
      inputsHash: inputsHash ?? this.inputsHash,
      result: result ?? this.result,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (scenarioId.present) {
      map['scenario_id'] = Variable<String>(scenarioId.value);
    }
    if (versionNo.present) {
      map['version_no'] = Variable<int>(versionNo.value);
    }
    if (computedAt.present) {
      map['computed_at'] = Variable<String>(computedAt.value);
    }
    if (horizonFrom.present) {
      map['horizon_from'] = Variable<String>(horizonFrom.value);
    }
    if (horizonTo.present) {
      map['horizon_to'] = Variable<String>(horizonTo.value);
    }
    if (inputsHash.present) {
      map['inputs_hash'] = Variable<String>(inputsHash.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(result.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScenarioRunsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('scenarioId: $scenarioId, ')
          ..write('versionNo: $versionNo, ')
          ..write('computedAt: $computedAt, ')
          ..write('horizonFrom: $horizonFrom, ')
          ..write('horizonTo: $horizonTo, ')
          ..write('inputsHash: $inputsHash, ')
          ..write('result: $result, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardTransactionsTable extends CardTransactions
    with TableInfo<$CardTransactionsTable, CardTransactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _txnTypeMeta = const VerificationMeta(
    'txnType',
  );
  @override
  late final GeneratedColumn<String> txnType = GeneratedColumn<String>(
    'txn_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _txnAtMeta = const VerificationMeta('txnAt');
  @override
  late final GeneratedColumn<String> txnAt = GeneratedColumn<String>(
    'txn_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _txnTzMeta = const VerificationMeta('txnTz');
  @override
  late final GeneratedColumn<String> txnTz = GeneratedColumn<String>(
    'txn_tz',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timePrecisionMeta = const VerificationMeta(
    'timePrecision',
  );
  @override
  late final GeneratedColumn<String> timePrecision = GeneratedColumn<String>(
    'time_precision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _postedOnMeta = const VerificationMeta(
    'postedOn',
  );
  @override
  late final GeneratedColumn<String> postedOn = GeneratedColumn<String>(
    'posted_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _merchantMeta = const VerificationMeta(
    'merchant',
  );
  @override
  late final GeneratedColumn<String> merchant = GeneratedColumn<String>(
    'merchant',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentTransactionIdMeta =
      const VerificationMeta('parentTransactionId');
  @override
  late final GeneratedColumn<String> parentTransactionId =
      GeneratedColumn<String>(
        'parent_transaction_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmationLevelMeta = const VerificationMeta(
    'confirmationLevel',
  );
  @override
  late final GeneratedColumn<String> confirmationLevel =
      GeneratedColumn<String>(
        'confirmation_level',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<String> recordedAt = GeneratedColumn<String>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    currencyAccountId,
    cardId,
    txnType,
    amountMinor,
    currency,
    txnAt,
    txnTz,
    timePrecision,
    postedOn,
    merchant,
    category,
    status,
    parentTransactionId,
    fingerprint,
    sourceKind,
    confirmationLevel,
    rowVersion,
    recordedAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardTransactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    }
    if (data.containsKey('txn_type')) {
      context.handle(
        _txnTypeMeta,
        txnType.isAcceptableOrUnknown(data['txn_type']!, _txnTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_txnTypeMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('txn_at')) {
      context.handle(
        _txnAtMeta,
        txnAt.isAcceptableOrUnknown(data['txn_at']!, _txnAtMeta),
      );
    } else if (isInserting) {
      context.missing(_txnAtMeta);
    }
    if (data.containsKey('txn_tz')) {
      context.handle(
        _txnTzMeta,
        txnTz.isAcceptableOrUnknown(data['txn_tz']!, _txnTzMeta),
      );
    } else if (isInserting) {
      context.missing(_txnTzMeta);
    }
    if (data.containsKey('time_precision')) {
      context.handle(
        _timePrecisionMeta,
        timePrecision.isAcceptableOrUnknown(
          data['time_precision']!,
          _timePrecisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timePrecisionMeta);
    }
    if (data.containsKey('posted_on')) {
      context.handle(
        _postedOnMeta,
        postedOn.isAcceptableOrUnknown(data['posted_on']!, _postedOnMeta),
      );
    }
    if (data.containsKey('merchant')) {
      context.handle(
        _merchantMeta,
        merchant.isAcceptableOrUnknown(data['merchant']!, _merchantMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('parent_transaction_id')) {
      context.handle(
        _parentTransactionIdMeta,
        parentTransactionId.isAcceptableOrUnknown(
          data['parent_transaction_id']!,
          _parentTransactionIdMeta,
        ),
      );
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('confirmation_level')) {
      context.handle(
        _confirmationLevelMeta,
        confirmationLevel.isAcceptableOrUnknown(
          data['confirmation_level']!,
          _confirmationLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmationLevelMeta);
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, currencyAccountId, id},
  ];
  @override
  CardTransactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardTransactionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      ),
      txnType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_type'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      txnAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_at'],
      )!,
      txnTz: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}txn_tz'],
      )!,
      timePrecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}time_precision'],
      )!,
      postedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}posted_on'],
      ),
      merchant: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merchant'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      parentTransactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_transaction_id'],
      ),
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      confirmationLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}confirmation_level'],
      )!,
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $CardTransactionsTable createAlias(String alias) {
    return $CardTransactionsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class CardTransactionRow extends DataClass
    implements Insertable<CardTransactionRow> {
  final String id;
  final String workspaceId;
  final String currencyAccountId;
  final String? cardId;

  /// `purchase` / `refund` / `repayment` / `transfer` / `fee` / `interest` /
  /// `installment_principal` / `installment_fee` / `adjustment`。
  final String txnType;
  final int amountMinor;
  final String currency;

  /// 交易时点（RFC 3339，按 [txnTz] 的偏移写出）。
  final String txnAt;

  /// 交易的业务时区（信用账户的 `business_tz`）。
  final String txnTz;

  /// `datetime` / `date` / `month`。
  final String timePrecision;

  /// 银行入账日；空 = 还不知道（按入账延迟区间给出"可能账期"，F-15）。
  final String? postedOn;
  final String? merchant;
  final String? category;

  /// `pending` / `posted` / `reversed`。
  final String status;

  /// 退款、冲正指向的原交易（同一币种子账户）。
  final String? parentTransactionId;
  final String fingerprint;

  /// `manual` / `import`。
  final String sourceKind;

  /// `system_estimated` / `user_confirmed` / `bank_confirmed`。
  final String confirmationLevel;
  final int rowVersion;
  final String recordedAt;
  final String updatedAt;
  final String? deletedAt;
  const CardTransactionRow({
    required this.id,
    required this.workspaceId,
    required this.currencyAccountId,
    this.cardId,
    required this.txnType,
    required this.amountMinor,
    required this.currency,
    required this.txnAt,
    required this.txnTz,
    required this.timePrecision,
    this.postedOn,
    this.merchant,
    this.category,
    required this.status,
    this.parentTransactionId,
    required this.fingerprint,
    required this.sourceKind,
    required this.confirmationLevel,
    required this.rowVersion,
    required this.recordedAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    if (!nullToAbsent || cardId != null) {
      map['card_id'] = Variable<String>(cardId);
    }
    map['txn_type'] = Variable<String>(txnType);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['currency'] = Variable<String>(currency);
    map['txn_at'] = Variable<String>(txnAt);
    map['txn_tz'] = Variable<String>(txnTz);
    map['time_precision'] = Variable<String>(timePrecision);
    if (!nullToAbsent || postedOn != null) {
      map['posted_on'] = Variable<String>(postedOn);
    }
    if (!nullToAbsent || merchant != null) {
      map['merchant'] = Variable<String>(merchant);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || parentTransactionId != null) {
      map['parent_transaction_id'] = Variable<String>(parentTransactionId);
    }
    map['fingerprint'] = Variable<String>(fingerprint);
    map['source_kind'] = Variable<String>(sourceKind);
    map['confirmation_level'] = Variable<String>(confirmationLevel);
    map['row_version'] = Variable<int>(rowVersion);
    map['recorded_at'] = Variable<String>(recordedAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  CardTransactionsCompanion toCompanion(bool nullToAbsent) {
    return CardTransactionsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      cardId: cardId == null && nullToAbsent
          ? const Value.absent()
          : Value(cardId),
      txnType: Value(txnType),
      amountMinor: Value(amountMinor),
      currency: Value(currency),
      txnAt: Value(txnAt),
      txnTz: Value(txnTz),
      timePrecision: Value(timePrecision),
      postedOn: postedOn == null && nullToAbsent
          ? const Value.absent()
          : Value(postedOn),
      merchant: merchant == null && nullToAbsent
          ? const Value.absent()
          : Value(merchant),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      status: Value(status),
      parentTransactionId: parentTransactionId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentTransactionId),
      fingerprint: Value(fingerprint),
      sourceKind: Value(sourceKind),
      confirmationLevel: Value(confirmationLevel),
      rowVersion: Value(rowVersion),
      recordedAt: Value(recordedAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory CardTransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardTransactionRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      cardId: serializer.fromJson<String?>(json['cardId']),
      txnType: serializer.fromJson<String>(json['txnType']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      txnAt: serializer.fromJson<String>(json['txnAt']),
      txnTz: serializer.fromJson<String>(json['txnTz']),
      timePrecision: serializer.fromJson<String>(json['timePrecision']),
      postedOn: serializer.fromJson<String?>(json['postedOn']),
      merchant: serializer.fromJson<String?>(json['merchant']),
      category: serializer.fromJson<String?>(json['category']),
      status: serializer.fromJson<String>(json['status']),
      parentTransactionId: serializer.fromJson<String?>(
        json['parentTransactionId'],
      ),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      confirmationLevel: serializer.fromJson<String>(json['confirmationLevel']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      recordedAt: serializer.fromJson<String>(json['recordedAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'cardId': serializer.toJson<String?>(cardId),
      'txnType': serializer.toJson<String>(txnType),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'currency': serializer.toJson<String>(currency),
      'txnAt': serializer.toJson<String>(txnAt),
      'txnTz': serializer.toJson<String>(txnTz),
      'timePrecision': serializer.toJson<String>(timePrecision),
      'postedOn': serializer.toJson<String?>(postedOn),
      'merchant': serializer.toJson<String?>(merchant),
      'category': serializer.toJson<String?>(category),
      'status': serializer.toJson<String>(status),
      'parentTransactionId': serializer.toJson<String?>(parentTransactionId),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'confirmationLevel': serializer.toJson<String>(confirmationLevel),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'recordedAt': serializer.toJson<String>(recordedAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  CardTransactionRow copyWith({
    String? id,
    String? workspaceId,
    String? currencyAccountId,
    Value<String?> cardId = const Value.absent(),
    String? txnType,
    int? amountMinor,
    String? currency,
    String? txnAt,
    String? txnTz,
    String? timePrecision,
    Value<String?> postedOn = const Value.absent(),
    Value<String?> merchant = const Value.absent(),
    Value<String?> category = const Value.absent(),
    String? status,
    Value<String?> parentTransactionId = const Value.absent(),
    String? fingerprint,
    String? sourceKind,
    String? confirmationLevel,
    int? rowVersion,
    String? recordedAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => CardTransactionRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    cardId: cardId.present ? cardId.value : this.cardId,
    txnType: txnType ?? this.txnType,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    txnAt: txnAt ?? this.txnAt,
    txnTz: txnTz ?? this.txnTz,
    timePrecision: timePrecision ?? this.timePrecision,
    postedOn: postedOn.present ? postedOn.value : this.postedOn,
    merchant: merchant.present ? merchant.value : this.merchant,
    category: category.present ? category.value : this.category,
    status: status ?? this.status,
    parentTransactionId: parentTransactionId.present
        ? parentTransactionId.value
        : this.parentTransactionId,
    fingerprint: fingerprint ?? this.fingerprint,
    sourceKind: sourceKind ?? this.sourceKind,
    confirmationLevel: confirmationLevel ?? this.confirmationLevel,
    rowVersion: rowVersion ?? this.rowVersion,
    recordedAt: recordedAt ?? this.recordedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  CardTransactionRow copyWithCompanion(CardTransactionsCompanion data) {
    return CardTransactionRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      txnType: data.txnType.present ? data.txnType.value : this.txnType,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      txnAt: data.txnAt.present ? data.txnAt.value : this.txnAt,
      txnTz: data.txnTz.present ? data.txnTz.value : this.txnTz,
      timePrecision: data.timePrecision.present
          ? data.timePrecision.value
          : this.timePrecision,
      postedOn: data.postedOn.present ? data.postedOn.value : this.postedOn,
      merchant: data.merchant.present ? data.merchant.value : this.merchant,
      category: data.category.present ? data.category.value : this.category,
      status: data.status.present ? data.status.value : this.status,
      parentTransactionId: data.parentTransactionId.present
          ? data.parentTransactionId.value
          : this.parentTransactionId,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      confirmationLevel: data.confirmationLevel.present
          ? data.confirmationLevel.value
          : this.confirmationLevel,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardTransactionRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('cardId: $cardId, ')
          ..write('txnType: $txnType, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('txnAt: $txnAt, ')
          ..write('txnTz: $txnTz, ')
          ..write('timePrecision: $timePrecision, ')
          ..write('postedOn: $postedOn, ')
          ..write('merchant: $merchant, ')
          ..write('category: $category, ')
          ..write('status: $status, ')
          ..write('parentTransactionId: $parentTransactionId, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('confirmationLevel: $confirmationLevel, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    workspaceId,
    currencyAccountId,
    cardId,
    txnType,
    amountMinor,
    currency,
    txnAt,
    txnTz,
    timePrecision,
    postedOn,
    merchant,
    category,
    status,
    parentTransactionId,
    fingerprint,
    sourceKind,
    confirmationLevel,
    rowVersion,
    recordedAt,
    updatedAt,
    deletedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardTransactionRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.cardId == this.cardId &&
          other.txnType == this.txnType &&
          other.amountMinor == this.amountMinor &&
          other.currency == this.currency &&
          other.txnAt == this.txnAt &&
          other.txnTz == this.txnTz &&
          other.timePrecision == this.timePrecision &&
          other.postedOn == this.postedOn &&
          other.merchant == this.merchant &&
          other.category == this.category &&
          other.status == this.status &&
          other.parentTransactionId == this.parentTransactionId &&
          other.fingerprint == this.fingerprint &&
          other.sourceKind == this.sourceKind &&
          other.confirmationLevel == this.confirmationLevel &&
          other.rowVersion == this.rowVersion &&
          other.recordedAt == this.recordedAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class CardTransactionsCompanion extends UpdateCompanion<CardTransactionRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<String?> cardId;
  final Value<String> txnType;
  final Value<int> amountMinor;
  final Value<String> currency;
  final Value<String> txnAt;
  final Value<String> txnTz;
  final Value<String> timePrecision;
  final Value<String?> postedOn;
  final Value<String?> merchant;
  final Value<String?> category;
  final Value<String> status;
  final Value<String?> parentTransactionId;
  final Value<String> fingerprint;
  final Value<String> sourceKind;
  final Value<String> confirmationLevel;
  final Value<int> rowVersion;
  final Value<String> recordedAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const CardTransactionsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.txnType = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.txnAt = const Value.absent(),
    this.txnTz = const Value.absent(),
    this.timePrecision = const Value.absent(),
    this.postedOn = const Value.absent(),
    this.merchant = const Value.absent(),
    this.category = const Value.absent(),
    this.status = const Value.absent(),
    this.parentTransactionId = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.confirmationLevel = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardTransactionsCompanion.insert({
    required String id,
    required String workspaceId,
    required String currencyAccountId,
    this.cardId = const Value.absent(),
    required String txnType,
    required int amountMinor,
    required String currency,
    required String txnAt,
    required String txnTz,
    required String timePrecision,
    this.postedOn = const Value.absent(),
    this.merchant = const Value.absent(),
    this.category = const Value.absent(),
    required String status,
    this.parentTransactionId = const Value.absent(),
    required String fingerprint,
    required String sourceKind,
    required String confirmationLevel,
    this.rowVersion = const Value.absent(),
    required String recordedAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       txnType = Value(txnType),
       amountMinor = Value(amountMinor),
       currency = Value(currency),
       txnAt = Value(txnAt),
       txnTz = Value(txnTz),
       timePrecision = Value(timePrecision),
       status = Value(status),
       fingerprint = Value(fingerprint),
       sourceKind = Value(sourceKind),
       confirmationLevel = Value(confirmationLevel),
       recordedAt = Value(recordedAt),
       updatedAt = Value(updatedAt);
  static Insertable<CardTransactionRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<String>? cardId,
    Expression<String>? txnType,
    Expression<int>? amountMinor,
    Expression<String>? currency,
    Expression<String>? txnAt,
    Expression<String>? txnTz,
    Expression<String>? timePrecision,
    Expression<String>? postedOn,
    Expression<String>? merchant,
    Expression<String>? category,
    Expression<String>? status,
    Expression<String>? parentTransactionId,
    Expression<String>? fingerprint,
    Expression<String>? sourceKind,
    Expression<String>? confirmationLevel,
    Expression<int>? rowVersion,
    Expression<String>? recordedAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (cardId != null) 'card_id': cardId,
      if (txnType != null) 'txn_type': txnType,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (currency != null) 'currency': currency,
      if (txnAt != null) 'txn_at': txnAt,
      if (txnTz != null) 'txn_tz': txnTz,
      if (timePrecision != null) 'time_precision': timePrecision,
      if (postedOn != null) 'posted_on': postedOn,
      if (merchant != null) 'merchant': merchant,
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (parentTransactionId != null)
        'parent_transaction_id': parentTransactionId,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (confirmationLevel != null) 'confirmation_level': confirmationLevel,
      if (rowVersion != null) 'row_version': rowVersion,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardTransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<String?>? cardId,
    Value<String>? txnType,
    Value<int>? amountMinor,
    Value<String>? currency,
    Value<String>? txnAt,
    Value<String>? txnTz,
    Value<String>? timePrecision,
    Value<String?>? postedOn,
    Value<String?>? merchant,
    Value<String?>? category,
    Value<String>? status,
    Value<String?>? parentTransactionId,
    Value<String>? fingerprint,
    Value<String>? sourceKind,
    Value<String>? confirmationLevel,
    Value<int>? rowVersion,
    Value<String>? recordedAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return CardTransactionsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      cardId: cardId ?? this.cardId,
      txnType: txnType ?? this.txnType,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      txnAt: txnAt ?? this.txnAt,
      txnTz: txnTz ?? this.txnTz,
      timePrecision: timePrecision ?? this.timePrecision,
      postedOn: postedOn ?? this.postedOn,
      merchant: merchant ?? this.merchant,
      category: category ?? this.category,
      status: status ?? this.status,
      parentTransactionId: parentTransactionId ?? this.parentTransactionId,
      fingerprint: fingerprint ?? this.fingerprint,
      sourceKind: sourceKind ?? this.sourceKind,
      confirmationLevel: confirmationLevel ?? this.confirmationLevel,
      rowVersion: rowVersion ?? this.rowVersion,
      recordedAt: recordedAt ?? this.recordedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (txnType.present) {
      map['txn_type'] = Variable<String>(txnType.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (txnAt.present) {
      map['txn_at'] = Variable<String>(txnAt.value);
    }
    if (txnTz.present) {
      map['txn_tz'] = Variable<String>(txnTz.value);
    }
    if (timePrecision.present) {
      map['time_precision'] = Variable<String>(timePrecision.value);
    }
    if (postedOn.present) {
      map['posted_on'] = Variable<String>(postedOn.value);
    }
    if (merchant.present) {
      map['merchant'] = Variable<String>(merchant.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (parentTransactionId.present) {
      map['parent_transaction_id'] = Variable<String>(
        parentTransactionId.value,
      );
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (confirmationLevel.present) {
      map['confirmation_level'] = Variable<String>(confirmationLevel.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<String>(recordedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('cardId: $cardId, ')
          ..write('txnType: $txnType, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('txnAt: $txnAt, ')
          ..write('txnTz: $txnTz, ')
          ..write('timePrecision: $timePrecision, ')
          ..write('postedOn: $postedOn, ')
          ..write('merchant: $merchant, ')
          ..write('category: $category, ')
          ..write('status: $status, ')
          ..write('parentTransactionId: $parentTransactionId, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('confirmationLevel: $confirmationLevel, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StatementVersionsTable extends StatementVersions
    with TableInfo<$StatementVersionsTable, StatementVersionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StatementVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statementIdMeta = const VerificationMeta(
    'statementId',
  );
  @override
  late final GeneratedColumn<String> statementId = GeneratedColumn<String>(
    'statement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionNoMeta = const VerificationMeta(
    'versionNo',
  );
  @override
  late final GeneratedColumn<int> versionNo = GeneratedColumn<int>(
    'version_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousBalanceMinorMeta =
      const VerificationMeta('previousBalanceMinor');
  @override
  late final GeneratedColumn<int> previousBalanceMinor = GeneratedColumn<int>(
    'previous_balance_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _newBalanceMinorMeta = const VerificationMeta(
    'newBalanceMinor',
  );
  @override
  late final GeneratedColumn<int> newBalanceMinor = GeneratedColumn<int>(
    'new_balance_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minDueMinorMeta = const VerificationMeta(
    'minDueMinor',
  );
  @override
  late final GeneratedColumn<int> minDueMinor = GeneratedColumn<int>(
    'min_due_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentsMinorMeta = const VerificationMeta(
    'paymentsMinor',
  );
  @override
  late final GeneratedColumn<int> paymentsMinor = GeneratedColumn<int>(
    'payments_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creditsMinorMeta = const VerificationMeta(
    'creditsMinor',
  );
  @override
  late final GeneratedColumn<int> creditsMinor = GeneratedColumn<int>(
    'credits_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feesMinorMeta = const VerificationMeta(
    'feesMinor',
  );
  @override
  late final GeneratedColumn<int> feesMinor = GeneratedColumn<int>(
    'fees_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interestMinorMeta = const VerificationMeta(
    'interestMinor',
  );
  @override
  late final GeneratedColumn<int> interestMinor = GeneratedColumn<int>(
    'interest_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _installmentDueMinorMeta =
      const VerificationMeta('installmentDueMinor');
  @override
  late final GeneratedColumn<int> installmentDueMinor = GeneratedColumn<int>(
    'installment_due_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creditBalanceMinorMeta =
      const VerificationMeta('creditBalanceMinor');
  @override
  late final GeneratedColumn<int> creditBalanceMinor = GeneratedColumn<int>(
    'credit_balance_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedByMeta = const VerificationMeta(
    'recordedBy',
  );
  @override
  late final GeneratedColumn<String> recordedBy = GeneratedColumn<String>(
    'recorded_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<String> recordedAt = GeneratedColumn<String>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    statementId,
    versionNo,
    sourceKind,
    previousBalanceMinor,
    newBalanceMinor,
    minDueMinor,
    paymentsMinor,
    creditsMinor,
    feesMinor,
    interestMinor,
    installmentDueMinor,
    creditBalanceMinor,
    dueDate,
    recordedBy,
    reason,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'statement_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StatementVersionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('statement_id')) {
      context.handle(
        _statementIdMeta,
        statementId.isAcceptableOrUnknown(
          data['statement_id']!,
          _statementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementIdMeta);
    }
    if (data.containsKey('version_no')) {
      context.handle(
        _versionNoMeta,
        versionNo.isAcceptableOrUnknown(data['version_no']!, _versionNoMeta),
      );
    } else if (isInserting) {
      context.missing(_versionNoMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('previous_balance_minor')) {
      context.handle(
        _previousBalanceMinorMeta,
        previousBalanceMinor.isAcceptableOrUnknown(
          data['previous_balance_minor']!,
          _previousBalanceMinorMeta,
        ),
      );
    }
    if (data.containsKey('new_balance_minor')) {
      context.handle(
        _newBalanceMinorMeta,
        newBalanceMinor.isAcceptableOrUnknown(
          data['new_balance_minor']!,
          _newBalanceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_newBalanceMinorMeta);
    }
    if (data.containsKey('min_due_minor')) {
      context.handle(
        _minDueMinorMeta,
        minDueMinor.isAcceptableOrUnknown(
          data['min_due_minor']!,
          _minDueMinorMeta,
        ),
      );
    }
    if (data.containsKey('payments_minor')) {
      context.handle(
        _paymentsMinorMeta,
        paymentsMinor.isAcceptableOrUnknown(
          data['payments_minor']!,
          _paymentsMinorMeta,
        ),
      );
    }
    if (data.containsKey('credits_minor')) {
      context.handle(
        _creditsMinorMeta,
        creditsMinor.isAcceptableOrUnknown(
          data['credits_minor']!,
          _creditsMinorMeta,
        ),
      );
    }
    if (data.containsKey('fees_minor')) {
      context.handle(
        _feesMinorMeta,
        feesMinor.isAcceptableOrUnknown(data['fees_minor']!, _feesMinorMeta),
      );
    }
    if (data.containsKey('interest_minor')) {
      context.handle(
        _interestMinorMeta,
        interestMinor.isAcceptableOrUnknown(
          data['interest_minor']!,
          _interestMinorMeta,
        ),
      );
    }
    if (data.containsKey('installment_due_minor')) {
      context.handle(
        _installmentDueMinorMeta,
        installmentDueMinor.isAcceptableOrUnknown(
          data['installment_due_minor']!,
          _installmentDueMinorMeta,
        ),
      );
    }
    if (data.containsKey('credit_balance_minor')) {
      context.handle(
        _creditBalanceMinorMeta,
        creditBalanceMinor.isAcceptableOrUnknown(
          data['credit_balance_minor']!,
          _creditBalanceMinorMeta,
        ),
      );
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('recorded_by')) {
      context.handle(
        _recordedByMeta,
        recordedBy.isAcceptableOrUnknown(data['recorded_by']!, _recordedByMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedByMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, statementId, id},
    {statementId, versionNo},
  ];
  @override
  StatementVersionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StatementVersionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      statementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}statement_id'],
      )!,
      versionNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_no'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      previousBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}previous_balance_minor'],
      ),
      newBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}new_balance_minor'],
      )!,
      minDueMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_due_minor'],
      ),
      paymentsMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payments_minor'],
      ),
      creditsMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credits_minor'],
      ),
      feesMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fees_minor'],
      ),
      interestMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_minor'],
      ),
      installmentDueMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}installment_due_minor'],
      ),
      creditBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credit_balance_minor'],
      ),
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      )!,
      recordedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_by'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $StatementVersionsTable createAlias(String alias) {
    return $StatementVersionsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class StatementVersionRow extends DataClass
    implements Insertable<StatementVersionRow> {
  final String id;
  final String workspaceId;
  final String statementId;
  final int versionNo;

  /// `manual` / `import` / `correction`。
  final String sourceKind;
  final int? previousBalanceMinor;
  final int newBalanceMinor;
  final int? minDueMinor;
  final int? paymentsMinor;
  final int? creditsMinor;
  final int? feesMinor;
  final int? interestMinor;
  final int? installmentDueMinor;
  final int? creditBalanceMinor;
  final String dueDate;

  /// `user` / `import`（本地只有一个使用者：`user` 即本机用户）。
  final String recordedBy;
  final String? reason;
  final String recordedAt;
  const StatementVersionRow({
    required this.id,
    required this.workspaceId,
    required this.statementId,
    required this.versionNo,
    required this.sourceKind,
    this.previousBalanceMinor,
    required this.newBalanceMinor,
    this.minDueMinor,
    this.paymentsMinor,
    this.creditsMinor,
    this.feesMinor,
    this.interestMinor,
    this.installmentDueMinor,
    this.creditBalanceMinor,
    required this.dueDate,
    required this.recordedBy,
    this.reason,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['statement_id'] = Variable<String>(statementId);
    map['version_no'] = Variable<int>(versionNo);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || previousBalanceMinor != null) {
      map['previous_balance_minor'] = Variable<int>(previousBalanceMinor);
    }
    map['new_balance_minor'] = Variable<int>(newBalanceMinor);
    if (!nullToAbsent || minDueMinor != null) {
      map['min_due_minor'] = Variable<int>(minDueMinor);
    }
    if (!nullToAbsent || paymentsMinor != null) {
      map['payments_minor'] = Variable<int>(paymentsMinor);
    }
    if (!nullToAbsent || creditsMinor != null) {
      map['credits_minor'] = Variable<int>(creditsMinor);
    }
    if (!nullToAbsent || feesMinor != null) {
      map['fees_minor'] = Variable<int>(feesMinor);
    }
    if (!nullToAbsent || interestMinor != null) {
      map['interest_minor'] = Variable<int>(interestMinor);
    }
    if (!nullToAbsent || installmentDueMinor != null) {
      map['installment_due_minor'] = Variable<int>(installmentDueMinor);
    }
    if (!nullToAbsent || creditBalanceMinor != null) {
      map['credit_balance_minor'] = Variable<int>(creditBalanceMinor);
    }
    map['due_date'] = Variable<String>(dueDate);
    map['recorded_by'] = Variable<String>(recordedBy);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['recorded_at'] = Variable<String>(recordedAt);
    return map;
  }

  StatementVersionsCompanion toCompanion(bool nullToAbsent) {
    return StatementVersionsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      statementId: Value(statementId),
      versionNo: Value(versionNo),
      sourceKind: Value(sourceKind),
      previousBalanceMinor: previousBalanceMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(previousBalanceMinor),
      newBalanceMinor: Value(newBalanceMinor),
      minDueMinor: minDueMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(minDueMinor),
      paymentsMinor: paymentsMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentsMinor),
      creditsMinor: creditsMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(creditsMinor),
      feesMinor: feesMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(feesMinor),
      interestMinor: interestMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(interestMinor),
      installmentDueMinor: installmentDueMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(installmentDueMinor),
      creditBalanceMinor: creditBalanceMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(creditBalanceMinor),
      dueDate: Value(dueDate),
      recordedBy: Value(recordedBy),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      recordedAt: Value(recordedAt),
    );
  }

  factory StatementVersionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StatementVersionRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      statementId: serializer.fromJson<String>(json['statementId']),
      versionNo: serializer.fromJson<int>(json['versionNo']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      previousBalanceMinor: serializer.fromJson<int?>(
        json['previousBalanceMinor'],
      ),
      newBalanceMinor: serializer.fromJson<int>(json['newBalanceMinor']),
      minDueMinor: serializer.fromJson<int?>(json['minDueMinor']),
      paymentsMinor: serializer.fromJson<int?>(json['paymentsMinor']),
      creditsMinor: serializer.fromJson<int?>(json['creditsMinor']),
      feesMinor: serializer.fromJson<int?>(json['feesMinor']),
      interestMinor: serializer.fromJson<int?>(json['interestMinor']),
      installmentDueMinor: serializer.fromJson<int?>(
        json['installmentDueMinor'],
      ),
      creditBalanceMinor: serializer.fromJson<int?>(json['creditBalanceMinor']),
      dueDate: serializer.fromJson<String>(json['dueDate']),
      recordedBy: serializer.fromJson<String>(json['recordedBy']),
      reason: serializer.fromJson<String?>(json['reason']),
      recordedAt: serializer.fromJson<String>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'statementId': serializer.toJson<String>(statementId),
      'versionNo': serializer.toJson<int>(versionNo),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'previousBalanceMinor': serializer.toJson<int?>(previousBalanceMinor),
      'newBalanceMinor': serializer.toJson<int>(newBalanceMinor),
      'minDueMinor': serializer.toJson<int?>(minDueMinor),
      'paymentsMinor': serializer.toJson<int?>(paymentsMinor),
      'creditsMinor': serializer.toJson<int?>(creditsMinor),
      'feesMinor': serializer.toJson<int?>(feesMinor),
      'interestMinor': serializer.toJson<int?>(interestMinor),
      'installmentDueMinor': serializer.toJson<int?>(installmentDueMinor),
      'creditBalanceMinor': serializer.toJson<int?>(creditBalanceMinor),
      'dueDate': serializer.toJson<String>(dueDate),
      'recordedBy': serializer.toJson<String>(recordedBy),
      'reason': serializer.toJson<String?>(reason),
      'recordedAt': serializer.toJson<String>(recordedAt),
    };
  }

  StatementVersionRow copyWith({
    String? id,
    String? workspaceId,
    String? statementId,
    int? versionNo,
    String? sourceKind,
    Value<int?> previousBalanceMinor = const Value.absent(),
    int? newBalanceMinor,
    Value<int?> minDueMinor = const Value.absent(),
    Value<int?> paymentsMinor = const Value.absent(),
    Value<int?> creditsMinor = const Value.absent(),
    Value<int?> feesMinor = const Value.absent(),
    Value<int?> interestMinor = const Value.absent(),
    Value<int?> installmentDueMinor = const Value.absent(),
    Value<int?> creditBalanceMinor = const Value.absent(),
    String? dueDate,
    String? recordedBy,
    Value<String?> reason = const Value.absent(),
    String? recordedAt,
  }) => StatementVersionRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    statementId: statementId ?? this.statementId,
    versionNo: versionNo ?? this.versionNo,
    sourceKind: sourceKind ?? this.sourceKind,
    previousBalanceMinor: previousBalanceMinor.present
        ? previousBalanceMinor.value
        : this.previousBalanceMinor,
    newBalanceMinor: newBalanceMinor ?? this.newBalanceMinor,
    minDueMinor: minDueMinor.present ? minDueMinor.value : this.minDueMinor,
    paymentsMinor: paymentsMinor.present
        ? paymentsMinor.value
        : this.paymentsMinor,
    creditsMinor: creditsMinor.present ? creditsMinor.value : this.creditsMinor,
    feesMinor: feesMinor.present ? feesMinor.value : this.feesMinor,
    interestMinor: interestMinor.present
        ? interestMinor.value
        : this.interestMinor,
    installmentDueMinor: installmentDueMinor.present
        ? installmentDueMinor.value
        : this.installmentDueMinor,
    creditBalanceMinor: creditBalanceMinor.present
        ? creditBalanceMinor.value
        : this.creditBalanceMinor,
    dueDate: dueDate ?? this.dueDate,
    recordedBy: recordedBy ?? this.recordedBy,
    reason: reason.present ? reason.value : this.reason,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  StatementVersionRow copyWithCompanion(StatementVersionsCompanion data) {
    return StatementVersionRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      statementId: data.statementId.present
          ? data.statementId.value
          : this.statementId,
      versionNo: data.versionNo.present ? data.versionNo.value : this.versionNo,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      previousBalanceMinor: data.previousBalanceMinor.present
          ? data.previousBalanceMinor.value
          : this.previousBalanceMinor,
      newBalanceMinor: data.newBalanceMinor.present
          ? data.newBalanceMinor.value
          : this.newBalanceMinor,
      minDueMinor: data.minDueMinor.present
          ? data.minDueMinor.value
          : this.minDueMinor,
      paymentsMinor: data.paymentsMinor.present
          ? data.paymentsMinor.value
          : this.paymentsMinor,
      creditsMinor: data.creditsMinor.present
          ? data.creditsMinor.value
          : this.creditsMinor,
      feesMinor: data.feesMinor.present ? data.feesMinor.value : this.feesMinor,
      interestMinor: data.interestMinor.present
          ? data.interestMinor.value
          : this.interestMinor,
      installmentDueMinor: data.installmentDueMinor.present
          ? data.installmentDueMinor.value
          : this.installmentDueMinor,
      creditBalanceMinor: data.creditBalanceMinor.present
          ? data.creditBalanceMinor.value
          : this.creditBalanceMinor,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      recordedBy: data.recordedBy.present
          ? data.recordedBy.value
          : this.recordedBy,
      reason: data.reason.present ? data.reason.value : this.reason,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StatementVersionRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('statementId: $statementId, ')
          ..write('versionNo: $versionNo, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('previousBalanceMinor: $previousBalanceMinor, ')
          ..write('newBalanceMinor: $newBalanceMinor, ')
          ..write('minDueMinor: $minDueMinor, ')
          ..write('paymentsMinor: $paymentsMinor, ')
          ..write('creditsMinor: $creditsMinor, ')
          ..write('feesMinor: $feesMinor, ')
          ..write('interestMinor: $interestMinor, ')
          ..write('installmentDueMinor: $installmentDueMinor, ')
          ..write('creditBalanceMinor: $creditBalanceMinor, ')
          ..write('dueDate: $dueDate, ')
          ..write('recordedBy: $recordedBy, ')
          ..write('reason: $reason, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    statementId,
    versionNo,
    sourceKind,
    previousBalanceMinor,
    newBalanceMinor,
    minDueMinor,
    paymentsMinor,
    creditsMinor,
    feesMinor,
    interestMinor,
    installmentDueMinor,
    creditBalanceMinor,
    dueDate,
    recordedBy,
    reason,
    recordedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StatementVersionRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.statementId == this.statementId &&
          other.versionNo == this.versionNo &&
          other.sourceKind == this.sourceKind &&
          other.previousBalanceMinor == this.previousBalanceMinor &&
          other.newBalanceMinor == this.newBalanceMinor &&
          other.minDueMinor == this.minDueMinor &&
          other.paymentsMinor == this.paymentsMinor &&
          other.creditsMinor == this.creditsMinor &&
          other.feesMinor == this.feesMinor &&
          other.interestMinor == this.interestMinor &&
          other.installmentDueMinor == this.installmentDueMinor &&
          other.creditBalanceMinor == this.creditBalanceMinor &&
          other.dueDate == this.dueDate &&
          other.recordedBy == this.recordedBy &&
          other.reason == this.reason &&
          other.recordedAt == this.recordedAt);
}

class StatementVersionsCompanion extends UpdateCompanion<StatementVersionRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> statementId;
  final Value<int> versionNo;
  final Value<String> sourceKind;
  final Value<int?> previousBalanceMinor;
  final Value<int> newBalanceMinor;
  final Value<int?> minDueMinor;
  final Value<int?> paymentsMinor;
  final Value<int?> creditsMinor;
  final Value<int?> feesMinor;
  final Value<int?> interestMinor;
  final Value<int?> installmentDueMinor;
  final Value<int?> creditBalanceMinor;
  final Value<String> dueDate;
  final Value<String> recordedBy;
  final Value<String?> reason;
  final Value<String> recordedAt;
  final Value<int> rowid;
  const StatementVersionsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.statementId = const Value.absent(),
    this.versionNo = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.previousBalanceMinor = const Value.absent(),
    this.newBalanceMinor = const Value.absent(),
    this.minDueMinor = const Value.absent(),
    this.paymentsMinor = const Value.absent(),
    this.creditsMinor = const Value.absent(),
    this.feesMinor = const Value.absent(),
    this.interestMinor = const Value.absent(),
    this.installmentDueMinor = const Value.absent(),
    this.creditBalanceMinor = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.recordedBy = const Value.absent(),
    this.reason = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StatementVersionsCompanion.insert({
    required String id,
    required String workspaceId,
    required String statementId,
    required int versionNo,
    required String sourceKind,
    this.previousBalanceMinor = const Value.absent(),
    required int newBalanceMinor,
    this.minDueMinor = const Value.absent(),
    this.paymentsMinor = const Value.absent(),
    this.creditsMinor = const Value.absent(),
    this.feesMinor = const Value.absent(),
    this.interestMinor = const Value.absent(),
    this.installmentDueMinor = const Value.absent(),
    this.creditBalanceMinor = const Value.absent(),
    required String dueDate,
    required String recordedBy,
    this.reason = const Value.absent(),
    required String recordedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       statementId = Value(statementId),
       versionNo = Value(versionNo),
       sourceKind = Value(sourceKind),
       newBalanceMinor = Value(newBalanceMinor),
       dueDate = Value(dueDate),
       recordedBy = Value(recordedBy),
       recordedAt = Value(recordedAt);
  static Insertable<StatementVersionRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? statementId,
    Expression<int>? versionNo,
    Expression<String>? sourceKind,
    Expression<int>? previousBalanceMinor,
    Expression<int>? newBalanceMinor,
    Expression<int>? minDueMinor,
    Expression<int>? paymentsMinor,
    Expression<int>? creditsMinor,
    Expression<int>? feesMinor,
    Expression<int>? interestMinor,
    Expression<int>? installmentDueMinor,
    Expression<int>? creditBalanceMinor,
    Expression<String>? dueDate,
    Expression<String>? recordedBy,
    Expression<String>? reason,
    Expression<String>? recordedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (statementId != null) 'statement_id': statementId,
      if (versionNo != null) 'version_no': versionNo,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (previousBalanceMinor != null)
        'previous_balance_minor': previousBalanceMinor,
      if (newBalanceMinor != null) 'new_balance_minor': newBalanceMinor,
      if (minDueMinor != null) 'min_due_minor': minDueMinor,
      if (paymentsMinor != null) 'payments_minor': paymentsMinor,
      if (creditsMinor != null) 'credits_minor': creditsMinor,
      if (feesMinor != null) 'fees_minor': feesMinor,
      if (interestMinor != null) 'interest_minor': interestMinor,
      if (installmentDueMinor != null)
        'installment_due_minor': installmentDueMinor,
      if (creditBalanceMinor != null)
        'credit_balance_minor': creditBalanceMinor,
      if (dueDate != null) 'due_date': dueDate,
      if (recordedBy != null) 'recorded_by': recordedBy,
      if (reason != null) 'reason': reason,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StatementVersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? statementId,
    Value<int>? versionNo,
    Value<String>? sourceKind,
    Value<int?>? previousBalanceMinor,
    Value<int>? newBalanceMinor,
    Value<int?>? minDueMinor,
    Value<int?>? paymentsMinor,
    Value<int?>? creditsMinor,
    Value<int?>? feesMinor,
    Value<int?>? interestMinor,
    Value<int?>? installmentDueMinor,
    Value<int?>? creditBalanceMinor,
    Value<String>? dueDate,
    Value<String>? recordedBy,
    Value<String?>? reason,
    Value<String>? recordedAt,
    Value<int>? rowid,
  }) {
    return StatementVersionsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      statementId: statementId ?? this.statementId,
      versionNo: versionNo ?? this.versionNo,
      sourceKind: sourceKind ?? this.sourceKind,
      previousBalanceMinor: previousBalanceMinor ?? this.previousBalanceMinor,
      newBalanceMinor: newBalanceMinor ?? this.newBalanceMinor,
      minDueMinor: minDueMinor ?? this.minDueMinor,
      paymentsMinor: paymentsMinor ?? this.paymentsMinor,
      creditsMinor: creditsMinor ?? this.creditsMinor,
      feesMinor: feesMinor ?? this.feesMinor,
      interestMinor: interestMinor ?? this.interestMinor,
      installmentDueMinor: installmentDueMinor ?? this.installmentDueMinor,
      creditBalanceMinor: creditBalanceMinor ?? this.creditBalanceMinor,
      dueDate: dueDate ?? this.dueDate,
      recordedBy: recordedBy ?? this.recordedBy,
      reason: reason ?? this.reason,
      recordedAt: recordedAt ?? this.recordedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (statementId.present) {
      map['statement_id'] = Variable<String>(statementId.value);
    }
    if (versionNo.present) {
      map['version_no'] = Variable<int>(versionNo.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (previousBalanceMinor.present) {
      map['previous_balance_minor'] = Variable<int>(previousBalanceMinor.value);
    }
    if (newBalanceMinor.present) {
      map['new_balance_minor'] = Variable<int>(newBalanceMinor.value);
    }
    if (minDueMinor.present) {
      map['min_due_minor'] = Variable<int>(minDueMinor.value);
    }
    if (paymentsMinor.present) {
      map['payments_minor'] = Variable<int>(paymentsMinor.value);
    }
    if (creditsMinor.present) {
      map['credits_minor'] = Variable<int>(creditsMinor.value);
    }
    if (feesMinor.present) {
      map['fees_minor'] = Variable<int>(feesMinor.value);
    }
    if (interestMinor.present) {
      map['interest_minor'] = Variable<int>(interestMinor.value);
    }
    if (installmentDueMinor.present) {
      map['installment_due_minor'] = Variable<int>(installmentDueMinor.value);
    }
    if (creditBalanceMinor.present) {
      map['credit_balance_minor'] = Variable<int>(creditBalanceMinor.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (recordedBy.present) {
      map['recorded_by'] = Variable<String>(recordedBy.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<String>(recordedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StatementVersionsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('statementId: $statementId, ')
          ..write('versionNo: $versionNo, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('previousBalanceMinor: $previousBalanceMinor, ')
          ..write('newBalanceMinor: $newBalanceMinor, ')
          ..write('minDueMinor: $minDueMinor, ')
          ..write('paymentsMinor: $paymentsMinor, ')
          ..write('creditsMinor: $creditsMinor, ')
          ..write('feesMinor: $feesMinor, ')
          ..write('interestMinor: $interestMinor, ')
          ..write('installmentDueMinor: $installmentDueMinor, ')
          ..write('creditBalanceMinor: $creditBalanceMinor, ')
          ..write('dueDate: $dueDate, ')
          ..write('recordedBy: $recordedBy, ')
          ..write('reason: $reason, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StatementsTable extends Statements
    with TableInfo<$StatementsTable, StatementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StatementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _statementDateMeta = const VerificationMeta(
    'statementDate',
  );
  @override
  late final GeneratedColumn<String> statementDate = GeneratedColumn<String>(
    'statement_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentVersionIdMeta = const VerificationMeta(
    'currentVersionId',
  );
  @override
  late final GeneratedColumn<String> currentVersionId = GeneratedColumn<String>(
    'current_version_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    currencyAccountId,
    statementDate,
    dueDate,
    status,
    currentVersionId,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'statements';
  @override
  VerificationContext validateIntegrity(
    Insertable<StatementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('statement_date')) {
      context.handle(
        _statementDateMeta,
        statementDate.isAcceptableOrUnknown(
          data['statement_date']!,
          _statementDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementDateMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('current_version_id')) {
      context.handle(
        _currentVersionIdMeta,
        currentVersionId.isAcceptableOrUnknown(
          data['current_version_id']!,
          _currentVersionIdMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, currencyAccountId, id},
    {workspaceId, currencyAccountId, statementDate},
  ];
  @override
  StatementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StatementRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      statementDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}statement_date'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      currentVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_version_id'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StatementsTable createAlias(String alias) {
    return $StatementsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class StatementRow extends DataClass implements Insertable<StatementRow> {
  final String id;
  final String workspaceId;
  final String currencyAccountId;
  final String statementDate;

  /// 当前版本的到期还款日。
  final String dueDate;

  /// `predicted` / `issued` / `amended` / `partially_settled` / `settled` / `overdue`。
  final String status;
  final String? currentVersionId;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const StatementRow({
    required this.id,
    required this.workspaceId,
    required this.currencyAccountId,
    required this.statementDate,
    required this.dueDate,
    required this.status,
    this.currentVersionId,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    map['statement_date'] = Variable<String>(statementDate);
    map['due_date'] = Variable<String>(dueDate);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || currentVersionId != null) {
      map['current_version_id'] = Variable<String>(currentVersionId);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  StatementsCompanion toCompanion(bool nullToAbsent) {
    return StatementsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      statementDate: Value(statementDate),
      dueDate: Value(dueDate),
      status: Value(status),
      currentVersionId: currentVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(currentVersionId),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory StatementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StatementRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      statementDate: serializer.fromJson<String>(json['statementDate']),
      dueDate: serializer.fromJson<String>(json['dueDate']),
      status: serializer.fromJson<String>(json['status']),
      currentVersionId: serializer.fromJson<String?>(json['currentVersionId']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'statementDate': serializer.toJson<String>(statementDate),
      'dueDate': serializer.toJson<String>(dueDate),
      'status': serializer.toJson<String>(status),
      'currentVersionId': serializer.toJson<String?>(currentVersionId),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  StatementRow copyWith({
    String? id,
    String? workspaceId,
    String? currencyAccountId,
    String? statementDate,
    String? dueDate,
    String? status,
    Value<String?> currentVersionId = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => StatementRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    statementDate: statementDate ?? this.statementDate,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
    currentVersionId: currentVersionId.present
        ? currentVersionId.value
        : this.currentVersionId,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StatementRow copyWithCompanion(StatementsCompanion data) {
    return StatementRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      statementDate: data.statementDate.present
          ? data.statementDate.value
          : this.statementDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      status: data.status.present ? data.status.value : this.status,
      currentVersionId: data.currentVersionId.present
          ? data.currentVersionId.value
          : this.currentVersionId,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StatementRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('statementDate: $statementDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('currentVersionId: $currentVersionId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    currencyAccountId,
    statementDate,
    dueDate,
    status,
    currentVersionId,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StatementRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.statementDate == this.statementDate &&
          other.dueDate == this.dueDate &&
          other.status == this.status &&
          other.currentVersionId == this.currentVersionId &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StatementsCompanion extends UpdateCompanion<StatementRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<String> statementDate;
  final Value<String> dueDate;
  final Value<String> status;
  final Value<String?> currentVersionId;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const StatementsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.statementDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.currentVersionId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StatementsCompanion.insert({
    required String id,
    required String workspaceId,
    required String currencyAccountId,
    required String statementDate,
    required String dueDate,
    required String status,
    this.currentVersionId = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       statementDate = Value(statementDate),
       dueDate = Value(dueDate),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<StatementRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<String>? statementDate,
    Expression<String>? dueDate,
    Expression<String>? status,
    Expression<String>? currentVersionId,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (statementDate != null) 'statement_date': statementDate,
      if (dueDate != null) 'due_date': dueDate,
      if (status != null) 'status': status,
      if (currentVersionId != null) 'current_version_id': currentVersionId,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StatementsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<String>? statementDate,
    Value<String>? dueDate,
    Value<String>? status,
    Value<String?>? currentVersionId,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return StatementsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      statementDate: statementDate ?? this.statementDate,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      currentVersionId: currentVersionId ?? this.currentVersionId,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (statementDate.present) {
      map['statement_date'] = Variable<String>(statementDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (currentVersionId.present) {
      map['current_version_id'] = Variable<String>(currentVersionId.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StatementsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('statementDate: $statementDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('currentVersionId: $currentVersionId, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InstallmentPlansTable extends InstallmentPlans
    with TableInfo<$InstallmentPlansTable, InstallmentPlanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstallmentPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _principalMinorMeta = const VerificationMeta(
    'principalMinor',
  );
  @override
  late final GeneratedColumn<int> principalMinor = GeneratedColumn<int>(
    'principal_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodsMeta = const VerificationMeta(
    'periods',
  );
  @override
  late final GeneratedColumn<int> periods = GeneratedColumn<int>(
    'periods',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _perPeriodRateMeta = const VerificationMeta(
    'perPeriodRate',
  );
  @override
  late final GeneratedColumn<String> perPeriodRate = GeneratedColumn<String>(
    'per_period_rate',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feeModeMeta = const VerificationMeta(
    'feeMode',
  );
  @override
  late final GeneratedColumn<String> feeMode = GeneratedColumn<String>(
    'fee_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remainderPolicyMeta = const VerificationMeta(
    'remainderPolicy',
  );
  @override
  late final GeneratedColumn<String> remainderPolicy = GeneratedColumn<String>(
    'remainder_policy',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roundingMeta = const VerificationMeta(
    'rounding',
  );
  @override
  late final GeneratedColumn<String> rounding = GeneratedColumn<String>(
    'rounding',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _earlySettledAtMeta = const VerificationMeta(
    'earlySettledAt',
  );
  @override
  late final GeneratedColumn<String> earlySettledAt = GeneratedColumn<String>(
    'early_settled_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    currencyAccountId,
    transactionId,
    principalMinor,
    periods,
    perPeriodRate,
    feeMode,
    remainderPolicy,
    rounding,
    status,
    earlySettledAt,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installment_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstallmentPlanRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('principal_minor')) {
      context.handle(
        _principalMinorMeta,
        principalMinor.isAcceptableOrUnknown(
          data['principal_minor']!,
          _principalMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_principalMinorMeta);
    }
    if (data.containsKey('periods')) {
      context.handle(
        _periodsMeta,
        periods.isAcceptableOrUnknown(data['periods']!, _periodsMeta),
      );
    } else if (isInserting) {
      context.missing(_periodsMeta);
    }
    if (data.containsKey('per_period_rate')) {
      context.handle(
        _perPeriodRateMeta,
        perPeriodRate.isAcceptableOrUnknown(
          data['per_period_rate']!,
          _perPeriodRateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_perPeriodRateMeta);
    }
    if (data.containsKey('fee_mode')) {
      context.handle(
        _feeModeMeta,
        feeMode.isAcceptableOrUnknown(data['fee_mode']!, _feeModeMeta),
      );
    } else if (isInserting) {
      context.missing(_feeModeMeta);
    }
    if (data.containsKey('remainder_policy')) {
      context.handle(
        _remainderPolicyMeta,
        remainderPolicy.isAcceptableOrUnknown(
          data['remainder_policy']!,
          _remainderPolicyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remainderPolicyMeta);
    }
    if (data.containsKey('rounding')) {
      context.handle(
        _roundingMeta,
        rounding.isAcceptableOrUnknown(data['rounding']!, _roundingMeta),
      );
    } else if (isInserting) {
      context.missing(_roundingMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('early_settled_at')) {
      context.handle(
        _earlySettledAtMeta,
        earlySettledAt.isAcceptableOrUnknown(
          data['early_settled_at']!,
          _earlySettledAtMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, transactionId},
  ];
  @override
  InstallmentPlanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstallmentPlanRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      )!,
      principalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}principal_minor'],
      )!,
      periods: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}periods'],
      )!,
      perPeriodRate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}per_period_rate'],
      )!,
      feeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fee_mode'],
      )!,
      remainderPolicy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remainder_policy'],
      )!,
      rounding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rounding'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      earlySettledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}early_settled_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InstallmentPlansTable createAlias(String alias) {
    return $InstallmentPlansTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class InstallmentPlanRow extends DataClass
    implements Insertable<InstallmentPlanRow> {
  final String id;
  final String workspaceId;
  final String currencyAccountId;
  final String transactionId;
  final int principalMinor;
  final int periods;
  final String perPeriodRate;

  /// `per_period` / `upfront`。
  final String feeMode;

  /// `last` / `first`。
  final String remainderPolicy;

  /// `HALF_UP`。
  final String rounding;

  /// `active` / `completed` / `early_settled` / `cancelled`（data-model §10.12）。
  final String status;
  final String? earlySettledAt;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const InstallmentPlanRow({
    required this.id,
    required this.workspaceId,
    required this.currencyAccountId,
    required this.transactionId,
    required this.principalMinor,
    required this.periods,
    required this.perPeriodRate,
    required this.feeMode,
    required this.remainderPolicy,
    required this.rounding,
    required this.status,
    this.earlySettledAt,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    map['transaction_id'] = Variable<String>(transactionId);
    map['principal_minor'] = Variable<int>(principalMinor);
    map['periods'] = Variable<int>(periods);
    map['per_period_rate'] = Variable<String>(perPeriodRate);
    map['fee_mode'] = Variable<String>(feeMode);
    map['remainder_policy'] = Variable<String>(remainderPolicy);
    map['rounding'] = Variable<String>(rounding);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || earlySettledAt != null) {
      map['early_settled_at'] = Variable<String>(earlySettledAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  InstallmentPlansCompanion toCompanion(bool nullToAbsent) {
    return InstallmentPlansCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      transactionId: Value(transactionId),
      principalMinor: Value(principalMinor),
      periods: Value(periods),
      perPeriodRate: Value(perPeriodRate),
      feeMode: Value(feeMode),
      remainderPolicy: Value(remainderPolicy),
      rounding: Value(rounding),
      status: Value(status),
      earlySettledAt: earlySettledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(earlySettledAt),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory InstallmentPlanRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstallmentPlanRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      principalMinor: serializer.fromJson<int>(json['principalMinor']),
      periods: serializer.fromJson<int>(json['periods']),
      perPeriodRate: serializer.fromJson<String>(json['perPeriodRate']),
      feeMode: serializer.fromJson<String>(json['feeMode']),
      remainderPolicy: serializer.fromJson<String>(json['remainderPolicy']),
      rounding: serializer.fromJson<String>(json['rounding']),
      status: serializer.fromJson<String>(json['status']),
      earlySettledAt: serializer.fromJson<String?>(json['earlySettledAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'transactionId': serializer.toJson<String>(transactionId),
      'principalMinor': serializer.toJson<int>(principalMinor),
      'periods': serializer.toJson<int>(periods),
      'perPeriodRate': serializer.toJson<String>(perPeriodRate),
      'feeMode': serializer.toJson<String>(feeMode),
      'remainderPolicy': serializer.toJson<String>(remainderPolicy),
      'rounding': serializer.toJson<String>(rounding),
      'status': serializer.toJson<String>(status),
      'earlySettledAt': serializer.toJson<String?>(earlySettledAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  InstallmentPlanRow copyWith({
    String? id,
    String? workspaceId,
    String? currencyAccountId,
    String? transactionId,
    int? principalMinor,
    int? periods,
    String? perPeriodRate,
    String? feeMode,
    String? remainderPolicy,
    String? rounding,
    String? status,
    Value<String?> earlySettledAt = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => InstallmentPlanRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    transactionId: transactionId ?? this.transactionId,
    principalMinor: principalMinor ?? this.principalMinor,
    periods: periods ?? this.periods,
    perPeriodRate: perPeriodRate ?? this.perPeriodRate,
    feeMode: feeMode ?? this.feeMode,
    remainderPolicy: remainderPolicy ?? this.remainderPolicy,
    rounding: rounding ?? this.rounding,
    status: status ?? this.status,
    earlySettledAt: earlySettledAt.present
        ? earlySettledAt.value
        : this.earlySettledAt,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InstallmentPlanRow copyWithCompanion(InstallmentPlansCompanion data) {
    return InstallmentPlanRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      principalMinor: data.principalMinor.present
          ? data.principalMinor.value
          : this.principalMinor,
      periods: data.periods.present ? data.periods.value : this.periods,
      perPeriodRate: data.perPeriodRate.present
          ? data.perPeriodRate.value
          : this.perPeriodRate,
      feeMode: data.feeMode.present ? data.feeMode.value : this.feeMode,
      remainderPolicy: data.remainderPolicy.present
          ? data.remainderPolicy.value
          : this.remainderPolicy,
      rounding: data.rounding.present ? data.rounding.value : this.rounding,
      status: data.status.present ? data.status.value : this.status,
      earlySettledAt: data.earlySettledAt.present
          ? data.earlySettledAt.value
          : this.earlySettledAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstallmentPlanRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('transactionId: $transactionId, ')
          ..write('principalMinor: $principalMinor, ')
          ..write('periods: $periods, ')
          ..write('perPeriodRate: $perPeriodRate, ')
          ..write('feeMode: $feeMode, ')
          ..write('remainderPolicy: $remainderPolicy, ')
          ..write('rounding: $rounding, ')
          ..write('status: $status, ')
          ..write('earlySettledAt: $earlySettledAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    currencyAccountId,
    transactionId,
    principalMinor,
    periods,
    perPeriodRate,
    feeMode,
    remainderPolicy,
    rounding,
    status,
    earlySettledAt,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstallmentPlanRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.transactionId == this.transactionId &&
          other.principalMinor == this.principalMinor &&
          other.periods == this.periods &&
          other.perPeriodRate == this.perPeriodRate &&
          other.feeMode == this.feeMode &&
          other.remainderPolicy == this.remainderPolicy &&
          other.rounding == this.rounding &&
          other.status == this.status &&
          other.earlySettledAt == this.earlySettledAt &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class InstallmentPlansCompanion extends UpdateCompanion<InstallmentPlanRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<String> transactionId;
  final Value<int> principalMinor;
  final Value<int> periods;
  final Value<String> perPeriodRate;
  final Value<String> feeMode;
  final Value<String> remainderPolicy;
  final Value<String> rounding;
  final Value<String> status;
  final Value<String?> earlySettledAt;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const InstallmentPlansCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.principalMinor = const Value.absent(),
    this.periods = const Value.absent(),
    this.perPeriodRate = const Value.absent(),
    this.feeMode = const Value.absent(),
    this.remainderPolicy = const Value.absent(),
    this.rounding = const Value.absent(),
    this.status = const Value.absent(),
    this.earlySettledAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstallmentPlansCompanion.insert({
    required String id,
    required String workspaceId,
    required String currencyAccountId,
    required String transactionId,
    required int principalMinor,
    required int periods,
    required String perPeriodRate,
    required String feeMode,
    required String remainderPolicy,
    required String rounding,
    required String status,
    this.earlySettledAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       transactionId = Value(transactionId),
       principalMinor = Value(principalMinor),
       periods = Value(periods),
       perPeriodRate = Value(perPeriodRate),
       feeMode = Value(feeMode),
       remainderPolicy = Value(remainderPolicy),
       rounding = Value(rounding),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<InstallmentPlanRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<String>? transactionId,
    Expression<int>? principalMinor,
    Expression<int>? periods,
    Expression<String>? perPeriodRate,
    Expression<String>? feeMode,
    Expression<String>? remainderPolicy,
    Expression<String>? rounding,
    Expression<String>? status,
    Expression<String>? earlySettledAt,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (principalMinor != null) 'principal_minor': principalMinor,
      if (periods != null) 'periods': periods,
      if (perPeriodRate != null) 'per_period_rate': perPeriodRate,
      if (feeMode != null) 'fee_mode': feeMode,
      if (remainderPolicy != null) 'remainder_policy': remainderPolicy,
      if (rounding != null) 'rounding': rounding,
      if (status != null) 'status': status,
      if (earlySettledAt != null) 'early_settled_at': earlySettledAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstallmentPlansCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<String>? transactionId,
    Value<int>? principalMinor,
    Value<int>? periods,
    Value<String>? perPeriodRate,
    Value<String>? feeMode,
    Value<String>? remainderPolicy,
    Value<String>? rounding,
    Value<String>? status,
    Value<String?>? earlySettledAt,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return InstallmentPlansCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      transactionId: transactionId ?? this.transactionId,
      principalMinor: principalMinor ?? this.principalMinor,
      periods: periods ?? this.periods,
      perPeriodRate: perPeriodRate ?? this.perPeriodRate,
      feeMode: feeMode ?? this.feeMode,
      remainderPolicy: remainderPolicy ?? this.remainderPolicy,
      rounding: rounding ?? this.rounding,
      status: status ?? this.status,
      earlySettledAt: earlySettledAt ?? this.earlySettledAt,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (principalMinor.present) {
      map['principal_minor'] = Variable<int>(principalMinor.value);
    }
    if (periods.present) {
      map['periods'] = Variable<int>(periods.value);
    }
    if (perPeriodRate.present) {
      map['per_period_rate'] = Variable<String>(perPeriodRate.value);
    }
    if (feeMode.present) {
      map['fee_mode'] = Variable<String>(feeMode.value);
    }
    if (remainderPolicy.present) {
      map['remainder_policy'] = Variable<String>(remainderPolicy.value);
    }
    if (rounding.present) {
      map['rounding'] = Variable<String>(rounding.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (earlySettledAt.present) {
      map['early_settled_at'] = Variable<String>(earlySettledAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstallmentPlansCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('transactionId: $transactionId, ')
          ..write('principalMinor: $principalMinor, ')
          ..write('periods: $periods, ')
          ..write('perPeriodRate: $perPeriodRate, ')
          ..write('feeMode: $feeMode, ')
          ..write('remainderPolicy: $remainderPolicy, ')
          ..write('rounding: $rounding, ')
          ..write('status: $status, ')
          ..write('earlySettledAt: $earlySettledAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InstallmentScheduleTable extends InstallmentSchedule
    with TableInfo<$InstallmentScheduleTable, InstallmentScheduleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InstallmentScheduleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _periodNoMeta = const VerificationMeta(
    'periodNo',
  );
  @override
  late final GeneratedColumn<int> periodNo = GeneratedColumn<int>(
    'period_no',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _principalMinorMeta = const VerificationMeta(
    'principalMinor',
  );
  @override
  late final GeneratedColumn<int> principalMinor = GeneratedColumn<int>(
    'principal_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feeMinorMeta = const VerificationMeta(
    'feeMinor',
  );
  @override
  late final GeneratedColumn<int> feeMinor = GeneratedColumn<int>(
    'fee_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statementDateMeta = const VerificationMeta(
    'statementDate',
  );
  @override
  late final GeneratedColumn<String> statementDate = GeneratedColumn<String>(
    'statement_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<String> dueDate = GeneratedColumn<String>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    planId,
    periodNo,
    principalMinor,
    feeMinor,
    statementDate,
    dueDate,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'installment_schedule';
  @override
  VerificationContext validateIntegrity(
    Insertable<InstallmentScheduleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('period_no')) {
      context.handle(
        _periodNoMeta,
        periodNo.isAcceptableOrUnknown(data['period_no']!, _periodNoMeta),
      );
    } else if (isInserting) {
      context.missing(_periodNoMeta);
    }
    if (data.containsKey('principal_minor')) {
      context.handle(
        _principalMinorMeta,
        principalMinor.isAcceptableOrUnknown(
          data['principal_minor']!,
          _principalMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_principalMinorMeta);
    }
    if (data.containsKey('fee_minor')) {
      context.handle(
        _feeMinorMeta,
        feeMinor.isAcceptableOrUnknown(data['fee_minor']!, _feeMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_feeMinorMeta);
    }
    if (data.containsKey('statement_date')) {
      context.handle(
        _statementDateMeta,
        statementDate.isAcceptableOrUnknown(
          data['statement_date']!,
          _statementDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementDateMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {planId, periodNo};
  @override
  InstallmentScheduleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InstallmentScheduleRow(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      periodNo: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period_no'],
      )!,
      principalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}principal_minor'],
      )!,
      feeMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fee_minor'],
      )!,
      statementDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}statement_date'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}due_date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $InstallmentScheduleTable createAlias(String alias) {
    return $InstallmentScheduleTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class InstallmentScheduleRow extends DataClass
    implements Insertable<InstallmentScheduleRow> {
  final String workspaceId;
  final String planId;
  final int periodNo;
  final int principalMinor;
  final int feeMinor;
  final String statementDate;
  final String dueDate;

  /// `scheduled` / `billed` / `settled` / `cancelled`（data-model §10.12）。
  final String status;
  const InstallmentScheduleRow({
    required this.workspaceId,
    required this.planId,
    required this.periodNo,
    required this.principalMinor,
    required this.feeMinor,
    required this.statementDate,
    required this.dueDate,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['plan_id'] = Variable<String>(planId);
    map['period_no'] = Variable<int>(periodNo);
    map['principal_minor'] = Variable<int>(principalMinor);
    map['fee_minor'] = Variable<int>(feeMinor);
    map['statement_date'] = Variable<String>(statementDate);
    map['due_date'] = Variable<String>(dueDate);
    map['status'] = Variable<String>(status);
    return map;
  }

  InstallmentScheduleCompanion toCompanion(bool nullToAbsent) {
    return InstallmentScheduleCompanion(
      workspaceId: Value(workspaceId),
      planId: Value(planId),
      periodNo: Value(periodNo),
      principalMinor: Value(principalMinor),
      feeMinor: Value(feeMinor),
      statementDate: Value(statementDate),
      dueDate: Value(dueDate),
      status: Value(status),
    );
  }

  factory InstallmentScheduleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InstallmentScheduleRow(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      planId: serializer.fromJson<String>(json['planId']),
      periodNo: serializer.fromJson<int>(json['periodNo']),
      principalMinor: serializer.fromJson<int>(json['principalMinor']),
      feeMinor: serializer.fromJson<int>(json['feeMinor']),
      statementDate: serializer.fromJson<String>(json['statementDate']),
      dueDate: serializer.fromJson<String>(json['dueDate']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'planId': serializer.toJson<String>(planId),
      'periodNo': serializer.toJson<int>(periodNo),
      'principalMinor': serializer.toJson<int>(principalMinor),
      'feeMinor': serializer.toJson<int>(feeMinor),
      'statementDate': serializer.toJson<String>(statementDate),
      'dueDate': serializer.toJson<String>(dueDate),
      'status': serializer.toJson<String>(status),
    };
  }

  InstallmentScheduleRow copyWith({
    String? workspaceId,
    String? planId,
    int? periodNo,
    int? principalMinor,
    int? feeMinor,
    String? statementDate,
    String? dueDate,
    String? status,
  }) => InstallmentScheduleRow(
    workspaceId: workspaceId ?? this.workspaceId,
    planId: planId ?? this.planId,
    periodNo: periodNo ?? this.periodNo,
    principalMinor: principalMinor ?? this.principalMinor,
    feeMinor: feeMinor ?? this.feeMinor,
    statementDate: statementDate ?? this.statementDate,
    dueDate: dueDate ?? this.dueDate,
    status: status ?? this.status,
  );
  InstallmentScheduleRow copyWithCompanion(InstallmentScheduleCompanion data) {
    return InstallmentScheduleRow(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      planId: data.planId.present ? data.planId.value : this.planId,
      periodNo: data.periodNo.present ? data.periodNo.value : this.periodNo,
      principalMinor: data.principalMinor.present
          ? data.principalMinor.value
          : this.principalMinor,
      feeMinor: data.feeMinor.present ? data.feeMinor.value : this.feeMinor,
      statementDate: data.statementDate.present
          ? data.statementDate.value
          : this.statementDate,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InstallmentScheduleRow(')
          ..write('workspaceId: $workspaceId, ')
          ..write('planId: $planId, ')
          ..write('periodNo: $periodNo, ')
          ..write('principalMinor: $principalMinor, ')
          ..write('feeMinor: $feeMinor, ')
          ..write('statementDate: $statementDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    planId,
    periodNo,
    principalMinor,
    feeMinor,
    statementDate,
    dueDate,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InstallmentScheduleRow &&
          other.workspaceId == this.workspaceId &&
          other.planId == this.planId &&
          other.periodNo == this.periodNo &&
          other.principalMinor == this.principalMinor &&
          other.feeMinor == this.feeMinor &&
          other.statementDate == this.statementDate &&
          other.dueDate == this.dueDate &&
          other.status == this.status);
}

class InstallmentScheduleCompanion
    extends UpdateCompanion<InstallmentScheduleRow> {
  final Value<String> workspaceId;
  final Value<String> planId;
  final Value<int> periodNo;
  final Value<int> principalMinor;
  final Value<int> feeMinor;
  final Value<String> statementDate;
  final Value<String> dueDate;
  final Value<String> status;
  final Value<int> rowid;
  const InstallmentScheduleCompanion({
    this.workspaceId = const Value.absent(),
    this.planId = const Value.absent(),
    this.periodNo = const Value.absent(),
    this.principalMinor = const Value.absent(),
    this.feeMinor = const Value.absent(),
    this.statementDate = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InstallmentScheduleCompanion.insert({
    required String workspaceId,
    required String planId,
    required int periodNo,
    required int principalMinor,
    required int feeMinor,
    required String statementDate,
    required String dueDate,
    required String status,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       planId = Value(planId),
       periodNo = Value(periodNo),
       principalMinor = Value(principalMinor),
       feeMinor = Value(feeMinor),
       statementDate = Value(statementDate),
       dueDate = Value(dueDate),
       status = Value(status);
  static Insertable<InstallmentScheduleRow> custom({
    Expression<String>? workspaceId,
    Expression<String>? planId,
    Expression<int>? periodNo,
    Expression<int>? principalMinor,
    Expression<int>? feeMinor,
    Expression<String>? statementDate,
    Expression<String>? dueDate,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (planId != null) 'plan_id': planId,
      if (periodNo != null) 'period_no': periodNo,
      if (principalMinor != null) 'principal_minor': principalMinor,
      if (feeMinor != null) 'fee_minor': feeMinor,
      if (statementDate != null) 'statement_date': statementDate,
      if (dueDate != null) 'due_date': dueDate,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InstallmentScheduleCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? planId,
    Value<int>? periodNo,
    Value<int>? principalMinor,
    Value<int>? feeMinor,
    Value<String>? statementDate,
    Value<String>? dueDate,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return InstallmentScheduleCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      planId: planId ?? this.planId,
      periodNo: periodNo ?? this.periodNo,
      principalMinor: principalMinor ?? this.principalMinor,
      feeMinor: feeMinor ?? this.feeMinor,
      statementDate: statementDate ?? this.statementDate,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (periodNo.present) {
      map['period_no'] = Variable<int>(periodNo.value);
    }
    if (principalMinor.present) {
      map['principal_minor'] = Variable<int>(principalMinor.value);
    }
    if (feeMinor.present) {
      map['fee_minor'] = Variable<int>(feeMinor.value);
    }
    if (statementDate.present) {
      map['statement_date'] = Variable<String>(statementDate.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<String>(dueDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InstallmentScheduleCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('planId: $planId, ')
          ..write('periodNo: $periodNo, ')
          ..write('principalMinor: $principalMinor, ')
          ..write('feeMinor: $feeMinor, ')
          ..write('statementDate: $statementDate, ')
          ..write('dueDate: $dueDate, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RepaymentsTable extends Repayments
    with TableInfo<$RepaymentsTable, RepaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RepaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _cashAccountIdMeta = const VerificationMeta(
    'cashAccountId',
  );
  @override
  late final GeneratedColumn<String> cashAccountId = GeneratedColumn<String>(
    'cash_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paymentInitiatedAtMeta =
      const VerificationMeta('paymentInitiatedAt');
  @override
  late final GeneratedColumn<String> paymentInitiatedAt =
      GeneratedColumn<String>(
        'payment_initiated_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _expectedDebitOnMeta = const VerificationMeta(
    'expectedDebitOn',
  );
  @override
  late final GeneratedColumn<String> expectedDebitOn = GeneratedColumn<String>(
    'expected_debit_on',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cashDebitedAtMeta = const VerificationMeta(
    'cashDebitedAt',
  );
  @override
  late final GeneratedColumn<String> cashDebitedAt = GeneratedColumn<String>(
    'cash_debited_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creditPostedAtMeta = const VerificationMeta(
    'creditPostedAt',
  );
  @override
  late final GeneratedColumn<String> creditPostedAt = GeneratedColumn<String>(
    'credit_posted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bankConfirmedAtMeta = const VerificationMeta(
    'bankConfirmedAt',
  );
  @override
  late final GeneratedColumn<String> bankConfirmedAt = GeneratedColumn<String>(
    'bank_confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _evidenceNoteMeta = const VerificationMeta(
    'evidenceNote',
  );
  @override
  late final GeneratedColumn<String> evidenceNote = GeneratedColumn<String>(
    'evidence_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<String> deletedAt = GeneratedColumn<String>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    currencyAccountId,
    cashAccountId,
    amountMinor,
    currency,
    status,
    method,
    paymentInitiatedAt,
    expectedDebitOn,
    cashDebitedAt,
    creditPostedAt,
    bankConfirmedAt,
    evidenceNote,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'repayments';
  @override
  VerificationContext validateIntegrity(
    Insertable<RepaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('cash_account_id')) {
      context.handle(
        _cashAccountIdMeta,
        cashAccountId.isAcceptableOrUnknown(
          data['cash_account_id']!,
          _cashAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('payment_initiated_at')) {
      context.handle(
        _paymentInitiatedAtMeta,
        paymentInitiatedAt.isAcceptableOrUnknown(
          data['payment_initiated_at']!,
          _paymentInitiatedAtMeta,
        ),
      );
    }
    if (data.containsKey('expected_debit_on')) {
      context.handle(
        _expectedDebitOnMeta,
        expectedDebitOn.isAcceptableOrUnknown(
          data['expected_debit_on']!,
          _expectedDebitOnMeta,
        ),
      );
    }
    if (data.containsKey('cash_debited_at')) {
      context.handle(
        _cashDebitedAtMeta,
        cashDebitedAt.isAcceptableOrUnknown(
          data['cash_debited_at']!,
          _cashDebitedAtMeta,
        ),
      );
    }
    if (data.containsKey('credit_posted_at')) {
      context.handle(
        _creditPostedAtMeta,
        creditPostedAt.isAcceptableOrUnknown(
          data['credit_posted_at']!,
          _creditPostedAtMeta,
        ),
      );
    }
    if (data.containsKey('bank_confirmed_at')) {
      context.handle(
        _bankConfirmedAtMeta,
        bankConfirmedAt.isAcceptableOrUnknown(
          data['bank_confirmed_at']!,
          _bankConfirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('evidence_note')) {
      context.handle(
        _evidenceNoteMeta,
        evidenceNote.isAcceptableOrUnknown(
          data['evidence_note']!,
          _evidenceNoteMeta,
        ),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, currencyAccountId, id},
  ];
  @override
  RepaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RepaymentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      cashAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_account_id'],
      ),
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      paymentInitiatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_initiated_at'],
      ),
      expectedDebitOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_debit_on'],
      ),
      cashDebitedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cash_debited_at'],
      ),
      creditPostedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}credit_posted_at'],
      ),
      bankConfirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bank_confirmed_at'],
      ),
      evidenceNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_note'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $RepaymentsTable createAlias(String alias) {
    return $RepaymentsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class RepaymentRow extends DataClass implements Insertable<RepaymentRow> {
  final String id;
  final String workspaceId;
  final String currencyAccountId;
  final String? cashAccountId;
  final int amountMinor;
  final String currency;

  /// `recorded` / `processing` / `cash_debited` / `credit_posted` / `bank_confirmed` / `failed` /
  /// `user_marked_paid` / `needs_review` / `reversed`。
  final String status;

  /// `auto_debit` / `manual` / `third_party` / `other`。
  final String method;
  final String? paymentInitiatedAt;
  final String? expectedDebitOn;
  final String? cashDebitedAt;
  final String? creditPostedAt;
  final String? bankConfirmedAt;
  final String? evidenceNote;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  const RepaymentRow({
    required this.id,
    required this.workspaceId,
    required this.currencyAccountId,
    this.cashAccountId,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.method,
    this.paymentInitiatedAt,
    this.expectedDebitOn,
    this.cashDebitedAt,
    this.creditPostedAt,
    this.bankConfirmedAt,
    this.evidenceNote,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    if (!nullToAbsent || cashAccountId != null) {
      map['cash_account_id'] = Variable<String>(cashAccountId);
    }
    map['amount_minor'] = Variable<int>(amountMinor);
    map['currency'] = Variable<String>(currency);
    map['status'] = Variable<String>(status);
    map['method'] = Variable<String>(method);
    if (!nullToAbsent || paymentInitiatedAt != null) {
      map['payment_initiated_at'] = Variable<String>(paymentInitiatedAt);
    }
    if (!nullToAbsent || expectedDebitOn != null) {
      map['expected_debit_on'] = Variable<String>(expectedDebitOn);
    }
    if (!nullToAbsent || cashDebitedAt != null) {
      map['cash_debited_at'] = Variable<String>(cashDebitedAt);
    }
    if (!nullToAbsent || creditPostedAt != null) {
      map['credit_posted_at'] = Variable<String>(creditPostedAt);
    }
    if (!nullToAbsent || bankConfirmedAt != null) {
      map['bank_confirmed_at'] = Variable<String>(bankConfirmedAt);
    }
    if (!nullToAbsent || evidenceNote != null) {
      map['evidence_note'] = Variable<String>(evidenceNote);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<String>(deletedAt);
    }
    return map;
  }

  RepaymentsCompanion toCompanion(bool nullToAbsent) {
    return RepaymentsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      cashAccountId: cashAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(cashAccountId),
      amountMinor: Value(amountMinor),
      currency: Value(currency),
      status: Value(status),
      method: Value(method),
      paymentInitiatedAt: paymentInitiatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentInitiatedAt),
      expectedDebitOn: expectedDebitOn == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedDebitOn),
      cashDebitedAt: cashDebitedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cashDebitedAt),
      creditPostedAt: creditPostedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(creditPostedAt),
      bankConfirmedAt: bankConfirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(bankConfirmedAt),
      evidenceNote: evidenceNote == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceNote),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory RepaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RepaymentRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      cashAccountId: serializer.fromJson<String?>(json['cashAccountId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      status: serializer.fromJson<String>(json['status']),
      method: serializer.fromJson<String>(json['method']),
      paymentInitiatedAt: serializer.fromJson<String?>(
        json['paymentInitiatedAt'],
      ),
      expectedDebitOn: serializer.fromJson<String?>(json['expectedDebitOn']),
      cashDebitedAt: serializer.fromJson<String?>(json['cashDebitedAt']),
      creditPostedAt: serializer.fromJson<String?>(json['creditPostedAt']),
      bankConfirmedAt: serializer.fromJson<String?>(json['bankConfirmedAt']),
      evidenceNote: serializer.fromJson<String?>(json['evidenceNote']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      deletedAt: serializer.fromJson<String?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'cashAccountId': serializer.toJson<String?>(cashAccountId),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'currency': serializer.toJson<String>(currency),
      'status': serializer.toJson<String>(status),
      'method': serializer.toJson<String>(method),
      'paymentInitiatedAt': serializer.toJson<String?>(paymentInitiatedAt),
      'expectedDebitOn': serializer.toJson<String?>(expectedDebitOn),
      'cashDebitedAt': serializer.toJson<String?>(cashDebitedAt),
      'creditPostedAt': serializer.toJson<String?>(creditPostedAt),
      'bankConfirmedAt': serializer.toJson<String?>(bankConfirmedAt),
      'evidenceNote': serializer.toJson<String?>(evidenceNote),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'deletedAt': serializer.toJson<String?>(deletedAt),
    };
  }

  RepaymentRow copyWith({
    String? id,
    String? workspaceId,
    String? currencyAccountId,
    Value<String?> cashAccountId = const Value.absent(),
    int? amountMinor,
    String? currency,
    String? status,
    String? method,
    Value<String?> paymentInitiatedAt = const Value.absent(),
    Value<String?> expectedDebitOn = const Value.absent(),
    Value<String?> cashDebitedAt = const Value.absent(),
    Value<String?> creditPostedAt = const Value.absent(),
    Value<String?> bankConfirmedAt = const Value.absent(),
    Value<String?> evidenceNote = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
    Value<String?> deletedAt = const Value.absent(),
  }) => RepaymentRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    cashAccountId: cashAccountId.present
        ? cashAccountId.value
        : this.cashAccountId,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    status: status ?? this.status,
    method: method ?? this.method,
    paymentInitiatedAt: paymentInitiatedAt.present
        ? paymentInitiatedAt.value
        : this.paymentInitiatedAt,
    expectedDebitOn: expectedDebitOn.present
        ? expectedDebitOn.value
        : this.expectedDebitOn,
    cashDebitedAt: cashDebitedAt.present
        ? cashDebitedAt.value
        : this.cashDebitedAt,
    creditPostedAt: creditPostedAt.present
        ? creditPostedAt.value
        : this.creditPostedAt,
    bankConfirmedAt: bankConfirmedAt.present
        ? bankConfirmedAt.value
        : this.bankConfirmedAt,
    evidenceNote: evidenceNote.present ? evidenceNote.value : this.evidenceNote,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  RepaymentRow copyWithCompanion(RepaymentsCompanion data) {
    return RepaymentRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      cashAccountId: data.cashAccountId.present
          ? data.cashAccountId.value
          : this.cashAccountId,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      status: data.status.present ? data.status.value : this.status,
      method: data.method.present ? data.method.value : this.method,
      paymentInitiatedAt: data.paymentInitiatedAt.present
          ? data.paymentInitiatedAt.value
          : this.paymentInitiatedAt,
      expectedDebitOn: data.expectedDebitOn.present
          ? data.expectedDebitOn.value
          : this.expectedDebitOn,
      cashDebitedAt: data.cashDebitedAt.present
          ? data.cashDebitedAt.value
          : this.cashDebitedAt,
      creditPostedAt: data.creditPostedAt.present
          ? data.creditPostedAt.value
          : this.creditPostedAt,
      bankConfirmedAt: data.bankConfirmedAt.present
          ? data.bankConfirmedAt.value
          : this.bankConfirmedAt,
      evidenceNote: data.evidenceNote.present
          ? data.evidenceNote.value
          : this.evidenceNote,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RepaymentRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('status: $status, ')
          ..write('method: $method, ')
          ..write('paymentInitiatedAt: $paymentInitiatedAt, ')
          ..write('expectedDebitOn: $expectedDebitOn, ')
          ..write('cashDebitedAt: $cashDebitedAt, ')
          ..write('creditPostedAt: $creditPostedAt, ')
          ..write('bankConfirmedAt: $bankConfirmedAt, ')
          ..write('evidenceNote: $evidenceNote, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    currencyAccountId,
    cashAccountId,
    amountMinor,
    currency,
    status,
    method,
    paymentInitiatedAt,
    expectedDebitOn,
    cashDebitedAt,
    creditPostedAt,
    bankConfirmedAt,
    evidenceNote,
    rowVersion,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RepaymentRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.cashAccountId == this.cashAccountId &&
          other.amountMinor == this.amountMinor &&
          other.currency == this.currency &&
          other.status == this.status &&
          other.method == this.method &&
          other.paymentInitiatedAt == this.paymentInitiatedAt &&
          other.expectedDebitOn == this.expectedDebitOn &&
          other.cashDebitedAt == this.cashDebitedAt &&
          other.creditPostedAt == this.creditPostedAt &&
          other.bankConfirmedAt == this.bankConfirmedAt &&
          other.evidenceNote == this.evidenceNote &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class RepaymentsCompanion extends UpdateCompanion<RepaymentRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<String?> cashAccountId;
  final Value<int> amountMinor;
  final Value<String> currency;
  final Value<String> status;
  final Value<String> method;
  final Value<String?> paymentInitiatedAt;
  final Value<String?> expectedDebitOn;
  final Value<String?> cashDebitedAt;
  final Value<String?> creditPostedAt;
  final Value<String?> bankConfirmedAt;
  final Value<String?> evidenceNote;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<String?> deletedAt;
  final Value<int> rowid;
  const RepaymentsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.cashAccountId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.status = const Value.absent(),
    this.method = const Value.absent(),
    this.paymentInitiatedAt = const Value.absent(),
    this.expectedDebitOn = const Value.absent(),
    this.cashDebitedAt = const Value.absent(),
    this.creditPostedAt = const Value.absent(),
    this.bankConfirmedAt = const Value.absent(),
    this.evidenceNote = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RepaymentsCompanion.insert({
    required String id,
    required String workspaceId,
    required String currencyAccountId,
    this.cashAccountId = const Value.absent(),
    required int amountMinor,
    required String currency,
    required String status,
    required String method,
    this.paymentInitiatedAt = const Value.absent(),
    this.expectedDebitOn = const Value.absent(),
    this.cashDebitedAt = const Value.absent(),
    this.creditPostedAt = const Value.absent(),
    this.bankConfirmedAt = const Value.absent(),
    this.evidenceNote = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       amountMinor = Value(amountMinor),
       currency = Value(currency),
       status = Value(status),
       method = Value(method),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<RepaymentRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<String>? cashAccountId,
    Expression<int>? amountMinor,
    Expression<String>? currency,
    Expression<String>? status,
    Expression<String>? method,
    Expression<String>? paymentInitiatedAt,
    Expression<String>? expectedDebitOn,
    Expression<String>? cashDebitedAt,
    Expression<String>? creditPostedAt,
    Expression<String>? bankConfirmedAt,
    Expression<String>? evidenceNote,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<String>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (cashAccountId != null) 'cash_account_id': cashAccountId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (currency != null) 'currency': currency,
      if (status != null) 'status': status,
      if (method != null) 'method': method,
      if (paymentInitiatedAt != null)
        'payment_initiated_at': paymentInitiatedAt,
      if (expectedDebitOn != null) 'expected_debit_on': expectedDebitOn,
      if (cashDebitedAt != null) 'cash_debited_at': cashDebitedAt,
      if (creditPostedAt != null) 'credit_posted_at': creditPostedAt,
      if (bankConfirmedAt != null) 'bank_confirmed_at': bankConfirmedAt,
      if (evidenceNote != null) 'evidence_note': evidenceNote,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RepaymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<String?>? cashAccountId,
    Value<int>? amountMinor,
    Value<String>? currency,
    Value<String>? status,
    Value<String>? method,
    Value<String?>? paymentInitiatedAt,
    Value<String?>? expectedDebitOn,
    Value<String?>? cashDebitedAt,
    Value<String?>? creditPostedAt,
    Value<String?>? bankConfirmedAt,
    Value<String?>? evidenceNote,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<String?>? deletedAt,
    Value<int>? rowid,
  }) {
    return RepaymentsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      cashAccountId: cashAccountId ?? this.cashAccountId,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      method: method ?? this.method,
      paymentInitiatedAt: paymentInitiatedAt ?? this.paymentInitiatedAt,
      expectedDebitOn: expectedDebitOn ?? this.expectedDebitOn,
      cashDebitedAt: cashDebitedAt ?? this.cashDebitedAt,
      creditPostedAt: creditPostedAt ?? this.creditPostedAt,
      bankConfirmedAt: bankConfirmedAt ?? this.bankConfirmedAt,
      evidenceNote: evidenceNote ?? this.evidenceNote,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (cashAccountId.present) {
      map['cash_account_id'] = Variable<String>(cashAccountId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (paymentInitiatedAt.present) {
      map['payment_initiated_at'] = Variable<String>(paymentInitiatedAt.value);
    }
    if (expectedDebitOn.present) {
      map['expected_debit_on'] = Variable<String>(expectedDebitOn.value);
    }
    if (cashDebitedAt.present) {
      map['cash_debited_at'] = Variable<String>(cashDebitedAt.value);
    }
    if (creditPostedAt.present) {
      map['credit_posted_at'] = Variable<String>(creditPostedAt.value);
    }
    if (bankConfirmedAt.present) {
      map['bank_confirmed_at'] = Variable<String>(bankConfirmedAt.value);
    }
    if (evidenceNote.present) {
      map['evidence_note'] = Variable<String>(evidenceNote.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<String>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RepaymentsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('cashAccountId: $cashAccountId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('status: $status, ')
          ..write('method: $method, ')
          ..write('paymentInitiatedAt: $paymentInitiatedAt, ')
          ..write('expectedDebitOn: $expectedDebitOn, ')
          ..write('cashDebitedAt: $cashDebitedAt, ')
          ..write('creditPostedAt: $creditPostedAt, ')
          ..write('bankConfirmedAt: $bankConfirmedAt, ')
          ..write('evidenceNote: $evidenceNote, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RepaymentAllocationsTable extends RepaymentAllocations
    with TableInfo<$RepaymentAllocationsTable, RepaymentAllocationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RepaymentAllocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyAccountIdMeta = const VerificationMeta(
    'currencyAccountId',
  );
  @override
  late final GeneratedColumn<String> currencyAccountId =
      GeneratedColumn<String>(
        'currency_account_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _repaymentIdMeta = const VerificationMeta(
    'repaymentId',
  );
  @override
  late final GeneratedColumn<String> repaymentId = GeneratedColumn<String>(
    'repayment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statementIdMeta = const VerificationMeta(
    'statementId',
  );
  @override
  late final GeneratedColumn<String> statementId = GeneratedColumn<String>(
    'statement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    workspaceId,
    currencyAccountId,
    repaymentId,
    statementId,
    amountMinor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'repayment_allocations';
  @override
  VerificationContext validateIntegrity(
    Insertable<RepaymentAllocationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('currency_account_id')) {
      context.handle(
        _currencyAccountIdMeta,
        currencyAccountId.isAcceptableOrUnknown(
          data['currency_account_id']!,
          _currencyAccountIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyAccountIdMeta);
    }
    if (data.containsKey('repayment_id')) {
      context.handle(
        _repaymentIdMeta,
        repaymentId.isAcceptableOrUnknown(
          data['repayment_id']!,
          _repaymentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_repaymentIdMeta);
    }
    if (data.containsKey('statement_id')) {
      context.handle(
        _statementIdMeta,
        statementId.isAcceptableOrUnknown(
          data['statement_id']!,
          _statementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_statementIdMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {repaymentId, statementId};
  @override
  RepaymentAllocationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RepaymentAllocationRow(
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      currencyAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_account_id'],
      )!,
      repaymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repayment_id'],
      )!,
      statementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}statement_id'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
    );
  }

  @override
  $RepaymentAllocationsTable createAlias(String alias) {
    return $RepaymentAllocationsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class RepaymentAllocationRow extends DataClass
    implements Insertable<RepaymentAllocationRow> {
  final String workspaceId;
  final String currencyAccountId;
  final String repaymentId;
  final String statementId;
  final int amountMinor;
  const RepaymentAllocationRow({
    required this.workspaceId,
    required this.currencyAccountId,
    required this.repaymentId,
    required this.statementId,
    required this.amountMinor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['workspace_id'] = Variable<String>(workspaceId);
    map['currency_account_id'] = Variable<String>(currencyAccountId);
    map['repayment_id'] = Variable<String>(repaymentId);
    map['statement_id'] = Variable<String>(statementId);
    map['amount_minor'] = Variable<int>(amountMinor);
    return map;
  }

  RepaymentAllocationsCompanion toCompanion(bool nullToAbsent) {
    return RepaymentAllocationsCompanion(
      workspaceId: Value(workspaceId),
      currencyAccountId: Value(currencyAccountId),
      repaymentId: Value(repaymentId),
      statementId: Value(statementId),
      amountMinor: Value(amountMinor),
    );
  }

  factory RepaymentAllocationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RepaymentAllocationRow(
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      currencyAccountId: serializer.fromJson<String>(json['currencyAccountId']),
      repaymentId: serializer.fromJson<String>(json['repaymentId']),
      statementId: serializer.fromJson<String>(json['statementId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workspaceId': serializer.toJson<String>(workspaceId),
      'currencyAccountId': serializer.toJson<String>(currencyAccountId),
      'repaymentId': serializer.toJson<String>(repaymentId),
      'statementId': serializer.toJson<String>(statementId),
      'amountMinor': serializer.toJson<int>(amountMinor),
    };
  }

  RepaymentAllocationRow copyWith({
    String? workspaceId,
    String? currencyAccountId,
    String? repaymentId,
    String? statementId,
    int? amountMinor,
  }) => RepaymentAllocationRow(
    workspaceId: workspaceId ?? this.workspaceId,
    currencyAccountId: currencyAccountId ?? this.currencyAccountId,
    repaymentId: repaymentId ?? this.repaymentId,
    statementId: statementId ?? this.statementId,
    amountMinor: amountMinor ?? this.amountMinor,
  );
  RepaymentAllocationRow copyWithCompanion(RepaymentAllocationsCompanion data) {
    return RepaymentAllocationRow(
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      currencyAccountId: data.currencyAccountId.present
          ? data.currencyAccountId.value
          : this.currencyAccountId,
      repaymentId: data.repaymentId.present
          ? data.repaymentId.value
          : this.repaymentId,
      statementId: data.statementId.present
          ? data.statementId.value
          : this.statementId,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RepaymentAllocationRow(')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('repaymentId: $repaymentId, ')
          ..write('statementId: $statementId, ')
          ..write('amountMinor: $amountMinor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    currencyAccountId,
    repaymentId,
    statementId,
    amountMinor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RepaymentAllocationRow &&
          other.workspaceId == this.workspaceId &&
          other.currencyAccountId == this.currencyAccountId &&
          other.repaymentId == this.repaymentId &&
          other.statementId == this.statementId &&
          other.amountMinor == this.amountMinor);
}

class RepaymentAllocationsCompanion
    extends UpdateCompanion<RepaymentAllocationRow> {
  final Value<String> workspaceId;
  final Value<String> currencyAccountId;
  final Value<String> repaymentId;
  final Value<String> statementId;
  final Value<int> amountMinor;
  final Value<int> rowid;
  const RepaymentAllocationsCompanion({
    this.workspaceId = const Value.absent(),
    this.currencyAccountId = const Value.absent(),
    this.repaymentId = const Value.absent(),
    this.statementId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RepaymentAllocationsCompanion.insert({
    required String workspaceId,
    required String currencyAccountId,
    required String repaymentId,
    required String statementId,
    required int amountMinor,
    this.rowid = const Value.absent(),
  }) : workspaceId = Value(workspaceId),
       currencyAccountId = Value(currencyAccountId),
       repaymentId = Value(repaymentId),
       statementId = Value(statementId),
       amountMinor = Value(amountMinor);
  static Insertable<RepaymentAllocationRow> custom({
    Expression<String>? workspaceId,
    Expression<String>? currencyAccountId,
    Expression<String>? repaymentId,
    Expression<String>? statementId,
    Expression<int>? amountMinor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (currencyAccountId != null) 'currency_account_id': currencyAccountId,
      if (repaymentId != null) 'repayment_id': repaymentId,
      if (statementId != null) 'statement_id': statementId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RepaymentAllocationsCompanion copyWith({
    Value<String>? workspaceId,
    Value<String>? currencyAccountId,
    Value<String>? repaymentId,
    Value<String>? statementId,
    Value<int>? amountMinor,
    Value<int>? rowid,
  }) {
    return RepaymentAllocationsCompanion(
      workspaceId: workspaceId ?? this.workspaceId,
      currencyAccountId: currencyAccountId ?? this.currencyAccountId,
      repaymentId: repaymentId ?? this.repaymentId,
      statementId: statementId ?? this.statementId,
      amountMinor: amountMinor ?? this.amountMinor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (currencyAccountId.present) {
      map['currency_account_id'] = Variable<String>(currencyAccountId.value);
    }
    if (repaymentId.present) {
      map['repayment_id'] = Variable<String>(repaymentId.value);
    }
    if (statementId.present) {
      map['statement_id'] = Variable<String>(statementId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RepaymentAllocationsCompanion(')
          ..write('workspaceId: $workspaceId, ')
          ..write('currencyAccountId: $currencyAccountId, ')
          ..write('repaymentId: $repaymentId, ')
          ..write('statementId: $statementId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReconciliationItemsTable extends ReconciliationItems
    with TableInfo<$ReconciliationItemsTable, ReconciliationItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReconciliationItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refsMeta = const VerificationMeta('refs');
  @override
  late final GeneratedColumn<String> refs = GeneratedColumn<String>(
    'refs',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedByMeta = const VerificationMeta(
    'resolvedBy',
  );
  @override
  late final GeneratedColumn<String> resolvedBy = GeneratedColumn<String>(
    'resolved_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resolvedAtMeta = const VerificationMeta(
    'resolvedAt',
  );
  @override
  late final GeneratedColumn<String> resolvedAt = GeneratedColumn<String>(
    'resolved_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowVersionMeta = const VerificationMeta(
    'rowVersion',
  );
  @override
  late final GeneratedColumn<int> rowVersion = GeneratedColumn<int>(
    'row_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceId,
    kind,
    refs,
    status,
    resolution,
    resolvedBy,
    resolvedAt,
    rowVersion,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reconciliation_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReconciliationItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('refs')) {
      context.handle(
        _refsMeta,
        refs.isAcceptableOrUnknown(data['refs']!, _refsMeta),
      );
    } else if (isInserting) {
      context.missing(_refsMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    if (data.containsKey('resolved_by')) {
      context.handle(
        _resolvedByMeta,
        resolvedBy.isAcceptableOrUnknown(data['resolved_by']!, _resolvedByMeta),
      );
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
        _resolvedAtMeta,
        resolvedAt.isAcceptableOrUnknown(data['resolved_at']!, _resolvedAtMeta),
      );
    }
    if (data.containsKey('row_version')) {
      context.handle(
        _rowVersionMeta,
        rowVersion.isAcceptableOrUnknown(data['row_version']!, _rowVersionMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workspaceId, id},
    {workspaceId, kind, refs},
  ];
  @override
  ReconciliationItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReconciliationItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      refs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refs'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
      resolvedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolved_by'],
      ),
      resolvedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolved_at'],
      ),
      rowVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReconciliationItemsTable createAlias(String alias) {
    return $ReconciliationItemsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class ReconciliationItemRow extends DataClass
    implements Insertable<ReconciliationItemRow> {
  final String id;
  final String workspaceId;

  /// `amount_mismatch` / `duplicate_repayment` / `refund_pending` / `unmatched_repayment`。
  final String kind;
  final String refs;

  /// `open` / `resolved` / `dismissed`。
  final String status;
  final String? resolution;

  /// `user` / `system`。
  final String? resolvedBy;
  final String? resolvedAt;
  final int rowVersion;
  final String createdAt;
  final String updatedAt;
  const ReconciliationItemRow({
    required this.id,
    required this.workspaceId,
    required this.kind,
    required this.refs,
    required this.status,
    this.resolution,
    this.resolvedBy,
    this.resolvedAt,
    required this.rowVersion,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['kind'] = Variable<String>(kind);
    map['refs'] = Variable<String>(refs);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    if (!nullToAbsent || resolvedBy != null) {
      map['resolved_by'] = Variable<String>(resolvedBy);
    }
    if (!nullToAbsent || resolvedAt != null) {
      map['resolved_at'] = Variable<String>(resolvedAt);
    }
    map['row_version'] = Variable<int>(rowVersion);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ReconciliationItemsCompanion toCompanion(bool nullToAbsent) {
    return ReconciliationItemsCompanion(
      id: Value(id),
      workspaceId: Value(workspaceId),
      kind: Value(kind),
      refs: Value(refs),
      status: Value(status),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
      resolvedBy: resolvedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedBy),
      resolvedAt: resolvedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAt),
      rowVersion: Value(rowVersion),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReconciliationItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReconciliationItemRow(
      id: serializer.fromJson<String>(json['id']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      kind: serializer.fromJson<String>(json['kind']),
      refs: serializer.fromJson<String>(json['refs']),
      status: serializer.fromJson<String>(json['status']),
      resolution: serializer.fromJson<String?>(json['resolution']),
      resolvedBy: serializer.fromJson<String?>(json['resolvedBy']),
      resolvedAt: serializer.fromJson<String?>(json['resolvedAt']),
      rowVersion: serializer.fromJson<int>(json['rowVersion']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'kind': serializer.toJson<String>(kind),
      'refs': serializer.toJson<String>(refs),
      'status': serializer.toJson<String>(status),
      'resolution': serializer.toJson<String?>(resolution),
      'resolvedBy': serializer.toJson<String?>(resolvedBy),
      'resolvedAt': serializer.toJson<String?>(resolvedAt),
      'rowVersion': serializer.toJson<int>(rowVersion),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ReconciliationItemRow copyWith({
    String? id,
    String? workspaceId,
    String? kind,
    String? refs,
    String? status,
    Value<String?> resolution = const Value.absent(),
    Value<String?> resolvedBy = const Value.absent(),
    Value<String?> resolvedAt = const Value.absent(),
    int? rowVersion,
    String? createdAt,
    String? updatedAt,
  }) => ReconciliationItemRow(
    id: id ?? this.id,
    workspaceId: workspaceId ?? this.workspaceId,
    kind: kind ?? this.kind,
    refs: refs ?? this.refs,
    status: status ?? this.status,
    resolution: resolution.present ? resolution.value : this.resolution,
    resolvedBy: resolvedBy.present ? resolvedBy.value : this.resolvedBy,
    resolvedAt: resolvedAt.present ? resolvedAt.value : this.resolvedAt,
    rowVersion: rowVersion ?? this.rowVersion,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReconciliationItemRow copyWithCompanion(ReconciliationItemsCompanion data) {
    return ReconciliationItemRow(
      id: data.id.present ? data.id.value : this.id,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      refs: data.refs.present ? data.refs.value : this.refs,
      status: data.status.present ? data.status.value : this.status,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
      resolvedBy: data.resolvedBy.present
          ? data.resolvedBy.value
          : this.resolvedBy,
      resolvedAt: data.resolvedAt.present
          ? data.resolvedAt.value
          : this.resolvedAt,
      rowVersion: data.rowVersion.present
          ? data.rowVersion.value
          : this.rowVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReconciliationItemRow(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('kind: $kind, ')
          ..write('refs: $refs, ')
          ..write('status: $status, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedBy: $resolvedBy, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceId,
    kind,
    refs,
    status,
    resolution,
    resolvedBy,
    resolvedAt,
    rowVersion,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReconciliationItemRow &&
          other.id == this.id &&
          other.workspaceId == this.workspaceId &&
          other.kind == this.kind &&
          other.refs == this.refs &&
          other.status == this.status &&
          other.resolution == this.resolution &&
          other.resolvedBy == this.resolvedBy &&
          other.resolvedAt == this.resolvedAt &&
          other.rowVersion == this.rowVersion &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ReconciliationItemsCompanion
    extends UpdateCompanion<ReconciliationItemRow> {
  final Value<String> id;
  final Value<String> workspaceId;
  final Value<String> kind;
  final Value<String> refs;
  final Value<String> status;
  final Value<String?> resolution;
  final Value<String?> resolvedBy;
  final Value<String?> resolvedAt;
  final Value<int> rowVersion;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ReconciliationItemsCompanion({
    this.id = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.refs = const Value.absent(),
    this.status = const Value.absent(),
    this.resolution = const Value.absent(),
    this.resolvedBy = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReconciliationItemsCompanion.insert({
    required String id,
    required String workspaceId,
    required String kind,
    required String refs,
    this.status = const Value.absent(),
    this.resolution = const Value.absent(),
    this.resolvedBy = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowVersion = const Value.absent(),
    required String createdAt,
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       workspaceId = Value(workspaceId),
       kind = Value(kind),
       refs = Value(refs),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ReconciliationItemRow> custom({
    Expression<String>? id,
    Expression<String>? workspaceId,
    Expression<String>? kind,
    Expression<String>? refs,
    Expression<String>? status,
    Expression<String>? resolution,
    Expression<String>? resolvedBy,
    Expression<String>? resolvedAt,
    Expression<int>? rowVersion,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (kind != null) 'kind': kind,
      if (refs != null) 'refs': refs,
      if (status != null) 'status': status,
      if (resolution != null) 'resolution': resolution,
      if (resolvedBy != null) 'resolved_by': resolvedBy,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (rowVersion != null) 'row_version': rowVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReconciliationItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? workspaceId,
    Value<String>? kind,
    Value<String>? refs,
    Value<String>? status,
    Value<String?>? resolution,
    Value<String?>? resolvedBy,
    Value<String?>? resolvedAt,
    Value<int>? rowVersion,
    Value<String>? createdAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReconciliationItemsCompanion(
      id: id ?? this.id,
      workspaceId: workspaceId ?? this.workspaceId,
      kind: kind ?? this.kind,
      refs: refs ?? this.refs,
      status: status ?? this.status,
      resolution: resolution ?? this.resolution,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      rowVersion: rowVersion ?? this.rowVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (refs.present) {
      map['refs'] = Variable<String>(refs.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (resolvedBy.present) {
      map['resolved_by'] = Variable<String>(resolvedBy.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<String>(resolvedAt.value);
    }
    if (rowVersion.present) {
      map['row_version'] = Variable<int>(rowVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReconciliationItemsCompanion(')
          ..write('id: $id, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('kind: $kind, ')
          ..write('refs: $refs, ')
          ..write('status: $status, ')
          ..write('resolution: $resolution, ')
          ..write('resolvedBy: $resolvedBy, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('rowVersion: $rowVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WorkspacesTable workspaces = $WorkspacesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $BanksTable banks = $BanksTable(this);
  late final $CreditPoolsTable creditPools = $CreditPoolsTable(this);
  late final $CreditAccountsTable creditAccounts = $CreditAccountsTable(this);
  late final $CurrencyAccountsTable currencyAccounts = $CurrencyAccountsTable(
    this,
  );
  late final $CardsTable cards = $CardsTable(this);
  late final $BillingRuleVersionsTable billingRuleVersions =
      $BillingRuleVersionsTable(this);
  late final $LimitSnapshotsTable limitSnapshots = $LimitSnapshotsTable(this);
  late final $CashAccountsTable cashAccounts = $CashAccountsTable(this);
  late final $CashBalanceSnapshotsTable cashBalanceSnapshots =
      $CashBalanceSnapshotsTable(this);
  late final $RecurringItemsTable recurringItems = $RecurringItemsTable(this);
  late final $CashEventsTable cashEvents = $CashEventsTable(this);
  late final $SnapshotIncludedEventsTable snapshotIncludedEvents =
      $SnapshotIncludedEventsTable(this);
  late final $RecurringOverridesTable recurringOverrides =
      $RecurringOverridesTable(this);
  late final $ScenariosTable scenarios = $ScenariosTable(this);
  late final $ScenarioRunsTable scenarioRuns = $ScenarioRunsTable(this);
  late final $CardTransactionsTable cardTransactions = $CardTransactionsTable(
    this,
  );
  late final $StatementVersionsTable statementVersions =
      $StatementVersionsTable(this);
  late final $StatementsTable statements = $StatementsTable(this);
  late final $InstallmentPlansTable installmentPlans = $InstallmentPlansTable(
    this,
  );
  late final $InstallmentScheduleTable installmentSchedule =
      $InstallmentScheduleTable(this);
  late final $RepaymentsTable repayments = $RepaymentsTable(this);
  late final $RepaymentAllocationsTable repaymentAllocations =
      $RepaymentAllocationsTable(this);
  late final $ReconciliationItemsTable reconciliationItems =
      $ReconciliationItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workspaces,
    appSettings,
    banks,
    creditPools,
    creditAccounts,
    currencyAccounts,
    cards,
    billingRuleVersions,
    limitSnapshots,
    cashAccounts,
    cashBalanceSnapshots,
    recurringItems,
    cashEvents,
    snapshotIncludedEvents,
    recurringOverrides,
    scenarios,
    scenarioRuns,
    cardTransactions,
    statementVersions,
    statements,
    installmentPlans,
    installmentSchedule,
    repayments,
    repaymentAllocations,
    reconciliationItems,
  ];
}

typedef $$WorkspacesTableCreateCompanionBuilder = WorkspacesCompanion Function({
  required String id,
  required String kind,
  required String name,
  required String createdAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});
typedef $$WorkspacesTableUpdateCompanionBuilder = WorkspacesCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> name,
  Value<String> createdAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});

class $$WorkspacesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspacesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkspacesTable> {
  $$WorkspacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$WorkspacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkspacesTable,
          WorkspaceRow,
          $$WorkspacesTableFilterComposer,
          $$WorkspacesTableOrderingComposer,
          $$WorkspacesTableAnnotationComposer,
          $$WorkspacesTableCreateCompanionBuilder,
          $$WorkspacesTableUpdateCompanionBuilder,
          (
            WorkspaceRow,
            BaseReferences<_$AppDatabase, $WorkspacesTable, WorkspaceRow>,
          ),
          WorkspaceRow,
          PrefetchHooks Function()
        > {
  $$WorkspacesTableTableManager(_$AppDatabase db, $WorkspacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesCompanion(
                id: id,
                kind: kind,
                name: name,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String name,
                required String createdAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkspacesCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                createdAt: createdAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkspacesTable, WorkspaceRow>(table),
                  BaseReferences<_$AppDatabase, $WorkspacesTable, WorkspaceRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkspacesTable,
      WorkspaceRow,
      $$WorkspacesTableFilterComposer,
      $$WorkspacesTableOrderingComposer,
      $$WorkspacesTableAnnotationComposer,
      $$WorkspacesTableCreateCompanionBuilder,
      $$WorkspacesTableUpdateCompanionBuilder,
      (
        WorkspaceRow,
        BaseReferences<_$AppDatabase, $WorkspacesTable, WorkspaceRow>,
      ),
      WorkspaceRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSettingRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingRow,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
          ),
          AppSettingRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppSettingsTable,
                    AppSettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSettingRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingRow,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
      ),
      AppSettingRow,
      PrefetchHooks Function()
    >;
typedef $$BanksTableCreateCompanionBuilder = BanksCompanion Function({
  required String id,
  required String workspaceId,
  required String name,
  Value<String> country,
  Value<String> businessTzDefault,
  Value<bool> isBuiltin,
  required String createdAt,
  Value<int> rowid,
});
typedef $$BanksTableUpdateCompanionBuilder = BanksCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> name,
  Value<String> country,
  Value<String> businessTzDefault,
  Value<bool> isBuiltin,
  Value<String> createdAt,
  Value<int> rowid,
});

class $$BanksTableFilterComposer extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessTzDefault => $composableBuilder(
    column: $table.businessTzDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BanksTableOrderingComposer
    extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get country => $composableBuilder(
    column: $table.country,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessTzDefault => $composableBuilder(
    column: $table.businessTzDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isBuiltin => $composableBuilder(
    column: $table.isBuiltin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BanksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BanksTable> {
  $$BanksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<String> get businessTzDefault => $composableBuilder(
    column: $table.businessTzDefault,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isBuiltin =>
      $composableBuilder(column: $table.isBuiltin, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BanksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BanksTable,
          BankRow,
          $$BanksTableFilterComposer,
          $$BanksTableOrderingComposer,
          $$BanksTableAnnotationComposer,
          $$BanksTableCreateCompanionBuilder,
          $$BanksTableUpdateCompanionBuilder,
          (BankRow, BaseReferences<_$AppDatabase, $BanksTable, BankRow>),
          BankRow,
          PrefetchHooks Function()
        > {
  $$BanksTableTableManager(_$AppDatabase db, $BanksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BanksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BanksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BanksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> country = const Value.absent(),
                Value<String> businessTzDefault = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BanksCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                country: country,
                businessTzDefault: businessTzDefault,
                isBuiltin: isBuiltin,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                Value<String> country = const Value.absent(),
                Value<String> businessTzDefault = const Value.absent(),
                Value<bool> isBuiltin = const Value.absent(),
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BanksCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                country: country,
                businessTzDefault: businessTzDefault,
                isBuiltin: isBuiltin,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BanksTable, BankRow>(table),
                  BaseReferences<_$AppDatabase, $BanksTable, BankRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BanksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BanksTable,
      BankRow,
      $$BanksTableFilterComposer,
      $$BanksTableOrderingComposer,
      $$BanksTableAnnotationComposer,
      $$BanksTableCreateCompanionBuilder,
      $$BanksTableUpdateCompanionBuilder,
      (BankRow, BaseReferences<_$AppDatabase, $BanksTable, BankRow>),
      BankRow,
      PrefetchHooks Function()
    >;
typedef $$CreditPoolsTableCreateCompanionBuilder =
    CreditPoolsCompanion Function({
      required String id,
      required String workspaceId,
      required String bankId,
      required String name,
      Value<String?> parentPoolId,
      required int sharedLimitMinor,
      required String currency,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$CreditPoolsTableUpdateCompanionBuilder =
    CreditPoolsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> bankId,
      Value<String> name,
      Value<String?> parentPoolId,
      Value<int> sharedLimitMinor,
      Value<String> currency,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$CreditPoolsTableFilterComposer
    extends Composer<_$AppDatabase, $CreditPoolsTable> {
  $$CreditPoolsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentPoolId => $composableBuilder(
    column: $table.parentPoolId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sharedLimitMinor => $composableBuilder(
    column: $table.sharedLimitMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CreditPoolsTableOrderingComposer
    extends Composer<_$AppDatabase, $CreditPoolsTable> {
  $$CreditPoolsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentPoolId => $composableBuilder(
    column: $table.parentPoolId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sharedLimitMinor => $composableBuilder(
    column: $table.sharedLimitMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CreditPoolsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CreditPoolsTable> {
  $$CreditPoolsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bankId =>
      $composableBuilder(column: $table.bankId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get parentPoolId => $composableBuilder(
    column: $table.parentPoolId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sharedLimitMinor => $composableBuilder(
    column: $table.sharedLimitMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CreditPoolsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CreditPoolsTable,
          CreditPoolRow,
          $$CreditPoolsTableFilterComposer,
          $$CreditPoolsTableOrderingComposer,
          $$CreditPoolsTableAnnotationComposer,
          $$CreditPoolsTableCreateCompanionBuilder,
          $$CreditPoolsTableUpdateCompanionBuilder,
          (
            CreditPoolRow,
            BaseReferences<_$AppDatabase, $CreditPoolsTable, CreditPoolRow>,
          ),
          CreditPoolRow,
          PrefetchHooks Function()
        > {
  $$CreditPoolsTableTableManager(_$AppDatabase db, $CreditPoolsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CreditPoolsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CreditPoolsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CreditPoolsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> bankId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> parentPoolId = const Value.absent(),
                Value<int> sharedLimitMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CreditPoolsCompanion(
                id: id,
                workspaceId: workspaceId,
                bankId: bankId,
                name: name,
                parentPoolId: parentPoolId,
                sharedLimitMinor: sharedLimitMinor,
                currency: currency,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String bankId,
                required String name,
                Value<String?> parentPoolId = const Value.absent(),
                required int sharedLimitMinor,
                required String currency,
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CreditPoolsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                bankId: bankId,
                name: name,
                parentPoolId: parentPoolId,
                sharedLimitMinor: sharedLimitMinor,
                currency: currency,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CreditPoolsTable, CreditPoolRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CreditPoolsTable,
                    CreditPoolRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CreditPoolsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CreditPoolsTable,
      CreditPoolRow,
      $$CreditPoolsTableFilterComposer,
      $$CreditPoolsTableOrderingComposer,
      $$CreditPoolsTableAnnotationComposer,
      $$CreditPoolsTableCreateCompanionBuilder,
      $$CreditPoolsTableUpdateCompanionBuilder,
      (
        CreditPoolRow,
        BaseReferences<_$AppDatabase, $CreditPoolsTable, CreditPoolRow>,
      ),
      CreditPoolRow,
      PrefetchHooks Function()
    >;
typedef $$CreditAccountsTableCreateCompanionBuilder =
    CreditAccountsCompanion Function({
      required String id,
      required String workspaceId,
      required String bankId,
      Value<String?> productName,
      required String holderAlias,
      Value<String> businessTz,
      Value<String> status,
      Value<String?> openedOn,
      Value<String?> closedOn,
      Value<String?> poolId,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$CreditAccountsTableUpdateCompanionBuilder =
    CreditAccountsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> bankId,
      Value<String?> productName,
      Value<String> holderAlias,
      Value<String> businessTz,
      Value<String> status,
      Value<String?> openedOn,
      Value<String?> closedOn,
      Value<String?> poolId,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

class $$CreditAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $CreditAccountsTable> {
  $$CreditAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get holderAlias => $composableBuilder(
    column: $table.holderAlias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get businessTz => $composableBuilder(
    column: $table.businessTz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openedOn => $composableBuilder(
    column: $table.openedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get closedOn => $composableBuilder(
    column: $table.closedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poolId => $composableBuilder(
    column: $table.poolId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CreditAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $CreditAccountsTable> {
  $$CreditAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bankId => $composableBuilder(
    column: $table.bankId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get holderAlias => $composableBuilder(
    column: $table.holderAlias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get businessTz => $composableBuilder(
    column: $table.businessTz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openedOn => $composableBuilder(
    column: $table.openedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closedOn => $composableBuilder(
    column: $table.closedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poolId => $composableBuilder(
    column: $table.poolId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CreditAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CreditAccountsTable> {
  $$CreditAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bankId =>
      $composableBuilder(column: $table.bankId, builder: (column) => column);

  GeneratedColumn<String> get productName => $composableBuilder(
    column: $table.productName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get holderAlias => $composableBuilder(
    column: $table.holderAlias,
    builder: (column) => column,
  );

  GeneratedColumn<String> get businessTz => $composableBuilder(
    column: $table.businessTz,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get openedOn =>
      $composableBuilder(column: $table.openedOn, builder: (column) => column);

  GeneratedColumn<String> get closedOn =>
      $composableBuilder(column: $table.closedOn, builder: (column) => column);

  GeneratedColumn<String> get poolId =>
      $composableBuilder(column: $table.poolId, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CreditAccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CreditAccountsTable,
          CreditAccountRow,
          $$CreditAccountsTableFilterComposer,
          $$CreditAccountsTableOrderingComposer,
          $$CreditAccountsTableAnnotationComposer,
          $$CreditAccountsTableCreateCompanionBuilder,
          $$CreditAccountsTableUpdateCompanionBuilder,
          (
            CreditAccountRow,
            BaseReferences<
              _$AppDatabase,
              $CreditAccountsTable,
              CreditAccountRow
            >,
          ),
          CreditAccountRow,
          PrefetchHooks Function()
        > {
  $$CreditAccountsTableTableManager(
    _$AppDatabase db,
    $CreditAccountsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CreditAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CreditAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CreditAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> bankId = const Value.absent(),
                Value<String?> productName = const Value.absent(),
                Value<String> holderAlias = const Value.absent(),
                Value<String> businessTz = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> openedOn = const Value.absent(),
                Value<String?> closedOn = const Value.absent(),
                Value<String?> poolId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CreditAccountsCompanion(
                id: id,
                workspaceId: workspaceId,
                bankId: bankId,
                productName: productName,
                holderAlias: holderAlias,
                businessTz: businessTz,
                status: status,
                openedOn: openedOn,
                closedOn: closedOn,
                poolId: poolId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String bankId,
                Value<String?> productName = const Value.absent(),
                required String holderAlias,
                Value<String> businessTz = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> openedOn = const Value.absent(),
                Value<String?> closedOn = const Value.absent(),
                Value<String?> poolId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CreditAccountsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                bankId: bankId,
                productName: productName,
                holderAlias: holderAlias,
                businessTz: businessTz,
                status: status,
                openedOn: openedOn,
                closedOn: closedOn,
                poolId: poolId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CreditAccountsTable, CreditAccountRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CreditAccountsTable,
                    CreditAccountRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CreditAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CreditAccountsTable,
      CreditAccountRow,
      $$CreditAccountsTableFilterComposer,
      $$CreditAccountsTableOrderingComposer,
      $$CreditAccountsTableAnnotationComposer,
      $$CreditAccountsTableCreateCompanionBuilder,
      $$CreditAccountsTableUpdateCompanionBuilder,
      (
        CreditAccountRow,
        BaseReferences<_$AppDatabase, $CreditAccountsTable, CreditAccountRow>,
      ),
      CreditAccountRow,
      PrefetchHooks Function()
    >;
typedef $$CurrencyAccountsTableCreateCompanionBuilder =
    CurrencyAccountsCompanion Function({
      required String id,
      required String workspaceId,
      required String creditAccountId,
      required String currency,
      Value<bool> isPrimary,
      Value<int> rowVersion,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$CurrencyAccountsTableUpdateCompanionBuilder =
    CurrencyAccountsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> creditAccountId,
      Value<String> currency,
      Value<bool> isPrimary,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$CurrencyAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $CurrencyAccountsTable> {
  $$CurrencyAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CurrencyAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $CurrencyAccountsTable> {
  $$CurrencyAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CurrencyAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CurrencyAccountsTable> {
  $$CurrencyAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CurrencyAccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CurrencyAccountsTable,
          CurrencyAccountRow,
          $$CurrencyAccountsTableFilterComposer,
          $$CurrencyAccountsTableOrderingComposer,
          $$CurrencyAccountsTableAnnotationComposer,
          $$CurrencyAccountsTableCreateCompanionBuilder,
          $$CurrencyAccountsTableUpdateCompanionBuilder,
          (
            CurrencyAccountRow,
            BaseReferences<
              _$AppDatabase,
              $CurrencyAccountsTable,
              CurrencyAccountRow
            >,
          ),
          CurrencyAccountRow,
          PrefetchHooks Function()
        > {
  $$CurrencyAccountsTableTableManager(
    _$AppDatabase db,
    $CurrencyAccountsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CurrencyAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CurrencyAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CurrencyAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> creditAccountId = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CurrencyAccountsCompanion(
                id: id,
                workspaceId: workspaceId,
                creditAccountId: creditAccountId,
                currency: currency,
                isPrimary: isPrimary,
                rowVersion: rowVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String creditAccountId,
                required String currency,
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => CurrencyAccountsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                creditAccountId: creditAccountId,
                currency: currency,
                isPrimary: isPrimary,
                rowVersion: rowVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CurrencyAccountsTable, CurrencyAccountRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CurrencyAccountsTable,
                    CurrencyAccountRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CurrencyAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CurrencyAccountsTable,
      CurrencyAccountRow,
      $$CurrencyAccountsTableFilterComposer,
      $$CurrencyAccountsTableOrderingComposer,
      $$CurrencyAccountsTableAnnotationComposer,
      $$CurrencyAccountsTableCreateCompanionBuilder,
      $$CurrencyAccountsTableUpdateCompanionBuilder,
      (
        CurrencyAccountRow,
        BaseReferences<
          _$AppDatabase,
          $CurrencyAccountsTable,
          CurrencyAccountRow
        >,
      ),
      CurrencyAccountRow,
      PrefetchHooks Function()
    >;
typedef $$CardsTableCreateCompanionBuilder = CardsCompanion Function({
  required String id,
  required String workspaceId,
  required String creditAccountId,
  required String last4,
  Value<String?> network,
  required String holderKind,
  Value<String?> primaryCardId,
  required String status,
  Value<String?> expiresYm,
  Value<String?> replacedByCardId,
  Value<String?> alias,
  Value<String?> effectiveFrom,
  Value<String?> closedOn,
  Value<int> rowVersion,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$CardsTableUpdateCompanionBuilder = CardsCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> creditAccountId,
  Value<String> last4,
  Value<String?> network,
  Value<String> holderKind,
  Value<String?> primaryCardId,
  Value<String> status,
  Value<String?> expiresYm,
  Value<String?> replacedByCardId,
  Value<String?> alias,
  Value<String?> effectiveFrom,
  Value<String?> closedOn,
  Value<int> rowVersion,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$CardsTableFilterComposer extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get last4 => $composableBuilder(
    column: $table.last4,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get holderKind => $composableBuilder(
    column: $table.holderKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get primaryCardId => $composableBuilder(
    column: $table.primaryCardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expiresYm => $composableBuilder(
    column: $table.expiresYm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replacedByCardId => $composableBuilder(
    column: $table.replacedByCardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get closedOn => $composableBuilder(
    column: $table.closedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get last4 => $composableBuilder(
    column: $table.last4,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get network => $composableBuilder(
    column: $table.network,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get holderKind => $composableBuilder(
    column: $table.holderKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get primaryCardId => $composableBuilder(
    column: $table.primaryCardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expiresYm => $composableBuilder(
    column: $table.expiresYm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replacedByCardId => $composableBuilder(
    column: $table.replacedByCardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get closedOn => $composableBuilder(
    column: $table.closedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creditAccountId => $composableBuilder(
    column: $table.creditAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get last4 =>
      $composableBuilder(column: $table.last4, builder: (column) => column);

  GeneratedColumn<String> get network =>
      $composableBuilder(column: $table.network, builder: (column) => column);

  GeneratedColumn<String> get holderKind => $composableBuilder(
    column: $table.holderKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get primaryCardId => $composableBuilder(
    column: $table.primaryCardId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get expiresYm =>
      $composableBuilder(column: $table.expiresYm, builder: (column) => column);

  GeneratedColumn<String> get replacedByCardId => $composableBuilder(
    column: $table.replacedByCardId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get closedOn =>
      $composableBuilder(column: $table.closedOn, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardsTable,
          CardRow,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (CardRow, BaseReferences<_$AppDatabase, $CardsTable, CardRow>),
          CardRow,
          PrefetchHooks Function()
        > {
  $$CardsTableTableManager(_$AppDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> creditAccountId = const Value.absent(),
                Value<String> last4 = const Value.absent(),
                Value<String?> network = const Value.absent(),
                Value<String> holderKind = const Value.absent(),
                Value<String?> primaryCardId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> expiresYm = const Value.absent(),
                Value<String?> replacedByCardId = const Value.absent(),
                Value<String?> alias = const Value.absent(),
                Value<String?> effectiveFrom = const Value.absent(),
                Value<String?> closedOn = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                workspaceId: workspaceId,
                creditAccountId: creditAccountId,
                last4: last4,
                network: network,
                holderKind: holderKind,
                primaryCardId: primaryCardId,
                status: status,
                expiresYm: expiresYm,
                replacedByCardId: replacedByCardId,
                alias: alias,
                effectiveFrom: effectiveFrom,
                closedOn: closedOn,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String creditAccountId,
                required String last4,
                Value<String?> network = const Value.absent(),
                required String holderKind,
                Value<String?> primaryCardId = const Value.absent(),
                required String status,
                Value<String?> expiresYm = const Value.absent(),
                Value<String?> replacedByCardId = const Value.absent(),
                Value<String?> alias = const Value.absent(),
                Value<String?> effectiveFrom = const Value.absent(),
                Value<String?> closedOn = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                creditAccountId: creditAccountId,
                last4: last4,
                network: network,
                holderKind: holderKind,
                primaryCardId: primaryCardId,
                status: status,
                expiresYm: expiresYm,
                replacedByCardId: replacedByCardId,
                alias: alias,
                effectiveFrom: effectiveFrom,
                closedOn: closedOn,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardsTable, CardRow>(table),
                  BaseReferences<_$AppDatabase, $CardsTable, CardRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardsTable,
      CardRow,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (CardRow, BaseReferences<_$AppDatabase, $CardsTable, CardRow>),
      CardRow,
      PrefetchHooks Function()
    >;
typedef $$BillingRuleVersionsTableCreateCompanionBuilder =
    BillingRuleVersionsCompanion Function({
      required String id,
      required String workspaceId,
      required String subjectKind,
      required String subjectId,
      required int statementDay,
      Value<bool> statementDayInclusive,
      required String dueKind,
      Value<int?> dueDay,
      Value<int> dueMonthOffset,
      Value<int?> dueDays,
      Value<String> dueDayKind,
      Value<String> holidayRollover,
      Value<String?> cutoffTime,
      Value<int> postingDelayMinDays,
      Value<int> postingDelayMaxDays,
      required String source,
      Value<String?> effectiveFrom,
      Value<String?> effectiveTo,
      Value<String?> verifiedOn,
      required int version,
      required String reviewStatus,
      Value<String?> exceptions,
      required String createdAt,
      Value<int> rowid,
    });
typedef $$BillingRuleVersionsTableUpdateCompanionBuilder =
    BillingRuleVersionsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> subjectKind,
      Value<String> subjectId,
      Value<int> statementDay,
      Value<bool> statementDayInclusive,
      Value<String> dueKind,
      Value<int?> dueDay,
      Value<int> dueMonthOffset,
      Value<int?> dueDays,
      Value<String> dueDayKind,
      Value<String> holidayRollover,
      Value<String?> cutoffTime,
      Value<int> postingDelayMinDays,
      Value<int> postingDelayMaxDays,
      Value<String> source,
      Value<String?> effectiveFrom,
      Value<String?> effectiveTo,
      Value<String?> verifiedOn,
      Value<int> version,
      Value<String> reviewStatus,
      Value<String?> exceptions,
      Value<String> createdAt,
      Value<int> rowid,
    });

class $$BillingRuleVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $BillingRuleVersionsTable> {
  $$BillingRuleVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectKind => $composableBuilder(
    column: $table.subjectKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get statementDayInclusive => $composableBuilder(
    column: $table.statementDayInclusive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueKind => $composableBuilder(
    column: $table.dueKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueDay => $composableBuilder(
    column: $table.dueDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueMonthOffset => $composableBuilder(
    column: $table.dueMonthOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueDays => $composableBuilder(
    column: $table.dueDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDayKind => $composableBuilder(
    column: $table.dueDayKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get holidayRollover => $composableBuilder(
    column: $table.holidayRollover,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cutoffTime => $composableBuilder(
    column: $table.cutoffTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get postingDelayMinDays => $composableBuilder(
    column: $table.postingDelayMinDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get postingDelayMaxDays => $composableBuilder(
    column: $table.postingDelayMaxDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verifiedOn => $composableBuilder(
    column: $table.verifiedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewStatus => $composableBuilder(
    column: $table.reviewStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exceptions => $composableBuilder(
    column: $table.exceptions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BillingRuleVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $BillingRuleVersionsTable> {
  $$BillingRuleVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectKind => $composableBuilder(
    column: $table.subjectKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get statementDayInclusive => $composableBuilder(
    column: $table.statementDayInclusive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueKind => $composableBuilder(
    column: $table.dueKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueDay => $composableBuilder(
    column: $table.dueDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueMonthOffset => $composableBuilder(
    column: $table.dueMonthOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueDays => $composableBuilder(
    column: $table.dueDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDayKind => $composableBuilder(
    column: $table.dueDayKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get holidayRollover => $composableBuilder(
    column: $table.holidayRollover,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cutoffTime => $composableBuilder(
    column: $table.cutoffTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get postingDelayMinDays => $composableBuilder(
    column: $table.postingDelayMinDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get postingDelayMaxDays => $composableBuilder(
    column: $table.postingDelayMaxDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verifiedOn => $composableBuilder(
    column: $table.verifiedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewStatus => $composableBuilder(
    column: $table.reviewStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exceptions => $composableBuilder(
    column: $table.exceptions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BillingRuleVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BillingRuleVersionsTable> {
  $$BillingRuleVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subjectKind => $composableBuilder(
    column: $table.subjectKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<int> get statementDay => $composableBuilder(
    column: $table.statementDay,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get statementDayInclusive => $composableBuilder(
    column: $table.statementDayInclusive,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueKind =>
      $composableBuilder(column: $table.dueKind, builder: (column) => column);

  GeneratedColumn<int> get dueDay =>
      $composableBuilder(column: $table.dueDay, builder: (column) => column);

  GeneratedColumn<int> get dueMonthOffset => $composableBuilder(
    column: $table.dueMonthOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get dueDays =>
      $composableBuilder(column: $table.dueDays, builder: (column) => column);

  GeneratedColumn<String> get dueDayKind => $composableBuilder(
    column: $table.dueDayKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get holidayRollover => $composableBuilder(
    column: $table.holidayRollover,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cutoffTime => $composableBuilder(
    column: $table.cutoffTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get postingDelayMinDays => $composableBuilder(
    column: $table.postingDelayMinDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get postingDelayMaxDays => $composableBuilder(
    column: $table.postingDelayMaxDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get effectiveFrom => $composableBuilder(
    column: $table.effectiveFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveTo => $composableBuilder(
    column: $table.effectiveTo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get verifiedOn => $composableBuilder(
    column: $table.verifiedOn,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get reviewStatus => $composableBuilder(
    column: $table.reviewStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exceptions => $composableBuilder(
    column: $table.exceptions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BillingRuleVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BillingRuleVersionsTable,
          BillingRuleVersionRow,
          $$BillingRuleVersionsTableFilterComposer,
          $$BillingRuleVersionsTableOrderingComposer,
          $$BillingRuleVersionsTableAnnotationComposer,
          $$BillingRuleVersionsTableCreateCompanionBuilder,
          $$BillingRuleVersionsTableUpdateCompanionBuilder,
          (
            BillingRuleVersionRow,
            BaseReferences<
              _$AppDatabase,
              $BillingRuleVersionsTable,
              BillingRuleVersionRow
            >,
          ),
          BillingRuleVersionRow,
          PrefetchHooks Function()
        > {
  $$BillingRuleVersionsTableTableManager(
    _$AppDatabase db,
    $BillingRuleVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BillingRuleVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BillingRuleVersionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BillingRuleVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> subjectKind = const Value.absent(),
                Value<String> subjectId = const Value.absent(),
                Value<int> statementDay = const Value.absent(),
                Value<bool> statementDayInclusive = const Value.absent(),
                Value<String> dueKind = const Value.absent(),
                Value<int?> dueDay = const Value.absent(),
                Value<int> dueMonthOffset = const Value.absent(),
                Value<int?> dueDays = const Value.absent(),
                Value<String> dueDayKind = const Value.absent(),
                Value<String> holidayRollover = const Value.absent(),
                Value<String?> cutoffTime = const Value.absent(),
                Value<int> postingDelayMinDays = const Value.absent(),
                Value<int> postingDelayMaxDays = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> effectiveFrom = const Value.absent(),
                Value<String?> effectiveTo = const Value.absent(),
                Value<String?> verifiedOn = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> reviewStatus = const Value.absent(),
                Value<String?> exceptions = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BillingRuleVersionsCompanion(
                id: id,
                workspaceId: workspaceId,
                subjectKind: subjectKind,
                subjectId: subjectId,
                statementDay: statementDay,
                statementDayInclusive: statementDayInclusive,
                dueKind: dueKind,
                dueDay: dueDay,
                dueMonthOffset: dueMonthOffset,
                dueDays: dueDays,
                dueDayKind: dueDayKind,
                holidayRollover: holidayRollover,
                cutoffTime: cutoffTime,
                postingDelayMinDays: postingDelayMinDays,
                postingDelayMaxDays: postingDelayMaxDays,
                source: source,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                verifiedOn: verifiedOn,
                version: version,
                reviewStatus: reviewStatus,
                exceptions: exceptions,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String subjectKind,
                required String subjectId,
                required int statementDay,
                Value<bool> statementDayInclusive = const Value.absent(),
                required String dueKind,
                Value<int?> dueDay = const Value.absent(),
                Value<int> dueMonthOffset = const Value.absent(),
                Value<int?> dueDays = const Value.absent(),
                Value<String> dueDayKind = const Value.absent(),
                Value<String> holidayRollover = const Value.absent(),
                Value<String?> cutoffTime = const Value.absent(),
                Value<int> postingDelayMinDays = const Value.absent(),
                Value<int> postingDelayMaxDays = const Value.absent(),
                required String source,
                Value<String?> effectiveFrom = const Value.absent(),
                Value<String?> effectiveTo = const Value.absent(),
                Value<String?> verifiedOn = const Value.absent(),
                required int version,
                required String reviewStatus,
                Value<String?> exceptions = const Value.absent(),
                required String createdAt,
                Value<int> rowid = const Value.absent(),
              }) => BillingRuleVersionsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                subjectKind: subjectKind,
                subjectId: subjectId,
                statementDay: statementDay,
                statementDayInclusive: statementDayInclusive,
                dueKind: dueKind,
                dueDay: dueDay,
                dueMonthOffset: dueMonthOffset,
                dueDays: dueDays,
                dueDayKind: dueDayKind,
                holidayRollover: holidayRollover,
                cutoffTime: cutoffTime,
                postingDelayMinDays: postingDelayMinDays,
                postingDelayMaxDays: postingDelayMaxDays,
                source: source,
                effectiveFrom: effectiveFrom,
                effectiveTo: effectiveTo,
                verifiedOn: verifiedOn,
                version: version,
                reviewStatus: reviewStatus,
                exceptions: exceptions,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BillingRuleVersionsTable, BillingRuleVersionRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $BillingRuleVersionsTable,
                    BillingRuleVersionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BillingRuleVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BillingRuleVersionsTable,
      BillingRuleVersionRow,
      $$BillingRuleVersionsTableFilterComposer,
      $$BillingRuleVersionsTableOrderingComposer,
      $$BillingRuleVersionsTableAnnotationComposer,
      $$BillingRuleVersionsTableCreateCompanionBuilder,
      $$BillingRuleVersionsTableUpdateCompanionBuilder,
      (
        BillingRuleVersionRow,
        BaseReferences<
          _$AppDatabase,
          $BillingRuleVersionsTable,
          BillingRuleVersionRow
        >,
      ),
      BillingRuleVersionRow,
      PrefetchHooks Function()
    >;
typedef $$LimitSnapshotsTableCreateCompanionBuilder =
    LimitSnapshotsCompanion Function({
      required String id,
      required String workspaceId,
      required String currencyAccountId,
      required int fixedMinor,
      Value<int> tempMinor,
      Value<String?> tempExpiresOn,
      Value<int> specialMinor,
      Value<String?> specialPurpose,
      required int usedMinor,
      required int availableRawMinor,
      Value<int> holdsMinor,
      required bool includesHolds,
      required String sourceKind,
      Value<String?> sourceDocumentId,
      required String balanceAsOf,
      required String observedAt,
      required String recordedAt,
      required String confirmationLevel,
      Value<int> rowid,
    });
typedef $$LimitSnapshotsTableUpdateCompanionBuilder =
    LimitSnapshotsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> currencyAccountId,
      Value<int> fixedMinor,
      Value<int> tempMinor,
      Value<String?> tempExpiresOn,
      Value<int> specialMinor,
      Value<String?> specialPurpose,
      Value<int> usedMinor,
      Value<int> availableRawMinor,
      Value<int> holdsMinor,
      Value<bool> includesHolds,
      Value<String> sourceKind,
      Value<String?> sourceDocumentId,
      Value<String> balanceAsOf,
      Value<String> observedAt,
      Value<String> recordedAt,
      Value<String> confirmationLevel,
      Value<int> rowid,
    });

class $$LimitSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $LimitSnapshotsTable> {
  $$LimitSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fixedMinor => $composableBuilder(
    column: $table.fixedMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tempMinor => $composableBuilder(
    column: $table.tempMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tempExpiresOn => $composableBuilder(
    column: $table.tempExpiresOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get specialMinor => $composableBuilder(
    column: $table.specialMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get specialPurpose => $composableBuilder(
    column: $table.specialPurpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usedMinor => $composableBuilder(
    column: $table.usedMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get availableRawMinor => $composableBuilder(
    column: $table.availableRawMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get holdsMinor => $composableBuilder(
    column: $table.holdsMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includesHolds => $composableBuilder(
    column: $table.includesHolds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDocumentId => $composableBuilder(
    column: $table.sourceDocumentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LimitSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $LimitSnapshotsTable> {
  $$LimitSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fixedMinor => $composableBuilder(
    column: $table.fixedMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tempMinor => $composableBuilder(
    column: $table.tempMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tempExpiresOn => $composableBuilder(
    column: $table.tempExpiresOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get specialMinor => $composableBuilder(
    column: $table.specialMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get specialPurpose => $composableBuilder(
    column: $table.specialPurpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usedMinor => $composableBuilder(
    column: $table.usedMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get availableRawMinor => $composableBuilder(
    column: $table.availableRawMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get holdsMinor => $composableBuilder(
    column: $table.holdsMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includesHolds => $composableBuilder(
    column: $table.includesHolds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDocumentId => $composableBuilder(
    column: $table.sourceDocumentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LimitSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LimitSnapshotsTable> {
  $$LimitSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fixedMinor => $composableBuilder(
    column: $table.fixedMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tempMinor =>
      $composableBuilder(column: $table.tempMinor, builder: (column) => column);

  GeneratedColumn<String> get tempExpiresOn => $composableBuilder(
    column: $table.tempExpiresOn,
    builder: (column) => column,
  );

  GeneratedColumn<int> get specialMinor => $composableBuilder(
    column: $table.specialMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get specialPurpose => $composableBuilder(
    column: $table.specialPurpose,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usedMinor =>
      $composableBuilder(column: $table.usedMinor, builder: (column) => column);

  GeneratedColumn<int> get availableRawMinor => $composableBuilder(
    column: $table.availableRawMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get holdsMinor => $composableBuilder(
    column: $table.holdsMinor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includesHolds => $composableBuilder(
    column: $table.includesHolds,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceDocumentId => $composableBuilder(
    column: $table.sourceDocumentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => column,
  );
}

class $$LimitSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LimitSnapshotsTable,
          LimitSnapshotRow,
          $$LimitSnapshotsTableFilterComposer,
          $$LimitSnapshotsTableOrderingComposer,
          $$LimitSnapshotsTableAnnotationComposer,
          $$LimitSnapshotsTableCreateCompanionBuilder,
          $$LimitSnapshotsTableUpdateCompanionBuilder,
          (
            LimitSnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $LimitSnapshotsTable,
              LimitSnapshotRow
            >,
          ),
          LimitSnapshotRow,
          PrefetchHooks Function()
        > {
  $$LimitSnapshotsTableTableManager(
    _$AppDatabase db,
    $LimitSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LimitSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LimitSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LimitSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<int> fixedMinor = const Value.absent(),
                Value<int> tempMinor = const Value.absent(),
                Value<String?> tempExpiresOn = const Value.absent(),
                Value<int> specialMinor = const Value.absent(),
                Value<String?> specialPurpose = const Value.absent(),
                Value<int> usedMinor = const Value.absent(),
                Value<int> availableRawMinor = const Value.absent(),
                Value<int> holdsMinor = const Value.absent(),
                Value<bool> includesHolds = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String?> sourceDocumentId = const Value.absent(),
                Value<String> balanceAsOf = const Value.absent(),
                Value<String> observedAt = const Value.absent(),
                Value<String> recordedAt = const Value.absent(),
                Value<String> confirmationLevel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LimitSnapshotsCompanion(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                fixedMinor: fixedMinor,
                tempMinor: tempMinor,
                tempExpiresOn: tempExpiresOn,
                specialMinor: specialMinor,
                specialPurpose: specialPurpose,
                usedMinor: usedMinor,
                availableRawMinor: availableRawMinor,
                holdsMinor: holdsMinor,
                includesHolds: includesHolds,
                sourceKind: sourceKind,
                sourceDocumentId: sourceDocumentId,
                balanceAsOf: balanceAsOf,
                observedAt: observedAt,
                recordedAt: recordedAt,
                confirmationLevel: confirmationLevel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String currencyAccountId,
                required int fixedMinor,
                Value<int> tempMinor = const Value.absent(),
                Value<String?> tempExpiresOn = const Value.absent(),
                Value<int> specialMinor = const Value.absent(),
                Value<String?> specialPurpose = const Value.absent(),
                required int usedMinor,
                required int availableRawMinor,
                Value<int> holdsMinor = const Value.absent(),
                required bool includesHolds,
                required String sourceKind,
                Value<String?> sourceDocumentId = const Value.absent(),
                required String balanceAsOf,
                required String observedAt,
                required String recordedAt,
                required String confirmationLevel,
                Value<int> rowid = const Value.absent(),
              }) => LimitSnapshotsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                fixedMinor: fixedMinor,
                tempMinor: tempMinor,
                tempExpiresOn: tempExpiresOn,
                specialMinor: specialMinor,
                specialPurpose: specialPurpose,
                usedMinor: usedMinor,
                availableRawMinor: availableRawMinor,
                holdsMinor: holdsMinor,
                includesHolds: includesHolds,
                sourceKind: sourceKind,
                sourceDocumentId: sourceDocumentId,
                balanceAsOf: balanceAsOf,
                observedAt: observedAt,
                recordedAt: recordedAt,
                confirmationLevel: confirmationLevel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LimitSnapshotsTable, LimitSnapshotRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LimitSnapshotsTable,
                    LimitSnapshotRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LimitSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LimitSnapshotsTable,
      LimitSnapshotRow,
      $$LimitSnapshotsTableFilterComposer,
      $$LimitSnapshotsTableOrderingComposer,
      $$LimitSnapshotsTableAnnotationComposer,
      $$LimitSnapshotsTableCreateCompanionBuilder,
      $$LimitSnapshotsTableUpdateCompanionBuilder,
      (
        LimitSnapshotRow,
        BaseReferences<_$AppDatabase, $LimitSnapshotsTable, LimitSnapshotRow>,
      ),
      LimitSnapshotRow,
      PrefetchHooks Function()
    >;
typedef $$CashAccountsTableCreateCompanionBuilder =
    CashAccountsCompanion Function({
      required String id,
      required String workspaceId,
      required String name,
      required String currency,
      required String kind,
      Value<bool> usableForRepayment,
      Value<String?> availableFrom,
      Value<int> reserveFloorMinor,
      Value<String> status,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$CashAccountsTableUpdateCompanionBuilder =
    CashAccountsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> name,
      Value<String> currency,
      Value<String> kind,
      Value<bool> usableForRepayment,
      Value<String?> availableFrom,
      Value<int> reserveFloorMinor,
      Value<String> status,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

class $$CashAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $CashAccountsTable> {
  $$CashAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usableForRepayment => $composableBuilder(
    column: $table.usableForRepayment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reserveFloorMinor => $composableBuilder(
    column: $table.reserveFloorMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CashAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashAccountsTable> {
  $$CashAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usableForRepayment => $composableBuilder(
    column: $table.usableForRepayment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reserveFloorMinor => $composableBuilder(
    column: $table.reserveFloorMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CashAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashAccountsTable> {
  $$CashAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get usableForRepayment => $composableBuilder(
    column: $table.usableForRepayment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availableFrom => $composableBuilder(
    column: $table.availableFrom,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reserveFloorMinor => $composableBuilder(
    column: $table.reserveFloorMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CashAccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CashAccountsTable,
          CashAccountRow,
          $$CashAccountsTableFilterComposer,
          $$CashAccountsTableOrderingComposer,
          $$CashAccountsTableAnnotationComposer,
          $$CashAccountsTableCreateCompanionBuilder,
          $$CashAccountsTableUpdateCompanionBuilder,
          (
            CashAccountRow,
            BaseReferences<_$AppDatabase, $CashAccountsTable, CashAccountRow>,
          ),
          CashAccountRow,
          PrefetchHooks Function()
        > {
  $$CashAccountsTableTableManager(_$AppDatabase db, $CashAccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> usableForRepayment = const Value.absent(),
                Value<String?> availableFrom = const Value.absent(),
                Value<int> reserveFloorMinor = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashAccountsCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                currency: currency,
                kind: kind,
                usableForRepayment: usableForRepayment,
                availableFrom: availableFrom,
                reserveFloorMinor: reserveFloorMinor,
                status: status,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                required String currency,
                required String kind,
                Value<bool> usableForRepayment = const Value.absent(),
                Value<String?> availableFrom = const Value.absent(),
                Value<int> reserveFloorMinor = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashAccountsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                currency: currency,
                kind: kind,
                usableForRepayment: usableForRepayment,
                availableFrom: availableFrom,
                reserveFloorMinor: reserveFloorMinor,
                status: status,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CashAccountsTable, CashAccountRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CashAccountsTable,
                    CashAccountRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CashAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CashAccountsTable,
      CashAccountRow,
      $$CashAccountsTableFilterComposer,
      $$CashAccountsTableOrderingComposer,
      $$CashAccountsTableAnnotationComposer,
      $$CashAccountsTableCreateCompanionBuilder,
      $$CashAccountsTableUpdateCompanionBuilder,
      (
        CashAccountRow,
        BaseReferences<_$AppDatabase, $CashAccountsTable, CashAccountRow>,
      ),
      CashAccountRow,
      PrefetchHooks Function()
    >;
typedef $$CashBalanceSnapshotsTableCreateCompanionBuilder =
    CashBalanceSnapshotsCompanion Function({
      required String id,
      required String workspaceId,
      required String cashAccountId,
      required int balanceMinor,
      required String balanceAsOf,
      required String observedAt,
      required String sourceKind,
      required String confirmationLevel,
      required String recordedAt,
      Value<int> rowid,
    });
typedef $$CashBalanceSnapshotsTableUpdateCompanionBuilder =
    CashBalanceSnapshotsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> cashAccountId,
      Value<int> balanceMinor,
      Value<String> balanceAsOf,
      Value<String> observedAt,
      Value<String> sourceKind,
      Value<String> confirmationLevel,
      Value<String> recordedAt,
      Value<int> rowid,
    });

class $$CashBalanceSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $CashBalanceSnapshotsTable> {
  $$CashBalanceSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balanceMinor => $composableBuilder(
    column: $table.balanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CashBalanceSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashBalanceSnapshotsTable> {
  $$CashBalanceSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balanceMinor => $composableBuilder(
    column: $table.balanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CashBalanceSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashBalanceSnapshotsTable> {
  $$CashBalanceSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get balanceMinor => $composableBuilder(
    column: $table.balanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get balanceAsOf => $composableBuilder(
    column: $table.balanceAsOf,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$CashBalanceSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CashBalanceSnapshotsTable,
          CashSnapshotRow,
          $$CashBalanceSnapshotsTableFilterComposer,
          $$CashBalanceSnapshotsTableOrderingComposer,
          $$CashBalanceSnapshotsTableAnnotationComposer,
          $$CashBalanceSnapshotsTableCreateCompanionBuilder,
          $$CashBalanceSnapshotsTableUpdateCompanionBuilder,
          (
            CashSnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $CashBalanceSnapshotsTable,
              CashSnapshotRow
            >,
          ),
          CashSnapshotRow,
          PrefetchHooks Function()
        > {
  $$CashBalanceSnapshotsTableTableManager(
    _$AppDatabase db,
    $CashBalanceSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashBalanceSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashBalanceSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CashBalanceSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> cashAccountId = const Value.absent(),
                Value<int> balanceMinor = const Value.absent(),
                Value<String> balanceAsOf = const Value.absent(),
                Value<String> observedAt = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> confirmationLevel = const Value.absent(),
                Value<String> recordedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashBalanceSnapshotsCompanion(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                balanceMinor: balanceMinor,
                balanceAsOf: balanceAsOf,
                observedAt: observedAt,
                sourceKind: sourceKind,
                confirmationLevel: confirmationLevel,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String cashAccountId,
                required int balanceMinor,
                required String balanceAsOf,
                required String observedAt,
                required String sourceKind,
                required String confirmationLevel,
                required String recordedAt,
                Value<int> rowid = const Value.absent(),
              }) => CashBalanceSnapshotsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                balanceMinor: balanceMinor,
                balanceAsOf: balanceAsOf,
                observedAt: observedAt,
                sourceKind: sourceKind,
                confirmationLevel: confirmationLevel,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CashBalanceSnapshotsTable, CashSnapshotRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CashBalanceSnapshotsTable,
                    CashSnapshotRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CashBalanceSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CashBalanceSnapshotsTable,
      CashSnapshotRow,
      $$CashBalanceSnapshotsTableFilterComposer,
      $$CashBalanceSnapshotsTableOrderingComposer,
      $$CashBalanceSnapshotsTableAnnotationComposer,
      $$CashBalanceSnapshotsTableCreateCompanionBuilder,
      $$CashBalanceSnapshotsTableUpdateCompanionBuilder,
      (
        CashSnapshotRow,
        BaseReferences<
          _$AppDatabase,
          $CashBalanceSnapshotsTable,
          CashSnapshotRow
        >,
      ),
      CashSnapshotRow,
      PrefetchHooks Function()
    >;
typedef $$RecurringItemsTableCreateCompanionBuilder =
    RecurringItemsCompanion Function({
      required String id,
      required String workspaceId,
      required String cashAccountId,
      required String label,
      required int amountMinor,
      required String cls,
      required String category,
      required String frequency,
      required String anchorOn,
      Value<String> dayRule,
      required String startOn,
      Value<String?> endOn,
      Value<bool> active,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$RecurringItemsTableUpdateCompanionBuilder =
    RecurringItemsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> cashAccountId,
      Value<String> label,
      Value<int> amountMinor,
      Value<String> cls,
      Value<String> category,
      Value<String> frequency,
      Value<String> anchorOn,
      Value<String> dayRule,
      Value<String> startOn,
      Value<String?> endOn,
      Value<bool> active,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$RecurringItemsTableFilterComposer
    extends Composer<_$AppDatabase, $RecurringItemsTable> {
  $$RecurringItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cls => $composableBuilder(
    column: $table.cls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchorOn => $composableBuilder(
    column: $table.anchorOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayRule => $composableBuilder(
    column: $table.dayRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startOn => $composableBuilder(
    column: $table.startOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endOn => $composableBuilder(
    column: $table.endOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecurringItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecurringItemsTable> {
  $$RecurringItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cls => $composableBuilder(
    column: $table.cls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get frequency => $composableBuilder(
    column: $table.frequency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchorOn => $composableBuilder(
    column: $table.anchorOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayRule => $composableBuilder(
    column: $table.dayRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startOn => $composableBuilder(
    column: $table.startOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endOn => $composableBuilder(
    column: $table.endOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecurringItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecurringItemsTable> {
  $$RecurringItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cls =>
      $composableBuilder(column: $table.cls, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get frequency =>
      $composableBuilder(column: $table.frequency, builder: (column) => column);

  GeneratedColumn<String> get anchorOn =>
      $composableBuilder(column: $table.anchorOn, builder: (column) => column);

  GeneratedColumn<String> get dayRule =>
      $composableBuilder(column: $table.dayRule, builder: (column) => column);

  GeneratedColumn<String> get startOn =>
      $composableBuilder(column: $table.startOn, builder: (column) => column);

  GeneratedColumn<String> get endOn =>
      $composableBuilder(column: $table.endOn, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RecurringItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecurringItemsTable,
          RecurringItemRow,
          $$RecurringItemsTableFilterComposer,
          $$RecurringItemsTableOrderingComposer,
          $$RecurringItemsTableAnnotationComposer,
          $$RecurringItemsTableCreateCompanionBuilder,
          $$RecurringItemsTableUpdateCompanionBuilder,
          (
            RecurringItemRow,
            BaseReferences<
              _$AppDatabase,
              $RecurringItemsTable,
              RecurringItemRow
            >,
          ),
          RecurringItemRow,
          PrefetchHooks Function()
        > {
  $$RecurringItemsTableTableManager(
    _$AppDatabase db,
    $RecurringItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecurringItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecurringItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecurringItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> cashAccountId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> cls = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> frequency = const Value.absent(),
                Value<String> anchorOn = const Value.absent(),
                Value<String> dayRule = const Value.absent(),
                Value<String> startOn = const Value.absent(),
                Value<String?> endOn = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecurringItemsCompanion(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                label: label,
                amountMinor: amountMinor,
                cls: cls,
                category: category,
                frequency: frequency,
                anchorOn: anchorOn,
                dayRule: dayRule,
                startOn: startOn,
                endOn: endOn,
                active: active,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String cashAccountId,
                required String label,
                required int amountMinor,
                required String cls,
                required String category,
                required String frequency,
                required String anchorOn,
                Value<String> dayRule = const Value.absent(),
                required String startOn,
                Value<String?> endOn = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecurringItemsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                label: label,
                amountMinor: amountMinor,
                cls: cls,
                category: category,
                frequency: frequency,
                anchorOn: anchorOn,
                dayRule: dayRule,
                startOn: startOn,
                endOn: endOn,
                active: active,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecurringItemsTable, RecurringItemRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RecurringItemsTable,
                    RecurringItemRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecurringItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecurringItemsTable,
      RecurringItemRow,
      $$RecurringItemsTableFilterComposer,
      $$RecurringItemsTableOrderingComposer,
      $$RecurringItemsTableAnnotationComposer,
      $$RecurringItemsTableCreateCompanionBuilder,
      $$RecurringItemsTableUpdateCompanionBuilder,
      (
        RecurringItemRow,
        BaseReferences<_$AppDatabase, $RecurringItemsTable, RecurringItemRow>,
      ),
      RecurringItemRow,
      PrefetchHooks Function()
    >;
typedef $$CashEventsTableCreateCompanionBuilder = CashEventsCompanion Function({
  required String id,
  required String workspaceId,
  required String cashAccountId,
  required String eventOn,
  Value<String?> eventAt,
  required int amountMinor,
  required String cls,
  required String category,
  Value<String?> label,
  Value<String> postingStatus,
  Value<String?> recurringItemId,
  Value<String?> occurrenceKey,
  Value<String?> transferGroupId,
  Value<String?> linkedRepaymentId,
  Value<String?> linkedPlanRunId,
  Value<int> rowVersion,
  required String createdAt,
  required String updatedAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});
typedef $$CashEventsTableUpdateCompanionBuilder = CashEventsCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> cashAccountId,
  Value<String> eventOn,
  Value<String?> eventAt,
  Value<int> amountMinor,
  Value<String> cls,
  Value<String> category,
  Value<String?> label,
  Value<String> postingStatus,
  Value<String?> recurringItemId,
  Value<String?> occurrenceKey,
  Value<String?> transferGroupId,
  Value<String?> linkedRepaymentId,
  Value<String?> linkedPlanRunId,
  Value<int> rowVersion,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});

class $$CashEventsTableFilterComposer
    extends Composer<_$AppDatabase, $CashEventsTable> {
  $$CashEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventOn => $composableBuilder(
    column: $table.eventOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventAt => $composableBuilder(
    column: $table.eventAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cls => $composableBuilder(
    column: $table.cls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postingStatus => $composableBuilder(
    column: $table.postingStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedRepaymentId => $composableBuilder(
    column: $table.linkedRepaymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedPlanRunId => $composableBuilder(
    column: $table.linkedPlanRunId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CashEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashEventsTable> {
  $$CashEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventOn => $composableBuilder(
    column: $table.eventOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventAt => $composableBuilder(
    column: $table.eventAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cls => $composableBuilder(
    column: $table.cls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postingStatus => $composableBuilder(
    column: $table.postingStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedRepaymentId => $composableBuilder(
    column: $table.linkedRepaymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedPlanRunId => $composableBuilder(
    column: $table.linkedPlanRunId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CashEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashEventsTable> {
  $$CashEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventOn =>
      $composableBuilder(column: $table.eventOn, builder: (column) => column);

  GeneratedColumn<String> get eventAt =>
      $composableBuilder(column: $table.eventAt, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cls =>
      $composableBuilder(column: $table.cls, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get postingStatus => $composableBuilder(
    column: $table.postingStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transferGroupId => $composableBuilder(
    column: $table.transferGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedRepaymentId => $composableBuilder(
    column: $table.linkedRepaymentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedPlanRunId => $composableBuilder(
    column: $table.linkedPlanRunId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CashEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CashEventsTable,
          CashEventRow,
          $$CashEventsTableFilterComposer,
          $$CashEventsTableOrderingComposer,
          $$CashEventsTableAnnotationComposer,
          $$CashEventsTableCreateCompanionBuilder,
          $$CashEventsTableUpdateCompanionBuilder,
          (
            CashEventRow,
            BaseReferences<_$AppDatabase, $CashEventsTable, CashEventRow>,
          ),
          CashEventRow,
          PrefetchHooks Function()
        > {
  $$CashEventsTableTableManager(_$AppDatabase db, $CashEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> cashAccountId = const Value.absent(),
                Value<String> eventOn = const Value.absent(),
                Value<String?> eventAt = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> cls = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String> postingStatus = const Value.absent(),
                Value<String?> recurringItemId = const Value.absent(),
                Value<String?> occurrenceKey = const Value.absent(),
                Value<String?> transferGroupId = const Value.absent(),
                Value<String?> linkedRepaymentId = const Value.absent(),
                Value<String?> linkedPlanRunId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashEventsCompanion(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                eventOn: eventOn,
                eventAt: eventAt,
                amountMinor: amountMinor,
                cls: cls,
                category: category,
                label: label,
                postingStatus: postingStatus,
                recurringItemId: recurringItemId,
                occurrenceKey: occurrenceKey,
                transferGroupId: transferGroupId,
                linkedRepaymentId: linkedRepaymentId,
                linkedPlanRunId: linkedPlanRunId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String cashAccountId,
                required String eventOn,
                Value<String?> eventAt = const Value.absent(),
                required int amountMinor,
                required String cls,
                required String category,
                Value<String?> label = const Value.absent(),
                Value<String> postingStatus = const Value.absent(),
                Value<String?> recurringItemId = const Value.absent(),
                Value<String?> occurrenceKey = const Value.absent(),
                Value<String?> transferGroupId = const Value.absent(),
                Value<String?> linkedRepaymentId = const Value.absent(),
                Value<String?> linkedPlanRunId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CashEventsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                eventOn: eventOn,
                eventAt: eventAt,
                amountMinor: amountMinor,
                cls: cls,
                category: category,
                label: label,
                postingStatus: postingStatus,
                recurringItemId: recurringItemId,
                occurrenceKey: occurrenceKey,
                transferGroupId: transferGroupId,
                linkedRepaymentId: linkedRepaymentId,
                linkedPlanRunId: linkedPlanRunId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CashEventsTable, CashEventRow>(table),
                  BaseReferences<_$AppDatabase, $CashEventsTable, CashEventRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CashEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CashEventsTable,
      CashEventRow,
      $$CashEventsTableFilterComposer,
      $$CashEventsTableOrderingComposer,
      $$CashEventsTableAnnotationComposer,
      $$CashEventsTableCreateCompanionBuilder,
      $$CashEventsTableUpdateCompanionBuilder,
      (
        CashEventRow,
        BaseReferences<_$AppDatabase, $CashEventsTable, CashEventRow>,
      ),
      CashEventRow,
      PrefetchHooks Function()
    >;
typedef $$SnapshotIncludedEventsTableCreateCompanionBuilder =
    SnapshotIncludedEventsCompanion Function({
      required String workspaceId,
      required String cashAccountId,
      required String snapshotId,
      required String cashEventId,
      Value<int> rowid,
    });
typedef $$SnapshotIncludedEventsTableUpdateCompanionBuilder =
    SnapshotIncludedEventsCompanion Function({
      Value<String> workspaceId,
      Value<String> cashAccountId,
      Value<String> snapshotId,
      Value<String> cashEventId,
      Value<int> rowid,
    });

class $$SnapshotIncludedEventsTableFilterComposer
    extends Composer<_$AppDatabase, $SnapshotIncludedEventsTable> {
  $$SnapshotIncludedEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashEventId => $composableBuilder(
    column: $table.cashEventId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnapshotIncludedEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $SnapshotIncludedEventsTable> {
  $$SnapshotIncludedEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashEventId => $composableBuilder(
    column: $table.cashEventId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnapshotIncludedEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SnapshotIncludedEventsTable> {
  $$SnapshotIncludedEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotId => $composableBuilder(
    column: $table.snapshotId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashEventId => $composableBuilder(
    column: $table.cashEventId,
    builder: (column) => column,
  );
}

class $$SnapshotIncludedEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SnapshotIncludedEventsTable,
          SnapshotIncludedEventRow,
          $$SnapshotIncludedEventsTableFilterComposer,
          $$SnapshotIncludedEventsTableOrderingComposer,
          $$SnapshotIncludedEventsTableAnnotationComposer,
          $$SnapshotIncludedEventsTableCreateCompanionBuilder,
          $$SnapshotIncludedEventsTableUpdateCompanionBuilder,
          (
            SnapshotIncludedEventRow,
            BaseReferences<
              _$AppDatabase,
              $SnapshotIncludedEventsTable,
              SnapshotIncludedEventRow
            >,
          ),
          SnapshotIncludedEventRow,
          PrefetchHooks Function()
        > {
  $$SnapshotIncludedEventsTableTableManager(
    _$AppDatabase db,
    $SnapshotIncludedEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnapshotIncludedEventsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SnapshotIncludedEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SnapshotIncludedEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> cashAccountId = const Value.absent(),
                Value<String> snapshotId = const Value.absent(),
                Value<String> cashEventId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SnapshotIncludedEventsCompanion(
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                snapshotId: snapshotId,
                cashEventId: cashEventId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String cashAccountId,
                required String snapshotId,
                required String cashEventId,
                Value<int> rowid = const Value.absent(),
              }) => SnapshotIncludedEventsCompanion.insert(
                workspaceId: workspaceId,
                cashAccountId: cashAccountId,
                snapshotId: snapshotId,
                cashEventId: cashEventId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $SnapshotIncludedEventsTable,
                    SnapshotIncludedEventRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SnapshotIncludedEventsTable,
                    SnapshotIncludedEventRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnapshotIncludedEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SnapshotIncludedEventsTable,
      SnapshotIncludedEventRow,
      $$SnapshotIncludedEventsTableFilterComposer,
      $$SnapshotIncludedEventsTableOrderingComposer,
      $$SnapshotIncludedEventsTableAnnotationComposer,
      $$SnapshotIncludedEventsTableCreateCompanionBuilder,
      $$SnapshotIncludedEventsTableUpdateCompanionBuilder,
      (
        SnapshotIncludedEventRow,
        BaseReferences<
          _$AppDatabase,
          $SnapshotIncludedEventsTable,
          SnapshotIncludedEventRow
        >,
      ),
      SnapshotIncludedEventRow,
      PrefetchHooks Function()
    >;
typedef $$RecurringOverridesTableCreateCompanionBuilder =
    RecurringOverridesCompanion Function({
      required String workspaceId,
      required String recurringItemId,
      required String occurrenceKey,
      required String action,
      Value<int?> amountMinor,
      Value<String?> eventOn,
      Value<String?> eventAt,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$RecurringOverridesTableUpdateCompanionBuilder =
    RecurringOverridesCompanion Function({
      Value<String> workspaceId,
      Value<String> recurringItemId,
      Value<String> occurrenceKey,
      Value<String> action,
      Value<int?> amountMinor,
      Value<String?> eventOn,
      Value<String?> eventAt,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$RecurringOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $RecurringOverridesTable> {
  $$RecurringOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventOn => $composableBuilder(
    column: $table.eventOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventAt => $composableBuilder(
    column: $table.eventAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecurringOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecurringOverridesTable> {
  $$RecurringOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventOn => $composableBuilder(
    column: $table.eventOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventAt => $composableBuilder(
    column: $table.eventAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecurringOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecurringOverridesTable> {
  $$RecurringOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recurringItemId => $composableBuilder(
    column: $table.recurringItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventOn =>
      $composableBuilder(column: $table.eventOn, builder: (column) => column);

  GeneratedColumn<String> get eventAt =>
      $composableBuilder(column: $table.eventAt, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RecurringOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecurringOverridesTable,
          RecurringOverrideRow,
          $$RecurringOverridesTableFilterComposer,
          $$RecurringOverridesTableOrderingComposer,
          $$RecurringOverridesTableAnnotationComposer,
          $$RecurringOverridesTableCreateCompanionBuilder,
          $$RecurringOverridesTableUpdateCompanionBuilder,
          (
            RecurringOverrideRow,
            BaseReferences<
              _$AppDatabase,
              $RecurringOverridesTable,
              RecurringOverrideRow
            >,
          ),
          RecurringOverrideRow,
          PrefetchHooks Function()
        > {
  $$RecurringOverridesTableTableManager(
    _$AppDatabase db,
    $RecurringOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecurringOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecurringOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecurringOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> recurringItemId = const Value.absent(),
                Value<String> occurrenceKey = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int?> amountMinor = const Value.absent(),
                Value<String?> eventOn = const Value.absent(),
                Value<String?> eventAt = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecurringOverridesCompanion(
                workspaceId: workspaceId,
                recurringItemId: recurringItemId,
                occurrenceKey: occurrenceKey,
                action: action,
                amountMinor: amountMinor,
                eventOn: eventOn,
                eventAt: eventAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String recurringItemId,
                required String occurrenceKey,
                required String action,
                Value<int?> amountMinor = const Value.absent(),
                Value<String?> eventOn = const Value.absent(),
                Value<String?> eventAt = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RecurringOverridesCompanion.insert(
                workspaceId: workspaceId,
                recurringItemId: recurringItemId,
                occurrenceKey: occurrenceKey,
                action: action,
                amountMinor: amountMinor,
                eventOn: eventOn,
                eventAt: eventAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecurringOverridesTable, RecurringOverrideRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $RecurringOverridesTable,
                    RecurringOverrideRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecurringOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecurringOverridesTable,
      RecurringOverrideRow,
      $$RecurringOverridesTableFilterComposer,
      $$RecurringOverridesTableOrderingComposer,
      $$RecurringOverridesTableAnnotationComposer,
      $$RecurringOverridesTableCreateCompanionBuilder,
      $$RecurringOverridesTableUpdateCompanionBuilder,
      (
        RecurringOverrideRow,
        BaseReferences<
          _$AppDatabase,
          $RecurringOverridesTable,
          RecurringOverrideRow
        >,
      ),
      RecurringOverrideRow,
      PrefetchHooks Function()
    >;
typedef $$ScenariosTableCreateCompanionBuilder = ScenariosCompanion Function({
  required String id,
  required String workspaceId,
  required String name,
  required String kind,
  required bool includeExpected,
  Value<int> incomeDelayDays,
  Value<String> incomeScale,
  Value<String> expenseScale,
  Value<String> sameDayOrder,
  Value<String> limitChanges,
  Value<String> eventOverrides,
  Value<int> rowVersion,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$ScenariosTableUpdateCompanionBuilder = ScenariosCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> name,
  Value<String> kind,
  Value<bool> includeExpected,
  Value<int> incomeDelayDays,
  Value<String> incomeScale,
  Value<String> expenseScale,
  Value<String> sameDayOrder,
  Value<String> limitChanges,
  Value<String> eventOverrides,
  Value<int> rowVersion,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$ScenariosTableFilterComposer
    extends Composer<_$AppDatabase, $ScenariosTable> {
  $$ScenariosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeExpected => $composableBuilder(
    column: $table.includeExpected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get incomeDelayDays => $composableBuilder(
    column: $table.incomeDelayDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incomeScale => $composableBuilder(
    column: $table.incomeScale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expenseScale => $composableBuilder(
    column: $table.expenseScale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sameDayOrder => $composableBuilder(
    column: $table.sameDayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get limitChanges => $composableBuilder(
    column: $table.limitChanges,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventOverrides => $composableBuilder(
    column: $table.eventOverrides,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScenariosTableOrderingComposer
    extends Composer<_$AppDatabase, $ScenariosTable> {
  $$ScenariosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeExpected => $composableBuilder(
    column: $table.includeExpected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get incomeDelayDays => $composableBuilder(
    column: $table.incomeDelayDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incomeScale => $composableBuilder(
    column: $table.incomeScale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expenseScale => $composableBuilder(
    column: $table.expenseScale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sameDayOrder => $composableBuilder(
    column: $table.sameDayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get limitChanges => $composableBuilder(
    column: $table.limitChanges,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventOverrides => $composableBuilder(
    column: $table.eventOverrides,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScenariosTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScenariosTable> {
  $$ScenariosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get includeExpected => $composableBuilder(
    column: $table.includeExpected,
    builder: (column) => column,
  );

  GeneratedColumn<int> get incomeDelayDays => $composableBuilder(
    column: $table.incomeDelayDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get incomeScale => $composableBuilder(
    column: $table.incomeScale,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expenseScale => $composableBuilder(
    column: $table.expenseScale,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sameDayOrder => $composableBuilder(
    column: $table.sameDayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get limitChanges => $composableBuilder(
    column: $table.limitChanges,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventOverrides => $composableBuilder(
    column: $table.eventOverrides,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ScenariosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScenariosTable,
          ScenarioRow,
          $$ScenariosTableFilterComposer,
          $$ScenariosTableOrderingComposer,
          $$ScenariosTableAnnotationComposer,
          $$ScenariosTableCreateCompanionBuilder,
          $$ScenariosTableUpdateCompanionBuilder,
          (
            ScenarioRow,
            BaseReferences<_$AppDatabase, $ScenariosTable, ScenarioRow>,
          ),
          ScenarioRow,
          PrefetchHooks Function()
        > {
  $$ScenariosTableTableManager(_$AppDatabase db, $ScenariosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScenariosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScenariosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScenariosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> includeExpected = const Value.absent(),
                Value<int> incomeDelayDays = const Value.absent(),
                Value<String> incomeScale = const Value.absent(),
                Value<String> expenseScale = const Value.absent(),
                Value<String> sameDayOrder = const Value.absent(),
                Value<String> limitChanges = const Value.absent(),
                Value<String> eventOverrides = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScenariosCompanion(
                id: id,
                workspaceId: workspaceId,
                name: name,
                kind: kind,
                includeExpected: includeExpected,
                incomeDelayDays: incomeDelayDays,
                incomeScale: incomeScale,
                expenseScale: expenseScale,
                sameDayOrder: sameDayOrder,
                limitChanges: limitChanges,
                eventOverrides: eventOverrides,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String name,
                required String kind,
                required bool includeExpected,
                Value<int> incomeDelayDays = const Value.absent(),
                Value<String> incomeScale = const Value.absent(),
                Value<String> expenseScale = const Value.absent(),
                Value<String> sameDayOrder = const Value.absent(),
                Value<String> limitChanges = const Value.absent(),
                Value<String> eventOverrides = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ScenariosCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                name: name,
                kind: kind,
                includeExpected: includeExpected,
                incomeDelayDays: incomeDelayDays,
                incomeScale: incomeScale,
                expenseScale: expenseScale,
                sameDayOrder: sameDayOrder,
                limitChanges: limitChanges,
                eventOverrides: eventOverrides,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ScenariosTable, ScenarioRow>(table),
                  BaseReferences<_$AppDatabase, $ScenariosTable, ScenarioRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScenariosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScenariosTable,
      ScenarioRow,
      $$ScenariosTableFilterComposer,
      $$ScenariosTableOrderingComposer,
      $$ScenariosTableAnnotationComposer,
      $$ScenariosTableCreateCompanionBuilder,
      $$ScenariosTableUpdateCompanionBuilder,
      (
        ScenarioRow,
        BaseReferences<_$AppDatabase, $ScenariosTable, ScenarioRow>,
      ),
      ScenarioRow,
      PrefetchHooks Function()
    >;
typedef $$ScenarioRunsTableCreateCompanionBuilder =
    ScenarioRunsCompanion Function({
      required String id,
      required String workspaceId,
      required String scenarioId,
      required int versionNo,
      required String computedAt,
      required String horizonFrom,
      required String horizonTo,
      required String inputsHash,
      required String result,
      Value<int> rowid,
    });
typedef $$ScenarioRunsTableUpdateCompanionBuilder =
    ScenarioRunsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> scenarioId,
      Value<int> versionNo,
      Value<String> computedAt,
      Value<String> horizonFrom,
      Value<String> horizonTo,
      Value<String> inputsHash,
      Value<String> result,
      Value<int> rowid,
    });

class $$ScenarioRunsTableFilterComposer
    extends Composer<_$AppDatabase, $ScenarioRunsTable> {
  $$ScenarioRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scenarioId => $composableBuilder(
    column: $table.scenarioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionNo => $composableBuilder(
    column: $table.versionNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get computedAt => $composableBuilder(
    column: $table.computedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get horizonFrom => $composableBuilder(
    column: $table.horizonFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get horizonTo => $composableBuilder(
    column: $table.horizonTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScenarioRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScenarioRunsTable> {
  $$ScenarioRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scenarioId => $composableBuilder(
    column: $table.scenarioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionNo => $composableBuilder(
    column: $table.versionNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get computedAt => $composableBuilder(
    column: $table.computedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get horizonFrom => $composableBuilder(
    column: $table.horizonFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get horizonTo => $composableBuilder(
    column: $table.horizonTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScenarioRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScenarioRunsTable> {
  $$ScenarioRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scenarioId => $composableBuilder(
    column: $table.scenarioId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionNo =>
      $composableBuilder(column: $table.versionNo, builder: (column) => column);

  GeneratedColumn<String> get computedAt => $composableBuilder(
    column: $table.computedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get horizonFrom => $composableBuilder(
    column: $table.horizonFrom,
    builder: (column) => column,
  );

  GeneratedColumn<String> get horizonTo =>
      $composableBuilder(column: $table.horizonTo, builder: (column) => column);

  GeneratedColumn<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);
}

class $$ScenarioRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScenarioRunsTable,
          ScenarioRunRow,
          $$ScenarioRunsTableFilterComposer,
          $$ScenarioRunsTableOrderingComposer,
          $$ScenarioRunsTableAnnotationComposer,
          $$ScenarioRunsTableCreateCompanionBuilder,
          $$ScenarioRunsTableUpdateCompanionBuilder,
          (
            ScenarioRunRow,
            BaseReferences<_$AppDatabase, $ScenarioRunsTable, ScenarioRunRow>,
          ),
          ScenarioRunRow,
          PrefetchHooks Function()
        > {
  $$ScenarioRunsTableTableManager(_$AppDatabase db, $ScenarioRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScenarioRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScenarioRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScenarioRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> scenarioId = const Value.absent(),
                Value<int> versionNo = const Value.absent(),
                Value<String> computedAt = const Value.absent(),
                Value<String> horizonFrom = const Value.absent(),
                Value<String> horizonTo = const Value.absent(),
                Value<String> inputsHash = const Value.absent(),
                Value<String> result = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScenarioRunsCompanion(
                id: id,
                workspaceId: workspaceId,
                scenarioId: scenarioId,
                versionNo: versionNo,
                computedAt: computedAt,
                horizonFrom: horizonFrom,
                horizonTo: horizonTo,
                inputsHash: inputsHash,
                result: result,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String scenarioId,
                required int versionNo,
                required String computedAt,
                required String horizonFrom,
                required String horizonTo,
                required String inputsHash,
                required String result,
                Value<int> rowid = const Value.absent(),
              }) => ScenarioRunsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                scenarioId: scenarioId,
                versionNo: versionNo,
                computedAt: computedAt,
                horizonFrom: horizonFrom,
                horizonTo: horizonTo,
                inputsHash: inputsHash,
                result: result,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ScenarioRunsTable, ScenarioRunRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ScenarioRunsTable,
                    ScenarioRunRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScenarioRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScenarioRunsTable,
      ScenarioRunRow,
      $$ScenarioRunsTableFilterComposer,
      $$ScenarioRunsTableOrderingComposer,
      $$ScenarioRunsTableAnnotationComposer,
      $$ScenarioRunsTableCreateCompanionBuilder,
      $$ScenarioRunsTableUpdateCompanionBuilder,
      (
        ScenarioRunRow,
        BaseReferences<_$AppDatabase, $ScenarioRunsTable, ScenarioRunRow>,
      ),
      ScenarioRunRow,
      PrefetchHooks Function()
    >;
typedef $$CardTransactionsTableCreateCompanionBuilder =
    CardTransactionsCompanion Function({
      required String id,
      required String workspaceId,
      required String currencyAccountId,
      Value<String?> cardId,
      required String txnType,
      required int amountMinor,
      required String currency,
      required String txnAt,
      required String txnTz,
      required String timePrecision,
      Value<String?> postedOn,
      Value<String?> merchant,
      Value<String?> category,
      required String status,
      Value<String?> parentTransactionId,
      required String fingerprint,
      required String sourceKind,
      required String confirmationLevel,
      Value<int> rowVersion,
      required String recordedAt,
      required String updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });
typedef $$CardTransactionsTableUpdateCompanionBuilder =
    CardTransactionsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> currencyAccountId,
      Value<String?> cardId,
      Value<String> txnType,
      Value<int> amountMinor,
      Value<String> currency,
      Value<String> txnAt,
      Value<String> txnTz,
      Value<String> timePrecision,
      Value<String?> postedOn,
      Value<String?> merchant,
      Value<String?> category,
      Value<String> status,
      Value<String?> parentTransactionId,
      Value<String> fingerprint,
      Value<String> sourceKind,
      Value<String> confirmationLevel,
      Value<int> rowVersion,
      Value<String> recordedAt,
      Value<String> updatedAt,
      Value<String?> deletedAt,
      Value<int> rowid,
    });

class $$CardTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $CardTransactionsTable> {
  $$CardTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txnType => $composableBuilder(
    column: $table.txnType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txnAt => $composableBuilder(
    column: $table.txnAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get txnTz => $composableBuilder(
    column: $table.txnTz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timePrecision => $composableBuilder(
    column: $table.timePrecision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postedOn => $composableBuilder(
    column: $table.postedOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get merchant => $composableBuilder(
    column: $table.merchant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentTransactionId => $composableBuilder(
    column: $table.parentTransactionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardTransactionsTable> {
  $$CardTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txnType => $composableBuilder(
    column: $table.txnType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txnAt => $composableBuilder(
    column: $table.txnAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get txnTz => $composableBuilder(
    column: $table.txnTz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timePrecision => $composableBuilder(
    column: $table.timePrecision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postedOn => $composableBuilder(
    column: $table.postedOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get merchant => $composableBuilder(
    column: $table.merchant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentTransactionId => $composableBuilder(
    column: $table.parentTransactionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardTransactionsTable> {
  $$CardTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get txnType =>
      $composableBuilder(column: $table.txnType, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get txnAt =>
      $composableBuilder(column: $table.txnAt, builder: (column) => column);

  GeneratedColumn<String> get txnTz =>
      $composableBuilder(column: $table.txnTz, builder: (column) => column);

  GeneratedColumn<String> get timePrecision => $composableBuilder(
    column: $table.timePrecision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get postedOn =>
      $composableBuilder(column: $table.postedOn, builder: (column) => column);

  GeneratedColumn<String> get merchant =>
      $composableBuilder(column: $table.merchant, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get parentTransactionId => $composableBuilder(
    column: $table.parentTransactionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get confirmationLevel => $composableBuilder(
    column: $table.confirmationLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$CardTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardTransactionsTable,
          CardTransactionRow,
          $$CardTransactionsTableFilterComposer,
          $$CardTransactionsTableOrderingComposer,
          $$CardTransactionsTableAnnotationComposer,
          $$CardTransactionsTableCreateCompanionBuilder,
          $$CardTransactionsTableUpdateCompanionBuilder,
          (
            CardTransactionRow,
            BaseReferences<
              _$AppDatabase,
              $CardTransactionsTable,
              CardTransactionRow
            >,
          ),
          CardTransactionRow,
          PrefetchHooks Function()
        > {
  $$CardTransactionsTableTableManager(
    _$AppDatabase db,
    $CardTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardTransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<String?> cardId = const Value.absent(),
                Value<String> txnType = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> txnAt = const Value.absent(),
                Value<String> txnTz = const Value.absent(),
                Value<String> timePrecision = const Value.absent(),
                Value<String?> postedOn = const Value.absent(),
                Value<String?> merchant = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> parentTransactionId = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> confirmationLevel = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> recordedAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardTransactionsCompanion(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                cardId: cardId,
                txnType: txnType,
                amountMinor: amountMinor,
                currency: currency,
                txnAt: txnAt,
                txnTz: txnTz,
                timePrecision: timePrecision,
                postedOn: postedOn,
                merchant: merchant,
                category: category,
                status: status,
                parentTransactionId: parentTransactionId,
                fingerprint: fingerprint,
                sourceKind: sourceKind,
                confirmationLevel: confirmationLevel,
                rowVersion: rowVersion,
                recordedAt: recordedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String currencyAccountId,
                Value<String?> cardId = const Value.absent(),
                required String txnType,
                required int amountMinor,
                required String currency,
                required String txnAt,
                required String txnTz,
                required String timePrecision,
                Value<String?> postedOn = const Value.absent(),
                Value<String?> merchant = const Value.absent(),
                Value<String?> category = const Value.absent(),
                required String status,
                Value<String?> parentTransactionId = const Value.absent(),
                required String fingerprint,
                required String sourceKind,
                required String confirmationLevel,
                Value<int> rowVersion = const Value.absent(),
                required String recordedAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardTransactionsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                cardId: cardId,
                txnType: txnType,
                amountMinor: amountMinor,
                currency: currency,
                txnAt: txnAt,
                txnTz: txnTz,
                timePrecision: timePrecision,
                postedOn: postedOn,
                merchant: merchant,
                category: category,
                status: status,
                parentTransactionId: parentTransactionId,
                fingerprint: fingerprint,
                sourceKind: sourceKind,
                confirmationLevel: confirmationLevel,
                rowVersion: rowVersion,
                recordedAt: recordedAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardTransactionsTable, CardTransactionRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $CardTransactionsTable,
                    CardTransactionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CardTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardTransactionsTable,
      CardTransactionRow,
      $$CardTransactionsTableFilterComposer,
      $$CardTransactionsTableOrderingComposer,
      $$CardTransactionsTableAnnotationComposer,
      $$CardTransactionsTableCreateCompanionBuilder,
      $$CardTransactionsTableUpdateCompanionBuilder,
      (
        CardTransactionRow,
        BaseReferences<
          _$AppDatabase,
          $CardTransactionsTable,
          CardTransactionRow
        >,
      ),
      CardTransactionRow,
      PrefetchHooks Function()
    >;
typedef $$StatementVersionsTableCreateCompanionBuilder =
    StatementVersionsCompanion Function({
      required String id,
      required String workspaceId,
      required String statementId,
      required int versionNo,
      required String sourceKind,
      Value<int?> previousBalanceMinor,
      required int newBalanceMinor,
      Value<int?> minDueMinor,
      Value<int?> paymentsMinor,
      Value<int?> creditsMinor,
      Value<int?> feesMinor,
      Value<int?> interestMinor,
      Value<int?> installmentDueMinor,
      Value<int?> creditBalanceMinor,
      required String dueDate,
      required String recordedBy,
      Value<String?> reason,
      required String recordedAt,
      Value<int> rowid,
    });
typedef $$StatementVersionsTableUpdateCompanionBuilder =
    StatementVersionsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> statementId,
      Value<int> versionNo,
      Value<String> sourceKind,
      Value<int?> previousBalanceMinor,
      Value<int> newBalanceMinor,
      Value<int?> minDueMinor,
      Value<int?> paymentsMinor,
      Value<int?> creditsMinor,
      Value<int?> feesMinor,
      Value<int?> interestMinor,
      Value<int?> installmentDueMinor,
      Value<int?> creditBalanceMinor,
      Value<String> dueDate,
      Value<String> recordedBy,
      Value<String?> reason,
      Value<String> recordedAt,
      Value<int> rowid,
    });

class $$StatementVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $StatementVersionsTable> {
  $$StatementVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionNo => $composableBuilder(
    column: $table.versionNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get previousBalanceMinor => $composableBuilder(
    column: $table.previousBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get newBalanceMinor => $composableBuilder(
    column: $table.newBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minDueMinor => $composableBuilder(
    column: $table.minDueMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paymentsMinor => $composableBuilder(
    column: $table.paymentsMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get creditsMinor => $composableBuilder(
    column: $table.creditsMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feesMinor => $composableBuilder(
    column: $table.feesMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestMinor => $composableBuilder(
    column: $table.interestMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get installmentDueMinor => $composableBuilder(
    column: $table.installmentDueMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get creditBalanceMinor => $composableBuilder(
    column: $table.creditBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StatementVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $StatementVersionsTable> {
  $$StatementVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionNo => $composableBuilder(
    column: $table.versionNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get previousBalanceMinor => $composableBuilder(
    column: $table.previousBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get newBalanceMinor => $composableBuilder(
    column: $table.newBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minDueMinor => $composableBuilder(
    column: $table.minDueMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paymentsMinor => $composableBuilder(
    column: $table.paymentsMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get creditsMinor => $composableBuilder(
    column: $table.creditsMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feesMinor => $composableBuilder(
    column: $table.feesMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestMinor => $composableBuilder(
    column: $table.interestMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get installmentDueMinor => $composableBuilder(
    column: $table.installmentDueMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get creditBalanceMinor => $composableBuilder(
    column: $table.creditBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StatementVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StatementVersionsTable> {
  $$StatementVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get versionNo =>
      $composableBuilder(column: $table.versionNo, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<int> get previousBalanceMinor => $composableBuilder(
    column: $table.previousBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get newBalanceMinor => $composableBuilder(
    column: $table.newBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minDueMinor => $composableBuilder(
    column: $table.minDueMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paymentsMinor => $composableBuilder(
    column: $table.paymentsMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get creditsMinor => $composableBuilder(
    column: $table.creditsMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get feesMinor =>
      $composableBuilder(column: $table.feesMinor, builder: (column) => column);

  GeneratedColumn<int> get interestMinor => $composableBuilder(
    column: $table.interestMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get installmentDueMinor => $composableBuilder(
    column: $table.installmentDueMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get creditBalanceMinor => $composableBuilder(
    column: $table.creditBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$StatementVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StatementVersionsTable,
          StatementVersionRow,
          $$StatementVersionsTableFilterComposer,
          $$StatementVersionsTableOrderingComposer,
          $$StatementVersionsTableAnnotationComposer,
          $$StatementVersionsTableCreateCompanionBuilder,
          $$StatementVersionsTableUpdateCompanionBuilder,
          (
            StatementVersionRow,
            BaseReferences<
              _$AppDatabase,
              $StatementVersionsTable,
              StatementVersionRow
            >,
          ),
          StatementVersionRow,
          PrefetchHooks Function()
        > {
  $$StatementVersionsTableTableManager(
    _$AppDatabase db,
    $StatementVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StatementVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StatementVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StatementVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> statementId = const Value.absent(),
                Value<int> versionNo = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<int?> previousBalanceMinor = const Value.absent(),
                Value<int> newBalanceMinor = const Value.absent(),
                Value<int?> minDueMinor = const Value.absent(),
                Value<int?> paymentsMinor = const Value.absent(),
                Value<int?> creditsMinor = const Value.absent(),
                Value<int?> feesMinor = const Value.absent(),
                Value<int?> interestMinor = const Value.absent(),
                Value<int?> installmentDueMinor = const Value.absent(),
                Value<int?> creditBalanceMinor = const Value.absent(),
                Value<String> dueDate = const Value.absent(),
                Value<String> recordedBy = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<String> recordedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StatementVersionsCompanion(
                id: id,
                workspaceId: workspaceId,
                statementId: statementId,
                versionNo: versionNo,
                sourceKind: sourceKind,
                previousBalanceMinor: previousBalanceMinor,
                newBalanceMinor: newBalanceMinor,
                minDueMinor: minDueMinor,
                paymentsMinor: paymentsMinor,
                creditsMinor: creditsMinor,
                feesMinor: feesMinor,
                interestMinor: interestMinor,
                installmentDueMinor: installmentDueMinor,
                creditBalanceMinor: creditBalanceMinor,
                dueDate: dueDate,
                recordedBy: recordedBy,
                reason: reason,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String statementId,
                required int versionNo,
                required String sourceKind,
                Value<int?> previousBalanceMinor = const Value.absent(),
                required int newBalanceMinor,
                Value<int?> minDueMinor = const Value.absent(),
                Value<int?> paymentsMinor = const Value.absent(),
                Value<int?> creditsMinor = const Value.absent(),
                Value<int?> feesMinor = const Value.absent(),
                Value<int?> interestMinor = const Value.absent(),
                Value<int?> installmentDueMinor = const Value.absent(),
                Value<int?> creditBalanceMinor = const Value.absent(),
                required String dueDate,
                required String recordedBy,
                Value<String?> reason = const Value.absent(),
                required String recordedAt,
                Value<int> rowid = const Value.absent(),
              }) => StatementVersionsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                statementId: statementId,
                versionNo: versionNo,
                sourceKind: sourceKind,
                previousBalanceMinor: previousBalanceMinor,
                newBalanceMinor: newBalanceMinor,
                minDueMinor: minDueMinor,
                paymentsMinor: paymentsMinor,
                creditsMinor: creditsMinor,
                feesMinor: feesMinor,
                interestMinor: interestMinor,
                installmentDueMinor: installmentDueMinor,
                creditBalanceMinor: creditBalanceMinor,
                dueDate: dueDate,
                recordedBy: recordedBy,
                reason: reason,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StatementVersionsTable, StatementVersionRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $StatementVersionsTable,
                    StatementVersionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StatementVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StatementVersionsTable,
      StatementVersionRow,
      $$StatementVersionsTableFilterComposer,
      $$StatementVersionsTableOrderingComposer,
      $$StatementVersionsTableAnnotationComposer,
      $$StatementVersionsTableCreateCompanionBuilder,
      $$StatementVersionsTableUpdateCompanionBuilder,
      (
        StatementVersionRow,
        BaseReferences<
          _$AppDatabase,
          $StatementVersionsTable,
          StatementVersionRow
        >,
      ),
      StatementVersionRow,
      PrefetchHooks Function()
    >;
typedef $$StatementsTableCreateCompanionBuilder = StatementsCompanion Function({
  required String id,
  required String workspaceId,
  required String currencyAccountId,
  required String statementDate,
  required String dueDate,
  required String status,
  Value<String?> currentVersionId,
  Value<int> rowVersion,
  required String createdAt,
  required String updatedAt,
  Value<int> rowid,
});
typedef $$StatementsTableUpdateCompanionBuilder = StatementsCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> currencyAccountId,
  Value<String> statementDate,
  Value<String> dueDate,
  Value<String> status,
  Value<String?> currentVersionId,
  Value<int> rowVersion,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<int> rowid,
});

class $$StatementsTableFilterComposer
    extends Composer<_$AppDatabase, $StatementsTable> {
  $$StatementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentVersionId => $composableBuilder(
    column: $table.currentVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StatementsTableOrderingComposer
    extends Composer<_$AppDatabase, $StatementsTable> {
  $$StatementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentVersionId => $composableBuilder(
    column: $table.currentVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StatementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StatementsTable> {
  $$StatementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get currentVersionId => $composableBuilder(
    column: $table.currentVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StatementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StatementsTable,
          StatementRow,
          $$StatementsTableFilterComposer,
          $$StatementsTableOrderingComposer,
          $$StatementsTableAnnotationComposer,
          $$StatementsTableCreateCompanionBuilder,
          $$StatementsTableUpdateCompanionBuilder,
          (
            StatementRow,
            BaseReferences<_$AppDatabase, $StatementsTable, StatementRow>,
          ),
          StatementRow,
          PrefetchHooks Function()
        > {
  $$StatementsTableTableManager(_$AppDatabase db, $StatementsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StatementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StatementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StatementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<String> statementDate = const Value.absent(),
                Value<String> dueDate = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> currentVersionId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StatementsCompanion(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                statementDate: statementDate,
                dueDate: dueDate,
                status: status,
                currentVersionId: currentVersionId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String currencyAccountId,
                required String statementDate,
                required String dueDate,
                required String status,
                Value<String?> currentVersionId = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => StatementsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                statementDate: statementDate,
                dueDate: dueDate,
                status: status,
                currentVersionId: currentVersionId,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StatementsTable, StatementRow>(table),
                  BaseReferences<_$AppDatabase, $StatementsTable, StatementRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StatementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StatementsTable,
      StatementRow,
      $$StatementsTableFilterComposer,
      $$StatementsTableOrderingComposer,
      $$StatementsTableAnnotationComposer,
      $$StatementsTableCreateCompanionBuilder,
      $$StatementsTableUpdateCompanionBuilder,
      (
        StatementRow,
        BaseReferences<_$AppDatabase, $StatementsTable, StatementRow>,
      ),
      StatementRow,
      PrefetchHooks Function()
    >;
typedef $$InstallmentPlansTableCreateCompanionBuilder =
    InstallmentPlansCompanion Function({
      required String id,
      required String workspaceId,
      required String currencyAccountId,
      required String transactionId,
      required int principalMinor,
      required int periods,
      required String perPeriodRate,
      required String feeMode,
      required String remainderPolicy,
      required String rounding,
      required String status,
      Value<String?> earlySettledAt,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$InstallmentPlansTableUpdateCompanionBuilder =
    InstallmentPlansCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> currencyAccountId,
      Value<String> transactionId,
      Value<int> principalMinor,
      Value<int> periods,
      Value<String> perPeriodRate,
      Value<String> feeMode,
      Value<String> remainderPolicy,
      Value<String> rounding,
      Value<String> status,
      Value<String?> earlySettledAt,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$InstallmentPlansTableFilterComposer
    extends Composer<_$AppDatabase, $InstallmentPlansTable> {
  $$InstallmentPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periods => $composableBuilder(
    column: $table.periods,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get perPeriodRate => $composableBuilder(
    column: $table.perPeriodRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feeMode => $composableBuilder(
    column: $table.feeMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remainderPolicy => $composableBuilder(
    column: $table.remainderPolicy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rounding => $composableBuilder(
    column: $table.rounding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get earlySettledAt => $composableBuilder(
    column: $table.earlySettledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstallmentPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $InstallmentPlansTable> {
  $$InstallmentPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periods => $composableBuilder(
    column: $table.periods,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get perPeriodRate => $composableBuilder(
    column: $table.perPeriodRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feeMode => $composableBuilder(
    column: $table.feeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remainderPolicy => $composableBuilder(
    column: $table.remainderPolicy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rounding => $composableBuilder(
    column: $table.rounding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get earlySettledAt => $composableBuilder(
    column: $table.earlySettledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstallmentPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstallmentPlansTable> {
  $$InstallmentPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get periods =>
      $composableBuilder(column: $table.periods, builder: (column) => column);

  GeneratedColumn<String> get perPeriodRate => $composableBuilder(
    column: $table.perPeriodRate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get feeMode =>
      $composableBuilder(column: $table.feeMode, builder: (column) => column);

  GeneratedColumn<String> get remainderPolicy => $composableBuilder(
    column: $table.remainderPolicy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rounding =>
      $composableBuilder(column: $table.rounding, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get earlySettledAt => $composableBuilder(
    column: $table.earlySettledAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$InstallmentPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstallmentPlansTable,
          InstallmentPlanRow,
          $$InstallmentPlansTableFilterComposer,
          $$InstallmentPlansTableOrderingComposer,
          $$InstallmentPlansTableAnnotationComposer,
          $$InstallmentPlansTableCreateCompanionBuilder,
          $$InstallmentPlansTableUpdateCompanionBuilder,
          (
            InstallmentPlanRow,
            BaseReferences<
              _$AppDatabase,
              $InstallmentPlansTable,
              InstallmentPlanRow
            >,
          ),
          InstallmentPlanRow,
          PrefetchHooks Function()
        > {
  $$InstallmentPlansTableTableManager(
    _$AppDatabase db,
    $InstallmentPlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstallmentPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstallmentPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InstallmentPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<String> transactionId = const Value.absent(),
                Value<int> principalMinor = const Value.absent(),
                Value<int> periods = const Value.absent(),
                Value<String> perPeriodRate = const Value.absent(),
                Value<String> feeMode = const Value.absent(),
                Value<String> remainderPolicy = const Value.absent(),
                Value<String> rounding = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> earlySettledAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstallmentPlansCompanion(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                transactionId: transactionId,
                principalMinor: principalMinor,
                periods: periods,
                perPeriodRate: perPeriodRate,
                feeMode: feeMode,
                remainderPolicy: remainderPolicy,
                rounding: rounding,
                status: status,
                earlySettledAt: earlySettledAt,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String currencyAccountId,
                required String transactionId,
                required int principalMinor,
                required int periods,
                required String perPeriodRate,
                required String feeMode,
                required String remainderPolicy,
                required String rounding,
                required String status,
                Value<String?> earlySettledAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => InstallmentPlansCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                transactionId: transactionId,
                principalMinor: principalMinor,
                periods: periods,
                perPeriodRate: perPeriodRate,
                feeMode: feeMode,
                remainderPolicy: remainderPolicy,
                rounding: rounding,
                status: status,
                earlySettledAt: earlySettledAt,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InstallmentPlansTable, InstallmentPlanRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $InstallmentPlansTable,
                    InstallmentPlanRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstallmentPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstallmentPlansTable,
      InstallmentPlanRow,
      $$InstallmentPlansTableFilterComposer,
      $$InstallmentPlansTableOrderingComposer,
      $$InstallmentPlansTableAnnotationComposer,
      $$InstallmentPlansTableCreateCompanionBuilder,
      $$InstallmentPlansTableUpdateCompanionBuilder,
      (
        InstallmentPlanRow,
        BaseReferences<
          _$AppDatabase,
          $InstallmentPlansTable,
          InstallmentPlanRow
        >,
      ),
      InstallmentPlanRow,
      PrefetchHooks Function()
    >;
typedef $$InstallmentScheduleTableCreateCompanionBuilder =
    InstallmentScheduleCompanion Function({
      required String workspaceId,
      required String planId,
      required int periodNo,
      required int principalMinor,
      required int feeMinor,
      required String statementDate,
      required String dueDate,
      required String status,
      Value<int> rowid,
    });
typedef $$InstallmentScheduleTableUpdateCompanionBuilder =
    InstallmentScheduleCompanion Function({
      Value<String> workspaceId,
      Value<String> planId,
      Value<int> periodNo,
      Value<int> principalMinor,
      Value<int> feeMinor,
      Value<String> statementDate,
      Value<String> dueDate,
      Value<String> status,
      Value<int> rowid,
    });

class $$InstallmentScheduleTableFilterComposer
    extends Composer<_$AppDatabase, $InstallmentScheduleTable> {
  $$InstallmentScheduleTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get periodNo => $composableBuilder(
    column: $table.periodNo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feeMinor => $composableBuilder(
    column: $table.feeMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InstallmentScheduleTableOrderingComposer
    extends Composer<_$AppDatabase, $InstallmentScheduleTable> {
  $$InstallmentScheduleTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get periodNo => $composableBuilder(
    column: $table.periodNo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feeMinor => $composableBuilder(
    column: $table.feeMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InstallmentScheduleTableAnnotationComposer
    extends Composer<_$AppDatabase, $InstallmentScheduleTable> {
  $$InstallmentScheduleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<int> get periodNo =>
      $composableBuilder(column: $table.periodNo, builder: (column) => column);

  GeneratedColumn<int> get principalMinor => $composableBuilder(
    column: $table.principalMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get feeMinor =>
      $composableBuilder(column: $table.feeMinor, builder: (column) => column);

  GeneratedColumn<String> get statementDate => $composableBuilder(
    column: $table.statementDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$InstallmentScheduleTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InstallmentScheduleTable,
          InstallmentScheduleRow,
          $$InstallmentScheduleTableFilterComposer,
          $$InstallmentScheduleTableOrderingComposer,
          $$InstallmentScheduleTableAnnotationComposer,
          $$InstallmentScheduleTableCreateCompanionBuilder,
          $$InstallmentScheduleTableUpdateCompanionBuilder,
          (
            InstallmentScheduleRow,
            BaseReferences<
              _$AppDatabase,
              $InstallmentScheduleTable,
              InstallmentScheduleRow
            >,
          ),
          InstallmentScheduleRow,
          PrefetchHooks Function()
        > {
  $$InstallmentScheduleTableTableManager(
    _$AppDatabase db,
    $InstallmentScheduleTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InstallmentScheduleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InstallmentScheduleTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InstallmentScheduleTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<int> periodNo = const Value.absent(),
                Value<int> principalMinor = const Value.absent(),
                Value<int> feeMinor = const Value.absent(),
                Value<String> statementDate = const Value.absent(),
                Value<String> dueDate = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InstallmentScheduleCompanion(
                workspaceId: workspaceId,
                planId: planId,
                periodNo: periodNo,
                principalMinor: principalMinor,
                feeMinor: feeMinor,
                statementDate: statementDate,
                dueDate: dueDate,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String planId,
                required int periodNo,
                required int principalMinor,
                required int feeMinor,
                required String statementDate,
                required String dueDate,
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => InstallmentScheduleCompanion.insert(
                workspaceId: workspaceId,
                planId: planId,
                periodNo: periodNo,
                principalMinor: principalMinor,
                feeMinor: feeMinor,
                statementDate: statementDate,
                dueDate: dueDate,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $InstallmentScheduleTable,
                    InstallmentScheduleRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $InstallmentScheduleTable,
                    InstallmentScheduleRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InstallmentScheduleTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InstallmentScheduleTable,
      InstallmentScheduleRow,
      $$InstallmentScheduleTableFilterComposer,
      $$InstallmentScheduleTableOrderingComposer,
      $$InstallmentScheduleTableAnnotationComposer,
      $$InstallmentScheduleTableCreateCompanionBuilder,
      $$InstallmentScheduleTableUpdateCompanionBuilder,
      (
        InstallmentScheduleRow,
        BaseReferences<
          _$AppDatabase,
          $InstallmentScheduleTable,
          InstallmentScheduleRow
        >,
      ),
      InstallmentScheduleRow,
      PrefetchHooks Function()
    >;
typedef $$RepaymentsTableCreateCompanionBuilder = RepaymentsCompanion Function({
  required String id,
  required String workspaceId,
  required String currencyAccountId,
  Value<String?> cashAccountId,
  required int amountMinor,
  required String currency,
  required String status,
  required String method,
  Value<String?> paymentInitiatedAt,
  Value<String?> expectedDebitOn,
  Value<String?> cashDebitedAt,
  Value<String?> creditPostedAt,
  Value<String?> bankConfirmedAt,
  Value<String?> evidenceNote,
  Value<int> rowVersion,
  required String createdAt,
  required String updatedAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});
typedef $$RepaymentsTableUpdateCompanionBuilder = RepaymentsCompanion Function({
  Value<String> id,
  Value<String> workspaceId,
  Value<String> currencyAccountId,
  Value<String?> cashAccountId,
  Value<int> amountMinor,
  Value<String> currency,
  Value<String> status,
  Value<String> method,
  Value<String?> paymentInitiatedAt,
  Value<String?> expectedDebitOn,
  Value<String?> cashDebitedAt,
  Value<String?> creditPostedAt,
  Value<String?> bankConfirmedAt,
  Value<String?> evidenceNote,
  Value<int> rowVersion,
  Value<String> createdAt,
  Value<String> updatedAt,
  Value<String?> deletedAt,
  Value<int> rowid,
});

class $$RepaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $RepaymentsTable> {
  $$RepaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentInitiatedAt => $composableBuilder(
    column: $table.paymentInitiatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedDebitOn => $composableBuilder(
    column: $table.expectedDebitOn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashDebitedAt => $composableBuilder(
    column: $table.cashDebitedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creditPostedAt => $composableBuilder(
    column: $table.creditPostedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bankConfirmedAt => $composableBuilder(
    column: $table.bankConfirmedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceNote => $composableBuilder(
    column: $table.evidenceNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RepaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $RepaymentsTable> {
  $$RepaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentInitiatedAt => $composableBuilder(
    column: $table.paymentInitiatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedDebitOn => $composableBuilder(
    column: $table.expectedDebitOn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashDebitedAt => $composableBuilder(
    column: $table.cashDebitedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creditPostedAt => $composableBuilder(
    column: $table.creditPostedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bankConfirmedAt => $composableBuilder(
    column: $table.bankConfirmedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceNote => $composableBuilder(
    column: $table.evidenceNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RepaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RepaymentsTable> {
  $$RepaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashAccountId => $composableBuilder(
    column: $table.cashAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get paymentInitiatedAt => $composableBuilder(
    column: $table.paymentInitiatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expectedDebitOn => $composableBuilder(
    column: $table.expectedDebitOn,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cashDebitedAt => $composableBuilder(
    column: $table.cashDebitedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get creditPostedAt => $composableBuilder(
    column: $table.creditPostedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bankConfirmedAt => $composableBuilder(
    column: $table.bankConfirmedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceNote => $composableBuilder(
    column: $table.evidenceNote,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$RepaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RepaymentsTable,
          RepaymentRow,
          $$RepaymentsTableFilterComposer,
          $$RepaymentsTableOrderingComposer,
          $$RepaymentsTableAnnotationComposer,
          $$RepaymentsTableCreateCompanionBuilder,
          $$RepaymentsTableUpdateCompanionBuilder,
          (
            RepaymentRow,
            BaseReferences<_$AppDatabase, $RepaymentsTable, RepaymentRow>,
          ),
          RepaymentRow,
          PrefetchHooks Function()
        > {
  $$RepaymentsTableTableManager(_$AppDatabase db, $RepaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RepaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RepaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RepaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<String?> cashAccountId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<String?> paymentInitiatedAt = const Value.absent(),
                Value<String?> expectedDebitOn = const Value.absent(),
                Value<String?> cashDebitedAt = const Value.absent(),
                Value<String?> creditPostedAt = const Value.absent(),
                Value<String?> bankConfirmedAt = const Value.absent(),
                Value<String?> evidenceNote = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RepaymentsCompanion(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                cashAccountId: cashAccountId,
                amountMinor: amountMinor,
                currency: currency,
                status: status,
                method: method,
                paymentInitiatedAt: paymentInitiatedAt,
                expectedDebitOn: expectedDebitOn,
                cashDebitedAt: cashDebitedAt,
                creditPostedAt: creditPostedAt,
                bankConfirmedAt: bankConfirmedAt,
                evidenceNote: evidenceNote,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String currencyAccountId,
                Value<String?> cashAccountId = const Value.absent(),
                required int amountMinor,
                required String currency,
                required String status,
                required String method,
                Value<String?> paymentInitiatedAt = const Value.absent(),
                Value<String?> expectedDebitOn = const Value.absent(),
                Value<String?> cashDebitedAt = const Value.absent(),
                Value<String?> creditPostedAt = const Value.absent(),
                Value<String?> bankConfirmedAt = const Value.absent(),
                Value<String?> evidenceNote = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<String?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RepaymentsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                cashAccountId: cashAccountId,
                amountMinor: amountMinor,
                currency: currency,
                status: status,
                method: method,
                paymentInitiatedAt: paymentInitiatedAt,
                expectedDebitOn: expectedDebitOn,
                cashDebitedAt: cashDebitedAt,
                creditPostedAt: creditPostedAt,
                bankConfirmedAt: bankConfirmedAt,
                evidenceNote: evidenceNote,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RepaymentsTable, RepaymentRow>(table),
                  BaseReferences<_$AppDatabase, $RepaymentsTable, RepaymentRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RepaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RepaymentsTable,
      RepaymentRow,
      $$RepaymentsTableFilterComposer,
      $$RepaymentsTableOrderingComposer,
      $$RepaymentsTableAnnotationComposer,
      $$RepaymentsTableCreateCompanionBuilder,
      $$RepaymentsTableUpdateCompanionBuilder,
      (
        RepaymentRow,
        BaseReferences<_$AppDatabase, $RepaymentsTable, RepaymentRow>,
      ),
      RepaymentRow,
      PrefetchHooks Function()
    >;
typedef $$RepaymentAllocationsTableCreateCompanionBuilder =
    RepaymentAllocationsCompanion Function({
      required String workspaceId,
      required String currencyAccountId,
      required String repaymentId,
      required String statementId,
      required int amountMinor,
      Value<int> rowid,
    });
typedef $$RepaymentAllocationsTableUpdateCompanionBuilder =
    RepaymentAllocationsCompanion Function({
      Value<String> workspaceId,
      Value<String> currencyAccountId,
      Value<String> repaymentId,
      Value<String> statementId,
      Value<int> amountMinor,
      Value<int> rowid,
    });

class $$RepaymentAllocationsTableFilterComposer
    extends Composer<_$AppDatabase, $RepaymentAllocationsTable> {
  $$RepaymentAllocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repaymentId => $composableBuilder(
    column: $table.repaymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RepaymentAllocationsTableOrderingComposer
    extends Composer<_$AppDatabase, $RepaymentAllocationsTable> {
  $$RepaymentAllocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repaymentId => $composableBuilder(
    column: $table.repaymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RepaymentAllocationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RepaymentAllocationsTable> {
  $$RepaymentAllocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyAccountId => $composableBuilder(
    column: $table.currencyAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repaymentId => $composableBuilder(
    column: $table.repaymentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get statementId => $composableBuilder(
    column: $table.statementId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );
}

class $$RepaymentAllocationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RepaymentAllocationsTable,
          RepaymentAllocationRow,
          $$RepaymentAllocationsTableFilterComposer,
          $$RepaymentAllocationsTableOrderingComposer,
          $$RepaymentAllocationsTableAnnotationComposer,
          $$RepaymentAllocationsTableCreateCompanionBuilder,
          $$RepaymentAllocationsTableUpdateCompanionBuilder,
          (
            RepaymentAllocationRow,
            BaseReferences<
              _$AppDatabase,
              $RepaymentAllocationsTable,
              RepaymentAllocationRow
            >,
          ),
          RepaymentAllocationRow,
          PrefetchHooks Function()
        > {
  $$RepaymentAllocationsTableTableManager(
    _$AppDatabase db,
    $RepaymentAllocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RepaymentAllocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RepaymentAllocationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RepaymentAllocationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> workspaceId = const Value.absent(),
                Value<String> currencyAccountId = const Value.absent(),
                Value<String> repaymentId = const Value.absent(),
                Value<String> statementId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RepaymentAllocationsCompanion(
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                repaymentId: repaymentId,
                statementId: statementId,
                amountMinor: amountMinor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workspaceId,
                required String currencyAccountId,
                required String repaymentId,
                required String statementId,
                required int amountMinor,
                Value<int> rowid = const Value.absent(),
              }) => RepaymentAllocationsCompanion.insert(
                workspaceId: workspaceId,
                currencyAccountId: currencyAccountId,
                repaymentId: repaymentId,
                statementId: statementId,
                amountMinor: amountMinor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $RepaymentAllocationsTable,
                    RepaymentAllocationRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RepaymentAllocationsTable,
                    RepaymentAllocationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RepaymentAllocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RepaymentAllocationsTable,
      RepaymentAllocationRow,
      $$RepaymentAllocationsTableFilterComposer,
      $$RepaymentAllocationsTableOrderingComposer,
      $$RepaymentAllocationsTableAnnotationComposer,
      $$RepaymentAllocationsTableCreateCompanionBuilder,
      $$RepaymentAllocationsTableUpdateCompanionBuilder,
      (
        RepaymentAllocationRow,
        BaseReferences<
          _$AppDatabase,
          $RepaymentAllocationsTable,
          RepaymentAllocationRow
        >,
      ),
      RepaymentAllocationRow,
      PrefetchHooks Function()
    >;
typedef $$ReconciliationItemsTableCreateCompanionBuilder =
    ReconciliationItemsCompanion Function({
      required String id,
      required String workspaceId,
      required String kind,
      required String refs,
      Value<String> status,
      Value<String?> resolution,
      Value<String?> resolvedBy,
      Value<String?> resolvedAt,
      Value<int> rowVersion,
      required String createdAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ReconciliationItemsTableUpdateCompanionBuilder =
    ReconciliationItemsCompanion Function({
      Value<String> id,
      Value<String> workspaceId,
      Value<String> kind,
      Value<String> refs,
      Value<String> status,
      Value<String?> resolution,
      Value<String?> resolvedBy,
      Value<String?> resolvedAt,
      Value<int> rowVersion,
      Value<String> createdAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$ReconciliationItemsTableFilterComposer
    extends Composer<_$AppDatabase, $ReconciliationItemsTable> {
  $$ReconciliationItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refs => $composableBuilder(
    column: $table.refs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolvedBy => $composableBuilder(
    column: $table.resolvedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReconciliationItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReconciliationItemsTable> {
  $$ReconciliationItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refs => $composableBuilder(
    column: $table.refs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolvedBy => $composableBuilder(
    column: $table.resolvedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReconciliationItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReconciliationItemsTable> {
  $$ReconciliationItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get refs =>
      $composableBuilder(column: $table.refs, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolvedBy => $composableBuilder(
    column: $table.resolvedBy,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolvedAt => $composableBuilder(
    column: $table.resolvedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowVersion => $composableBuilder(
    column: $table.rowVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReconciliationItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReconciliationItemsTable,
          ReconciliationItemRow,
          $$ReconciliationItemsTableFilterComposer,
          $$ReconciliationItemsTableOrderingComposer,
          $$ReconciliationItemsTableAnnotationComposer,
          $$ReconciliationItemsTableCreateCompanionBuilder,
          $$ReconciliationItemsTableUpdateCompanionBuilder,
          (
            ReconciliationItemRow,
            BaseReferences<
              _$AppDatabase,
              $ReconciliationItemsTable,
              ReconciliationItemRow
            >,
          ),
          ReconciliationItemRow,
          PrefetchHooks Function()
        > {
  $$ReconciliationItemsTableTableManager(
    _$AppDatabase db,
    $ReconciliationItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReconciliationItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReconciliationItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReconciliationItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> refs = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<String?> resolvedBy = const Value.absent(),
                Value<String?> resolvedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReconciliationItemsCompanion(
                id: id,
                workspaceId: workspaceId,
                kind: kind,
                refs: refs,
                status: status,
                resolution: resolution,
                resolvedBy: resolvedBy,
                resolvedAt: resolvedAt,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String workspaceId,
                required String kind,
                required String refs,
                Value<String> status = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<String?> resolvedBy = const Value.absent(),
                Value<String?> resolvedAt = const Value.absent(),
                Value<int> rowVersion = const Value.absent(),
                required String createdAt,
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReconciliationItemsCompanion.insert(
                id: id,
                workspaceId: workspaceId,
                kind: kind,
                refs: refs,
                status: status,
                resolution: resolution,
                resolvedBy: resolvedBy,
                resolvedAt: resolvedAt,
                rowVersion: rowVersion,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReconciliationItemsTable, ReconciliationItemRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ReconciliationItemsTable,
                    ReconciliationItemRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReconciliationItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReconciliationItemsTable,
      ReconciliationItemRow,
      $$ReconciliationItemsTableFilterComposer,
      $$ReconciliationItemsTableOrderingComposer,
      $$ReconciliationItemsTableAnnotationComposer,
      $$ReconciliationItemsTableCreateCompanionBuilder,
      $$ReconciliationItemsTableUpdateCompanionBuilder,
      (
        ReconciliationItemRow,
        BaseReferences<
          _$AppDatabase,
          $ReconciliationItemsTable,
          ReconciliationItemRow
        >,
      ),
      ReconciliationItemRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WorkspacesTableTableManager get workspaces =>
      $$WorkspacesTableTableManager(_db, _db.workspaces);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$BanksTableTableManager get banks =>
      $$BanksTableTableManager(_db, _db.banks);
  $$CreditPoolsTableTableManager get creditPools =>
      $$CreditPoolsTableTableManager(_db, _db.creditPools);
  $$CreditAccountsTableTableManager get creditAccounts =>
      $$CreditAccountsTableTableManager(_db, _db.creditAccounts);
  $$CurrencyAccountsTableTableManager get currencyAccounts =>
      $$CurrencyAccountsTableTableManager(_db, _db.currencyAccounts);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
  $$BillingRuleVersionsTableTableManager get billingRuleVersions =>
      $$BillingRuleVersionsTableTableManager(_db, _db.billingRuleVersions);
  $$LimitSnapshotsTableTableManager get limitSnapshots =>
      $$LimitSnapshotsTableTableManager(_db, _db.limitSnapshots);
  $$CashAccountsTableTableManager get cashAccounts =>
      $$CashAccountsTableTableManager(_db, _db.cashAccounts);
  $$CashBalanceSnapshotsTableTableManager get cashBalanceSnapshots =>
      $$CashBalanceSnapshotsTableTableManager(_db, _db.cashBalanceSnapshots);
  $$RecurringItemsTableTableManager get recurringItems =>
      $$RecurringItemsTableTableManager(_db, _db.recurringItems);
  $$CashEventsTableTableManager get cashEvents =>
      $$CashEventsTableTableManager(_db, _db.cashEvents);
  $$SnapshotIncludedEventsTableTableManager get snapshotIncludedEvents =>
      $$SnapshotIncludedEventsTableTableManager(
        _db,
        _db.snapshotIncludedEvents,
      );
  $$RecurringOverridesTableTableManager get recurringOverrides =>
      $$RecurringOverridesTableTableManager(_db, _db.recurringOverrides);
  $$ScenariosTableTableManager get scenarios =>
      $$ScenariosTableTableManager(_db, _db.scenarios);
  $$ScenarioRunsTableTableManager get scenarioRuns =>
      $$ScenarioRunsTableTableManager(_db, _db.scenarioRuns);
  $$CardTransactionsTableTableManager get cardTransactions =>
      $$CardTransactionsTableTableManager(_db, _db.cardTransactions);
  $$StatementVersionsTableTableManager get statementVersions =>
      $$StatementVersionsTableTableManager(_db, _db.statementVersions);
  $$StatementsTableTableManager get statements =>
      $$StatementsTableTableManager(_db, _db.statements);
  $$InstallmentPlansTableTableManager get installmentPlans =>
      $$InstallmentPlansTableTableManager(_db, _db.installmentPlans);
  $$InstallmentScheduleTableTableManager get installmentSchedule =>
      $$InstallmentScheduleTableTableManager(_db, _db.installmentSchedule);
  $$RepaymentsTableTableManager get repayments =>
      $$RepaymentsTableTableManager(_db, _db.repayments);
  $$RepaymentAllocationsTableTableManager get repaymentAllocations =>
      $$RepaymentAllocationsTableTableManager(_db, _db.repaymentAllocations);
  $$ReconciliationItemsTableTableManager get reconciliationItems =>
      $$ReconciliationItemsTableTableManager(_db, _db.reconciliationItems);
}
