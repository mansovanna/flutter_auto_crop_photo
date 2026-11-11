import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'guide_steps.dart';

/// Swipeable step-by-step guide. The last page leads straight to the camera.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _pageController = PageController();
  int _page = 0;

  bool get _isLast => _page == guideSteps.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _openCamera() {
    Navigator.of(context).pushReplacement(CameraScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${_page + 1} of ${guideSteps.length}'),
        actions: [
          if (!_isLast)
            TextButton(onPressed: _openCamera, child: const Text('Skip')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar across all steps.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (var i = 0; i < guideSteps.length; i++)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _page ? colors.primary : colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: guideSteps.length,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, i) => _GuidePage(number: i + 1, step: guideSteps[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  if (_page > 0)
                    OutlinedButton.icon(
                      onPressed: () => _goTo(_page - 1),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isLast ? _openCamera : () => _goTo(_page + 1),
                    icon: Icon(_isLast ? Icons.camera_alt : Icons.arrow_forward),
                    label: Text(_isLast ? 'Open camera' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.number, required this.step});

  final int number;
  final GuideStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 56, color: colors.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Step $number',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(color: colors.primary),
        ),
        const SizedBox(height: 4),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          step.summary,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tips', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final tip in step.tips)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle, size: 18, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tip)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
