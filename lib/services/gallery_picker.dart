import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the user pick an existing photo from the gallery.
abstract final class GalleryPicker {
  static final _picker = ImagePicker();

  /// Returns the photo's bytes, or null if the user cancelled or picking
  /// failed (a snackbar explains failures).
  ///
  /// Very large photos are scaled down on the device to at most
  /// [maxDimension] px, which keeps detection and filters fast while
  /// leaving plenty of resolution for documents.
  static Future<Uint8List?> pick(BuildContext context, {double maxDimension = 3000}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (file == null) return null; // cancelled
      return await file.readAsBytes();
    } on PlatformException catch (e) {
      final String message;
      if (e.code.contains('access_denied')) {
        message = 'Photo access is required. Enable it in system settings.';
      } else if (e.code == 'channel-error') {
        // The plugin's native side is missing from the installed build,
        // typically after adding the plugin and only hot-restarting.
        message = 'Gallery is not available in this build. '
            'Stop the app and run it again (a hot restart is not enough).';
      } else {
        message = 'Could not open the photo: ${e.message ?? e.code}';
      }
      messenger?.showSnackBar(SnackBar(content: Text(message)));
      return null;
    }
  }
}
