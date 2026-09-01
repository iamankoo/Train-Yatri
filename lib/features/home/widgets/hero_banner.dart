import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';

/// Decorative banner beneath the brand header.
///
/// The reference mainpage design shows a full illustrated train-on-a-
/// bridge scene here. That illustration was not supplied as its own
/// asset (only the composed screenshot was), so rather than crop it out
/// of the reference screenshot and ship it as a fake "asset", this
/// renders a simple track/skyline motif from real widgets in the brand
/// palette. A proper illustration can drop in later without touching
/// any layout code around it.
class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandNavy, AppColors.primary],
          ),
        ),
        child: Stack(
          children: [
            // A large Material glyph scaled way up (as a faint background
            // decoration) renders with visibly hard, blocky edges instead
            // of a soft pattern, so the banner intentionally stays to the
            // gradient + a normal-sized icon rather than that effect.
            Positioned(
              right: AppSpacing.lg,
              top: AppSpacing.lg,
              child: Icon(
                Icons.train_rounded,
                size: 56,
                color: AppColors.textOnDark,
              ),
            ),
            const Positioned(
              left: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: Text(
                'Track any train, anywhere in India',
                style: TextStyle(
                  color: AppColors.textOnDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
