import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_text_styles.dart';

/// "Designed by Aniket" + logo + "Train Yatri" wordmark + tagline block,
/// reproducing the reference mainpage design with real text/image
/// widgets (not a screenshot).
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Designed by', style: AppTextStyles.bodyMuted),
            Text(
              'Aniket',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.asset(
            'assets/icon.png',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  style: AppTextStyles.brandWordmark,
                  children: [
                    TextSpan(text: 'Train '),
                    TextSpan(
                      text: 'Yatri',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const Text(
                'Your journey. Our track.',
                style: AppTextStyles.tagline,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
