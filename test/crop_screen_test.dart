import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_auto_crop/screens/crop_screen.dart';
import 'package:flutter_auto_crop/services/doc_filters.dart';
import 'package:flutter_auto_crop/widgets/crop_editor.dart';
import 'package:flutter_auto_crop/widgets/filter_strip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _photo() {
  final image = img.Image(width: 800, height: 600);
  img.fill(image, color: img.ColorRgb8(40, 40, 40));
  img.fillPolygon(
    image,
    vertices: [img.Point(150, 80), img.Point(650, 120), img.Point(620, 540), img.Point(120, 500)],
    color: img.ColorRgb8(245, 245, 245),
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Lets real background isolates finish, then rebuilds.
Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  if (!done()) {
    // ignore: avoid_print
    print('TEXTS: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}');
  }
  expect(done(), isTrue, reason: 'background work did not finish');
}

void main() {
  testWidgets('one screen: corners, filters, rotate and save', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);

    final photo = _photo();
    // Isolates only make progress in real time, so start them inside runAsync.
    await tester.runAsync(() => tester.pumpWidget(MaterialApp(home: CropScreen(photoBytes: photo))));

    // Detection + thumbnails run on isolates.
    await _settle(tester, () => find.text('Original').evaluate().isNotEmpty);
    expect(find.textContaining('Document detected'), findsOneWidget);
    expect(find.byType(FilterStrip), findsOneWidget);
    for (final f in DocFilter.values) {
      await tester.scrollUntilVisible(find.text(f.label), 80,
          scrollable: find.descendant(of: find.byType(FilterStrip), matching: find.byType(Scrollable)));
      expect(find.text(f.label), findsOneWidget);
    }

    // Pick a filter.
    await tester.ensureVisible(find.text('B & W'));
    await tester.runAsync(() async {
      await tester.tap(find.text('B & W'));
      await tester.pump();
    });
    await _settle(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    // Rotate right: the photo turns from landscape to portrait and the
    // detected page corners turn with it.
    CropEditor editor() => tester.widget<CropEditor>(find.byType(CropEditor));
    expect(editor().imageSize, const Size(800, 600));
    final before = editor().corners;
    await tester.runAsync(() async {
      await tester.tap(find.text('Right'));
      await tester.pump();
    });
    await _settle(tester, () => editor().imageSize == const Size(600, 800));
    final after = editor().corners;
    // Page top-left (~150, 80) is now near the top-right: (600 - 80, 150).
    expect((after[1] - Offset(600 - before[0].dy, before[0].dx)).distance, lessThan(1));

    // Filter is kept and recomputed for the rotated photo (thumbnails too).
    await _settle(tester, () =>
        find.byType(CircularProgressIndicator).evaluate().isEmpty && find.text('Original').evaluate().isNotEmpty);
    await tester.scrollUntilVisible(find.text('B & W'), 80,
        scrollable: find.descendant(of: find.byType(FilterStrip), matching: find.byType(Scrollable)));
    expect(tester.widget<Text>(find.text('B & W')).style?.fontWeight, FontWeight.bold);

    // Save is on this screen (no separate enhance step) and enabled.
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(save, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.text('Next'), findsNothing);
  });
}
