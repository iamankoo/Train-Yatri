import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../data/providers/running_days_lookup_providers.dart';
import '../../domain/entities/direct_service.dart';
import '../../domain/entities/station.dart';
import '../../domain/repositories/running_days_lookup_repository.dart';
import '../../domain/services/journey_discovery_service.dart';
import '../../domain/services/running_days_filter.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/date_formatter.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/loading_state.dart';
import '../../shared/widgets/section_title.dart';
import 'widgets/connecting_journey_card.dart';
import 'widgets/train_result_card.dart';

/// Search Results (Block 5): direct services and one-change connecting
/// journeys between [from] and [to] on [date], via
/// `JourneyDiscoveryService.discover` - direct services and
/// connections come straight from the offline SQLite database, never
/// fabricated. A result is excluded when the static running-days table
/// *confirms* it doesn't operate on [date]'s weekday (see
/// `RunningDaysFilter`, Block 6) - a service with no running-days data
/// at all is never excluded on that basis alone.
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({
    required this.from,
    required this.to,
    required this.date,
    super.key,
  });

  final Station from;
  final Station to;
  final DateTime date;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late Future<JourneyDiscoveryResult> _future;

  /// Populated after direct results load, via a best-effort background
  /// call to the backend's progressive running-days lookup (see
  /// `docs/RUNNING_DAYS_BACKFILL.md`). Never blocks or delays the
  /// offline search itself - starts empty, and `_ResultsList` shows a
  /// single unsplit "Direct" section until (if ever) this fills in.
  Map<String, RunningDaysAnswer> _runningDaysAnswers = {};

  @override
  void initState() {
    super.initState();
    _future = _search();
  }

  Future<JourneyDiscoveryResult> _search() async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    final discovered = await JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: widget.from.stationId,
      toStationId: widget.to.stationId,
    );
    // A train the static 2026 dataset *confirms* does not run on
    // widget.date's weekday is removed here - never merely because
    // running-days data is absent for it (see RunningDaysFilter's own
    // doc comment). This is offline/local-DB only, distinct from the
    // additive RailRadar-backed "Running on <date>" section below.
    final result = await RunningDaysFilter.apply(
      repository: repository,
      result: discovered,
      weekday: widget.date.weekday,
    );
    if (result.direct.isNotEmpty) {
      unawaited(_loadRunningDays(result.direct));
    }
    return result;
  }

  Future<void> _loadRunningDays(List<DirectService> direct) async {
    final numbers = {
      for (final service in direct) service.train.number,
    }.toList();
    final lookupRepository = ref.read(runningDaysLookupRepositoryProvider);
    final answers = await lookupRepository.getRunningDays(numbers);
    if (!mounted || answers.isEmpty) return;
    setState(() => _runningDaysAnswers = answers);
  }

  void _retry() => setState(() {
    _runningDaysAnswers = {};
    _future = _search();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(from: widget.from, to: widget.to, date: widget.date),
            Expanded(
              child: FutureBuilder<JourneyDiscoveryResult>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingState(message: 'Searching trains...');
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: 'Could not search trains. Please try again.',
                      onRetry: _retry,
                    );
                  }
                  final result = snapshot.data;
                  if (result == null || result.isEmpty) {
                    return const EmptyState(
                      icon: Icons.train_outlined,
                      message: 'No journey found',
                    );
                  }
                  return _ResultsList(
                    result: result,
                    date: widget.date,
                    runningDaysAnswers: _runningDaysAnswers,
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

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.result,
    required this.date,
    required this.runningDaysAnswers,
  });

  final JourneyDiscoveryResult result;
  final DateTime date;
  final Map<String, RunningDaysAnswer> runningDaysAnswers;

  /// Direct services RailRadar has confirmed actually run on [date]'s
  /// weekday - shown first, ahead of the complete list below, per the
  /// product requirement that a search surface likely-relevant trains
  /// before the full unfiltered list. Empty (and therefore invisible)
  /// until the backend's progressive lookup has confirmed at least one
  /// - this never removes or reorders the complete list underneath it.
  List<DirectService> get _runningOnDate => [
    for (final service in result.direct)
      if (runningDaysAnswers[service.train.number]?.status ==
              RunningDaysLookupStatus.confirmed &&
          runningDaysAnswers[service.train.number]!.operatesOnWeekday(
            date.weekday,
          ))
        service,
  ];

  @override
  Widget build(BuildContext context) {
    final hasDirect = result.direct.isNotEmpty;
    final hasConnecting = result.connecting.isNotEmpty;
    final runningOnDate = _runningOnDate;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        if (hasDirect) ...[
          if (runningOnDate.isNotEmpty) ...[
            SectionTitle(title: 'Running on ${DateFormatter.shortDate(date)}'),
            const SizedBox(height: AppSpacing.sm),
            for (final service in runningOnDate) ...[
              TrainResultCard(service: service, date: date),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
            const SectionTitle(title: 'All Direct Trains'),
          ] else
            const SectionTitle(title: 'Direct'),
          const SizedBox(height: AppSpacing.sm),
          for (final service in result.direct) ...[
            TrainResultCard(service: service, date: date),
            const SizedBox(height: AppSpacing.sm),
          ],
        ] else ...[
          Semantics(
            label: 'No direct trains found',
            child: const Text(
              'No direct trains found',
              style: AppTextStyles.bodyMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (hasConnecting)
            Semantics(
              label: 'Connections available',
              child: const Text(
                'Connections available',
                style: AppTextStyles.bodyMuted,
              ),
            ),
        ],
        if (hasConnecting) ...[
          if (hasDirect) const SizedBox(height: AppSpacing.md),
          const SectionTitle(title: '1 Change'),
          const SizedBox(height: AppSpacing.sm),
          for (final journey in result.connecting) ...[
            ConnectingJourneyCard(journey: journey, date: date),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.from, required this.to, required this.date});

  final Station from;
  final Station to;
  final DateTime date;

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
              label:
                  '${from.name} to ${to.name}, ${DateFormatter.shortDate(date)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          from.code,
                          style: AppTextStyles.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          to.code,
                          style: AppTextStyles.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateFormatter.shortDate(date),
                    style: AppTextStyles.bodyMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
