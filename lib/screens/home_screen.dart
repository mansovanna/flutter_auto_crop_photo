import 'package:flutter/material.dart';

import '../services/gallery_picker.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';
import 'guide_screen.dart';
import 'guide_steps.dart';

/// Start screen: open the camera, or read the step-by-step guide first.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openCamera(BuildContext context) {
    Navigator.of(context).push(CameraScreen.route());
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final bytes = await GalleryPicker.pick(context);
    if (bytes == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CropScreen(photoBytes: bytes)),
    );
  }

  void _openGuide(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GuideScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            Icon(Icons.crop, size: 56, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'Auto Crop',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Take a photo or pick one from your gallery — the app finds the page and crops it for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 28),

            // --- Options -----------------------------------------------------
            _OptionCard(
              icon: Icons.camera_alt,
              title: 'Open camera',
              subtitle: 'Take a photo and crop it automatically',
              highlighted: true,
              onTap: () => _openCamera(context),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.photo_library,
              title: 'Choose from gallery',
              subtitle: 'Crop a photo you already took',
              onTap: () => _pickFromGallery(context),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              icon: Icons.menu_book,
              title: 'Step-by-step guide',
              subtitle: 'Learn how to get the best crop',
              onTap: () => _openGuide(context),
            ),

            // --- Quick steps -------------------------------------------------
            const SizedBox(height: 32),
            Text('How it works', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var i = 0; i < guideSteps.length; i++)
              _StepTile(
                number: i + 1,
                step: guideSteps[i],
                isLast: i == guideSteps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = highlighted ? colors.primaryContainer : colors.surfaceContainerHigh;
    final fg = highlighted ? colors.onPrimaryContainer : colors.onSurface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: highlighted ? colors.primary : colors.secondaryContainer,
                foregroundColor: highlighted ? colors.onPrimary : colors.onSecondaryContainer,
                child: Icon(icon, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: fg.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.step, required this.isLast});

  final int number;
  final GuideStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Number + connecting line.
          Column(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                child: Text('$number', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: colors.outlineVariant),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    step.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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
