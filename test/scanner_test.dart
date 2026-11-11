import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_auto_crop/services/doc_filters.dart';
import 'package:flutter_auto_crop/services/document_detector.dart';
import 'package:flutter_auto_crop/services/perspective.dart';
import 'package:flutter_auto_crop/services/quad.dart';
import 'package:flutter_auto_crop/services/scan_image.dart';
import 'package:flutter_auto_crop/services/scan_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _canvas(int w, int h, img.Color bg) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: bg);
  return image;
}

void _fillQuad(img.Image image, List<Offset> q, img.Color color) {
  img.fillPolygon(
    image,
    vertices: [for (final p in q) img.Point(p.dx, p.dy)],
    color: color,
  );
}

/// Every detected corner within [tolerance] px of the expected one.
Matcher _cornersNear(List<Offset> expected, double tolerance) => predicate<List<Offset>?>(
      (actual) {
        if (actual == null || actual.length != 4) return false;
        for (var i = 0; i < 4; i++) {
          if ((actual[i] - expected[i]).distance > tolerance) return false;
        }
        return true;
      },
      'corners within ${tolerance}px of $expected',
    );

double _meanLum(ScanImage s, {int x0 = 0, int y0 = 0, int? x1, int? y1}) {
  x1 ??= s.width;
  y1 ??= s.height;
  var sum = 0.0, n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * s.width + x) * 3;
      sum += (s.rgb[i] + s.rgb[i + 1] + s.rgb[i + 2]) / 3;
      n++;
    }
  }
  return sum / n;
}

