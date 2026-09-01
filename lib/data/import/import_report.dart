/// One problem found while importing a single source row. Every
/// rejected or altered record produces one of these - nothing is ever
/// dropped from the import without a corresponding, explainable entry
/// here.
final class ImportIssue {
  const ImportIssue({
    required this.file,
    required this.rowNumber,
    required this.reason,
  });

  /// Which source file the row came from (e.g. "stations.csv").
  final String file;

  /// 1-based row number within that file, counting the header as row 1
  /// (so it lines up with what a human sees opening the file).
  final int rowNumber;

  final String reason;

  @override
  String toString() => '$file:$rowNumber - $reason';
}

/// The full result of one import run, including everything needed to
/// answer "what exactly did the import do" without re-reading the
/// source files.
final class ImportReport {
  const ImportReport({
    required this.stationCount,
    required this.trainCount,
    required this.routeStopCount,
    required this.runningDaysCount,
    required this.rejectedStations,
    required this.rejectedTrains,
    required this.rejectedRouteStops,
    required this.rejectedRunningDays,
    required this.integrityCheckPassed,
    required this.databaseSizeBytes,
  });

  final int stationCount;
  final int trainCount;
  final int routeStopCount;
  final int runningDaysCount;

  final List<ImportIssue> rejectedStations;
  final List<ImportIssue> rejectedTrains;
  final List<ImportIssue> rejectedRouteStops;
  final List<ImportIssue> rejectedRunningDays;

  final bool integrityCheckPassed;
  final int databaseSizeBytes;

  int get totalRejected =>
      rejectedStations.length +
      rejectedTrains.length +
      rejectedRouteStops.length +
      rejectedRunningDays.length;

  bool get isClean => totalRejected == 0 && integrityCheckPassed;

  String toSummary() {
    final buffer = StringBuffer()
      ..writeln('Railway data import report')
      ..writeln(
        '  stations:      $stationCount imported, ${rejectedStations.length} rejected',
      )
      ..writeln(
        '  trains:        $trainCount imported, ${rejectedTrains.length} rejected',
      )
      ..writeln(
        '  route stops:   $routeStopCount imported, ${rejectedRouteStops.length} rejected',
      )
      ..writeln(
        '  running days:  $runningDaysCount imported, ${rejectedRunningDays.length} rejected',
      )
      ..writeln('  integrity_check: ${integrityCheckPassed ? 'ok' : 'FAILED'}')
      ..writeln('  database size: $databaseSizeBytes bytes');

    for (final issue in [
      ...rejectedStations,
      ...rejectedTrains,
      ...rejectedRouteStops,
      ...rejectedRunningDays,
    ]) {
      buffer.writeln('  rejected: $issue');
    }
    return buffer.toString();
  }
}
