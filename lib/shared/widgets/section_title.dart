import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A section heading with an optional trailing action ("View All"),
/// reused by every list-style section on Home (and later on other
/// screens with the same "heading + action" pattern).
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    super.key,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.heading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onActionTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                actionLabel!,
                style: AppTextStyles.title.copyWith(color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }
}
