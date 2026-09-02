import 'route_stop.dart';
import 'train_service.dart';

/// One train's stop at a particular station - the train identity paired
/// with just that one [RouteStop], without a second station/train
/// already chosen the way [DirectService] requires. This is what
/// journey discovery (Block 5) needs for "candidate first-leg trains
/// departing a station" - the eventual destination isn't known yet at
/// that point, so `DirectService` (which pairs a from/to stop pair on
/// one train) doesn't fit.
final class TrainStop {
  const TrainStop({required this.train, required this.stop});

  final TrainService train;
  final RouteStop stop;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainStop && train == other.train && stop == other.stop;

  @override
  int get hashCode => Object.hash(train, stop);

  @override
  String toString() => 'TrainStop(${train.number}, $stop)';
}
