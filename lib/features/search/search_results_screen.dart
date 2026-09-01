import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/railway_providers.dart';
import '../../domain/entities/direct_service.dart';
import '../../domain/entities/station.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/utils/date_formatter.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/historical_data_notice.dart';
import '../../shared/widgets/loading_state.dart';
import 'widgets/train_result_card.dart';

/// The first real Search Results screen: direct (single-train, no
/// change of train) services between [from] and [to] on [date],
/// queried straight from the offline SQLite database via
/// `RailwayRepository.findDirectServices`. [date] is retained on the
/// request (per the product's date-aware-search requirement) but is
/// not used to filter results - the dataset has no operating-day
/// calendar to filter by (see [HistoricalDataNotice]).
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
  late Future<List<DirectService>> _future;

  @override
  void initState() {
    super.initState();
    _future = _search();
  }

  Future<List<DirectService>> _search() async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    return repository.findDirectServices(
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
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: HistoricalDataNotice(),
            ),
            Expanded(
              child: FutureBuilder<List<DirectService>>(
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
                  final results = snapshot.data ?? const [];
                  if (results.isEmpty) {
                    return const EmptyState(
                      icon: Icons.train_outlined,
                      message: 'No direct trains found',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    itemCount: results.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) =>
                        TrainResultCard(service: results[index]),
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
