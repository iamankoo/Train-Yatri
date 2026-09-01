import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'core/routing/app_routes.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: TrainYatriApp()));
}

class TrainYatriApp extends StatelessWidget {
  const TrainYatriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Train Yatri',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
