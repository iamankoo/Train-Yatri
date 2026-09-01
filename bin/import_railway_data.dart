// ignore_for_file: depend_on_referenced_packages
// sqflite_common_ffi is a dev_dependency deliberately - it's only ever
// used here (a dev-time build tool) and in tests, never by the shipped
// app, which uses the default sqflite platform-channel factory instead.

// Rebuilds the packaged railway SQLite database from source CSV files.
//
// Usage:
//   dart run bin/import_railway_data.dart \
//     --stations stations.csv \
//     --trains trains.csv \
//     --route-stops route_stops.csv \
//     --running-days running_days.csv \
//     --output assets/database/railway.db \
//     --source "<dataset name/URL>" \
//     --source-version "<dataset version or date>"
//
// See docs/RAILWAY_DATABASE.md for the exact expected CSV column
// layout for each input file and where to get a real dataset from.
//
// This is a plain Dart CLI tool (not part of the Flutter app itself),
// run at build/dev time to produce the asset the app actually ships.
import 'dart:io';

import 'package:args/args.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:train_yatri/data/database/connection_setup.dart';
import 'package:train_yatri/data/database/schema.dart' as schema;
import 'package:train_yatri/data/import/csv_source.dart';
import 'package:train_yatri/data/import/railway_importer.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('stations', mandatory: true, help: 'Path to stations.csv')
    ..addOption('trains', mandatory: true, help: 'Path to trains.csv')
    ..addOption('route-stops', mandatory: true, help: 'Path to route_stops.csv')
    ..addOption(
      'running-days',
      mandatory: true,
      help: 'Path to running_days.csv',
    )
    ..addOption(
      'output',
      defaultsTo: 'assets/database/railway.db',
      help: 'Where to write the built SQLite database',
    )
    ..addOption(
      'source',
      mandatory: true,
      help: 'Human-readable dataset source/provenance description',
    )
    ..addOption(
      'source-version',
      help: "The source dataset's own version/date, if it has one",
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (args['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }

  final stationsFile = File(args['stations'] as String);
  final trainsFile = File(args['trains'] as String);
  final routeStopsFile = File(args['route-stops'] as String);
  final runningDaysFile = File(args['running-days'] as String);
  final outputPath = args['output'] as String;

  for (final file in [
    stationsFile,
    trainsFile,
    routeStopsFile,
    runningDaysFile,
  ]) {
    if (!file.existsSync()) {
      stderr.writeln('Input file not found: ${file.path}');
      exitCode = 1;
      return;
    }
  }

  sqfliteFfiInit();

  final outputFile = File(outputPath);
  if (outputFile.existsSync()) {
    // Deterministic output: always rebuild from a clean slate rather
    // than mutating whatever was there before.
    outputFile.deleteSync();
  }
  outputFile.parent.createSync(recursive: true);

  final db = await databaseFactoryFfi.openDatabase(outputPath);
  await configureRailwayConnection(db);
  for (final statement in schema.schemaStatements) {
    await db.execute(statement);
  }

  final report = await RailwayImporter(db).import(
    stations: parseCsvSource(stationsFile.readAsStringSync()),
    trains: parseCsvSource(trainsFile.readAsStringSync()),
    routeStops: parseCsvSource(routeStopsFile.readAsStringSync()),
    runningDays: parseCsvSource(runningDaysFile.readAsStringSync()),
    datasetSource: args['source'] as String,
    datasetVersion: args['source-version'] as String?,
  );
  await db.close();

  stdout.writeln(report.toSummary());

  if (!report.integrityCheckPassed) {
    stderr.writeln(
      'SQLite integrity_check FAILED - refusing to ship this database.',
    );
    exitCode = 1;
    return;
  }
  if (report.stationCount == 0 || report.trainCount == 0) {
    stderr.writeln(
      'No stations or trains were imported - check the input files.',
    );
    exitCode = 1;
    return;
  }
}
