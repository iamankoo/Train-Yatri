import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/shared/theme/app_colors.dart';
import 'package:train_yatri/shared/theme/app_theme.dart';

void main() {
  group('AppTheme.light', () {
    test('uses the brand colors sampled from the supplied assets', () {
      final theme = AppTheme.light;

      expect(theme.colorScheme.primary, AppColors.primary);
      expect(theme.scaffoldBackgroundColor, AppColors.background);
    });

    test('gives buttons a full-width, large touch target by default', () {
      final theme = AppTheme.light;
      final buttonStyle = theme.elevatedButtonTheme.style!;

      final minSize = buttonStyle.minimumSize?.resolve({});
      expect(minSize, isNotNull);
      expect(minSize!.height, greaterThanOrEqualTo(48));
    });
  });
}
