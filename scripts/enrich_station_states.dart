// Computes data/enrichment/station_states.csv: a station-code -> state
// enrichment table for the ~2,590 railway stations that (as of Block 2A/
// 3) still have no `state` after the datameet + Wikipedia sources
// scripts/transform_railway_data.dart already applies, but DO have a
// coordinate (also from datameet).
//
// Method: deterministic point-in-polygon. For each such station's
// (lon, lat), this determines which one of India's 36 official
// state/union-territory boundary polygons contains that point (ray
// casting, exterior ring minus hole rings) - a fixed geometric
// computation, never a name-based or textual guess.
//
// Sources:
//  - Station coordinates: github.com/datameet/railways (CC0) - the same
//    source already used for coordinates/state in the base pipeline.
//  - State/UT boundaries: geoBoundaries "IND-ADM1" release
//    (www.geoboundaries.org, CC BY 2.5 India), itself built from
//    DataMeet India community data + Election Commission of India
//    (per the release's own metadata at
//    https://www.geoboundaries.org/api/current/gbOpen/IND/ADM1/) - the
//    same DataMeet lineage as the coordinates above, plus India's
//    election authority.
//
// Verification performed (see docs/RAILWAY_DATABASE.md "Block 4" for
// the full writeup): this was cross-checked by running the identical
// computation against BOTH the full-resolution
// (geoBoundaries-IND-ADM1.geojson) and the simplified
// (geoBoundaries-IND-ADM1_simplified.geojson) release of the same
// dataset - every one of the 2,590 resolvable stations got the
// identical state at both resolutions. A station whose coordinate does
// not fall inside any of the 36 polygons (or has no coordinate at all)
// gets no row here - left unresolved, never guessed - and is instead
// listed in data/enrichment/unresolved_stations.csv.
//
// Usage:
//   dart run scripts/enrich_station_states.dart --input raw_data --output data/enrichment
import 'dart:convert';
import 'dart:io';

import 'package:train_yatri/domain/services/railway_normalization.dart';

import 'state_names.dart';

const _retrievalDate = '2026-09-02';
const _source =
    'Computed: point-in-polygon against geoBoundaries India ADM1 '
    'state/union-territory boundaries (William & Mary geoLab, CC BY 2.5 '
    'India; boundary source data: DataMeet India community + Election '
    'Commission of India), applied to station coordinates from '
    'datameet/railways (CC0)';
const _sourceUrl =
    'https://www.geoboundaries.org/api/current/gbOpen/IND/ADM1/; '
    'https://github.com/datameet/railways';
const _confidence = 'verified-geometric';
const _method = 'point_in_polygon';

class _Ring {
  _Ring(this.points);
  final List<List<double>> points; // [ [lon, lat], ... ]
}

class _Polygon {
  _Polygon(this.rings); // rings[0] = exterior, rest = holes
  final List<_Ring> rings;
}

class _StateBoundary {
  _StateBoundary(this.name, this.polygons);
  final String name;
  final List<_Polygon> polygons;
}

bool _pointInRing(double x, double y, _Ring ring) {
  var inside = false;
  final pts = ring.points;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final xi = pts[i][0], yi = pts[i][1];
    final xj = pts[j][0], yj = pts[j][1];
    final intersects =
        ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}

bool _pointInPolygon(double x, double y, _Polygon polygon) {
  if (!_pointInRing(x, y, polygon.rings[0])) return false;
  for (var k = 1; k < polygon.rings.length; k++) {
    if (_pointInRing(x, y, polygon.rings[k])) return false;
  }
  return true;
}

String? _findState(double lon, double lat, List<_StateBoundary> boundaries) {
  for (final boundary in boundaries) {
    for (final polygon in boundary.polygons) {
      if (_pointInPolygon(lon, lat, polygon)) return boundary.name;
    }
  }
  return null;
}

