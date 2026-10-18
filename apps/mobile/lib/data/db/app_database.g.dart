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
}
