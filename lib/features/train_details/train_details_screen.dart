import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../data/providers/running_days_lookup_providers.dart';
import '../../domain/entities/route_stop_with_station.dart';
import '../../domain/entities/train_service.dart';
import '../../domain/repositories/running_days_lookup_repository.dart';
import '../../domain/services/live_status_presentation.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/date_formatter.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/loading_state.dart';
import '../live_tracking/live_status_controller.dart';
import '../live_tracking/widgets/live_status_body.dart';
import 'widgets/route_timeline.dart';

/// The real Train Details screen (Block 4, extended in Block 6): a
/// train's full, ordered route from the offline SQLite database, plus
/// - automatically, whenever the train is actually confirmed running on
/// [journeyDate] - its real live status and current position. There is
/// deliberately no separate "Live Status" button to discover: Live
/// Status is part of this screen's own content whenever it legitimately
/// applies, using the exact same [LiveStatusController]/
/// [LiveStatusRepository] as every other Live Status entry point (the
/// Live tab, recently-viewed trains) - never a second implementation.
///
/// [journeyDate] is the *searched* date - not "today" - so a search for
/// a future or past date asks Live Status about that specific date,
/// never silently substituting the current date.
class TrainDetailsScreen extends ConsumerStatefulWidget {
  const TrainDetailsScreen({
    required this.train,
    required this.journeyDate,
    super.key,
  });

  final TrainService train;
  final DateTime journeyDate;

  @override
  ConsumerState<TrainDetailsScreen> createState() => _TrainDetailsScreenState();
}

class _TrainDetailsScreenState extends ConsumerState<TrainDetailsScreen> {
  late Future<List<RouteStopWithStation>> _routeFuture;

  /// `null` while the progressive running-days lookup hasn't answered
  /// yet (or found nothing) - never treated as "confirmed running".
  RunningDaysAnswer? _runningDaysAnswer;
  bool _runningDaysChecked = false;

  /// Set the moment this train is either confirmed running on
  /// [journeyDate] (automatically) or the user explicitly asks to
  /// check anyway (the running-days answer was unknown) - once set,
  /// the real [LiveStatusController] for this exact train number and
  /// date takes over rendering, same as every other entry point.
  LiveStatusQuery? _liveQuery;

  @override
  void initState() {
    super.initState();
    _routeFuture = _loadRoute();
    _checkRunningDays();
  }

  Future<List<RouteStopWithStation>> _loadRoute() async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    return repository.getRouteWithStations(widget.train.trainId);
  }

  Future<void> _checkRunningDays() async {
    final repository = ref.read(runningDaysLookupRepositoryProvider);
    final answers = await repository.getRunningDays([widget.train.number]);
    if (!mounted) return;
    final answer = answers[widget.train.number];
    setState(() {
      _runningDaysChecked = true;
      _runningDaysAnswer = answer;
      if (answer != null &&
          answer.status == RunningDaysLookupStatus.confirmed &&
          answer.operatesOnWeekday(widget.journeyDate.weekday)) {
        _liveQuery = _queryForThisTrain();
      }
    });
  }

  LiveStatusQuery _queryForThisTrain() => LiveStatusQuery(
    widget.train.number,
    journeyDate: DateFormatter.isoDate(widget.journeyDate),
  );

  void _checkLiveStatusAnyway() =>
      setState(() => _liveQuery = _queryForThisTrain());

  void _retryRoute() => setState(() => _routeFuture = _loadRoute());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(train: widget.train),
            Expanded(
              child: FutureBuilder<List<RouteStopWithStation>>(
                future: _routeFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingState(message: 'Loading route...');
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message:
                          'Could not load this train\'s route. Please try again.',
                      onRetry: _retryRoute,
                    );
                  }
                  final stops = snapshot.data ?? const [];
                  if (stops.isEmpty) {
                    return const EmptyState(
                      icon: Icons.route_outlined,
                      message: 'No route recorded for this train',
                    );
                  }
                  return _liveQuery != null
                      ? _LiveOrFallback(
                          liveQuery: _liveQuery!,
                          staticStops: stops,
                        )
                      : _StaticWithGate(
                          stops: stops,
                          checked: _runningDaysChecked,
                          answer: _runningDaysAnswer,
                          journeyDate: widget.journeyDate,
                          onCheckAnyway: _checkLiveStatusAnyway,
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A live status query is active for this train/date. Once real live
/// data arrives, the live header + auto-scrolling route become the
/// centerpiece (replacing the static view, which would otherwise just
/// duplicate the same route with less information). Until then - or if
/// the fetch fails - the already-loaded static schedule stays visible
/// the whole time, per Block 6's "never block the page while Live
/// Status loads": only a small strip at the top reflects the live
/// fetch's own state.
class _LiveOrFallback extends ConsumerWidget {
  const _LiveOrFallback({required this.liveQuery, required this.staticStops});

  final LiveStatusQuery liveQuery;
  final List<RouteStopWithStation> staticStops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveStatusControllerProvider(liveQuery));

    if (state is LiveStatusAvailable) {
      return LiveStatusBody(
        state: state,
        onRetry: () => ref
            .read(liveStatusControllerProvider(liveQuery).notifier)
            .refreshNow(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switch (state) {
            LiveStatusLoading() => const _InlineLoading(),
            LiveStatusUnavailable(:final message) => _InlineNotice(
              icon: Icons.info_outline_rounded,
              text: message,
              actionLabel: 'Retry',
              onTap: () => ref
                  .read(liveStatusControllerProvider(liveQuery).notifier)
                  .refreshNow(),
            ),
            LiveStatusAvailable() => const SizedBox.shrink(),
          },
          const SizedBox(height: AppSpacing.md),
          RouteTimeline(stops: staticStops),
        ],
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checking live status',
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Checking live status...',
              style: AppTextStyles.bodyMuted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// No live query is active yet - show the static schedule, plus a
/// small, honest note about why: either this train is confirmed not to
/// run on [journeyDate], or that simply isn't known yet, in which case
/// the user can ask anyway. Never a blank page, never a fabricated
/// live state.
class _StaticWithGate extends StatelessWidget {
  const _StaticWithGate({
    required this.stops,
    required this.checked,
    required this.answer,
    required this.journeyDate,
    required this.onCheckAnyway,
  });

  final List<RouteStopWithStation> stops;
  final bool checked;
  final RunningDaysAnswer? answer;
  final DateTime journeyDate;
  final VoidCallback onCheckAnyway;

  bool get _confirmedNotRunning =>
      checked &&
      answer != null &&
      answer!.status == RunningDaysLookupStatus.confirmed &&
      !answer!.operatesOnWeekday(journeyDate.weekday);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_confirmedNotRunning)
            const _InlineNotice(
              icon: Icons.event_busy_outlined,
              text: 'Not running on the selected date',
            )
          else if (checked)
            _InlineNotice(
              icon: Icons.satellite_alt_outlined,
              text: 'Live status not yet checked for this train',
              actionLabel: 'Check now',
              onTap: onCheckAnyway,
            ),
          if (checked) const SizedBox(height: AppSpacing.md),
          RouteTimeline(stops: stops),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: actionLabel == null ? text : '$text. $actionLabel',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(text, style: AppTextStyles.bodyMuted)),
            if (actionLabel != null && onTap != null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.train});

  final TrainService train;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
          ),
          Expanded(
            child: Semantics(
              header: true,
              label: '${train.name}, train number ${train.number}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    train.name,
                    style: AppTextStyles.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text('#${train.number}', style: AppTextStyles.bodyMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
