import 'data_confidence.dart';

/// A train/service identity, as distinct from any specific journey date
/// (see [RunningDays] for which days it actually runs).
final class TrainService {
  const TrainService({
    required this.trainId,
    required this.number,
    required this.name,
    required this.isActive,
    this.confidence = DataConfidence.unknown,
  });

  /// Stable internal identifier (SQLite row id).
  final int trainId;

  /// The train number as given by the source (e.g. "12301").
  final String number;

  final String name;

  /// Whether the source marks this service as currently operating.
  /// `true` unless the source explicitly says otherwise.
  final bool isActive;

  /// Confidence in this train's identity/metadata as provided by the
  /// source. Distinct from [RunningDays.confidence], which specifically
  /// covers the weekly operating pattern.
  final DataConfidence confidence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainService &&
          trainId == other.trainId &&
          number == other.number &&
          name == other.name &&
          isActive == other.isActive &&
          confidence == other.confidence;

  @override
  int get hashCode => Object.hash(trainId, number, name, isActive, confidence);

  @override
  String toString() => 'TrainService($number, $name)';
}
