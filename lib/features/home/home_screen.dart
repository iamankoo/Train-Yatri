import 'package:flutter/material.dart';

import '../../shared/theme/app_spacing.dart';
import 'widgets/brand_header.dart';
import 'widgets/hero_banner.dart';
import 'widgets/home_bottom_nav_bar.dart';
import 'widgets/home_top_bar.dart';
import 'widgets/journey_search_card.dart';
import 'widgets/quick_actions_section.dart';
import 'widgets/recent_searches_section.dart';

/// Home screen foundation - real, interactive Flutter widgets laid out
/// to match the supplied `assets/mainpage.png` reference: brand header,
/// From/To/Date search card, quick actions, recent searches, bottom nav.
///
/// No railway data, search, or backend calls happen here yet; that is
/// intentionally out of scope for Block 1 (see AGENT/task notes -
/// Blocks 2-9 wire up the database, search, live status, ratings, PNR
/// and booking respectively).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: const [
            HomeTopBar(),
            SizedBox(height: AppSpacing.md),
            BrandHeader(),
            SizedBox(height: AppSpacing.lg),
            HeroBanner(),
            SizedBox(height: AppSpacing.lg),
            JourneySearchCard(),
            SizedBox(height: AppSpacing.xl),
            QuickActionsSection(),
            SizedBox(height: AppSpacing.xl),
            RecentSearchesSection(),
          ],
        ),
      ),
      bottomNavigationBar: const HomeBottomNavBar(),
    );
  }
}
