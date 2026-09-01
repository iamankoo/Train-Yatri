import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/date_formatter.dart';
import 'icon_chip.dart';

/// A real date-selection row backed by the platform date picker. Reused
/// wherever the app needs a journey/travel date (Home today; later,
/// PNR lookup date, ratings date, etc).
class DateField extends StatelessWidget {
  const DateField({
    required this.date,
    required this.onTap,
    super.key,
    this.label = 'Date of Journey',
  });

  final DateTime date;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = DateFormatter.shortDate(date);
    return Semantics(
      button: true,
      label: '$label. $formatted',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                const IconChip(icon: Icons.calendar_month_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTextStyles.label),
                      const SizedBox(height: 2),
                      Text(formatted, style: AppTextStyles.body),
                    ],
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
