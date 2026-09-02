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
//  3. Wikipedia's "List of railway stations in India" - CC BY-SA 4.0 -
//     a station-code-to-state table, used only to fill `state` for a
//     station still missing it after source 2 (datameet's own `state`
//     field is blank for roughly half its entries) - never to add a
//     station or override a state either earlier source already gave.
//
//  4. geoBoundaries-IND-ADM1.geojson - India's 36 state/union-territory
//     boundary polygons, CC BY 2.5 India, from
//     www.geoboundaries.org (William & Mary geoLab; its own metadata
//     credits DataMeet India community + Election Commission of India
//     as the underlying source data). Used by
//     scripts/enrich_station_states.dart (Block 4) - not by this
//     project's main pipeline directly - to geometrically determine a
//     state for a station still missing one after sources 2-3, from
//     coordinates source 2 already supplies. ~44 MB; downloaded here
//     via GitHub's LFS media resolver since the plain raw.githubusercontent.com
//     URL for this particular file only returns the LFS pointer, not
//     the file content.
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
  // Wikipedia's "List of railway stations in India" - a station
  // code -> state table, CC BY-SA 4.0. Used only to fill in `state` for
  // stations source 1 provides but source 2's own state field is blank
  // for (datameet's `state` property is empty on roughly half its
  // entries) - never to add a station or override a state either
  // earlier source already gave.
  'wikipedia_station_list.wikitext':
      'https://en.wikipedia.org/w/index.php?title=List_of_railway_stations_in_India&action=raw',
  // Block 4: India state/UT boundary polygons for geometric station
  // state enrichment (scripts/enrich_station_states.dart). Fetched via
  // GitHub's LFS media resolver (media.githubusercontent.com) rather
  // than the usual raw.githubusercontent.com host, because this
  // specific file is Git-LFS-tracked in its upstream repo and the plain
  // raw host only returns the LFS pointer text, not the ~44 MB file.
  'geoBoundaries-IND-ADM1.geojson':
      'https://media.githubusercontent.com/media/wmgeolab/geoBoundaries/9469f09/releaseData/gbOpen/IND/ADM1/geoBoundaries-IND-ADM1.geojson',
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
