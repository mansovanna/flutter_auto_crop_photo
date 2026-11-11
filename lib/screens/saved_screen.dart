import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'camera_screen.dart';

/// Shows the saved scan, with shortcuts to scan again or go home.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Saved to gallery'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: Image.memory(bytes)),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    icon: const Icon(Icons.home),
                    label: const Text('Home'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    // Back to the camera if the scan came from it; a scan
                    // picked from the gallery on the home screen goes home.
                    onPressed: () => Navigator.of(context).popUntil(
                      (r) => r.settings.name == CameraScreen.routeName || r.isFirst,
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan another'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
