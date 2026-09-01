// Converts the raw files downloaded by scripts/acquire_railway_data.dart
// into the four CSVs bin/import_railway_data.dart consumes
// (stations.csv, trains.csv, route_stops.csv, running_days.csv).
//
// Usage:
//   dart run scripts/transform_railway_data.dart --input raw_data --output build_data
//
// What this does, precisely (see docs/RAILWAY_DATABASE.md for the full
// writeup):
//
//  - Trains and route stops come entirely from
//    Train_details_22122017.csv's own train number, station code/name,
//    stop sequence (SEQ), arrival/departure time and cumulative
//    distance columns - nothing is invented.
//  - The source has no day-offset column. Overnight stops are detected
//    deterministically: within each train's stops (sorted by SEQ),
//    whenever a stop's time-of-day is earlier than the previous stop's,
//    that is a real day boundary the source's own times already imply
//    - day_offset is incremented from that, never guessed.
//  - The source marks a train's very first stop with a placeholder
//    arrival of "00:00:00" (there is nothing to arrive from) and its
//    last stop with a placeholder departure of "00:00:00" (there is
//    nothing to depart to). Both are dropped to null here rather than
//    imported as if they were real times.
//  - Station coordinates/state are added only when datameet's CC0
//    station list has an entry whose code matches one already present
//    from the primary source - never used to add a station the primary
//    source doesn't have, and never used to override its code or name.
//  - For a station datameet has no state for (its own `state` field is
//    blank on roughly half its entries), Wikipedia's "List of railway
//    stations in India" (CC BY-SA 4.0) is checked as a second,
//    strictly-fallback source by station code - only ever fills a gap,
//    never overrides a state either earlier source already provided.
//    A station with no state in any source keeps `state: null` - not
//    guessed.
//  - running_days.csv is written with a header only, no rows: neither
//    source provides a weekly operating calendar, and none was found
//    from another legitimate bulk-downloadable source (see
//    docs/RAILWAY_DATABASE.md "Known limitations").
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:train_yatri/domain/services/railway_normalization.dart';

class _StationRecord {
  _StationRecord(this.code, this.name);
  final String code;
  final String name;
  String? state;
  double? latitude;
  double? longitude;
}

class _RouteRow {
  _RouteRow({
    required this.trainNumber,
    required this.stopSequence,
    required this.stationCode,
    required this.arrivalRaw,
    required this.departureRaw,
    required this.distanceKm,
  });

  final String trainNumber;
  final int stopSequence;
  final String stationCode;
  final String arrivalRaw;
  final String departureRaw;
  final String distanceKm;
}

final _wikiLinkWithDisplay = RegExp(r'\[\[([^\]|]*)\|([^\]]*)\]\]');
final _wikiLink = RegExp(r'\[\[([^\]]*)\]\]');
final _wikiTemplate = RegExp(r'\{\{[^}]*\}\}');
final _htmlTag = RegExp(r'<[^>]*>');
final _stationCodePattern = RegExp(r'^[A-Za-z0-9]{1,6}$');

String _stripWikiMarkup(String value) {
  var s = value.trim();
  s = s.replaceAllMapped(_wikiLinkWithDisplay, (m) => m.group(2) ?? '');
  s = s.replaceAllMapped(_wikiLink, (m) => m.group(1) ?? '');
  s = s.replaceAll(_wikiTemplate, '');
  s = s.replaceAll(_htmlTag, '');
  s = s.replaceAll('&nbsp;', ' ');
  return s.trim();
}

/// Parses the `{|class="wikitable sortable" ... |}` tables in
/// Wikipedia's "List of railway stations in India" article
/// (`action=raw` wikitext) into a station-code -> state map. Each row
/// looks like `| {{stnlnk|Name}} || CODE || State || Zone || Elevation
/// || Notes`; only the code and state columns are used. First
/// occurrence of a code wins if the article itself lists a code twice
/// with different states (rare, and not worth failing the whole import
/// over).
Map<String, String> _parseWikipediaStationStates(String wikitext) {
  final result = <String, String>{};
  for (final line in wikitext.split('\n')) {
    if (!line.startsWith('|') ||
        line.startsWith('|-') ||
        line.startsWith('|}')) {
      continue;
    }
    final content = line.replaceFirst(RegExp(r'^\|+\s?'), '');
    final fields = content.split('||');
    if (fields.length < 4) continue;
    final code = _stripWikiMarkup(fields[1]).toUpperCase();
    final state = _stripWikiMarkup(fields[2]);
    if (!_stationCodePattern.hasMatch(code) || state.isEmpty) continue;
    result.putIfAbsent(code, () => state);
  }
  return result;
}

