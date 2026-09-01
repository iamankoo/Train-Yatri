import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';

/// Decorative banner beneath the brand header.
///
/// The reference mainpage design shows a full illustrated train-on-a-
/// bridge scene here. That illustration was not supplied as its own
/// asset (only the composed screenshot was), so rather than crop it out
/// of the reference screenshot and ship it as a fake "asset", this
/// renders the tagline and a train mark side by side on one line in the
/// brand palette. A proper illustration can drop in later without
/// touching any layout code around it.
///
/// Deliberately narrower than the full content width (extra horizontal
/// margin on top of Home's own page padding) so it doesn't visually
/// compete with the full-width search card below it; the Row layout
/// (rather than the previous Stack of two corners) keeps the text and
/// train mark on one line and never lets the icon overlap the text -
/// the text gets the flexible space, the icon a fixed column.
class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brandNavy, AppColors.primary],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Track any train, anywhere in India',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textOnDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                Icons.train_rounded,
                size: 36,
                color: AppColors.textOnDark.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
