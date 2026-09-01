// All identifiers in this fixture (station codes, train numbers/names)
// are synthetic test-only values - never real railway data - used
// purely to exercise the import pipeline's parsing, validation and
// deduplication logic end to end.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';

import '../test_support/ffi_setup.dart';

const _stationsCsv = '''
code,name,city,state,latitude,longitude
TSA,Test Station Alpha,Test City,Test State,12.34,56.78
TSB,Test Station Beta,Test City,Test State,,
TSA,Duplicate Alpha,,,,
BADLL,Bad LatLong Station,,,notanumber,12.0
''';

const _trainsCsv = '''
number,name,is_active
00001T,Test Express One,1
00002T,Test Express Two,
00001T,Duplicate Number,1
00003T,Bad Active Train,maybe
''';

const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
00001T,1,TSA,,23:50,0,0
00001T,2,TSB,00:10,00:15,1,120.5
00001T,2,TSB,00:20,00:25,1,120.5
00001T,3,ZZZ,10:00,10:05,1,200
99999T,1,TSA,10:00,10:05,0,0
00002T,1,TSA,,badtime,0,0
00002T,abc,TSA,,10:00,0,0
''';

const _runningDaysCsv = '''
train_number,monday,tuesday,wednesday,thursday,friday,saturday,sunday,confidence
00001T,1,0,1,0,1,0,0,confirmed
00002T,1,1,1,1,1,1,1,
99999T,1,1,1,1,1,1,1,confirmed
00001T,maybe,0,1,0,1,0,0,confirmed
''';

void main() {
  setUpAll(ensureSqfliteFfiInitialized);

  test(
    'imports valid rows and rejects every invalid one, explainably',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      for (final statement in schema.schemaStatements) {
        await db.execute(statement);
      }
      addTearDown(db.close);

      final report = await RailwayImporter(db).import(
        stations: parseCsvSource(_stationsCsv),
        trains: parseCsvSource(_trainsCsv),
        routeStops: parseCsvSource(_routeStopsCsv),
        runningDays: parseCsvSource(_runningDaysCsv),
        datasetSource: 'synthetic test fixture',
        datasetVersion: 'test-1',
      );

      expect(report.stationCount, 2, reason: 'TSA and TSB only');
      expect(report.rejectedStations, hasLength(2));

      expect(report.trainCount, 2, reason: '00001T and 00002T only');
      expect(report.rejectedTrains, hasLength(2));

      expect(report.routeStopCount, 2);
      expect(report.rejectedRouteStops, hasLength(5));

      expect(report.runningDaysCount, 2);
      expect(report.rejectedRunningDays, hasLength(2));

      expect(report.integrityCheckPassed, isTrue);
      expect(report.databaseSizeBytes, greaterThan(0));
      expect(report.totalRejected, 11);
      expect(report.isClean, isFalse);
    },
  );

  test(
    'every rejection names its source file, row number and reason',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      for (final statement in schema.schemaStatements) {
        await db.execute(statement);
      }
      addTearDown(db.close);

      final report = await RailwayImporter(db).import(
        stations: parseCsvSource(_stationsCsv),
        trains: parseCsvSource(_trainsCsv),
        routeStops: parseCsvSource(_routeStopsCsv),
        runningDays: parseCsvSource(_runningDaysCsv),
        datasetSource: 'synthetic test fixture',
      );

      for (final issue in [
        ...report.rejectedStations,
        ...report.rejectedTrains,
        ...report.rejectedRouteStops,
        ...report.rejectedRunningDays,
      ]) {
        expect(issue.file, isNotEmpty);
        expect(issue.rowNumber, greaterThan(1));
        expect(issue.reason, isNotEmpty);
      }

      final duplicateStationIssue = report.rejectedStations.firstWhere(
        (i) => i.reason.contains('duplicate'),
      );
      expect(
        duplicateStationIssue.rowNumber,
        4,
      ); // header=1, so row 4 = "TSA,Duplicate Alpha,..."
    },
  );

  test('writes dataset provenance into schema_meta', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await configureRailwayConnection(db);
    for (final statement in schema.schemaStatements) {
      await db.execute(statement);
    }
    addTearDown(db.close);

    await RailwayImporter(db).import(
      stations: parseCsvSource(_stationsCsv),
      trains: parseCsvSource(_trainsCsv),
      routeStops: parseCsvSource(_routeStopsCsv),
      runningDays: parseCsvSource(_runningDaysCsv),
      datasetSource: 'synthetic test fixture',
      datasetVersion: 'test-1',
    );

    final rows = await db.query('schema_meta');
    expect(rows, hasLength(1));
    expect(rows.first['dataset_source'], 'synthetic test fixture');
    expect(rows.first['dataset_version'], 'test-1');
    expect(rows.first['schema_version'], schema.schemaVersion);
  });
}
