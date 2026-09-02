import 'package:flutter/material.dart';

import '../../../domain/entities/live_train_status.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';

/// A compact operational-change alert (diverted/cancelled/rescheduled)
/// - Block 6 Part 27: shown as a clear, compact notice, never raw
/// provider JSON, and never buried below the fold.
class LiveExceptionBanner extends StatelessWidget {
  const LiveExceptionBanner({required this.exception, super.key});

  final LiveException exception;

  String get _label => switch (exception.type) {
    LiveExceptionType.diverted => 'Diverted',
    LiveExceptionType.cancelled => 'Cancelled',
    LiveExceptionType.rescheduled => 'Rescheduled',
    LiveExceptionType.unknown => 'Notice',
  };

  @override
  Widget build(BuildContext context) {
    final message = exception.message;
    return Semantics(
      label: message == null ? _label : '$_label: $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _label,
                    style: AppTextStyles.title.copyWith(color: AppColors.error),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(message, style: AppTextStyles.bodyMuted),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
