import 'direct_service.dart';
import 'station.dart';

/// A one-change journey: [legA] (FROM -> [interchange]) followed by
/// [legB] ([interchange] -> TO), both real single-train legs from the
/// static timetable, chronologically validated by
/// `JourneyDiscoveryService` (see that class for exactly how - in
/// particular why [waitingDuration]/[totalDuration] cannot be derived
/// from [DirectService.journeyDuration] alone: [legA] and [legB] are
/// two different trains, each with its own `day_offset` numbering
/// relative to its own origin, not a shared calendar).
///
/// [legA]/[legB] double as each leg's own "Direct" representation
/// (same shape as a direct search result) - deliberately reusing
/// [DirectService] rather than introducing a parallel "JourneyLeg"
/// type, since the two are structurally identical (a train plus its
/// from/to stops) and this lets a leg be opened straight into the
/// existing Train Details screen (`TrainDetailsScreen(train: leg.train)`)
/// with no duplicate plumbing.
final class ConnectingJourney {
  const ConnectingJourney({
    required this.legA,
    required this.interchange,
    required this.legB,
    required this.waitingDuration,
    required this.totalDuration,
  });

  final DirectService legA;
  final Station interchange;
  final DirectService legB;

  /// Time between [legA]'s arrival at [interchange] and [legB]'s
  /// departure from it, already inclusive of the configured minimum
  /// connection buffer (`JourneyDiscoveryConfig.minimumConnectionBufferMinutes`)
  /// - a candidate with less than that buffer is rejected before a
  /// [ConnectingJourney] is ever constructed, never clamped/adjusted
  /// here.
  final Duration waitingDuration;

  /// [legA]'s boarding at FROM to [legB]'s arrival at TO, computed with
  /// day_offset-aware arithmetic across both legs - never a naive sum
  /// of each leg's own duration (see
  /// `JourneyDiscoveryService._buildConnection` for why that would be
  /// wrong).
  final Duration totalDuration;

  /// Stops actually traveled through: both legs' own stop spans added
  /// together (not counting the interchange stop twice). Available
  /// whenever both legs' stop sequences are - which they always are
  /// here, since both come from real recorded routes.
  int get totalStops =>
      (legA.toStop.stopSequence - legA.fromStop.stopSequence) +
      (legB.toStop.stopSequence - legB.fromStop.stopSequence);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectingJourney &&
          legA == other.legA &&
          interchange == other.interchange &&
          legB == other.legB &&
          waitingDuration == other.waitingDuration &&
          totalDuration == other.totalDuration;

  @override
  int get hashCode =>
      Object.hash(legA, interchange, legB, waitingDuration, totalDuration);

  @override
  String toString() =>
      'ConnectingJourney(${legA.train.number} -> ${interchange.code} -> ${legB.train.number})';
}
