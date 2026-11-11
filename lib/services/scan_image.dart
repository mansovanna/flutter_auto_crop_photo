import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Plain 8-bit RGB pixel buffer. Cheap to send between isolates and fast to
/// index in tight loops (unlike `img.Image.getPixel`).
class ScanImage {
  ScanImage(this.width, this.height, this.rgb)
      : assert(rgb.length == width * height * 3);

  /// Accepts any decoded image: palette (indexed) PNGs, grayscale, 16-bit,
  /// and images with transparency (flattened onto white, like paper).
  factory ScanImage.fromImage(img.Image image) {
    final w = image.width, h = image.height;

    // Fast path: plain 8-bit RGB. A palette image also reports 3 channels,
    // but its pixel data are palette indices, so it must be expanded.
    if (!image.hasPalette && image.format == img.Format.uint8 && image.numChannels == 3) {
      return ScanImage(w, h, Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb)));
    }

    // Everything else: expand to 8-bit RGBA (keeping real transparency;
    // images without alpha come out opaque), then composite over white.
    final rgba = image
        .convert(format: img.Format.uint8, numChannels: 4)
        .getBytes(order: img.ChannelOrder.rgba);
    final rgb = Uint8List(w * h * 3);
    for (var i = 0, o = 0; o < rgb.length; i += 4, o += 3) {
      final a = rgba[i + 3];
      if (a == 255) {
        rgb[o] = rgba[i];
        rgb[o + 1] = rgba[i + 1];
        rgb[o + 2] = rgba[i + 2];
      } else {
        final inv = 255 - a;
        rgb[o] = (rgba[i] * a + 255 * inv) ~/ 255;
        rgb[o + 1] = (rgba[i + 1] * a + 255 * inv) ~/ 255;
        rgb[o + 2] = (rgba[i + 2] * a + 255 * inv) ~/ 255;
      }
    }
    return ScanImage(w, h, rgb);
  }

  final int width;
  final int height;
  final Uint8List rgb;

  img.Image toImage() => img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgb.buffer,
        bytesOffset: rgb.offsetInBytes,
        numChannels: 3,
        order: img.ChannelOrder.rgb,
      );

  /// Returns a copy rotated by 90° ([clockwise] or counter-clockwise).
  ScanImage rotated({required bool clockwise}) {
    final nw = height, nh = width;
    final out = Uint8List(rgb.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final nx = clockwise ? height - 1 - y : y;
        final ny = clockwise ? x : width - 1 - x;
        final s = (y * width + x) * 3, d = (ny * nw + nx) * 3;
        out[d] = rgb[s];
        out[d + 1] = rgb[s + 1];
        out[d + 2] = rgb[s + 2];
      }
    }
    return ScanImage(nw, nh, out);
  }

  /// Returns a copy whose longest side is at most [maxSide].
  ScanImage downscale(int maxSide) {
    final longest = width > height ? width : height;
    if (longest <= maxSide) return this;
    final s = maxSide / longest;
    return ScanImage.fromImage(img.copyResize(
      toImage(),
      width: (width * s).round().clamp(1, maxSide),
      height: (height * s).round().clamp(1, maxSide),
      interpolation: img.Interpolation.average,
    ));
  }

  Uint8List encodeJpg({int quality = 90}) =>
      Uint8List.fromList(img.encodeJpg(toImage(), quality: quality));
}
