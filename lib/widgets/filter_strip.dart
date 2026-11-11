import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/doc_filters.dart';
import '../services/scan_image.dart';
import '../services/scan_processor.dart';

/// Filter state shared by the crop and enhance screens: thumbnails for the
/// strip, plus a screen-sized preview per filter computed on first use and
/// cached. All heavy work runs on background isolates via [ScanJobs].
class FilterPreviews extends ChangeNotifier {
  FilterPreviews({DocFilter initial = DocFilter.original}) : _selected = initial;

  ScanImage? _base;
  Map<DocFilter, Uint8List>? _thumbnails;
  final Map<DocFilter, Uint8List> _cache = {};
  Uint8List? _lastShown;
  DocFilter _selected;
  bool _userSelected = false;
  bool _disposed = false;
  Object? error;

  DocFilter get selected => _selected;

  /// True once the user tapped a filter (vs. the initial default).
  bool get userSelected => _userSelected;

  Map<DocFilter, Uint8List>? get thumbnails => _thumbnails;

  /// Preview to display: the selected filter if ready, else the last one
  /// that was shown (so the image never blanks while a filter computes).
  Uint8List? get shown => _cache[_selected] ?? _lastShown;

  bool get isComputingSelected => !_cache.containsKey(_selected);

  /// Bumped on every [load]; results computed for an older base are dropped.
  int _generation = 0;

  /// Starts (or restarts, e.g. after a rotation) on a new [base], keeping
  /// the selected filter. [base] should be screen-sized (see
  /// [ScanProcessor.previewBase]). [originalJpeg], when given, is [base]
  /// already encoded: it is shown immediately and used for "Original".
  Future<void> load(ScanImage base, {Uint8List? originalJpeg}) async {
    final gen = ++_generation;
    _base = base;
    _cache.clear();
    _thumbnails = null;
    if (originalJpeg != null) {
      _cache[DocFilter.original] = originalJpeg;
      _lastShown = originalJpeg;
    }
    _notify();
    try {
      await Future.wait([
        ScanJobs.thumbnails(base).then((t) {
          if (gen != _generation) return;
          _thumbnails = t;
          _notify();
        }),
        _ensure(_selected),
      ]);
    } catch (e) {
      if (gen != _generation) return;
      error = e;
      _notify();
    }
  }

  void select(DocFilter filter) {
    if (_cache[_selected] != null) _lastShown = _cache[_selected];
    _selected = filter;
    _userSelected = true;
    _notify();
    _ensure(filter).catchError((Object e) {
      error = e;
      _notify();
    });
  }

  Future<void> _ensure(DocFilter filter) async {
    final base = _base;
    if (base == null || _cache.containsKey(filter)) return;
    final gen = _generation;
    final jpg = await ScanJobs.preview(base, filter);
    if (gen != _generation) return; // photo was rotated meanwhile
    _cache[filter] = jpg;
    if (filter == _selected) _lastShown = jpg;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Horizontal strip of filter thumbnails.
class FilterStrip extends StatelessWidget {
  const FilterStrip({super.key, required this.previews, this.height = 108});

  final FilterPreviews previews;
  final double height;

  @override
  Widget build(BuildContext context) {
    final thumbs = previews.thumbnails;
    return SizedBox(
      height: height,
      child: thumbs == null
          ? const Center(child: LinearProgressIndicator())
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in DocFilter.values)
                  _FilterThumb(
                    label: f.label,
                    bytes: thumbs[f]!,
                    selected: f == previews.selected,
                    onTap: () => previews.select(f),
                  ),
              ],
            ),
    );
  }
}

class _FilterThumb extends StatelessWidget {
  const _FilterThumb({
    required this.label,
    required this.bytes,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Uint8List bytes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? color : Colors.white24, width: selected ? 3 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(bytes, fit: BoxFit.cover, cacheHeight: 200, gaplessPlayback: true),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? color : Colors.white70,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
