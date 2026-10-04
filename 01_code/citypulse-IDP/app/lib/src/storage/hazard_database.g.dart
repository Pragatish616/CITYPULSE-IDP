// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hazard_database.dart';

// ignore_for_file: type=lint
class $ObservationsTable extends Observations
    with TableInfo<$ObservationsTable, ObservationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hazardClassMeta = const VerificationMeta(
    'hazardClass',
  );
  @override
  late final GeneratedColumn<String> hazardClass = GeneratedColumn<String>(
    'hazard_class',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _polarityMeta = const VerificationMeta(
    'polarity',
  );
  @override
  late final GeneratedColumn<int> polarity = GeneratedColumn<int>(
    'polarity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  @override
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> receivedAt = GeneratedColumn<DateTime>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceClassMeta = const VerificationMeta(
    'sourceClass',
  );
  @override
  late final GeneratedColumn<String> sourceClass = GeneratedColumn<String>(
    'source_class',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _intensityJsonMeta = const VerificationMeta(
    'intensityJson',
  );
  @override
  late final GeneratedColumn<String> intensityJson = GeneratedColumn<String>(
    'intensity_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _precisionStateMeta = const VerificationMeta(
    'precisionState',
  );
  @override
  late final GeneratedColumn<String> precisionState = GeneratedColumn<String>(
    'precision_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('exact'),
  );
  static const VerificationMeta _coarsenedAtMeta = const VerificationMeta(
    'coarsenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> coarsenedAt = GeneratedColumn<DateTime>(
    'coarsened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hazardClass,
    polarity,
    lat,
    lon,
    accuracyM,
    observedAt,
    receivedAt,
    sourceClass,
    sourceId,
    intensityJson,
    rawJson,
    precisionState,
    coarsenedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObservationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hazard_class')) {
      context.handle(
        _hazardClassMeta,
        hazardClass.isAcceptableOrUnknown(
          data['hazard_class']!,
          _hazardClassMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hazardClassMeta);
    }
    if (data.containsKey('polarity')) {
      context.handle(
        _polarityMeta,
        polarity.isAcceptableOrUnknown(data['polarity']!, _polarityMeta),
      );
    } else if (isInserting) {
      context.missing(_polarityMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    } else if (isInserting) {
      context.missing(_accuracyMMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    if (data.containsKey('source_class')) {
      context.handle(
        _sourceClassMeta,
        sourceClass.isAcceptableOrUnknown(
          data['source_class']!,
          _sourceClassMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceClassMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('intensity_json')) {
      context.handle(
        _intensityJsonMeta,
        intensityJson.isAcceptableOrUnknown(
          data['intensity_json']!,
          _intensityJsonMeta,
        ),
      );
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    }
    if (data.containsKey('precision_state')) {
      context.handle(
        _precisionStateMeta,
        precisionState.isAcceptableOrUnknown(
          data['precision_state']!,
          _precisionStateMeta,
        ),
      );
    }
    if (data.containsKey('coarsened_at')) {
      context.handle(
        _coarsenedAtMeta,
        coarsenedAt.isAcceptableOrUnknown(
          data['coarsened_at']!,
          _coarsenedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ObservationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObservationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hazardClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hazard_class'],
      )!,
      polarity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}polarity'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}received_at'],
      )!,
      sourceClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_class'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      intensityJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intensity_json'],
      ),
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      ),
      precisionState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}precision_state'],
      )!,
      coarsenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}coarsened_at'],
      ),
    );
  }

  @override
  $ObservationsTable createAlias(String alias) {
    return $ObservationsTable(attachedDatabase, alias);
  }
}

class ObservationRow extends DataClass implements Insertable<ObservationRow> {
  /// UUIDv7, client-generated (`docs/CONTRACTS.md` §1 header note). A plain
  /// `TEXT PRIMARY KEY` -- note this means SQLite does *not* alias this
  /// column to the table's `rowid` (only an `INTEGER PRIMARY KEY` column
  /// does that), so `Observations` keeps its own separate implicit integer
  /// `rowid`. That separate `rowid` is exactly what pairs each row with its
  /// `observations_rtree` shadow row (`HazardDatabase`'s doc comment).
  final String id;
  final String hazardClass;

