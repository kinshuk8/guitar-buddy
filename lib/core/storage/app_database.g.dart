// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(Insertable<Setting> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
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

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
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
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
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

  SettingsCompanion copyWith({Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SettingsCompanion(
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
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteChordsTable extends FavoriteChords
    with TableInfo<$FavoriteChordsTable, FavoriteChord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteChordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [symbol, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_chords';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteChord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(_symbolMeta, symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta));
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta, addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {symbol};
  @override
  FavoriteChord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteChord(
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FavoriteChordsTable createAlias(String alias) {
    return $FavoriteChordsTable(attachedDatabase, alias);
  }
}

class FavoriteChord extends DataClass implements Insertable<FavoriteChord> {
  final String symbol;
  final DateTime addedAt;
  const FavoriteChord({required this.symbol, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['symbol'] = Variable<String>(symbol);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FavoriteChordsCompanion toCompanion(bool nullToAbsent) {
    return FavoriteChordsCompanion(symbol: Value(symbol), addedAt: Value(addedAt));
  }

  factory FavoriteChord.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteChord(
      symbol: serializer.fromJson<String>(json['symbol']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  FavoriteChord copyWith({String? symbol, DateTime? addedAt}) =>
      FavoriteChord(symbol: symbol ?? this.symbol, addedAt: addedAt ?? this.addedAt);
  FavoriteChord copyWithCompanion(FavoriteChordsCompanion data) {
    return FavoriteChord(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteChord(')
          ..write('symbol: $symbol, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(symbol, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteChord && other.symbol == this.symbol && other.addedAt == this.addedAt);
}

class FavoriteChordsCompanion extends UpdateCompanion<FavoriteChord> {
  final Value<String> symbol;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const FavoriteChordsCompanion({
    this.symbol = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteChordsCompanion.insert({
    required String symbol,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : symbol = Value(symbol),
       addedAt = Value(addedAt);
  static Insertable<FavoriteChord> custom({
    Expression<String>? symbol,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteChordsCompanion copyWith({
    Value<String>? symbol,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return FavoriteChordsCompanion(
      symbol: symbol ?? this.symbol,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteChordsCompanion(')
          ..write('symbol: $symbol, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomTuningsTable extends CustomTunings with TableInfo<$CustomTuningsTable, CustomTuning> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomTuningsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, notes, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_tunings';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomTuning> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(_notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    } else if (isInserting) {
      context.missing(_notesMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomTuning map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomTuning(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $CustomTuningsTable createAlias(String alias) {
    return $CustomTuningsTable(attachedDatabase, alias);
  }
}

class CustomTuning extends DataClass implements Insertable<CustomTuning> {
  final String id;
  final String name;
  final String notes;
  final int position;
  const CustomTuning({
    required this.id,
    required this.name,
    required this.notes,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['notes'] = Variable<String>(notes);
    map['position'] = Variable<int>(position);
    return map;
  }

  CustomTuningsCompanion toCompanion(bool nullToAbsent) {
    return CustomTuningsCompanion(
      id: Value(id),
      name: Value(name),
      notes: Value(notes),
      position: Value(position),
    );
  }

  factory CustomTuning.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomTuning(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      notes: serializer.fromJson<String>(json['notes']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'notes': serializer.toJson<String>(notes),
      'position': serializer.toJson<int>(position),
    };
  }

  CustomTuning copyWith({String? id, String? name, String? notes, int? position}) => CustomTuning(
    id: id ?? this.id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    position: position ?? this.position,
  );
  CustomTuning copyWithCompanion(CustomTuningsCompanion data) {
    return CustomTuning(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      notes: data.notes.present ? data.notes.value : this.notes,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomTuning(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notes: $notes, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, notes, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomTuning &&
          other.id == this.id &&
          other.name == this.name &&
          other.notes == this.notes &&
          other.position == this.position);
}

class CustomTuningsCompanion extends UpdateCompanion<CustomTuning> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> notes;
  final Value<int> position;
  final Value<int> rowid;
  const CustomTuningsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.notes = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomTuningsCompanion.insert({
    required String id,
    required String name,
    required String notes,
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       notes = Value(notes),
       position = Value(position);
  static Insertable<CustomTuning> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? notes,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomTuningsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? notes,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return CustomTuningsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomTuningsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notes: $notes, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSongsTable extends UserSongs with TableInfo<$UserSongsTable, UserSong> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _addedAtMeta = const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, source, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_songs';
  @override
  VerificationContext validateIntegrity(Insertable<UserSong> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta, source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta, addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserSong map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserSong(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $UserSongsTable createAlias(String alias) {
    return $UserSongsTable(attachedDatabase, alias);
  }
}

class UserSong extends DataClass implements Insertable<UserSong> {
  final String id;
  final String source;
  final DateTime addedAt;
  const UserSong({required this.id, required this.source, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source'] = Variable<String>(source);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  UserSongsCompanion toCompanion(bool nullToAbsent) {
    return UserSongsCompanion(id: Value(id), source: Value(source), addedAt: Value(addedAt));
  }

  factory UserSong.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserSong(
      id: serializer.fromJson<String>(json['id']),
      source: serializer.fromJson<String>(json['source']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'source': serializer.toJson<String>(source),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  UserSong copyWith({String? id, String? source, DateTime? addedAt}) =>
      UserSong(id: id ?? this.id, source: source ?? this.source, addedAt: addedAt ?? this.addedAt);
  UserSong copyWithCompanion(UserSongsCompanion data) {
    return UserSong(
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserSong(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, source, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserSong &&
          other.id == this.id &&
          other.source == this.source &&
          other.addedAt == this.addedAt);
}

class UserSongsCompanion extends UpdateCompanion<UserSong> {
  final Value<String> id;
  final Value<String> source;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const UserSongsCompanion({
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserSongsCompanion.insert({
    required String id,
    required String source,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       source = Value(source),
       addedAt = Value(addedAt);
  static Insertable<UserSong> custom({
    Expression<String>? id,
    Expression<String>? source,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserSongsCompanion copyWith({
    Value<String>? id,
    Value<String>? source,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return UserSongsCompanion(
      id: id ?? this.id,
      source: source ?? this.source,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSongsCompanion(')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomChordsTable extends CustomChords with TableInfo<$CustomChordsTable, CustomChord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomChordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _fretsMeta = const VerificationMeta('frets');
  @override
  late final GeneratedColumn<String> frets = GeneratedColumn<String>(
    'frets',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, frets, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_chords';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomChord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('frets')) {
      context.handle(_fretsMeta, frets.isAcceptableOrUnknown(data['frets']!, _fretsMeta));
    } else if (isInserting) {
      context.missing(_fretsMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta, addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomChord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomChord(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      frets: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frets'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $CustomChordsTable createAlias(String alias) {
    return $CustomChordsTable(attachedDatabase, alias);
  }
}

class CustomChord extends DataClass implements Insertable<CustomChord> {
  final String id;
  final String name;
  final String frets;
  final DateTime addedAt;
  const CustomChord({
    required this.id,
    required this.name,
    required this.frets,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['frets'] = Variable<String>(frets);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  CustomChordsCompanion toCompanion(bool nullToAbsent) {
    return CustomChordsCompanion(
      id: Value(id),
      name: Value(name),
      frets: Value(frets),
      addedAt: Value(addedAt),
    );
  }

  factory CustomChord.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomChord(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      frets: serializer.fromJson<String>(json['frets']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'frets': serializer.toJson<String>(frets),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  CustomChord copyWith({String? id, String? name, String? frets, DateTime? addedAt}) => CustomChord(
    id: id ?? this.id,
    name: name ?? this.name,
    frets: frets ?? this.frets,
    addedAt: addedAt ?? this.addedAt,
  );
  CustomChord copyWithCompanion(CustomChordsCompanion data) {
    return CustomChord(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      frets: data.frets.present ? data.frets.value : this.frets,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomChord(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('frets: $frets, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, frets, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomChord &&
          other.id == this.id &&
          other.name == this.name &&
          other.frets == this.frets &&
          other.addedAt == this.addedAt);
}

class CustomChordsCompanion extends UpdateCompanion<CustomChord> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> frets;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const CustomChordsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.frets = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomChordsCompanion.insert({
    required String id,
    required String name,
    required String frets,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       frets = Value(frets),
       addedAt = Value(addedAt);
  static Insertable<CustomChord> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? frets,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (frets != null) 'frets': frets,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomChordsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? frets,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return CustomChordsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      frets: frets ?? this.frets,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (frets.present) {
      map['frets'] = Variable<String>(frets.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomChordsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('frets: $frets, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $FavoriteChordsTable favoriteChords = $FavoriteChordsTable(this);
  late final $CustomTuningsTable customTunings = $CustomTuningsTable(this);
  late final $UserSongsTable userSongs = $UserSongsTable(this);
  late final $CustomChordsTable customChords = $CustomChordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settings,
    favoriteChords,
    customTunings,
    userSongs,
    customChords,
  ];
}

typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsTableOrderingComposer extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsTableAnnotationComposer extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
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

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$FavoriteChordsTableCreateCompanionBuilder = FavoriteChordsCompanion Function({
  required String symbol,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$FavoriteChordsTableUpdateCompanionBuilder = FavoriteChordsCompanion Function({
  Value<String> symbol,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$FavoriteChordsTableFilterComposer extends Composer<_$AppDatabase, $FavoriteChordsTable> {
  $$FavoriteChordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$FavoriteChordsTableOrderingComposer extends Composer<_$AppDatabase, $FavoriteChordsTable> {
  $$FavoriteChordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$FavoriteChordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteChordsTable> {
  $$FavoriteChordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$FavoriteChordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoriteChordsTable,
          FavoriteChord,
          $$FavoriteChordsTableFilterComposer,
          $$FavoriteChordsTableOrderingComposer,
          $$FavoriteChordsTableAnnotationComposer,
          $$FavoriteChordsTableCreateCompanionBuilder,
          $$FavoriteChordsTableUpdateCompanionBuilder,
          (FavoriteChord, BaseReferences<_$AppDatabase, $FavoriteChordsTable, FavoriteChord>),
          FavoriteChord,
          PrefetchHooks Function()
        > {
  $$FavoriteChordsTableTableManager(_$AppDatabase db, $FavoriteChordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteChordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteChordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteChordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> symbol = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => FavoriteChordsCompanion(symbol: symbol, addedAt: addedAt, rowid: rowid),
          createCompanionCallback: ({
            required String symbol,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) => FavoriteChordsCompanion.insert(symbol: symbol, addedAt: addedAt, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FavoriteChordsTable, FavoriteChord>(table),
                  BaseReferences<_$AppDatabase, $FavoriteChordsTable, FavoriteChord>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteChordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoriteChordsTable,
      FavoriteChord,
      $$FavoriteChordsTableFilterComposer,
      $$FavoriteChordsTableOrderingComposer,
      $$FavoriteChordsTableAnnotationComposer,
      $$FavoriteChordsTableCreateCompanionBuilder,
      $$FavoriteChordsTableUpdateCompanionBuilder,
      (FavoriteChord, BaseReferences<_$AppDatabase, $FavoriteChordsTable, FavoriteChord>),
      FavoriteChord,
      PrefetchHooks Function()
    >;
typedef $$CustomTuningsTableCreateCompanionBuilder = CustomTuningsCompanion Function({
  required String id,
  required String name,
  required String notes,
  required int position,
  Value<int> rowid,
});
typedef $$CustomTuningsTableUpdateCompanionBuilder = CustomTuningsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> notes,
  Value<int> position,
  Value<int> rowid,
});

class $$CustomTuningsTableFilterComposer extends Composer<_$AppDatabase, $CustomTuningsTable> {
  $$CustomTuningsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => ColumnFilters(column));
}

class $$CustomTuningsTableOrderingComposer extends Composer<_$AppDatabase, $CustomTuningsTable> {
  $$CustomTuningsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => ColumnOrderings(column));
}

class $$CustomTuningsTableAnnotationComposer extends Composer<_$AppDatabase, $CustomTuningsTable> {
  $$CustomTuningsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$CustomTuningsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomTuningsTable,
          CustomTuning,
          $$CustomTuningsTableFilterComposer,
          $$CustomTuningsTableOrderingComposer,
          $$CustomTuningsTableAnnotationComposer,
          $$CustomTuningsTableCreateCompanionBuilder,
          $$CustomTuningsTableUpdateCompanionBuilder,
          (CustomTuning, BaseReferences<_$AppDatabase, $CustomTuningsTable, CustomTuning>),
          CustomTuning,
          PrefetchHooks Function()
        > {
  $$CustomTuningsTableTableManager(_$AppDatabase db, $CustomTuningsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$CustomTuningsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomTuningsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomTuningsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomTuningsCompanion(
                id: id,
                name: name,
                notes: notes,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String notes,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => CustomTuningsCompanion.insert(
                id: id,
                name: name,
                notes: notes,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomTuningsTable, CustomTuning>(table),
                  BaseReferences<_$AppDatabase, $CustomTuningsTable, CustomTuning>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomTuningsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomTuningsTable,
      CustomTuning,
      $$CustomTuningsTableFilterComposer,
      $$CustomTuningsTableOrderingComposer,
      $$CustomTuningsTableAnnotationComposer,
      $$CustomTuningsTableCreateCompanionBuilder,
      $$CustomTuningsTableUpdateCompanionBuilder,
      (CustomTuning, BaseReferences<_$AppDatabase, $CustomTuningsTable, CustomTuning>),
      CustomTuning,
      PrefetchHooks Function()
    >;
typedef $$UserSongsTableCreateCompanionBuilder = UserSongsCompanion Function({
  required String id,
  required String source,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$UserSongsTableUpdateCompanionBuilder = UserSongsCompanion Function({
  Value<String> id,
  Value<String> source,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$UserSongsTableFilterComposer extends Composer<_$AppDatabase, $UserSongsTable> {
  $$UserSongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$UserSongsTableOrderingComposer extends Composer<_$AppDatabase, $UserSongsTable> {
  $$UserSongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$UserSongsTableAnnotationComposer extends Composer<_$AppDatabase, $UserSongsTable> {
  $$UserSongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$UserSongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSongsTable,
          UserSong,
          $$UserSongsTableFilterComposer,
          $$UserSongsTableOrderingComposer,
          $$UserSongsTableAnnotationComposer,
          $$UserSongsTableCreateCompanionBuilder,
          $$UserSongsTableUpdateCompanionBuilder,
          (UserSong, BaseReferences<_$AppDatabase, $UserSongsTable, UserSong>),
          UserSong,
          PrefetchHooks Function()
        > {
  $$UserSongsTableTableManager(_$AppDatabase db, $UserSongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$UserSongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$UserSongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => UserSongsCompanion(id: id, source: source, addedAt: addedAt, rowid: rowid),
          createCompanionCallback: ({
            required String id,
            required String source,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) => UserSongsCompanion.insert(id: id, source: source, addedAt: addedAt, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserSongsTable, UserSong>(table),
                  BaseReferences<_$AppDatabase, $UserSongsTable, UserSong>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserSongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSongsTable,
      UserSong,
      $$UserSongsTableFilterComposer,
      $$UserSongsTableOrderingComposer,
      $$UserSongsTableAnnotationComposer,
      $$UserSongsTableCreateCompanionBuilder,
      $$UserSongsTableUpdateCompanionBuilder,
      (UserSong, BaseReferences<_$AppDatabase, $UserSongsTable, UserSong>),
      UserSong,
      PrefetchHooks Function()
    >;
typedef $$CustomChordsTableCreateCompanionBuilder = CustomChordsCompanion Function({
  required String id,
  required String name,
  required String frets,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$CustomChordsTableUpdateCompanionBuilder = CustomChordsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> frets,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$CustomChordsTableFilterComposer extends Composer<_$AppDatabase, $CustomChordsTable> {
  $$CustomChordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get frets =>
      $composableBuilder(column: $table.frets, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnFilters(column));
}

class $$CustomChordsTableOrderingComposer extends Composer<_$AppDatabase, $CustomChordsTable> {
  $$CustomChordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get frets =>
      $composableBuilder(column: $table.frets, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => ColumnOrderings(column));
}

class $$CustomChordsTableAnnotationComposer extends Composer<_$AppDatabase, $CustomChordsTable> {
  $$CustomChordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get frets =>
      $composableBuilder(column: $table.frets, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$CustomChordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomChordsTable,
          CustomChord,
          $$CustomChordsTableFilterComposer,
          $$CustomChordsTableOrderingComposer,
          $$CustomChordsTableAnnotationComposer,
          $$CustomChordsTableCreateCompanionBuilder,
          $$CustomChordsTableUpdateCompanionBuilder,
          (CustomChord, BaseReferences<_$AppDatabase, $CustomChordsTable, CustomChord>),
          CustomChord,
          PrefetchHooks Function()
        > {
  $$CustomChordsTableTableManager(_$AppDatabase db, $CustomChordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$CustomChordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$CustomChordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomChordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> frets = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomChordsCompanion(
                id: id,
                name: name,
                frets: frets,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String frets,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => CustomChordsCompanion.insert(
                id: id,
                name: name,
                frets: frets,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomChordsTable, CustomChord>(table),
                  BaseReferences<_$AppDatabase, $CustomChordsTable, CustomChord>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomChordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomChordsTable,
      CustomChord,
      $$CustomChordsTableFilterComposer,
      $$CustomChordsTableOrderingComposer,
      $$CustomChordsTableAnnotationComposer,
      $$CustomChordsTableCreateCompanionBuilder,
      $$CustomChordsTableUpdateCompanionBuilder,
      (CustomChord, BaseReferences<_$AppDatabase, $CustomChordsTable, CustomChord>),
      CustomChord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SettingsTableTableManager get settings => $$SettingsTableTableManager(_db, _db.settings);
  $$FavoriteChordsTableTableManager get favoriteChords =>
      $$FavoriteChordsTableTableManager(_db, _db.favoriteChords);
  $$CustomTuningsTableTableManager get customTunings =>
      $$CustomTuningsTableTableManager(_db, _db.customTunings);
  $$UserSongsTableTableManager get userSongs => $$UserSongsTableTableManager(_db, _db.userSongs);
  $$CustomChordsTableTableManager get customChords =>
      $$CustomChordsTableTableManager(_db, _db.customChords);
}
