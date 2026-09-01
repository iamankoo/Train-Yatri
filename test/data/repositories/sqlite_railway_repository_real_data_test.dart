// Tests against the REAL production assets/database/railway.db (built
// from the acquired dataset - see docs/RAILWAY_DATABASE.md for
// provenance), not the synthetic fixture used elsewhere. Every expected
// value here was read directly out of the built database / the
// generated build_data/ CSVs, never invented - e.g. the Howrah-New
// Delhi Rajdhani Express (12301) route below is exactly what
// `grep "^12301," build_data/route_stops.csv` produces.
//
// Skips itself (rather than failing) if assets/database/railway.db
// doesn't exist, so the rest of the suite still runs in an environment
// that hasn't built the production database.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';

import '../test_support/ffi_setup.dart';

const _dbPath = 'assets/database/railway.db';

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  final dbExists = File(_dbPath).existsSync();

  group('SqliteRailwayRepository against the real production database', () {
    late Database db;
    late SqliteRailwayRepository repository;

    setUpAll(() async {
      if (!dbExists) return;
      // Must be absolute - sqflite_common_ffi resolves a relative path
      // against its own .dart_tool/sqflite_common_ffi/databases/
      // directory, not this process's working directory.
      db = await databaseFactoryFfi.openDatabase(
        File(_dbPath).absolute.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      await configureRailwayConnection(db);
      repository = SqliteRailwayRepository(db);
    });

    tearDownAll(() async {
      if (dbExists) await db.close();
    });

    test('getStationByCode finds New Delhi (NDLS)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final station = await repository.getStationByCode('NDLS');
      expect(station, isNotNull);
      expect(station!.name, 'NEW DELHI');
      // Real coordinates from the source data, not invented.
      expect(station.latitude, closeTo(28.64, 0.1));
      expect(station.longitude, closeTo(77.22, 0.1));
    });

    test('searchStations finds New Delhi by name prefix', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final results = await repository.searchStations('new delhi');
      expect(results.any((s) => s.code == 'NDLS'), isTrue);
    });

    test(
      'getTrainByNumber finds the Howrah Rajdhani Express (12301)',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');
        final train = await repository.getTrainByNumber('12301');
        expect(train, isNotNull);
        expect(train!.number, '12301');
      },
    );

    test('searchTrains finds Rajdhani-named trains', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final results = await repository.searchTrains('kolkata rajd');
      expect(results, isNotEmpty);
      expect(results.any((t) => t.number == '12301'), isTrue);
    });

    test('getRoute(12301) matches the real Howrah -> New Delhi route, '
        'including the real overnight day_offset crossing between '
        'Gaya (day 0) and Mughal Sarai (day 1)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final train = (await repository.getTrainByNumber('12301'))!;
      final route = await repository.getRoute(train.trainId);

      expect(route, hasLength(8));
      expect(route.first.isOrigin, isTrue);
      expect(route.last.isTerminus, isTrue);

      // Real, published stop sequence of this train.
      final gaya = route[3];
      final mgs = route[4];
      expect(gaya.dayOffset, 0);
      expect(mgs.dayOffset, 1);
      expect(
        mgs.arrivalTime!.minutesSinceMidnight,
        lessThan(gaya.departureTime!.minutesSinceMidnight),
        reason:
            '00:45 (Mughal Sarai) is numerically before 22:37 (Gaya) as a '
            'clock time - only dayOffset shows it is actually later',
      );
    });

    test(
      'getRunningDays is honestly null - no calendar source was found',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');
        final train = (await repository.getTrainByNumber('12301'))!;
        final days = await repository.getRunningDays(train.trainId);
        expect(
          days,
          isNull,
          reason:
              'documented limitation: no legitimate bulk running-days source '
              'was found (see docs/RAILWAY_DATABASE.md) - this must stay '
              'null, never a guessed calendar',
        );
      },
    );

    test('getTrainsAtStation finds real trains stopping at NDLS', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final station = (await repository.getStationByCode('NDLS'))!;
      final trains = await repository.getTrainsAtStation(
        station.stationId,
        limit: 500,
      );
      expect(trains, isNotEmpty);
      expect(trains.any((t) => t.number == '12301'), isTrue);
    });

    test('getDatasetMetadata reports real, non-trivial coverage', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final metadata = await repository.getDatasetMetadata();
      expect(metadata.stationCount, greaterThan(8000));
      expect(metadata.trainCount, greaterThan(11000));
      expect(metadata.routeStopCount, greaterThan(180000));
      expect(metadata.datasetSource, contains('data.gov.in'));
    });

    test('station/train lookups use their indexes on the real, '
        'production-sized database (not a synthetic proxy)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      Future<String> planFor(String sql, List<Object?> args) async {
        final plan = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
        return plan.map((r) => r.values.join(' ')).join('\n').toUpperCase();
      }

      expect(
        await planFor('SELECT * FROM stations WHERE normalized_code = ?', [
          'NDLS',
        ]),
        contains('USING INDEX'),
      );
      expect(
        await planFor('SELECT * FROM trains WHERE normalized_number = ?', [
          '12301',
        ]),
        contains('USING INDEX'),
      );
      expect(
        await planFor(
          'SELECT * FROM route_stops WHERE train_id = ? ORDER BY stop_sequence',
          [1],
        ),
        contains('USING INDEX'),
      );
    });

    test('200 real indexed station lookups against the full 8k+ station '
        'table stay fast (no accidental full scan)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final codes = (await db.query(
        'stations',
        columns: ['code'],
        limit: 200,
      )).map((r) => r['code'] as String).toList();

      final stopwatch = Stopwatch()..start();
      for (final code in codes) {
        await repository.getStationByCode(code);
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(3000));
    });
  });
}