  /// `+1` present, `-1` absent/cleared (`docs/CONTRACTS.md` §1).
  final int polarity;
  final double lat;
  final double lon;
  final double accuracyM;
  final DateTime observedAt;
  final DateTime receivedAt;
  final String sourceClass;
  final String sourceId;

  /// `intensity` is class-specific and optional (`docs/CONTRACTS.md` §1) --
  /// stored as a JSON string rather than one column per possible shape.
  final String? intensityJson;

  /// The raw source payload, if retained -- same reasoning as
  /// [intensityJson].
  final String? rawJson;

  /// `exact` | `coarsened` (ADR-010).
  final String precisionState;
  final DateTime? coarsenedAt;
  const ObservationRow({
    required this.id,
    required this.hazardClass,
    required this.polarity,
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.observedAt,
    required this.receivedAt,
    required this.sourceClass,
    required this.sourceId,
    this.intensityJson,
    this.rawJson,
    required this.precisionState,
    this.coarsenedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hazard_class'] = Variable<String>(hazardClass);
    map['polarity'] = Variable<int>(polarity);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['accuracy_m'] = Variable<double>(accuracyM);
    map['observed_at'] = Variable<DateTime>(observedAt);
    map['received_at'] = Variable<DateTime>(receivedAt);
    map['source_class'] = Variable<String>(sourceClass);
    map['source_id'] = Variable<String>(sourceId);
    if (!nullToAbsent || intensityJson != null) {
      map['intensity_json'] = Variable<String>(intensityJson);
    }
    if (!nullToAbsent || rawJson != null) {
      map['raw_json'] = Variable<String>(rawJson);
    }
    map['precision_state'] = Variable<String>(precisionState);
    if (!nullToAbsent || coarsenedAt != null) {
      map['coarsened_at'] = Variable<DateTime>(coarsenedAt);
    }
    return map;
  }

  ObservationsCompanion toCompanion(bool nullToAbsent) {
    return ObservationsCompanion(
      id: Value(id),
      hazardClass: Value(hazardClass),
      polarity: Value(polarity),
      lat: Value(lat),
      lon: Value(lon),
      accuracyM: Value(accuracyM),
      observedAt: Value(observedAt),
      receivedAt: Value(receivedAt),
      sourceClass: Value(sourceClass),
      sourceId: Value(sourceId),
      intensityJson: intensityJson == null && nullToAbsent
          ? const Value.absent()
          : Value(intensityJson),
      rawJson: rawJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rawJson),
      precisionState: Value(precisionState),
      coarsenedAt: coarsenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(coarsenedAt),
    );
  }

