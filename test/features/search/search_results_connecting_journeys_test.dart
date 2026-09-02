// Block 5, "Connecting journey UI" (Part 16/17/21): DIRECT and 1 CHANGE
// must render as clearly distinct sections, "No direct trains found" /
// "Connections available" must show honestly when only a connection
// exists, and a connecting journey's legs must open into the existing
// Train Details screen. Uses its own dedicated synthetic fixture (not
// fake_railway_repository.dart's shared one) so these specific
// direct+connecting/connecting-only scenarios can be constructed
// precisely without disturbing every other widget test that shares
// that fixture.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';
import 'package:train_yatri/data/providers/railway_providers.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';
import 'package:train_yatri/domain/entities/station.dart';
import 'package:train_yatri/features/search/search_results_screen.dart';
import 'package:train_yatri/features/train_details/train_details_screen.dart';

const _stationsCsv = '''
code,name,city,state,latitude,longitude
WA,Both Origin,,,,
WJ,Both Interchange,,,,
WB,Both Destination,,,,
WX,ConnOnly Origin,,,,
WY,ConnOnly Interchange,,,,
WZ,ConnOnly Destination,,,,
''';

const _trainsCsv = '''
number,name,is_active
97001T,W Direct Through,1
97002T,W Leg A,1
97003T,W Leg B,1
98001T,X Leg A,1
98002T,X Leg B,1
''';

// 97001T runs WA -> WB directly, with no stop at the interchange at
// all - deliberately isolated from the connecting pair below so it
// cannot also qualify as a connecting-journey first leg through WJ.
// 97002T (WA -> WJ, arr 10:00) + 97003T (WJ -> WB, dep 10:40) form the
// one valid connection.
const _routeStopsCsv = '''
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
97001T,1,WA,,06:00,0,0
97001T,2,WB,07:30,,0,100
97002T,1,WA,,09:00,0,0
97002T,2,WJ,10:00,,0,50
97003T,1,WJ,,10:40,0,0
97003T,2,WB,11:30,,0,50
98001T,1,WX,,06:00,0,0
98001T,2,WY,07:00,,0,50
98002T,1,WY,,07:40,0,0
98002T,2,WZ,08:30,,0,50
''';

Future<Database> _openFixtureDb() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await configureRailwayConnection(db);
  for (final statement in schema.schemaStatements) {
    await db.execute(statement);
  }
  await RailwayImporter(db).import(
    stations: parseCsvSource(_stationsCsv),
    trains: parseCsvSource(_trainsCsv),
    routeStops: parseCsvSource(_routeStopsCsv),
    runningDays: const [],
    datasetSource: 'synthetic connecting-journey UI fixture',
  );
  return db;
}

/// Looks up a station by code from a throwaway instance of the same
/// deterministic fixture (identical CSVs, identical insert order ->
/// identical autoincrement IDs) so the [Station] passed into
/// [SearchResultsScreen] matches whatever ID the widget's own
/// separately-opened database assigns.
Future<Station> _lookupStation(String code) async {
  final db = await _openFixtureDb();
  final station = await SqliteRailwayRepository(db).getStationByCode(code);
  await db.close();
  return station!;
}

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      railwayRepositoryProvider.overrideWith((ref) async {
        final db = await _openFixtureDb();
        ref.onDispose(db.close);
        return SqliteRailwayRepository(db);
      }),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'shows Direct and 1 Change as distinct, separately-labeled sections '
    'when both a direct service and a connection exist',
    (tester) async {
      final from = await _lookupStation('WA');
      final to = await _lookupStation('WB');

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: from, to: to, date: DateTime(2026, 9, 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Direct'), findsOneWidget);
      expect(find.text('1 Change'), findsOneWidget);
      expect(find.textContaining('97001T'), findsOneWidget); // direct
      expect(find.textContaining('97002T'), findsOneWidget); // leg A
      expect(find.textContaining('97003T'), findsOneWidget); // leg B
      expect(find.textContaining('Change at Both Interchange'), findsOneWidget);
      expect(find.text('No direct trains found'), findsNothing);
    },
  );

  testWidgets(
    'shows "No direct trains found" then "Connections available" when '
    'only a connection exists - never claims a direct train exists',
    (tester) async {
      final from = await _lookupStation('WX');
      final to = await _lookupStation('WZ');

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: from, to: to, date: DateTime(2026, 9, 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No direct trains found'), findsOneWidget);
      expect(find.text('Connections available'), findsOneWidget);
      expect(find.text('Direct'), findsNothing);
      expect(find.text('1 Change'), findsOneWidget);
      expect(find.textContaining('98001T'), findsOneWidget);
      expect(find.textContaining('98002T'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a connecting journey\'s leg opens Train Details for that '
    'leg\'s own train (Block 5 Train Details integration)',
    (tester) async {
      final from = await _lookupStation('WX');
      final to = await _lookupStation('WZ');

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: from, to: to, date: DateTime(2026, 9, 2)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('98001T'));
      await tester.pumpAndSettle();

      expect(find.byType(TrainDetailsScreen), findsOneWidget);
      expect(find.textContaining('98001T'), findsOneWidget);
    },
  );

  testWidgets('exposes semantic labels for the connecting journey\'s legs, the '
      'change-at row, and the total duration (Block 5 accessibility)', (
    tester,
  ) async {
    final from = await _lookupStation('WA');
    final to = await _lookupStation('WB');

    await tester.pumpWidget(
      _wrap(
        SearchResultsScreen(from: from, to: to, date: DateTime(2026, 9, 2)),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.byType(Scaffold).first);
    final semanticsTree = semantics.toStringDeep();
    expect(semanticsTree, contains('97002T'));
    expect(semanticsTree, contains('Change at Both Interchange'));
    expect(semanticsTree, contains('Wait 40 min'));
    expect(semanticsTree, contains('Total journey time'));
  });

  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    testWidgets('the connecting-journey card lays out without horizontal '
        'overflow at ${width}dp width', (tester) async {
      tester.view.physicalSize = Size(width, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final from = await _lookupStation('WA');
      final to = await _lookupStation('WB');

      await tester.pumpWidget(
        _wrap(
          SearchResultsScreen(from: from, to: to, date: DateTime(2026, 9, 2)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
