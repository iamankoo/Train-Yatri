// Tests against the REAL production assets/database/railway.db (built
// from the acquired dataset - see docs/RAILWAY_DATABASE.md for
// provenance), not the synthetic fixture used elsewhere. Every expected
// value here was read directly out of the built database / the
// generated build_data/ CSVs, never invented - e.g. the Howrah
// Rajdhani Express (12301) route below is exactly what
// `grep "^12301," build_data/tag2026_final/route_stops.csv` produces.
//
// Rebuilt for Block 6's 2026 dataset replacement (docs/RAILWAY_DATABASE.md
// "Block 6"): station/train counts and specific example trains changed
// along with the dataset itself. 12301's recorded route below reaches
// Ghaziabad Jn. (GZB), not New Delhi - a known, documented Block 6
// extraction-completeness limitation (see that doc), not a fabricated
// stop; the test asserts exactly what the database actually contains.
//
// Skips itself (rather than failing) if assets/database/railway.db
// doesn't exist, so the rest of the suite still runs in an environment
// that hasn't built the production database.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/entities/data_confidence.dart';

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

    test('getRoute(12301) matches the real Howrah Rajdhani route, '
        'including the real overnight day_offset crossing between '
        'Gaya (day 0) and Prayagraj (day 1)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final train = (await repository.getTrainByNumber('12301'))!;
      final route = await repository.getRoute(train.trainId);

      expect(route, hasLength(13));
      expect(route.first.isOrigin, isTrue);

      // Real, published stop sequence of this train.
      final gaya = route[3];
      final prayagraj = route[7];
      expect(gaya.dayOffset, 0);
      expect(prayagraj.dayOffset, 1);
      expect(
        prayagraj.arrivalTime!.minutesSinceMidnight,
        lessThan(gaya.departureTime!.minutesSinceMidnight),
        reason:
            '02:43 (Prayagraj) is numerically before 22:35 (Gaya) as a '
            'clock time - only dayOffset shows it is actually later',
      );
    });

    test('getRouteWithStations(12301) - Block 4\'s Train Details data source '
        '- carries real station names through the join and preserves the '
        'same overnight day_offset crossing as getRoute', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final train = (await repository.getTrainByNumber('12301'))!;
      final route = await repository.getRouteWithStations(train.trainId);

      expect(route, hasLength(13));
      expect(route.first.station.code, 'HWH');

      final gaya = route[3];
      final prayagraj = route[7];
      expect(gaya.station.code, 'GAYA');
      expect(prayagraj.station.code, 'PRYJ');
      expect(gaya.stop.dayOffset, 0);
      expect(prayagraj.stop.dayOffset, 1);
    });

    test('getRouteWithStations(12951) - the Tejas Rajdhani, another real '
        'overnight train - crosses from day 0 to day 1 at Ratlam Jn', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final train = (await repository.getTrainByNumber('12951'))!;
      final route = await repository.getRouteWithStations(train.trainId);

      expect(route, hasLength(16));
      expect(route.first.station.code, 'MMCT');

      final bharuch = route[7];
      final ratlam = route[8];
      expect(bharuch.station.code, 'BH');
      expect(ratlam.station.code, 'RTM');
      expect(bharuch.stop.dayOffset, 0);
      expect(ratlam.stop.dayOffset, 1);
    });

    test(
      'getRunningDays is confirmed for the real 2026 Howrah Rajdhani '
      'calendar (published as "Except Su")',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');
        final train = (await repository.getTrainByNumber('12301'))!;
        final days = await repository.getRunningDays(train.trainId);
        expect(days, isNotNull);
        expect(days!.confidence, DataConfidence.confirmed);
        expect(days.sunday, isFalse);
        expect(days.monday, isTrue);
      },
    );

    test(
      'getRunningDays is honestly null for a train the 2026 timetable '
      'material gives no calendar for',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');
        final train = (await repository.getTrainByNumber('12009'))!;
        final days = await repository.getRunningDays(train.trainId);
        expect(
          days!.confidence,
          DataConfidence.unknown,
          reason:
              'documented limitation: not every real train\'s running-day '
              'text was recoverable from the source tables (see '
              'docs/RAILWAY_DATABASE.md "Block 6") - this must stay '
              'unknown, never a guessed calendar',
        );
      },
    );

    test('findDirectServices(HWH, PRYJ) finds the real Howrah Rajdhani '
        'Express (12301), with a correct overnight duration', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final hwh = (await repository.getStationByCode('HWH'))!;
      // Prayagraj (PRYJ), not the route's own last recorded stop (GZB) -
      // GZB has no recorded arrival time for this train (a genuinely
      // blank cell in the source table, not a bug here), so it can't
      // produce a journeyDuration; PRYJ has both times recorded.
      final pryj = (await repository.getStationByCode('PRYJ'))!;

      final services = await repository.findDirectServices(
        fromStationId: hwh.stationId,
        toStationId: pryj.stationId,
      );
      expect(services.any((s) => s.train.number == '12301'), isTrue);

      final rajdhani = services.firstWhere((s) => s.train.number == '12301');
      expect(rajdhani.fromStop.dayOffset, 0);
      expect(rajdhani.toStop.dayOffset, 1);
      expect(rajdhani.journeyDuration, isNotNull);
      expect(rajdhani.journeyDuration!.inHours, greaterThan(6));
    });

    test('findDirectServices(GZB, HWH) - the reverse direction - does not '
        'return 12301, which only runs one way', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final hwh = (await repository.getStationByCode('HWH'))!;
      final gzb = (await repository.getStationByCode('GZB'))!;

      final reversed = await repository.findDirectServices(
        fromStationId: gzb.stationId,
        toStationId: hwh.stationId,
      );
      expect(reversed.any((s) => s.train.number == '12301'), isFalse);
    });

    test('getTrainsAtStation finds real trains stopping at Gaya Jn.', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');
      final station = (await repository.getStationByCode('GAYA'))!;
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
      expect(metadata.trainCount, greaterThan(2000));
      expect(metadata.routeStopCount, greaterThan(16000));
      expect(metadata.datasetSource, contains('Trains at a Glance 2026'));
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
