// Downloads the raw railway source files this project builds
// assets/database/railway.db from. Run before
// scripts/transform_railway_data.dart.
//
// Usage:
//   dart run scripts/acquire_railway_data.dart --output raw_data
//
// Sources (see docs/RAILWAY_DATABASE.md for full provenance/license
// details):
//
//  1. Train_details_22122017.csv - a train-number/station/stop-sequence
//     timetable originally published on data.gov.in (India's Open
//     Government Data platform, GODL-India licensed) and mirrored at
//     github.com/itzmeanjan/indian-railway. This is the primary source:
//     trains, stations, and route stops with arrival/departure times
//     and cumulative distance all come from here.
//
//  2. stations.json - a CC0 (public domain) GeoJSON station list from
//     github.com/datameet/railways, used only to enrich stations
//     already found in source 1 with state and coordinates when the
//     station code matches - never to add stations source 1 doesn't
//     have, and never to override its code/name.
//
// data.gov.in's own catalog page (data.gov.in/catalog/indian-railways-
// train-time-table) returns HTTP 403 to automated fetches and requires
// interactive/registered access to browse - this script uses the two
// mirrors above, which are what were actually usable, and documents
// that substitution rather than silently presenting the mirror as the
// primary government site.
import 'dart:io';

const _sources = {
  'train_details_22122017.csv':
      'https://raw.githubusercontent.com/itzmeanjan/indian-railway/master/data/Train_details_22122017.csv',
  'datameet_stations.json':
      'https://raw.githubusercontent.com/datameet/railways/master/stations.json',
};

Future<void> main(List<String> arguments) async {
  var outputDir = 'raw_data';
  final outputFlagIndex = arguments.indexOf('--output');
  if (outputFlagIndex != -1 && outputFlagIndex + 1 < arguments.length) {
    outputDir = arguments[outputFlagIndex + 1];
  }

  final dir = Directory(outputDir);
  await dir.create(recursive: true);

  final client = HttpClient();
  try {
    for (final entry in _sources.entries) {
      stdout.writeln('Downloading ${entry.key} from ${entry.value} ...');
      final request = await client.getUrl(Uri.parse(entry.value));
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln(
          '  FAILED: HTTP ${response.statusCode} for ${entry.value}',
        );
        exitCode = 1;
        continue;
      }
      final file = File('${dir.path}/${entry.key}');
      final sink = file.openWrite();
      await response.pipe(sink);
      final size = await file.length();
      stdout.writeln('  saved to ${file.path} ($size bytes)');
    }
  } finally {
    client.close();
  }

  stdout.writeln(
    'Retrieved at: ${DateTime.now().toUtc().toIso8601String()} UTC',
  );
}
