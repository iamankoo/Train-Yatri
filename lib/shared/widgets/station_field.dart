import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'icon_chip.dart';

/// A tappable From/To station row. Block 3 will connect [onTap] to a
/// real station picker backed by the offline SQLite dataset and start
/// passing a selected station name through [value]; this widget's shape
/// (icon + label + value, min 48dp tall touch target) stays the same.
class StationField extends StatelessWidget {
  const StationField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
    this.isPlaceholder = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label. $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                IconChip(icon: icon),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTextStyles.label),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: isPlaceholder
                            ? AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                              )
                            : AppTextStyles.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
