import 'package:flutter/material.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/utils/coming_soon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/section_title.dart';

/// Recent-searches list.
///
/// Search history isn't persisted anywhere yet (that lands with the
/// local database/repository layer in Block 2), so this shows a
/// genuine [EmptyState] instead of a fabricated entry - once real
/// searches are saved, this becomes a list of recent-search cards using
/// the same section shell.
class RecentSearchesSection extends StatelessWidget {
  const RecentSearchesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Recently Searched',
          actionLabel: 'View All',
          onActionTap: () => showComingSoon(context, 'Search history'),
        ),
        const SizedBox(height: AppSpacing.md),
        const EmptyState(
          icon: Icons.history_rounded,
          message: 'No recent searches yet',
        ),
      ],
    );
  }
}
