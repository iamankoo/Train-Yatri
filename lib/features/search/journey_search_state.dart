import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/station.dart';

/// The From/To/Date the user has currently set up on Home, shared
/// between [JourneySearchCard], the station picker, and recent-search
/// restoration so a swap or a restored search is reflected everywhere
/// consistently.
final class JourneySearchState {
  const JourneySearchState({this.from, this.to, required this.date});

  final Station? from;
  final Station? to;
  final DateTime date;

  /// From and To are both chosen and distinct - the minimum to run a
  /// search.
  bool get isValid =>
      from != null && to != null && from!.stationId != to!.stationId;

  bool get hasSameStationSelected =>
      from != null && to != null && from!.stationId == to!.stationId;
}

class JourneySearchController extends StateNotifier<JourneySearchState> {
  JourneySearchController() : super(JourneySearchState(date: _today()));

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void setFrom(Station station) =>
      state = JourneySearchState(from: station, to: state.to, date: state.date);

  void setTo(Station station) => state = JourneySearchState(
    from: state.from,
    to: station,
    date: state.date,
  );

  void clearFrom() =>
      state = JourneySearchState(from: null, to: state.to, date: state.date);

  void clearTo() =>
      state = JourneySearchState(from: state.from, to: null, date: state.date);

  void setDate(DateTime date) =>
      state = JourneySearchState(from: state.from, to: state.to, date: date);

  /// Swaps From and To, keeping the selected date untouched.
  void swap() => state = JourneySearchState(
    from: state.to,
    to: state.from,
    date: state.date,
  );

  /// Restores a full search (e.g. from a recent-search entry) in one
  /// step.
  void restore({
    required Station from,
    required Station to,
    required DateTime date,
  }) {
    state = JourneySearchState(from: from, to: to, date: date);
  }
}

final journeySearchControllerProvider =
    StateNotifierProvider<JourneySearchController, JourneySearchState>(
      (ref) => JourneySearchController(),
    );