  factory ObservationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObservationRow(
      id: serializer.fromJson<String>(json['id']),
      hazardClass: serializer.fromJson<String>(json['hazardClass']),
      polarity: serializer.fromJson<int>(json['polarity']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      accuracyM: serializer.fromJson<double>(json['accuracyM']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      receivedAt: serializer.fromJson<DateTime>(json['receivedAt']),
      sourceClass: serializer.fromJson<String>(json['sourceClass']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      intensityJson: serializer.fromJson<String?>(json['intensityJson']),
      rawJson: serializer.fromJson<String?>(json['rawJson']),
      precisionState: serializer.fromJson<String>(json['precisionState']),
      coarsenedAt: serializer.fromJson<DateTime?>(json['coarsenedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hazardClass': serializer.toJson<String>(hazardClass),
      'polarity': serializer.toJson<int>(polarity),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'accuracyM': serializer.toJson<double>(accuracyM),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'receivedAt': serializer.toJson<DateTime>(receivedAt),
      'sourceClass': serializer.toJson<String>(sourceClass),
      'sourceId': serializer.toJson<String>(sourceId),
      'intensityJson': serializer.toJson<String?>(intensityJson),
      'rawJson': serializer.toJson<String?>(rawJson),
      'precisionState': serializer.toJson<String>(precisionState),
      'coarsenedAt': serializer.toJson<DateTime?>(coarsenedAt),
    };
  }

  ObservationRow copyWith({
    String? id,
    String? hazardClass,
    int? polarity,
    double? lat,
    double? lon,
    double? accuracyM,
    DateTime? observedAt,
    DateTime? receivedAt,
    String? sourceClass,
    String? sourceId,
    Value<String?> intensityJson = const Value.absent(),
    Value<String?> rawJson = const Value.absent(),
    String? precisionState,
    Value<DateTime?> coarsenedAt = const Value.absent(),
  }) => ObservationRow(
    id: id ?? this.id,
    hazardClass: hazardClass ?? this.hazardClass,
    polarity: polarity ?? this.polarity,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    accuracyM: accuracyM ?? this.accuracyM,
    observedAt: observedAt ?? this.observedAt,
    receivedAt: receivedAt ?? this.receivedAt,
    sourceClass: sourceClass ?? this.sourceClass,
    sourceId: sourceId ?? this.sourceId,
    intensityJson: intensityJson.present
        ? intensityJson.value
        : this.intensityJson,
    rawJson: rawJson.present ? rawJson.value : this.rawJson,
    precisionState: precisionState ?? this.precisionState,
    coarsenedAt: coarsenedAt.present ? coarsenedAt.value : this.coarsenedAt,
  );
  ObservationRow copyWithCompanion(ObservationsCompanion data) {
    return ObservationRow(
      id: data.id.present ? data.id.value : this.id,
      hazardClass: data.hazardClass.present
          ? data.hazardClass.value
          : this.hazardClass,
      polarity: data.polarity.present ? data.polarity.value : this.polarity,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      sourceClass: data.sourceClass.present
          ? data.sourceClass.value
          : this.sourceClass,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      intensityJson: data.intensityJson.present
          ? data.intensityJson.value
          : this.intensityJson,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      precisionState: data.precisionState.present
          ? data.precisionState.value
          : this.precisionState,
      coarsenedAt: data.coarsenedAt.present
          ? data.coarsenedAt.value
          : this.coarsenedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObservationRow(')
          ..write('id: $id, ')
          ..write('hazardClass: $hazardClass, ')
          ..write('polarity: $polarity, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('observedAt: $observedAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sourceClass: $sourceClass, ')
          ..write('sourceId: $sourceId, ')
          ..write('intensityJson: $intensityJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('precisionState: $precisionState, ')
          ..write('coarsenedAt: $coarsenedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hazardClass,
    polarity,
    lat,
    lon,
    accuracyM,
    observedAt,
    receivedAt,
    sourceClass,
    sourceId,
    intensityJson,
    rawJson,
    precisionState,
    coarsenedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObservationRow &&
          other.id == this.id &&
          other.hazardClass == this.hazardClass &&
          other.polarity == this.polarity &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.accuracyM == this.accuracyM &&
          other.observedAt == this.observedAt &&
          other.receivedAt == this.receivedAt &&
          other.sourceClass == this.sourceClass &&
          other.sourceId == this.sourceId &&
          other.intensityJson == this.intensityJson &&
          other.rawJson == this.rawJson &&
          other.precisionState == this.precisionState &&
          other.coarsenedAt == this.coarsenedAt);
}

class ObservationsCompanion extends UpdateCompanion<ObservationRow> {
  final Value<String> id;
  final Value<String> hazardClass;
  final Value<int> polarity;
  final Value<double> lat;
  final Value<double> lon;
  final Value<double> accuracyM;
  final Value<DateTime> observedAt;
  final Value<DateTime> receivedAt;
  final Value<String> sourceClass;
  final Value<String> sourceId;
  final Value<String?> intensityJson;
  final Value<String?> rawJson;
  final Value<String> precisionState;
  final Value<DateTime?> coarsenedAt;
  final Value<int> rowid;
  const ObservationsCompanion({
    this.id = const Value.absent(),
    this.hazardClass = const Value.absent(),
    this.polarity = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.sourceClass = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.intensityJson = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.precisionState = const Value.absent(),
    this.coarsenedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationsCompanion.insert({
    required String id,
    required String hazardClass,
    required int polarity,
    required double lat,
    required double lon,
    required double accuracyM,
    required DateTime observedAt,
    required DateTime receivedAt,
    required String sourceClass,
    required String sourceId,
    this.intensityJson = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.precisionState = const Value.absent(),
    this.coarsenedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hazardClass = Value(hazardClass),
       polarity = Value(polarity),
       lat = Value(lat),
       lon = Value(lon),
       accuracyM = Value(accuracyM),
       observedAt = Value(observedAt),
       receivedAt = Value(receivedAt),
       sourceClass = Value(sourceClass),
       sourceId = Value(sourceId);
  static Insertable<ObservationRow> custom({
    Expression<String>? id,
    Expression<String>? hazardClass,
    Expression<int>? polarity,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? accuracyM,
    Expression<DateTime>? observedAt,
    Expression<DateTime>? receivedAt,
    Expression<String>? sourceClass,
    Expression<String>? sourceId,
    Expression<String>? intensityJson,
    Expression<String>? rawJson,
    Expression<String>? precisionState,
    Expression<DateTime>? coarsenedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hazardClass != null) 'hazard_class': hazardClass,
      if (polarity != null) 'polarity': polarity,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (observedAt != null) 'observed_at': observedAt,
      if (receivedAt != null) 'received_at': receivedAt,
      if (sourceClass != null) 'source_class': sourceClass,
      if (sourceId != null) 'source_id': sourceId,
      if (intensityJson != null) 'intensity_json': intensityJson,
      if (rawJson != null) 'raw_json': rawJson,
      if (precisionState != null) 'precision_state': precisionState,
      if (coarsenedAt != null) 'coarsened_at': coarsenedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? hazardClass,
    Value<int>? polarity,
    Value<double>? lat,
    Value<double>? lon,
    Value<double>? accuracyM,
    Value<DateTime>? observedAt,
    Value<DateTime>? receivedAt,
    Value<String>? sourceClass,
    Value<String>? sourceId,
    Value<String?>? intensityJson,
    Value<String?>? rawJson,
    Value<String>? precisionState,
    Value<DateTime?>? coarsenedAt,
    Value<int>? rowid,
  }) {
    return ObservationsCompanion(
      id: id ?? this.id,
      hazardClass: hazardClass ?? this.hazardClass,
      polarity: polarity ?? this.polarity,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      accuracyM: accuracyM ?? this.accuracyM,
      observedAt: observedAt ?? this.observedAt,
      receivedAt: receivedAt ?? this.receivedAt,
      sourceClass: sourceClass ?? this.sourceClass,
      sourceId: sourceId ?? this.sourceId,
      intensityJson: intensityJson ?? this.intensityJson,
      rawJson: rawJson ?? this.rawJson,
      precisionState: precisionState ?? this.precisionState,
      coarsenedAt: coarsenedAt ?? this.coarsenedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hazardClass.present) {
      map['hazard_class'] = Variable<String>(hazardClass.value);
    }
    if (polarity.present) {
      map['polarity'] = Variable<int>(polarity.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<DateTime>(receivedAt.value);
    }
    if (sourceClass.present) {
      map['source_class'] = Variable<String>(sourceClass.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (intensityJson.present) {
      map['intensity_json'] = Variable<String>(intensityJson.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (precisionState.present) {
      map['precision_state'] = Variable<String>(precisionState.value);
    }
    if (coarsenedAt.present) {
      map['coarsened_at'] = Variable<DateTime>(coarsenedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationsCompanion(')
          ..write('id: $id, ')
          ..write('hazardClass: $hazardClass, ')
          ..write('polarity: $polarity, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('observedAt: $observedAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('sourceClass: $sourceClass, ')
          ..write('sourceId: $sourceId, ')
          ..write('intensityJson: $intensityJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('precisionState: $precisionState, ')
          ..write('coarsenedAt: $coarsenedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _observationIdMeta = const VerificationMeta(
    'observationId',
  );
  @override
  late final GeneratedColumn<String> observationId = GeneratedColumn<String>(
    'observation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncAttemptsMeta = const VerificationMeta(
    'syncAttempts',
  );
  @override
  late final GeneratedColumn<int> syncAttempts = GeneratedColumn<int>(
    'sync_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    observationId,
    createdAt,
    syncedAt,
    syncAttempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('observation_id')) {
      context.handle(
        _observationIdMeta,
        observationId.isAcceptableOrUnknown(
          data['observation_id']!,
          _observationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observationIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('sync_attempts')) {
      context.handle(
        _syncAttemptsMeta,
        syncAttempts.isAcceptableOrUnknown(
          data['sync_attempts']!,
          _syncAttemptsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {observationId};
  @override
  OutboxEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntryRow(
      observationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observation_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      ),
      syncAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_attempts'],
      )!,
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntryRow extends DataClass implements Insertable<OutboxEntryRow> {
  /// References `Observations.id`. One outbox entry per observation, so this
  /// doubles as the outbox row's own primary key.
  final String observationId;
  final DateTime createdAt;

  /// `null` while pending; set once the server has acknowledged receipt.
  final DateTime? syncedAt;
  final int syncAttempts;
  const OutboxEntryRow({
    required this.observationId,
    required this.createdAt,
    this.syncedAt,
    required this.syncAttempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['observation_id'] = Variable<String>(observationId);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<DateTime>(syncedAt);
    }
    map['sync_attempts'] = Variable<int>(syncAttempts);
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      observationId: Value(observationId),
      createdAt: Value(createdAt),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      syncAttempts: Value(syncAttempts),
    );
  }

  factory OutboxEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntryRow(
      observationId: serializer.fromJson<String>(json['observationId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      syncedAt: serializer.fromJson<DateTime?>(json['syncedAt']),
      syncAttempts: serializer.fromJson<int>(json['syncAttempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'observationId': serializer.toJson<String>(observationId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'syncedAt': serializer.toJson<DateTime?>(syncedAt),
      'syncAttempts': serializer.toJson<int>(syncAttempts),
    };
  }

  OutboxEntryRow copyWith({
    String? observationId,
    DateTime? createdAt,
    Value<DateTime?> syncedAt = const Value.absent(),
    int? syncAttempts,
  }) => OutboxEntryRow(
    observationId: observationId ?? this.observationId,
    createdAt: createdAt ?? this.createdAt,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    syncAttempts: syncAttempts ?? this.syncAttempts,
  );
  OutboxEntryRow copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntryRow(
      observationId: data.observationId.present
          ? data.observationId.value
          : this.observationId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      syncAttempts: data.syncAttempts.present
          ? data.syncAttempts.value
          : this.syncAttempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntryRow(')
          ..write('observationId: $observationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('syncAttempts: $syncAttempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(observationId, createdAt, syncedAt, syncAttempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntryRow &&
          other.observationId == this.observationId &&
          other.createdAt == this.createdAt &&
          other.syncedAt == this.syncedAt &&
          other.syncAttempts == this.syncAttempts);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntryRow> {
  final Value<String> observationId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> syncedAt;
  final Value<int> syncAttempts;
  final Value<int> rowid;
  const OutboxEntriesCompanion({
    this.observationId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.syncAttempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    required String observationId,
    this.createdAt = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.syncAttempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : observationId = Value(observationId);
  static Insertable<OutboxEntryRow> custom({
    Expression<String>? observationId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? syncedAt,
    Expression<int>? syncAttempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (observationId != null) 'observation_id': observationId,
      if (createdAt != null) 'created_at': createdAt,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (syncAttempts != null) 'sync_attempts': syncAttempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxEntriesCompanion copyWith({
    Value<String>? observationId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? syncedAt,
    Value<int>? syncAttempts,
    Value<int>? rowid,
  }) {
    return OutboxEntriesCompanion(
      observationId: observationId ?? this.observationId,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (observationId.present) {
      map['observation_id'] = Variable<String>(observationId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (syncAttempts.present) {
      map['sync_attempts'] = Variable<int>(syncAttempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('observationId: $observationId, ')
          ..write('createdAt: $createdAt, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('syncAttempts: $syncAttempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$HazardDatabase extends GeneratedDatabase {
  _$HazardDatabase(QueryExecutor e) : super(e);
  $HazardDatabaseManager get managers => $HazardDatabaseManager(this);
  late final $ObservationsTable observations = $ObservationsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    observations,
    outboxEntries,
  ];
}

typedef $$ObservationsTableCreateCompanionBuilder =
    ObservationsCompanion Function({
      required String id,
      required String hazardClass,
      required int polarity,
      required double lat,
      required double lon,
      required double accuracyM,
      required DateTime observedAt,
      required DateTime receivedAt,
      required String sourceClass,
      required String sourceId,
      Value<String?> intensityJson,
      Value<String?> rawJson,
      Value<String> precisionState,
      Value<DateTime?> coarsenedAt,
      Value<int> rowid,
    });
typedef $$ObservationsTableUpdateCompanionBuilder =
    ObservationsCompanion Function({
      Value<String> id,
      Value<String> hazardClass,
      Value<int> polarity,
      Value<double> lat,
      Value<double> lon,
      Value<double> accuracyM,
      Value<DateTime> observedAt,
      Value<DateTime> receivedAt,
      Value<String> sourceClass,
      Value<String> sourceId,
      Value<String?> intensityJson,
      Value<String?> rawJson,
      Value<String> precisionState,
      Value<DateTime?> coarsenedAt,
      Value<int> rowid,
    });

class $$ObservationsTableFilterComposer
    extends Composer<_$HazardDatabase, $ObservationsTable> {
  $$ObservationsTableFilterComposer({
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

  ColumnFilters<String> get hazardClass => $composableBuilder(
    column: $table.hazardClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get polarity => $composableBuilder(
    column: $table.polarity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceClass => $composableBuilder(
    column: $table.sourceClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intensityJson => $composableBuilder(
    column: $table.intensityJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get precisionState => $composableBuilder(
    column: $table.precisionState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get coarsenedAt => $composableBuilder(
    column: $table.coarsenedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ObservationsTableOrderingComposer
    extends Composer<_$HazardDatabase, $ObservationsTable> {
  $$ObservationsTableOrderingComposer({
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

  ColumnOrderings<String> get hazardClass => $composableBuilder(
    column: $table.hazardClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get polarity => $composableBuilder(
    column: $table.polarity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lon => $composableBuilder(
    column: $table.lon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceClass => $composableBuilder(
    column: $table.sourceClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intensityJson => $composableBuilder(
    column: $table.intensityJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get precisionState => $composableBuilder(
    column: $table.precisionState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get coarsenedAt => $composableBuilder(
    column: $table.coarsenedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ObservationsTableAnnotationComposer
    extends Composer<_$HazardDatabase, $ObservationsTable> {
  $$ObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hazardClass => $composableBuilder(
    column: $table.hazardClass,
    builder: (column) => column,
  );

  GeneratedColumn<int> get polarity =>
      $composableBuilder(column: $table.polarity, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lon =>
      $composableBuilder(column: $table.lon, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceClass => $composableBuilder(
    column: $table.sourceClass,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get intensityJson => $composableBuilder(
    column: $table.intensityJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<String> get precisionState => $composableBuilder(
    column: $table.precisionState,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get coarsenedAt => $composableBuilder(
    column: $table.coarsenedAt,
    builder: (column) => column,
  );
}

class $$ObservationsTableTableManager
    extends
        RootTableManager<
          _$HazardDatabase,
          $ObservationsTable,
          ObservationRow,
          $$ObservationsTableFilterComposer,
          $$ObservationsTableOrderingComposer,
          $$ObservationsTableAnnotationComposer,
          $$ObservationsTableCreateCompanionBuilder,
          $$ObservationsTableUpdateCompanionBuilder,
          (
            ObservationRow,
            BaseReferences<
              _$HazardDatabase,
              $ObservationsTable,
              ObservationRow
            >,
          ),
          ObservationRow,
          PrefetchHooks Function()
        > {
  $$ObservationsTableTableManager(_$HazardDatabase db, $ObservationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hazardClass = const Value.absent(),
                Value<int> polarity = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lon = const Value.absent(),
                Value<double> accuracyM = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<DateTime> receivedAt = const Value.absent(),
                Value<String> sourceClass = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String?> intensityJson = const Value.absent(),
                Value<String?> rawJson = const Value.absent(),
                Value<String> precisionState = const Value.absent(),
                Value<DateTime?> coarsenedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion(
                id: id,
                hazardClass: hazardClass,
                polarity: polarity,
                lat: lat,
                lon: lon,
                accuracyM: accuracyM,
                observedAt: observedAt,
                receivedAt: receivedAt,
                sourceClass: sourceClass,
                sourceId: sourceId,
                intensityJson: intensityJson,
                rawJson: rawJson,
                precisionState: precisionState,
                coarsenedAt: coarsenedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hazardClass,
                required int polarity,
                required double lat,
                required double lon,
                required double accuracyM,
                required DateTime observedAt,
                required DateTime receivedAt,
                required String sourceClass,
                required String sourceId,
                Value<String?> intensityJson = const Value.absent(),
                Value<String?> rawJson = const Value.absent(),
                Value<String> precisionState = const Value.absent(),
                Value<DateTime?> coarsenedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion.insert(
                id: id,
                hazardClass: hazardClass,
                polarity: polarity,
                lat: lat,
                lon: lon,
                accuracyM: accuracyM,
                observedAt: observedAt,
                receivedAt: receivedAt,
                sourceClass: sourceClass,
                sourceId: sourceId,
                intensityJson: intensityJson,
                rawJson: rawJson,
                precisionState: precisionState,
                coarsenedAt: coarsenedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$HazardDatabase,
      $ObservationsTable,
      ObservationRow,
      $$ObservationsTableFilterComposer,
      $$ObservationsTableOrderingComposer,
      $$ObservationsTableAnnotationComposer,
      $$ObservationsTableCreateCompanionBuilder,
      $$ObservationsTableUpdateCompanionBuilder,
      (
        ObservationRow,
        BaseReferences<_$HazardDatabase, $ObservationsTable, ObservationRow>,
      ),
      ObservationRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxEntriesTableCreateCompanionBuilder =
    OutboxEntriesCompanion Function({
      required String observationId,
      Value<DateTime> createdAt,
      Value<DateTime?> syncedAt,
      Value<int> syncAttempts,
      Value<int> rowid,
    });
typedef $$OutboxEntriesTableUpdateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<String> observationId,
      Value<DateTime> createdAt,
      Value<DateTime?> syncedAt,
      Value<int> syncAttempts,
      Value<int> rowid,
    });

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$HazardDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get observationId => $composableBuilder(
    column: $table.observationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$HazardDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get observationId => $composableBuilder(
    column: $table.observationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$HazardDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get observationId => $composableBuilder(
    column: $table.observationId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<int> get syncAttempts => $composableBuilder(
    column: $table.syncAttempts,
    builder: (column) => column,
  );
}

class $$OutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$HazardDatabase,
          $OutboxEntriesTable,
          OutboxEntryRow,
          $$OutboxEntriesTableFilterComposer,
          $$OutboxEntriesTableOrderingComposer,
          $$OutboxEntriesTableAnnotationComposer,
          $$OutboxEntriesTableCreateCompanionBuilder,
          $$OutboxEntriesTableUpdateCompanionBuilder,
          (
            OutboxEntryRow,
            BaseReferences<
              _$HazardDatabase,
              $OutboxEntriesTable,
              OutboxEntryRow
            >,
          ),
          OutboxEntryRow,
          PrefetchHooks Function()
        > {
  $$OutboxEntriesTableTableManager(
    _$HazardDatabase db,
    $OutboxEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> observationId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> syncAttempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxEntriesCompanion(
                observationId: observationId,
                createdAt: createdAt,
                syncedAt: syncedAt,
                syncAttempts: syncAttempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String observationId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> syncedAt = const Value.absent(),
                Value<int> syncAttempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxEntriesCompanion.insert(
                observationId: observationId,
                createdAt: createdAt,
                syncedAt: syncedAt,
                syncAttempts: syncAttempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$HazardDatabase,
      $OutboxEntriesTable,
      OutboxEntryRow,
      $$OutboxEntriesTableFilterComposer,
      $$OutboxEntriesTableOrderingComposer,
      $$OutboxEntriesTableAnnotationComposer,
      $$OutboxEntriesTableCreateCompanionBuilder,
      $$OutboxEntriesTableUpdateCompanionBuilder,
      (
        OutboxEntryRow,
        BaseReferences<_$HazardDatabase, $OutboxEntriesTable, OutboxEntryRow>,
      ),
      OutboxEntryRow,
      PrefetchHooks Function()
    >;

class $HazardDatabaseManager {
  final _$HazardDatabase _db;
  $HazardDatabaseManager(this._db);
  $$ObservationsTableTableManager get observations =>
      $$ObservationsTableTableManager(_db, _db.observations);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
}