void main() {
  group('DocumentDetector', () {
    test('finds a tilted white page on a dark table', () {
      final image = _canvas(1000, 800, img.ColorRgb8(45, 40, 38));
      const page = [Offset(260, 90), Offset(760, 150), Offset(700, 720), Offset(180, 640)];
      _fillQuad(image, page, img.ColorRgb8(245, 245, 240));
      // Some "text" on the page should not confuse detection.
      img.fillRect(image, x1: 320, y1: 250, x2: 600, y2: 270, color: img.ColorRgb8(30, 30, 30));
      img.fillRect(image, x1: 320, y1: 320, x2: 560, y2: 340, color: img.ColorRgb8(30, 30, 30));

      expect(DocumentDetector.detect(image), _cornersNear(page, 15));
    });

    test('finds a dark card on a light background', () {
      final image = _canvas(800, 600, img.ColorRgb8(235, 235, 230));
      const card = [Offset(200, 150), Offset(560, 150), Offset(560, 420), Offset(200, 420)];
      _fillQuad(image, card, img.ColorRgb8(40, 60, 90));

      expect(DocumentDetector.detect(image), _cornersNear(card, 12));
    });

    test('ignores a small object away from the page', () {
      final image = _canvas(1000, 800, img.ColorRgb8(50, 50, 50));
      const page = [Offset(150, 100), Offset(650, 100), Offset(650, 700), Offset(150, 700)];
      _fillQuad(image, page, img.ColorRgb8(240, 240, 240));
      img.fillCircle(image, x: 880, y: 650, radius: 25, color: img.ColorRgb8(200, 30, 30));

      expect(DocumentDetector.detect(image), _cornersNear(page, 15));
    });

    test('finds a white page on a light grey digital background', () {
      // Like an invoice mock-up: flat grey (230,232,233) around a white page,
      // a contrast too low for camera-photo thresholds.
      final image = _canvas(900, 900, img.ColorRgb8(230, 232, 233));
      const page = [Offset(160, 60), Offset(740, 60), Offset(740, 840), Offset(160, 840)];
      _fillQuad(image, page, img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 200, y1: 300, x2: 700, y2: 330, color: img.ColorRgb8(230, 100, 40));
      img.fillRect(image, x1: 200, y1: 760, x2: 400, y2: 800, color: img.ColorRgb8(230, 100, 40));

      expect(DocumentDetector.detect(image), _cornersNear(page, 12));
    });

    test('selects the full image for a digital page that fills the frame', () {
      // Like an invoice template / screenshot: white page edge to edge with a
      // table in the middle. The table must not be mistaken for the page.
      final image = _canvas(600, 800, img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 60, y1: 300, x2: 540, y2: 330, color: img.ColorRgb8(10, 40, 120));
      for (var y = 360; y <= 620; y += 40) {
        img.drawLine(image, x1: 60, y1: y, x2: 540, y2: y, color: img.ColorRgb8(200, 200, 200), thickness: 2);
      }
      img.drawLine(image, x1: 60, y1: 300, x2: 60, y2: 620, color: img.ColorRgb8(200, 200, 200), thickness: 2);
      img.drawLine(image, x1: 540, y1: 300, x2: 540, y2: 620, color: img.ColorRgb8(200, 200, 200), thickness: 2);
      img.fillRect(image, x1: 60, y1: 80, x2: 260, y2: 110, color: img.ColorRgb8(30, 30, 30)); // title

      expect(DocumentDetector.detect(image), isNull);
    });

    test('returns null for a featureless photo', () {
      final image = _canvas(400, 300, img.ColorRgb8(128, 128, 128));
      expect(DocumentDetector.detect(image), isNull);
    });
  });

  group('ScanImage.fromImage', () {
    // Regression: palette PNGs from the gallery crashed ("Could not process
    // photo") because palette indices were read as RGB bytes.
    /// Every pixel of [s] equals the decoded image's own colour.
    void expectSamePixels(ScanImage s, img.Image decoded) {
      expect(s.rgb.length, decoded.width * decoded.height * 3);
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          final i = (y * decoded.width + x) * 3;
          expect(
            [s.rgb[i], s.rgb[i + 1], s.rgb[i + 2]],
            [(p.rNormalized * 255).round(), (p.gNormalized * 255).round(), (p.bNormalized * 255).round()],
            reason: 'pixel ($x, $y)',
          );
        }
      }
    }

    test('expands palette (indexed) PNGs', () {
      final src = _canvas(60, 40, img.ColorRgb8(250, 250, 250));
      img.fillRect(src, x1: 10, y1: 10, x2: 29, y2: 29, color: img.ColorRgb8(30, 60, 200));
      img.fillRect(src, x1: 35, y1: 5, x2: 55, y2: 35, color: img.ColorRgb8(20, 20, 20));
      final decoded = img.decodePng(img.encodePng(img.quantize(src, numberOfColors: 8)))!;
      expect(decoded.hasPalette, isTrue);

      final s = ScanImage.fromImage(decoded);
      expectSamePixels(s, decoded);
      // The page is not uniform: palette entries really were looked up.
      expect(s.rgb.toSet().length, greaterThan(1));
    });

    test('handles grayscale and 16-bit images', () {
      final gray = img.Image(width: 30, height: 20, numChannels: 1);
      img.fill(gray, color: img.ColorUint8.rgb(90, 90, 90));
      expect(ScanImage.fromImage(gray).rgb.every((v) => v == 90), isTrue);

      final rgb8 = _canvas(30, 20, img.ColorRgb8(255, 255, 255));
      img.fillRect(rgb8, x1: 0, y1: 0, x2: 14, y2: 19, color: img.ColorRgb8(255, 0, 0));
      final deep = rgb8.convert(format: img.Format.uint16);
      expect(deep.format, img.Format.uint16);
      expectSamePixels(ScanImage.fromImage(deep), deep);
    });

    test('flattens transparency onto white', () {
      final rgba = img.Image(width: 30, height: 20, numChannels: 4);
      img.fill(rgba, color: img.ColorRgba8(0, 0, 0, 0)); // fully transparent
      img.fillRect(rgba, x1: 0, y1: 0, x2: 9, y2: 19, color: img.ColorRgba8(0, 0, 255, 255));
      final s = ScanImage.fromImage(rgba);
      expect([s.rgb[0], s.rgb[1], s.rgb[2]], [0, 0, 255]); // opaque blue kept
      final t = (10 * 30 + 20) * 3;
      expect([s.rgb[t], s.rgb[t + 1], s.rgb[t + 2]], [255, 255, 255]); // transparent -> white
    });

    test('a palette PNG goes through the whole pipeline', () {
      final src = _canvas(400, 300, img.ColorRgb8(40, 40, 40));
      _fillQuad(src, const [Offset(80, 50), Offset(320, 60), Offset(310, 250), Offset(70, 240)],
          img.ColorRgb8(245, 245, 245));
      final png = Uint8List.fromList(img.encodePng(img.quantize(src, numberOfColors: 8)));

      final a = ScanProcessor.analyze(png);
      expect(a.detected, isTrue);
      final flat = ScanProcessor.warp(a.image, a.corners);
      expect(ScanProcessor.render(flat, DocFilter.enhanced, 0), isNotEmpty);
    });
  });

  group('rotation', () {
    test('ScanImage.rotated moves pixels and swaps the size', () {
      final image = _canvas(4, 2, img.ColorRgb8(0, 0, 0));
      image.setPixelRgb(0, 0, 255, 0, 0); // red at top-left
      final src = ScanImage.fromImage(image);

      final cw = src.rotated(clockwise: true);
      expect([cw.width, cw.height], [2, 4]);
      expect(cw.rgb[(0 * 2 + 1) * 3], 255); // top-left -> top-right

      final ccw = src.rotated(clockwise: false);
      expect(ccw.rgb[(3 * 2 + 0) * 3], 255); // top-left -> bottom-left

      // Four turns give back the original.
      var r = src;
      for (var i = 0; i < 4; i++) {
        r = r.rotated(clockwise: true);
      }
      expect(r.rgb, src.rgb);
    });

    test('rotated corners still frame the same page', () {
      final image = _canvas(800, 600, img.ColorRgb8(40, 40, 40));
      const page = [Offset(150, 80), Offset(650, 120), Offset(620, 540), Offset(120, 500)];
      _fillQuad(image, page, img.ColorRgb8(245, 245, 245));
      final photo = Uint8List.fromList(img.encodeJpg(image));
      final a = ScanProcessor.analyze(photo);

      for (final clockwise in [true, false]) {
        final r = ScanProcessor.rotate(a, clockwise: clockwise);
        expect(Quad.isValid(r.corners), isTrue);
        // The flattened page has the same pixels whichever way it was turned.
        final straight = ScanProcessor.warp(a.image, a.corners);
        final turned = ScanProcessor.warp(r.image, r.corners);
        expect({turned.width, turned.height}, {straight.width, straight.height});
        expect(_meanLum(turned), closeTo(_meanLum(straight), 2));
      }
    });
  });

  group('Quad', () {
    test('orders corners clockwise from top-left', () {
      const shuffled = [Offset(10, 90), Offset(90, 10), Offset(5, 5), Offset(95, 95)];
      expect(Quad.order(shuffled), const [Offset(5, 5), Offset(90, 10), Offset(95, 95), Offset(10, 90)]);
    });

    test('rejects crossed corners', () {
      const ok = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];
      const crossed = [Offset(0, 0), Offset(100, 0), Offset(0, 100), Offset(100, 100)];
      expect(Quad.isValid(ok), isTrue);
      expect(Quad.isValid(crossed), isFalse);
    });
  });

  group('PerspectiveWarp', () {
    test('full-image corners return the same image', () {
      final image = _canvas(120, 80, img.ColorRgb8(0, 0, 0));
      img.fillRect(image, x1: 30, y1: 20, x2: 59, y2: 49, color: img.ColorRgb8(255, 255, 255));
      final src = ScanImage.fromImage(image);

      final out = PerspectiveWarp.warp(src, Quad.fullImage(const Size(120, 80)));

      expect(out.width, 120);
      expect(out.height, 80);
      expect(out.rgb, src.rgb);
    });

    test('flattens a tilted page into an upright rectangle', () {
      final image = _canvas(1000, 800, img.ColorRgb8(20, 20, 20));
      const page = [Offset(260, 90), Offset(760, 150), Offset(700, 720), Offset(180, 640)];
      _fillQuad(image, page, img.ColorRgb8(250, 250, 250));

      final out = PerspectiveWarp.warp(ScanImage.fromImage(image), page);

      // Size follows the longest opposite edges.
      final expectedW = math.max((page[1] - page[0]).distance, (page[2] - page[3]).distance);
      final expectedH = math.max((page[3] - page[0]).distance, (page[2] - page[1]).distance);
      expect(out.width, closeTo(expectedW, 1));
      expect(out.height, closeTo(expectedH, 1));
      // Only the page is left: (almost) entirely white, dark table gone.
      expect(_meanLum(out, x0: 3, y0: 3, x1: out.width - 3, y1: out.height - 3), greaterThan(245));
    });
  });

  group('DocFilters', () {
    // White paper with a strong shadow on the right half and a black text line
    // crossing both halves.
    ScanImage shadowedPage() {
      final image = _canvas(400, 300, img.ColorRgb8(235, 230, 220));
      for (var x = 200; x < 400; x++) {
        final shade = 235 - ((x - 200) * 0.5).round();
        img.drawLine(image, x1: x, y1: 0, x2: x, y2: 299, color: img.ColorRgb8(shade, shade - 5, shade - 15));
      }
      img.fillRect(image, x1: 40, y1: 140, x2: 360, y2: 146, color: img.ColorRgb8(25, 25, 25));
      return ScanImage.fromImage(image);
    }

    test('enhanced whitens paper in light and in shadow, keeps text dark', () {
      final out = DocFilters.apply(shadowedPage(), DocFilter.enhanced);
      expect(_meanLum(out, x0: 20, y0: 20, x1: 180, y1: 120), greaterThan(240));
      expect(_meanLum(out, x0: 220, y0: 20, x1: 380, y1: 120), greaterThan(235));
      expect(_meanLum(out, x0: 60, y0: 141, x1: 340, y1: 145), lessThan(80));
    });

    test('black & white produces only pure black and white', () {
      final out = DocFilters.apply(shadowedPage(), DocFilter.blackWhite);
      expect(out.rgb.every((v) => v == 0 || v == 255), isTrue);
      expect(_meanLum(out, x0: 220, y0: 20, x1: 380, y1: 120), 255);
      expect(_meanLum(out, x0: 60, y0: 141, x1: 340, y1: 145), 0);
    });

    test('every filter keeps the page size', () {
      final page = shadowedPage();
      for (final f in DocFilter.values) {
        final out = DocFilters.apply(page, f);
        expect([out.width, out.height], [page.width, page.height], reason: f.name);
      }
    });

    // A page with a red logo (~10% of the page width).
    ScanImage pageWithLogo() {
      final image = _canvas(800, 600, img.ColorRgb8(235, 235, 230));
      img.fillRect(image, x1: 360, y1: 260, x2: 440, y2: 320, color: img.ColorRgb8(200, 80, 70));
      return ScanImage.fromImage(image);
    }

    // Red minus blue at the centre of the logo: 0 means the colour is gone.
    double logoSpread(ScanImage s) {
      final i = (290 * s.width + 400) * 3;
      return (s.rgb[i] - s.rgb[i + 2]).toDouble();
    }

    test('enhanced keeps coloured areas coloured', () {
      expect(logoSpread(DocFilters.apply(pageWithLogo(), DocFilter.enhanced)), greaterThan(80));
    });

    test('magic color is more saturated than enhanced', () {
      final page = pageWithLogo();
      expect(
        logoSpread(DocFilters.apply(page, DocFilter.magicColor)),
        greaterThan(logoSpread(DocFilters.apply(page, DocFilter.enhanced))),
      );
    });

    test('lighten brightens without clipping white', () {
      final page = shadowedPage();
      final out = DocFilters.apply(page, DocFilter.lighten);
      expect(_meanLum(out), greaterThan(_meanLum(page)));
      expect(out.rgb.reduce(math.max), lessThanOrEqualTo(255));
    });

    test('sharpen increases contrast across an edge', () {
      final image = _canvas(100, 60, img.ColorRgb8(200, 200, 200));
      img.fillRect(image, x1: 50, y1: 0, x2: 99, y2: 59, color: img.ColorRgb8(60, 60, 60));
      final page = ScanImage.fromImage(image);
      final out = DocFilters.apply(page, DocFilter.sharpen);
      int at(ScanImage s, int x) => s.rgb[(30 * s.width + x) * 3];
      expect(at(out, 48) - at(out, 51), greaterThan(at(page, 48) - at(page, 51)));
      // Flat areas are unchanged.
      expect(at(out, 10), at(page, 10));
    });

    test('eco ink uses grey ink and white paper only', () {
      final out = DocFilters.apply(shadowedPage(), DocFilter.ecoInk);
      expect(out.rgb.every((v) => v == DocFilters.ecoInkLevel || v == 255), isTrue);
      expect(_meanLum(out, x0: 60, y0: 141, x1: 340, y1: 145), DocFilters.ecoInkLevel);
    });

    test('grayscale has equal channels', () {
      final out = DocFilters.apply(shadowedPage(), DocFilter.grayscale);
      for (var i = 0; i < out.rgb.length; i += 3) {
        expect(out.rgb[i], out.rgb[i + 1]);
        expect(out.rgb[i], out.rgb[i + 2]);
      }
    });
  });

  test('render rotates by quarter turns', () {
    final doc = ScanImage.fromImage(_canvas(300, 200, img.ColorRgb8(255, 255, 255)));
    final out = img.decodeJpg(ScanProcessor.render(doc, DocFilter.original, 1))!;
    expect(out.width, 200);
    expect(out.height, 300);
  });

  test('whole pipeline runs on background isolates (ScanJobs)', () async {
    // Regression: closures passed to Isolate.run from a State captured the
    // State and failed with "object is unsendable".
    final image = _canvas(800, 600, img.ColorRgb8(40, 40, 40));
    _fillQuad(image, const [Offset(150, 80), Offset(650, 120), Offset(620, 540), Offset(120, 500)],
        img.ColorRgb8(245, 245, 245));
    final photo = Uint8List.fromList(img.encodeJpg(image));

    final analysis = await ScanJobs.analyze(photo);
    expect(analysis.detected, isTrue);
    final rotated = await ScanJobs.rotate(analysis, clockwise: true);
    expect([rotated.image.width, rotated.image.height], [analysis.image.height, analysis.image.width]);
    final thumbs = await ScanJobs.thumbnails(rotated.preview);
    expect(thumbs.keys, DocFilter.values);
    expect(await ScanJobs.preview(rotated.preview, DocFilter.magicColor), isNotEmpty);
    final jpg = await ScanJobs.cropAndRender(rotated.image, rotated.corners, DocFilter.enhanced);
    final out = img.decodeJpg(jpg)!;
    // Page was ~500 wide x ~420 tall; after rotating it is taller than wide.
    expect(out.height, greaterThan(out.width));
  });
}
