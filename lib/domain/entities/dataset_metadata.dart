/// Provenance/versioning record for whatever railway dataset is
/// currently packaged in the app, read from the database's own
/// `schema_meta` table rather than hard-coded - so the app can never
/// misreport what data it's actually running against.
final class DatasetMetadata {
  const DatasetMetadata({
    required this.schemaVersion,
    required this.datasetSource,
    required this.datasetVersion,
    required this.importedAt,
    required this.stationCount,
    required this.trainCount,
    required this.routeStopCount,
  });

  /// Version of the SQLite table structure itself (see
  /// `lib/data/database/schema.dart`) - distinct from [datasetVersion],
  /// which is the railway data's own version/date.
  final int schemaVersion;

  /// Free-text description of where the railway data came from.
  final String datasetSource;

  /// The source dataset's own version/date string, when it has one.
  final String? datasetVersion;

  final DateTime importedAt;

  final int stationCount;
  final int trainCount;
  final int routeStopCount;
}
