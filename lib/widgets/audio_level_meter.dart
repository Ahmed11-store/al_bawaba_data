import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Real-time 0–100% audio volume gauge, driven by
/// [InspectionProvider.audioLevel]. Rendered as a row of bars that
/// light up left-to-right, cheap to rebuild every audio frame.
class AudioLevelMeter extends StatelessWidget {
  const AudioLevelMeter({super.key, required this.level, this.barCount = 24});

  /// Normalized 0.0–1.0 level.
  final double level;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    final activeBars = (level.clamp(0.0, 1.0) * barCount).round();

    return Row(
      children: List.generate(barCount, (i) {
        final active = i < activeBars;
        final heightFactor = 0.3 + (i / barCount) * 0.7;
        Color color;
        if (!active) {
          color = AppColors.cardBorder;
        } else if (i / barCount < 0.6) {
          color = AppColors.success;
        } else if (i / barCount < 0.85) {
          color = const Color(0xFFFFC107);
        } else {
          color = AppColors.danger;
        }

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: 28 * heightFactor,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}
