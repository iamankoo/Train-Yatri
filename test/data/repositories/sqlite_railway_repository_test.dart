// Synthetic test-only railway data - not real stations/trains.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/entities/data_confidence.dart';

import '../test_support/ffi_setup.dart';

const _stationsCsv = '''
code,name,city,state,latitude,longitude
NDA,New Delta Alpha,Delta City,Delta State,28.6,77.2
MCB,Mumbai Central Beta,Beta City,Beta State,19.0,72.8
JXN,Junction Gamma,,,,
''';

const _trainsCsv = '''
number,name,is_active
00101T,Test Overnight Express,1
00102T,Test Day Express,1
''';

// 00101T departs NDA at 23:50 day 0, arrives MCB at 00:10 day 1 - a
// genuine midnight crossing, to prove dayOffset (not raw clock time)
// determines chronological order.
const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
00101T,1,NDA,,23:50,0,0
00101T,2,JXN,23:59,23:59,0,50
00101T,3,MCB,00:10,,1,300
00102T,1,NDA,,09:00,0,0
00102T,2,MCB,15:00,,0,300
''';

const _runningDaysCsv = '''
train_number,monday,tuesday,wednesday,thursday,friday,saturday,sunday,confidence
00101T,1,1,1,1,1,1,1,confirmed
''';

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  late Database db;
  late SqliteRailwayRepository repository;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await configureRailwayConnection(db);
    for (final statement in schema.schemaStatements) {
      await db.execute(statement);
    }
    await RailwayImporter(db).import(
      stations: parseCsvSource(_stationsCsv),
      trains: parseCsvSource(_trainsCsv),
      routeStops: parseCsvSource(_routeStopsCsv),
      runningDays: parseCsvSource(_runningDaysCsv),
      datasetSource: 'synthetic test fixture',
      datasetVersion: 'test-1',
    );
    repository = SqliteRailwayRepository(db);
  });

  tearDown(() => db.close());

  group('searchStations', () {
    test('matches by name, case-insensitively', () async {
      final results = await repository.searchStations('mumbai');
      expect(results, hasLength(1));
      expect(results.first.code, 'MCB');
    });

    test('matches by code prefix, case-insensitively', () async {
      final results = await repository.searchStations('nd');
      expect(results, hasLength(1));
      expect(results.first.code, 'NDA');
    });

    test('returns no results for a query matching nothing', () async {
      expect(await repository.searchStations('zzzznotfound'), isEmpty);
    });

    test(
      'does not invent city/state when the source left them blank',
      () async {
        final results = await repository.searchStations('junction');
        expect(results.single.city, isNull);
        expect(results.single.state, isNull);
      },
    );
  });

  group('getStationByCode', () {
    test('exact match, case-insensitive', () async {
      final station = await repository.getStationByCode('nda');
      expect(station, isNotNull);
      expect(station!.name, 'New Delta Alpha');
    });

    test('returns null for an unknown code', () async {
      expect(await repository.getStationByCode('ZZZ'), isNull);
    });
  });

  group('searchTrains / getTrainByNumber', () {
    test('searchTrains matches by name prefix (search is prefix-based, '
        'by design, so the query stays index-friendly)', () async {
      final results = await repository.searchTrains('Test Overnight');
      expect(results.single.number, '00101T');
    });

    test('getTrainByNumber returns null for an unknown number', () async {
      expect(await repository.getTrainByNumber('99999X'), isNull);
    });
  });

  group('getRoute', () {
    test('returns stops ordered by stop_sequence', () async {
      final trainId = (await repository.getTrainByNumber('00101T'))!.trainId;
      final route = await repository.getRoute(trainId);
      expect(route.map((s) => s.stopSequence), [1, 2, 3]);
    });

    test('day_offset correctly orders a stop after midnight', () async {
      final trainId = (await repository.getTrainByNumber('00101T'))!.trainId;
      final route = await repository.getRoute(trainId);

      final origin = route[0];
      final finalStop = route[2];

      // The final stop's clock time (00:10) is numerically earlier than
      // the origin's departure (23:50) - only dayOffset disambiguates
      // that it is actually a day later, i.e. chronologically after.
      expect(
        origin.departureTime!.minutesSinceMidnight,
        greaterThan(finalStop.arrivalTime!.minutesSinceMidnight),
      );
      expect(finalStop.dayOffset, greaterThan(origin.dayOffset));
    });

    test(
      'origin stop has no arrival time, terminus has no departure time',
      () async {
        final trainId = (await repository.getTrainByNumber('00101T'))!.trainId;
        final route = await repository.getRoute(trainId);
        expect(route.first.isOrigin, isTrue);
        expect(route.last.isTerminus, isTrue);
      },
    );

    test('empty list for a train with no recorded route', () async {
      expect(await repository.getRoute(999999), isEmpty);
    });
  });

  group('getTrainsAtStation', () {
    test('finds every train that stops at a station', () async {
      final station = (await repository.getStationByCode('MCB'))!;
      final trains = await repository.getTrainsAtStation(station.stationId);
      expect(trains.map((t) => t.number), containsAll(['00101T', '00102T']));
    });
  });

  group('getRunningDays', () {
    test(
      'returns confirmed running days when the source provided them',
      () async {
        final trainId = (await repository.getTrainByNumber('00101T'))!.trainId;
        final days = await repository.getRunningDays(trainId);
        expect(days!.confidence, DataConfidence.confirmed);
        expect(days.monday, isTrue);
      },
    );

    test(
      'is unknown-confidence, not confirmed, when the source did not say',
      () async {
        final trainId = (await repository.getTrainByNumber('00102T'))!.trainId;
        final days = await repository.getRunningDays(trainId);
        expect(
          days,
          isNull,
          reason: 'no running_days row was imported for 00102T at all',
        );
      },
    );
  });

  group('getDatasetMetadata', () {
    test('reflects the actual import, not a hard-coded value', () async {
      final metadata = await repository.getDatasetMetadata();
      expect(metadata.datasetSource, 'synthetic test fixture');
      expect(metadata.datasetVersion, 'test-1');
      expect(metadata.stationCount, 3);
      expect(metadata.trainCount, 2);
    });
  });
}
