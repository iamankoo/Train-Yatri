import 'package:flutter/material.dart';

/// Train Yatri brand palette.
///
/// Values are sampled directly from the supplied brand assets
/// (assets/icon.png, assets/splashscreen.png, assets/mainpage.png) rather
/// than picked arbitrarily, so the in-app theme stays visually consistent
/// with the source artwork.
abstract final class AppColors {
  /// Vivid CTA / accent blue - buttons, links, active states.
  /// Sampled from the "Yatri" wordmark and search-button accents.
  static const Color primary = Color(0xFF0053FC);

  /// Deep brand navy - the icon's background square.
  static const Color brandNavy = Color(0xFF103D7D);

  /// Splash screen background gradient (top -> bottom), sampled from
  /// assets/splashscreen.png.
  static const Color splashGradientTop = Color(0xFF002E7B);
  static const Color splashGradientBottom = Color(0xFF011336);

  /// App background - light blue-white, sampled from assets/mainpage.png.
  static const Color background = Color(0xFFEEF4FE);

  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textOnDark = Color(0xFFFFFFFF);

  static const Color divider = Color(0xFFE7ECF6);
  static const Color iconChipBackground = Color(0xFFE3ECFC);

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  /// A genuine, distinct yellow - used only for a future train
  /// stoppage in the Live Status route timeline (Block 6). Distinct
  /// from [warning] (an amber/orange already used for unrelated "+1
  /// day" badges) so the two don't read as the same signal.
  static const Color amber = Color(0xFFEAB308);
}
