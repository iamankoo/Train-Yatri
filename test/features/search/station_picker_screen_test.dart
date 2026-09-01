import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:train_yatri/features/search/station_picker_screen.dart';

import '../../test_support/fake_railway_repository.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [fakeRailwayRepositoryOverride()],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows a neutral prompt before anything is typed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const StationPickerScreen(fieldLabel: 'From')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Type a station name or code to search'), findsOneWidget);
  });

  testWidgets('shows the field label so the user knows which field this is', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const StationPickerScreen(fieldLabel: 'To')));
    await tester.pumpAndSettle();

    expect(find.textContaining('To'), findsWidgets);
  });

  testWidgets('shows an honest empty state for a query matching nothing real', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const StationPickerScreen(fieldLabel: 'From')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzznotarealstation');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('No matching stations found'), findsOneWidget);
  });

  testWidgets('clearing the query back to empty returns to the prompt state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const StationPickerScreen(fieldLabel: 'From')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'NDA');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('New Delta Alpha'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Type a station name or code to search'), findsOneWidget);
  });

  testWidgets('the back button returns without a selection', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<Object?>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const StationPickerScreen(fieldLabel: 'From'),
                    ),
                  );
                  // Surface the result so the test can assert on it.
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('result:$result')));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.textContaining('result:null'), findsOneWidget);
  });
}