int? _timeToMinutes(String hhmmss) {
  final parts = hhmmss.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

Future<void> main(List<String> arguments) async {
  var inputDir = 'raw_data';
  var outputDir = 'build_data';
  for (var i = 0; i < arguments.length - 1; i++) {
    if (arguments[i] == '--input') inputDir = arguments[i + 1];
    if (arguments[i] == '--output') outputDir = arguments[i + 1];
  }

  final sourceFile = File('$inputDir/train_details_22122017.csv');
  final stationsFile = File('$inputDir/datameet_stations.json');
  if (!sourceFile.existsSync() || !stationsFile.existsSync()) {
    stderr.writeln(
      'Missing input files in "$inputDir" - run scripts/acquire_railway_data.dart first.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln('Reading ${sourceFile.path} ...');
  final rows = const CsvToListConverter(
    eol: '\n',
  ).convert(sourceFile.readAsStringSync(), eol: '\n');
  // header: Train No,Train Name,SEQ,Station Code,Station Name,
  //         Arrival time,Departure Time,Distance,Source Station,
  //         Source Station Name,Destination Station,Destination Station Name
  final dataRows = rows.skip(1).where((r) => r.length >= 8);

  final stationsByCode = <String, _StationRecord>{};
  final trainNameByNumber = <String, String>{};
  final trainNameConflicts = <String>[];
  final routeRowsByTrain = <String, List<_RouteRow>>{};

  for (final row in dataRows) {
    final trainNumber = row[0].toString().trim();
    final trainName = row[1].toString().trim();
    final seq = int.tryParse(row[2].toString().trim());
    final stationCode = row[3].toString().trim();
    final stationName = row[4].toString().trim();
    final arrival = row[5].toString().trim();
    final departure = row[6].toString().trim();
    final distance = row[7].toString().trim();

    if (trainNumber.isEmpty || stationCode.isEmpty || seq == null) continue;

    final existingTrainName = trainNameByNumber[trainNumber];
    if (existingTrainName == null) {
      trainNameByNumber[trainNumber] = trainName;
    } else if (existingTrainName != trainName) {
      trainNameConflicts.add(
        '$trainNumber: "$existingTrainName" vs "$trainName" (kept first)',
      );
    }

    stationsByCode.putIfAbsent(
      RailwayNormalization.normalizeCode(stationCode),
      () => _StationRecord(stationCode, stationName),
    );

    routeRowsByTrain
        .putIfAbsent(trainNumber, () => [])
        .add(
          _RouteRow(
            trainNumber: trainNumber,
            stopSequence: seq,
            stationCode: stationCode,
            arrivalRaw: arrival,
            departureRaw: departure,
            distanceKm: distance,
          ),
        );
  }

  stdout.writeln(
    'Parsed ${trainNameByNumber.length} trains, ${stationsByCode.length} '
    'station codes, ${routeRowsByTrain.values.fold<int>(0, (a, b) => a + b.length)} route rows.',
  );
  if (trainNameConflicts.isNotEmpty) {
    stdout.writeln(
      '${trainNameConflicts.length} train(s) had more than one name in the source; kept the first-seen name for each:',
    );
    for (final c in trainNameConflicts) {
      stdout.writeln('  $c');
    }
  }

  stdout.writeln('Reading ${stationsFile.path} ...');
  final geoJson =
      jsonDecode(stationsFile.readAsStringSync()) as Map<String, dynamic>;
  final features = geoJson['features'] as List;
  var stateFromDatameet = 0;
  var coordsFromDatameet = 0;
  for (final feature in features) {
    final props = (feature as Map<String, dynamic>)['properties'] as Map;
    final code = props['code'] as String?;
    if (code == null) continue;
    final record = stationsByCode[RailwayNormalization.normalizeCode(code)];
    if (record == null) continue; // not one of our primary-source stations
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    final coords = (geometry?['coordinates'] as List?) ?? const [];
    // datameet leaves `state` as "" (not absent) on roughly half its
    // entries - only take it when it actually has a value, so an empty
    // string here never overwrites/blocks a later fallback source.
    final state = props['state'] as String?;
    if (state != null && state.isNotEmpty) {
      record.state = state;
      stateFromDatameet++;
    }
    if (coords.length == 2) {
      final lon = coords[0] as num?;
      final lat = coords[1] as num?;
      if (lon != null && lat != null) {
        record.longitude = lon.toDouble();
        record.latitude = lat.toDouble();
        coordsFromDatameet++;
      }
    }
  }
  stdout.writeln(
    'datameet: $stateFromDatameet / ${stationsByCode.length} stations got a state, '
    '$coordsFromDatameet got coordinates.',
  );

  final wikipediaFile = File('$inputDir/wikipedia_station_list.wikitext');
  if (wikipediaFile.existsSync()) {
    stdout.writeln('Reading ${wikipediaFile.path} ...');
    final wikiStateByCode = _parseWikipediaStationStates(
      wikipediaFile.readAsStringSync(),
    );
    var stateFromWikipedia = 0;
    for (final record in stationsByCode.values) {
      if (record.state != null) continue; // datameet already had it
      final normalizedCode = RailwayNormalization.normalizeCode(record.code);
      final state = wikiStateByCode[normalizedCode];
      if (state != null) {
        record.state = state;
        stateFromWikipedia++;
      }
    }
    final stillMissing = stationsByCode.values
        .where((r) => r.state == null)
        .length;
    stdout.writeln(
      'Wikipedia: $stateFromWikipedia additional stations got a state '
      '(${wikiStateByCode.length} station-code -> state pairs parsed). '
      '$stillMissing / ${stationsByCode.length} stations still have no '
      'state from any source - left as null, not guessed.',
    );
  } else {
    stdout.writeln(
      '${wikipediaFile.path} not found - skipping Wikipedia state fallback.',
    );
  }

  // --- day_offset derivation ---
  final finalRouteRows = <List<String>>[];
  for (final entry in routeRowsByTrain.entries) {
    final stops = entry.value
      ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));
    var dayOffset = 0;
    int? prevAnchorMinutes;
    for (var i = 0; i < stops.length; i++) {
      final stop = stops[i];
      final isFirst = i == 0;
      final isLast = i == stops.length - 1;
      final arrival = isFirst ? '' : stop.arrivalRaw;
      final departure = isLast ? '' : stop.departureRaw;

      final anchorRaw = arrival.isNotEmpty ? arrival : departure;
      final anchorMinutes = anchorRaw.isEmpty
          ? null
          : _timeToMinutes(anchorRaw);
      if (anchorMinutes != null &&
          prevAnchorMinutes != null &&
          anchorMinutes < prevAnchorMinutes) {
        dayOffset += 1;
      }
      if (anchorMinutes != null) prevAnchorMinutes = anchorMinutes;

      finalRouteRows.add([
        stop.trainNumber,
        stop.stopSequence.toString(),
        stop.stationCode,
        arrival,
        departure,
        dayOffset.toString(),
        stop.distanceKm,
      ]);
    }
  }

  final outDir = Directory(outputDir)..createSync(recursive: true);
  const converter = ListToCsvConverter(eol: '\n');

  File('${outDir.path}/stations.csv').writeAsStringSync(
    converter.convert([
      ['code', 'name', 'city', 'state', 'latitude', 'longitude'],
      for (final s in stationsByCode.values)
        [
          s.code,
          s.name,
          '',
          s.state ?? '',
          s.latitude?.toString() ?? '',
          s.longitude?.toString() ?? '',
        ],
    ]),
  );

  File('${outDir.path}/trains.csv').writeAsStringSync(
    converter.convert([
      ['number', 'name', 'is_active'],
      for (final e in trainNameByNumber.entries) [e.key, e.value, ''],
    ]),
  );

  File('${outDir.path}/route_stops.csv').writeAsStringSync(
    converter.convert([
      [
        'train_number',
        'stop_sequence',
        'station_code',
        'arrival_time',
        'departure_time',
        'day_offset',
        'distance_km',
      ],
      ...finalRouteRows,
    ]),
  );

  File('${outDir.path}/running_days.csv').writeAsStringSync(
    converter.convert([
      [
        'train_number',
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
        'confidence',
      ],
    ]),
  );

  stdout.writeln('Wrote CSVs to ${outDir.path}/');
}
