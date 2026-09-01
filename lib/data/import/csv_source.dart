import 'package:csv/csv.dart';

/// One parsed data row, keyed by its file's header column names, plus
/// the 1-based row number it came from (header counted as row 1) so
/// validation issues can point back at the exact source line.
final class SourceRow {
  const SourceRow(this.rowNumber, this.fields);

  final int rowNumber;
  final Map<String, String> fields;

  String? operator [](String column) {
    final value = fields[column]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}

/// Parses CSV text where the first row is a header naming each column,
/// used for all four railway source files (stations, trains,
/// route_stops, running_days). Blank trailing lines are ignored.
List<SourceRow> parseCsvSource(String csvText) {
  final rows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(csvText, eol: '\n');

  if (rows.isEmpty) return const [];

  final header = rows.first.map((cell) => cell.toString().trim()).toList();
  final result = <SourceRow>[];

  for (var i = 1; i < rows.length; i++) {
    final rawRow = rows[i];
    if (rawRow.length == 1 && rawRow.first.toString().trim().isEmpty) {
      continue; // trailing blank line
    }
    final fields = <String, String>{};
    for (var c = 0; c < header.length && c < rawRow.length; c++) {
      fields[header[c]] = rawRow[c].toString();
    }
    // rowNumber is 1-based including the header row itself, i.e. the
    // first data row is row 2 - matching what a spreadsheet/editor shows.
    result.add(SourceRow(i + 1, fields));
  }

  return result;
}
