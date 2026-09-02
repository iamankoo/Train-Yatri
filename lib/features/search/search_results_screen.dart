import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../domain/entities/station.dart';
import '../../domain/services/journey_discovery_service.dart';
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
/// fabricated. [date] is retained on the request (per the product's
/// date-aware-search requirement) but is not used to filter results.
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

  @override
  void initState() {
    super.initState();
    _future = _search();
  }

  Future<JourneyDiscoveryResult> _search() async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    return JourneyDiscoveryService.discover(
      repository: repository,
      fromStationId: widget.from.stationId,
      toStationId: widget.to.stationId,
    );
  }

  void _retry() => setState(() => _future = _search());

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
                  return _ResultsList(result: result);
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
  const _ResultsList({required this.result});

  final JourneyDiscoveryResult result;

  @override
  Widget build(BuildContext context) {
    final hasDirect = result.direct.isNotEmpty;
    final hasConnecting = result.connecting.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        if (hasDirect) ...[
          const SectionTitle(title: 'Direct'),
          const SizedBox(height: AppSpacing.sm),
          for (final service in result.direct) ...[
            TrainResultCard(service: service),
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
            ConnectingJourneyCard(journey: journey),
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
