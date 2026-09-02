// RunningDaysFilter (Block 6): a direct/connecting result is dropped
// only when the static running_days table *confirms* the train doesn't
// operate on the searched weekday - never merely because there's no
// data for it. Synthetic fixture, not real trains.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/entities/connecting_journey.dart';
import 'package:train_yatri/domain/services/journey_discovery_service.dart';
import 'package:train_yatri/domain/services/running_days_filter.dart';

import '../../data/test_support/ffi_setup.dart';

const _stationsCsv = '''
code,name,city,state,latitude,longitude
RDA,RunningDays Origin,,,,
RDB,RunningDays Destination,,,,
RDJ,RunningDays Interchange,,,,
RDC,RunningDays Far Destination,,,,
''';

const _trainsCsv = '''
number,name,is_active
81001T,Confirmed Mon Wed Fri,1
81002T,Confirmed Daily,1
81003T,No Running Days Data,1
82001T,Leg A Confirmed Tue Only,1
82002T,Leg B Confirmed Daily,1
''';

const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
81001T,1,RDA,,08:00,0,0
81001T,2,RDB,10:00,,0,100
81002T,1,RDA,,09:00,0,0
81002T,2,RDB,11:00,,0,100
81003T,1,RDA,,10:00,0,0
81003T,2,RDB,12:00,,0,100
82001T,1,RDA,,08:00,0,0
82001T,2,RDJ,10:00,,0,100
82002T,1,RDJ,,10:40,0,0
82002T,2,RDC,12:00,,0,60
''';

const _runningDaysCsv = '''
train_number,monday,tuesday,wednesday,thursday,friday,saturday,sunday,confidence
81001T,1,0,1,0,1,0,0,confirmed
81002T,1,1,1,1,1,1,1,confirmed
82001T,0,1,0,0,0,0,0,confirmed
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
      datasetSource: 'synthetic running-days-filter fixture',
      datasetVersion: 'test-1',
    );
    repository = SqliteRailwayRepository(db);
  });

  tearDown(() => db.close());

  Future<int> stationId(String code) async =>
      (await repository.getStationByCode(code))!.stationId;

  test(
    'a train confirmed not to run on the searched weekday is removed, '
    'a confirmed-daily train and one with no data at all both stay',
    () async {
      final discovered = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('RDA'),
        toStationId: await stationId('RDB'),
      );
      expect(discovered.direct, hasLength(3));

      // Tuesday: 81001T (Mon/Wed/Fri only) must be excluded; 81002T
      // (confirmed daily) and 81003T (no running-days row at all) must
      // both remain.
      final tuesday = await RunningDaysFilter.apply(
        repository: repository,
        result: discovered,
        weekday: DateTime.tuesday,
      );
      expect(
        tuesday.direct.map((s) => s.train.number),
        containsAll(['81002T', '81003T']),
      );
      expect(
        tuesday.direct.map((s) => s.train.number),
        isNot(contains('81001T')),
      );

      // Wednesday: 81001T does run - nothing excluded.
      final wednesday = await RunningDaysFilter.apply(
        repository: repository,
        result: discovered,
        weekday: DateTime.wednesday,
      );
      expect(wednesday.direct, hasLength(3));
    },
  );

  test(
    'a connecting journey is dropped if EITHER leg is confirmed not to '
    'run that weekday, even though the other leg does',
    () async {
      final discovered = await JourneyDiscoveryService.discover(
        repository: repository,
        fromStationId: await stationId('RDA'),
        toStationId: await stationId('RDC'),
      );
      expect(discovered.connecting, hasLength(1));

      // 82001T (leg A) only runs Tuesday; 82002T (leg B) runs daily.
      // On Monday, leg A is confirmed not running - the whole
      // connection must be dropped even though leg B would be fine.
      final monday = await RunningDaysFilter.apply(
        repository: repository,
        result: discovered,
        weekday: DateTime.monday,
      );
      expect(monday.connecting, isEmpty);

      final tuesday = await RunningDaysFilter.apply(
        repository: repository,
        result: discovered,
        weekday: DateTime.tuesday,
      );
      expect(tuesday.connecting, hasLength(1));
    },
  );

  test('a result with no direct/connecting services is returned unchanged', () async {
    const empty = JourneyDiscoveryResult(direct: [], connecting: <ConnectingJourney>[]);
    final result = await RunningDaysFilter.apply(
      repository: repository,
      result: empty,
      weekday: DateTime.monday,
    );
    expect(result.direct, isEmpty);
    expect(result.connecting, isEmpty);
  });
}
