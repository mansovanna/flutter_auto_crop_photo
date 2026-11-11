import 'package:flutter/material.dart';
import 'package:flutter_auto_crop/screens/guide_screen.dart';
import 'package:flutter_auto_crop/screens/guide_steps.dart';
import 'package:flutter_auto_crop/screens/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home shows all options and the steps', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('Open camera'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Step-by-step guide'), findsOneWidget);
    for (final step in guideSteps) {
      await tester.scrollUntilVisible(find.text(step.title), 100);
      expect(find.text(step.title), findsOneWidget);
    }
  });

  testWidgets('guide walks through every step', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.tap(find.text('Step-by-step guide'));
    await tester.pumpAndSettle();

    expect(find.byType(GuideScreen), findsOneWidget);
    for (var i = 0; i < guideSteps.length; i++) {
      expect(find.text('Step ${i + 1} of ${guideSteps.length}'), findsOneWidget);
      expect(find.text(guideSteps[i].title), findsOneWidget);
      if (i < guideSteps.length - 1) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }
    // Last page offers the camera instead of "Next".
    expect(find.text('Next'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Open camera'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step ${guideSteps.length - 1} of ${guideSteps.length}'), findsOneWidget);
  });
}
