import 'package:flutter/material.dart';

/// One step of the "how to use" guide. Shared by the home screen summary and
/// the full step-by-step guide so the two never disagree.
class GuideStep {
  const GuideStep({
    required this.icon,
    required this.title,
    required this.summary,
    required this.tips,
  });

  final IconData icon;
  final String title;
  final String summary;
  final List<String> tips;
}

const guideSteps = <GuideStep>[
  GuideStep(
    icon: Icons.crop_free,
    title: 'Place the document',
    summary: 'Put the page on a plain background that contrasts with it.',
    tips: [
      'A dark table under white paper (or the reverse) works best.',
      'Keep the whole subject inside the frame with a little space around it.',
      'Avoid busy patterns behind the subject.',
    ],
  ),
  GuideStep(
    icon: Icons.camera_alt,
    title: 'Take the photo',
    summary: 'Hold the phone steady and tap the shutter button.',
    tips: [
      'Hold the phone parallel to the subject to keep edges straight.',
      'Tap the flash icon in low light.',
      'Use the switch icon to change between front and back camera.',
      'Already have a photo? Tap the gallery icon (or "Choose from gallery" on the home screen).',
    ],
  ),
  GuideStep(
    icon: Icons.crop_rotate,
    title: 'Adjust the corners',
    summary: 'The app finds the 4 corners of the page. Fine-tune them if needed.',
    tips: [
      'Drag a corner dot to move it — a magnifier helps you place it exactly.',
      'Drag the bar in the middle of a side to move the whole side.',
      'Tap "Auto" to restore the detected corners, or "All" for the whole photo.',
    ],
  ),
  GuideStep(
    icon: Icons.auto_awesome,
    title: 'Enhance and save',
    summary: 'On the same screen: pick a filter, rotate if needed, then tap Save.',
    tips: [
      '"Enhanced" whitens the paper and removes shadows.',
      'Use "B & W" for crisp text documents.',
      'Tap "Left" or "Right" to turn the page the right way up.',
      'Save straightens the page, applies the filter and stores it in the "AutoCrop" album.',
    ],
  ),
];
