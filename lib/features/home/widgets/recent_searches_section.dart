import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/railway_providers.dart';
import '../../../data/providers/recent_searches_providers.dart';
import '../../../domain/entities/recent_search.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/coming_soon.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_state.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/train_yatri_card.dart';
import '../../search/journey_search_state.dart';
import '../../search/search_results_screen.dart';

/// Recent-searches list.
///
/// Backed by [recentSearchesProvider] (on-device only, see
/// `RecentSearchesRepository`) - shows a genuine [EmptyState] until the
/// user has actually run a search, never a fabricated example entry.
/// Tapping a real entry re-resolves its stations from the current
/// database (by code, not a possibly-stale row id) and runs a fresh
/// search - it never claims the old result is still valid.
class RecentSearchesSection extends ConsumerWidget {
  const RecentSearchesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSearches = ref.watch(recentSearchesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Recently Searched',
          actionLabel: 'View All',
          onActionTap: () => showComingSoon(context, 'Search history'),
        ),
        const SizedBox(height: AppSpacing.md),
        recentSearches.when(
          loading: () => const LoadingState(),
          error: (_, _) => const EmptyState(
            icon: Icons.history_rounded,
            message: 'No recent searches yet',
          ),
          data: (searches) {
            if (searches.isEmpty) {
              return const EmptyState(
                icon: Icons.history_rounded,
                message: 'No recent searches yet',
              );
            }
            final shown = searches.take(3).toList();
            return Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  _RecentSearchCard(search: shown[i]),
                  if (i != shown.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecentSearchCard extends ConsumerWidget {
  const _RecentSearchCard({required this.search});

  final RecentSearch search;

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final repository = await ref.read(railwayRepositoryProvider.future);
    final from = await repository.getStationByCode(search.fromCode);
    final to = await repository.getStationByCode(search.toCode);
    if (from == null || to == null) {
      if (context.mounted) {
        showComingSoon(
          context,
          'This route',
          'no longer available in the current database',
        );
      }
      return;
    }
    ref
        .read(journeySearchControllerProvider.notifier)
        .restore(from: from, to: to, date: search.date);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SearchResultsScreen(from: from, to: to, date: search.date),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label:
          '${search.fromName} to ${search.toName}, ${DateFormatter.shortDate(search.date)}',
      child: TrainYatriCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: InkWell(
          onTap: () => _restore(context, ref),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.iconChipBackground,
                child: Icon(
                  Icons.history_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${search.fromCode} → ${search.toCode}',
                      style: AppTextStyles.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormatter.shortDate(search.date),
                      style: AppTextStyles.bodyMuted,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