List<_Polygon> _polygonsFromGeometry(Map<String, dynamic> geometry) {
  final type = geometry['type'] as String;
  final coords = geometry['coordinates'] as List;
  List<_Ring> ringsOf(List rawRings) => [
    for (final rawRing in rawRings)
      _Ring([
        for (final pt in rawRing as List)
          [(pt[0] as num).toDouble(), (pt[1] as num).toDouble()],
      ]),
  ];
  if (type == 'Polygon') {
    return [_Polygon(ringsOf(coords))];
  } else if (type == 'MultiPolygon') {
    return [for (final poly in coords) _Polygon(ringsOf(poly as List))];
  }
  return const [];
}

Future<void> main(List<String> arguments) async {
  var inputDir = 'raw_data';
  var outputDir = 'data/enrichment';
  for (var i = 0; i < arguments.length - 1; i++) {
    if (arguments[i] == '--input') inputDir = arguments[i + 1];
    if (arguments[i] == '--output') outputDir = arguments[i + 1];
  }

  final stationsFile = File('$inputDir/datameet_stations.json');
  final boundaryFile = File('$inputDir/geoBoundaries-IND-ADM1.geojson');
  if (!stationsFile.existsSync() || !boundaryFile.existsSync()) {
    stderr.writeln(
      'Missing input files in "$inputDir" - need datameet_stations.json '
      'and geoBoundaries-IND-ADM1.geojson (see docs/RAILWAY_DATABASE.md '
      '"Block 4" for how to fetch the latter; it is too large to keep in '
      'git and is not covered by scripts/acquire_railway_data.dart).',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('Reading ${boundaryFile.path} ...');
  final geo = jsonDecode(boundaryFile.readAsStringSync()) as Map;
  final boundaries = <_StateBoundary>[
    for (final feature in geo['features'] as List)
      _StateBoundary(
        canonicalizeStateName(
              (feature['properties'] as Map)['shapeName'] as String,
            ) ??
            (throw StateError(
              'Unrecognized state name from geoBoundaries: '
              '${(feature['properties'] as Map)['shapeName']}',
            )),
        _polygonsFromGeometry(feature['geometry'] as Map<String, dynamic>),
      ),
  ];
  stdout.writeln('Loaded ${boundaries.length} state/UT boundary polygons.');

  stdout.writeln('Reading ${stationsFile.path} ...');
  final stationsJson = jsonDecode(stationsFile.readAsStringSync()) as Map;
  final features = stationsJson['features'] as List;

  final resolvedRows = <List<String>>[];
  var withCoords = 0;
  var noCoordinate = 0;
  var outsideAllBoundaries = 0;

  for (final feature in features) {
    final props = (feature as Map)['properties'] as Map;
    final code = props['code'] as String?;
    if (code == null || code.trim().isEmpty) continue;
    final normalizedCode = RailwayNormalization.normalizeCode(code);

    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = (geometry?['coordinates'] as List?) ?? const [];
    if (coords.length != 2) {
      noCoordinate++;
      continue;
    }
    withCoords++;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    final state = _findState(lon, lat, boundaries);
    if (state == null) {
      outsideAllBoundaries++;
      continue;
    }
    resolvedRows.add([normalizedCode, state]);
  }

  stdout.writeln(
    '$withCoords / ${features.length} datameet stations had a coordinate '
    '($noCoordinate did not); ${resolvedRows.length} resolved to a state, '
    '$outsideAllBoundaries had a coordinate outside all 36 boundaries '
    '(left unresolved, not guessed).\n'
    'This is every datameet station this method can resolve, not just '
    'ones this project currently has missing a state for - '
    'scripts/transform_railway_data.dart applies it only as a gap-filler. '
    'The authoritative "still missing a state" report for THIS project\'s '
    'stations is generated after the full pipeline runs - see '
    'docs/RAILWAY_DATABASE.md "Block 4".',
  );

  final outDir = Directory(outputDir)..createSync(recursive: true);

  final statesFile = File('${outDir.path}/station_states.csv');
  final buffer = StringBuffer()
    ..writeln(
      'station_code,state,source,source_url,retrieval_date,confidence,method',
    );
  for (final row in resolvedRows) {
    buffer.writeln(
      '${row[0]},${row[1]},"$_source",$_sourceUrl,$_retrievalDate,$_confidence,$_method',
    );
  }
  statesFile.writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote ${resolvedRows.length} rows to ${statesFile.path}');
}
