/// A railway station, as provided by the imported dataset.
///
/// Every field here reflects what the source data actually contains.
/// [city], [state], [latitude] and [longitude] are nullable because the
/// source does not guarantee them for every station - they are `null`
/// (never a fake placeholder like `0` or `"Unknown"`) when the source
/// did not provide a value.
final class Station {
  const Station({
    required this.stationId,
    required this.code,
    required this.name,
    this.city,
    this.state,
    this.latitude,
    this.longitude,
  });

  /// Stable internal identifier (SQLite row id) - not a railway concept,
  /// just how this app refers to the station internally.
  final int stationId;

  /// The station code as given by the source (e.g. "NDLS"). Not
  /// normalized - use [RailwayNormalization] when matching against it.
  final String code;

  final String name;

  final String? city;
  final String? state;

  final double? latitude;
  final double? longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Station &&
          stationId == other.stationId &&
          code == other.code &&
          name == other.name &&
          city == other.city &&
          state == other.state &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode =>
      Object.hash(stationId, code, name, city, state, latitude, longitude);

  @override
  String toString() => 'Station($code, $name)';
}
