// Regression coverage for Block 4's station-state enrichment
// (scripts/enrich_station_states.dart, data/enrichment/station_states.csv,
// docs/RAILWAY_DATABASE.md "Block 4"). Runs against the real bundled
// asset, the same way test/data/database/railway_database_real_asset_test.dart
// does, so a future dataset rebuild that silently drops the enrichment
// (e.g. someone forgets to regenerate data/enrichment/station_states.csv,
// or the transform pipeline's fallback ordering regresses) fails this
// test rather than shipping quietly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/railway_database.dart';
import 'package:train_yatri/data/repositories/sqlite_railway_repository.dart';

import '../test_support/ffi_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureSqfliteFfiInitialized);

  final dbExists = File('assets/database/railway.db').existsSync();

  group('Block 4 station-state enrichment (real asset)', () {
    late RailwayDatabase database;
    late Database db;
    late SqliteRailwayRepository repository;
    late Directory scratch;

    setUp(() async {
      if (!dbExists) return;
      scratch = Directory.systemTemp.createTempSync(
        'station_state_enrichment_test_',
      );
      database = RailwayDatabase(
        databaseFactory: databaseFactoryFfi,
        databasesDirectory: () async => scratch.path,
      );
      db = await database.open();
      repository = SqliteRailwayRepository(db);
    });

    tearDown(() async {
      if (!dbExists) return;
      await database.close();
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    test(
      'CYI (Chhayapuri) resolves to Gujarat - the case Block 4 was asked '
      'to explicitly verify',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');

        final station = await repository.getStationByCode('CYI');
        expect(station, isNotNull);
        expect(station!.name, 'CHHAYAPURI');
        expect(station.state, 'Gujarat');
      },
    );

    test(
      'a representative sample of previously-missing stations now has a '
      'state, each one of the 36 canonical Indian state/UT names',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');

        // Every one of these had state: null before Block 4 (see
        // docs/RAILWAY_DATABASE.md); each is now resolved by the
        // geometric enrichment source.
        const sampleCodes = ['CYI', 'BCOB', 'DARA', 'NRZB', 'RF'];
        for (final code in sampleCodes) {
          final station = await repository.getStationByCode(code);
          expect(station, isNotNull, reason: '$code should exist');
          expect(
            station!.state,
            isNotNull,
            reason: '$code should have a state after Block 4 enrichment',
          );
          expect(station.state, isNotEmpty);
        }
      },
    );

    test(
      'a genuinely unresolved station (no coordinate in any legitimate '
      'source) still honestly has no state - not guessed',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');

        // ACOI (CHHEOKI) has no coordinate in the datameet source and so
        // cannot be geometrically resolved - see
        // data/enrichment/unresolved_stations.csv. It must stay null,
        // never a fabricated value.
        final station = await repository.getStationByCode('ACOI');
        expect(station, isNotNull);
        expect(station!.state, isNull);
      },
    );

    test(
      'no state value in the database is outside the 36 canonical '
      'Indian state/union-territory names (no typos, no stale names '
      'like "Orissa", no casing drift)',
      () async {
        if (!dbExists) return markTestSkipped('railway.db not built');

        const canonical = {
          'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar',
          'Chhattisgarh', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh',
          'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh',
          'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland',
          'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
          'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
          'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh',
          'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
          'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
          //
        };

        final rows = await db.query(
          'stations',
          distinct: true,
          columns: ['state'],
          where: "state IS NOT NULL AND state != ''",
        );
        final actual = rows.map((r) => r['state'] as String).toSet();
        expect(actual.difference(canonical), isEmpty);
      },
    );
  });
}
