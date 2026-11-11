import 'dart:math' as math;
import 'dart:typed_data';

import 'scan_image.dart';

enum DocFilter {
  original('Original'),
  enhanced('Enhanced'),
  magicColor('Magic color'),
  lighten('Lighten'),
  sharpen('Sharpen'),
  grayscale('Grayscale'),
  blackWhite('B & W'),
  ecoInk('Eco ink');

  const DocFilter(this.label);
  final String label;
}

/// Scanner-style filters.
///
/// * Enhanced / Magic color / Grayscale / B & W / Eco ink first estimate the
///   paper brightness across the page (removing shadows and uneven light) and
///   divide it out, which turns the page white and keeps ink dark.
/// * Lighten brightens dark photos without changing colours much.
/// * Sharpen makes small text and fine lines crisper (unsharp mask).
abstract final class DocFilters {
  static ScanImage apply(ScanImage src, DocFilter filter) => switch (filter) {
    DocFilter.original => src,
    DocFilter.enhanced => _enhanced(src),
    DocFilter.magicColor => _saturate(_enhanced(src), 1.6),
    DocFilter.lighten => _lighten(src),
    DocFilter.sharpen => _sharpen(src, amount: 1.4),
    DocFilter.grayscale => _grayscale(src),
    DocFilter.blackWhite => _threshold(src, ink: 0),
    DocFilter.ecoInk => _threshold(src, ink: ecoInkLevel),
  };

  /// Grey used for "ink" by the Eco ink filter: readable, but prints with
  /// far less toner than solid black.
  static const ecoInkLevel = 110;

  static final Uint8List _lightenLut = () {
    final lut = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      lut[i] = (255 * math.pow(i / 255, 0.65)).round();
    }
    return lut;
  }();

  static ScanImage _lighten(ScanImage src) {
    final out = Uint8List(src.rgb.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = _lightenLut[src.rgb[i]];
    }
    return ScanImage(src.width, src.height, out);
  }

  /// Pushes each channel away from the pixel's grey level by [factor].
  static ScanImage _saturate(ScanImage src, double factor) {
    final rgb = src.rgb;
    final out = Uint8List(rgb.length);
    for (var i = 0; i < rgb.length; i += 3) {
      final r = rgb[i], g = rgb[i + 1], b = rgb[i + 2];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      out[i] = (l + (r - l) * factor).round().clamp(0, 255);
      out[i + 1] = (l + (g - l) * factor).round().clamp(0, 255);
      out[i + 2] = (l + (b - l) * factor).round().clamp(0, 255);
    }
    return ScanImage(src.width, src.height, out);
  }

  /// Unsharp mask: add back the difference between the image and a blur.
  static ScanImage _sharpen(ScanImage src, {required double amount}) {
    final w = src.width, h = src.height, rgb = src.rgb;
    final blurred = _boxBlurRgb(_boxBlurRgb(rgb, w, h), w, h);
    final out = Uint8List(rgb.length);
    for (var i = 0; i < rgb.length; i++) {
      out[i] = (rgb[i] + (rgb[i] - blurred[i]) * amount).round().clamp(0, 255);
    }
    return ScanImage(w, h, out);
  }

  static Uint8List _boxBlurRgb(Uint8List src, int w, int h) {
    final tmp = Uint8List(src.length);
    final out = Uint8List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final l = x > 0 ? x - 1 : x, r = x < w - 1 ? x + 1 : x;
        for (var c = 0; c < 3; c++) {
          tmp[(y * w + x) * 3 + c] =
              (src[(y * w + l) * 3 + c] +
                  src[(y * w + x) * 3 + c] +
                  src[(y * w + r) * 3 + c]) ~/
              3;
        }
      }
    }
    for (var y = 0; y < h; y++) {
      final t = y > 0 ? y - 1 : y, b = y < h - 1 ? y + 1 : y;
      for (var x = 0; x < w; x++) {
        for (var c = 0; c < 3; c++) {
          out[(y * w + x) * 3 + c] =
              (tmp[(t * w + x) * 3 + c] +
                  tmp[(y * w + x) * 3 + c] +
                  tmp[(b * w + x) * 3 + c]) ~/
              3;
        }
      }
    }
    return out;
  }

  // Ratio -> output value. Ratio 1 (paper) maps to white; ink gets darker.
  static final Uint8List _toneLut = () {
    final lut = Uint8List(1024);
    for (var i = 0; i < 1024; i++) {
      final ratio = i / 1023 * 1.25;
      lut[i] = (255 * math.pow(math.min(1.0, ratio * 1.08), 1.5)).round();
    }
    return lut;
  }();

  static int _tone(double value, double background) {
    final ratio = value / (background < 1 ? 1 : background);
    final idx = (ratio / 1.25 * 1023).round();
    return _toneLut[idx > 1023 ? 1023 : idx];
  }

  static ScanImage _enhanced(ScanImage src) {
    final w = src.width, h = src.height, rgb = src.rgb;
    final bg = [
      for (var c = 0; c < 3; c++)
        _BackgroundMap(rgb, w, h, channels: 3, channel: c),
    ];
    final out = Uint8List(rgb.length);
    for (var y = 0; y < h; y++) {
      for (var c = 0; c < 3; c++) {
        bg[c].prepareRow(y);
      }
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        for (var c = 0; c < 3; c++) {
          out[i + c] = _tone(rgb[i + c].toDouble(), bg[c].at(x));
        }
      }
    }
    return ScanImage(w, h, out);
  }

  static ScanImage _grayscale(ScanImage src) {
    final w = src.width, h = src.height;
    final lum = _luminance(src);
    final bg = _BackgroundMap(lum, w, h, channels: 1, channel: 0);
    final out = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      bg.prepareRow(y);
      for (var x = 0; x < w; x++) {
        final v = _tone(lum[y * w + x].toDouble(), bg.at(x));
        final i = (y * w + x) * 3;
        out[i] = v;
        out[i + 1] = v;
        out[i + 2] = v;
      }
    }
    return ScanImage(w, h, out);
  }

  /// Two-level output: ink becomes [ink], paper becomes white.
  static ScanImage _threshold(ScanImage src, {required int ink}) {
    final w = src.width, h = src.height;
    final lum = _luminance(src);
    final bg = _BackgroundMap(lum, w, h, channels: 1, channel: 0);
    final out = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      bg.prepareRow(y);
      for (var x = 0; x < w; x++) {
        final v = lum[y * w + x] < bg.at(x) * 0.8 ? ink : 255;
        final i = (y * w + x) * 3;
        out[i] = v;
        out[i + 1] = v;
        out[i + 2] = v;
      }
    }
    return ScanImage(w, h, out);
  }

  static Uint8List _luminance(ScanImage src) {
    final n = src.width * src.height;
    final lum = Uint8List(n);
    final rgb = src.rgb;
    for (var i = 0; i < n; i++) {
      lum[i] =
          (rgb[i * 3] * 77 + rgb[i * 3 + 1] * 150 + rgb[i * 3 + 2] * 29) >> 8;
    }
    return lum;
  }
}

