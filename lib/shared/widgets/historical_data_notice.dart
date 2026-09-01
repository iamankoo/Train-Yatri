import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// A compact, honest disclosure shown wherever the app presents data
/// derived from the static Dec-2017 timetable snapshot (see
/// `docs/RAILWAY_DATABASE.md`) - it must never be presented as a
/// current or live schedule, and this dataset has no operating-day
/// calendar at all.
class HistoricalDataNotice extends StatelessWidget {
  const HistoricalDataNotice({super.key});

  static const _message =
      'Schedule data is from Dec 2017. Operating days unavailable.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _message,
                style: AppTextStyles.label.copyWith(color: AppColors.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
