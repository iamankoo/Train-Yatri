// Tests against the REAL production assets/database/railway.db - real
// trains, real routes, never a manufactured example.
//
// Rebuilt for Block 6's 2026 dataset replacement (see
// docs/RAILWAY_DATABASE.md "Block 6"): the previous version's specific
// connecting-journey example (69122 -> BRC -> 12655) no longer exists -
// both were December-2017-dataset trains not present in the official
// 2026 timetable material this project now uses, which is itself the
// point of this block's work. The examples below were re-verified
// directly against the rebuilt database (`grep "^12301," .../
// route_stops.csv` etc.), not invented; connecting-journey correctness
// itself is exhaustively covered by the synthetic fixtures in
// journey_discovery_service_test.dart; this file only needs to confirm
// the service layer still behaves correctly against the real,
// production-sized data.
//
// Skips itself (rather than failing) if assets/database/railway.db
// doesn't exist, matching every other *_real_data_test.dart in this
// project.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/core/journey/journey_discovery_config.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/services/journey_discovery_service.dart';

import '../../data/test_support/ffi_setup.dart';

const _dbPath = 'assets/database/railway.db';
const _wideConfig = JourneyDiscoveryConfig(
  maxFirstLegCandidates: 15,
  maxInterchangeCandidates: 60,
);

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  final dbExists = File(_dbPath).existsSync();

  group('JourneyDiscoveryService against the real production database', () {
    late Database db;
    late SqliteRailwayRepository repository;

    setUpAll(() async {
      if (!dbExists) return;
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

    test('the known real overnight direct route (12301, the Howrah '
        'Rajdhani via Gaya) still passes through the service layer '
        'unchanged, with the correct day_offset crossing', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      // Real 2026 data: this train's recorded route (verified directly
      // against build_data/tag2026_final/route_stops.csv) reaches
      // Ghaziabad Jn. (GZB) - the last stop this dataset's extraction
      // pipeline could confirm for it; see docs/RAILWAY_DATABASE.md
      // "Block 6" known limitations for why a small number of long
      // routes are recorded incomplete rather than guessed further.
      final gzb = (await repository.getStationByCode('GZB'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: hwh.stationId,
        toStationId: gzb.stationId,
      );

      final rajdhani = result.direct.firstWhere(
        (d) => d.train.number == '12301',
      );
      expect(rajdhani.fromStop.dayOffset, 0);
      expect(rajdhani.toStop.dayOffset, 1);
    });

    test('the reverse direction of a real one-way route returns no direct '
        'service (12301 only runs Howrah -> Delhi)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      final gzb = (await repository.getStationByCode('GZB'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: gzb.stationId,
        toStationId: hwh.stationId,
      );
      expect(result.direct.any((d) => d.train.number == '12301'), isFalse);
    });

    test('a route with multiple real direct services still returns them '
        'all through the service layer, same as the repository '
        'directly', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      final gzb = (await repository.getStationByCode('GZB'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: hwh.stationId,
        toStationId: gzb.stationId,
      );
      final direct = await repository.findDirectServices(
        fromStationId: hwh.stationId,
        toStationId: gzb.stationId,
      );
      expect(
        result.direct.map((d) => d.train.number),
        direct.map((d) => d.train.number),
      );
    });

    test('an invalid/unknown station ID produces empty results, never '
        'a crash', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: 999999999,
        toStationId: 999999998,
      );
      expect(result.isEmpty, isTrue);
    });

    test('an identical FROM/TO station ID produces empty results (no '
        'self-journey)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final ndls = (await repository.getStationByCode('NDLS'))!;
      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: ndls.stationId,
        toStationId: ndls.stationId,
      );
      expect(result.isEmpty, isTrue);
    });

    test('a connecting-journey search over the real, production-sized '
        'database completes within a realistic time bound (SQL/index '
        'performance, not an in-memory graph search)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      final ndls = (await repository.getStationByCode('NDLS'))!;

      final stopwatch = Stopwatch()..start();
      await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: hwh.stationId,
        toStationId: ndls.stationId,
        config: _wideConfig,
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
