// Tests against the REAL production assets/database/railway.db (see
// docs/RAILWAY_DATABASE.md for provenance) - real trains, real routes,
// never a manufactured example. The specific connecting journey below
// (69122 -> Vadodara Jn. (BRC) -> 12655 "Navajeevan Express") was found
// by actually running JourneyDiscoveryService.discover against this
// database (Chhayapuri, a Vadodara suburb, naturally connects to a
// long-distance service departing Vadodara itself - real geography,
// not a coincidence), not invented to fit the algorithm.
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
// A wider-than-default search so the real, real-world connection below
// (through the 10th of 11 stops on a 118-stop-deep candidate pool) is
// reliably found - the production defaults
// (JourneyDiscoveryConfig.defaults) are tuned for interactive search
// latency, not for guaranteeing every real connection surfaces within
// them.
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

    test(
      'finds the real Chhayapuri (CYI) -> Chennai Central (MAS) '
      'connection via Vadodara Jn. (BRC): train 69122 (a real Godhra - '
      'Vadodara passenger service) into the real Navajeevan Express '
      '(12655), with a correctly calculated wait and total duration',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');

        final cyi = (await repository.getStationByCode('CYI'))!;
        final mas = (await repository.getStationByCode('MAS'))!;

        final result = await JourneyDiscoveryService.discover(
          repository: repository,
          fromStationId: cyi.stationId,
          toStationId: mas.stationId,
          config: _wideConfig,
        );

        // No single real train runs Chhayapuri -> Chennai Central.
        expect(result.direct, isEmpty);
        expect(result.connecting, isNotEmpty);

        final connection = result.connecting.firstWhere(
          (c) =>
              c.legA.train.number == '69122' && c.legB.train.number == '12655',
        );
        expect(connection.interchange.code, 'BRC');
        expect(
          connection.waitingDuration,
          const Duration(hours: 1, minutes: 37),
        );
        expect(
          connection.totalDuration,
          const Duration(hours: 32, minutes: 58),
        );
        // legA really is CYI -> BRC, in that order.
        expect(
          connection.legA.fromStop.stopSequence,
          lessThan(connection.legA.toStop.stopSequence),
        );
      },
    );

    test('a route with multiple real direct services (Vadodara Jn. -> '
        'Chennai Central) still returns them all through the service '
        'layer, same as the repository directly', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final brc = (await repository.getStationByCode('BRC'))!;
      final mas = (await repository.getStationByCode('MAS'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: brc.stationId,
        toStationId: mas.stationId,
      );

      final direct = await repository.findDirectServices(
        fromStationId: brc.stationId,
        toStationId: mas.stationId,
      );
      expect(result.direct.length, greaterThan(1));
      expect(
        result.direct.map((d) => d.train.number),
        direct.map((d) => d.train.number),
      );
    });

    test('the known real overnight direct route (12301, Howrah -> New '
        'Delhi Rajdhani) still passes through the service layer '
        'unchanged', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      final ndls = (await repository.getStationByCode('NDLS'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: hwh.stationId,
        toStationId: ndls.stationId,
      );

      final rajdhani = result.direct.firstWhere(
        (d) => d.train.number == '12301',
      );
      expect(rajdhani.fromStop.dayOffset, 0);
      expect(rajdhani.toStop.dayOffset, 1);
    });

    test('the reverse direction of a real one-way route returns no direct '
        'service (12301 only runs Howrah -> New Delhi)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final hwh = (await repository.getStationByCode('HWH'))!;
      final ndls = (await repository.getStationByCode('NDLS'))!;

      final result = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: ndls.stationId,
        toStationId: hwh.stationId,
      );
      expect(result.direct.any((d) => d.train.number == '12301'), isFalse);
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

    test('a real connecting-journey search over the full 11,112-train '
        'database completes within a realistic time bound (SQL/index '
        'performance, not an in-memory graph search)', () async {
      if (!dbExists) return markTestSkipped('railway.db not built');

      final cyi = (await repository.getStationByCode('CYI'))!;
      final mas = (await repository.getStationByCode('MAS'))!;

      final stopwatch = Stopwatch()..start();
      await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: cyi.stationId,
        toStationId: mas.stationId,
        config: _wideConfig,
      );
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
}