/// Smooth estimate of paper brightness for one channel: a coarse grid where
/// each cell holds the mean of its brighter pixels (so ink is ignored),
/// blurred, then bilinearly interpolated per pixel.
class _BackgroundMap {
  _BackgroundMap(
    Uint8List data,
    this.w,
    this.h, {
    required int channels,
    required int channel,
  }) {
    block = math.max(4, (math.max(w, h) / 24).ceil());
    gw = (w / block).ceil();
    gh = (h / block).ceil();
    var grid = Float32List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final x0 = gx * block, y0 = gy * block;
        final x1 = math.min(w, x0 + block), y1 = math.min(h, y0 + block);
        var sum = 0, count = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            sum += data[(y * w + x) * channels + channel];
            count++;
          }
        }
        final mean = sum / count;
        var bSum = 0, bCount = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            final v = data[(y * w + x) * channels + channel];
            if (v >= mean) {
              bSum += v;
              bCount++;
            }
          }
        }
        grid[gy * gw + gx] = bCount == 0 ? mean : bSum / bCount;
      }
    }
    // Take the brightest nearby cell so coloured blocks (logos, highlights,
    // headers) up to a few cells wide are not mistaken for paper and
    // washed out. Shadows vary slowly, so they survive this.
    grid = _blur(_blur(_maxNearby(grid, 2)));
    _grid = grid;

    _x0 = Int32List(w);
    _x1 = Int32List(w);
    _ax = Float32List(w);
    for (var x = 0; x < w; x++) {
      final f = ((x + 0.5) / block - 0.5).clamp(0.0, gw - 1.0);
      _x0[x] = f.floor();
      _x1[x] = math.min(gw - 1, _x0[x] + 1);
      _ax[x] = f - _x0[x];
    }
    _row = Float32List(gw);
  }

  final int w, h;
  late final int block, gw, gh;
  late final Float32List _grid;
  late final Int32List _x0, _x1;
  late final Float32List _ax;
  late final Float32List _row;

  /// Interpolates the grid vertically for row [y]; call before [at].
  void prepareRow(int y) {
    final f = ((y + 0.5) / block - 0.5).clamp(0.0, gh - 1.0);
    final y0 = f.floor();
    final y1 = math.min(gh - 1, y0 + 1);
    final ay = f - y0;
    for (var gx = 0; gx < gw; gx++) {
      final a = _grid[y0 * gw + gx], b = _grid[y1 * gw + gx];
      _row[gx] = a + (b - a) * ay;
    }
  }

  double at(int x) {
    final a = _row[_x0[x]], b = _row[_x1[x]];
    return a + (b - a) * _ax[x];
  }

  Float32List _maxNearby(Float32List g, int radius) {
    final out = Float32List(g.length);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var m = 0.0;
        for (
          var yy = math.max(0, y - radius);
          yy <= math.min(gh - 1, y + radius);
          yy++
        ) {
          for (
            var xx = math.max(0, x - radius);
            xx <= math.min(gw - 1, x + radius);
            xx++
          ) {
            final v = g[yy * gw + xx];
            if (v > m) m = v;
          }
        }
        out[y * gw + x] = m;
      }
    }
    return out;
  }

  Float32List _blur(Float32List g) {
    final out = Float32List(g.length);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var s = 0.0, c = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final yy = y + dy, xx = x + dx;
            if (yy < 0 || yy >= gh || xx < 0 || xx >= gw) continue;
            s += g[yy * gw + xx];
            c++;
          }
        }
        out[y * gw + x] = s / c;
      }
    }
    return out;
  }
}
