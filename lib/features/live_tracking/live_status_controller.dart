import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../data/repositories/backend_live_status_repository.dart';
import '../../domain/repositories/live_status_repository.dart';
import '../../domain/services/live_status_presentation.dart';

final liveStatusRepositoryProvider = Provider<LiveStatusRepository>((ref) {
  return BackendLiveStatusRepository(baseUrl: Env.apiBaseUrl);
});

/// Identifies one Live Status screen instance - the family key for
/// [liveStatusControllerProvider]. Two instances with the same train
/// number and journey date share a controller (and its poll timer);
/// a different train or date gets its own.
@immutable
class LiveStatusQuery {
  const LiveStatusQuery(this.trainNumber, {this.journeyDate});

  final String trainNumber;
  final String? journeyDate;

  @override
  bool operator ==(Object other) =>
      other is LiveStatusQuery &&
      other.trainNumber == trainNumber &&
      other.journeyDate == journeyDate;

  @override
  int get hashCode => Object.hash(trainNumber, journeyDate);
}

/// Fetches live status for one train and polls it roughly every
/// [pollInterval] (Block 6 Part 24: "~every 30 seconds") - but only
/// while both this controller is alive (the Live Status screen is on
/// screen; `autoDispose` tears it down the moment the last watcher
/// goes away, cancelling the timer) and the app is in the foreground
/// (tracked via [WidgetsBindingObserver] - polling pauses on
/// background/inactive and resumes with an immediate refresh when the
/// app comes back).
class LiveStatusController extends StateNotifier<LiveStatusState>
    with WidgetsBindingObserver {
  LiveStatusController({
    required this.repository,
    required this.trainNumber,
    this.journeyDate,
    this.pollInterval = const Duration(seconds: 30),
  }) : super(const LiveStatusLoading()) {
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  final LiveStatusRepository repository;
  final String trainNumber;
  final String? journeyDate;
  final Duration pollInterval;

  Timer? _timer;
  bool _appInForeground = true;
  bool _refreshInFlight = false;

  Future<void> refreshNow() => _refresh();

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    final previous = state;
    if (previous is LiveStatusAvailable) {
      state = previous.copyWith(isRefreshing: true);
    } else {
      state = const LiveStatusLoading();
    }

    try {
      final status = await repository.getLiveStatus(
        trainNumber,
        journeyDate: journeyDate,
      );
      if (!mounted) return;
      state = LiveStatusAvailable(status);
    } on LiveStatusException catch (error) {
      if (!mounted) return;
      state = previous is LiveStatusAvailable
          ? previous.copyWith(isRefreshing: false, isStale: true)
          : LiveStatusUnavailable(error.category, error.message);
    } on Object {
      if (!mounted) return;
      state = previous is LiveStatusAvailable
          ? previous.copyWith(isRefreshing: false, isStale: true)
          : const LiveStatusUnavailable(
              LiveStatusFailureCategory.unknown,
              "Couldn't load live status.",
            );
    } finally {
      _refreshInFlight = false;
    }

    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    _timer?.cancel();
    if (!mounted || !_appInForeground) return;
    _timer = Timer(pollInterval, () => unawaited(_refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (inForeground == _appInForeground) return;
    _appInForeground = inForeground;
    if (inForeground) {
      unawaited(_refresh());
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}

final liveStatusControllerProvider = StateNotifierProvider.autoDispose
    .family<LiveStatusController, LiveStatusState, LiveStatusQuery>((
      ref,
      query,
    ) {
      final repository = ref.watch(liveStatusRepositoryProvider);
      // No explicit `ref.onDispose(controller.dispose)` here:
      // StateNotifierProvider already calls `.dispose()` on the
      // notifier it creates when the provider itself is disposed -
      // adding a second one double-disposes the controller and
      // crashes ("Tried to use LiveStatusController after `dispose`
      // was called").
      return LiveStatusController(
        repository: repository,
        trainNumber: query.trainNumber,
        journeyDate: query.journeyDate,
      );
    });
