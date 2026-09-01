import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/coming_soon.dart';
import '../../../shared/widgets/section_title.dart';

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// Compact quick-action tiles. Every action here is a real feature on
/// the product roadmap (live status, PNR, station search, booking) but
/// none of them are wired up yet in Block 1, so each shows honest
/// "coming soon" feedback instead of a dead tap or a fabricated result
/// screen.
class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({super.key});

  static const _actions = [
    _QuickAction('Live Status', Icons.train_rounded, AppColors.primary),
    _QuickAction(
      'PNR Status',
      Icons.confirmation_number_outlined,
      Color(0xFF16A34A),
    ),
    _QuickAction(
      'Station Search',
      Icons.location_searching_rounded,
      Color(0xFFD97706),
    ),
    _QuickAction('Book Tickets', Icons.event_seat_outlined, Color(0xFF9333EA)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Quick Actions'),
        const SizedBox(height: AppSpacing.md),
        // IntrinsicHeight + stretch: label text can wrap to one or two
        // lines depending on the action ("Station Search" vs. "Book
        // Tickets"), which would otherwise make tiles different
        // heights even though they're already equal-width (Expanded).
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in _actions) ...[
                Expanded(
                  child: _QuickActionTile(
                    action: action,
                    onTap: () => showComingSoon(context, action.label),
                  ),
                ),
                if (action != _actions.last)
                  const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.onTap});

  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: action.color, size: 26),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
